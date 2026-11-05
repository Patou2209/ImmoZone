import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';

/// Widget universel pour afficher une image de propriété.
/// Gère automatiquement 3 formats :
///   1. Base64 data URI  → `data:image/jpeg;base64,...`  (stocké dans Firestore)
///   2. URL réseau       → `https://...`                 (Firebase Storage, etc.)
///   3. Fichier local    → chemin absolu (uniquement sur l'appareil de l'annonceur)
///
/// ⚡ Corrections audit M3 (v1.6.0) :
///   - URLs réseau : CachedNetworkImage → cache DISQUE persistant (les vignettes
///     ne sont plus re-téléchargées à chaque lancement de l'app).
///   - Base64 : décodage MÉMOÏSÉ dans un cache LRU statique + future mémoïsée →
///     plus de re-décodage ni de spinner à chaque rebuild (fin du scintillement).
///   - Grandes images base64 décodées dans un isolate (compute) → plus de
///     frames bloquées sur le thread UI.
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

  // ── Cache LRU statique des bytes décodés (base64) ─────────────────────────
  // Clé = hash de la chaîne source. Plafond pour borner la RAM : les vignettes
  // (~15 KB) et avatars y tiennent largement ; les grandes photos legacy
  // (~500 KB) sont évincées en premier (ordre d'insertion = LRU simple).
  static final Map<int, Uint8List> _bytesCache = <int, Uint8List>{};
  static final Map<int, Future<Uint8List?>> _inflight =
      <int, Future<Uint8List?>>{};
  static const int _maxCacheEntries = 80;

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

  /// PERF : largeur de décodage adaptée à la taille d'affichage réelle.
  int _cacheWidthFor(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    double base;
    if (width != null && width!.isFinite && width! > 0) {
      base = width!;
    } else if (height != null && height!.isFinite && height! > 0) {
      base = height! * 1.7; // ratio paysage typique des cartes
    } else {
      base = MediaQuery.of(context).size.width; // plein écran par défaut
    }
    return (base * dpr).round().clamp(64, 1400);
  }

  /// Décodage base64 pur (exécutable dans un isolate via compute).
  static Uint8List? _decodeSync(String src) {
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

  /// Décode avec mémoïsation : 1 décodage par source, partagé entre tous les
  /// widgets et tous les rebuilds. Grandes chaînes → isolate (compute).
  static Future<Uint8List?> _decodeMemoized(String src) {
    final key = src.hashCode;
    final cached = _bytesCache[key];
    if (cached != null) return Future.value(cached);
    final existing = _inflight[key];
    if (existing != null) return existing;

    // Petites images (< 50 Ko encodé ≈ 37 Ko réel) : décodage direct, moins
    // cher que le coût fixe d'un isolate. Grandes : compute() hors thread UI.
    final future = (src.length < 50 * 1024
            ? Future.value(_decodeSync(src))
            : compute(_decodeSync, src))
        .then((bytes) {
      _inflight.remove(key);
      if (bytes != null) {
        if (_bytesCache.length >= _maxCacheEntries) {
          _bytesCache.remove(_bytesCache.keys.first); // éviction LRU simple
        }
        _bytesCache[key] = bytes;
      }
      return bytes;
    });
    _inflight[key] = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return _wrap(_placeholder());

    // ── 1. Base64 data URI ────────────────────────────────────────────────────
    if (src.startsWith('data:image/')) {
      // Cache hit → rendu synchrone immédiat, aucun FutureBuilder, zéro flicker.
      final cached = _bytesCache[src.hashCode];
      if (cached != null) {
        return _wrap(Image.memory(
          cached,
          width: width,
          height: height,
          fit: fit,
          cacheWidth: _cacheWidthFor(context),
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(),
        ));
      }
      return _wrap(FutureBuilder<Uint8List?>(
        future: _decodeMemoized(src), // future PARTAGÉE (pas recréée par build)
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
            cacheWidth: _cacheWidthFor(context),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(),
          );
        },
      ));
    }

    // ── 2. URL réseau (https / http) ──────────────────────────────────────────
    if (src.startsWith('http://') || src.startsWith('https://')) {
      if (kIsWeb) {
        // Web : le cache HTTP du navigateur honore déjà le cacheControl 30 j
        // posé à l'upload — Image.network suffit.
        return _wrap(Image.network(
          src,
          width: width,
          height: height,
          fit: fit,
          cacheWidth: _cacheWidthFor(context),
          errorBuilder: (_, __, ___) => _placeholder(),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return _loading();
          },
        ));
      }
      // Mobile : cache DISQUE persistant → une vignette téléchargée une fois
      // reste disponible aux lancements suivants, même hors connexion.
      return _wrap(CachedNetworkImage(
        imageUrl: src,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: _cacheWidthFor(context),
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, __) => _loading(),
        errorWidget: (_, __, ___) => _placeholder(),
      ));
    }

    // ── 3. Fichier local (uniquement sur l'appareil de l'annonceur) ──────────
    if (!kIsWeb) {
      try {
        final file = File(src);
        if (file.existsSync()) {
          return _wrap(Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            cacheWidth: _cacheWidthFor(context),
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
