const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

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
