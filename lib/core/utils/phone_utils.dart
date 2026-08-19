/// Utilitaires de normalisation des numéros de téléphone.
///
/// Problème fréquent : l'utilisateur saisit son numéro avec le 0 national
/// (ex: 081 234 5678) alors que l'indicatif pays (+243) est déjà sélectionné.
/// Le numéro final devient +2430812345678 (invalide) au lieu de +243812345678.
class PhoneUtils {
  PhoneUtils._();

  /// Normalise la PARTIE LOCALE d'un numéro (saisie sans indicatif pays) :
  /// - supprime espaces, tirets, points et parenthèses
  /// - supprime un éventuel préfixe '+'
  /// - supprime le/les 0 nationaux en tête (081... → 81...)
  ///
  /// Exemples : '081 234 5678' → '812345678' ; '0812345678' → '812345678' ;
  ///            '812345678' → '812345678' (inchangé)
  static String normalizeLocal(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s\-\.\(\)]'), '');
    p = p.replaceFirst(RegExp(r'^\+'), '');
    // Retirer le(s) zéro(s) national(aux) en tête — jamais valide après un indicatif
    p = p.replaceFirst(RegExp(r'^0+'), '');
    return p;
  }

  /// Normalise un numéro COMPLET potentiellement saisi avec indicatif :
  /// - supprime espaces, tirets, points, parenthèses et '+'
  /// - si le numéro commence par un indicatif connu (243...) → conservé tel quel
  /// - sinon, supprime le(s) 0 nationaux en tête
  ///
  /// Exemples : '+243 081 234 5678' → '243812345678' (0 retiré après indicatif)
  ///            '0812345678' → '812345678'
  ///            '7704100021' → '7704100021' (sandbox, inchangé)
  static String normalizeMsisdn(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s\-\.\(\)]'), '').replaceFirst(RegExp(r'^\+'), '');
    // Cas indicatif RDC explicite : retirer un éventuel 0 glissé APRÈS le 243
    if (p.startsWith('243')) {
      final local = p.substring(3).replaceFirst(RegExp(r'^0+'), '');
      return '243$local';
    }
    // Numéro local : retirer le(s) 0 nationaux en tête
    return p.replaceFirst(RegExp(r'^0+'), '');
  }
}
