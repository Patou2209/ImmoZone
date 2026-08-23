# ImmoZone — Guide de test Postman : API Orange Money Business

> **Objectif** : tester de bout en bout l'intégration Orange Money Business (encaissement WITHDRAW + remboursement CREDIT) en **sandbox**, depuis l'obtention des clés jusqu'à la dernière requête.
>
> - **Projet** : ImmoZone (Flutter + Firebase) — https://immozone.pro
> - **API** : Orange Money Business API v1.0 — `https://api.orange.com/om_partner_api/v1`
> - **Contrat souscrit** : services **Withdraw** (encaissement) + **Credit** (remboursement). Le service *Debit* n'est **pas** souscrit (→ erreur 70 si utilisé).
> - **Collection Postman prête à l'emploi** : voir `ImmoZone_OrangeMoney.postman_collection.json` (ou le lien fourni précédemment).

---

## Sommaire

1. [Étape 0 — Obtenir les clés (Orange Developer)](#étape-0--obtenir-les-clés-orange-developer)
2. [Étape 1 — Configurer le secret Firebase](#étape-1--configurer-le-secret-firebase)
3. [Étape 2 — Préparer Postman (variables)](#étape-2--préparer-postman-variables)
4. [Étape 3 — Obtenir le Bearer token OAuth2](#étape-3--obtenir-le-bearer-token-oauth2)
5. [Étape 4 — Encaissement direct (WITHDRAW, API Orange)](#étape-4--encaissement-direct-withdraw-api-orange)
6. [Étape 5 — Vérifier le statut d'une transaction](#étape-5--vérifier-le-statut-dune-transaction)
7. [Étape 6 — Remboursement direct (CREDIT, API Orange)](#étape-6--remboursement-direct-credit-api-orange)
8. [Étape 7 — Tester via les Cloud Functions ImmoZone](#étape-7--tester-via-les-cloud-functions-immozone)
9. [Étape 8 — Simuler le webhook Orange](#étape-8--simuler-le-webhook-orange)
10. [Étape 9 — Vérifier les données dans Firestore](#étape-9--vérifier-les-données-dans-firestore)
11. [Pièges connus (à lire absolument)](#pièges-connus-à-lire-absolument)
12. [Passage en production](#passage-en-production)

---

## Étape 0 — Obtenir les clés (Orange Developer)

### 0.1 Créer le compte et l'application

1. Aller sur **https://developer.orange.com** et créer un compte (email + validation).
2. Menu **My apps** → **Create a new app** :
   - **Name** : `Immozone`
   - **Description** : paiement des crédits de publication d'annonces immobilières
3. Une fois l'app créée, ouvrir sa page : vous y trouvez les 3 valeurs clés :

| Clé | Où la trouver | À quoi elle sert |
|---|---|---|
| **Client ID** | Page de l'app | Identifiant OAuth2 |
| **Client secret** | Page de l'app (bouton *Show*) | Secret OAuth2 |
| **Authorization header** | Page de l'app — chaîne `Basic xxxxx...` | La version encodée base64 de `client_id:client_secret`, prête à l'emploi |

> 💡 **C'est l'« Authorization header » qui nous intéresse** : c'est lui qu'on utilise pour obtenir le Bearer token. Il vaut `Basic base64(client_id:client_secret)`.

### 0.2 Souscrire à l'API Orange Money Business

1. Catalogue d'API → **Orange Money Business** → **Subscribe** avec l'app `Immozone`.
2. Lors de la souscription, Orange demande **2 informations de callback** (déclarées une seule fois) :

| Champ demandé | Valeur déclarée pour ImmoZone |
|---|---|
| **Callback URL** (base, sans `/notifications`) | `https://us-central1-immozone-d9a68.cloudfunctions.net/orangeMoneyWebhook` |
| **Authorization header** (que Orange enverra à CHAQUE callback) | `Basic aW1tb3pvbmUtY2FsbGJhY2s6ZTNhZ2Z5OFBDS0pBalh1bmJHbm8wUk80OG40ZFNy` <br>*(= `immozone-callback:e3agfy8PCKJAjXunbGno0RO48n4dSr` en base64)* |

3. Orange lance alors **3 tests automatiques** sur `{callbackUrl}/orangeMoneyProvTest` (vérifie que le webhook répond 200 avec la bonne auth, 401 sans). Notre webhook les gère déjà.
4. Après validation, Orange envoie un **email d'activation** contenant le **MSISDN de test sandbox** : pour nous → **`7704100021`**.

### 0.3 Paramètres sandbox reçus

| Paramètre | Valeur sandbox |
|---|---|
| Pays (`country`) | `sx` |
| Devise | `OUV` (obligatoire en sandbox) |
| Montants | **ENTIERS uniquement** (pas de décimales) |
| MSISDN de test | `7704100021` |

---

## Étape 1 — Configurer le secret Firebase

Le code des Cloud Functions lit les credentials OAuth via le secret **`ORANGE_OAUTH_BASIC`** (jamais en dur dans le code).

```bash
# Valeur = la chaîne base64 SANS le préfixe "Basic "
firebase functions:secrets:set ORANGE_OAUTH_BASIC
# → coller la chaîne base64 de l'Authorization header de l'app Orange

# Vérifier
firebase functions:secrets:access ORANGE_OAUTH_BASIC

# Redéployer les fonctions qui l'utilisent
cd functions && firebase deploy --only functions
```

---

## Étape 2 — Préparer Postman (variables)

Créer un **Environment** Postman `ImmoZone Sandbox` avec ces variables :

| Variable | Valeur | Note |
|---|---|---|
| `om_host` | `https://api.orange.com` | |
| `om_base` | `{{om_host}}/om_partner_api/v1` | |
| `country` | `sx` | sandbox |
| `currency` | `OUV` | sandbox |
| `msisdn_test` | `7704100021` | MSISDN sandbox |
| `oauth_basic` | `Basic <votre chaîne base64>` | Authorization header de l'app Orange |
| `bearer_token` | *(vide — rempli à l'étape 3)* | |
| `cf_base` | `https://us-central1-immozone-d9a68.cloudfunctions.net` | Cloud Functions |
| `webhook_auth` | `Basic aW1tb3pvbmUtY2FsbGJhY2s6ZTNhZ2Z5OFBDS0pBalh1bmJHbm8wUk80OG40ZFNy` | Auth callback |
| `admin_uid` | `2oJTIYVNS6gAZPTrO2pCiCldmYV2` | UID admin Firestore |

---

## Étape 3 — Obtenir le Bearer token OAuth2

**Le token est valide 1 h.** À refaire quand il expire (les Cloud Functions le font automatiquement, avec cache + retry sur 401).

### Requête

```
POST https://api.orange.com/oauth/v3/token
```

**Headers :**

| Header | Valeur |
|---|---|
| `Authorization` | `{{oauth_basic}}` (ex : `Basic TGl2ZU...xyz=`) |
| `Content-Type` | `application/x-www-form-urlencoded` |
| `Accept` | `application/json` |

**Body** (x-www-form-urlencoded) :

| Clé | Valeur |
|---|---|
| `grant_type` | `client_credentials` |

### Réponse attendue — `200 OK`

```json
{
  "token_type": "Bearer",
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9...",
  "expires_in": 3600
}
```

➡️ **Copier `access_token` dans la variable Postman `bearer_token`.**

**Erreurs possibles :**
- `401 invalid_client` → l'`Authorization` header est faux (vérifier la base64, le préfixe `Basic `).

---

## Étape 4 — Encaissement direct (WITHDRAW, API Orange)

> Le **WITHDRAW** = le client paie le marchand (client → ImmoZone). En sandbox il n'y a pas de saisie de PIN réelle : Orange répond `202` puis envoie la notification finale sur notre webhook.

### Requête

```
POST {{om_base}}/{{country}}/withdraw
→ POST https://api.orange.com/om_partner_api/v1/sx/withdraw
```

**Headers :**

| Header | Valeur |
|---|---|
| `Authorization` | `Bearer {{bearer_token}}` |
| `Content-Type` | `application/json` |
| `Accept` | `application/json` |

**Body (raw JSON) :**

```json
{
  "peerId": "7704100021",
  "peerIdType": "msisdn",
  "amount": 19,
  "currency": "OUV",
  "transactionId": "pay-test-1787088337459"
}
```

⚠️ **Règles STRICTES sur le body :**

| Champ | Règle |
|---|---|
| `peerIdType` | `msisdn` en **minuscules** (sinon erreur) |
| `amount` | **ENTIER** en sandbox (13 ✅, 13.5 ❌) |
| `currency` | `OUV` obligatoire en sandbox |
| `transactionId` | **Unique, jamais réutilisé**, **PAS d'underscore `_`** (erreur 24 — tirets `-` uniquement), **longueur < ~30 caractères** (sinon → *"Invalid body field"*) |

### Réponse attendue — `202 Accepted`

```json
{
  "transactionId": "pay-test-1787088337459",
  "status": "PENDING"
}
```

➡️ La transaction est **PENDING**. Le statut final (`SUCCESSFUL`/`FAILED`) arrive :
- soit par **notification webhook** (voir Étape 8 — en sandbox Orange l'envoie après quelques secondes/minutes),
- soit en interrogeant la **Status API** (Étape 5).

**Erreurs fréquentes :**

| Réponse | Cause | Solution |
|---|---|---|
| `Invalid body field` | `transactionId` trop long, underscore, `peerIdType` mal casé, montant décimal | Corriger le body |
| `FAILED` + *"opération identique"* | **Anti-doublon Orange** : même montant + même msisdn dans les ~5 dernières minutes | Changer le montant OU attendre 5 min |
| Erreur 70 | Service non souscrit (ex : `debit`) | Utiliser `withdraw` |
| `401` | Token expiré | Refaire l'Étape 3 |

---

## Étape 5 — Vérifier le statut d'une transaction

### Requête

```
GET {{om_base}}/{{country}}/withdraw/transactions/{transactionId}
→ GET https://api.orange.com/om_partner_api/v1/sx/withdraw/transactions/pay-test-1787088337459
```

*(pour un remboursement : remplacer `withdraw` par `credit` dans le chemin)*

**Headers :** `Authorization: Bearer {{bearer_token}}`, `Accept: application/json`

### Réponse attendue — `200 OK`

```json
{
  "transactionId": "CI260818.2331.A02520",
  "requestId": "pay-test-1787088337459",
  "status": "SUCCESSFUL",
  "peerId": "7704100021",
  "amount": 13,
  "currency": "OUV",
  "executionDate": "2026-08-18 23:31:12"
}
```

| `status` | Signification |
|---|---|
| `PENDING` | En attente (client n'a pas encore validé / traitement en cours) |
| `SUCCESSFUL` | Payé ✅ |
| `FAILED` | Échoué (PIN refusé, solde insuffisant, anti-doublon...) |

---

## Étape 6 — Remboursement direct (CREDIT, API Orange)

> Le **CREDIT** = le marchand renvoie de l'argent au client (ImmoZone → client). Quasi immédiat (pas de PIN client).

### Requête

```
POST {{om_base}}/{{country}}/credit
→ POST https://api.orange.com/om_partner_api/v1/sx/credit
```

**Headers :** identiques à l'Étape 4.

**Body (raw JSON) :**

```json
{
  "peerId": "7704100021",
  "peerIdType": "msisdn",
  "amount": 13,
  "currency": "OUV",
  "transactionId": "refund-1787088692392-r9wt"
}
```

⚠️ Le `transactionId` de remboursement doit être **NOUVEAU** (jamais celui du paiement d'origine), format court `refund-<timestamp>-<4car>` (~25 caractères).

### Réponse attendue — `202 Accepted` puis `SUCCESSFUL` en quelques secondes

Vérifier avec : `GET {{om_base}}/{{country}}/credit/transactions/refund-1787088692392-r9wt`

---

## Étape 7 — Tester via les Cloud Functions ImmoZone

> C'est le **vrai flux applicatif** : les Cloud Functions gèrent OAuth, retry 401, écriture Firestore, notifications push, polling post-202, etc.

Base : `{{cf_base}}` = `https://us-central1-immozone-d9a68.cloudfunctions.net`

### 7.1 `initiateOrangePayment` — lancer un encaissement

```
POST {{cf_base}}/initiateOrangePayment
Content-Type: application/json
```

```json
{
  "paymentId": "pay-test-1787099999999",
  "phoneNumber": "7704100021",
  "amount": 17,
  "currency": "OUV",
  "userId": "2oJTIYVNS6gAZPTrO2pCiCldmYV2"
}
```

| Champ | Note |
|---|---|
| `paymentId` | Unique, format `pay-<timestamp>`, **sans underscore** |
| `phoneNumber` | msisdn (les `+`, espaces, tirets sont nettoyés automatiquement) |
| `amount` | Arrondi à l'entier automatiquement en sandbox |
| `userId` | UID Firestore du client (le doc `payments/{paymentId}` doit exister avec `creditsQty` pour créditer après confirmation) |

**Réponse `200`** :
```json
{ "success": true, "status": "PENDING", "transactionId": "pay-test-1787099999999" }
```

La fonction écrit dans Firestore `payments/{paymentId}` : `status: "pending"`, `omCurrency`, etc.

### 7.2 `checkOrangePaymentStatus` — vérifier/synchroniser le statut

```
GET {{cf_base}}/checkOrangePaymentStatus?paymentId=pay-test-1787099999999
```

**Réponse `200`** :
```json
{ "transactionStatus": "SUCCESSFUL", "source": "firestore" }
```
- `source: "firestore"` → le webhook a déjà traité la notification
- `source: "orange"` → statut lu en direct sur la Status API Orange (et synchronisé dans Firestore)

### 7.3 `refundOrangePayment` — rembourser un paiement confirmé (admin)

```
POST {{cf_base}}/refundOrangePayment
Content-Type: application/json
```

```json
{
  "paymentId": "pay-test-1787099999999",
  "adminId": "2oJTIYVNS6gAZPTrO2pCiCldmYV2",
  "adminName": "Patou",
  "reason": "Test remboursement Postman"
}
```

**Conditions vérifiées par la fonction (sinon `400`/`403`) :**
- `adminId` doit avoir `role: "admin"` dans `users/{adminId}`
- Le paiement doit être `status: "confirmed"` et `operator: "orange_money"`
- Pas déjà remboursé (`refundStatus` ≠ `pending`/`refunded`)

**Réponse `200` (cas nominal — polling post-202 confirme immédiatement) :**
```json
{
  "success": true,
  "status": "refunded",
  "refundId": "refund-1787088692392-r9wt",
  "omTransactionId": "CI260818.2331.A02520"
}
```

La fonction : génère un `refundId` court unique → `POST /sx/credit` → si `202`, **poll le statut 2× (2,5 s d'intervalle)** → écrit `refunds/{refundId}` + `payments/{paymentId}.refundStatus: "refunded"` + notification au client.

### 7.4 `directOrangeCredit` — crédit libre (dashboard admin)

Pour renvoyer un montant arbitraire vers n'importe quel numéro (sans paiement d'origine) :

```
POST {{cf_base}}/directOrangeCredit
Content-Type: application/json
```

```json
{
  "phoneNumber": "7704100021",
  "amount": 5,
  "adminId": "2oJTIYVNS6gAZPTrO2pCiCldmYV2",
  "adminName": "Patou",
  "reason": "Geste commercial test"
}
```

**Réponse `200`** : identique au 7.3 (avec `refundId` = `refund-direct-<timestamp>`).

---

## Étape 8 — Simuler le webhook Orange

> En sandbox, Orange envoie la vraie notification tout seul. Mais on peut la **simuler dans Postman** pour tester le traitement sans attendre.

```
POST {{cf_base}}/orangeMoneyWebhook/notifications
```

**Headers :**

| Header | Valeur |
|---|---|
| `Authorization` | `{{webhook_auth}}` ⚠️ **obligatoire** — sans lui → `401` |
| `Content-Type` | `application/json` |

**Body (format exact envoyé par Orange — VÉRIFIÉ EN LIVE le 19/08/2026) :**

```json
{
  "status": "SUCCESS",
  "message": "Transaction completed",
  "transactionData": {
    "transactionId": "pay-test-1787099999999",
    "txnId": "CI260818.2331.A02520",
    "type": "withdraw",
    "peerId": "7704100021",
    "amount": 17,
    "currency": "OUV",
    "executionDate": "2026-08-18 23:31:12",
    "country": "sx"
  }
}
```

**Champs importants :**
- `status` (racine) : `"SUCCESS"` ou `"FAILED"` — c'est CE champ que le webhook lit
- `transactionData.transactionId` : **NOTRE** identifiant (`pay-...` / `refund-...`)
- `transactionData.txnId` : l'identifiant **Orange** (ex: `CI260818.2331.A02520`)

> ⚠️ **Attention** : un body au mauvais format (ex: `{"notificationType": ..., "transaction": {...}}`)
> renvoie quand même `200` mais en ~0,1 s et **ne traite RIEN** (aucun champ reconnu).
> Le bon format répond `200` en ~2–3 s avec traitement complet.

**Réponse attendue : `200 {"status":"OK"}`** (en ~2-3 s : le webhook **traite AVANT de répondre** — crédite l'utilisateur, met `payments/{id}.status: "confirmed"`, envoie la notif push).

**Routage automatique par préfixe du `transactionData.transactionId` :**
- `pay-...` → traité comme un **paiement** (withdraw)
- `refund-...` ou `refund_...` → traité comme un **remboursement** (credit)

**Test de l'auth :** renvoyer la même requête **sans** header `Authorization` → doit répondre `401`.

---

## Étape 9 — Vérifier les données dans Firestore

Les documents sont lisibles via l'API REST publique Firestore :

```
GET https://firestore.googleapis.com/v1/projects/immozone-d9a68/databases/(default)/documents/payments/pay-test-1787099999999
GET https://firestore.googleapis.com/v1/projects/immozone-d9a68/databases/(default)/documents/refunds/refund-1787088692392-r9wt
```

**Champs clés à vérifier après un flux complet :**

| Collection | Champ | Valeur attendue |
|---|---|---|
| `payments/{id}` | `status` | `pending` → `confirmed` (après webhook) |
| `payments/{id}` | `omTransactionId`, `omAmount`, `omPeerId` | Renseignés par le webhook |
| `payments/{id}` | `refundStatus` | `refunded` après remboursement |
| `refunds/{refundId}` | `status` | `confirmed` |
| `refunds/{refundId}` | `omTransactionId` | ID Orange réel (ex: `CI260818.2331.A02520`) |
| `credits/credit_{paymentId}` | `quantity`, `remaining` | Crédits ajoutés au compte client |

---

## Pièges connus (à lire absolument)

| # | Piège | Symptôme | Solution |
|---|---|---|---|
| 1 | **Anti-doublon Orange** | `FAILED` "opération identique" | Même montant + même msisdn interdits pendant ~5 min → **varier le montant à chaque test** (13, 17, 19, 23...) |
| 2 | **`transactionId` trop long** | `Invalid body field` | Rester sous ~30 caractères (`refund-<ts>-<4car>` ✅, `refund-<paymentId>-<ts>` ❌) |
| 3 | **Underscore dans `transactionId`** | Erreur 24 | Tirets `-` uniquement |
| 4 | **Réutilisation d'un `transactionId`** | Rejet | Toujours générer un nouvel ID (timestamp) |
| 5 | **Montant décimal en sandbox** | Rejet | Entiers uniquement (`13`, pas `13.5`) |
| 6 | **Devise ≠ OUV en sandbox** | Rejet | Toujours `OUV` en sandbox |
| 7 | **`peerIdType` en majuscules** | Rejet | `msisdn` en minuscules |
| 8 | **Token expiré (1 h)** | `401` | Refaire l'Étape 3 (les CF le font automatiquement) |
| 9 | **Webhook sans auth** | `401` | Header `Authorization: {{webhook_auth}}` obligatoire |
| 10 | **Service `debit`** | Erreur 70 | Non souscrit — utiliser `withdraw` |

---

## Passage en production

Dans `functions/index.js`, basculer :

```js
sandboxMode: false,   // → pays 'cd' (RDC), devise 'USD'
```

| Paramètre | Sandbox | Production |
|---|---|---|
| `country` | `sx` | `cd` (RDC) |
| `currency` | `OUV` | `USD` |
| Montants | Entiers | Décimaux acceptés (à confirmer avec Orange RDC) |
| MSISDN | `7704100021` | Vrais numéros Orange Money clients |
| Credentials | Mêmes clés | Clés **production** fournies par Orange après validation du contrat |

Puis redéployer : `cd functions && firebase deploy --only functions`

---

## Récapitulatif du flux complet (checklist de test)

- [ ] **1.** `POST /oauth/v3/token` → `200` + `access_token`
- [ ] **2.** `POST {{cf_base}}/initiateOrangePayment` (montant inédit) → `200 PENDING`
- [ ] **3.** Attendre la notification Orange OU simuler le webhook → `200 OK`
- [ ] **4.** `GET {{cf_base}}/checkOrangePaymentStatus?paymentId=...` → `SUCCESSFUL`
- [ ] **5.** Firestore : `payments/{id}.status == "confirmed"` + crédits ajoutés
- [ ] **6.** `POST {{cf_base}}/refundOrangePayment` → `200 refunded` + `omTransactionId`
- [ ] **7.** Firestore : `refunds/{refundId}.status == "confirmed"`, `payments/{id}.refundStatus == "refunded"`
- [ ] **8.** (Optionnel) `POST {{cf_base}}/directOrangeCredit` → crédit libre `200`

> ✅ Ce flux exact a été **validé en live le 18/08/2026** : withdraw 13 OUV confirmé via webhook (1 seul envoi suffit), remboursement 13 OUV confirmé immédiatement avec `omTransactionId: CI260818.2331.A02520`.

---

*Dernière mise à jour : 18/08/2026 — ImmoZone (Flutter + Firebase Cloud Functions + Orange Money Business API v1.0)*
