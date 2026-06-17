import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/property_model.dart';
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/data_service.dart';

class AdminPropertyDetailScreen extends StatefulWidget {
  final PropertyModel property;
  const AdminPropertyDetailScreen({super.key, required this.property});

  @override
  State<AdminPropertyDetailScreen> createState() => _AdminPropertyDetailScreenState();
}

class _AdminPropertyDetailScreenState extends State<AdminPropertyDetailScreen> {
  late PropertyModel _property;
  bool _boostLoading = false;
  final DataService _ds = DataService();

  @override
  void initState() {
    super.initState();
    _property = widget.property;
  }

  // ── Couleur selon statut ──────────────────────────────────────────────────
  Color _statusColor(String status) {
    switch (status) {
      case 'Actif':       return AppTheme.statusActive;
      case 'En attente':  return AppTheme.statusPending;
      case 'Vendu':       return AppTheme.statusSold;
      case 'Rejeté':      return AppTheme.statusRejected;
      default:            return Colors.grey;
    }
  }

  // ── Couleur / gradient boost par niveau ──────────────────────────────────
  List<Color> _boostGradient(int level) {
    switch (level) {
      case 3: return [const Color(0xFF7B1FA2), const Color(0xFFE040FB)]; // VIP violet
      case 2: return [const Color(0xFFE65100), const Color(0xFFFF9800)]; // Premium orange
      default: return [const Color(0xFF1565C0), const Color(0xFF42A5F5)]; // Standard bleu
    }
  }

  String _boostLevelLabel(int level) {
    switch (level) {
      case 3: return 'VIP';
      case 2: return 'Premium';
      default: return 'Standard';
    }
  }

  IconData _boostIcon(int level) =>
      level == 3 ? Icons.workspace_premium_rounded : Icons.star_rounded;

  // ── Formatage date ────────────────────────────────────────────────────────
  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  }

  // ── Jours restants boost ──────────────────────────────────────────────────
  int _daysLeft(DateTime? end) {
    if (end == null) return 0;
    final diff = end.difference(DateTime.now());
    return diff.inDays.clamp(0, 999);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Détail Annonce',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ──────────────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                _property.mainImage,
                height: 220, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 220,
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  child: const Icon(Icons.home, size: 80, color: AppTheme.accentColor),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Titre + statut ─────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: Text(_property.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins', color: AppTheme.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(_property.status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor(_property.status)),
                ),
                child: Text(_property.status,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins', color: _statusColor(_property.status))),
              ),
            ]),
            const SizedBox(height: 8),
            Text('${_property.type} • ${_property.transactionType} • ${_property.formattedPrice}',
                style: const TextStyle(fontSize: 14, color: AppTheme.accentColor,
                    fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${_property.address}, ${_property.commune}, ${_property.city}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary,
                      fontFamily: 'Poppins'),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // ══════════════════════════════════════════════════════════════
            // ── SECTION BOOST ─────────────────────────────────────────────
            // ══════════════════════════════════════════════════════════════
            _buildBoostSection(),

            const SizedBox(height: 20),

            // ── Description ────────────────────────────────────────────────
            _sectionTitle('Description'),
            const SizedBox(height: 8),
            Text(_property.description,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary,
                    fontFamily: 'Poppins', height: 1.6)),
            const SizedBox(height: 16),

            // ── Infos annonceur ────────────────────────────────────────────
            _sectionTitle('Informations Annonceur'),
            const SizedBox(height: 8),
            _infoRow(Icons.person_outline,  'Nom',       _property.ownerName),
            _infoRow(Icons.phone_outlined,  'Téléphone', _property.ownerPhone),
            _infoRow(Icons.email_outlined,  'Email',     _property.ownerEmail),
            const SizedBox(height: 16),

            // ── Statistiques ───────────────────────────────────────────────
            _sectionTitle('Statistiques'),
            const SizedBox(height: 8),
            Row(children: [
              _statBadge('${_property.views}', 'Vues', Icons.visibility),
              const SizedBox(width: 12),
              _statBadge(
                '${_property.createdAt.day}/${_property.createdAt.month}/${_property.createdAt.year}',
                'Publié le', Icons.calendar_today,
              ),
            ]),
            const SizedBox(height: 24),

            // ── Modération ─────────────────────────────────────────────────
            _sectionTitle('Actions de modération'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                if (_property.status != 'Actif')
                  _actionBtn(context, 'Approuver', Icons.check_circle_outline,
                      AppTheme.successColor, () => _changeStatus(context, 'Actif')),
                if (_property.status != 'Rejeté')
                  _actionBtn(context, 'Rejeter', Icons.cancel_outlined,
                      AppTheme.errorColor, () => _changeStatus(context, 'Rejeté')),
                if (_property.status != 'Vendu')
                  _actionBtn(context, 'Marquer vendu', Icons.sell_outlined,
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

  // ══════════════════════════════════════════════════════════════════════════
  // ── SECTION BOOST COMPLÈTE ────────────────────────────────────────────────
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildBoostSection() {
    final isActive = _property.isBoostActive;
    final level = _property.boostLevel;
    final daysLeft = _daysLeft(_property.boostEnd);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? _boostGradient(level).first.withValues(alpha: 0.4)
              : const Color(0xFFE4E8F0),
          width: isActive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? _boostGradient(level).first.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      colors: _boostGradient(level),
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFF5F7FA), Color(0xFFEEF2FA)],
                    ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              Icon(
                isActive ? _boostIcon(level) : Icons.rocket_launch_outlined,
                color: isActive ? Colors.white : AppTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isActive
                      ? 'Boost actif — ${_boostLevelLabel(level)}'
                      : 'Boost — Mettre en avant',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isActive ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$daysLeft j restant${daysLeft > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Statut boost actuel ──────────────────────────────────
                if (isActive) ...[
                  _buildCurrentBoostStatus(),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFE4E8F0)),
                  const SizedBox(height: 14),
                  const Text('Modifier le boost :',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                  const SizedBox(height: 10),
                ],

                // ── Légende des niveaux ──────────────────────────────────
                _buildBoostLegend(),
                const SizedBox(height: 16),

                // ── Grille de sélection ──────────────────────────────────
                const Text('Choisir le niveau et la durée :',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 12),

                // Standard
                _buildBoostLevelBlock(
                  level: 1,
                  label: 'Standard',
                  subtitle: 'Visible si critères géo + type correspondent',
                  colors: _boostGradient(1),
                  icon: Icons.star_rounded,
                ),
                const SizedBox(height: 10),

                // Premium
                _buildBoostLevelBlock(
                  level: 2,
                  label: 'Premium',
                  subtitle: 'Critères géo + type — filtres avancés ignorés',
                  colors: _boostGradient(2),
                  icon: Icons.star_rounded,
                ),
                const SizedBox(height: 10),

                // VIP
                _buildBoostLevelBlock(
                  level: 3,
                  label: 'VIP — Spécial',
                  subtitle: 'Visible PARTOUT — ignore tous les filtres',
                  colors: _boostGradient(3),
                  icon: Icons.workspace_premium_rounded,
                ),

                // ── Bouton retirer ───────────────────────────────────────
                if (isActive) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFE4E8F0)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _boostLoading ? null : () => _removeBoost(),
                      icon: _boostLoading
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2,
                                  color: AppTheme.errorColor))
                          : const Icon(Icons.rocket_outlined, size: 16,
                              color: AppTheme.errorColor),
                      label: const Text('Retirer le boost',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                              fontWeight: FontWeight.w600, color: AppTheme.errorColor)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.errorColor, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Statut boost actuel (badges + dates) ─────────────────────────────────
  Widget _buildCurrentBoostStatus() {
    final colors = _boostGradient(_property.boostLevel);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.first.withValues(alpha: 0.08), colors.last.withValues(alpha: 0.04)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.first.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_boostIcon(_property.boostLevel), color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Text(_boostLevelLabel(_property.boostLevel),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
            const SizedBox(width: 10),
            Text(_property.boostBadge ?? '',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: colors.first, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 13,
                color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text('Expire le : ${_fmtDate(_property.boostEnd)}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.textSecondary)),
          ]),
        ],
      ),
    );
  }

  // ── Légende des niveaux ───────────────────────────────────────────────────
  Widget _buildBoostLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E8F0)),
      ),
      child: Column(children: [
        _legendRow(Icons.star_rounded, 'Standard', const Color(0xFF1565C0),
            'Section Offres Spéciales si géo+type correspondent'),
        const SizedBox(height: 6),
        _legendRow(Icons.star_rounded, 'Premium', const Color(0xFFE65100),
            'Idem Standard — filtres avancés (prix, pièces) ignorés'),
        const SizedBox(height: 6),
        _legendRow(Icons.workspace_premium_rounded, 'VIP', const Color(0xFF7B1FA2),
            'Toujours en tête — ignore TOUS les filtres'),
      ]),
    );
  }

  Widget _legendRow(IconData icon, String label, Color color, String desc) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 15),
      const SizedBox(width: 8),
      Text('$label : ', style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
          fontWeight: FontWeight.w700, color: color)),
      Expanded(
        child: Text(desc, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
            color: AppTheme.textSecondary)),
      ),
    ]);
  }

  // ── Bloc de boost par niveau (avec 3 boutons de durée) ────────────────────
  Widget _buildBoostLevelBlock({
    required int level,
    required String label,
    required String subtitle,
    required List<Color> colors,
    required IconData icon,
  }) {
    final isCurrentLevel = _property.isBoostActive && _property.boostLevel == level;

    return Container(
      decoration: BoxDecoration(
        color: isCurrentLevel
            ? colors.first.withValues(alpha: 0.06)
            : const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentLevel
              ? colors.first.withValues(alpha: 0.35)
              : const Color(0xFFE4E8F0),
          width: isCurrentLevel ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre du niveau
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: Colors.white, size: 13),
                const SizedBox(width: 5),
                Text(label, style: const TextStyle(fontFamily: 'Poppins',
                    fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
            if (isCurrentLevel) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.first.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Actif',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.w700, color: colors.first)),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 10),

          // Boutons durée
          Row(children: [
            _durationBtn(level: level, days: 7,  label: '7 jours', colors: colors),
            const SizedBox(width: 8),
            _durationBtn(level: level, days: 15, label: '15 jours', colors: colors),
            const SizedBox(width: 8),
            _durationBtn(level: level, days: 30, label: '30 jours', colors: colors),
          ]),
        ],
      ),
    );
  }

  // ── Bouton durée individuel ───────────────────────────────────────────────
  Widget _durationBtn({
    required int level,
    required int days,
    required String label,
    required List<Color> colors,
  }) {
    final isCurrent = _property.isBoostActive &&
        _property.boostLevel == level &&
        _property.boostType == (days <= 7 ? 'semaine' : days <= 15 ? '15jours' : 'mois');

    return Expanded(
      child: GestureDetector(
        onTap: _boostLoading ? null : () => _applyBoost(level: level, days: days),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: isCurrent
                ? LinearGradient(colors: colors)
                : null,
            color: isCurrent ? null : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCurrent ? colors.first : const Color(0xFFCDD5E0),
              width: 1.5,
            ),
          ),
          child: _boostLoading
              ? const Center(child: SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor)))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? Colors.white : AppTheme.textPrimary,
                      )),
                ]),
        ),
      ),
    );
  }

  // ── Appliquer un boost ────────────────────────────────────────────────────
  Future<void> _applyBoost({required int level, required int days}) async {
    final label = _boostLevelLabel(level);

    // Confirmation
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _boostGradient(level)),
              shape: BoxShape.circle,
            ),
            child: Icon(_boostIcon(level), color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Activer le boost $label',
                style: const TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          _confirmInfoRow(Icons.home_work_outlined, _property.title),
          const SizedBox(height: 8),
          _confirmInfoRow(Icons.workspace_premium_rounded, 'Niveau : $label'),
          const SizedBox(height: 4),
          _confirmInfoRow(Icons.timer_outlined, 'Durée : $days jours'),
          const SizedBox(height: 4),
          _confirmInfoRow(Icons.event_outlined,
              'Expire le : ${_fmtDate(DateTime.now().add(Duration(days: days)))}'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Text(
              level == 3
                  ? '⚡ VIP : cette annonce apparaîtra dans la section Offres Spéciales sur tous les écrans, sans condition de filtre.'
                  : level == 2
                      ? '🔶 Premium : visible dans Offres Spéciales si le pays, la province, la ville, la commune et le type correspondent — les filtres avancés sont ignorés.'
                      : '🔵 Standard : visible dans Offres Spéciales si les 6 critères géographiques et le type correspondent.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: Color(0xFF5D4037), height: 1.4),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(_boostIcon(level), size: 16),
            label: Text('Activer $days jours',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _boostGradient(level).first,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _boostLoading = true);
    try {
      await _ds.boostProperty(_property.id, boostLevel: level, days: days);
      // Recharger la propriété
      if (mounted) {
        setState(() {
          _property = _property.copyWith(
            isFeatured: true,
            boostLevel: level,
            boostEnd: DateTime.now().add(Duration(days: days)),
            boostType: days <= 7 ? 'semaine' : days <= 15 ? '15jours' : 'mois',
          );
          _boostLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            Icon(_boostIcon(level), color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Boost $label activé pour $days jours ✓',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
            )),
          ]),
          backgroundColor: _boostGradient(level).first,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ));
        // Rafraîchir le provider
        if (mounted) context.read<PropertyProvider>().loadAllProperties();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _boostLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    }
  }

  // ── Retirer le boost ──────────────────────────────────────────────────────
  Future<void> _removeBoost() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Retirer le boost',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          'L\'annonce "${_property.title}" ne sera plus mise en avant et sortira de la section Offres Spéciales.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.rocket_outlined, size: 16),
            label: const Text('Retirer', style: TextStyle(fontFamily: 'Poppins')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _boostLoading = true);
    try {
      await _ds.removeBoost(_property.id);
      if (mounted) {
        setState(() {
          _property = _property.copyWith(
            isFeatured: false,
            boostLevel: 0,
            boostEnd: PropertyModel.clearDate,
            boostType: PropertyModel.clearStr,
          );
          _boostLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Boost retiré avec succès.',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Colors.grey,
          behavior: SnackBarBehavior.floating,
        ));
        if (mounted) context.read<PropertyProvider>().loadAllProperties();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _boostLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    }
  }

  Widget _confirmInfoRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 14, color: AppTheme.accentColor),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
              color: AppTheme.textPrimary),
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]);
  }

  // ── Modération ────────────────────────────────────────────────────────────
  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          fontFamily: 'Poppins', color: AppTheme.textPrimary));

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: AppTheme.accentColor),
        const SizedBox(width: 8),
        Text('$label : ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
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
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
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
    await context.read<PropertyProvider>().updateStatus(_property.id, status);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Statut mis à jour : $status'),
        backgroundColor: AppTheme.successColor,
      ));
      Navigator.pop(context);
    }
  }

  Future<void> _deleteProperty(BuildContext context) async {
    final isActive = _property.status == 'Actif';
    final confirmCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
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
          ]),
          content: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isActive)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Annonce ACTIVE — visible par tous les utilisateurs. Sa suppression est définitive et irréversible.',
                    style: TextStyle(fontSize: 11, color: Color(0xFFE65100),
                        fontFamily: 'Poppins', height: 1.4),
                  )),
                ]),
              )
            else
              const Text('Cette action est définitive et irréversible.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary,
                      fontFamily: 'Poppins')),
            if (isActive) ...[
              const SizedBox(height: 14),
              const Text('Tapez SUPPRIMER pour confirmer :',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary, fontFamily: 'Poppins')),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                onChanged: (_) => setStateDialog(() {}),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w600, color: AppTheme.errorColor),
                decoration: InputDecoration(
                  hintText: 'SUPPRIMER',
                  hintStyle: const TextStyle(color: AppTheme.textHint, fontFamily: 'Poppins'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: confirmCtrl.text == 'SUPPRIMER'
                          ? AppTheme.errorColor : AppTheme.dividerColor, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.errorColor, width: 2)),
                  filled: true, fillColor: Colors.white,
                ),
              ),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () { confirmCtrl.dispose(); Navigator.pop(ctx, false); },
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: isActive
                  ? (confirmCtrl.text == 'SUPPRIMER'
                      ? () { confirmCtrl.dispose(); Navigator.pop(ctx, true); }
                      : null)
                  : () { confirmCtrl.dispose(); Navigator.pop(ctx, true); },
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('Supprimer définitivement',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.red.shade200,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && context.mounted) {
      await context.read<PropertyProvider>().deleteProperty(_property.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.delete_forever, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Annonce "${_property.title}" supprimée définitivement',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
              overflow: TextOverflow.ellipsis,
            )),
          ]),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ));
        Navigator.pop(context);
      }
    }
  }
}
