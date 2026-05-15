import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/data_service.dart';

class AdminCategoriesScreen extends StatelessWidget {
  const AdminCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ds = DataService();
    final settings = ds.systemSettings;
    final adminName  = settings['admin_name']  as String? ?? 'Administrateur';
    final adminEmail = settings['admin_email'] as String? ?? '';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Catégories & Infos',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Admin Info Card ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        adminName.isNotEmpty ? adminName[0].toUpperCase() : 'A',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentColor,
                            fontFamily: 'Poppins'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(adminName,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFamily: 'Poppins')),
                        const Text('Administrateur ImmoZone',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                fontFamily: 'Poppins')),
                        if (adminEmail.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(adminEmail,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                  fontFamily: 'Poppins')),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _sectionTitle('Types de biens'),
            const SizedBox(height: 10),
            _tagsList(AppConstants.propertyTypes, AppTheme.primaryColor),
            const SizedBox(height: 20),

            _sectionTitle('Types de transactions'),
            const SizedBox(height: 10),
            _tagsList(AppConstants.transactionTypes, AppTheme.successColor),
            const SizedBox(height: 20),

            _sectionTitle('Villes disponibles'),
            const SizedBox(height: 10),
            _tagsList(AppConstants.cities, AppTheme.secondaryColor),
            const SizedBox(height: 20),

            _sectionTitle('Équipements'),
            const SizedBox(height: 10),
            _tagsList(AppConstants.amenities, AppTheme.accentColor),
            const SizedBox(height: 28),

            _sectionTitle('Paramètres de l\'application'),
            const SizedBox(height: 12),
            _settingsTile(
              context,
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Gérer les alertes et notifications',
              onTap: () => _showComingSoon(context),
            ),
            _settingsTile(
              context,
              icon: Icons.security_outlined,
              title: 'Sécurité',
              subtitle: 'Changer le mot de passe admin',
              onTap: () => _showComingSoon(context),
            ),
            _settingsTile(
              context,
              icon: Icons.bar_chart_outlined,
              title: 'Rapports & Exports',
              subtitle: 'Exporter les données en CSV',
              onTap: () => _showComingSoon(context),
            ),
            _settingsTile(
              context,
              icon: Icons.help_outline,
              title: 'Aide & Support',
              subtitle: 'Documentation et assistance',
              onTap: () => _showComingSoon(context),
            ),
            _settingsTile(
              context,
              icon: Icons.info_outline,
              title: 'À propos',
              subtitle: 'ImmoZone v1.0.0',
              onTap: () => _showAbout(context),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context, ds),
                icon: const Icon(Icons.logout, color: AppTheme.errorColor),
                label: const Text('Se déconnecter',
                    style: TextStyle(
                        color: AppTheme.errorColor,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.errorColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            fontFamily: 'Poppins'));
  }

  Widget _tagsList(List<String> items, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map((item) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(item,
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Poppins')),
                ))
            .toList(),
      ),
    );
  }

  Widget _settingsTile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF20202F).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.accentColor, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
                color: AppTheme.textPrimary)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontFamily: 'Poppins')),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textHint),
        onTap: onTap,
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fonctionnalité bientôt disponible !',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppTheme.accentColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.home_work, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('ImmoZone',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    color: AppTheme.textPrimary)),
            const Text('Version 1.0.0',
                style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontFamily: 'Poppins')),
            const SizedBox(height: 12),
            const Text(
              'Votre partenaire immobilier de confiance. Connectez annonceurs et demandeurs en toute simplicité.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontFamily: 'Poppins',
                  height: 1.5),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer',
                  style: TextStyle(fontFamily: 'Poppins')),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, DataService ds) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Déconnexion',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Voulez-vous vous déconnecter ?',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ds.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Déconnecter',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
