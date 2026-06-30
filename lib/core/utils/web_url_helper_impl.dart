// Implémentation web — utilise dart:js_interop (Flutter 3.x / Dart 3.x)
import 'dart:js_interop';

@JS('window.history.replaceState')
external void _historyReplaceState(JSAny? state, JSString title, JSString url);

/// Remplace l'URL courante dans l'historique du navigateur sans rechargement.
void replaceState(String path) {
  try {
    final uri = Uri.base.replace(path: path, query: '', fragment: '');
    _historyReplaceState(JSObject(), ''.toJS, uri.toString().toJS);
  } catch (_) {}
}
