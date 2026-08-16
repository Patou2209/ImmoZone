const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const https = require('https');

admin.initializeApp();
const db = admin.firestore();

// ═══════════════════════════════════════════════════════════════════════════════
// ORANGE MONEY B2B API — Configuration
// ═══════════════════════════════════════════════════════════════════════════════
// Ces valeurs seront fournies par Orange lors de la réunion technique.
// En attendant, elles sont en mode SIMULATION (sandbox).
const ORANGE_CONFIG = {
  // À récupérer sur https://developer.orange.com/ après souscription
  baseUrl: 'api.orange.com',           // URL de base Orange API (à confirmer pour DRC)
  basicAuth: '',                        // Authorization: Basic XXXX (fourni par Orange)
  contractId: '',                       // contractId (fourni lors de la signature)
  posId: '',                            // Point of Sale ID (fourni par Orange)
  currency: 'USD',                     // DRC — à ajuster si Orange confirme autre devise
  sandboxMode: true,                    // ← passer à false lors du go-live

  // ⚠️ URL de callback: Orange appellera cette URL après confirmation USSD du client
  // C'est cette URL qu'on doit communiquer à Orange lors de la réunion.
  // Doc B2B: le callbackURL est configuré UNE FOIS lors du provisioning
  // (champ "callbackURL" + "authorization" du partner profile), PAS dans chaque requête.
  callbackUrl: 'https://us-central1-immozone-d9a68.cloudfunctions.net/orangeMoneyWebhook',

  // 🔒 Sécurité callback (doc: partnerCallbackAuthorization)
  // Valeur "Basic XXXX" que NOUS avons définie (générée le 10/08/2026) et qu'il faut
  // COMMUNIQUER À ORANGE lors du provisioning (champ "authorization" du partner profile).
  // Orange renverra ce header Authorization dans chaque notification → le webhook le vérifie.
  // Correspond à: immozone-callback:e3agfy8PCKJAjXunbGno0RO48n4dSr
  // ⚠️ En sandbox on laisse la vérification désactivée (voir sandboxMode ci-dessous) ;
  // elle s'active automatiquement au go-live puisque la valeur est non-vide.
  partnerCallbackAuthorization: 'Basic aW1tb3pvbmUtY2FsbGJhY2s6ZTNhZ2Z5OFBDS0pBalh1bmJHbm8wUk80OG40ZFNy',

  // Endpoints B2B (doc: /services → /forms/cashin → /transactions/cashin)
  // ⚠️ Les préfixes exacts seront confirmés par Orange lors de la réunion technique.
  servicesPath: '/orange-money-b2b/v1/services',
  formsPath: '/orange-money-b2b/v1/forms/cashin',   // retourne le x-omr-forms-token
  cashinPath: '/orange-money-b2b/v1/transactions/cashin',
  cashoutPath: '/orange-money-b2b/v1/transactions/cashout',
  statusPath: '/orange-money-b2b/v1/transactions',   // GET /transactions/{transactionId} (ID PARTENAIRE)
};

// Cache du x-omr-forms-token (valide 24h = 86400 secondes)
let _omrToken = null;
let _omrTokenExpiry = 0;

// ─── Helper: appel HTTPS vers Orange API ───────────────────────────────────────
async function orangeApiCall({ method, path, body, extraHeaders = {} }) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : '';
    const options = {
      hostname: ORANGE_CONFIG.baseUrl,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${ORANGE_CONFIG.basicAuth}`,
        'Accept': 'application/json',
        ...extraHeaders,
      },
    };
    if (bodyStr) options.headers['Content-Length'] = Buffer.byteLength(bodyStr);

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

// ─── Récupérer ou renouveler le x-omr-forms-token (cache 24h) ─────────────────
async function getOmrToken() {
  const now = Date.now();
  // Si token valide en mémoire, le retourner
  if (_omrToken && now < _omrTokenExpiry) return _omrToken;

  // Vérifier dans Firestore (survit aux redémarrages de fonction)
  const configRef = db.collection('config').doc('orange_money_token');
  const configDoc = await configRef.get();
  if (configDoc.exists) {
    const { token, expiry } = configDoc.data();
    if (token && expiry && now < expiry) {
      _omrToken = token;
      _omrTokenExpiry = expiry;
      return token;
    }
  }

  // En mode sandbox: retourner un token fictif pour les tests
  if (ORANGE_CONFIG.sandboxMode) {
    console.log('[Orange] SANDBOX MODE — token simulé');
    _omrToken = 'SANDBOX_TOKEN_' + Date.now();
    _omrTokenExpiry = now + 86400000; // 24h
    return _omrToken;
  }

  // Appel réel: GET /forms pour obtenir le token
  const resp = await orangeApiCall({
    method: 'GET',
    path: ORANGE_CONFIG.formsPath,
  });

  if (resp.status !== 200 || !resp.body?.token?.value) {
    throw new Error(`Orange /forms failed: ${resp.status} — ${JSON.stringify(resp.body)}`);
  }

  const token = resp.body.token.value;
  const expiresInMs = (parseInt(resp.body.token.expiresIn) || 86400) * 1000;
  const expiry = now + expiresInMs - 60000; // -1min de marge

  // Persister dans Firestore
  await configRef.set({ token, expiry, updatedAt: new Date().toISOString() });
  _omrToken = token;
  _omrTokenExpiry = expiry;
  return token;
}

// ─── Créditer l'utilisateur dans Firestore après paiement confirmé ────────────
async function creditUserAfterPayment(paymentId) {
  const payDoc = await db.collection('payments').doc(paymentId).get();
  if (!payDoc.exists) {
    console.warn(`[creditUser] Payment ${paymentId} not found`);
    return;
  }
  const payment = payDoc.data();
  if (payment.status !== 'confirmed') return; // déjà traité

  const creditsQty = payment.creditsQty || 0;
  if (creditsQty <= 0) {
    console.warn(`[creditUser] Payment ${paymentId} has no creditsQty`);
    return;
  }

  const creditId = `credit_${paymentId}`;
  const creditRef = db.collection('credits').doc(creditId);
  const existing = await creditRef.get();
  if (existing.exists) {
    console.log(`[creditUser] Credit ${creditId} already exists, skipping`);
    return; // idempotent
  }

  await creditRef.set({
    id: creditId,
    userId: payment.userId,
    total: creditsQty,
    remaining: creditsQty,
    source: 'paiement_orange_money',
    sourceLabel: 'Orange Money',
    orderId: payment.orderId,
    createdAt: new Date().toISOString(),
    expiresAt: null,
  });

  console.log(`[creditUser] ✅ ${creditsQty} crédits attribués à ${payment.userId}`);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 1: initiateOrangePayment
// Appelée par l'app Flutter quand le client clique "Payer avec Orange Money"
// URL: https://us-central1-immozone-d9a68.cloudfunctions.net/initiateOrangePayment
// ═══════════════════════════════════════════════════════════════════════════════
exports.initiateOrangePayment = onRequest(
  { region: 'us-central1', cors: true },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    try {
      const { paymentId, phoneNumber, amount, currency, creditsQty, userId, productType, orderId } = req.body;

      // Validation basique
      if (!paymentId || !phoneNumber || !amount || !userId) {
        res.status(400).json({ error: 'Paramètres manquants: paymentId, phoneNumber, amount, userId requis' });
        return;
      }

      console.log(`[initiateOrangePayment] paymentId=${paymentId} msisdn=${phoneNumber} amount=${amount}`);

      // ── MODE SANDBOX ──────────────────────────────────────────────────────────
      if (ORANGE_CONFIG.sandboxMode) {
        console.log('[initiateOrangePayment] SANDBOX — simulation PENDING');

        // Mettre à jour le doc Firestore avec le statut pending
        await db.collection('payments').doc(paymentId).update({
          status: 'pending',
          operator: 'orange_money',
          omTransactionId: `SANDBOX_${Date.now()}`,
          omInitiatedAt: new Date().toISOString(),
        });

        res.status(200).json({
          success: true,
          transactionStatus: 'PENDING',
          transactionId: paymentId,
          omTransactionId: `SANDBOX_OM_${Date.now()}`,
          message: 'SANDBOX: Confirmez via USSD sur votre téléphone',
          sandboxMode: true,
        });
        return;
      }

      // ── MODE PRODUCTION ───────────────────────────────────────────────────────
      // 1. Obtenir le token OMR
      const omrToken = await getOmrToken();

      // 2. Normaliser le numéro (s'assurer du format msisdn)
      const msisdn = phoneNumber.replace(/\s/g, '').replace(/^\+/, '');

      // 3. Appel Cashin Orange API
      // ⚠️ NOTE: callbackUrl N'est PAS dans le body — il est configuré UNE SEULE FOIS
      // lors du provisioning sur le portail Orange Developer (pas dans chaque requête)
      // Body EXACT selon la doc B2B (6 champs, PAS de contractId ici — il appartient
      // au provisioning du profil partenaire, pas aux transactions) :
      const cashinBody = {
        peerId: msisdn,
        peerIdType: 'msisdn',
        amount: parseFloat(amount),
        currency: currency || ORANGE_CONFIG.currency,
        posId: ORANGE_CONFIG.posId,
        transactionId: paymentId,   // Notre ID unique (max 36 car.) — Orange le renvoie dans la notification
      };

      const omResp = await orangeApiCall({
        method: 'POST',
        path: ORANGE_CONFIG.cashinPath,
        body: cashinBody,
        extraHeaders: { 'x-omr-forms-token': omrToken },
      });

      console.log(`[initiateOrangePayment] Orange response: ${omResp.status}`, omResp.body);

      if (omResp.status === 201 || omResp.status === 200) {
        // Doc B2B — réponse: { transactionId, status, peerId, ..., reference }
        // "reference" = ID interne Orange (ex: MP211208.1349.A00129)
        const respBody = omResp.body || {};
        const transactionStatus = respBody.status || respBody.transactionStatus || 'PENDING';
        const omReference = respBody.reference || respBody.omTransactionId || '';

        // Cas nominal doc: le cashin peut répondre SUCCESS de façon synchrone
        if (transactionStatus === 'SUCCESS' || transactionStatus === 'SUCCESSFUL') {
          await db.collection('payments').doc(paymentId).update({
            status: 'confirmed',
            confirmedAt: new Date().toISOString(),
            isConfirmed: true,
            operator: 'orange_money',
            omTransactionId: omReference,
            omTxnId: omReference,
            omFinalStatus: 'SUCCESSFUL',
            omInitiatedAt: new Date().toISOString(),
          });
          await creditUserAfterPayment(paymentId);

          res.status(200).json({
            success: true,
            transactionStatus: 'SUCCESSFUL',
            transactionId: paymentId,
            omTransactionId: omReference,
            message: 'Paiement confirmé',
          });
          return;
        }

        // Sinon: PENDING → attendre confirmation USSD + notification callback
        await db.collection('payments').doc(paymentId).update({
          status: 'pending',
          operator: 'orange_money',
          omTransactionId: omReference,
          omInitiatedAt: new Date().toISOString(),
        });

        res.status(200).json({
          success: true,
          transactionStatus: 'PENDING',
          transactionId: paymentId,
          omTransactionId: omReference,
          message: 'Veuillez confirmer le paiement sur votre téléphone via USSD',
        });
      } else {
        // Erreur Orange
        const errorMsg = omResp.body?.message || `Erreur Orange: ${omResp.status}`;
        console.error('[initiateOrangePayment] Orange error:', omResp.body);

        await db.collection('payments').doc(paymentId).update({
          status: 'failed',
          failureReason: errorMsg,
          failedAt: new Date().toISOString(),
        });

        res.status(200).json({
          success: false,
          transactionStatus: 'FAILED',
          error: errorMsg,
        });
      }

    } catch (err) {
      console.error('[initiateOrangePayment] Exception:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 2: orangeMoneyWebhook
// Appelée par Orange après confirmation USSD du client
// ⚠️ DOIT répondre HTTP 200 en moins de 5 secondes
// URL: https://us-central1-immozone-d9a68.cloudfunctions.net/orangeMoneyWebhook
// ← C'est cette URL à donner à Orange comme callbackURL
// ═══════════════════════════════════════════════════════════════════════════════
exports.orangeMoneyWebhook = onRequest(
  { region: 'us-central1', cors: false },
  async (req, res) => {
    // 🔒 Vérification du header Authorization envoyé par Orange
    // (doc: partnerCallbackAuthorization défini lors du provisioning).
    // Désactivée en sandbox (tests manuels sans header possible) ;
    // active automatiquement dès que sandboxMode = false au go-live.
    if (!ORANGE_CONFIG.sandboxMode && ORANGE_CONFIG.partnerCallbackAuthorization) {
      const authHeader = req.headers['authorization'] || '';
      if (authHeader !== ORANGE_CONFIG.partnerCallbackAuthorization) {
        console.warn('[orangeWebhook] ⛔ Authorization header invalide — notification rejetée');
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }
    }

    // Répondre 200 immédiatement pour éviter le timeout Orange (< 5s obligatoire)
    res.status(200).json({ received: true });

    try {
      // Orange peut envoyer le payload sous différents formats selon la version API
      // On accepte tous les noms possibles pour l'ID de transaction
      const body = req.body || {};

      // Log brut du payload pour diagnostic lors des premiers tests
      console.log('[orangeWebhook] RAW payload:', JSON.stringify(body));

      // Format officiel doc B2B (section "Transaction notification") :
      // { "transactionId": "53186253-...", "status": "SUCCESS", "peerId": "770000000",
      //   "peerIdType": "msisdn", "amount": 100, "currency": "XOF",
      //   "reference": "MP211208.1349.A00129" }
      // On accepte aussi les variantes d'autres versions d'API (SUCCESSFUL, externalTxnId, txnid).

      const transactionStatus = body.status || body.transactionStatus;  // "SUCCESS" / "FAILED"
      const transactionType   = body.type;                              // "CASHIN" / "CASHOUT" (optionnel)

      // transactionId = NOTRE ID envoyé dans cashinBody (champ officiel doc)
      const transactionId =
        body.transactionId ||      // ← champ officiel doc B2B (notre ID)
        body.externalTxnId ||      // variante autres versions API
        body.orderId;

      // reference = ID interne Orange Money (ex: MP211208.1349.A00129)
      const omTransactionId =
        body.reference ||          // ← champ officiel doc B2B
        body.txnid ||              // variante autres versions API
        body.omTransactionId;

      const peerId          = body.peerId;
      const amount          = body.amount;
      const currency        = body.currency;
      const failureReason   = body.failureReason || body.errorDescription || body.message || '';

      console.log(`[orangeWebhook] externalTxnId=${transactionId} status=${transactionStatus} type=${transactionType} txnid=${omTransactionId}`);

      if (!transactionId) {
        console.warn('[orangeWebhook] No externalTxnId/transactionId in payload — dumping full body:', JSON.stringify(body));
        return;
      }

      const payRef = db.collection('payments').doc(transactionId);
      const payDoc = await payRef.get();

      if (!payDoc.exists) {
        console.warn(`[orangeWebhook] Payment ${transactionId} not found in Firestore`);
        return;
      }

      const payment = payDoc.data();

      // Éviter le double-traitement
      if (payment.status === 'confirmed' || payment.status === 'failed') {
        console.log(`[orangeWebhook] Payment ${transactionId} already processed (${payment.status})`);
        return;
      }

      if (transactionStatus === 'SUCCESS' || transactionStatus === 'SUCCESSFUL') {
        // ── SUCCÈS ────────────────────────────────────────────────────────────
        await payRef.update({
          status: 'confirmed',
          confirmedAt: new Date().toISOString(),
          isConfirmed: true,
          omTxnId: omTransactionId || '',        // reference Orange ex: MP211208.1349.A00129
          omPeerId: peerId || '',                // numéro msisdn du client
          omAmount: amount || 0,                 // montant confirmé par Orange
          omCurrency: currency || '',            // devise confirmée par Orange
          omFinalStatus: 'SUCCESSFUL',
        });

        // Créditer l'utilisateur
        await creditUserAfterPayment(transactionId);

        // Notification push (optionnel — si FCM configuré)
        try {
          const userDoc = await db.collection('users').doc(payment.userId).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            const fcmToken = userData.fcmToken;
            if (fcmToken) {
              await admin.messaging().send({
                token: fcmToken,
                notification: {
                  title: '✅ Paiement confirmé — ImmoZone',
                  body: `${payment.creditsQty} crédit(s) ajouté(s) à votre compte`,
                },
                data: { paymentId: transactionId, status: 'confirmed' },
              });
            }
          }
        } catch (notifErr) {
          console.warn('[orangeWebhook] FCM notification failed:', notifErr.message);
        }

        console.log(`[orangeWebhook] ✅ Payment ${transactionId} CONFIRMED — ${payment.creditsQty} crédits attribués`);

      } else if (transactionStatus === 'FAILED' || transactionStatus === 'FAILURE' || transactionStatus === 'CANCELLED' || transactionStatus === 'EXPIRED' || transactionStatus === 'REJECTED') {
        // ── ÉCHEC ─────────────────────────────────────────────────────────────
        await payRef.update({
          status: 'failed',
          failedAt: new Date().toISOString(),
          omFinalStatus: transactionStatus,
          failureReason: failureReason || `Orange: ${transactionStatus}`,
        });

        // Notification push échec
        try {
          const userDoc = await db.collection('users').doc(payment.userId).get();
          if (userDoc.exists) {
            const fcmToken = userDoc.data().fcmToken;
            if (fcmToken) {
              await admin.messaging().send({
                token: fcmToken,
                notification: {
                  title: '❌ Paiement échoué — ImmoZone',
                  body: 'Votre paiement Orange Money n\'a pas abouti. Réessayez.',
                },
                data: { paymentId: transactionId, status: 'failed' },
              });
            }
          }
        } catch (notifErr) {
          console.warn('[orangeWebhook] FCM failed notification error:', notifErr.message);
        }

        console.log(`[orangeWebhook] ❌ Payment ${transactionId} FAILED`);
      } else {
        console.log(`[orangeWebhook] Status inconnu: ${transactionStatus} — ignoré`);
      }

    } catch (err) {
      // Ne jamais crasher — Orange attend HTTP 200
      console.error('[orangeWebhook] Exception (after 200 sent):', err);
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 3: checkOrangePaymentStatus
// Polling manuel du statut (fallback si callback non reçu)
// Appelée par Flutter toutes les 10s pendant l'attente USSD
// URL: https://us-central1-immozone-d9a68.cloudfunctions.net/checkOrangePaymentStatus
// ═══════════════════════════════════════════════════════════════════════════════
exports.checkOrangePaymentStatus = onRequest(
  { region: 'us-central1', cors: true },
  async (req, res) => {
    const { paymentId } = req.query;

    if (!paymentId) {
      res.status(400).json({ error: 'paymentId requis' });
      return;
    }

    try {
      // 1. Vérifier d'abord dans Firestore (le webhook a peut-être déjà mis à jour)
      const payDoc = await db.collection('payments').doc(paymentId).get();
      if (!payDoc.exists) {
        res.status(404).json({ error: 'Payment not found' });
        return;
      }

      const payment = payDoc.data();

      // Si déjà traité par le webhook → retourner directement
      if (payment.status === 'confirmed') {
        res.status(200).json({ transactionStatus: 'SUCCESSFUL', source: 'firestore' });
        return;
      }
      if (payment.status === 'failed') {
        res.status(200).json({ transactionStatus: 'FAILED', source: 'firestore' });
        return;
      }

      // 2. En mode sandbox → simuler selon un paramètre de test
      if (ORANGE_CONFIG.sandboxMode) {
        res.status(200).json({ transactionStatus: 'PENDING', source: 'sandbox' });
        return;
      }

      // 3. En production → interroger Orange API
      // Doc B2B: GET /transactions/{transactionId} où {transactionId} est
      // l'ID de la transaction CÔTÉ PARTENAIRE (= notre paymentId), pas l'ID Orange.
      const omrToken = await getOmrToken();

      const statusResp = await orangeApiCall({
        method: 'GET',
        path: `${ORANGE_CONFIG.statusPath}/${encodeURIComponent(paymentId)}`,
        extraHeaders: { 'x-omr-forms-token': omrToken },
      });

      // Normaliser le statut Orange (SUCCESS → SUCCESSFUL) pour l'app Flutter
      const rawStatus = statusResp.body?.status || statusResp.body?.transactionStatus || 'PENDING';
      let omStatus = 'PENDING';
      if (rawStatus === 'SUCCESS' || rawStatus === 'SUCCESSFUL') omStatus = 'SUCCESSFUL';
      else if (['FAILED', 'FAILURE', 'CANCELLED', 'EXPIRED', 'REJECTED'].includes(rawStatus)) omStatus = 'FAILED';

      // Si Orange confirme le succès mais que le webhook n'est pas encore passé → créditer
      if (omStatus === 'SUCCESSFUL' && payment.status !== 'confirmed') {
        await db.collection('payments').doc(paymentId).update({
          status: 'confirmed',
          confirmedAt: new Date().toISOString(),
          isConfirmed: true,
          omTxnId: statusResp.body?.reference || payment.omTransactionId || '',
          omFinalStatus: 'SUCCESSFUL',
        });
        await creditUserAfterPayment(paymentId);
      } else if (omStatus === 'FAILED' && payment.status !== 'failed') {
        await db.collection('payments').doc(paymentId).update({
          status: 'failed',
          failedAt: new Date().toISOString(),
          omFinalStatus: rawStatus,
          failureReason: `Orange: ${rawStatus}`,
        });
      }

      res.status(200).json({ transactionStatus: omStatus, source: 'orange_api' });

    } catch (err) {
      console.error('[checkOrangePaymentStatus] Error:', err);
      res.status(500).json({ error: err.message });
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION PLANIFIÉE: expireProperties
// S'exécute toutes les heures. Passe status 'Actif' → 'Expire' pour toute
// annonce dont expiresAt est dépassé, et notifie l'annonceur.
// C'est LA source de vérité serveur du cycle de vie des annonces (30 jours) :
// même si le client n'ouvre jamais l'app, l'annonce expire quand même.
// ═══════════════════════════════════════════════════════════════════════════════
exports.expireProperties = onSchedule(
  { schedule: 'every 60 minutes', region: 'us-central1', timeZone: 'Africa/Kinshasa' },
  async () => {
    const now = new Date();
    const nowIso = now.toISOString();

    try {
      // Les dates sont stockées en chaînes ISO-8601 → comparaison lexicale valide
      const snap = await db.collection('properties')
        .where('status', '==', 'Actif')
        .get();

      let expiredCount = 0;
      const batch = db.batch();
      const notifications = [];

      snap.forEach((doc) => {
        const data = doc.data();
        const expiresAt = data.expiresAt; // chaîne ISO ou null

        // ── Cas 1: annonce active SANS date d'expiration (donnée legacy) ──
        // On la répare : expiresAt = createdAt + 30 jours (ou now + 30 j si pas de createdAt)
        if (!expiresAt) {
          const created = data.createdAt ? new Date(data.createdAt) : now;
          const repaired = new Date(created.getTime() + 30 * 24 * 3600 * 1000);
          if (repaired <= now) {
            // Déjà au-delà des 30 jours depuis création → expirer immédiatement
            batch.update(doc.ref, {
              status: 'Expire',
              expiresAt: repaired.toISOString(),
              updatedAt: nowIso,
            });
            expiredCount++;
            notifications.push({ doc, data });
          } else {
            // Encore dans la fenêtre → juste réparer la date manquante
            batch.update(doc.ref, { expiresAt: repaired.toISOString() });
          }
          return;
        }

        // ── Cas 2: date d'expiration dépassée → expirer ──
        if (expiresAt <= nowIso) {
          batch.update(doc.ref, {
            status: 'Expire',
            updatedAt: nowIso,
          });
          expiredCount++;
          notifications.push({ doc, data });
        }
      });

      if (expiredCount > 0 || notifications.length > 0) {
        await batch.commit();
      }

      // Notifications in-app aux annonceurs (hors batch — non bloquant)
      for (const { doc, data } of notifications) {
        try {
          if (!data.ownerId) continue;
          const notifId = `notif_exp_${doc.id}_${Date.now()}`;
          await db.collection('notifications').doc(notifId).set({
            id: notifId,
            userId: data.ownerId,
            type: 'info',
            title: 'Annonce expirée',
            body: `Votre annonce "${data.title || ''}" a expiré après sa période de validité. ` +
                  `Vous pouvez la renouveler depuis votre profil pour la republier.`,
            propertyId: doc.id,
            propertyTitle: data.title || '',
            isRead: false,
            createdAt: nowIso,
          });

          // Notification push FCM (si token disponible)
          const userDoc = await db.collection('users').doc(data.ownerId).get();
          const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
          if (fcmToken) {
            await admin.messaging().send({
              token: fcmToken,
              notification: {
                title: '⏰ Annonce expirée — ImmoZone',
                body: `"${data.title || 'Votre annonce'}" a expiré. Renouvelez-la depuis votre profil.`,
              },
              data: { propertyId: doc.id, type: 'expired' },
            });
          }
        } catch (notifErr) {
          console.warn(`[expireProperties] Notification failed for ${doc.id}:`, notifErr.message);
        }
      }

      console.log(`[expireProperties] ✅ Scan terminé — ${expiredCount} annonce(s) expirée(s) sur ${snap.size} active(s)`);
    } catch (err) {
      console.error('[expireProperties] Exception:', err);
    }
  }
);

const APP_NAME = 'ImmoZone';
const BASE_URL = 'https://www.immozone.pro';
const DEFAULT_IMG = `${BASE_URL}/icons/Icon-512.png`;
const DEFAULT_DESC = 'La plateforme immobilière de référence en RDC & Congo-Brazzaville. Achetez, vendez ou louez en quelques clics.';

/**
 * propertyPreview — Cloud Function HTTPS
 * Intercepte /property/:id AVANT que Firebase Hosting serve index.html.
 * Lit les données de l'annonce dans Firestore et retourne un HTML
 * avec les vraies meta OG (titre, description, photo) pour WhatsApp/Facebook.
 * Flutter démarre ensuite normalement via le script flutter_bootstrap.js intégré.
 */
exports.propertyPreview = onRequest(async (req, res) => {
  try {
    // Extraire l'ID de l'annonce depuis le path /property/:id
    const match = req.path.match(/^\/property\/([^/]+)$/);
    if (!match) {
      res.status(404).send('Not found');
      return;
    }

    const propertyId = match[1];
    const ref = 'IZ' + propertyId.slice(-4).toUpperCase();

    // Lire l'annonce dans Firestore
    let title = `Annonce ${ref} — ${APP_NAME}`;
    let description = DEFAULT_DESC;
    let imageUrl = DEFAULT_IMG;
    let propertyUrl = `${BASE_URL}/property/${propertyId}`;

    try {
      const doc = await db.collection('properties').doc(propertyId).get();
      if (doc.exists) {
        const data = doc.data();
        const propTitle = data.title || '';
        const city = data.city || '';
        const price = data.price ? `${Number(data.price).toLocaleString('fr-FR')} USD` : '';
        const transType = data.transaction_type || data.transactionType || '';

        // Titre enrichi
        title = `${propTitle} — Réf. ${ref} | ${APP_NAME}`;

        // Description enrichie
        description = `${transType ? transType + ' · ' : ''}${city}${price ? ' · ' + price : ''} — Découvrez cette annonce sur ImmoZone et contactez l'annonceur directement.`;

        // Photo principale de l'annonce
        const images = data.images || data.imageUrls || [];
        if (Array.isArray(images) && images.length > 0) {
          imageUrl = images[0];
        } else if (data.main_image || data.mainImage) {
          imageUrl = data.main_image || data.mainImage;
        }
      }
    } catch (firestoreErr) {
      // Firestore inaccessible → on continue avec les valeurs par défaut
      console.warn('Firestore read failed:', firestoreErr.message);
    }

    // Générer le HTML avec meta OG + bootstrap Flutter
    const html = `<!DOCTYPE html>
<html lang="fr">
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">

  <!-- Open Graph (WhatsApp, Facebook, Telegram) -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="${APP_NAME}">
  <meta property="og:title" content="${escHtml(title)}">
  <meta property="og:description" content="${escHtml(description)}">
  <meta property="og:image" content="${escHtml(imageUrl)}">
  <meta property="og:image:width" content="800">
  <meta property="og:image:height" content="600">
  <meta property="og:url" content="${escHtml(propertyUrl)}">

  <!-- Twitter Card -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escHtml(title)}">
  <meta name="twitter:description" content="${escHtml(description)}">
  <meta name="twitter:image" content="${escHtml(imageUrl)}">

  <!-- SEO -->
  <meta name="description" content="${escHtml(description)}">

  <!-- App -->
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="${APP_NAME}">
  <link rel="apple-touch-icon" href="/icons/Icon-192.png">
  <link rel="icon" type="image/png" href="/favicon.png">
  <title>${escHtml(title)}</title>
  <link rel="manifest" href="/manifest.json">
</head>
<body>
  <script src="/flutter_bootstrap.js" async></script>
</body>
</html>`;

    res.set('Cache-Control', 'public, max-age=300'); // 5 min cache
    res.set('Content-Type', 'text/html; charset=utf-8');
    res.status(200).send(html);

  } catch (err) {
    console.error('propertyPreview error:', err);
    // En cas d'erreur, rediriger vers index.html pour que Flutter gère
    res.redirect(302, '/');
  }
});

/** Échappe les caractères HTML spéciaux dans les attributs */
function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
