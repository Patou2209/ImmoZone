const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const https = require('https');

admin.initializeApp();
const db = admin.firestore();

// ═══════════════════════════════════════════════════════════════════════════════
// ORANGE MONEY BUSINESS API (Partner) — Configuration
// Doc officielle: Base path https://api.orange.com/om_partner_api/v1
// Auth: OAuth2 client_credentials → Bearer token (1h) via POST /oauth/v3/token
// Service utilisé: DEBIT (Merchant Payment) — POST /{country}/debit
// ═══════════════════════════════════════════════════════════════════════════════
const ORANGE_CONFIG = {
  apiHost: 'api.orange.com',

  // ── Bascule sandbox/production ─────────────────────────────────────────────
  // sandboxMode=true  → pays 'sx', devise 'OUV', montants ENTIERS uniquement
  // sandboxMode=false → pays 'cd' (RDC), devise 'USD'
  sandboxMode: true,                    // ← passer à false au go-live production

  sandbox: {
    country: 'sx',
    currency: 'OUV',
    integerAmountsOnly: true,           // sandbox: pas de décimales
    // MSISDN de test auto-accepté (PIN 1357) — doc section 8
    testMsisdn: '7704100023',
  },
  production: {
    country: 'cd',                      // RDC — alpha-2 (doc section 10)
    currency: 'USD',                    // RDC accepte CDF ou USD → USD confirmé
    integerAmountsOnly: false,          // à ajuster si Orange RDC exige des entiers
  },

  // ── OAuth2 (Step 3 de la doc) ───────────────────────────────────────────────
  // Credentials de l'application "Immozone" sur console.developer.orange.com
  // → page de l'app, champ "Authorization header" (Basic xxxxx).
  // 🔒 SÉCURITÉ: fourni via variable d'env/secret ORANGE_OAUTH_BASIC (recommandé)
  //    ou en dur ci-dessous (déconseillé — visible sur GitHub).
  //    Valeur attendue SANS le préfixe "Basic " (juste la chaîne base64).
  //    Lue dynamiquement via omOauthCredentials() ci-dessous.

  // ── Callback (Step 1-2 de la doc) ───────────────────────────────────────────
  // URL de BASE (sans /notifications) déclarée à la souscription sur Orange Developer.
  // Orange appellera automatiquement:
  //   {callbackUrl}/notifications        → notifications de transaction
  //   {callbackUrl}/orangeMoneyProvTest  → 3 tests automatiques de souscription
  callbackUrl: 'https://us-central1-immozone-d9a68.cloudfunctions.net/orangeMoneyWebhook',

  // Header Authorization que NOUS avons déclaré à la souscription (champ
  // "Authorization header"). Orange l'enverra dans CHAQUE requête callback.
  // Vérification TOUJOURS active (sandbox inclus — exigé par les 3 tests, doc section 8).
  // Correspond à: immozone-callback:e3agfy8PCKJAjXunbGno0RO48n4dSr
  partnerCallbackAuthorization: 'Basic aW1tb3pvbmUtY2FsbGJhY2s6ZTNhZ2Z5OFBDS0pBalh1bmJHbm8wUk80OG40ZFNy',

  // ── Chemins API ─────────────────────────────────────────────────────────────
  basePath: '/om_partner_api/v1',       // + /{country}/debit, /{country}/debit/transactions/{id}
  oauthPath: '/oauth/v3/token',
};

// Helpers d'environnement (sandbox vs production)
function omEnv() {
  return ORANGE_CONFIG.sandboxMode ? ORANGE_CONFIG.sandbox : ORANGE_CONFIG.production;
}
// Credentials OAuth lus à CHAQUE appel (le secret est injecté au runtime par Firebase)
function omOauthCredentials() {
  return (process.env.ORANGE_OAUTH_BASIC || '').trim();
}
function omDebitPath()  { return `${ORANGE_CONFIG.basePath}/${omEnv().country}/debit`; }
function omStatusPath(transactionId) {
  return `${ORANGE_CONFIG.basePath}/${omEnv().country}/debit/transactions/${encodeURIComponent(transactionId)}`;
}

// Cache du Bearer token OAuth (valide 1h = 3600 s)
let _oauthToken = null;
let _oauthTokenExpiry = 0;

// ─── Helper: requête HTTPS générique ───────────────────────────────────────────
async function httpsRequest({ hostname, path, method, headers = {}, bodyStr = '' }) {
  return new Promise((resolve, reject) => {
    const options = { hostname, path, method, headers: { ...headers } };
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
    req.setTimeout(30000, () => { req.destroy(new Error('Orange API timeout (30s)')); });
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

// ─── OAuth2: obtenir/renouveler le Bearer token (cache 1h, doc Step 3) ────────
async function getOAuthToken({ forceRefresh = false } = {}) {
  const now = Date.now();
  if (!forceRefresh && _oauthToken && now < _oauthTokenExpiry) return _oauthToken;

  // Cache Firestore (survit aux cold starts des fonctions)
  const configRef = db.collection('config').doc('orange_oauth_token');
  if (!forceRefresh) {
    const configDoc = await configRef.get();
    if (configDoc.exists) {
      const { token, expiry } = configDoc.data();
      if (token && expiry && now < expiry) {
        _oauthToken = token;
        _oauthTokenExpiry = expiry;
        return token;
      }
    }
  }

  const oauthCreds = omOauthCredentials();
  if (!oauthCreds) {
    throw new Error('ORANGE_OAUTH_BASIC non configuré — définissez le secret Firebase avec les app credentials Orange Developer (firebase functions:secrets:set ORANGE_OAUTH_BASIC)');
  }

  // POST https://api.orange.com/oauth/v3/token (grant_type=client_credentials)
  const resp = await httpsRequest({
    hostname: ORANGE_CONFIG.apiHost,
    path: ORANGE_CONFIG.oauthPath,
    method: 'POST',
    headers: {
      'Authorization': `Basic ${oauthCreds.replace(/^Basic\s+/i, '')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    },
    bodyStr: 'grant_type=client_credentials',
  });

  if (resp.status !== 200 || !resp.body?.access_token) {
    throw new Error(`OAuth Orange échoué: HTTP ${resp.status} — ${JSON.stringify(resp.body)}`);
  }

  const token = resp.body.access_token;
  const expiresInMs = (parseInt(resp.body.expires_in) || 3600) * 1000;
  const expiry = now + expiresInMs - 120000; // marge de sécurité 2 min

  await configRef.set({ token, expiry, updatedAt: new Date().toISOString() });
  _oauthToken = token;
  _oauthTokenExpiry = expiry;
  console.log('[Orange OAuth] Nouveau Bearer token obtenu (validité ~1h)');
  return token;
}

// ─── Appel API Orange Money authentifié (Bearer) avec retry auto sur 401 ──────
async function orangeApiCall({ method, path, body }) {
  const bodyStr = body ? JSON.stringify(body) : '';
  const doCall = async (token) => httpsRequest({
    hostname: ORANGE_CONFIG.apiHost,
    path,
    method,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    bodyStr,
  });

  let token = await getOAuthToken();
  let resp = await doCall(token);

  // 401 = token invalide/expiré → refresh + 1 retry (doc: error reference)
  if (resp.status === 401) {
    console.warn('[Orange API] 401 — refresh du token OAuth et retry');
    token = await getOAuthToken({ forceRefresh: true });
    resp = await doCall(token);
  }
  return resp;
}

// ─── Traduction des codes d'erreur Orange (doc section 6) ─────────────────────
function orangeErrorMessage(respBody, httpStatus) {
  const code = respBody?.code ?? respBody?.errorCode;
  const map = {
    10: 'Service souscrit mais pas encore activé par Orange. Veuillez patienter.',
    23: 'Requête invalide (champ manquant ou mal formaté).',
    30: 'Erreur technique de transaction (montant/devise invalide pour ce pays).',
    51: 'Demandeur non autorisé (OMContractRef mal associé à l\'application).',
    70: 'Service non inclus dans votre contrat Orange Money.',
  };
  if (code !== undefined && map[code]) return `[Orange ${code}] ${map[code]}`;
  if (httpStatus === 429) return 'Trop de requêtes vers Orange — veuillez réessayer dans quelques instants.';
  return respBody?.message || respBody?.description || `Erreur Orange HTTP ${httpStatus}`;
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
  { region: 'us-central1', cors: true, secrets: ['ORANGE_OAUTH_BASIC'] },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    try {
      const { paymentId, phoneNumber, amount, currency, userId } = req.body;

      // Validation basique
      if (!paymentId || !phoneNumber || !amount || !userId) {
        res.status(400).json({ error: 'Paramètres manquants: paymentId, phoneNumber, amount, userId requis' });
        return;
      }

      const env = omEnv();
      console.log(`[initiateOrangePayment] paymentId=${paymentId} msisdn=${phoneNumber} amount=${amount} env=${env.country}`);

      // 1. Normaliser le numéro (format msisdn: chiffres uniquement, sans +)
      const msisdn = String(phoneNumber).replace(/[\s\-]/g, '').replace(/^\+/, '');

      // 2. Montant: le sandbox n'accepte QUE des entiers (doc section 8)
      let txAmount = parseFloat(amount);
      if (env.integerAmountsOnly) txAmount = Math.round(txAmount);

      // 3. Body DEBIT exact (doc 4.1 — 5 champs, transactionId = idempotency key)
      // ⚠️ transactionId JAMAIS réutilisable, même après échec (doc section 6/7)
      const debitBody = {
        peerId: msisdn,
        peerIdType: 'msisdn',
        amount: txAmount,
        currency: currency || env.currency,
        transactionId: paymentId,
      };

      // 4. POST /{country}/debit — OAuth Bearer géré/rafraîchi automatiquement
      const omResp = await orangeApiCall({
        method: 'POST',
        path: omDebitPath(),
        body: debitBody,
      });

      console.log(`[initiateOrangePayment] Orange HTTP ${omResp.status}:`, JSON.stringify(omResp.body));

      // ── 202 Accepted = transaction créée (doc: "No 202 = transaction failed") ──
      if (omResp.status === 202) {
        const respBody = omResp.body || {};
        const txStatus = respBody.status || 'PENDING';
        const txData = respBody.transactionData || {};

        // Cas nominal: PENDING → le client valide par PIN → callback /notifications
        await db.collection('payments').doc(paymentId).update({
          status: 'pending',
          operator: 'orange_money',
          omCountry: env.country,
          omCurrency: debitBody.currency,
          omAmount: txAmount,
          omServiceTimeout: txData.serviceTimeout || 300000,
          omInitiatedAt: new Date().toISOString(),
        });

        res.status(200).json({
          success: true,
          transactionStatus: txStatus === 'SUCCESS' ? 'SUCCESSFUL' : 'PENDING',
          transactionId: paymentId,
          serviceTimeout: txData.serviceTimeout || 300000,
          message: 'Confirmez le paiement sur votre téléphone (code PIN Orange Money)',
          sandboxMode: ORANGE_CONFIG.sandboxMode,
        });
        return;
      }

      // ── 429 = rate limit — transaction JAMAIS créée, retry possible plus tard ──
      // ── autres 4xx/5xx = échec définitif, NE PAS poller le statut (doc) ────────
      const errorMsg = orangeErrorMessage(omResp.body, omResp.status);
      console.error('[initiateOrangePayment] Orange error:', omResp.status, JSON.stringify(omResp.body));

      await db.collection('payments').doc(paymentId).update({
        status: 'failed',
        failureReason: errorMsg,
        failedAt: new Date().toISOString(),
        omHttpStatus: omResp.status,
      });

      res.status(200).json({
        success: false,
        transactionStatus: 'FAILED',
        retryable: omResp.status === 429,   // 429: rejouable avec un NOUVEAU transactionId
        error: errorMsg,
      });

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
    // ── Routage interne (doc Step 1) ──────────────────────────────────────────
    // Orange appelle {callbackUrl}/notifications et {callbackUrl}/orangeMoneyProvTest
    const path = (req.path || '/').replace(/\/+$/, '') || '/';

    // 🔒 Vérification Basic Auth — TOUJOURS active (sandbox inclus, doc section 8:
    // "Same callback validation as production")
    const authHeader = req.headers['authorization'] || '';
    const authValid = authHeader === ORANGE_CONFIG.partnerCallbackAuthorization;

    // ── /orangeMoneyProvTest : les 3 tests automatiques de souscription ───────
    // Test 1 (sans auth) → 401 | Test 2 (fausse auth) → 401 | Test 3 (bonne auth) → 200
    if (path.endsWith('/orangeMoneyProvTest')) {
      if (!authValid) {
        console.warn('[orangeWebhook] ProvTest: auth absente/invalide → 401 (comportement attendu tests 1-2)');
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }
      console.log('[orangeWebhook] ✅ ProvTest: auth valide → 200 (test 3 réussi)');
      res.status(200).json({ status: 'OK' });
      return;
    }

    // ── /notifications (ou racine par tolérance) : notification de transaction ─
    if (!authValid) {
      console.warn('[orangeWebhook] ⛔ Authorization header invalide — notification rejetée');
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    // Répondre 200 immédiatement (exigence Orange: accusé de réception)
    res.status(200).json({ status: 'OK' });

    try {
      const body = req.body || {};
      console.log(`[orangeWebhook] RAW payload (path=${path}):`, JSON.stringify(body));

      // Format officiel (doc section 5):
      // { "status": "SUCCESS"|"FAILED", "message": "...",
      //   "transactionData": { "transactionId": <NOTRE ID>, "txnId": <ID Orange>,
      //     "type": "debit", "peerId", "amount", "currency", "executionDate", "country" } }
      const transactionStatus = body.status;
      const txData = body.transactionData || {};

      const transactionId   = txData.transactionId;   // NOTRE ID (clé Firestore payments)
      const omTransactionId = txData.txnId || '';     // ID interne Orange (ex: SX260220.1608.B02855) — optionnel
      const peerId          = txData.peerId;
      const amount          = txData.amount;
      const currency        = txData.currency;
      const executionDate   = txData.executionDate || '';
      const failureReason   = body.message || '';

      console.log(`[orangeWebhook] transactionId=${transactionId} status=${transactionStatus} txnId=${omTransactionId}`);

      if (!transactionId) {
        console.warn('[orangeWebhook] transactionData.transactionId absent — payload complet:', JSON.stringify(body));
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

      if (transactionStatus === 'SUCCESS') {
        // ── SUCCÈS ────────────────────────────────────────────────────────────
        await payRef.update({
          status: 'confirmed',
          confirmedAt: new Date().toISOString(),
          isConfirmed: true,
          omTxnId: omTransactionId,              // ID Orange ex: SX260220.1608.B02855 (peut être vide)
          omPeerId: peerId || '',                // numéro msisdn du client
          omAmount: amount || 0,                 // montant confirmé par Orange
          omCurrency: currency || '',            // devise confirmée par Orange
          omExecutionDate: executionDate,        // date d'exécution ISO 8601
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

      } else if (transactionStatus === 'FAILED') {
        // ── ÉCHEC ─────────────────────────────────────────────────────────────
        // (le message contient la raison, ex: timeout PIN 5 min, solde insuffisant…)
        await payRef.update({
          status: 'failed',
          failedAt: new Date().toISOString(),
          omFinalStatus: 'FAILED',
          failureReason: failureReason || 'Paiement Orange Money échoué',
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
  { region: 'us-central1', cors: true, secrets: ['ORANGE_OAUTH_BASIC'] },
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

      // 2. Interroger la Status API Orange (doc 4.7)
      // GET /{country}/debit/transactions/{transactionId} — {transactionId} = NOTRE ID
      // Fonctionne aussi en sandbox (sx) — le sandbox est pleinement fonctionnel pour debit.
      const statusResp = await orangeApiCall({
        method: 'GET',
        path: omStatusPath(paymentId),
      });

      // ── 404 = transaction inexistante chez Orange (doc: "Do not retry —
      //    submit a new transaction with a new transactionId") ──────────────────
      if (statusResp.status === 404) {
        await db.collection('payments').doc(paymentId).update({
          status: 'failed',
          failedAt: new Date().toISOString(),
          omFinalStatus: 'NOT_FOUND',
          failureReason: 'Transaction introuvable chez Orange — veuillez relancer un nouveau paiement',
        });
        res.status(200).json({ transactionStatus: 'FAILED', reason: 'not_found', source: 'orange_api' });
        return;
      }

      // Réponse doc 4.7: { status: SUCCESS|FAILED|PENDING, message, transactionData: {...} }
      const rawStatus = statusResp.body?.status || 'PENDING';
      const txData = statusResp.body?.transactionData || {};
      let omStatus = 'PENDING';
      if (rawStatus === 'SUCCESS') omStatus = 'SUCCESSFUL';
      else if (rawStatus === 'FAILED') omStatus = 'FAILED';

      // Si Orange confirme le succès mais que le webhook n'est pas encore passé → créditer
      if (omStatus === 'SUCCESSFUL' && payment.status !== 'confirmed') {
        await db.collection('payments').doc(paymentId).update({
          status: 'confirmed',
          confirmedAt: new Date().toISOString(),
          isConfirmed: true,
          omTxnId: txData.txnId || '',
          omExecutionDate: txData.executionDate || '',
          omFinalStatus: 'SUCCESSFUL',
        });
        await creditUserAfterPayment(paymentId);
      } else if (omStatus === 'FAILED' && payment.status !== 'failed') {
        await db.collection('payments').doc(paymentId).update({
          status: 'failed',
          failedAt: new Date().toISOString(),
          omFinalStatus: 'FAILED',
          failureReason: statusResp.body?.message || 'Paiement Orange Money échoué',
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

    // ═════════════════════════════════════════════════════════════════════════
    // PURGE 72h : suppression DÉFINITIVE des biens marqués vendus/occupés
    // depuis plus de 72 heures (3 jours). Pendant les 72h le bien reste visible
    // (badge "Vendu"/"Occupé" + tableau Historique), puis il est totalement
    // retiré du système.
    // ═════════════════════════════════════════════════════════════════════════
    try {
      const cutoffIso = new Date(now.getTime() - 72 * 3600 * 1000).toISOString();

      const [soldSnap, rentedSnap] = await Promise.all([
        db.collection('properties').where('isSold', '==', true).get(),
        db.collection('properties').where('isRented', '==', true).get(),
      ]);

      // Fusion + déduplication (un doc peut matcher les deux requêtes)
      const toCheck = new Map();
      soldSnap.forEach((d) => toCheck.set(d.id, d));
      rentedSnap.forEach((d) => toCheck.set(d.id, d));

      const delBatch = db.batch();
      const deleted = [];

      toCheck.forEach((doc) => {
        const data = doc.data();
        // Dates stockées en ISO-8601 → comparaison lexicale valide.
        // Si updatedAt absent, on utilise createdAt ; si aucune date, on ignore
        // (sera réparé au prochain marquage/màj).
        const ref = data.updatedAt || data.createdAt;
        if (!ref) return;
        if (ref <= cutoffIso) {
          delBatch.delete(doc.ref);
          deleted.push({ id: doc.id, data });
        }
      });

      if (deleted.length > 0) {
        await delBatch.commit();

        // Notifier chaque annonceur que son annonce vendue/occupée a été retirée
        for (const { id, data } of deleted) {
          try {
            if (!data.ownerId) continue;
            const label = data.isSold ? 'vendue' : 'occupée';
            const notifId = `notif_purge_${id}_${Date.now()}`;
            await db.collection('notifications').doc(notifId).set({
              id: notifId,
              userId: data.ownerId,
              type: 'info',
              title: 'Annonce retirée',
              body: `Votre annonce "${data.title || ''}" marquée ${label} a été retirée du système ` +
                    `après le délai de 72 heures, conformément aux règles de la plateforme.`,
              propertyId: id,
              propertyTitle: data.title || '',
              isRead: false,
              createdAt: nowIso,
            });
          } catch (nErr) {
            console.warn(`[expireProperties] Purge notification failed for ${id}:`, nErr.message);
          }
        }
      }

      console.log(`[expireProperties] 🗑️ Purge 72h — ${deleted.length} bien(s) vendu(s)/occupé(s) supprimé(s) définitivement (${toCheck.size} vérifié(s))`);
    } catch (purgeErr) {
      console.error('[expireProperties] Purge 72h exception:', purgeErr);
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
