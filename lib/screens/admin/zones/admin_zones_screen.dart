import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/data_service.dart';

/// Ecran admin — Gestion des zones geographiques et credits par commune
/// Architecture : Pays > Ville > Communes (avec credits configurables)
class AdminZonesScreen extends StatefulWidget {
  const AdminZonesScreen({super.key});
  @override
  State<AdminZonesScreen> createState() => _AdminZonesScreenState();
}

class _AdminZonesScreenState extends State<AdminZonesScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  bool _isLoading = true;
  bool _isSaving = false;

  // zones stockees : { 'Commune': { 'credits': int, 'standing': string, 'city': string, 'country': string } }
  Map<String, dynamic> _zones = {};

  // Pays disponibles (extensible)
  static const List<Map<String, String>> _countries = [
    {'code': 'Congo (RDC)',         'flag': 'cd', 'label': 'Congo (RDC)'},
    {'code': 'Congo (Brazzaville)', 'flag': 'cg', 'label': 'Congo-Brazzaville'},
  ];

  // Pays selectionne
  String _selectedCountry = 'Congo (RDC)';
  // Ville selectionnee (null = toutes)
  String? _selectedCity;

  // standing presets
  static const List<String> _standings = [
    'Standard', 'Intermediaire', 'Premium', 'Luxe',
  ];
  static const Map<String, int> _standingDefaults = {
    'Standard':      1,
    'Intermediaire': 3,
    'Premium':       5,
    'Luxe':          10,
  };
  static const Map<String, Color> _standingColors = {
    'Standard':      Colors.grey,
    'Intermediaire': Colors.blue,
    'Premium':       Colors.orange,
    'Luxe':          Colors.purple,
  };

  // Villes du pays selectionne
  List<String> get _citiesForCountry {
    if (_selectedCountry == 'Congo (Brazzaville)') {
      final Set<String> all = {};
      for (final p in AppConstants.provincesBrazzaville) {
        all.addAll(AppConstants.getCitiesForProvince(_selectedCountry, p));
      }
      // Garder seulement les villes qui ont des communes definies
      return all.where((c) => AppConstants.getCommunesForCity(c).isNotEmpty).toList()..sort();
    }
    // RDC : utiliser la liste des villes qui ont des communes
    return AppConstants.cities
        .where((c) => AppConstants.getCommunesForCity(c).isNotEmpty)
        .toList()..sort();
  }

  // Communes de la ville selectionnee
  List<String> get _communesForSelectedCity {
    if (_selectedCity == null) return [];
    return AppConstants.getCommunesForCity(_selectedCity!);
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
    _snackOk('Zones geographiques sauvegardees');
  }

  void _setZone(String commune, int credits, String standing) {
    setState(() {
      _zones[commune] = {
        'credits': credits,
        'standing': standing,
        'city': _selectedCity ?? '',
        'country': _selectedCountry,
      };
    });
  }

  void _removeZone(String commune) {
    setState(() => _zones.remove(commune));
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

  // Stats pour le pays selectionne
  int get _configuredCountForCountry {
    return _zones.values.where((v) {
      final m = v as Map<String, dynamic>;
      return (m['country'] as String?) == _selectedCountry;
    }).length;
  }

  int get _configuredCountForCity {
    if (_selectedCity == null) return 0;
    return _communesForSelectedCity.where((c) => _zones.containsKey(c)).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Zones Geographiques',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 16, color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded, color: Colors.white),
            tooltip: 'Sauvegarder',
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : Column(children: [
              // ── Bandeau info ──────────────────────────────────────────────
              _buildInfoBanner(),
              // ── Selecteur Pays ────────────────────────────────────────────
              _buildCountrySelector(),
              // ── Selecteur Ville ───────────────────────────────────────────
              _buildCitySelector(),
              // ── Liste des communes ────────────────────────────────────────
              Expanded(child: _buildCommunesList()),
            ]),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(
                color: AppTheme.dividerColor.withValues(alpha: 0.5))),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8, offset: const Offset(0, -2),
            )],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded, color: Colors.white, size: 18),
              label: const Text('Sauvegarder les zones',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bandeau info credits ────────────────────────────────────────────────────
  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
      ),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.toll_outlined, color: AppTheme.accentColor, size: 18),
          SizedBox(width: 8),
          Text('Systeme de credits',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 13, color: AppTheme.accentColor)),
        ]),
        SizedBox(height: 6),
        Text('10 USD = 100 credits  •  1 credit = 0,10 USD',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        SizedBox(height: 3),
        Text('Fixez le cout en credits pour publier dans chaque commune. Plus la zone est premium, plus vous pouvez demander de credits.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: AppTheme.textSecondary, height: 1.4)),
      ]),
    );
  }

  // ── Selecteur pays ─────────────────────────────────────────────────────────
  Widget _buildCountrySelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pays',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 13, color: AppTheme.textPrimary)),
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
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primaryColor
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primaryColor
                          : AppTheme.dividerColor,
                    ),
                    boxShadow: selected ? [BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      blurRadius: 6,
                    )] : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(c['code'] == 'Congo (RDC)' ? 'cd' : 'cg',
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(c['label']!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : AppTheme.textPrimary,
                            )),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 4),
                        Text('($_configuredCountForCountry)',
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 10,
                              color: Colors.white70)),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 8),
          // Bouton ajouter pays
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

  // ── Selecteur ville ────────────────────────────────────────────────────────
  Widget _buildCitySelector() {
    final cities = _citiesForCountry;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Ville',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 13, color: AppTheme.textPrimary)),
          if (_selectedCity != null)
            Text('$_configuredCountForCity/${_communesForSelectedCity.length} configur.',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
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
              final configCount = AppConstants.getCommunesForCity(city)
                  .where((c) => _zones.containsKey(c)).length;
              return GestureDetector(
                onTap: () => setState(() =>
                    _selectedCity = isSelected ? null : city),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.accentColor
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.accentColor
                          : AppTheme.dividerColor,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(city,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                        )),
                    if (configCount > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.25)
                              : AppTheme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$configCount',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.primaryColor,
                            )),
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

  // ── Liste des communes ─────────────────────────────────────────────────────
  Widget _buildCommunesList() {
    if (_selectedCity == null) {
      return _buildSelectCityPlaceholder();
    }
    final communes = _communesForSelectedCity;
    if (communes.isEmpty) {
      return const Center(
        child: Text('Aucune commune disponible pour cette ville',
            style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: communes.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return _buildCityConfigHeader(communes);
        }
        final commune = communes[i - 1];
        final isConfigured = _zones.containsKey(commune);
        final data = isConfigured
            ? _zones[commune] as Map<String, dynamic>
            : {'credits': 1, 'standing': 'Standard'};
        final credits = (data['credits'] as num?)?.toInt() ?? 1;
        final standing = data['standing'] as String? ?? 'Standard';
        return _buildCommuneCard(commune, credits, standing, isConfigured);
      },
    );
  }

  Widget _buildSelectCityPlaceholder() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 16, color: AppTheme.textPrimary)),
        const SizedBox(height: 6),
        const Text('pour configurer ses communes',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppTheme.textSecondary)),
      ]),
    );
  }

  Widget _buildCityConfigHeader(List<String> communes) {
    final configured = communes.where((c) => _zones.containsKey(c)).length;
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_selectedCity!,
                style: const TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 14,
                    color: AppTheme.primaryColor)),
            Text('$configured/$total commune(s) configuree(s)',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary)),
          ]),
        ),
        // Bouton config rapide (tout configurer avec le meme standing)
        TextButton.icon(
          onPressed: () => _showBulkConfigDialog(communes),
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
      String commune, int credits, String standing, bool isConfigured) {
    final standingColor = _standingColors[standing] ?? Colors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConfigured
              ? standingColor.withValues(alpha: 0.4)
              : AppTheme.dividerColor.withValues(alpha: 0.5),
          width: isConfigured ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2),
        )],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: isConfigured
                ? standingColor.withValues(alpha: 0.12)
                : Colors.grey.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isConfigured ? Icons.location_on_rounded : Icons.location_off_rounded,
            size: 20,
            color: isConfigured ? standingColor : Colors.grey.shade400,
          ),
        ),
        title: Text(commune,
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13,
              color: isConfigured ? AppTheme.textPrimary : AppTheme.textSecondary,
            )),
        subtitle: isConfigured
            ? Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: standingColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(standing,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: standingColor,
                      )),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.toll_outlined, size: 12,
                    color: AppTheme.accentColor),
                const SizedBox(width: 3),
                Text('$credits credit${credits > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 11,
                      color: AppTheme.accentColor, fontWeight: FontWeight.w600,
                    )),
              ])
            : const Text('Non configuree — defaut systeme',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // Bouton modifier
          IconButton(
            icon: Icon(
              isConfigured ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
              color: isConfigured ? AppTheme.primaryColor : AppTheme.accentColor,
            ),
            onPressed: () => _showEditCommuneDialog(
                commune, credits, standing, isConfigured),
            tooltip: isConfigured ? 'Modifier' : 'Configurer',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          // Bouton supprimer (seulement si configuree)
          if (isConfigured)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16,
                  color: AppTheme.errorColor),
              onPressed: () => _removeZone(commune),
              tooltip: 'Retirer config',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ]),
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showEditCommuneDialog(
      String commune, int credits, String standing, bool isEdit) {
    int newCredits = credits;
    String newStanding = standing;
    final creditsCtrl = TextEditingController(text: '$credits');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.location_on_rounded,
                color: AppTheme.primaryColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(commune,
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Standing
              const Align(alignment: Alignment.centerLeft,
                  child: Text('Standing',
                      style: TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600, fontSize: 12,
                          color: AppTheme.textSecondary))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _standings.map((s) {
                final sel = newStanding == s;
                final c = _standingColors[s] ?? Colors.grey;
                return ChoiceChip(
                  label: Text(s,
                      style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : c)),
                  selected: sel,
                  selectedColor: c,
                  backgroundColor: c.withValues(alpha: 0.1),
                  side: BorderSide(color: c.withValues(alpha: 0.4)),
                  onSelected: (_) => setD(() {
                    newStanding = s;
                    newCredits = _standingDefaults[s] ?? 1;
                    creditsCtrl.text = '$newCredits';
                  }),
                );
              }).toList()),
              const SizedBox(height: 16),
              // Credits
              TextField(
                controller: creditsCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Credits requis pour publier',
                  labelStyle: const TextStyle(fontFamily: 'Poppins'),
                  prefixIcon: const Icon(Icons.toll_outlined,
                      color: AppTheme.accentColor),
                  suffixText: 'credits',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.accentColor, width: 2),
                  ),
                  helperText: '${(int.tryParse(creditsCtrl.text) ?? 1) * 0.1} USD par publication',
                ),
                onChanged: (v) {
                  newCredits = int.tryParse(v) ?? 1;
                  setD(() {});
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Poppins')),
            ),
            ElevatedButton(
              onPressed: () {
                _setZone(commune,
                    int.tryParse(creditsCtrl.text) ?? 1, newStanding);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(isEdit ? 'Modifier' : 'Configurer',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBulkConfigDialog(List<String> communes) {
    String bulkStanding = 'Standard';
    int bulkCredits = 1;
    final creditsCtrl = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.auto_fix_high_rounded,
                color: AppTheme.accentColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Config. rapide — $_selectedCity',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Appliquer un meme standing et credits a toutes les '
                '${communes.length} communes de $_selectedCity',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.textSecondary, height: 1.4)),
            const SizedBox(height: 14),
            const Align(alignment: Alignment.centerLeft,
                child: Text('Standing',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, fontSize: 12,
                        color: AppTheme.textSecondary))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _standings.map((s) {
              final sel = bulkStanding == s;
              final c = _standingColors[s] ?? Colors.grey;
              return ChoiceChip(
                label: Text(s,
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : c)),
                selected: sel,
                selectedColor: c,
                backgroundColor: c.withValues(alpha: 0.1),
                side: BorderSide(color: c.withValues(alpha: 0.4)),
                onSelected: (_) => setD(() {
                  bulkStanding = s;
                  bulkCredits = _standingDefaults[s] ?? 1;
                  creditsCtrl.text = '$bulkCredits';
                }),
              );
            }).toList()),
            const SizedBox(height: 14),
            TextField(
              controller: creditsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Credits',
                labelStyle: const TextStyle(fontFamily: 'Poppins'),
                prefixIcon: const Icon(Icons.toll_outlined,
                    color: AppTheme.accentColor),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: AppTheme.accentColor, width: 2),
                ),
              ),
              onChanged: (v) =>
                  bulkCredits = int.tryParse(v) ?? 1,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler',
                    style: TextStyle(fontFamily: 'Poppins'))),
            ElevatedButton.icon(
              onPressed: () {
                final credits = int.tryParse(creditsCtrl.text) ?? 1;
                for (final c in communes) {
                  _setZone(c, credits, bulkStanding);
                }
                Navigator.pop(ctx);
                _snackOk('${communes.length} communes configurees');
              },
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Appliquer a tous',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.public_rounded, color: AppTheme.primaryColor, size: 22),
          SizedBox(width: 8),
          Text('Ajouter un pays',
              style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 15)),
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
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              _snackOk(
                  'Fonctionnalite en cours de developpement pour ${nameCtrl.text}');
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Ajouter',
                style: TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
