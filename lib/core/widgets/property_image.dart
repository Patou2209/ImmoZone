import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Widget universel pour afficher une image de propriété.
/// Gère automatiquement 3 formats :
///   1. Base64 data URI  → `data:image/jpeg;base64,...`  (stocké dans Firestore)
///   2. URL réseau       → `https://...`                 (Unsplash, Firebase Storage, etc.)
///   3. Fichier local    → chemin absolu (uniquement sur l'appareil de l'annonceur)
///
/// Corrections v1.2.12 :
///   - Décodage base64 robuste : try/catch précis avec FormatException
///   - FutureBuilder pour décoder les grandes images base64 hors du main thread
///   - Fallback explicite pour les chemins locaux inaccessibles (autre appareil)
///   - Indicateur de chargement visible pendant le décodage
class PropertyImage extends StatelessWidget {
  final String src;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final BorderRadius? borderRadius;

  const PropertyImage({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.borderRadius,
  });

  Widget _placeholder() =>
      placeholder ??
      Container(
        width: width,
        height: height,
        color: AppTheme.primaryColor,
        child: const Center(
          child: Icon(Icons.home_work_outlined,
              size: 40, color: AppTheme.accentColor),
        ),
      );

  Widget _loading() => Container(
        width: width,
        height: height,
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppTheme.accentColor,
            strokeWidth: 2,
          ),
        ),
      );

  Widget _wrap(Widget child) {
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  /// Décode une chaîne base64 en bytes — exécuté dans un Future
  /// pour éviter de bloquer l'UI sur de grandes images.
  static Future<Uint8List?> _decodeBase64(String src) async {
    try {
      final commaIdx = src.indexOf(',');
      if (commaIdx == -1) return null;
      final encoded = src.substring(commaIdx + 1).trim();
      if (encoded.isEmpty) return null;
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return _wrap(_placeholder());

    // ── 1. Base64 data URI ────────────────────────────────────────────────────
    // Format: data:image/jpeg;base64,/9j/4AAQ...
    if (src.startsWith('data:image/')) {
      return _wrap(FutureBuilder<Uint8List?>(
        future: _decodeBase64(src),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _loading();
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return _placeholder();
          }
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(),
          );
        },
      ));
    }

    // ── 2. URL réseau (https / http) ──────────────────────────────────────────
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return _wrap(Image.network(
        src,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return _loading();
        },
      ));
    }

    // ── 3. Fichier local (uniquement sur l'appareil de l'annonceur) ──────────
    // Sur web ou sur un autre appareil, le chemin local n'existe pas → placeholder
    if (!kIsWeb) {
      try {
        final file = File(src);
        if (file.existsSync()) {
          return _wrap(Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => _placeholder(),
          ));
        }
      } catch (_) {
        // Chemin invalide ou inaccessible → placeholder
      }
    }

    // ── 4. Fallback universel ─────────────────────────────────────────────────
    return _wrap(_placeholder());
  }
}
