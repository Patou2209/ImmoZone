import 'package:share_plus/share_plus.dart';

import '../constants/app_constants.dart';
import '../../models/property_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ShareHelper — construction UNIQUE du message de partage d'une annonce.
// Utilisé par tous les écrans (accueil, favoris, recherche, détail, profil,
// annonceur) pour garantir un message identique partout.
//
// Format :
//   J'ai trouvé cet(te) {type du bien} qui pourrait t'intéresser.
//   Réf. IZXXXX
//   https://www.immozone.pro/property/prop_XXXX
// ─────────────────────────────────────────────────────────────────────────────
class ShareHelper {
  ShareHelper._();

  /// Types de biens FÉMININS → « cette » ; les autres → « cet »/« ce ».
  /// (Maison, Villa, Propriété…, Concession, Salle…, Chambre… = féminins)
  static const Set<String> _feminineTypes = {
    'Maison',
    'Villa',
    'Propriété commerciale',
    'Propriété industrielle',
    'Concession',
    'Salle de fêtes',
    'Chambre d\'hôtel',
    'Salle polyvalente',
  };

  /// Types masculins commençant par une VOYELLE → « cet » (cet appartement,
  /// cet espace…) ; sinon « ce » (ce bureau, ce terrain).
  static String _demonstrative(String type) {
    if (_feminineTypes.contains(type)) return 'cette';
    final first = type.trim().toLowerCase();
    if (first.startsWith(RegExp(r'[aeiouéèêh]'))) return 'cet';
    return 'ce';
  }

  /// Référence courte affichée à l'utilisateur (IZ + 4 derniers du docId).
  static String refOf(PropertyModel p) =>
      'IZ${p.id.length >= 4 ? p.id.substring(p.id.length - 4).toUpperCase() : p.id.toUpperCase()}';

  /// Message complet de partage.
  static String buildMessage(PropertyModel p) {
    final ref = refOf(p);
    final link = '${AppConstants.webBaseUrl}/property/${p.id}';
    final demo = _demonstrative(p.type);
    // Type en minuscule dans la phrase ; « Appartement / flat » → « appartement »
    final typeLabel = p.type.isNotEmpty
        ? p.type.split('/').first.trim().toLowerCase()
        : 'bien';
    return 'J\'ai trouvé $demo $typeLabel qui pourrait t\'intéresser.\n'
        'Réf. $ref\n'
        '$link';
  }

  /// Partage l'annonce via la feuille de partage native.
  static Future<void> shareProperty(PropertyModel p) async {
    await SharePlus.instance.share(ShareParams(text: buildMessage(p)));
  }
}
