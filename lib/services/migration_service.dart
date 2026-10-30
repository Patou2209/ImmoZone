import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'storage_service.dart';

/// ⚡ QW5 — Migration one-shot des annonces existantes :
/// photos base64 (dans les documents Firestore) → Firebase Storage.
///
/// PRINCIPE DE SÉCURITÉ ABSOLU (« nous ne voulons rien perdre ») :
///   1. COPIER   : upload de chaque photo base64 vers Storage ;
///   2. VÉRIFIER : getMetadata() confirme la présence ET la taille exacte ;
///   3. NETTOYER : seulement si TOUTES les photos de l'annonce sont
///      copiées + vérifiées, le document est mis à jour (URLs + thumbnail).
///      Si une seule étape échoue → le document n'est PAS touché,
///      l'annonce reste en base64 et fonctionne comme avant.
///
/// RÉTROCOMPATIBILITÉ : PropertyImage (toutes versions, y compris la
/// v1.5.5 en production) affiche indifféremment base64 et URLs →
/// la migration peut tourner AVANT la release 1.5.6 sans rien casser.
///
/// Idempotente : relancer la migration ignore les annonces déjà migrées.
class MigrationResult {
  int total = 0; // annonces examinées
  int migrated = 0; // annonces migrées avec succès
  int alreadyClean = 0; // annonces déjà en URLs (rien à faire)
  int failed = 0; // annonces laissées INTACTES suite à un échec
  final List<String> errors = [];

  @override
  String toString() =>
      'total=$total, migrées=$migrated, déjà propres=$alreadyClean, '
      'échecs (intactes)=$failed';
}

class MigrationService {
  final _db = FirebaseFirestore.instance;
  final _storage = StorageService();

  /// Migre toutes les annonces dont `images` contient du base64.
  /// [onProgress] : callback UI (message lisible, index courant, total).
  Future<MigrationResult> migratePropertiesToStorage({
    void Function(String message, int current, int total)? onProgress,
  }) async {
    final result = MigrationResult();

    final snap = await _db.collection('properties').get();
    final docs = snap.docs;
    result.total = docs.length;

    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final data = doc.data();
      final id = doc.id;
      final title = (data['title'] ?? id).toString();

      final images = (data['images'] as List?)?.cast<dynamic>() ?? [];
      final base64Count =
          images.where((e) => e is String && e.startsWith('data:')).length;

      // Rien à migrer : déjà en URLs (ou sans photo).
      if (base64Count == 0) {
        // Si l'annonce migrée n'a pas encore de thumbnail, on peut en
        // générer un plus tard côté app — pas bloquant ici.
        result.alreadyClean++;
        onProgress?.call('✓ "$title" — déjà propre', i + 1, docs.length);
        continue;
      }

      onProgress?.call(
          '⏳ "$title" — $base64Count photo(s) à migrer…', i + 1, docs.length);

      try {
        // ── 1. COPIER + 2. VÉRIFIER chaque photo ────────────────────────
        final newImages = <String>[];
        String? thumbnail = data['thumbnail'] as String?;
        var ok = true;

        for (var p = 0; p < images.length; p++) {
          final src = images[p];
          if (src is! String) continue;

          if (!src.startsWith('data:')) {
            // Déjà une URL (ou chemin) — conservée telle quelle, même ordre.
            newImages.add(src);
            continue;
          }

          // Décodage du data-URI.
          final comma = src.indexOf(',');
          if (comma < 0) {
            ok = false;
            result.errors.add('$id/photo_$p : data-URI invalide');
            break;
          }
          final header = src.substring(0, comma); // data:image/jpeg;base64
          final contentType = header.contains('image/png')
              ? 'image/png'
              : header.contains('image/webp')
                  ? 'image/webp'
                  : 'image/jpeg';
          final Uint8List bytes;
          try {
            bytes = base64Decode(src.substring(comma + 1));
          } catch (e) {
            ok = false;
            result.errors.add('$id/photo_$p : base64 illisible ($e)');
            break;
          }

          // COPIER → Storage (sous un préfixe dédié à la migration pour ne
          // jamais entrer en collision avec des uploads app).
          final url = await _storage.uploadPropertyPhoto(
            propertyId: '$id/migrated',
            index: p,
            bytes: bytes,
            contentType: contentType,
          );

          // VÉRIFIER : présence + taille exacte dans Storage.
          final verified = await _storage.verifyUpload(url, bytes.length);
          if (!verified) {
            ok = false;
            result.errors.add('$id/photo_$p : vérification Storage échouée');
            break;
          }
          newImages.add(url);

          // Thumbnail depuis la photo principale (index 0) si absent.
          final mainIdx = (data['mainImageIndex'] as num?)?.toInt() ?? 0;
          if ((thumbnail == null || thumbnail.isEmpty) &&
              p == (mainIdx < images.length ? mainIdx : 0)) {
            thumbnail = await StorageService.makeThumbnail(bytes);
          }
        }

        if (!ok || newImages.isEmpty) {
          result.failed++;
          onProgress?.call(
              '✗ "$title" — échec, annonce laissée INTACTE', i + 1, docs.length);
          continue; // Document non touché → rien perdu.
        }

        // Thumbnail de secours : si toujours absent, depuis la 1re base64.
        if (thumbnail == null || thumbnail.isEmpty) {
          final firstB64 = images
              .whereType<String>()
              .firstWhere((e) => e.startsWith('data:'), orElse: () => '');
          if (firstB64.isNotEmpty) {
            final comma = firstB64.indexOf(',');
            try {
              thumbnail = await StorageService.makeThumbnail(
                  base64Decode(firstB64.substring(comma + 1)));
            } catch (_) {}
          }
        }

        // ── 3. NETTOYER : écrire URLs + thumbnail (remplace le base64) ──
        await _db.collection('properties').doc(id).update({
          'images': newImages,
          if (thumbnail != null && thumbnail.isNotEmpty)
            'thumbnail': thumbnail,
        });

        // Contre-vérification finale : relire le doc et confirmer.
        final check = await _db.collection('properties').doc(id).get();
        final checkImages =
            (check.data()?['images'] as List?)?.cast<dynamic>() ?? [];
        final stillB64 = checkImages
            .any((e) => e is String && e.startsWith('data:'));
        if (stillB64 || checkImages.length != newImages.length) {
          result.errors.add('$id : contre-vérification inattendue');
        }

        result.migrated++;
        onProgress?.call(
            '✅ "$title" — ${newImages.length} photo(s) migrée(s)',
            i + 1,
            docs.length);
      } catch (e) {
        result.failed++;
        result.errors.add('$id : $e');
        onProgress?.call(
            '✗ "$title" — erreur ($e), annonce laissée INTACTE',
            i + 1,
            docs.length);
        if (kDebugMode) debugPrint('[Migration] $id : $e');
      }
    }

    return result;
  }
}
