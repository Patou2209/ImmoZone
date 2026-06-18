import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }

  // ── Web Firebase config ──────────────────────────────────────────────────
  // ⚠️ appId web : à remplacer par la vraie valeur depuis Firebase Console
  //    Firebase Console → Project Settings → Your apps → Web app → App ID
  //    Format : 1:836828432238:web:XXXXXXXXXXXX
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCPx_8e7-ecYA6amk-yu-8inbgJ0beme2g',
    appId: '1:836828432238:web:d101bc8e3e61183546637f',
    messagingSenderId: '836828432238',
    projectId: 'immozone-d9a68',
    storageBucket: 'immozone-d9a68.firebasestorage.app',
    authDomain: 'immozone-d9a68.firebaseapp.com',
  );

  // ── Android Firebase config ──────────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCPx_8e7-ecYA6amk-yu-8inbgJ0beme2g',
    appId: '1:836828432238:android:d101bc8e3e61183546637f',
    messagingSenderId: '836828432238',
    projectId: 'immozone-d9a68',
    storageBucket: 'immozone-d9a68.firebasestorage.app',
  );
}
