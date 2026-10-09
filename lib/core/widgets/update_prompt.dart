import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';
import '../../services/data_service.dart';

/// ── Pop-up « Mise à jour disponible » ────────────────────────────────────────
/// Déclenché par l'ADMIN depuis Paramètres → Plateforme : il définit le numéro
/// de build minimal requis (`update_build`) dans config/system_settings.
///
/// Comportement :
/// - À CHAQUE lancement de l'app, si update_build > build installé
///   (AppConstants.appBuildNumber) → le pop-up s'affiche.
/// - « Mettre à jour maintenant » → ouvre le Play Store.
/// - « Plus tard » → ferme le pop-up ; il réapparaîtra au prochain lancement.
/// - Une fois la mise à jour installée (build >= update_build), le pop-up
///   ne s'affiche plus jamais (comparaison de versions, pas de flag).
class UpdatePrompt {
  UpdatePrompt._();

  static bool _shownThisSession = false;

  /// À appeler au lancement (home publique). Vérifie Firestore et affiche
  /// le pop-up si une mise à jour est requise. Silencieux en cas d'erreur.
  static Future<void> checkAndShow(BuildContext context) async {
    if (_shownThisSession) return; // une seule fois par lancement
    try {
      final ds = DataService();
      final settings = await ds.getSettingsMap();
      final requiredBuild = (settings['update_build'] as num?)?.toInt() ?? 0;
      if (requiredBuild <= AppConstants.appBuildNumber) return; // à jour

      final message = settings['update_message'] as String? ?? '';
      final url = settings['update_url'] as String? ??
          AppConstants.playStoreUrl;

      _shownThisSession = true;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _UpdateDialog(message: message, updateUrl: url),
      );
    } catch (_) {
      // Jamais bloquant : en cas d'erreur réseau, l'app démarre normalement.
    }
  }
}

class _UpdateDialog extends StatelessWidget {
  final String message;
  final String updateUrl;
  const _UpdateDialog({required this.message, required this.updateUrl});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update_rounded,
                color: AppTheme.accentColor, size: 34),
          ),
          const SizedBox(height: 16),
          const Text('Mise à jour disponible',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
                  fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            message.isNotEmpty
                ? message
                : 'Une nouvelle version d\'ImmoZone est en ligne !\n'
                  'Mettez à jour pour profiter des dernières améliorations.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppTheme.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(updateUrl);
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Mettre à jour maintenant',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Plus tard',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: AppTheme.textHint)),
          ),
        ]),
      ),
    );
  }
}
