import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/data_service.dart';

/// Ecran admin — Zones geographiques
///
/// NOUVELLE ARCHITECTURE :
///   1. Section "Zones" — 4 niveaux (Standard / Intermediaire / Premium / Luxe)
///      Chaque zone a un nombre d'unites configurable par l'admin
///   2. Section "Communes" — on assigne chaque commune a une zone
///      Le cout annonce = unites de la zone assignee
///
/// Stockage Firestore :
///   config/zones_config  -> { 'Standard': {'units': 1}, 'Intermediaire': {'units': 3}, ... }
///   config/geographic_zones -> { 'Commune': {'zone': 'Standard', 'city': '', 'country': ''} }
class AdminZonesScreen extends StatefulWidget {
  const AdminZonesScreen({super.key});
  @override
  State<AdminZonesScreen> createState() => _AdminZonesScreenState();
}

class _AdminZonesScreenState extends State<AdminZonesScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  late TabController _tabCtrl;

  bool _isLoading = true;
  bool _isSaving = false;

  // ── Zone config : { 'Standard': {'units': 1, 'color': ...}, ... } ──────────
  // Unites par zone (editables par l'admin)
  Map<String, int> _zoneUnits = {
    'Standard':       1,
    'Intermediaire':  3,
    'Premium':        5,
    'Luxe':           10,
  };

  // Ordre fixe des zones
  static const List<String> _zoneNames = [
    'Standard', 'Intermediaire', 'Premium', 'Luxe',
  ];

  static const Map<String, Color> _zoneColors = {
    'Standard':       Colors.grey,
    'Intermediaire':  Colors.blue,
    'Premium':        Colors.orange,
    'Luxe':           Colors.purple,
  };

  static const Map<String, IconData> _zoneIcons = {
    'Standard':       Icons.star_outline_rounded,
    'Intermediaire':  Icons.star_half_rounded,
    'Premium':        Icons.star_rounded,
    'Luxe':           Icons.diamond_outlined,
  };

  // ── Communes : { 'Commune': {'zone': 'Standard', 'city': '', 'country': ''} }
  Map<String, dynamic> _communeAssignments = {};

  // Navigation pays/ville
  static const List<Map<String, String>> _countries = [
    {'code': 'Congo (RDC)',         'label': 'Congo (RDC)'},
    {'code': 'Congo (Brazzaville)', 'label': 'Congo-Brazzaville'},
  ];
  String _selectedCountry = 'Congo (RDC)';
  String? _selectedCity;

  // ── Getters ────────────────────────────────────────────────────────────────
  List<String> get _citiesForCountry {
    if (_selectedCountry == 'Congo (Brazzaville)') {
      final Set<String> all = {};
      for (final p in AppConstants.provincesBrazzaville) {
        all.addAll(AppConstants.getCitiesForProvince(_selectedCountry, p));
      }
      return all
          .where((c) => AppConstants.getCommunesForCity(c).isNotEmpty)
          .toList()
        ..sort();
    }
    return AppConstants.cities
        .where((c) => AppConstants.getCommunesForCity(c).isNotEmpty)
        .toList()
      ..sort();
  }

  List<String> get _communesForSelectedCity {
    if (_selectedCity == null) return [];
    return AppConstants.getCommunesForCity(_selectedCity!);
  }

  int get _configuredCountForCountry {
    return _communeAssignments.values.where((v) {
      final m = v as Map<String, dynamic>;
      return (m['country'] as String?) == _selectedCountry;
    }).length;
  }

  int get _configuredCountForCity {
    if (_selectedCity == null) return 0;
    return _communesForSelectedCity
        .where((c) => _communeAssignments.containsKey(c))
        .length;
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    // Charger config des zones (unites)
    final zonesConfig = _ds.zonesConfig;
    if (zonesConfig.isNotEmpty) {
      for (final name in _zoneNames) {
        final cfg = zonesConfig[name];
        if (cfg != null) {
          _zoneUnits[name] = (cfg['units'] as num?)?.toInt() ?? _zoneUnits[name]!;
        }
      }
    }

    // Charger assignations communes
    final raw = _ds.geographicZones;
    // Support ancien format { commune: {credits, standing} } ET nouveau format { commune: {zone, ...} }
    final converted = <String, dynamic>{};
    for (final entry in raw.entries) {
      final v = entry.value as Map<String, dynamic>;
      if (v.containsKey('zone')) {
        converted[entry.key] = v;
      } else if (v.containsKey('standing')) {
        // Migration ancien format
        converted[entry.key] = {
          'zone': v['standing'] ?? 'Standard',
          'city': v['city'] ?? '',
          'country': v['country'] ?? '',
        };
      }
    }
    _communeAssignments = converted;

    setState(() => _isLoading = false);
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);

    // Sauvegarder config zones
    final zonesConfigMap = <String, dynamic>{};
    for (final name in _zoneNames) {
      zonesConfigMap[name] = {'units': _zoneUnits[name] ?? 1};
    }
    await _ds.saveZonesConfig(zonesConfigMap);

    // Sauvegarder assignations communes (au format zone)
    await _ds.saveGeographicZones(_communeAssignments);

    setState(() => _isSaving = false);
    _snackOk('Configuration des zones sauvegardee');
  }

  void _assignCommune(String commune, String zoneName) {
    setState(() {
      _communeAssignments[commune] = {
        'zone': zoneName,
        'city': _selectedCity ?? '',
        'country': _selectedCountry,
      };
    });
  }

  void _removeCommune(String commune) {
    setState(() => _communeAssignments.remove(commune));
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

  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Zones Geographiques',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFFFFA726),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 12),
          tabs: const [
            Tab(icon: Icon(Icons.layers_rounded, size: 16), text: 'Zones'),
            Tab(icon: Icon(Icons.map_outlined, size: 16), text: 'Communes'),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded, color: Colors.white),
            tooltip: 'Sauvegarder',
            onPressed: _isSaving ? null : _saveAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildZonesTab(),
                _buildCommunesTab(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
                top: BorderSide(
                    color: AppTheme.dividerColor.withValues(alpha: 0.5))),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2))
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAll,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded, color: Colors.white, size: 18),
            label: const Text('Sauvegarder la configuration',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                      color: Color(0xFFFFA726), width: 1.5)),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ONGLET 1 — ZONES (configuration des unites par zone)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildZonesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Bandeau explicatif
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppTheme.accentColor.withValues(alpha: 0.3)),
          ),
          child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.accentColor, size: 18),
                  SizedBox(width: 8),
                  Text('Systeme de zones et unites',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.accentColor)),
                ]),
                SizedBox(height: 8),
                Text(
                  '10 USD = 100 unites  •  1 unite = 0,10 USD\n\n'
                  'Chaque zone a un nombre d\'unites. Quand une commune est assignee a une zone, '
                  'le cout de publication dans cette commune = les unites de sa zone.',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppTheme.accentColor,
                      height: 1.5),
                ),
              ]),
        ),
        const SizedBox(height: 20),

        // En-tete section
        _sectionHeader('Configurer les zones'),
        const SizedBox(height: 12),

        // Cards zones
        ..._zoneNames.map((zoneName) => _buildZoneConfigCard(zoneName)),

        const SizedBox(height: 16),

        // Recap usage
        _buildZoneUsageRecap(),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _buildZoneConfigCard(String zoneName) {
    final color = _zoneColors[zoneName] ?? Colors.grey;
    final icon = _zoneIcons[zoneName] ?? Icons.star_outline_rounded;
    final units = _zoneUnits[zoneName] ?? 1;
    final usd = (units * 0.1).toStringAsFixed(2);
    final communeCount = _communeAssignments.values.where((v) {
      final m = v as Map<String, dynamic>;
      return (m['zone'] as String?) == zoneName;
    }).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header zone
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(zoneName,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: color)),
                    Text(
                      '$communeCount commune${communeCount > 1 ? 's' : ''} assignee${communeCount > 1 ? 's' : ''}',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: color.withValues(alpha: 0.7)),
                    ),
                  ]),
            ),
            // Badge unites actuelles
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$units unite${units > 1 ? 's' : ''}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.white),
              ),
            ),
          ]),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Ligne : slider + champ texte
          Row(children: [
            // Slider
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Unites par annonce',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary)),
                          Text('$usd USD',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: color)),
                        ]),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: color,
                        inactiveTrackColor: color.withValues(alpha: 0.15),
                        thumbColor: color,
                        overlayColor: color.withValues(alpha: 0.1),
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8),
                      ),
                      child: Slider(
                        value: units.toDouble().clamp(1, 50),
                        min: 1,
                        max: 50,
                        divisions: 49,
                        label: '$units',
                        onChanged: (v) => setState(
                            () => _zoneUnits[zoneName] = v.round()),
                      ),
                    ),
                  ]),
            ),
            const SizedBox(width: 12),
            // Champ numerique direct
            SizedBox(
              width: 70,
              child: _ZoneUnitsField(
                initialValue: units,
                color: color,
                onChanged: (v) =>
                    setState(() => _zoneUnits[zoneName] = v),
              ),
            ),
          ]),

          // Boutons rapides
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [1, 2, 3, 5, 10, 15, 20].map((v) {
              final isSelected = units == v;
              return GestureDetector(
                onTap: () => setState(() => _zoneUnits[zoneName] = v),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color
                        : color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isSelected
                            ? color
                            : color.withValues(alpha: 0.25)),
                  ),
                  child: Text('$v',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color:
                              isSelected ? Colors.white : color)),
                ),
              );
            }).toList(),
          ),
        ]),
      ),
    );
  }

  Widget _buildZoneUsageRecap() {
    final total = _communeAssignments.length;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.donut_small_rounded,
              color: AppTheme.primaryColor, size: 16),
          const SizedBox(width: 8),
          Text('$total commune${total > 1 ? 's' : ''} assignee${total > 1 ? 's' : ''}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppTheme.primaryColor)),
        ]),
        const SizedBox(height: 10),
        ..._zoneNames.map((z) {
          final count = _communeAssignments.values.where((v) {
            final m = v as Map<String, dynamic>;
            return (m['zone'] as String?) == z;
          }).length;
          if (count == 0) return const SizedBox.shrink();
          final color = _zoneColors[z] ?? Colors.grey;
          final units = _zoneUnits[z] ?? 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(z,
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color))),
              Text('$count communes',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppTheme.textSecondary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('$units u.',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ONGLET 2 — COMMUNES (assignation commune -> zone)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildCommunesTab() {
    return Column(children: [
      // Selecteur pays
      _buildCountrySelector(),
      // Selecteur ville
      _buildCitySelector(),
      // Liste communes
      Expanded(child: _buildCommunesList()),
    ]);
  }

  Widget _buildCountrySelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pays',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        Row(children: [
          ..._countries.map((c) {
            final selected = _selectedCountry == c['code'];
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _selectedCountry = c['code']!;
                  _selectedCity = null;
                }),
                child: Container(
                  margin: EdgeInsets.only(
                      right: c == _countries.last ? 0 : 8),
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primaryColor
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected
                            ? AppTheme.primaryColor
                            : AppTheme.dividerColor),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.15),
                                blurRadius: 6)
                          ]
                        : null,
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                            c['code'] == 'Congo (RDC)' ? 'cd' : 'cg',
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(c['label']!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : AppTheme.textPrimary)),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 4),
                          Text('($_configuredCountForCountry)',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: Colors.white70)),
                        ],
                      ]),
                ),
              ),
            );
          }),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showAddCountryDialog,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: const Icon(Icons.add_rounded,
                  color: AppTheme.accentColor, size: 18),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildCitySelector() {
    final cities = _citiesForCountry;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Ville',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.textPrimary)),
          if (_selectedCity != null)
            Text(
                '$_configuredCountForCity/${_communesForSelectedCity.length} assignee(s)',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppTheme.textSecondary)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cities.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final city = cities[i];
              final isSelected = _selectedCity == city;
              final assignedCount = AppConstants.getCommunesForCity(city)
                  .where((c) => _communeAssignments.containsKey(c))
                  .length;
              return GestureDetector(
                onTap: () => setState(
                    () => _selectedCity = isSelected ? null : city),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.accentColor
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isSelected
                            ? AppTheme.accentColor
                            : AppTheme.dividerColor),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(city,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textPrimary)),
                    if (assignedCount > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.25)
                              : AppTheme.primaryColor
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$assignedCount',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.primaryColor)),
                      ),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildCommunesList() {
    if (_selectedCity == null) {
      return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_city_rounded,
                    size: 48, color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 16),
              const Text('Selectionnez une ville',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              const Text('pour assigner ses communes a des zones',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppTheme.textSecondary)),
            ]),
      );
    }

    final communes = _communesForSelectedCity;
    if (communes.isEmpty) {
      return const Center(
        child: Text('Aucune commune disponible',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: AppTheme.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: communes.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return _buildCityHeader(communes);
        final commune = communes[i - 1];
        final isAssigned = _communeAssignments.containsKey(commune);
        final zoneName = isAssigned
            ? (_communeAssignments[commune] as Map<String, dynamic>)['zone']
                    as String? ??
                'Standard'
            : null;
        return _buildCommuneCard(commune, zoneName, isAssigned);
      },
    );
  }

  Widget _buildCityHeader(List<String> communes) {
    final assigned =
        communes.where((c) => _communeAssignments.containsKey(c)).length;
    final total = communes.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        const Icon(Icons.location_on_rounded,
            color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedCity!,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.primaryColor)),
                Text('$assigned/$total commune(s) assignee(s)',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: AppTheme.textSecondary)),
              ]),
        ),
        TextButton.icon(
          onPressed: () => _showBulkAssignDialog(communes),
          icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
          label: const Text('Config. rapide',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accentColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
      ]),
    );
  }

  Widget _buildCommuneCard(
      String commune, String? zoneName, bool isAssigned) {
    final color = zoneName != null
        ? (_zoneColors[zoneName] ?? Colors.grey)
        : Colors.grey;
    final units = zoneName != null ? (_zoneUnits[zoneName] ?? 1) : 0;
    final usd = (units * 0.1).toStringAsFixed(2);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAssigned
              ? color.withValues(alpha: 0.4)
              : AppTheme.dividerColor.withValues(alpha: 0.5),
          width: isAssigned ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isAssigned
                ? color.withValues(alpha: 0.12)
                : Colors.grey.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isAssigned
                ? (_zoneIcons[zoneName] ?? Icons.location_on_rounded)
                : Icons.location_off_rounded,
            size: 20,
            color: isAssigned ? color : Colors.grey.shade400,
          ),
        ),
        title: Text(commune,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isAssigned
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary)),
        subtitle: isAssigned
            ? Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(zoneName ?? '',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.toll_outlined,
                    size: 12, color: AppTheme.accentColor),
                const SizedBox(width: 3),
                Text('$units u. • $usd USD',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: AppTheme.accentColor,
                        fontWeight: FontWeight.w600)),
              ])
            : const Text('Non assignee — defaut systeme',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppTheme.textSecondary)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // Bouton assigner / modifier
          IconButton(
            icon: Icon(
              isAssigned
                  ? Icons.edit_rounded
                  : Icons.add_rounded,
              size: 18,
              color: isAssigned
                  ? AppTheme.primaryColor
                  : AppTheme.accentColor,
            ),
            onPressed: () =>
                _showAssignZoneDialog(commune, zoneName),
            tooltip: isAssigned ? 'Changer de zone' : 'Assigner une zone',
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (isAssigned)
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: AppTheme.errorColor),
              onPressed: () => _removeCommune(commune),
              tooltip: 'Retirer assignation',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ]),
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showAssignZoneDialog(String commune, String? currentZone) {
    String selectedZone = currentZone ?? 'Standard';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.location_on_rounded,
                color: AppTheme.primaryColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(commune,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ]),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Assigner une zone a cette commune :',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 14),
                ..._zoneNames.map((z) {
                  final c = _zoneColors[z] ?? Colors.grey;
                  final icon = _zoneIcons[z] ?? Icons.star_outline_rounded;
                  final units = _zoneUnits[z] ?? 1;
                  final usd = (units * 0.1).toStringAsFixed(2);
                  final isSelected = selectedZone == z;

                  return GestureDetector(
                    onTap: () => setD(() => selectedZone = z),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? c.withValues(alpha: 0.1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? c
                              : AppTheme.dividerColor,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: c, size: 16),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(z,
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: c)),
                                Text('$units unite${units > 1 ? 's' : ''} / annonce  •  $usd USD',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        color: c.withValues(alpha: 0.8))),
                              ]),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded,
                              color: c, size: 20),
                      ]),
                    ),
                  );
                }),
              ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppTheme.textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                _assignCommune(commune, selectedZone);
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.check_rounded,
                  size: 16, color: Colors.white),
              label: const Text('Assigner',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBulkAssignDialog(List<String> communes) {
    String bulkZone = 'Standard';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.auto_fix_high_rounded,
                color: AppTheme.accentColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Config. rapide — $_selectedCity',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
          ]),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigner la meme zone a toutes les '
                  '${communes.length} communes de $_selectedCity',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.4),
                ),
                const SizedBox(height: 14),
                ..._zoneNames.map((z) {
                  final c = _zoneColors[z] ?? Colors.grey;
                  final icon =
                      _zoneIcons[z] ?? Icons.star_outline_rounded;
                  final units = _zoneUnits[z] ?? 1;
                  final isSelected = bulkZone == z;

                  return GestureDetector(
                    onTap: () => setD(() => bulkZone = z),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? c.withValues(alpha: 0.1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              isSelected ? c : AppTheme.dividerColor,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Icon(icon, color: c, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(z,
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: c))),
                        Text('$units u.',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: c)),
                        const SizedBox(width: 6),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded,
                              color: c, size: 18),
                      ]),
                    ),
                  );
                }),
              ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppTheme.textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                for (final c in communes) {
                  _assignCommune(c, bulkZone);
                }
                Navigator.pop(ctx);
                _snackOk(
                    '${communes.length} communes assignees a la zone $bulkZone');
              },
              icon: const Icon(Icons.check_rounded,
                  size: 16, color: Colors.white),
              label: const Text('Appliquer a tous',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCountryDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.public_rounded,
              color: AppTheme.primaryColor, size: 22),
          SizedBox(width: 8),
          Text('Ajouter un pays',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ]),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: 'Nom du pays',
            labelStyle: const TextStyle(fontFamily: 'Poppins'),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                  color: AppTheme.primaryColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              _snackOk(
                  'Fonctionnalite en developpement pour ${nameCtrl.text}');
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Ajouter',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _sectionHeader(String title) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(
              left: BorderSide(
                  color: AppTheme.primaryColor, width: 3)),
        ),
        child: Text(title,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppTheme.textPrimary)),
      );
}

// ── Widget interne pour le champ unite (evite StatefulBuilder imbriques) ──
class _ZoneUnitsField extends StatefulWidget {
  final int initialValue;
  final Color color;
  final ValueChanged<int> onChanged;

  const _ZoneUnitsField({
    required this.initialValue,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_ZoneUnitsField> createState() => _ZoneUnitsFieldState();
}

class _ZoneUnitsFieldState extends State<_ZoneUnitsField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.initialValue}');
  }

  @override
  void didUpdateWidget(_ZoneUnitsField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue) {
      final newText = '${widget.initialValue}';
      if (_ctrl.text != newText) {
        _ctrl.text = newText;
        _ctrl.selection = TextSelection.fromPosition(
            TextPosition(offset: newText.length));
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: widget.color),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 10),
        filled: true,
        fillColor: widget.color.withValues(alpha: 0.06),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: widget.color.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: widget.color, width: 2)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: widget.color.withValues(alpha: 0.3))),
      ),
      onChanged: (v) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed >= 1) {
          widget.onChanged(parsed.clamp(1, 999));
        }
      },
    );
  }
}
