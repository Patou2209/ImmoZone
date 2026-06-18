import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/property_card.dart';
import '../../../core/widgets/ad_banner_card.dart';
import '../../../services/data_service.dart';
import '../../../models/property_model.dart';
import '../../../models/ad_model.dart';
import '../property_detail/property_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? initialType;
  final String? initialTransaction;
  /// Quand true : charge uniquement les annonces vendues/occupées (72h)
  /// et interdit de mélanger avec les disponibilités.
  final bool initialHistorique;

  const SearchScreen({
    super.key,
    this.initialType,
    this.initialTransaction,
    this.initialHistorique = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  String? _selectedType;
  String? _selectedTransaction;

  // Filtres géographiques en cascade
  String? _selectedCountry;
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedCommune;

  bool _showFilters = false;
  bool _hasSearched = false; // masque "aucune annonce" tant qu'aucune requête envoyée
  List<String> _favorites = [];
  List<AdModel> _liveAds = [];
  int _adRotationIndex = 0;
  static const _kAdRotKey = 'ad_rotation_index';
  final DataService _dataService = DataService();

  // Listes dynamiques
  List<String> get _availableProvinces {
    if (_selectedCountry == null) return [];
    return AppConstants.getProvincesForCountry(_selectedCountry!);
  }

  List<String> get _availableCities {
    if (_selectedCountry == null || _selectedProvince == null) return [];
    return AppConstants.getCitiesForProvince(_selectedCountry!, _selectedProvince!);
  }

  List<String> get _availableCommunes {
    if (_selectedCity == null) return [];
    return AppConstants.getCommunesForCity(_selectedCity!);
  }

  bool get _hasActiveFilters =>
      _selectedType != null ||
      _selectedTransaction != null ||
      _selectedCountry != null ||
      _selectedProvince != null ||
      _selectedCity != null ||
      _selectedCommune != null ||
      _searchCtrl.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Pré-remplir les filtres si fournis depuis le dashboard stats
    if (widget.initialType != null) _selectedType = widget.initialType;
    if (widget.initialTransaction != null) _selectedTransaction = widget.initialTransaction;
    if (widget.initialHistorique) {
      context.read<PropertyProvider>().loadHistoriqueProperties();
    } else {
      context.read<PropertyProvider>().loadProperties();
    }
    _loadFavorites();
    // Appliquer les filtres initiaux automatiquement après le premier frame
    if (widget.initialType != null || widget.initialTransaction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyFilters());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final favs = await _dataService.getFavorites();
    if (mounted) setState(() => _favorites = favs);
    final ads = await _dataService.getLiveAds();
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_kAdRotKey) ?? 0;
    if (mounted) setState(() {
      _liveAds = ads;
      _adRotationIndex = savedIndex;
    });
  }

  Future<void> _toggleFavorite(String id) async {
    await _dataService.toggleFavorite(id);
    await _loadFavorites();
  }

  void _applyFilters() {
    setState(() => _hasSearched = true);
    final provider = context.read<PropertyProvider>();
    provider.filterByType(_selectedType);
    provider.filterByTransaction(_selectedTransaction);
    provider.filterByCity(_selectedCity);
    provider.filterByCommune(_selectedCommune);
    provider.filterByCountry(_selectedCountry);
    provider.filterByProvince(_selectedProvince);
    provider.search(_searchCtrl.text);
  }

  void _clearFilters() {
    setState(() {
      _selectedType = null;
      _selectedTransaction = null;
      _selectedCountry = null;
      _selectedProvince = null;
      _selectedCity = null;
      _selectedCommune = null;
      _hasSearched = false;
      _searchCtrl.clear();
    });
    context.read<PropertyProvider>().clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PropertyProvider>();
    final properties = provider.filteredProperties;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Rechercher',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list,
                color: Colors.white),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            tooltip: 'Filtres',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          // ── Bandeau Historique 72h (visible uniquement en mode historique) ────
          if (widget.initialHistorique)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFFE65100),
              child: Row(children: [
                const Icon(Icons.history_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Annonces vendues / occupées — 72 dernières heures',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ]),
            ),

          // ── Barre de recherche ──────────────────────────────────────────────
          Container(
            color: AppTheme.accentColor,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onSubmitted: (_) => _applyFilters(),
                    decoration: InputDecoration(
                      hintText: 'Titre, ville, commune...',
                      hintStyle: const TextStyle(fontSize: 14, fontFamily: 'Poppins', color: AppTheme.textHint),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.accentColor),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                              onPressed: () {
                                _searchCtrl.clear();
                                if (_hasSearched) _applyFilters();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _applyFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.accentColor, width: 1.5),
                    ),
                  ),
                  child: const Text('Chercher',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
            ),
          ),

          // ── Panneau de filtres ──────────────────────────────────────────────
          AnimatedCrossFade(
            firstChild: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Ligne 1 : Type + Transaction
                Row(children: [
                  Expanded(child: _filterDropdown(
                    hint: 'Type de propriété',
                    value: _selectedType,
                    items: AppConstants.propertyTypes,
                    onChanged: (v) => setState(() => _selectedType = v),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _filterDropdown(
                    hint: 'Transaction',
                    value: _selectedTransaction,
                    items: AppConstants.transactionTypes,
                    onChanged: (v) => setState(() => _selectedTransaction = v),
                  )),
                ]),
                const SizedBox(height: 10),

                // Ligne 2 : Pays
                _filterDropdown(
                  hint: 'Pays',
                  value: _selectedCountry,
                  items: AppConstants.countries,
                  icon: Icons.public,
                  onChanged: (v) => setState(() {
                    _selectedCountry = v;
                    _selectedProvince = null;
                    _selectedCity = null;
                    _selectedCommune = null;
                  }),
                ),
                const SizedBox(height: 10),

                // Ligne 3 : Province + Ville (si pays sélectionné)
                if (_selectedCountry != null) ...[
                  Row(children: [
                    Expanded(child: _filterDropdown(
                      hint: 'Province',
                      value: _selectedProvince,
                      items: _availableProvinces,
                      icon: Icons.map_outlined,
                      onChanged: (v) => setState(() {
                        _selectedProvince = v;
                        _selectedCity = null;
                        _selectedCommune = null;
                      }),
                    )),
                    if (_selectedProvince != null && _availableCities.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(child: _filterDropdown(
                        hint: 'Ville',
                        value: _selectedCity,
                        items: _availableCities,
                        icon: Icons.location_city,
                        onChanged: (v) => setState(() {
                          _selectedCity = v;
                          _selectedCommune = null;
                        }),
                      )),
                    ],
                  ]),
                  const SizedBox(height: 10),
                ],

                // Ligne 4 : Commune (si ville sélectionnée)
                if (_selectedCity != null && _availableCommunes.isNotEmpty) ...[
                  _filterDropdown(
                    hint: 'Commune',
                    value: _selectedCommune,
                    items: _availableCommunes,
                    icon: Icons.location_on_outlined,
                    onChanged: (v) => setState(() => _selectedCommune = v),
                  ),
                  const SizedBox(height: 10),
                ],

                // Boutons Appliquer / Effacer
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _applyFilters,
                      icon: const Icon(Icons.search, size: 16, color: Colors.white),
                      label: const Text('Appliquer',
                          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Effacer', style: TextStyle(fontSize: 12, fontFamily: 'Poppins')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.errorColor,
                      side: const BorderSide(color: AppTheme.errorColor),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ]),
              ]),
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 250),
          ),

          // ── Barre de résultats ──────────────────────────────────────────────
          if (_hasSearched)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.white,
              child: Row(
                children: [
                  Text(
                    '${properties.length} résultat${properties.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins', color: AppTheme.textSecondary),
                  ),
                  if (_hasActiveFilters)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Filtres actifs',
                            style: TextStyle(fontSize: 11, color: AppTheme.accentColor, fontFamily: 'Poppins')),
                      ),
                    ),
                ],
              ),
            ),

          // ── Liste des résultats ─────────────────────────────────────────────
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
                : !_hasSearched
                    // Aucune requête envoyée → invitation à chercher
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search, size: 72, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            const Text(
                              'Recherchez un bien immobilier',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins', color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Utilisez la barre de recherche ou\nles filtres pour trouver votre bien.',
                              style: TextStyle(fontSize: 13, fontFamily: 'Poppins',
                                  color: AppTheme.textHint),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () => setState(() => _showFilters = true),
                              icon: const Icon(Icons.filter_list, size: 16, color: Colors.white),
                              label: const Text('Ouvrir les filtres',
                                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildSearchResults(context, provider, properties),
          ),
        ],
        ),
      ),
    );
  }

  /// Construit la vue des résultats avec la section "Offres Spéciales" en tête
  Widget _buildSearchResults(BuildContext context, PropertyProvider provider, List<PropertyModel> properties) {
    // Annonces boostées filtrées selon les critères courants
    final boosted = provider.getBoostedProperties(
      transactionType: _selectedTransaction,
      propertyType: _selectedType,
      country: _selectedCountry,
      province: _selectedProvince,
      city: _selectedCity,
      commune: _selectedCommune,
    );

    if (properties.isEmpty && boosted.isEmpty) {
      // Aucun résultat du tout
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('Aucun résultat trouvé',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins', color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            const Text("Essayez d'autres critères de recherche",
                style: TextStyle(fontSize: 13, fontFamily: 'Poppins',
                    color: AppTheme.textHint)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Effacer les filtres',
                  style: TextStyle(fontFamily: 'Poppins', color: AppTheme.accentColor)),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // crossCount basé sur la largeur réelle disponible (padding 12×2 = 24px déduit)
        final crossCount = ((width - 24) / 400).floor().clamp(1, 99);
        final hPad = 12.0;

        return ListView(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: hPad),
          children: [
            // ── Section Offres Spéciales ────────────────────────────────
            if (boosted.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildBoostSectionHeader(
                icon: Icons.workspace_premium_rounded,
                label: 'Offres Spéciales',
                color: const Color(0xFFE65100),
              ),
              const SizedBox(height: 8),
              // Grille responsive pour les boostées
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 400 / 450,
                ),
                itemCount: boosted.length,
                itemBuilder: (ctx, i) {
                  final p = boosted[i];
                  return PropertyCard(
                    property: p,
                    isFavorite: _favorites.contains(p.id),
                    onFavorite: () => _toggleFavorite(p.id),
                    onTap: () => Navigator.push(ctx,
                        MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p))),
                  );
                },
              ),
              if (properties.isNotEmpty) _buildBoostSectionDivider(),
            ],

            // ── Titre section normale ───────────────────────────────────
            if (boosted.isNotEmpty && properties.isNotEmpty) ...[
              _buildBoostSectionHeader(
                icon: Icons.home_work_rounded,
                label: 'Toutes les annonces',
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 8),
            ],

            // ── Grille normale avec publicités intercalées ──────────────
            ..._buildNormalGridWithAds(context, properties, crossCount),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// Construit la grille unifiée annonces + publicités.
  ///
  /// Les publicités occupent exactement 1 slot de grille (400×450),
  /// intercalées parmi les annonces :
  ///   • 0–4 annonces → 1 pub insérée après la dernière annonce
  ///   • 5+ annonces  → 2 pubs : après l'index 3 + après la dernière
  ///
  /// Retourne [Widget] — un seul GridView avec items mixtes.
  List<Widget> _buildNormalGridWithAds(BuildContext context, List<PropertyModel> properties, int crossCount) {
    if (properties.isEmpty) return [];

    final n = properties.length;

    // ── Construire la liste d'items (PropertyModel | AdModel) ────────────────
    // Un item peut être soit une annonce (PropertyModel) soit une pub (AdModel).
    // On utilise Object comme type commun.
    final List<Object> mixedItems = [];

    if (_liveAds.isEmpty) {
      // Pas de pubs : juste les annonces
      mixedItems.addAll(properties);
    } else {
      final totalAds = _liveAds.length;
      final twoAds   = n >= 5;
      final AdModel adFirst  = _liveAds[_adRotationIndex % totalAds];
      final AdModel adSecond = _liveAds[(_adRotationIndex + 1) % totalAds];

      // Persister la rotation
      final next = (_adRotationIndex + (twoAds ? 2 : 1)) % totalAds;
      SharedPreferences.getInstance().then((p) => p.setInt(_kAdRotKey, next));

      if (twoAds) {
        // Annonces 0..3 → pub → annonces 4..n-1 → pub
        mixedItems.addAll(properties.sublist(0, 4));
        mixedItems.add(adFirst);
        mixedItems.addAll(properties.sublist(4));
        mixedItems.add(adSecond);
      } else {
        // Toutes les annonces → pub à la fin
        mixedItems.addAll(properties);
        mixedItems.add(adFirst);
      }
    }

    // ── Un seul GridView avec items mixtes ────────────────────────────────────
    return [
      LayoutBuilder(
        builder: (ctx, constraints) {
          final cols = (constraints.maxWidth / 400).floor().clamp(1, 99);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 400 / 450,
            ),
            itemCount: mixedItems.length,
            itemBuilder: (gridCtx, i) {
              final item = mixedItems[i];
              if (item is AdModel) {
                // Slot publicitaire — même taille qu'une annonce
                return AdBannerCard(
                  key: ValueKey('ad_${item.id}_$i'),
                  ad: item,
                  gridMode: true,
                );
              }
              // Slot annonce normale
              final p = item as PropertyModel;
              return PropertyCard(
                property: p,
                isFavorite: _favorites.contains(p.id),
                onFavorite: () => _toggleFavorite(p.id),
                onTap: () => Navigator.push(gridCtx,
                    MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p))),
              );
            },
          );
        },
      ),
    ];
  }

  Widget _buildBoostSectionHeader({required IconData icon, required String label, required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.75)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.white,
              )),
        ]),
      ),
    );
  }

  Widget _buildBoostSectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Container(height: 1, color: const Color(0xFFE4E8F0))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('Annonces disponibles',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: Colors.grey[400], fontWeight: FontWeight.w500)),
        ),
        Expanded(child: Container(height: 1, color: const Color(0xFFE4E8F0))),
      ]),
    );
  }

  Widget _filterDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    IconData? icon,
  }) {
    return DropdownButtonFormField<String>(
      value: (items.contains(value)) ? value : null,
      hint: Text(hint, style: const TextStyle(fontSize: 12, fontFamily: 'Poppins')),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: icon != null ? Icon(icon, size: 16, color: AppTheme.accentColor) : null,
      ),
      isExpanded: true,
      items: [
        DropdownMenuItem<String>(value: null, child: Text('Tous', style: const TextStyle(fontSize: 12, fontFamily: 'Poppins', color: AppTheme.textHint))),
        ...items.map((t) => DropdownMenuItem(
              value: t,
              child: Text(t, style: const TextStyle(fontSize: 12, fontFamily: 'Poppins'), overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: onChanged,
    );
  }
}
