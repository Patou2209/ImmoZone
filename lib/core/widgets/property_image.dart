import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Widget universel pour afficher une image de propriété.
/// Gère automatiquement 3 formats :
///   1. Base64 data URI  → `data:image/jpeg;base64,...`  (stocké dans Firestore)
///   2. URL réseau       → `https://...`                 (Unsplash, etc.)
///   3. Fichier local    → chemin absolu (uniquement sur l'appareil de l'annonceur)
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

  Widget _wrap(Widget child) {
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return _wrap(_placeholder());

    // ── Base64 data URI ──────────────────────────────────────────────────────
    if (src.startsWith('data:image/')) {
      try {
        final commaIdx = src.indexOf(',');
        if (commaIdx == -1) return _wrap(_placeholder());
        final bytes = base64Decode(src.substring(commaIdx + 1));
        return _wrap(Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _placeholder(),
        ));
      } catch (_) {
        return _wrap(_placeholder());
      }
    }

    // ── URL réseau ───────────────────────────────────────────────────────────
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return _wrap(Image.network(
        src,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height,
            color: AppTheme.primaryColor,
            child: const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.accentColor, strokeWidth: 2),
            ),
          );
        },
      ));
    }

    // ── Fichier local (uniquement sur l'appareil de l'annonceur) ────────────
    if (!kIsWeb) {
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
    }

    return _wrap(_placeholder());
  }
}
