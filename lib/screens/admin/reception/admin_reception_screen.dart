import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/property_image.dart';
import '../../../models/property_model.dart';
import '../../../services/data_service.dart';
import '../../../models/app_notification_model.dart';

class AdminReceptionScreen extends StatefulWidget {
  const AdminReceptionScreen({super.key});
  @override
  State<AdminReceptionScreen> createState() => _AdminReceptionScreenState();
}

class _AdminReceptionScreenState extends State<AdminReceptionScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  late TabController _tabCtrl;
  List<PropertyModel> _pending = [];
  List<PropertyModel> _validated = [];
  List<PropertyModel> _rejected = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final all = await _ds.getProperties();
    setState(() {
      _pending   = all.where((p) => p.status == 'En attente').toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _validated = all.where((p) => p.status == 'Actif').toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _rejected  = all.where((p) => p.status == 'Rejeté').toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _isLoading = false;
    });
  }

  Future<void> _approve(PropertyModel p) async {
    final settings = _ds.systemSettings;
    final days = (settings['announcement_validity_days'] ?? 30) as int;
    await _ds.updatePropertyStatus(p.id, 'Actif');
    // Mettre à jour expiresAt
    final props = await _ds.getProperties();
    final idx = props.indexWhere((x) => x.id == p.id);
    if (idx != -1) {
      final updated = props[idx].copyWith(
        status: 'Actif',
        expiresAt: DateTime.now().add(Duration(days: days)),
        updatedAt: DateTime.now(),
      );
      await _ds.updateProperty(updated);
    }
    _snackOk('✅ Annonce approuvée et publiée pour $days jours');
    _load();
  }

  Future<void> _reject(PropertyModel p, String reason) async {
    await _ds.updatePropertyStatus(p.id, 'Rejeté');
    // Notifier l'annonceur
    await _ds.addNotification(AppNotification(
      id: 'notif_rej_${p.id}_${DateTime.now().millisecondsSinceEpoch}',
      userId: p.ownerId,
      type: 'rejet',
      title: 'Annonce rejetée',
      body: 'Votre annonce "${p.title}" a été rejetée.\nMotif : $reason',
      propertyId: p.id,
      propertyTitle: p.title,
      createdAt: DateTime.now(),
    ));
    _snackErr('❌ Annonce rejetée — annonceur notifié');
    _load();
  }

  void _snackOk(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _snackErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Row(children: [
          const Text('Centre de Réception', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          if (_pending.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.errorColor, borderRadius: BorderRadius.circular(12)),
              child: Text('${_pending.length}', style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white)),
            ),
        ]),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
            tooltip: 'Actualiser',
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFFFFA726),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFFA726),
          unselectedLabelColor: AppTheme.primaryColor,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 11),
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.hourglass_top_rounded, size: 16),
                const SizedBox(width: 4),
                Text('En attente${_pending.isNotEmpty ? " (${_pending.length})" : ""}'),
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_circle_rounded, size: 16),
                const SizedBox(width: 4),
                Text('Approuvées${_validated.isNotEmpty ? " (${_validated.length})" : ""}'),
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cancel_rounded, size: 16),
                const SizedBox(width: 4),
                Text('Rejetées${_rejected.isNotEmpty ? " (${_rejected.length})" : ""}'),
              ]),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(_pending,   canDecide: true),
                _buildList(_validated, canDecide: false),
                _buildList(_rejected,  canDecide: false, showReapprove: true),
              ],
            ),
    );
  }

  Widget _buildList(List<PropertyModel> items,
      {required bool canDecide, bool showReapprove = false}) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(canDecide ? Icons.inbox_rounded : Icons.done_all_rounded,
            size: 64, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(canDecide ? 'Aucune annonce en attente' : 'Aucune annonce ici',
            style: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary, fontSize: 15)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: items.length,
        itemBuilder: (_, i) => _ReceptionCard(
          property: items[i],
          canDecide: canDecide,
          showReapprove: showReapprove,
          onApprove: () => _approve(items[i]),
          onReject: () => _showRejectDialog(items[i]),
          onReapprove: showReapprove ? () => _approve(items[i]) : null,
          onView: () => _showFullDetail(items[i]),
        ),
      ),
    );
  }

  static const List<String> _rejectionReasons = [
    'Contenu interdit ou illégal',
    'Informations fausses ou trompeuses',
    'Image de mauvaise qualité ou interdite',
    'Utilisation de mots clé abusifs',
    'Language inapproprié',
    'Annonce en double',
    'Catégorie incorrecte',
    'Annonce générée par IA',
  ];

  void _showRejectDialog(PropertyModel p) {
    String? _selectedReason;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Motif de rejet', style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Annonce : "${p.title}"',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),
            const Text('Sélectionner une raison :',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _selectedReason == null
                    ? AppTheme.dividerColor : AppTheme.errorColor, width: 1.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedReason,
                  isExpanded: true,
                  hint: const Text('Choisir un motif...',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textHint)),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.errorColor),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textPrimary),
                  onChanged: (val) => setDlgState(() => _selectedReason = val),
                  items: _rejectionReasons.map((reason) => DropdownMenuItem(
                    value: reason,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        const Icon(Icons.cancel_outlined, size: 14, color: AppTheme.errorColor),
                        const SizedBox(width: 8),
                        Expanded(child: Text(reason,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                            overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                  )).toList(),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler',
                    style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary))),
            ElevatedButton(
              onPressed: _selectedReason == null ? null : () {
                Navigator.pop(ctx);
                _reject(p, _selectedReason!);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Rejeter',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullDetail(PropertyModel p) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ReceptionDetailScreen(
        initialProperty: p,
        dataService: _ds,
        onApprove: p.status == 'En attente' ? () { Navigator.pop(context); _approve(p); } : null,
        onReject:  p.status == 'En attente' ? () { Navigator.pop(context); _showRejectDialog(p); } : null,
      ),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CARTE ANNONCE DANS LA LISTE
// ══════════════════════════════════════════════════════════════════════════════
class _ReceptionCard extends StatelessWidget {
  final PropertyModel property;
  final bool canDecide;
  final bool showReapprove;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onReapprove;
  final VoidCallback onView;

  const _ReceptionCard({
    required this.property,
    required this.canDecide,
    required this.showReapprove,
    required this.onApprove,
    required this.onReject,
    this.onReapprove,
    required this.onView,
  });

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return 'il y a ${diff.inDays}j';
    if (diff.inHours > 0) return 'il y a ${diff.inHours}h';
    return 'il y a ${diff.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = property.status == 'En attente'
        ? AppTheme.warningColor
        : property.status == 'Actif'
            ? AppTheme.successColor
            : AppTheme.errorColor;

    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: onView,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── En-tête coloré ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(property.status, style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 12, color: statusColor,
              )),
              const Spacer(),
              Text(_timeAgo(property.createdAt), style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textHint)),
              const SizedBox(width: 6),
              const Icon(Icons.open_in_new_rounded, size: 14, color: AppTheme.textHint),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Miniature + titre ─────────────────────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: PropertyImage(
                        src: property.images.isNotEmpty ? property.images[0] : '',
                        width: 80, height: 80,
                        placeholder: _imgPlaceholder(),
                      ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(property.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 14, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text('${property.type} · ${property.transactionType}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${property.commune}, ${property.city}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Text(property.formattedPrice,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                          fontSize: 15, color: AppTheme.accentColor)),
                ])),
              ]),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // ── Infos annonceur ────────────────────────────────────────────
              _infoRow(Icons.person_outline, 'Annonceur', property.ownerName),
              const SizedBox(height: 4),
              _infoRow(Icons.phone, 'WhatsApp', property.ownerWhatsApp.isNotEmpty ? property.ownerWhatsApp : property.ownerPhone),
              const SizedBox(height: 4),
              _infoRow(Icons.email_outlined, 'Email', property.ownerEmail),
              const SizedBox(height: 4),
              _infoRow(Icons.photo_library_outlined, 'Photos', '${property.images.length} photo(s) jointe(s)'),

              // ── Boutons décision ───────────────────────────────────────────
              if (canDecide) ...[
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: AppTheme.errorColor),
                      label: const Text('Rejeter', style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppTheme.errorColor, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.errorColor, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                      label: const Text('Approuver', style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successColor,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ] else if (showReapprove) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onReapprove,
                    icon: const Icon(Icons.undo_rounded, size: 16, color: Colors.white),
                    label: const Text('Ré-approuver', style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    ));
  }

  Widget _imgPlaceholder() => Container(
    width: 80, height: 80,
    decoration: BoxDecoration(
      color: AppTheme.primaryColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.home_outlined, size: 36, color: AppTheme.accentColor),
  );

  Widget _infoRow(IconData icon, String label, String value) => Row(children: [
    Icon(icon, size: 14, color: AppTheme.accentColor),
    const SizedBox(width: 6),
    Text('$label : ', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
        fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
    Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textPrimary))),
  ]);
}

// ══════════════════════════════════════════════════════════════════════════════
// ÉCRAN DÉTAIL COMPLET (toutes les informations de l'annonce)
// ══════════════════════════════════════════════════════════════════════════════
class _ReceptionDetailScreen extends StatefulWidget {
  final PropertyModel initialProperty;
  final DataService dataService;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _ReceptionDetailScreen({
    required this.initialProperty,
    required this.dataService,
    this.onApprove,
    this.onReject,
  });

  @override
  State<_ReceptionDetailScreen> createState() => _ReceptionDetailScreenState();
}

class _ReceptionDetailScreenState extends State<_ReceptionDetailScreen> {
  PropertyModel? _property;
  bool _loadingDetail = true;

  @override
  void initState() {
    super.initState();
    // Afficher immédiatement avec les données disponibles, puis recharger
    // le document complet depuis Firestore pour garantir que les images
    // (parfois grandes en base64) sont chargées intégralement.
    _property = widget.initialProperty;
    _loadingDetail = false;
    _fetchFullProperty();
  }

  Future<void> _fetchFullProperty() async {
    try {
      final fresh = await widget.dataService.getPropertyById(widget.initialProperty.id);
      if (fresh != null && mounted) {
        setState(() => _property = fresh);
      }
    } catch (_) {
      // On conserve initialProperty si le rechargement échoue
    }
  }

  @override
  Widget build(BuildContext context) {
    final property = _property ?? widget.initialProperty;
    final statusColor = property.status == 'En attente'
        ? AppTheme.warningColor
        : property.status == 'Actif'
            ? AppTheme.successColor
            : AppTheme.errorColor;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Dossier Annonce', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_loadingDetail)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Statut ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Center(child: Text('STATUT : ${property.status.toUpperCase()}',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                    fontSize: 13, color: statusColor))),
          ),
          const SizedBox(height: 14),

          // ── Galerie photos ────────────────────────────────────────────────
          _section('📷 Photos (${property.images.length})',
            property.images.isEmpty
              ? _emptyInfo('Aucune photo soumise')
              : SizedBox(
                  height: 220,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: property.images.length,
                    itemBuilder: (_, i) {
                      final src = property.images[i];
                      // Déterminer le type de source pour l'étiquette de débogage
                      final label = src.startsWith('data:image/')
                          ? 'base64 (${(src.length / 1024).toStringAsFixed(0)} KB)'
                          : src.startsWith('http')
                              ? 'URL réseau'
                              : 'Chemin local';
                      return Padding(
                        padding: EdgeInsets.only(right: i < property.images.length - 1 ? 10 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: PropertyImage(
                                src: src,
                                width: 240, height: 190,
                                placeholder: Container(
                                  width: 240, height: 190,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    const Icon(Icons.broken_image_outlined, size: 40, color: AppTheme.accentColor),
                                    const SizedBox(height: 6),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('Photo ${i + 1} non disponible',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                              color: AppTheme.textSecondary)),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Photo ${i + 1} · $label',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 9,
                                    color: AppTheme.textHint)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          ),
          const SizedBox(height: 14),

          // ── Infos du bien ──────────────────────────────────────────────────
          _section('Informations du bien', Column(children: [
            _row('Titre',          property.title),
            _row('Type de propriété',   property.type),
            _row('Transaction',    property.transactionType),
            _row('Prix',           property.formattedPrice),
            if (property.surface != null) _row('Surface', '${property.surface!.toStringAsFixed(0)} m²'),
            if (property.bedrooms != null) _row('Chambres', '${property.bedrooms}'),
            if (property.bathrooms != null) _row('Salles de bain', '${property.bathrooms}'),
            _row('Parking',        property.hasParking ? 'Oui' : 'Non'),
            if (property.amenities.isNotEmpty)
              _row('Équipements', property.amenities.join(', ')),
          ])),
          const SizedBox(height: 14),

          // ── Adresse ────────────────────────────────────────────────────────
          _section('Adresse complète', Column(children: [
            _row('Pays',      'Congo (RDC)'),
            _row('Province',  property.province),
            _row('Ville',     property.city),
            _row('Commune',   property.commune),
            _row('Quartier',  property.quartier),
            _row('Avenue',    property.address),
          ])),
          const SizedBox(height: 14),

          // ── Description ───────────────────────────────────────────────────
          _section('📝 Description', Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(property.description.isEmpty ? 'Aucune description' : property.description,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: AppTheme.textSecondary, height: 1.6)),
          )),
          const SizedBox(height: 14),

          // ── Infos annonceur ────────────────────────────────────────────────
          _section('👤 Coordonnées de l\'annonceur', Column(children: [
            _row('Nom complet',     property.ownerName),
            _rowCopy(context, 'WhatsApp', property.ownerWhatsApp.isNotEmpty ? property.ownerWhatsApp : property.ownerPhone),
            _rowCopy(context, 'Email',    property.ownerEmail),
            _row('Date de soumission', _formatDate(property.createdAt)),
          ])),
          const SizedBox(height: 14),

          // ── Paiement soumis ───────────────────────────────────────────────
          _section('💳 Informations de paiement', Column(children: [
            _row('Pack choisi',  'À vérifier dans l\'onglet Paiements'),
            _row('Statut paiement', 'En attente de validation'),
          ])),
          const SizedBox(height: 20),

          // ── Boutons décision ───────────────────────────────────────────────
          if (widget.onApprove != null && widget.onReject != null) ...[
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onReject,
                  icon: const Icon(Icons.cancel_outlined, size: 18, color: AppTheme.errorColor),
                  label: const Text('Rejeter', style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppTheme.errorColor)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.errorColor, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: widget.onApprove,
                  icon: const Icon(Icons.check_circle_outline, size: 18, color: Colors.white),
                  label: const Text('Approuver & Publier', style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 30),
          ],
        ]),
      ),
    );
  }

  Widget _section(String title, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppTheme.primaryColor, AppTheme.primaryDark]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(title, style: const TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: child,
      ),
    ],
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120, child: Text('$label :', style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary))),
      Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _rowCopy(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120, child: Text('$label :', style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary))),
      Expanded(child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$label copié !', style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ));
        },
        child: Row(children: [
          Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: AppTheme.accentColor,
              fontWeight: FontWeight.w700, decoration: TextDecoration.underline))),
          const SizedBox(width: 4),
          const Icon(Icons.copy_rounded, size: 14, color: AppTheme.accentColor),
        ]),
      ))),
    ]),
  );

  Widget _emptyInfo(String msg) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(msg, style: const TextStyle(fontFamily: 'Poppins',
        fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic)),
  );

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      'à ${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
}
