import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/property_model.dart';
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';

class AdminPropertyDetailScreen extends StatelessWidget {
  final PropertyModel property;
  const AdminPropertyDetailScreen({super.key, required this.property});

  Color _statusColor(String status) {
    switch (status) {
      case 'Actif': return AppTheme.statusActive;
      case 'En attente': return AppTheme.statusPending;
      case 'Vendu': return AppTheme.statusSold;
      case 'Rejeté': return AppTheme.statusRejected;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('Détail Annonce')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(property.mainImage,
                  height: 220, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(height: 220,
                      color: const Color(0xFF20202F).withValues(alpha: 0.08),
                      child: const Icon(Icons.home, size: 80, color: AppTheme.accentColor))),
            ),
            const SizedBox(height: 16),
            // Status + Title
            Row(
              children: [
                Expanded(child: Text(property.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins', color: AppTheme.textPrimary))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor(property.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor(property.status)),
                  ),
                  child: Text(property.status,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins', color: _statusColor(property.status))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${property.type} • ${property.transactionType} • ${property.formattedPrice}',
                style: const TextStyle(fontSize: 14, color: AppTheme.accentColor,
                    fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text('${property.address}, ${property.commune}, ${property.city}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'Poppins')),
            ]),
            const SizedBox(height: 16),
            _sectionTitle('Description'),
            const SizedBox(height: 8),
            Text(property.description, style: const TextStyle(fontSize: 13,
                color: AppTheme.textSecondary, fontFamily: 'Poppins', height: 1.6)),
            const SizedBox(height: 16),
            _sectionTitle('Informations Annonceur'),
            const SizedBox(height: 8),
            _infoRow(Icons.person_outline, 'Nom', property.ownerName),
            _infoRow(Icons.phone_outlined, 'Téléphone', property.ownerPhone),
            _infoRow(Icons.email_outlined, 'Email', property.ownerEmail),
            const SizedBox(height: 16),
            _sectionTitle('Statistiques'),
            const SizedBox(height: 8),
            Row(children: [
              _statBadge('${property.views}', 'Vues', Icons.visibility),
              const SizedBox(width: 12),
              _statBadge('${property.createdAt.day}/${property.createdAt.month}/${property.createdAt.year}',
                  'Publié le', Icons.calendar_today),
            ]),
            const SizedBox(height: 24),
            _sectionTitle('Actions de modération'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (property.status != 'Actif')
                  _actionBtn(context, 'Approuver', Icons.check_circle_outline,
                      AppTheme.successColor, () => _changeStatus(context, 'Actif')),
                if (property.status != 'Rejeté')
                  _actionBtn(context, 'Rejeter', Icons.cancel_outlined,
                      AppTheme.errorColor, () => _changeStatus(context, 'Rejeté')),
                if (property.status != 'Vendu')
                  _actionBtn(context, 'Marquer Vendu', Icons.sell_outlined,
                      AppTheme.primaryColor, () => _changeStatus(context, 'Vendu')),
                _actionBtn(context, 'Supprimer', Icons.delete_outline,
                    Colors.red.shade800, () => _deleteProperty(context)),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          fontFamily: 'Poppins', color: AppTheme.textPrimary));

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: AppTheme.accentColor),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            fontFamily: 'Poppins', color: AppTheme.textPrimary)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13,
            fontFamily: 'Poppins', color: AppTheme.textSecondary))),
      ]),
    );
  }

  Widget _statBadge(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF20202F).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppTheme.accentColor),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              fontFamily: 'Poppins', color: AppTheme.accentColor)),
          Text(label, style: const TextStyle(fontSize: 10,
              fontFamily: 'Poppins', color: AppTheme.textSecondary)),
        ]),
      ]),
    );
  }

  Widget _actionBtn(BuildContext context, String label, IconData icon,
      Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _changeStatus(BuildContext context, String status) async {
    await context.read<PropertyProvider>().updateStatus(property.id, status);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Statut mis à jour: $status'),
        backgroundColor: AppTheme.successColor,
      ));
      Navigator.pop(context);
    }
  }

  Future<void> _deleteProperty(BuildContext context) async {
    final isActive = property.status == 'Actif';
    final confirmCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever, color: AppTheme.errorColor, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Suppression définitive',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 16, color: AppTheme.textPrimary)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Aperçu annonce
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(property.mainImage,
                          width: 52, height: 52, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 52, height: 52,
                              color: const Color(0xFF20202F).withValues(alpha: 0.08),
                              child: const Icon(Icons.home,
                                  color: AppTheme.accentColor, size: 24))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(property.title,
                              style: const TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                  color: AppTheme.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(property.ownerName,
                              style: const TextStyle(fontSize: 11,
                                  color: AppTheme.textSecondary,
                                  fontFamily: 'Poppins')),
                          Text(property.formattedPrice,
                              style: const TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accentColor,
                                  fontFamily: 'Poppins')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Alerte renforcée si actif
              if (isActive)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cette annonce est actuellement ACTIVE et visible par les utilisateurs. Sa suppression est définitive et irréversible.',
                          style: TextStyle(fontSize: 11,
                              color: Color(0xFFE65100),
                              fontFamily: 'Poppins',
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Text('Cette action est définitive et irréversible.',
                    style: TextStyle(fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontFamily: 'Poppins')),
              // Saisie de confirmation pour annonces actives
              if (isActive) ...[
                const SizedBox(height: 14),
                const Text('Tapez SUPPRIMER pour confirmer :',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  onChanged: (_) => setStateDialog(() {}),
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.errorColor),
                  decoration: InputDecoration(
                    hintText: 'SUPPRIMER',
                    hintStyle: const TextStyle(
                        color: AppTheme.textHint, fontFamily: 'Poppins'),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: confirmCtrl.text == 'SUPPRIMER'
                            ? AppTheme.errorColor
                            : AppTheme.dividerColor,
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppTheme.errorColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                confirmCtrl.dispose();
                Navigator.pop(ctx, false);
              },
              child: const Text('Annuler',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppTheme.textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: isActive
                  ? (confirmCtrl.text == 'SUPPRIMER'
                      ? () {
                          confirmCtrl.dispose();
                          Navigator.pop(ctx, true);
                        }
                      : null)
                  : () {
                      confirmCtrl.dispose();
                      Navigator.pop(ctx, true);
                    },
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('Supprimer définitivement',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.red.shade200,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && context.mounted) {
      await context.read<PropertyProvider>().deleteProperty(property.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.delete_forever, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Annonce "${property.title}" supprimée définitivement',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    }
  }
}
