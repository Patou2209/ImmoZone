/// Helper central pour transformer toute erreur technique en message
/// compréhensible par l'utilisateur — AUCUN terme technique (firebase,
/// exception, codes internes…) ne doit apparaître à l'écran.
class ErrorHelper {
  ErrorHelper._();

  /// Marqueurs indiquant qu'un message est technique et ne doit JAMAIS
  /// être montré tel quel à l'utilisateur.
  static final List<String> _technicalMarkers = [
    'firebase', 'cloud_firestore', 'firestore', 'firebase_auth',
    'platformexception', 'plugin', 'stacktrace', 'stack trace',
    'null check', 'nosuchmethod', 'rangeerror', 'formatexception',
    'type \'', 'instance of', 'clientexception', 'handshake',
    'xmlhttprequest', 'assertion', 'unimplemented', 'code=',
    'grpc', 'deadline', 'internal error', 'unknown error',
    'httpexception', 'certificate', 'errno',
  ];

  /// Traduit une erreur (Exception, String, autre) en message français propre.
  /// [fallback] : message générique utilisé quand l'erreur est technique.
  static String friendly(Object? error,
      {String fallback = 'Une erreur est survenue. Veuillez réessayer.'}) {
    if (error == null) return fallback;
    String raw = error.toString().trim();
    // Retirer les préfixes techniques courants
    raw = raw
        .replaceFirst(RegExp(r'^Exception:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^Error:\s*', caseSensitive: false), '')
        .trim();
    if (raw.isEmpty) return fallback;

    final lower = raw.toLowerCase();

    // ── Cas connus → messages dédiés ────────────────────────────────────────
    if (lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('unavailable') ||
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('unreachable') ||
        lower.contains('failed host lookup')) {
      return 'Problème de connexion internet. Vérifiez votre réseau et réessayez.';
    }
    if (lower.contains('permission-denied') || lower.contains('permission denied')) {
      return 'Accès refusé. Veuillez vous reconnecter puis réessayer.';
    }
    if (lower.contains('not-found') || lower.contains('not found')) {
      return 'Donnée introuvable. Elle a peut-être été supprimée.';
    }
    if (lower.contains('too-many-requests') || lower.contains('resource-exhausted')) {
      return 'Trop de tentatives. Veuillez patienter un instant puis réessayer.';
    }
    if (lower.contains('maximum allowed size') || lower.contains('invalid-argument')) {
      return 'Les données envoyées sont trop volumineuses. '
          'Réduisez la taille des photos et réessayez.';
    }
    if (lower.contains('unauthenticated')) {
      return 'Session expirée. Veuillez vous reconnecter.';
    }

    // ── Message technique non identifié → générique ─────────────────────────
    // Un message métier volontaire (ex: Exception('Solde insuffisant…'))
    // est en français et ne contient aucun marqueur technique : il passe.
    final bool isTechnical = raw.length > 220 ||
        _technicalMarkers.any((m) => lower.contains(m)) ||
        RegExp(r'\[[a-z_/-]+\]').hasMatch(lower); // codes du style [cloud_firestore/xxx]
    if (isTechnical) return fallback;

    // Message métier lisible (déjà en français, ex: Exception('Solde insuffisant'))
    return raw;
  }
}
