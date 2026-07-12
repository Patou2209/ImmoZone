// Web implementation — reads from window.localStorage synchronously.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Returns the value of [key] from localStorage, or null if absent.
String? readLocal(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}
