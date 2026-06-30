import 'package:flutter/foundation.dart';

// ignore: avoid_web_libraries_in_flutter
import 'web_url_helper_impl.dart'
    if (dart.library.io) 'web_url_helper_stub.dart' as _impl;

/// Utilitaire pour synchroniser l'URL du navigateur web avec la page courante.
/// No-op sur Android/iOS.
class WebUrlHelper {
  /// Met à jour l'URL → /property/:id
  static void setPropertyUrl(String propertyId) {
    if (!kIsWeb) return;
    _impl.replaceState('/property/$propertyId');
  }

  /// Remet l'URL → /public
  static void setPublicUrl() {
    if (!kIsWeb) return;
    _impl.replaceState('/public');
  }
}
