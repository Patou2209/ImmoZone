/// Utilitaires de formatage de texte.
class TextFormatter {
  TextFormatter._();

  /// Met un nom en "Title Case" : première lettre de chaque mot en majuscule,
  /// le reste en minuscules. Gère les espaces, tirets et apostrophes.
  /// Ex: "NGANDU kalala" → "Ngandu Kalala" ; "jean-pierre" → "Jean-Pierre".
  static String toTitleCase(String input) {
    final s = input.trim();
    if (s.isEmpty) return s;
    final buffer = StringBuffer();
    bool capitalizeNext = true;
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == ' ' || ch == '-' || ch == '\'' || ch == '’') {
        buffer.write(ch);
        capitalizeNext = true;
      } else {
        buffer.write(capitalizeNext ? ch.toUpperCase() : ch.toLowerCase());
        capitalizeNext = false;
      }
    }
    // Normaliser les espaces multiples
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
  }
}
