import 'package:flutter/material.dart';
import '../models/property_model.dart';
import '../services/data_service.dart';
import '../core/constants/app_constants.dart';

class PropertyProvider extends ChangeNotifier {
  final DataService _dataService = DataService();
  List<PropertyModel> _properties = [];
  List<PropertyModel> _filteredProperties = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  String? _selectedType;
  String? _selectedTransaction;
  String? _selectedCity;
  String? _selectedCommune;
  String? _selectedCountry;
  String? _selectedProvince;
  double? _minPrice;
  double? _maxPrice;
  // Mode historique : affiche uniquement les annonces vendues/occupées (72h)
  bool _historiqueMode = false;

  List<PropertyModel> get properties => _properties;
  List<PropertyModel> get filteredProperties => _filteredProperties;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String? get selectedType => _selectedType;
  String? get selectedTransaction => _selectedTransaction;
  String? get selectedCity => _selectedCity;
  bool get historiqueMode => _historiqueMode;

  // ─── BOOST ──────────────────────────────────────────────────────────────────
  // Retourne les annonces boostées actives selon les filtres courants.
  // VIP : toujours inclus (ignore tous les filtres).
  // Premium/Standard : inclus si les 6 critères de base correspondent.
  List<PropertyModel> getBoostedProperties({
    String? country,
    String? province,
    String? city,
    String? commune,
    String? transactionType,
    String? propertyType,
  }) {
    final now = DateTime.now();
    // Pool source : toutes les annonces actives (non sellées)
    final pool = _properties.where((p) =>
        p.isBoostActive && p.status == 'Actif' && !p.isSold && !p.isRented).toList();

    final result = pool.where((p) {
      // VIP → toujours visible
      if (p.isVip) return true;
      // Standard / Premium → les 6 critères de base doivent correspondre
      final matchCountry      = country == null || country.isEmpty ||
          p.country.toLowerCase() == country.toLowerCase();
      final matchProvince     = province == null || province.isEmpty ||
          p.province.toLowerCase() == province.toLowerCase();
      final matchCity         = city == null || city.isEmpty ||
          p.city.toLowerCase() == city.toLowerCase();
      final matchCommune      = commune == null || commune.isEmpty ||
          p.commune.toLowerCase() == commune.toLowerCase();
      final matchTransaction  = transactionType == null || transactionType.isEmpty ||
          p.transactionType == transactionType;
      final matchType         = propertyType == null || propertyType.isEmpty ||
          p.type == propertyType;
      return matchCountry && matchProvince && matchCity &&
             matchCommune && matchTransaction && matchType;
    }).toList();

    // Tri : VIP (3) > Premium (2) > Standard (1) ; à égalité : boost récent en premier
    result.sort((a, b) {
      if (a.boostLevel != b.boostLevel) return b.boostLevel.compareTo(a.boostLevel);
      final aEnd = a.boostEnd ?? now;
      final bEnd = b.boostEnd ?? now;
      return bEnd.compareTo(aEnd);
    });
    return result;
  }

  Future<void> loadProperties() async {
    _isLoading = true;
    _historiqueMode = false; // mode normal : annonces actives uniquement
    notifyListeners();
    try {
      _properties = await _dataService.getActiveProperties();
      _applyFilters();
    } catch (e) {
      _error = 'Erreur de chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Charge UNIQUEMENT les annonces vendues ou occupées dans les 3 derniers jours (72h).
  /// Utilisé exclusivement depuis SearchScreen en mode historique.
  Future<void> loadHistoriqueProperties() async {
    _isLoading = true;
    _historiqueMode = true;
    notifyListeners();
    try {
      final all = await _dataService.getProperties();
      final now = DateTime.now();
      _properties = all.where((p) {
        if (!(p.isSold || p.isRented)) return false;
        if (p.updatedAt == null) return false;
        return now.difference(p.updatedAt!).inHours < 72; // 3 jours
      }).toList();
      _applyFilters();
    } catch (e) {
      _error = 'Erreur de chargement historique';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadAllProperties() async {
    _isLoading = true;
    notifyListeners();
    try {
      _properties = await _dataService.getProperties();
      _filteredProperties = List.from(_properties);
    } catch (e) {
      _error = 'Erreur de chargement';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<List<PropertyModel>> getUserProperties(String userId) async {
    return await _dataService.getUserProperties(userId);
  }

  Future<List<PropertyModel>> getPendingProperties() async {
    return await _dataService.getPendingProperties();
  }

  List<PropertyModel> getFeaturedProperties() {
    return _properties.where((p) => p.isFeatured).toList();
  }

  void search(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void filterByType(String? type) {
    _selectedType = type;
    _applyFilters();
    notifyListeners();
  }

  void filterByTransaction(String? transaction) {
    _selectedTransaction = transaction;
    _applyFilters();
    notifyListeners();
  }

  void filterByCity(String? city) {
    _selectedCity = city;
    _applyFilters();
    notifyListeners();
  }

  void filterByPrice(double? min, double? max) {
    _minPrice = min;
    _maxPrice = max;
    _applyFilters();
    notifyListeners();
  }

  void filterByCommune(String? commune) {
    _selectedCommune = commune;
    _applyFilters();
    notifyListeners();
  }

  void filterByCountry(String? country) {
    _selectedCountry = country;
    _applyFilters();
    notifyListeners();
  }

  void filterByProvince(String? province) {
    _selectedProvince = province;
    _applyFilters();
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedType = null;
    _selectedTransaction = null;
    _selectedCity = null;
    _selectedCommune = null;
    _selectedCountry = null;
    _selectedProvince = null;
    _minPrice = null;
    _maxPrice = null;
    // Ne pas réinitialiser _historiqueMode ici — le mode est géré
    // par SearchScreen (loadProperties vs loadHistoriqueProperties)
    _applyFilters();
    notifyListeners();
  }

  // ── Helpers REF:IZ ─────────────────────────────────────────────────────────
  /// Extrait la référence complète IZ depuis la query (IZ inclus).
  /// Ex : "REF:IZ7326" → "IZ7326", "IZ7326" → "IZ7326", "iz 7326" → "IZ7326"
  /// Retourne null si la query ne ressemble pas à une référence IZ.
  static String? _extractRefSuffix(String query) {
    final q = query.trim().toUpperCase().replaceAll(RegExp(r'[\s:\-_]'), '');
    // Cas 1 : contient explicitement le préfixe IZ → extraire IZ + ce qui suit
    final matchIZ = RegExp(r'(IZ[A-Z0-9]{1,10})$').firstMatch(q);
    if (matchIZ != null) return matchIZ.group(1); // ex: "IZ7326"
    // Cas 2 : query = uniquement des chiffres (4 à 10) → les utilisateurs tapent
    // juste "2209" en pensant à la ref IZ2209 — traiter comme ref
    final matchDigits = RegExp(r'^[0-9]{4,10}$').firstMatch(q);
    if (matchDigits != null) return 'IZ${matchDigits.group(0)}'; // → "IZ2209"
    return null;
  }

  /// Vérifie si une annonce correspond à la référence IZ extraite.
  /// La référence affichée d'une annonce est : "IZ" + 4 derniers chars de p.id
  static bool _matchesRef(PropertyModel p, String izRef) {
    final id = p.id.toUpperCase();
    // Référence d'affichage : IZ + 4 derniers chars de l'ID
    final displayRef = 'IZ${id.length >= 4 ? id.substring(id.length - 4) : id}';
    // Suffixe seul (chiffres après IZ) pour match partiel sur l'ID complet
    final suffix = izRef.startsWith('IZ') ? izRef.substring(2) : izRef;

    if (displayRef == izRef) return true;          // match exact ref affichée
    if (displayRef.contains(izRef)) return true;   // ref affichée contient la query
    if (id.endsWith(suffix)) return true;          // l'ID complet se termine par les chiffres
    if (id.contains(suffix)) return true;          // l'ID contient les chiffres
    return false;
  }

  /// True si la query courante est une recherche par référence IZ.
  bool get isRefSearch => _extractRefSuffix(_searchQuery) != null;

  void _applyFilters() {
    final refSuffix = _extractRefSuffix(_searchQuery);

    // ── Mode REF : recherche par référence IZ (ex : REF:IZ7326) ─────────────
    // Tous les filtres géo/type sont ignorés — seule la référence compte.
    // Les boostées sont incluses (override de l'exclusion normale).
    if (refSuffix != null) {
      _filteredProperties = _properties
          .where((p) => _matchesRef(p, refSuffix))
          .toList();
      return;
    }

    // ── Mode normal : filtre classique ───────────────────────────────────────
    // Les annonces boostées sont exclues de la liste normale — elles s'affichent
    // dans la section "Offres Spéciales" via getBoostedProperties().
    _filteredProperties = _properties.where((p) {
      if (p.isBoostActive) return false;
      final matchesSearch = _searchQuery.isEmpty ||
          p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.city.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.commune.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (p.province ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.type.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesType        = _selectedType == null || p.type == _selectedType;
      final matchesTransaction = _selectedTransaction == null || p.transactionType == _selectedTransaction;
      final matchesCity        = _selectedCity == null || p.city == _selectedCity;
      final matchesCommune     = _selectedCommune == null || p.commune == _selectedCommune;
      final matchesCountry     = _selectedCountry == null ||
          (p.province != null && AppConstants.getProvincesForCountry(_selectedCountry!)
              .any((prov) => prov == p.province)) ||
          _selectedCountry == AppConstants.defaultCountry;
      final matchesProvince    = _selectedProvince == null || p.province == _selectedProvince;
      final matchesMinPrice    = _minPrice == null || p.price >= _minPrice!;
      final matchesMaxPrice    = _maxPrice == null || p.price <= _maxPrice!;
      return matchesSearch && matchesType && matchesTransaction &&
          matchesCity && matchesCommune && matchesCountry &&
          matchesProvince && matchesMinPrice && matchesMaxPrice;
    }).toList();
  }


  Future<void> addProperty(PropertyModel property) async {
    await _dataService.addProperty(property);
    await loadAllProperties();
  }

  Future<void> updateProperty(PropertyModel property) async {
    await _dataService.updateProperty(property);
    await loadAllProperties();
  }

  Future<void> deleteProperty(String id) async {
    await _dataService.deleteProperty(id);
    await loadAllProperties();
  }

  Future<void> updateStatus(String id, String status) async {
    await _dataService.updatePropertyStatus(id, status);
    await loadAllProperties();
  }

  Future<Map<String, dynamic>> getStats() async {
    return await _dataService.getAdminStats();
  }
}
