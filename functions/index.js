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
// Service d'ENCAISSEMENT (client → marchand): WITHDRAW (Cashout) — POST /{country}/withdraw
//   Doc 3.3: Customer OM account → Partner OM account. Le client reçoit un push
//   USSD/SMS, confirme par PIN, puis Orange notifie le callbackUrl (SUCCESS/FAILED).
//   Flux STRICTEMENT identique au debit — seul l'endpoint diffère.
//   Contrat ehYUTxuSVUgzesKX: services actifs = Credit + Withdraw (Debit NON souscrit,
//   erreur 70). collectionService permet de rebasculer sur 'debit' en 1 ligne si besoin.
// Service de REMBOURSEMENT (marchand → client): CREDIT — POST /{country}/credit
// ═══════════════════════════════════════════════════════════════════════════════
const ORANGE_CONFIG = {
  apiHost: 'api.orange.com',

  // ── Service utilisé pour encaisser les paiements clients ───────────────────
  // 'withdraw' (actif sur notre contrat) | 'debit' (non souscrit — erreur 70)
  collectionService: 'withdraw',

  // ── Bascule sandbox/production ─────────────────────────────────────────────
  // sandboxMode=true  → pays 'sx', devise 'OUV', montants ENTIERS uniquement
  // sandboxMode=false → pays 'cd' (RDC), devise 'USD'
  sandboxMode: false,                   // ✅ PRODUCTION (go-live 02/09/2026) — app "Immozone production", pays 'cd', devise 'USD'

  sandbox: {
    country: 'sx',
    currency: 'OUV',
    integerAmountsOnly: true,           // sandbox: pas de décimales
    // MSISDN de test du souscripteur (email d'activation Orange du 18/08/2026)
    testMsisdn: '7704100021',
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
  basePath: '/om_partner_api/v1',       // + /{country}/{service}, /{country}/{service}/transactions/{id}
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
// Normalisation msisdn — ⚠️ VÉRIFIÉ EN PROD (03/09/2026): Orange Money RDC (cd)
// n'accepte QUE le format LOCAL (0840931102). Le format international 243840931102
// retourne "The customer account is unknown" (code 24).
// → on retire espaces/tirets/+, puis on convertit 243XXXXXXXXX → 0XXXXXXXXX.
function omNormalizeMsisdn(phoneNumber) {
  let m = String(phoneNumber || '').replace(/[\s\-]/g, '').replace(/^\+/, '');
  if (!ORANGE_CONFIG.sandboxMode) {
    if (m.startsWith('243') && m.length === 12) {
      m = '0' + m.slice(3);          // 243840931102 → 0840931102
    } else if (m.length === 9 && !m.startsWith('0')) {
      m = '0' + m;                   // 840931102 → 0840931102 (le Flutter retire le 0 national)
    }
    // m.length === 10 && startsWith('0') → déjà au bon format
  }
  return m;
}
// Chemin d'encaissement — piloté par ORANGE_CONFIG.collectionService (withdraw/debit)
function omCollectPath() { return `${ORANGE_CONFIG.basePath}/${omEnv().country}/${ORANGE_CONFIG.collectionService}`; }
function omCreditPath()  { return `${ORANGE_CONFIG.basePath}/${omEnv().country}/credit`; }
function omStatusPath(transactionId, type = ORANGE_CONFIG.collectionService) {
  return `${ORANGE_CONFIG.basePath}/${omEnv().country}/${type}/transactions/${encodeURIComponent(transactionId)}`;
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

      // 1. Normaliser le numéro (prod cd: format LOCAL 0XXXXXXXXX exigé par Orange)
      const msisdn = omNormalizeMsisdn(phoneNumber);

      // 2. Montant: le sandbox n'accepte QUE des entiers (doc section 8)
      let txAmount = parseFloat(amount);
      if (env.integerAmountsOnly) txAmount = Math.round(txAmount);

      // 3. Body d'encaissement (withdraw/debit — même schéma 5 champs,
      //    transactionId = idempotency key)
      // ⚠️ transactionId JAMAIS réutilisable, même après échec (doc section 6/7)
      // ⚠️ Pattern Orange: underscores '_' REJETÉS (erreur 24) → sanitisation
      // ⚠️ Sandbox: devise OUV OBLIGATOIRE — on force env.currency en sandbox
      const txId = String(paymentId).replace(/_/g, '-');
      const collectBody = {
        peerId: msisdn,
        peerIdType: 'msisdn',
        amount: txAmount,
        currency: ORANGE_CONFIG.sandboxMode ? env.currency : (currency || env.currency),
        transactionId: txId,
      };

      // 4. POST /{country}/withdraw (doc 3.3 Cashout: client → marchand, confirmation
      //    PIN client puis callback) — OAuth Bearer géré/rafraîchi automatiquement
      const omResp = await orangeApiCall({
        method: 'POST',
        path: omCollectPath(),
        body: collectBody,
      });

      console.log(`[initiateOrangePayment] Orange HTTP ${omResp.status}:`, JSON.stringify(omResp.body));

      // ── 202 Accepted = transaction créée (doc: "No 202 = transaction failed") ──
      if (omResp.status === 202) {
        const respBody = omResp.body || {};
        const txStatus = respBody.status || 'PENDING';
        const txData = respBody.transactionData || {};

        // Cas nominal: PENDING → le client valide par PIN → callback /notifications
        // set+merge: robuste même si le doc n'existe pas encore (tests curl), et
        // préserve les champs créés côté Flutter en usage réel
        await db.collection('payments').doc(paymentId).set({
          status: 'pending',
          operator: 'orange_money',
          omCountry: env.country,
          omCurrency: collectBody.currency,
          omAmount: txAmount,
          omService: ORANGE_CONFIG.collectionService,   // 'withdraw' (trace du service utilisé)
          omServiceTimeout: txData.serviceTimeout || 300000,
          omInitiatedAt: new Date().toISOString(),
        }, { merge: true });

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

      await db.collection('payments').doc(paymentId).set({
        status: 'failed',
        failureReason: errorMsg,
        failedAt: new Date().toISOString(),
        omHttpStatus: omResp.status,
      }, { merge: true });

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

    // ⚠️ FIX: traiter la notification AVANT de répondre 200.
    // Cloud Functions gèle l'exécution dès que la réponse HTTP est envoyée
    // (surtout au cold start) → le traitement post-réponse était parfois perdu
    // et Orange devait renvoyer la notification une 2ème fois.
    // Le traitement Firestore prend < 2s, largement sous la limite Orange de 5s.
    const handleNotification = async () => {
      const body = req.body || {};
      console.log(`[orangeWebhook] RAW payload (path=${path}):`, JSON.stringify(body));

      // Format officiel (doc section 5):
      // { "status": "SUCCESS"|"FAILED", "message": "...",
      //   "transactionData": { "transactionId": <NOTRE ID>, "txnId": <ID Orange>,
      //     "type": "withdraw"|"debit"|"credit", "peerId", "amount", "currency", "executionDate", "country" } }
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

      // ── Notification de REMBOURSEMENT (credit) ? ─────────────────────────────
      // Nos refundIds sont préfixés 'refund-' (tirets — pattern Orange) →
      // routage vers le traitement dédié ('refund_' gardé pour compatibilité)
      if (transactionId.startsWith('refund-') || transactionId.startsWith('refund_')) {
        await processRefundNotification(transactionId, transactionStatus, {
          omTransactionId, executionDate, failureReason,
        });
        return;
      }

      // Le transactionId envoyé à Orange est sanitisé (underscores → tirets).
      // Si le doc Firestore n'existe pas sous l'id reçu, on tente la variante
      // avec underscores (anciens ids 'pay_...' créés côté Flutter).
      let payRef = db.collection('payments').doc(transactionId);
      let payDoc = await payRef.get();

      if (!payDoc.exists && transactionId.startsWith('pay-')) {
        const legacyId = 'pay_' + transactionId.slice(4);
        const legacyRef = db.collection('payments').doc(legacyId);
        const legacyDoc = await legacyRef.get();
        if (legacyDoc.exists) { payRef = legacyRef; payDoc = legacyDoc; }
      }

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

        // Créditer l'utilisateur (payRef.id = id réel du doc Firestore,
        // qui peut différer du transactionId sanitisé envoyé à Orange)
        await creditUserAfterPayment(payRef.id);

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
                data: { paymentId: payRef.id, status: 'confirmed' },
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
                data: { paymentId: payRef.id, status: 'failed' },
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

    };

    try {
      await handleNotification();
    } catch (err) {
      // Ne jamais renvoyer d'erreur — Orange attend toujours un HTTP 200
      console.error('[orangeWebhook] Exception pendant le traitement:', err);
    }

    // Accusé de réception APRÈS traitement complet (exigence Orange: 200 < 5s)
    res.status(200).json({ status: 'OK' });
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
      // GET /{country}/{collectionService}/transactions/{transactionId} — {transactionId} = NOTRE ID
      // ⚠️ Même sanitisation qu'à l'initiation (underscores → tirets)
      const statusResp = await orangeApiCall({
        method: 'GET',
        path: omStatusPath(String(paymentId).replace(/_/g, '-')),
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

// ─── Helper: poller le statut d'un CREDIT après le 202 ─────────────────────────
// En sandbox (et souvent en prod), le CREDIT passe en SUCCESS en ~2s mais la
// réponse 202 initiale dit encore PENDING. Sans ce polling, le remboursement
// resterait bloqué 'pending' jusqu'au webhook (qui peut ne jamais arriver si
// Orange a déjà résolu la transaction avant d'appeler le callback).
// Retourne { finalStatus: 'SUCCESS'|'FAILED'|'PENDING', txnId, executionDate, message }
async function pollCreditFinalStatus(refundId, { delayMs = 2500, attempts = 2 } = {}) {
  for (let i = 0; i < attempts; i++) {
    await new Promise(r => setTimeout(r, delayMs));
    try {
      const statusResp = await orangeApiCall({
        method: 'GET',
        path: omStatusPath(refundId, 'credit'),
      });
      console.log(`[pollCreditFinalStatus] ${refundId} tentative ${i + 1}: HTTP ${statusResp.status}`, JSON.stringify(statusResp.body));
      const body = statusResp.body || {};
      const txData = body.transactionData || {};
      if (body.status === 'SUCCESS') {
        return { finalStatus: 'SUCCESS', txnId: txData.txnId || '', executionDate: txData.executionDate || '', message: body.message || '' };
      }
      if (body.status === 'FAILED') {
        return { finalStatus: 'FAILED', txnId: txData.txnId || '', executionDate: txData.executionDate || '', message: body.message || '' };
      }
    } catch (err) {
      console.warn(`[pollCreditFinalStatus] ${refundId} tentative ${i + 1} erreur:`, err.message);
    }
  }
  return { finalStatus: 'PENDING', txnId: '', executionDate: '', message: '' };
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION 4: refundOrangePayment
// Remboursement d'un paiement confirmé — service CREDIT Orange Money
// (POST /{country}/credit — ImmoZone → portefeuille du client)
// Appelée par l'admin depuis l'écran Gestion des Paiements
// URL: https://us-central1-immozone-d9a68.cloudfunctions.net/refundOrangePayment
// ═══════════════════════════════════════════════════════════════════════════════
exports.refundOrangePayment = onRequest(
  { region: 'us-central1', cors: true, secrets: ['ORANGE_OAUTH_BASIC'] },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'POST requis' });
      return;
    }

    // Portée large : accessible au catch pour rollback en cas de crash après révocation
    let revokedListOuter = [];
    try {
      const {
        paymentId, adminId, adminName, reason,
        refundPhoneNumber,     // 🆕 numéro Orange Money à créditer (saisi par l'admin)
        buyerPhoneNumber,      // 🆕 numéro du compte Immozone qui avait été crédité
        declaredAmount,        // 🆕 montant déclaré par l'admin (doit == Firestore)
      } = req.body || {};

      if (!paymentId || !adminId) {
        res.status(400).json({ error: 'Paramètres manquants: paymentId, adminId requis' });
        return;
      }
      // 🆕 RÈGLE 1 : l'admin DOIT renseigner les numéros + le montant
      if (!refundPhoneNumber || !buyerPhoneNumber || declaredAmount === undefined || declaredAmount === null) {
        res.status(400).json({
          error: 'Paramètres requis: refundPhoneNumber (numéro OM à créditer), buyerPhoneNumber (compte Immozone crédité), declaredAmount (montant)',
        });
        return;
      }

      // 🔒 Garde-fou: vérifier que l'appelant est bien un admin
      const adminDoc = await db.collection('users').doc(adminId).get();
      if (!adminDoc.exists || adminDoc.data().role !== 'admin') {
        res.status(403).json({ error: 'Accès refusé — réservé aux administrateurs' });
        return;
      }

      // 1. Charger et valider le paiement d'origine
      const payRef = db.collection('payments').doc(paymentId);
      const payDoc = await payRef.get();
      if (!payDoc.exists) {
        res.status(404).json({ error: 'Paiement introuvable' });
        return;
      }
      const payment = payDoc.data();

      if (payment.status !== 'confirmed') {
        res.status(400).json({ error: 'Seul un paiement confirmé peut être remboursé' });
        return;
      }
      if (payment.operator !== 'orange_money') {
        res.status(400).json({ error: 'Remboursement automatique disponible uniquement pour Orange Money' });
        return;
      }
      if (payment.refundStatus === 'pending' || payment.refundStatus === 'refunded') {
        res.status(400).json({ error: `Remboursement déjà ${payment.refundStatus === 'pending' ? 'en cours' : 'effectué'}` });
        return;
      }

      // 🆕 RÈGLE 2 : fenêtre de 72h — au-delà, remboursement refusé
      const opDate = new Date(payment.confirmedAt || payment.createdAt || 0).getTime();
      const ageHours = (Date.now() - opDate) / 3600000;
      if (!opDate || ageHours > 72) {
        res.status(400).json({
          error: `Remboursement refusé : l'achat date de plus de 72h (${Math.floor(ageHours)}h). Fenêtre de remboursement dépassée.`,
        });
        return;
      }

      // 🆕 RÈGLE 3a : le numéro Immozone renseigné doit être celui de l'acheteur
      // On compare au numéro porté par le paiement ET au numéro du compte user.
      const buyerNorm = omNormalizeMsisdn(buyerPhoneNumber);
      const payNorm = omNormalizeMsisdn(payment.phoneNumber || '');
      const omNorm = omNormalizeMsisdn(payment.omPeerId || '');
      let userPhoneNorm = '';
      try {
        if (payment.userId) {
          const buyerDoc = await db.collection('users').doc(payment.userId).get();
          if (buyerDoc.exists) userPhoneNorm = omNormalizeMsisdn(buyerDoc.data().phone || '');
        }
      } catch (_) {}
      // 🆕 Fallback Firebase AUTH : doc Firestore supprimé (compte effacé/recréé)
      // → le numéro reste dans Auth (celui de l'OTP WhatsApp).
      if (!userPhoneNorm && payment.userId) {
        try {
          const authUser = await admin.auth().getUser(payment.userId);
          userPhoneNorm = omNormalizeMsisdn(authUser.phoneNumber || '');
        } catch (_) {}
      }
      const buyerMatches = buyerNorm && (buyerNorm === payNorm || buyerNorm === omNorm || buyerNorm === userPhoneNorm);
      if (!buyerMatches) {
        console.warn(`[refundOrangePayment] ⛔ buyer mismatch: saisi=${buyerNorm} vs payment=${payNorm}/${omNorm}/user=${userPhoneNorm}`);
        res.status(400).json({
          error: 'Vérification échouée : le numéro Immozone renseigné ne correspond pas à l\'acheteur de ce paiement.',
        });
        return;
      }

      // 🆕 RÈGLE 3b : le montant déclaré doit être EXACTEMENT celui de Firestore
      const expectedAmount = parseFloat(payment.omAmount || payment.amount || 0);
      const declared = parseFloat(String(declaredAmount).replace(',', '.'));
      if (!declared || Math.abs(declared - expectedAmount) > 0.001) {
        res.status(400).json({
          error: `Vérification échouée : montant déclaré (${declared}) différent du montant enregistré (${expectedAmount} ${payment.omCurrency || 'USD'}).`,
        });
        return;
      }

      const env = omEnv();

      // 2. Destinataire : le numéro OM RENSEIGNÉ par l'admin (règle métier),
      //    format LOCAL exigé par Orange en prod cd
      const msisdn = omNormalizeMsisdn(refundPhoneNumber);
      if (!msisdn || !/^\d{7,15}$/.test(msisdn)) {
        res.status(400).json({ error: 'Numéro Orange Money à créditer invalide' });
        return;
      }

      // 3. Montant validé (== Firestore)
      let refundAmount = expectedAmount;
      if (env.integerAmountsOnly) refundAmount = Math.round(refundAmount);
      if (!refundAmount || refundAmount <= 0) {
        res.status(400).json({ error: 'Montant de remboursement invalide' });
        return;
      }

      // 🆕 RÈGLE 4 : RÉVOQUER LES CRÉDITS D'ABORD — si la révocation échoue,
      // le remboursement N'EST PAS effectué (pas d'argent sans reprise des crédits).
      let revokedList = [];
      try {
        revokedList = await revokeCreditsForPayment(paymentId);
        revokedListOuter = revokedList;
      } catch (revokeErr) {
        console.error('[refundOrangePayment] ⛔ Échec révocation crédits — remboursement ANNULÉ:', revokeErr);
        res.status(500).json({
          error: 'Révocation des crédits impossible — remboursement annulé par sécurité. Réessayez.',
        });
        return;
      }

      // 4. transactionId de remboursement: NOUVEAU, unique, jamais réutilisé
      // ⚠️ Pattern Orange: underscores REJETÉS (erreur 24) — tirets uniquement.
      // ⚠️ LONGUEUR: l'ancien format `refund-<paymentId>-<ts>` (~38 car.)
      //    dépassait la limite Orange → "Invalid body field".
      //    Format court (~25 car.): le lien paymentId est dans le doc refunds.
      const refundId = `refund-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

      const creditBody = {
        peerId: msisdn,
        peerIdType: 'msisdn',
        amount: refundAmount,
        currency: payment.omCurrency || env.currency,
        transactionId: refundId,
      };

      console.log(`[refundOrangePayment] paymentId=${paymentId} refundId=${refundId} msisdn=${msisdn} amount=${refundAmount}`);

      // 5. POST /{country}/credit — même flux que debit (202 = accepté)
      const omResp = await orangeApiCall({
        method: 'POST',
        path: omCreditPath(),
        body: creditBody,
      });

      console.log(`[refundOrangePayment] Orange HTTP ${omResp.status}:`, JSON.stringify(omResp.body));

      if (omResp.status === 202) {
        const respBody = omResp.body || {};
        let isImmediate = respBody.status === 'SUCCESS';
        let isFailed = false;
        let omTxnId = (respBody.transactionData || {}).txnId || '';
        let failMessage = '';

        // ⚠️ FIX: si le 202 dit PENDING, poller la Status API (~2,5s) —
        // le CREDIT aboutit quasi immédiatement et le webhook peut ne jamais
        // être appelé si la transaction est déjà résolue.
        if (!isImmediate) {
          const polled = await pollCreditFinalStatus(refundId);
          if (polled.finalStatus === 'SUCCESS') {
            isImmediate = true;
            omTxnId = polled.txnId || omTxnId;
          } else if (polled.finalStatus === 'FAILED') {
            isFailed = true;
            failMessage = polled.message || 'Remboursement refusé par Orange';
          }
        }

        // 🆕 Si Orange a REFUSÉ le crédit → restaurer les crédits révoqués (rollback)
        if (isFailed && revokedList.length > 0) {
          await unrevokeCredits(revokedList);
        }

        // Doc de suivi du remboursement (le webhook le retrouvera par refundId)
        await db.collection('refunds').doc(refundId).set({
          id: refundId,
          paymentId,
          userId: payment.userId ?? null,   // robustesse: doc de test sans userId
          msisdn,
          buyerPhoneNumber: buyerNorm,      // 🆕 traçabilité: compte acheteur vérifié
          amount: refundAmount,
          currency: creditBody.currency,
          status: isImmediate ? 'confirmed' : (isFailed ? 'failed' : 'pending'),
          creditsRevoked: revokedList.map((r) => r.id), // 🆕 traçabilité révocation
          reason: reason || null,
          adminId,
          adminName: adminName || '',
          createdAt: new Date().toISOString(),
          ...(isImmediate ? { confirmedAt: new Date().toISOString(), omTxnId } : {}),
          ...(isFailed ? { failedAt: new Date().toISOString(), failureReason: failMessage } : {}),
        });

        await payRef.update({
          refundStatus: isImmediate ? 'refunded' : (isFailed ? 'failed' : 'pending'),
          refundId,
          refundAmount,
          refundReason: reason || null,
          refundRequestedAt: new Date().toISOString(),
          refundRequestedBy: adminName || adminId,
          ...(isImmediate ? { refundedAt: new Date().toISOString() } : {}),
        });

        const totalRevokedPay = revokedList.reduce((s, r) => s + (r.remaining || 0), 0);
        res.status(200).json({
          success: !isFailed,
          refundId,
          creditsRevoked: totalRevokedPay,
          refundStatus: isImmediate ? 'refunded' : (isFailed ? 'failed' : 'pending'),
          amount: refundAmount,
          currency: creditBody.currency,
          ...(isFailed ? { error: failMessage } : {}),
          message: isImmediate
            ? `Remboursement effectué avec succès — ${totalRevokedPay} crédit(s) révoqué(s)`
            : (isFailed ? failMessage : 'Remboursement initié — confirmation Orange en attente'),
        });
        return;
      }

      // Échec (dont code 70 tant que le service CREDIT n'est pas activé au contrat)
      // 🆕 Orange a rejeté la requête → restaurer les crédits révoqués (rollback)
      if (revokedList.length > 0) await unrevokeCredits(revokedList);
      const errorMsg = orangeErrorMessage(omResp.body, omResp.status);
      console.error('[refundOrangePayment] Orange error:', omResp.status, JSON.stringify(omResp.body));
      res.status(200).json({
        success: false,
        retryable: omResp.status === 429,
        error: errorMsg,
      });

    } catch (err) {
      console.error('[refundOrangePayment] Exception:', err);
      // 🆕 Crash après révocation mais avant/inconnu côté Orange → restaurer les crédits
      // (le webhook re-révoquera si Orange confirme finalement le remboursement)
      if (revokedListOuter.length > 0) await unrevokeCredits(revokedListOuter);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION: directOrangeCredit — Remboursement dashboard admin SÉCURISÉ
// 🔒 N'est PLUS un remboursement libre : le système recherche le paiement
// confirmé correspondant (numéro acheteur + montant, < 72h, non remboursé),
// RÉVOQUE SES CRÉDITS D'ABORD, puis effectue le POST /{country}/credit.
// Aucun achat correspondant → REFUS. Rollback des crédits si Orange échoue.
// URL: https://us-central1-immozone-d9a68.cloudfunctions.net/directOrangeCredit
// ═══════════════════════════════════════════════════════════════════════════════
exports.directOrangeCredit = onRequest(
  { region: 'us-central1', cors: true, secrets: ['ORANGE_OAUTH_BASIC'] },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'POST requis' });
      return;
    }

    // Portée large : accessible au catch pour rollback après révocation
    let revokedListOuter = [];
    try {
      const { phoneNumber, buyerPhoneNumber, amount, adminId, adminName, reason } = req.body || {};

      // 🆕 RÈGLE 1 : numéro OM à créditer + compte Immozone acheteur + montant requis
      if (!phoneNumber || !buyerPhoneNumber || !amount || !adminId) {
        res.status(400).json({
          error: 'Paramètres requis: phoneNumber (numéro OM à créditer), buyerPhoneNumber (compte Immozone crédité), amount, adminId',
        });
        return;
      }

      // 🔒 Garde-fou: vérifier que l'appelant est bien un admin
      const adminDoc = await db.collection('users').doc(adminId).get();
      if (!adminDoc.exists || adminDoc.data().role !== 'admin') {
        res.status(403).json({ error: 'Accès refusé — réservé aux administrateurs' });
        return;
      }

      const env = omEnv();

      // 1. Normaliser les numéros (prod cd: format LOCAL 0XXXXXXXXX exigé par Orange)
      const msisdn = omNormalizeMsisdn(phoneNumber);
      if (!/^\d{7,15}$/.test(msisdn)) {
        res.status(400).json({ error: 'Numéro Orange Money invalide' });
        return;
      }
      const buyerNorm = omNormalizeMsisdn(buyerPhoneNumber);
      if (!/^\d{7,15}$/.test(buyerNorm)) {
        res.status(400).json({ error: 'Numéro du compte Immozone invalide' });
        return;
      }

      // 2. Montant (sandbox: entiers uniquement)
      let creditAmount = parseFloat(String(amount).replace(',', '.'));
      if (env.integerAmountsOnly) creditAmount = Math.round(creditAmount);
      if (!creditAmount || creditAmount <= 0) {
        res.status(400).json({ error: 'Montant invalide' });
        return;
      }

      // 🆕 RÈGLE 2+3 : retrouver le paiement CONFIRMÉ correspondant —
      // même acheteur, même montant, moins de 72h, pas encore remboursé.
      // ⚠️ Filtre Firestore sur UNE seule inégalité (createdAt ISO string) pour
      // ne pas exiger d'index composite ; le reste est vérifié en mémoire.
      const cutoffIso = new Date(Date.now() - 73 * 3600000).toISOString(); // marge 1h
      const paySnap = await db.collection('payments')
        .where('createdAt', '>=', cutoffIso)
        .get();

      const candidates = [];
      for (const doc of paySnap.docs) {
        const p = doc.data();
        if (p.status !== 'confirmed') continue;
        if (p.operator && p.operator !== 'orange_money') continue;
        if (p.refundStatus === 'pending' || p.refundStatus === 'refunded') continue;
        // Fenêtre 72h stricte sur confirmedAt||createdAt
        const opDate = new Date(p.confirmedAt || p.createdAt || 0).getTime();
        if (!opDate || (Date.now() - opDate) / 3600000 > 72) continue;
        // Acheteur : numéro du paiement OU du compte user
        const payNorm = omNormalizeMsisdn(p.phoneNumber || '');
        const omNorm = omNormalizeMsisdn(p.omPeerId || '');
        let userPhoneNorm = '';
        if (p.userId) {
          try {
            const uDoc = await db.collection('users').doc(p.userId).get();
            if (uDoc.exists) userPhoneNorm = omNormalizeMsisdn(uDoc.data().phone || '');
          } catch (_) {}
          // 🆕 Fallback Firebase AUTH : si le doc Firestore du compte a été
          // supprimé (compte effacé/recréé), le numéro reste dans Auth —
          // c'est lui qui a servi à l'OTP WhatsApp. Sans ce fallback, le
          // lien acheteur↔paiement est cassé et le remboursement refusé à tort.
          if (!userPhoneNorm) {
            try {
              const authUser = await admin.auth().getUser(p.userId);
              userPhoneNorm = omNormalizeMsisdn(authUser.phoneNumber || '');
            } catch (_) {}
          }
        }
        if (buyerNorm !== payNorm && buyerNorm !== omNorm && buyerNorm !== userPhoneNorm) continue;
        // Montant exact (±0.001)
        const expected = parseFloat(p.omAmount || p.amount || 0);
        if (Math.abs(creditAmount - expected) > 0.001) continue;
        candidates.push({ id: doc.id, data: p, opDate });
      }

      if (candidates.length === 0) {
        console.warn(`[directOrangeCredit] ⛔ Aucun achat correspondant: buyer=${buyerNorm} amount=${creditAmount}`);
        res.status(400).json({
          error: 'Remboursement refusé : aucun achat confirmé de ce montant trouvé pour ce numéro dans les dernières 72h (ou déjà remboursé).',
        });
        return;
      }

      // Plusieurs achats identiques → rembourser le plus récent
      candidates.sort((a, b) => b.opDate - a.opDate);
      const matched = candidates[0];
      const payRef = db.collection('payments').doc(matched.id);

      // 🆕 RÈGLE 4 : RÉVOQUER LES CRÉDITS D'ABORD — si échec, pas de remboursement.
      let revokedList = [];
      try {
        revokedList = await revokeCreditsForPayment(matched.id, 'remboursement_direct_admin');
        revokedListOuter = revokedList;
      } catch (revokeErr) {
        console.error('[directOrangeCredit] ⛔ Échec révocation crédits — remboursement ANNULÉ:', revokeErr);
        res.status(500).json({
          error: 'Révocation des crédits impossible — remboursement annulé par sécurité. Réessayez.',
        });
        return;
      }

      // 3. transactionId unique — préfixe 'refund-' pour le routage webhook,
      //    tirets uniquement (pattern Orange, jamais de '_')
      const refundId = `refund-direct-${Date.now()}`;

      const creditBody = {
        peerId: msisdn,
        peerIdType: 'msisdn',
        amount: creditAmount,
        currency: env.currency,
        transactionId: refundId,
      };

      console.log(`[directOrangeCredit] admin=${adminId} msisdn=${msisdn} amount=${creditAmount} refundId=${refundId} paymentId=${matched.id} revoked=${revokedList.length}`);

      // 4. POST /{country}/credit
      const omResp = await orangeApiCall({
        method: 'POST',
        path: omCreditPath(),
        body: creditBody,
      });

      console.log(`[directOrangeCredit] Orange HTTP ${omResp.status}:`, JSON.stringify(omResp.body));

      if (omResp.status === 202) {
        const respBody = omResp.body || {};
        let isImmediate = respBody.status === 'SUCCESS';
        let isFailed = false;
        let omTxnId = (respBody.transactionData || {}).txnId || '';
        let failMessage = '';

        // ⚠️ FIX: si le 202 dit PENDING, poller la Status API (~2,5s) —
        // le CREDIT aboutit quasi immédiatement; sans ce polling le doc
        // resterait bloqué 'pending' (cas refund-direct-1787083866992).
        if (!isImmediate) {
          const polled = await pollCreditFinalStatus(refundId);
          if (polled.finalStatus === 'SUCCESS') {
            isImmediate = true;
            omTxnId = polled.txnId || omTxnId;
          } else if (polled.finalStatus === 'FAILED') {
            isFailed = true;
            failMessage = polled.message || 'Remboursement refusé par Orange';
          }
        }

        // 🆕 Orange a REFUSÉ → restaurer les crédits révoqués (rollback)
        if (isFailed && revokedList.length > 0) {
          await unrevokeCredits(revokedList);
        }

        // Doc de suivi (collection refunds — le webhook le retrouvera par refundId)
        await db.collection('refunds').doc(refundId).set({
          id: refundId,
          paymentId: matched.id,                // 🆕 paiement lié retrouvé par le système
          type: 'direct',
          userId: matched.data.userId ?? null,
          msisdn,
          buyerPhoneNumber: buyerNorm,          // 🆕 traçabilité: compte acheteur vérifié
          creditsRevoked: revokedList.map((r) => r.id), // 🆕 traçabilité révocation
          amount: creditAmount,
          currency: env.currency,
          status: isImmediate ? 'confirmed' : (isFailed ? 'failed' : 'pending'),
          reason: reason || null,
          adminId,
          adminName: adminName || '',
          createdAt: new Date().toISOString(),
          ...(isImmediate ? { confirmedAt: new Date().toISOString(), omTxnId } : {}),
          ...(isFailed ? { failedAt: new Date().toISOString(), failureReason: failMessage } : {}),
        });

        // 🆕 Marquer le paiement remboursé → empêche tout double remboursement
        await payRef.update({
          refundStatus: isImmediate ? 'refunded' : (isFailed ? 'failed' : 'pending'),
          refundId,
          refundAmount: creditAmount,
          refundReason: reason || null,
          refundRequestedAt: new Date().toISOString(),
          refundRequestedBy: adminName || adminId,
          ...(isImmediate ? { refundedAt: new Date().toISOString() } : {}),
        });

        // ⚠️ FIX message: compter les CRÉDITS révoqués (somme des remaining),
        // pas le nombre de documents (1 doc peut contenir 33 crédits).
        const totalCreditsRevoked = revokedList.reduce((s, r) => s + (r.remaining || 0), 0);
        res.status(200).json({
          success: !isFailed,
          refundId,
          paymentId: matched.id,
          creditsRevoked: totalCreditsRevoked,
          refundStatus: isImmediate ? 'refunded' : (isFailed ? 'failed' : 'pending'),
          amount: creditAmount,
          currency: env.currency,
          ...(isFailed ? { error: failMessage } : {}),
          message: isImmediate
            ? `Remboursement de ${creditAmount} ${env.currency} envoyé au ${msisdn} — ${totalCreditsRevoked} crédit(s) révoqué(s) du compte acheteur`
            : (isFailed ? failMessage : 'Remboursement initié — confirmation Orange en attente'),
        });
        return;
      }

      // 🆕 Orange a rejeté la requête → restaurer les crédits révoqués (rollback)
      if (revokedList.length > 0) await unrevokeCredits(revokedList);
      const errorMsg = orangeErrorMessage(omResp.body, omResp.status);
      console.error('[directOrangeCredit] Orange error:', omResp.status, JSON.stringify(omResp.body));
      res.status(200).json({
        success: false,
        retryable: omResp.status === 429,
        error: errorMsg,
      });

    } catch (err) {
      console.error('[directOrangeCredit] Exception:', err);
      // 🆕 Crash après révocation → restaurer les crédits (le webhook re-révoquera
      // si Orange confirme finalement le remboursement)
      if (revokedListOuter.length > 0) await unrevokeCredits(revokedListOuter);
      res.status(500).json({ success: false, error: err.message });
    }
  }
);

// ─── Révoquer les crédits associés à un paiement remboursé ─────────────────────
// ⚠️ Deux formats d'ID coexistent en prod :
//   - `credit_<paymentId>`                (crédit auto serveur — creditUserAfterPayment)
//   - `credit_<paymentId>_<timestamp>`    (validation manuelle admin côté app)
// → requête par PLAGE d'ID (préfixe) pour couvrir les deux.
// Retourne la liste des docs révoqués (pour rollback éventuel) ; throw si échec.
async function revokeCreditsForPayment(paymentId, reason = 'remboursement_orange_money') {
  const prefix = `credit_${paymentId}`;
  const snap = await db.collection('credits')
    .where(admin.firestore.FieldPath.documentId(), '>=', prefix)
    .where(admin.firestore.FieldPath.documentId(), '<=', prefix + '\uf8ff')
    .get();

  const revoked = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.revoked === true) continue; // déjà révoqué (idempotent)
    await doc.ref.update({
      remainingBeforeRevoke: d.remaining ?? 0, // pour rollback
      remaining: 0,
      revoked: true,
      revokedAt: new Date().toISOString(),
      revokedReason: reason,
    });
    revoked.push({ id: doc.id, remaining: d.remaining ?? 0 });
    console.log(`[revokeCredits] ✅ ${doc.id} révoqué (remaining ${d.remaining ?? 0} → 0)`);
  }
  if (snap.empty) {
    console.warn(`[revokeCredits] Aucun doc crédit trouvé pour ${paymentId} (préfixe ${prefix})`);
  }
  return revoked;
}

// Rollback : restaurer les crédits révoqués si le remboursement Orange échoue ensuite
async function unrevokeCredits(revokedList) {
  for (const item of revokedList) {
    try {
      await db.collection('credits').doc(item.id).update({
        remaining: item.remaining,
        revoked: false,
        revokedAt: null,
        revokedReason: null,
        unrevokedAt: new Date().toISOString(),
      });
      console.log(`[unrevokeCredits] ↩️ ${item.id} restauré (remaining=${item.remaining})`);
    } catch (e) {
      console.error(`[unrevokeCredits] ÉCHEC restauration ${item.id}:`, e.message);
    }
  }
}

// Compat : ancien nom utilisé par le webhook (révocation après confirmation asynchrone)
async function revokeCreditsAfterRefund(paymentId) {
  try {
    await revokeCreditsForPayment(paymentId);
  } catch (e) {
    console.warn('[revokeCredits] Échec révocation:', e.message);
  }
}

// ─── Traiter la notification callback d'un remboursement (credit) ──────────────
async function processRefundNotification(refundId, transactionStatus, { omTransactionId, executionDate, failureReason }) {
  const refundRef = db.collection('refunds').doc(refundId);
  const refundDoc = await refundRef.get();
  if (!refundDoc.exists) {
    console.warn(`[refundWebhook] Refund ${refundId} introuvable dans Firestore`);
    return;
  }
  const refund = refundDoc.data();
  if (refund.status === 'confirmed' || refund.status === 'failed') {
    console.log(`[refundWebhook] Refund ${refundId} déjà traité (${refund.status})`);
    return;
  }

  // Remboursement 'direct' (dashboard admin): pas de paiement lié → payRef null
  const payRef = refund.paymentId ? db.collection('payments').doc(refund.paymentId) : null;

  if (transactionStatus === 'SUCCESS') {
    await refundRef.update({
      status: 'confirmed',
      confirmedAt: new Date().toISOString(),
      omTxnId: omTransactionId || '',
      omExecutionDate: executionDate || '',
    });
    if (payRef) {
      await payRef.update({
        refundStatus: 'refunded',
        refundedAt: new Date().toISOString(),
      });
      await revokeCreditsAfterRefund(refund.paymentId);
    }

    // Notifier le client remboursé (FCM, best-effort — seulement si userId connu)
    try {
      if (refund.userId) {
        const userDoc = await db.collection('users').doc(refund.userId).get();
        const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;
        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: '💸 Remboursement effectué — ImmoZone',
              body: `${refund.amount} ${refund.currency} remboursé(s) sur votre compte Orange Money`,
            },
            data: { refundId, paymentId: refund.paymentId || '', status: 'refunded' },
          });
        }
      }
    } catch (e) {
      console.warn('[refundWebhook] FCM notification failed:', e.message);
    }
    console.log(`[refundWebhook] ✅ Refund ${refundId} CONFIRMED`);

  } else if (transactionStatus === 'FAILED') {
    await refundRef.update({
      status: 'failed',
      failedAt: new Date().toISOString(),
      failureReason: failureReason || 'Remboursement Orange Money échoué',
    });
    if (payRef) await payRef.update({ refundStatus: 'failed' });
    console.log(`[refundWebhook] ❌ Refund ${refundId} FAILED: ${failureReason}`);
  } else {
    console.log(`[refundWebhook] Status inconnu pour ${refundId}: ${transactionStatus} — ignoré`);
  }
}

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

// ═══════════════════════════════════════════════════════════════════════════════
// WHATSAPP OTP — Authentification par code via WhatsApp Business Cloud API (Meta)
// Remplace l'OTP SMS Firebase (bloqué par Play Integrity sur la version Play Store).
// Flux: sendWhatsAppOtp → code 6 chiffres → template WhatsApp → verifyWhatsAppOtp
//       → custom token Firebase → signInWithCustomToken côté Flutter.
// ─────────────────────────────────────────────────────────────────────────────
// ⚠️ TEMPLATE PROVISOIRE (entreprise Meta non vérifiée → catégorie AUTHENTICATION
//    indisponible) : on utilise le template UTILITY 'immozone_reference' dont la
//    variable {{1}} porte le code. Après vérification de l'entreprise :
//    1) créer le template AUTHENTICATION 'immozone_otp' (bouton Copy code)
//    2) passer templateName: 'immozone_otp' et templateCategory: 'AUTHENTICATION'
// ═══════════════════════════════════════════════════════════════════════════════
const WHATSAPP_CONFIG = {
  apiHost: 'graph.facebook.com',
  apiVersion: 'v21.0',
  phoneNumberId: '1344165878774630',      // Numéro Immozone +243 982 527 498
  wabaId: '1604739647744226',
  templateName: 'immozone_reference',     // → 'immozone_otp' après vérif entreprise
  templateLanguage: 'fr',
  // 'UTILITY'        → code injecté dans la variable {{1}} du BODY
  // 'AUTHENTICATION' → code dans BODY {{1}} + paramètre du bouton Copy code
  templateCategory: 'UTILITY',
  otpLength: 6,
  otpTtlMinutes: 5,
  maxVerifyAttempts: 5,
  maxSendsPerWindow: 3,                   // anti-abus: 3 envois max…
  sendWindowMinutes: 15,                  // …par fenêtre de 15 min par numéro
};

function getWhatsAppToken() {
  return (process.env.WHATSAPP_TOKEN || '').trim();
}

/** Normalise un numéro RDC vers le format international sans '+' (243XXXXXXXXX). */
function waNormalizeMsisdn(phoneNumber) {
  let m = String(phoneNumber || '').replace(/[\s\-]/g, '').replace(/^\+/, '');
  if (m.startsWith('0') && m.length === 10) m = '243' + m.slice(1);
  else if (m.length === 9 && !m.startsWith('243')) m = '243' + m;
  return m;
}

function hashOtp(code, msisdn) {
  return require('crypto').createHash('sha256').update(`${code}:${msisdn}:immozone-otp`).digest('hex');
}

/** Appel HTTPS Graph API (POST JSON). */
function waApiRequest(path, payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload);
    const req = https.request({
      hostname: WHATSAPP_CONFIG.apiHost,
      path: `/${WHATSAPP_CONFIG.apiVersion}${path}`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${getWhatsAppToken()}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let data = '';
      res.on('data', (c) => data += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, json: JSON.parse(data) }); }
        catch (e) { resolve({ status: res.statusCode, json: { raw: data } }); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

/** Construit le payload template selon la catégorie (UTILITY vs AUTHENTICATION). */
function buildOtpTemplatePayload(msisdn, code) {
  const components = [
    { type: 'body', parameters: [{ type: 'text', text: code }] },
  ];
  if (WHATSAPP_CONFIG.templateCategory === 'AUTHENTICATION') {
    // Le bouton Copy code exige le code en paramètre d'URL du bouton (index 0)
    components.push({
      type: 'button', sub_type: 'url', index: '0',
      parameters: [{ type: 'text', text: code }],
    });
  }
  return {
    messaging_product: 'whatsapp',
    to: msisdn,
    type: 'template',
    template: {
      name: WHATSAPP_CONFIG.templateName,
      language: { code: WHATSAPP_CONFIG.templateLanguage },
      components,
    },
  };
}

/**
 * sendWhatsAppOtp — POST {phoneNumber}
 * Génère un code 6 chiffres, le stocke hashé (TTL 5 min), l'envoie via WhatsApp.
 */
exports.sendWhatsAppOtp = onRequest(
  { region: 'us-central1', cors: true, secrets: ['WHATSAPP_TOKEN'] },
  async (req, res) => {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST requis' });
    try {
      const { phoneNumber } = req.body || {};
      if (!phoneNumber) return res.status(400).json({ error: 'phoneNumber requis' });

      const msisdn = waNormalizeMsisdn(phoneNumber);
      if (!/^243[0-9]{9}$/.test(msisdn)) {
        return res.status(400).json({ error: 'Numéro invalide. Format attendu: 0XXXXXXXXX ou +243XXXXXXXXX' });
      }

      const otpRef = db.collection('whatsapp_otp').doc(msisdn);
      const now = Date.now();

      // Anti-abus: fenêtre glissante d'envois
      const snap = await otpRef.get();
      if (snap.exists) {
        const d = snap.data();
        const windowStart = now - WHATSAPP_CONFIG.sendWindowMinutes * 60000;
        const recentSends = (d.sendTimestamps || []).filter((t) => t > windowStart);
        if (recentSends.length >= WHATSAPP_CONFIG.maxSendsPerWindow) {
          const retryInSec = Math.ceil((recentSends[0] + WHATSAPP_CONFIG.sendWindowMinutes * 60000 - now) / 1000);
          return res.status(429).json({
            error: `Trop de demandes. Réessayez dans ${Math.ceil(retryInSec / 60)} min.`,
            retryAfterSeconds: retryInSec,
          });
        }
      }

      // Génération du code (6 chiffres, crypto-aléatoire)
      const code = String(require('crypto').randomInt(0, 10 ** WHATSAPP_CONFIG.otpLength)).padStart(WHATSAPP_CONFIG.otpLength, '0');

      // Envoi WhatsApp
      const wa = await waApiRequest(`/${WHATSAPP_CONFIG.phoneNumberId}/messages`, buildOtpTemplatePayload(msisdn, code));
      if (wa.status !== 200 || wa.json.error) {
        console.error('sendWhatsAppOtp WA error:', JSON.stringify(wa.json));
        const waErr = (wa.json.error || {});
        // 131026 = numéro sans WhatsApp / non joignable
        const friendly = waErr.code === 131026
          ? 'Ce numéro ne semble pas avoir WhatsApp.'
          : 'Envoi WhatsApp impossible. Réessayez plus tard.';
        return res.status(502).json({ error: friendly, waCode: waErr.code || null });
      }

      // Stockage hashé (jamais le code en clair)
      const prevTimestamps = snap.exists ? (snap.data().sendTimestamps || []) : [];
      await otpRef.set({
        codeHash: hashOtp(code, msisdn),
        expiresAt: new Date(now + WHATSAPP_CONFIG.otpTtlMinutes * 60000).toISOString(),
        attempts: 0,
        verified: false,
        sendTimestamps: [...prevTimestamps.filter((t) => t > now - 3600000), now],
        waMessageId: (wa.json.messages && wa.json.messages[0] && wa.json.messages[0].id) || null,
        updatedAt: new Date(now).toISOString(),
      });

      console.log(`sendWhatsAppOtp: code envoyé à ${msisdn} (msg ${(wa.json.messages || [{}])[0].id})`);
      return res.json({ success: true, expiresInSeconds: WHATSAPP_CONFIG.otpTtlMinutes * 60 });
    } catch (err) {
      console.error('sendWhatsAppOtp error:', err);
      return res.status(500).json({ error: 'Erreur interne' });
    }
  }
);

/**
 * verifyWhatsAppOtp — POST {phoneNumber, code}
 * Vérifie le code; si OK → custom token Firebase (uid lié au numéro de téléphone).
 */
exports.verifyWhatsAppOtp = onRequest(
  { region: 'us-central1', cors: true },
  async (req, res) => {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST requis' });
    try {
      const { phoneNumber, code } = req.body || {};
      if (!phoneNumber || !code) return res.status(400).json({ error: 'phoneNumber et code requis' });

      const msisdn = waNormalizeMsisdn(phoneNumber);
      const otpRef = db.collection('whatsapp_otp').doc(msisdn);
      const snap = await otpRef.get();
      if (!snap.exists) return res.status(400).json({ error: 'Aucun code demandé pour ce numéro.' });

      const d = snap.data();
      if (d.verified) return res.status(400).json({ error: 'Code déjà utilisé. Demandez-en un nouveau.' });
      if (new Date(d.expiresAt).getTime() < Date.now()) {
        return res.status(400).json({ error: 'Code expiré. Demandez-en un nouveau.' });
      }
      if ((d.attempts || 0) >= WHATSAPP_CONFIG.maxVerifyAttempts) {
        return res.status(429).json({ error: 'Trop de tentatives. Demandez un nouveau code.' });
      }

      if (hashOtp(String(code).trim(), msisdn) !== d.codeHash) {
        await otpRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
        const remaining = WHATSAPP_CONFIG.maxVerifyAttempts - (d.attempts || 0) - 1;
        return res.status(400).json({ error: 'Code incorrect.', attemptsRemaining: remaining });
      }

      // Code valide → usage unique
      await otpRef.update({ verified: true, verifiedAt: new Date().toISOString() });

      // Utilisateur Firebase: réutilise l'uid existant (créé par l'ancien Phone Auth)
      // ou en crée un nouveau avec ce numéro.
      const e164 = '+' + msisdn;
      let user;
      try {
        user = await admin.auth().getUserByPhoneNumber(e164);
      } catch (e) {
        user = await admin.auth().createUser({ phoneNumber: e164 });
        console.log(`verifyWhatsAppOtp: nouvel utilisateur créé ${user.uid} (${e164})`);
      }

      const customToken = await admin.auth().createCustomToken(user.uid, { authMethod: 'whatsapp_otp' });
      console.log(`verifyWhatsAppOtp: connexion OK ${user.uid} (${e164})`);
      return res.json({ success: true, token: customToken, uid: user.uid, isNewUser: !user.metadata || user.metadata.creationTime === user.metadata.lastSignInTime });
    } catch (err) {
      console.error('verifyWhatsAppOtp error:', err);
      return res.status(500).json({ error: 'Erreur interne' });
    }
  }
);
