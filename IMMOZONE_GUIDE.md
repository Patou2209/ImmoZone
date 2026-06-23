# ImmoZone — Guide Complet de Déploiement & Maintenance

---

## Table des matières

1. [Keystore Android — Informations de signature](#1-keystore-android--informations-de-signature)
2. [Workflow de mise à jour — Web & Mobile](#2-workflow-de-mise-à-jour--web--mobile)
3. [GitHub Actions — Déploiement web automatique](#3-github-actions--déploiement-web-automatique)
4. [Domaine personnalisé GoDaddy → Firebase](#4-domaine-personnalisé-godaddy--firebase)
5. [Checklist mise en production — App Check](#5-checklist-mise-en-production--app-check)

---

## 1. Keystore Android — Informations de signature

> ⚠️ **CONFIDENTIEL** — Ne jamais committer ces informations dans le repo GitHub.

### Fichiers de signature

| Fichier | Chemin dans le projet |
|---|---|
| Keystore | `android/release-key.jks` |
| Propriétés | `android/key.properties` |

### Contenu de `android/key.properties`

```properties
storePassword=fADp^s0yOv3LFWFMiW!B
keyPassword=fADp^s0yOv3LFWFMiW!B
keyAlias=release
storeFile=../release-key.jks
```

### Empreintes du certificat (pour Firebase Console)

```
Alias     : release
Valide du : 01/05/2026 au 16/09/2053

SHA-1  :  34:75:38:85:E0:D4:09:7D:97:27:C9:A6:EE:B9:8F:76:27:B7:4C:FF

SHA-256:  F0:71:FA:93:72:D4:FA:88:A9:AA:29:F8:8E:F3:3A:8D:EF:0A:BC:BF:
          1F:D1:14:27:E6:B2:45:9C:9C:0E:D7:C8
```

### Infos keystore complètes

```
Owner  : CN=Flutter App, OU=Mobile Development, O=GenSpark,
         L=San Francisco, ST=California, C=US
Issuer : CN=Flutter App, OU=Mobile Development, O=GenSpark,
         L=San Francisco, ST=California, C=US
Algo   : SHA256withRSA
```

### Commande pour vérifier le keystore à tout moment

```bash
keytool -list -v \
  -keystore android/release-key.jks \
  -alias release \
  -storepass "fADp^s0yOv3LFWFMiW!B"
```

---

## 2. Workflow de mise à jour — Web & Mobile

### 2.1 Mise à jour Web (vous faites tout depuis VS Code)

```powershell
# Terminal VS Code — depuis C:\TECHNOWEB\ImmoZone

git add .
git commit -m "Description claire de la modification"
git push origin main

# ✅ C'est tout !
# GitHub Actions prend le relais automatiquement (~4 minutes) :
#   → flutter pub get
#   → flutter build web --release --pwa-strategy=none
#   → suppression flutter_service_worker.js
#   → firebase deploy
#   → https://immozone-d9a68.web.app mis à jour ✅
```

### 2.2 Surveiller le déploiement

```
https://github.com/Patou2209/ImmoZone/actions

✅ Cercle vert  = déploiement réussi, site mis à jour
❌ Cercle rouge = erreur (copier le log d'erreur et demander au sandbox)
🟡 Cercle jaune = en cours (~4 minutes)
```

### 2.3 Mise à jour Mobile APK/AAB (via le sandbox Genspark)

```
1. Décrire la modification au sandbox
2. Le sandbox applique les changements + génère l'APK
3. Télécharger le lien APK fourni
4. Pour le Play Store : demander un AAB (Android App Bundle)
```

**Commandes build mobile (sandbox les exécute) :**

```bash
# APK release (installation directe)
flutter build apk --release

# AAB release (Play Store)
flutter build appbundle --release

# Fichiers générés :
# APK → build/app/outputs/flutter-apk/app-release.apk
# AAB → build/app/outputs/bundle/release/app-release.aab
```

---

## 3. GitHub Actions — Déploiement web automatique

### Fichier workflow : `.github/workflows/deploy.yml`

```yaml
name: Build & Deploy ImmoZone Web

on:
  push:
    branches:
      - main
  workflow_dispatch:

jobs:
  build_and_deploy:
    name: Flutter Build + Firebase Deploy
    runs-on: ubuntu-latest
    timeout-minutes: 20

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.35.4'
          channel: 'stable'
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Build Flutter Web
        run: |
          flutter build web --release \
            --pwa-strategy=none \
            --dart-define=flutter.inspector.structuredErrors=false

      - name: Remove Service Worker
        run: rm -f build/web/flutter_service_worker.js

      - name: Deploy to Firebase Hosting
        uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: ${{ secrets.GITHUB_TOKEN }}
          firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          projectId: immozone-d9a68
          channelId: live
```

### Secret GitHub requis

```
GitHub → Settings → Secrets and variables → Actions → New repository secret

Nom    : FIREBASE_SERVICE_ACCOUNT
Valeur : contenu complet du fichier firebase-admin-sdk.json
```

### URLs de production

```
Web app    : https://immozone-d9a68.web.app
Console    : https://console.firebase.google.com/project/immozone-d9a68
Actions    : https://github.com/Patou2209/ImmoZone/actions
```

---

## 4. Domaine personnalisé GoDaddy → Firebase

### Étape 1 — Acheter le domaine chez GoDaddy

```
https://www.godaddy.com
→ Recherchez : immozone.cd  /  immozone.com  /  immo-zone.net
→ Achetez le domaine souhaité
```

### Étape 2 — Ajouter le domaine dans Firebase Console

```
1. https://console.firebase.google.com/project/immozone-d9a68/hosting
2. Cliquez "Add custom domain"
3. Entrez : www.votredomaine.com
4. Firebase vous fournit les enregistrements DNS à configurer
   (les valeurs IP ci-dessous sont indicatives — utilisez celles fournies par Firebase)
```

### Étape 3 — Configurer les DNS chez GoDaddy

```
GoDaddy → Mon compte → Mes domaines → Gérer DNS
→ Supprimer les enregistrements A existants (parking GoDaddy)
→ Ajouter les enregistrements fournis par Firebase :
```

| Type  | Nom  | Valeur                    | TTL  |
|-------|------|---------------------------|------|
| A     | @    | (IP fournie par Firebase) | 600  |
| A     | @    | (IP fournie par Firebase) | 600  |
| CNAME | www  | immozone-d9a68.web.app.   | 3600 |

> ⚠️ Les adresses IP exactes sont générées par Firebase au moment de l'ajout
> du domaine. Utilisez toujours les valeurs affichées dans la console Firebase.

### Étape 4 — Vérification et SSL automatique

```
→ Firebase vérifie les DNS automatiquement
→ Délai de propagation : 24 à 48 heures
→ Certificat SSL (HTTPS) généré automatiquement par Firebase — GRATUIT
→ Aucune configuration supplémentaire nécessaire
```

### Étape 5 — Redirection www ↔ domaine nu

```
Firebase Console → Hosting → Custom domains
→ Ajouter votredomaine.com (sans www) → rediriger vers www.votredomaine.com
   OU
→ Ajouter www.votredomaine.com → rediriger vers votredomaine.com
```

### Schéma complet

```
git push origin main
        │
        ▼
GitHub Actions (~4 min)
  flutter build web
  firebase deploy
        │
        ▼
Firebase Hosting
  https://immozone-d9a68.web.app  ←──┐
        │                            │ DNS CNAME
        ▼                            │
  https://www.immozone.cd  ──────────┘
  (SSL automatique Firebase)
        │
        ▼ DNS A records (GoDaddy)
  Serveurs Firebase CDN (mondial)
```

### Checklist domaine personnalisé

```
[ ] Acheter domaine chez GoDaddy
[ ] Firebase Console → Hosting → Add custom domain
[ ] Copier les enregistrements DNS fournis par Firebase
[ ] GoDaddy → DNS Manager → Supprimer enregistrements A parking
[ ] GoDaddy → DNS Manager → Ajouter les nouveaux enregistrements
[ ] Attendre 24-48h propagation DNS
[ ] Firebase valide automatiquement + génère certificat SSL
[ ] Tester https://www.votredomaine.com ✅
[ ] Configurer redirection www ↔ domaine nu
```

---

## 5. Checklist mise en production — App Check

> À faire avant de publier sur le **Google Play Store**.
> L'app en mode debug utilise un token de test — il faut passer en mode production.

### État actuel (développement)

**`lib/main.dart`** — ligne à modifier :
```dart
// ACTUELLEMENT (debug) :
await FirebaseAppCheck.instance.activate(
  androidProvider: AndroidProvider.debug,  // ← À changer
);

// PRODUCTION :
await FirebaseAppCheck.instance.activate(
  androidProvider: AndroidProvider.playIntegrity,  // ← Valeur finale
);
```

**`android/app/src/main/AndroidManifest.xml`** — lignes à supprimer :
```xml
<!-- Ces 4 lignes sont à supprimer pour la production -->
<!-- Firebase App Check — debug token pour APK sideload (hors Play Store) -->
<!-- Ce token permet à Play Integrity de valider l'app même sans Play Store -->
<!-- Token enregistré dans Firebase Console → App Check → Debug tokens -->
<meta-data
    android:name="com.google.firebase.appcheck.debug.force_debug_token"
    android:value="3EBB85EC-B680-4076-A9E8-6A52F48A0A9F" />
```

**Debug token actuel** (à supprimer de Firebase Console en production) :
```
3EBB85EC-B680-4076-A9E8-6A52F48A0A9F
```

### Checklist complète

```
[ ] TÂCHE 1 — lib/main.dart
      AndroidProvider.debug  →  AndroidProvider.playIntegrity

[ ] TÂCHE 2 — AndroidManifest.xml
      Supprimer les 4 lignes du bloc debug token (lignes 34-39)

[ ] TÂCHE 3 — Firebase Console : vérifier les empreintes SHA
      https://console.firebase.google.com/project/immozone-d9a68/settings/general
      → Votre app Android → Ajouter empreinte SHA
      SHA-1  : 34:75:38:85:E0:D4:09:7D:97:27:C9:A6:EE:B9:8F:76:27:B7:4C:FF
      SHA-256: F0:71:FA:93:72:D4:FA:88:A9:AA:29:F8:8E:F3:3A:8D:EF:0A:BC:BF:
               1F:D1:14:27:E6:B2:45:9C:9C:0E:D7:C8

[ ] TÂCHE 4 — Firebase Console : activer App Check Enforcement
      https://console.firebase.google.com/project/immozone-d9a68/appcheck
      → Authentication → Activer l'application (Enforce)
      → Firestore     → Activer l'application (Enforce)

[ ] TÂCHE 5 — Firebase Console : supprimer le debug token
      https://console.firebase.google.com/project/immozone-d9a68/appcheck
      → Debug tokens → Supprimer : 3EBB85EC-B680-4076-A9E8-6A52F48A0A9F

[ ] TÂCHE 6 — Build final Play Store
      flutter build appbundle --release
      → Fichier : build/app/outputs/bundle/release/app-release.aab

[ ] TÂCHE 7 — git commit + push
      git add .
      git commit -m "Production: App Check playIntegrity, remove debug token"
      git push origin main
```

### Vérification finale avant soumission Play Store

```
[ ] App Check en mode playIntegrity ✅
[ ] Debug token supprimé du code ✅
[ ] Debug token supprimé de Firebase Console ✅
[ ] SHA-1 + SHA-256 enregistrés dans Firebase ✅
[ ] App Check Enforcement activé sur Authentication + Firestore ✅
[ ] Build AAB release généré ✅
[ ] Tests sur appareil physique réussis ✅
```

---

## Références rapides

| Ressource | URL |
|---|---|
| App en production | https://immozone-d9a68.web.app |
| Firebase Console | https://console.firebase.google.com/project/immozone-d9a68 |
| GitHub Repository | https://github.com/Patou2209/ImmoZone |
| GitHub Actions | https://github.com/Patou2209/ImmoZone/actions |
| Firebase Hosting | https://console.firebase.google.com/project/immozone-d9a68/hosting |
| Firebase App Check | https://console.firebase.google.com/project/immozone-d9a68/appcheck |
| Firebase Auth | https://console.firebase.google.com/project/immozone-d9a68/authentication |
| Firestore Database | https://console.firebase.google.com/project/immozone-d9a68/firestore |

---

*Document généré le 18/06/2026 — ImmoZone v1.2.59*


4. Domaine personnalisé GoDaddy → Firebase
Etape 1 — Acheter le domaine chez GoDaddy
Copyhttps://www.godaddy.com
→ Recherchez : immozone.cd  /  immozone.com  /  immo-zone.net
→ Achetez le domaine souhaite
Etape 2 — Ajouter le domaine dans Firebase Console
Copy1. https://console.firebase.google.com/project/immozone-d9a68/hosting
2. Cliquez "Add custom domain"
3. Entrez : www.votredomaine.com
4. Firebase vous fournit les enregistrements DNS a configurer
Etape 3 — Configurer les DNS chez GoDaddy
CopyGoDaddy → Mon compte → Mes domaines → Gerer DNS
→ Supprimer les enregistrements A existants (parking GoDaddy)
→ Ajouter les enregistrements fournis par Firebase :
Type	Nom	Valeur	                 TTL
A	     @	(IP fournie par Firebase)	600
A	     @	(IP fournie par Firebase)	600
CNAME	www	immozone-d9a68.web.app.	  3600
Les adresses IP exactes sont generees par Firebase au moment de l'ajout du domaine. Utiliser toujours les valeurs affichees dans la console Firebase.

Etape 4 — Verification et SSL automatique
Copy→ Firebase verifie les DNS automatiquement
→ Delai de propagation : 24 a 48 heures
→ Certificat SSL (HTTPS) genere automatiquement par Firebase — GRATUIT
→ Aucune configuration supplementaire necessaire

///////////////////===============/////////////////////////////////////

# BASH POUR METTRE A JOUR LE COTE WEB APRES CHAQUE MODIFICATION
# Dans le project Immozone:
git pull origin main  //pour pull les modification faites sur Genspark
flutter build web --release  // pour build la version web du plateforme(conformement a l'application android)
npm install -g firebase-tools  // pour installer le Firebase CLI (si pas deja faites)
Si npm n'est pas reconnu non plus, installez d'abord Node.js : https://nodejs.org (version LTS) puis relancez PowerShell.
firebase login  // pour se connecter a firebase qui contient votre project; Un navigateur va s'ouvrir → connectez-vous avec le compte Google lié à votre projet Firebase (immozone-d9a68).
firebase deploy --only hosting  // pour le deployement.




