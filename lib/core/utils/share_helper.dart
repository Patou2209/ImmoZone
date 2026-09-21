import 'package:share_plus/share_plus.dart';

import '../constants/app_constants.dart';
import '../../models/property_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ShareHelper — construction UNIQUE du message de partage d'une annonce.
// Utilisé par tous les écrans (accueil, favoris, recherche, détail, profil,
// annonceur) pour garantir un message identique partout.
//
// Format :
//   Bonjour,
//   J'ai trouvé cette propriété qui pourrait t'intéresser.
//   Réf. IZXXXX
//   https://www.immozone.pro/property/prop_XXXX
// ─────────────────────────────────────────────────────────────────────────────
class ShareHelper {
  ShareHelper._();

  /// Référence courte affichée à l'utilisateur (IZ + 4 derniers du docId).
  static String refOf(PropertyModel p) =>
      'IZ${p.id.length >= 4 ? p.id.substring(p.id.length - 4).toUpperCase() : p.id.toUpperCase()}';

  /// Message complet de partage.
  static String buildMessage(PropertyModel p) {
    final ref = refOf(p);
    final link = '${AppConstants.webBaseUrl}/property/${p.id}';
    return 'Bonjour,\n'
        'J\'ai trouvé cette propriété qui pourrait t\'intéresser.\n'
        'Réf. $ref\n'
        '$link';
  }

  /// Partage l'annonce via la feuille de partage native.
  static Future<void> shareProperty(PropertyModel p) async {
    await SharePlus.instance.share(ShareParams(text: buildMessage(p)));
  }
}
