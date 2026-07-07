import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/property_model.dart';
import 'admin_property_detail_screen.dart';

class AdminPropertiesScreen extends StatefulWidget {
  const AdminPropertiesScreen({super.key});

  @override
  State<AdminPropertiesScreen> createState() => _AdminPropertiesScreenState();
}

class _AdminPropertiesScreenState extends State<AdminPropertiesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<PropertyModel> _allProperties = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await context.read<PropertyProvider>().loadAllProperties();
    setState(() {
      _allProperties = context.read<PropertyProvider>().properties;
      _isLoading = false;
    });
  }

  List<PropertyModel> _filtered(String status) {
    return _allProperties.where((p) {
      // L'onglet 'Tous' n'affiche PAS les supprimés (ils ont leur propre onglet)
      if (status == 'Tous') {
        if (p.status == 'Supprimé') return false;
      } else {
        if (p.status != status) return false;
      }
      final matchSearch = _searchQuery.isEmpty ||
          p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.ownerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.city.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchSearch;
    }).toList();
  }

  List<PropertyModel> _filteredDeleted() {
    return _allProperties.where((p) {
      if (p.status != 'Supprimé') return false;
      final matchSearch = _searchQuery.isEmpty ||
          p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.ownerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.city.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchSearch;
    }).toList();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Gestion des Annonces'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle: const TextStyle(color: AppTheme.textHint, fontFamily: 'Poppins'),
                    prefixIcon: const Icon(Icons.search, color: AppTheme.textHint, size: 20),
                    fillColor: const Color(0xFFEEF2FA),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
              TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                labelColor: const Color(0xFFFFA726),
                unselectedLabelColor: AppTheme.primaryColor,
                indicatorColor: const Color(0xFFFFA726),
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12),
                tabs: [
                  Tab(text: 'Tous (${_filtered('Tous').length})'),
                  Tab(text: 'En attente (${_filtered('En attente').length})'),
                  Tab(text: 'Actifs (${_filtered('Actif').length})'),
                  Tab(text: 'Rejetés (${_filtered('Rejeté').length})'),
                  Tab(text: 'Supprimés (${_filteredDeleted().length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList('Tous'),
                _buildList('En attente'),
                _buildList('Actif'),
                _buildList('Rejeté'),
                _buildDeletedList(),
              ],
            ),
    );
  }

  Widget _buildList(String status) {
    final items = _filtered(status);
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_work_outlined, size: 64, color: AppTheme.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('Aucune annonce ${status == 'Tous' ? '' : status.toLowerCase()}',
                style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Poppins')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final prop = items[index];
          return _AdminPropertyTile(
            property: prop,
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AdminPropertyDetailScreen(property: prop)));
              _loadData();
            },
            onStatusChange: (newStatus) async {
              final provider = context.read<PropertyProvider>();
              final messenger = ScaffoldMessenger.of(context);
              await provider.updateStatus(prop.id, newStatus);
              _loadData();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Statut mis à jour: $newStatus'),
                  backgroundColor: AppTheme.successColor,
                ),
              );
            },
            onDelete: () async {
              final provider = context.read<PropertyProvider>();
              final messenger = ScaffoldMessenger.of(context);
              final result = await _confirmDelete(context, prop);
              if (result == null) return;
              // Suppression douce : status='Supprimé' + deletedAt + notification
              await provider.softDeleteProperty(prop.id, result);
              _loadData();
              messenger.showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'Annonce "${prop.title}" supprimée — restaurable 24 h',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      )),
                    ],
                  ),
                  backgroundColor: AppTheme.errorColor,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  duration: const Duration(seconds: 4),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static const List<String> _deletionReasons = [
    'Contenu interdit ou illégal',
    'Informations fausses ou trompeuses',
    'Image de mauvaise qualité ou interdite',
    'Utilisation de mots clé abusifs',
    'Language inapproprié',
    'Annonce en double',
    'Catégorie incorrecte',
    'Annonce générée par IA',
  ];

  // Retourne la raison choisie, ou null si annulation
  Future<String?> _confirmDelete(BuildContext context, PropertyModel prop) {
    final isActive = prop.status == 'Actif';
    final confirmCtrl = TextEditingController();
    String? selectedReason;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
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
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Aperçu annonce avec vraie image
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildPropertyImage(prop.mainImage, 52),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prop.title,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                fontFamily: 'Poppins', color: AppTheme.textPrimary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(prop.ownerName,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary,
                                fontFamily: 'Poppins')),
                        Text(prop.formattedPrice,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor, fontFamily: 'Poppins')),
                      ],
                    )),
                  ]),
                ),
                const SizedBox(height: 12),
                // Bandeau non-remboursable
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.money_off_rounded, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(child: Text(
                      'Suppression non remboursable. Les crédits utilisés ne seront pas restitutés.',
                      style: TextStyle(fontSize: 11, color: Colors.red,
                          fontFamily: 'Poppins', height: 1.4),
                    )),
                  ]),
                ),
                const SizedBox(height: 12),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        'Annonce ACTIVE — visible par tous les utilisateurs.',
                        style: TextStyle(fontSize: 11, color: Color(0xFFE65100),
                            fontFamily: 'Poppins', height: 1.4),
                      )),
                    ]),
                  ),
                const SizedBox(height: 14),
                // Dropdown raison
                const Text('Motif de suppression *',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selectedReason == null ? AppTheme.dividerColor : AppTheme.errorColor,
                      width: 1.5,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedReason,
                      isExpanded: true,
                      hint: const Text('Choisir un motif...',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                              color: AppTheme.textHint)),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppTheme.errorColor),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: AppTheme.textPrimary),
                      onChanged: (val) => setDlg(() => selectedReason = val),
                      items: _deletionReasons.map((r) => DropdownMenuItem(
                        value: r,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            const Icon(Icons.cancel_outlined, size: 13,
                                color: AppTheme.errorColor),
                            const SizedBox(width: 8),
                            Expanded(child: Text(r,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                                overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                      )).toList(),
                    ),
                  ),
                ),
                // Confirmation texte si annonce active
                if (isActive) ...[  
                  const SizedBox(height: 14),
                  const Text('Tapez SUPPRIMER pour confirmer :',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary, fontFamily: 'Poppins')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmCtrl,
                    onChanged: (_) => setDlg(() {}),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                        fontWeight: FontWeight.w600, color: AppTheme.errorColor),
                    decoration: InputDecoration(
                      hintText: 'SUPPRIMER',
                      hintStyle: const TextStyle(color: AppTheme.textHint, fontFamily: 'Poppins'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: confirmCtrl.text == 'SUPPRIMER'
                              ? AppTheme.errorColor : AppTheme.dividerColor, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.errorColor, width: 2),
                      ),
                      filled: true, fillColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () { confirmCtrl.dispose(); Navigator.pop(ctx, null); },
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: selectedReason == null
                  ? null
                  : (isActive && confirmCtrl.text != 'SUPPRIMER'
                      ? null
                      : () { confirmCtrl.dispose(); Navigator.pop(ctx, selectedReason); }),
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
  }

  Widget _buildDeletedList() {
    final items = _filteredDeleted();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 64,
                color: AppTheme.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text('Aucune annonce supprimée',
                style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Poppins')),
            const SizedBox(height: 6),
            const Text('Les annonces supprimées apparaissent ici\npendant 24 h avant suppression définitive.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textHint, fontFamily: 'Poppins', fontSize: 12)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final prop = items[index];
          final deletedAt = prop.deletedAt;
          final now = DateTime.now();
          final canRestore = deletedAt == null ||
              now.difference(deletedAt).inHours < 24;
          final hoursLeft = deletedAt != null
              ? (24 - now.difference(deletedAt).inHours).clamp(0, 24)
              : 24;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: canRestore
                    ? Colors.orange.shade200
                    : Colors.red.shade200,
                width: 1.5,
              ),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8, offset: const Offset(0, 2),
              )],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _buildPropertyImage(prop.mainImage, 72),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prop.title,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                fontFamily: 'Poppins', color: AppTheme.textPrimary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${prop.commune}, ${prop.city}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary,
                                fontFamily: 'Poppins')),
                        Text('Annonceur: ${prop.ownerName}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary,
                                fontFamily: 'Poppins')),
                        const SizedBox(height: 6),
                        // Barre de temps restant
                        if (canRestore)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 13, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text(
                                  hoursLeft <= 1
                                      ? 'Restaurable encore < 1 h'
                                      : 'Restaurable encore $hoursLeft h',
                                  style: const TextStyle(
                                      fontSize: 10, fontFamily: 'Poppins',
                                      color: Color(0xFFE65100), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.cancel_outlined, size: 13, color: Colors.red),
                                SizedBox(width: 4),
                                Text('Délai 24 h dépassé — suppression définitive',
                                    style: TextStyle(fontSize: 10, fontFamily: 'Poppins',
                                        color: Colors.red, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (canRestore)
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () async {
                                    final provider = context.read<PropertyProvider>();
                                    final messenger = ScaffoldMessenger.of(context);
                                    try {
                                      await provider.restoreProperty(prop.id);
                                      _loadData();
                                      messenger.showSnackBar(SnackBar(
                                        content: Row(children: [
                                          const Icon(Icons.restore, color: Colors.white, size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(
                                            'Annonce "${prop.title}" restaurée',
                                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          )),
                                        ]),
                                        backgroundColor: AppTheme.successColor,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        duration: const Duration(seconds: 3),
                                      ));
                                    } catch (e) {
                                      messenger.showSnackBar(SnackBar(
                                        content: Text('Erreur: $e',
                                            style: const TextStyle(fontFamily: 'Poppins')),
                                        backgroundColor: AppTheme.errorColor,
                                      ));
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.successColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.restore, color: Colors.white, size: 15),
                                        SizedBox(width: 5),
                                        Text('Restaurer',
                                            style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                                fontWeight: FontWeight.w600, color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            // Suppression définitive immédiate
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () async {
                                  final provider = context.read<PropertyProvider>();
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16)),
                                      title: const Text('Suppression définitive',
                                          style: TextStyle(fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w700, fontSize: 16)),
                                      content: Text(
                                        'Supprimer définitivement "${prop.title}" ?\nCette action est irréversible.',
                                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Annuler',
                                              style: TextStyle(fontFamily: 'Poppins')),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: AppTheme.errorColor),
                                          child: const Text('Supprimer',
                                              style: TextStyle(fontFamily: 'Poppins',
                                                  color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  await provider.deleteProperty(prop.id);
                                  _loadData();
                                  messenger.showSnackBar(SnackBar(
                                    content: const Text('Annonce supprimée définitivement',
                                        style: TextStyle(fontFamily: 'Poppins')),
                                    backgroundColor: AppTheme.errorColor,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.errorColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.4)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.delete_forever, color: AppTheme.errorColor, size: 15),
                                      SizedBox(width: 5),
                                      Text('Supprimer',
                                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                              fontWeight: FontWeight.w600, color: AppTheme.errorColor)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Widget image intelligent: local (File), base64 ou réseau
  Widget _buildPropertyImage(String src, double size) {
    final placeholder = Container(
      width: size, height: size,
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      child: Icon(Icons.home_rounded, color: AppTheme.accentColor, size: size * 0.5),
    );
    if (src.isEmpty || src.startsWith('https://images.unsplash.com')) return placeholder;
    if (src.startsWith('data:image') || (src.length > 200 && !src.startsWith('http'))) {
      try {
        final b64 = src.contains(',') ? src.split(',').last : src;
        final bytes = base64Decode(b64);
        return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder);
      } catch (_) { return placeholder; }
    }
    if (!kIsWeb && !src.startsWith('http')) {
      final file = File(src);
      return Image.file(file, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder);
    }
    return Image.network(src, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder);
  }
}

class _AdminPropertyTile extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback onTap;
  final Function(String) onStatusChange;
  final VoidCallback onDelete;

  const _AdminPropertyTile({
    required this.property,
    required this.onTap,
    required this.onStatusChange,
    required this.onDelete,
  });

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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildPropertyImageStatic(property.mainImage, 80),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(property.title,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins', color: AppTheme.textPrimary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        // Badge boost niveau
                        if (property.isBoostActive) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: property.isVip
                                    ? [const Color(0xFF7B1FA2), const Color(0xFFE040FB)]
                                    : property.isPremium
                                        ? [const Color(0xFFE65100), const Color(0xFFFF9800)]
                                        : [const Color(0xFF1565C0), const Color(0xFF42A5F5)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                property.isVip
                                    ? Icons.workspace_premium_rounded
                                    : Icons.star_rounded,
                                color: Colors.white, size: 10,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                property.isVip ? 'VIP'
                                    : property.isPremium ? 'PRO' : 'STD',
                                style: const TextStyle(fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Poppins',
                                    color: Colors.white),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _statusColor(property.status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(property.status,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins', color: _statusColor(property.status))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${property.commune}, ${property.city}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary,
                            fontFamily: 'Poppins')),
                    Text('Annonceur: ${property.ownerName}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary,
                            fontFamily: 'Poppins')),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(property.formattedPrice,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor, fontFamily: 'Poppins')),
                        Row(
                          children: [
                            // Quick approve if pending
                            if (property.status == 'En attente')
                              _iconBtn(Icons.check_circle_outline, AppTheme.successColor,
                                  () => onStatusChange('Actif')),
                            if (property.status == 'En attente')
                              _iconBtn(Icons.cancel_outlined, AppTheme.errorColor,
                                  () => onStatusChange('Rejeté')),
                            _iconBtn(Icons.delete_outline, AppTheme.errorColor, onDelete),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onPressed) {
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(icon, color: color, size: 22),
      ),
    ));
  }

  /// Affiche la vraie image de la propriété (locale, base64 ou réseau)
  Widget _buildPropertyImageStatic(String src, double size) {
    final placeholder = Container(
      width: size, height: size,
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      child: Icon(Icons.home_rounded, color: AppTheme.accentColor, size: size * 0.5),
    );
    if (src.isEmpty || src.startsWith('https://images.unsplash.com')) return placeholder;
    if (src.startsWith('data:image') || (src.length > 200 && !src.startsWith('http'))) {
      try {
        final b64 = src.contains(',') ? src.split(',').last : src;
        final bytes = base64Decode(b64);
        return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder);
      } catch (_) { return placeholder; }
    }
    if (!kIsWeb && !src.startsWith('http')) {
      return Image.file(File(src), width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder);
    }
    return Image.network(src, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder);
  }
}
