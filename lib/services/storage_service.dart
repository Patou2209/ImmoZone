import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

/// ⚡ QW5 — Service d'upload des photos d'annonces vers Firebase Storage.
///
/// AVANT : photos encodées en base64 DANS le document Firestore
///   → documents de ~750 KB, chaque lecture de liste téléchargeait TOUT
///   (20 annonces ≈ 15 Mo ≈ 60 s sur 4G).
/// APRÈS : photos dans Firebase Storage (CDN Google + cache HTTP natif),
///   le document ne contient que les URLs + une miniature base64 ~15 KB
///   → documents de ~20 KB (-97 %).
///
/// RÉTROCOMPATIBILITÉ TOTALE :
///   - PropertyImage affiche déjà les 2 formats (base64 ET URLs) ;
///   - la v1.5.5 en production lit `images` comme avant (URLs comprises) ;
///   - en cas d'échec d'upload Storage (réseau, règles), l'appelant retombe
///     sur l'encodage base64 historique → la publication n'échoue JAMAIS
///     à cause de Storage.
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  FirebaseStorage get _storage => FirebaseStorage.instance;

  /// Taille max du côté long de la miniature (listes/cartes).
  static const int thumbMaxSize = 360;

  /// Qualité JPEG de la miniature (~10-25 KB à 360px).
  static const int thumbQuality = 55;

  /// Upload une photo d'annonce. Retourne l'URL de téléchargement.
  /// Lève une exception en cas d'échec (l'appelant gère le fallback base64).
  Future<String> uploadPropertyPhoto({
    required String propertyId,
    required int index,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final ext = contentType == 'image/png' ? 'png' : 'jpg';
    final ref = _storage.ref('properties/$propertyId/photo_$index.$ext');
    await ref
        .putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            // Cache CDN/navigateur 30 jours : les photos d'une annonce sont
            // immuables (une modification ré-uploade sous un autre index/nom).
            cacheControl: 'public, max-age=2592000',
          ),
        )
        .timeout(const Duration(seconds: 60));
    return ref.getDownloadURL().timeout(const Duration(seconds: 20));
  }

  /// Vérifie qu'un upload est bien présent dans Storage avec la taille
  /// attendue (étape VÉRIFIER de la migration : on ne nettoie le base64
  /// qu'après cette confirmation).
  Future<bool> verifyUpload(String url, int expectedSize) async {
    try {
      final meta = await _storage
          .refFromURL(url)
          .getMetadata()
          .timeout(const Duration(seconds: 20));
      return meta.size == expectedSize;
    } catch (e) {
      if (kDebugMode) debugPrint('[StorageService.verifyUpload] $e');
      return false;
    }
  }

  /// Supprime toutes les photos Storage d'une annonce (best-effort —
  /// silencieux si le dossier n'existe pas, ex: annonce 100 % base64).
  Future<void> deletePropertyPhotos(String propertyId) async {
    try {
      final root = _storage.ref('properties/$propertyId');
      final list = await root.listAll().timeout(const Duration(seconds: 20));
      for (final item in list.items) {
        try {
          await item.delete();
        } catch (_) {}
      }
      // Sous-dossiers (migrated/, edit_*/ …) — 1 niveau suffit.
      for (final prefix in list.prefixes) {
        try {
          final sub = await prefix.listAll().timeout(const Duration(seconds: 20));
          for (final item in sub.items) {
            try {
              await item.delete();
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[StorageService.deletePhotos] $e');
    }
  }

  /// Génère la miniature base64 (data URI JPEG ~15 KB) à partir des bytes
  /// de la photo principale. Exécuté dans un isolate (compute) pour ne pas
  /// bloquer l'UI. Retourne null si le décodage échoue (format exotique) —
  /// dans ce cas les listes retomberont sur mainImage (fallback du modèle).
  static Future<String?> makeThumbnail(Uint8List bytes) async {
    try {
      return await compute(_encodeThumbnail, bytes);
    } catch (e) {
      if (kDebugMode) debugPrint('[StorageService.makeThumbnail] $e');
      return null;
    }
  }
}

/// Fonction TOP-LEVEL pour compute() : décode → redimensionne → ré-encode.
String? _encodeThumbnail(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded,
            width: StorageService.thumbMaxSize,
            interpolation: img.Interpolation.average)
        : img.copyResize(decoded,
            height: StorageService.thumbMaxSize,
            interpolation: img.Interpolation.average);
    final jpg = img.encodeJpg(resized, quality: StorageService.thumbQuality);
    return 'data:image/jpeg;base64,${base64Encode(jpg)}';
  } catch (_) {
    return null;
  }
}
