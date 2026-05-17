import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/data_service.dart';

/// Écran admin — Gestion des zones géographiques et crédits par commune
class AdminZonesScreen extends StatefulWidget {
  const AdminZonesScreen({super.key});
  @override
  State<AdminZonesScreen> createState() => _AdminZonesScreenState();
}

class _AdminZonesScreenState extends State<AdminZonesScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  bool _isLoading = true;
  bool _isSaving  = false;

  // zones : { 'Commune': { 'credits': int, 'standing': string } }
  Map<String, dynamic> _zones = {};

  // Filtre en cascade pour ajouter/modifier
  String _filterCountry  = AppConstants.defaultCountry;
  String? _filterProvince;
  String? _filterCity;

  // standing presets
  static const List<String> _standings = [
    'Standard', 'Intermédiaire', 'Premium', 'Luxe',
  ];
  static const Map<String, int> _standingDefaults = {
    'Standard':     1,
    'Intermédiaire':3,
    'Premium':      5,
    'Luxe':         10,
  };

  // Listes dynamiques
  List<String> get _availableProvinces =>
      AppConstants.getProvincesForCountry(_filterCountry);
  List<String> get _availableCities =>
      _filterProvince != null
          ? AppConstants.getCitiesForProvince(_filterCountry, _filterProvince!)
          : [];


  // Communes filtrées affichées dans la liste
  List<MapEntry<String, dynamic>> get _filteredZoneEntries {
    if (_filterCity != null) {
      final communes = AppConstants.getCommunesForCity(_filterCity!);
      return communes.map((c) => MapEntry(c, _zones[c] ?? {'credits': 1, 'standing': 'Standard'})).toList();
    }
    if (_filterProvince != null) {
      final cities = _availableCities;
      final Set<String> allCommunes = {};
      for (final city in cities) {
        allCommunes.addAll(AppConstants.getCommunesForCity(city));
      }
      return allCommunes.map((c) => MapEntry(c, _zones[c] ?? {'credits': 1, 'standing': 'Standard'})).toList();
    }
    // Afficher toutes les communes configurées + celles du pays
    final provinces = _availableProvinces;
    final Set<String> allCommunes = {};
    for (final prov in provinces) {
      final cities = AppConstants.getCitiesForProvince(_filterCountry, prov);
      for (final city in cities) {
        allCommunes.addAll(AppConstants.getCommunesForCity(city));
      }
    }
    return allCommunes.map((c) => MapEntry(c, _zones[c] ?? {'credits': 1, 'standing': 'Standard'})).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _zones = Map<String, dynamic>.from(_ds.geographicZones);
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await _ds.saveGeographicZones(_zones);
    setState(() => _isSaving = false);
    _snackOk('✅ Zones géographiques sauvegardées');
  }

  void _setZone(String commune, int credits, String standing) {
    setState(() {
      _zones[commune] = {'credits': credits, 'standing': standing};
    });
  }

  void _removeZone(String commune) {
    setState(() => _zones.remove(commune));
  }

  void _applyStandingToAll(String standing) {
    final credits = _standingDefaults[standing] ?? 1;
    for (final entry in _filteredZoneEntries) {
      _zones[entry.key] = {'credits': credits, 'standing': standing};
    }
    setState(() {});
    _snackOk('Standing "$standing" appliqué à toutes les communes affichées');
  }

  void _showEditDialog(String commune, Map<String, dynamic> current) {
    int credits = (current['credits'] as num?)?.toInt() ?? 1;
    String standing = current['standing'] as String? ?? 'Standard';
    final credCtrl = TextEditingController(text: '$credits');

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.location_on, color: AppTheme.accentColor, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(commune,
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // Crédits requis
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Crédits requis pour publier *',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: credCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.toll_outlined, color: AppTheme.accentColor, size: 18),
                hintText: 'Ex: 5',
                filled: true, fillColor: AppTheme.backgroundColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor)),
                suffixText: 'crédits',
                suffixStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.textHint),
              ),
              onChanged: (v) => setS(() => credits = int.tryParse(v) ?? 1),
            ),
            const SizedBox(height: 14),
            // Standing
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Standing de la zone',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _standings.map((s) {
                final isSelected = s == standing;
                return GestureDetector(
                  onTap: () {
                    setS(() {
                      standing = s;
                      credits = _standingDefaults[s] ?? 1;
                      credCtrl.text = '$credits';
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? _standingColor(s) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? _standingColor(s) : AppTheme.dividerColor,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(s, style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                    )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '10 USD = 100 crédits  •  1 crédit = 0,10 USD\nCette zone coûte $credits crédit${credits > 1 ? 's' : ''} (${(credits * 0.1).toStringAsFixed(2)} USD)',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.accentColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                final c = int.tryParse(credCtrl.text) ?? 1;
                _setZone(commune, c < 1 ? 1 : c, standing);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Confirmer',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Color _standingColor(String standing) {
    switch (standing) {
      case 'Standard':     return Colors.green;
      case 'Intermédiaire': return AppTheme.accentColor;
      case 'Premium':      return AppTheme.warningColor;
      case 'Luxe':         return const Color(0xFFBE9C48);
      default:             return AppTheme.textSecondary;
    }
  }

  IconData _standingIcon(String standing) {
    switch (standing) {
      case 'Standard':     return Icons.star_border;
      case 'Intermédiaire': return Icons.star_half;
      case 'Premium':      return Icons.star;
      case 'Luxe':         return Icons.workspace_premium_rounded;
      default:             return Icons.location_on_outlined;
    }
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

  @override
  Widget build(BuildContext context) {
    final entries = _filteredZoneEntries;
    final configuredCount = entries.where((e) => _zones.containsKey(e.key)).length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Zones Géographiques',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: AppTheme.primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded, color: AppTheme.accentColor),
            tooltip: 'Sauvegarder',
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : Column(children: [

              // ── Bannière info crédits ──────────────────────────────────────
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.toll_outlined, color: AppTheme.accentColor, size: 18),
                    SizedBox(width: 8),
                    Text('Système de crédits',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                            fontSize: 13, color: AppTheme.accentColor)),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                    '10 USD = 100 crédits  •  1 crédit = 0,10 USD\n'
                    'Fixez ici le coût en crédits pour publier dans chaque commune.\n'
                    'Plus la zone est premium, plus vous pouvez demander de crédits.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        color: AppTheme.accentColor, height: 1.5),
                  ),
                ]),
              ),

              // ── Filtres en cascade ─────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                margin: const EdgeInsets.only(top: 12),
                child: Column(children: [
                  // Pays
                  _buildDropdown(
                    label: 'Pays', value: _filterCountry,
                    items: AppConstants.countries,
                    icon: Icons.public,
                    onChanged: (v) {
                      if (v != null) setState(() {
                        _filterCountry = v;
                        _filterProvince = null;
                        _filterCity = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  // Province + Ville en ligne
                  Row(children: [
                    Expanded(child: _buildDropdown(
                      label: 'Province', value: _filterProvince,
                      items: _availableProvinces,
                      icon: Icons.map_outlined,
                      onChanged: (v) => setState(() {
                        _filterProvince = v;
                        _filterCity = null;
                      }),
                      nullable: true,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _buildDropdown(
                      label: 'Ville', value: _filterCity,
                      items: _availableCities,
                      icon: Icons.location_city,
                      onChanged: (v) => setState(() => _filterCity = v),
                      nullable: true,
                    )),
                  ]),
                ]),
              ),

              // ── Barre de stats + actions groupées ─────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppTheme.backgroundColor,
                child: Row(children: [
                  Text('$configuredCount/${entries.length} commune(s) configurée(s)',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.auto_fix_high, color: AppTheme.accentColor),
                    tooltip: 'Appliquer un standing à toutes',
                    itemBuilder: (_) => _standings.map((s) => PopupMenuItem(
                      value: s,
                      child: Row(children: [
                        Icon(_standingIcon(s), color: _standingColor(s), size: 16),
                        const SizedBox(width: 8),
                        Text('$s (${_standingDefaults[s]} crédits)',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                      ]),
                    )).toList(),
                    onSelected: _applyStandingToAll,
                  ),
                ]),
              ),

              // ── Liste des communes ─────────────────────────────────────────
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_off, size: 56, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            const Text('Aucune commune trouvée',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                    color: AppTheme.textSecondary)),
                            const SizedBox(height: 8),
                            const Text('Sélectionnez un pays, une province ou une ville.',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                    color: AppTheme.textHint)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final commune = entries[i].key;
                          final data    = _zones[commune] as Map<String, dynamic>?;
                          final credits = (data?['credits'] as num?)?.toInt() ?? 1;
                          final standing = data?['standing'] as String? ?? 'Standard';
                          final isConfigured = _zones.containsKey(commune);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isConfigured
                                    ? _standingColor(standing).withValues(alpha: 0.4)
                                    : AppTheme.dividerColor,
                              ),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6,
                              )],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _standingColor(standing).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_standingIcon(standing),
                                    color: _standingColor(standing), size: 20),
                              ),
                              title: Text(commune, style: const TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                fontSize: 13, color: AppTheme.textPrimary,
                              )),
                              subtitle: isConfigured
                                  ? Text(
                                      '$standing • $credits crédit${credits > 1 ? 's' : ''} '
                                      '(${(credits * 0.1).toStringAsFixed(2)} USD)',
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                          color: _standingColor(standing), fontWeight: FontWeight.w600),
                                    )
                                  : const Text('Non configurée — défaut système',
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                          color: AppTheme.textHint)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                // Badge crédits
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isConfigured
                                        ? _standingColor(standing)
                                        : AppTheme.dividerColor,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isConfigured ? '$credits cr.' : 'défaut',
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                        fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, color: AppTheme.textHint, size: 20),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'edit',
                                        child: Row(children: [
                                          Icon(Icons.edit_outlined, size: 16, color: AppTheme.accentColor),
                                          SizedBox(width: 8),
                                          Text('Configurer', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                                        ])),
                                    if (isConfigured)
                                      const PopupMenuItem(value: 'reset',
                                          child: Row(children: [
                                            Icon(Icons.refresh, size: 16, color: AppTheme.textSecondary),
                                            SizedBox(width: 8),
                                            Text('Réinitialiser', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                                          ])),
                                  ],
                                  onSelected: (v) {
                                    if (v == 'edit') {
                                      _showEditDialog(commune, data ?? {'credits': 1, 'standing': 'Standard'});
                                    } else if (v == 'reset') {
                                      _removeZone(commune);
                                    }
                                  },
                                ),
                              ]),
                              onTap: () => _showEditDialog(
                                  commune, data ?? {'credits': 1, 'standing': 'Standard'}),
                            ),
                          );
                        },
                      ),
              ),
            ]),

      // ── Bouton Sauvegarder ───────────────────────────────────────────────────
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.dividerColor.withValues(alpha: 0.5))),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2),
          )],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded, color: Colors.white, size: 18),
            label: const Text('Sauvegarder les zones',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
    bool nullable = false,
  }) {
    final safeItems = items.toList();
    final safeValue = safeItems.contains(value) ? value : null;
    return DropdownButtonFormField<String>(
      value: safeValue,
      hint: Text(label, style: const TextStyle(fontSize: 12, fontFamily: 'Poppins', color: AppTheme.textHint)),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: Icon(icon, size: 16, color: AppTheme.accentColor),
        isDense: true,
      ),
      isExpanded: true,
      items: [
        if (nullable)
          const DropdownMenuItem<String>(
            value: null,
            child: Text('Tous', style: TextStyle(fontSize: 12, fontFamily: 'Poppins', color: AppTheme.textHint)),
          ),
        ...safeItems.map((s) => DropdownMenuItem(
          value: s,
          child: Text(s, style: const TextStyle(fontSize: 12, fontFamily: 'Poppins'), overflow: TextOverflow.ellipsis),
        )),
      ],
      onChanged: onChanged,
    );
  }
}
