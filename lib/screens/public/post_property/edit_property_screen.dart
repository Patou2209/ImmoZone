import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/property_provider.dart';
import '../../../models/property_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';

class EditPropertyScreen extends StatefulWidget {
  final PropertyModel property;
  const EditPropertyScreen({super.key, required this.property});

  @override
  State<EditPropertyScreen> createState() => _EditPropertyScreenState();
}

class _EditPropertyScreenState extends State<EditPropertyScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // ── Champs principaux ──────────────────────────────────────────────────────
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _surfaceCtrl;
  late final TextEditingController _bedroomsCtrl;
  late final TextEditingController _bathroomsCtrl;
  late final TextEditingController _floorsCtrl;
  late final TextEditingController _quartierCtrl;

  // Dropdowns
  late String _selectedType;
  late String _selectedTransaction;
  late String _selectedCurrency;
  late String _selectedCountry;
  late String _selectedProvince;
  late String _selectedCity;
  late String _selectedCommune;

  // Booleans
  late bool _hasParking;
  late bool _hasElectricity;
  late bool _hasWater;
  late bool _hasAscenseur;
  late bool _hasAirConditioning;
  late bool _hasCuisineEquipee;
  late bool _hasCommission;
  late int  _garantieMois;
  late final TextEditingController _commissionPctCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    _titleCtrl        = TextEditingController(text: p.title);
    _descCtrl         = TextEditingController(text: p.description);
    _priceCtrl        = TextEditingController(text: p.price.toStringAsFixed(0));
    _surfaceCtrl      = TextEditingController(text: p.surface?.toStringAsFixed(0) ?? '');
    _bedroomsCtrl     = TextEditingController(text: p.bedrooms?.toString() ?? '');
    _bathroomsCtrl    = TextEditingController(text: p.bathrooms?.toString() ?? '');
    _floorsCtrl       = TextEditingController(text: p.floors?.toString() ?? '');
    _quartierCtrl     = TextEditingController(text: p.address);
    _commissionPctCtrl = TextEditingController(
        text: p.commissionPct?.toStringAsFixed(0) ?? '');

    _selectedType        = p.type;
    _selectedTransaction = p.transactionType;
    _selectedCurrency    = p.currency;
    _selectedCountry     = p.country.isNotEmpty ? p.country : AppConstants.defaultCountry;
    _selectedProvince    = p.province.isNotEmpty ? p.province : 'Kinshasa';
    _selectedCity        = p.city.isNotEmpty ? p.city : 'Kinshasa';
    _selectedCommune     = p.commune.isNotEmpty ? p.commune : 'Gombe';

    _hasParking       = p.hasParking;
    _hasElectricity   = p.hasElectricity;
    _hasWater         = p.hasWater;
    _hasAscenseur     = p.hasAscenseur;
    _hasAirConditioning = p.hasAirConditioning ?? false;
    _hasCuisineEquipee = p.hasCuisineEquipee;
    _hasCommission    = p.hasCommission;
    _garantieMois     = p.garantieMois ?? 0;
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl, _descCtrl, _priceCtrl, _surfaceCtrl,
      _bedroomsCtrl, _bathroomsCtrl, _floorsCtrl, _quartierCtrl,
      _commissionPctCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  // ── Listes cascade ─────────────────────────────────────────────────────────
  List<String> get _provinces =>
      AppConstants.getProvincesForCountry(_selectedCountry);
  List<String> get _cities =>
      AppConstants.getCitiesForProvince(_selectedCountry, _selectedProvince);
  List<String> get _communes =>
      AppConstants.getCommunesForCity(_selectedCity);

  bool get _isLocation => _selectedTransaction == 'Location';

  // ── Sauvegarde ─────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final p = widget.property;
      // Build updated model — use PropertyModel constructor directly to allow
      // setting nullable fields to null (copyWith cannot reset nullable to null).
      final updated = PropertyModel(
        id:              p.id,
        title:           _titleCtrl.text.trim(),
        description:     _descCtrl.text.trim(),
        price:           double.tryParse(_priceCtrl.text.trim()) ?? p.price,
        currency:        _selectedCurrency,
        surface:         double.tryParse(_surfaceCtrl.text.trim()),
        bedrooms:        int.tryParse(_bedroomsCtrl.text.trim()),
        bathrooms:       int.tryParse(_bathroomsCtrl.text.trim()),
        floors:          int.tryParse(_floorsCtrl.text.trim()),
        address:         _quartierCtrl.text.trim(),
        quartier:        p.quartier,
        type:            _selectedType,
        transactionType: _selectedTransaction,
        country:         _selectedCountry,
        province:        _selectedProvince,
        city:            _selectedCity,
        commune:         _selectedCommune,
        hasParking:      _hasParking,
        hasElectricity:  _hasElectricity,
        hasWater:        _hasWater,
        hasAscenseur:    _hasAscenseur,
        hasAirConditioning: _hasAirConditioning,
        hasCuisineEquipee: _hasCuisineEquipee,
        hasCommission:   _hasCommission,
        commissionPct:   _hasCommission
            ? double.tryParse(_commissionPctCtrl.text.trim())
            : null,
        garantieMois:    _isLocation ? _garantieMois : null,
        // Preserve unchanged fields
        amenities:       p.amenities,
        images:          p.images,
        mainImageIndex:  p.mainImageIndex,
        ownerId:         p.ownerId,
        ownerName:       p.ownerName,
        ownerPhone:      p.ownerPhone,
        ownerEmail:      p.ownerEmail,
        ownerWhatsApp:   p.ownerWhatsApp,
        ownerCategory:   p.ownerCategory,
        status:          p.status,
        isSold:          p.isSold,
        isRented:        p.isRented,
        createdAt:       p.createdAt,
        updatedAt:       DateTime.now(),
        expiresAt:       p.expiresAt,
        views:           p.views,
        isFeatured:      p.isFeatured,
        boostEnd:        p.boostEnd,
        boostType:       p.boostType,
        latitude:        p.latitude,
        longitude:       p.longitude,
        pricePerNight:   p.pricePerNight,
        numberOfBeds:    p.numberOfBeds,
        hasBreakfast:    p.hasBreakfast,
        pricePerDay:     p.pricePerDay,
        capacity:        p.capacity,
        minLeaseDuration: p.minLeaseDuration,
      );
      await context.read<PropertyProvider>().updateProperty(updated);
      if (!mounted) return;
      Navigator.pop(context, true); // true = reload needed
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Annonce mise à jour avec succès',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.accentColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e',
            style: const TextStyle(fontFamily: 'Poppins'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(title, style: const TextStyle(
        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
        fontSize: 13, color: AppTheme.accentColor)),
  );

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? keyboard, String? Function(String?)? validator,
       int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _dropdown<T>(String label, List<T> items, T value, ValueChanged<T?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        value: items.contains(value) ? value : items.first,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        ),
        items: items.map((e) => DropdownMenuItem<T>(
          value: e,
          child: Text(e.toString(), style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13)),
        )).toList(),
        onChanged: onChanged,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
            color: AppTheme.textPrimary),
        isExpanded: true,
      ),
    );
  }

  Widget _toggle(String label, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: value ? AppTheme.accentColor : AppTheme.textHint),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textPrimary))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.accentColor,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Modifier l\'annonce',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                fontSize: 16)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Informations principales ────────────────────────────────────
            _section('Informations principales'),
            _field('Titre de l\'annonce', _titleCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Titre requis' : null),
            _field('Description', _descCtrl, maxLines: 4),

            // ── Type de propriété / Transaction ─────────────────────────────
            _section('Type de propriété'),
            _dropdown('Type de propriété', AppConstants.propertyTypes,
                _selectedType, (v) {
              if (v != null) setState(() => _selectedType = v);
            }),
            _dropdown('Type de transaction', AppConstants.transactionTypes,
                _selectedTransaction, (v) {
              if (v != null) setState(() => _selectedTransaction = v);
            }),

            // ── Prix ────────────────────────────────────────────────────────
            _section('Prix'),
            Row(children: [
              Expanded(
                flex: 3,
                child: _field('Prix', _priceCtrl,
                    keyboard: TextInputType.number,
                    validator: (v) => (v == null || double.tryParse(v.trim()) == null)
                        ? 'Prix invalide' : null),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _dropdown('Devise', const ['USD', 'CDF', 'CFA', 'AOA', 'RWF', 'BIF', 'EUR'],
                    _selectedCurrency, (v) {
                  if (v != null) setState(() => _selectedCurrency = v);
                }),
              ),
            ]),

            // ── Garantie & Commission (Location seulement) ──────────────────
            if (_isLocation) ...[
              _section('Conditions de location'),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  const Icon(Icons.security_rounded, size: 18, color: AppTheme.accentColor),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Garantie (mois)',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          color: AppTheme.textPrimary))),
                  Row(children: [
                    IconButton(
                      onPressed: () => setState(() {
                        if (_garantieMois > 0) _garantieMois--;
                      }),
                      icon: const Icon(Icons.remove_circle_outline,
                          color: AppTheme.textHint),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    Text('$_garantieMois mois', style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                        fontSize: 14, color: AppTheme.accentColor)),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => _garantieMois++),
                      icon: const Icon(Icons.add_circle_outline,
                          color: AppTheme.accentColor),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ]),
                ]),
              ),
              _toggle('Commission agence', Icons.handshake_rounded,
                  _hasCommission,
                  (v) => setState(() => _hasCommission = v)),
              if (_hasCommission)
                _field('Commission (% du loyer)', _commissionPctCtrl,
                    keyboard: TextInputType.number),
            ],

            // ── Superficie ──────────────────────────────────────────────────
            _section('Superficie & Pièces'),
            Row(children: [
              Expanded(child: _field('Surface (m²)', _surfaceCtrl,
                  keyboard: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field('Étages', _floorsCtrl,
                  keyboard: TextInputType.number)),
            ]),
            Row(children: [
              Expanded(child: _field('Chambres', _bedroomsCtrl,
                  keyboard: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field('Salles de bain', _bathroomsCtrl,
                  keyboard: TextInputType.number)),
            ]),

            // ── Localisation ────────────────────────────────────────────────
            _section('Localisation'),
            _dropdown('Pays', AppConstants.filterCountries,
                _selectedCountry, (v) {
              if (v != null) setState(() {
                _selectedCountry = v;
                _selectedProvince = AppConstants.getProvincesForCountry(v).first;
                _selectedCity = AppConstants.getCitiesForProvince(
                    v, _selectedProvince).first;
                _selectedCommune = AppConstants.getCommunesForCity(_selectedCity).isNotEmpty
                    ? AppConstants.getCommunesForCity(_selectedCity).first
                    : '';
              });
            }),
            _dropdown('Province', _provinces, _selectedProvince, (v) {
              if (v != null) setState(() {
                _selectedProvince = v;
                _selectedCity = AppConstants.getCitiesForProvince(
                    _selectedCountry, v).first;
                _selectedCommune = AppConstants.getCommunesForCity(_selectedCity).isNotEmpty
                    ? AppConstants.getCommunesForCity(_selectedCity).first
                    : '';
              });
            }),
            Row(children: [
              Expanded(child: _dropdown('Ville', _cities, _selectedCity, (v) {
                if (v != null) setState(() {
                  _selectedCity = v;
                  _selectedCommune = AppConstants.getCommunesForCity(v).isNotEmpty
                      ? AppConstants.getCommunesForCity(v).first
                      : '';
                });
              })),
              const SizedBox(width: 8),
              if (_communes.isNotEmpty)
                Expanded(child: _dropdown('Commune', _communes,
                    _communes.contains(_selectedCommune)
                        ? _selectedCommune
                        : _communes.first, (v) {
                  if (v != null) setState(() => _selectedCommune = v);
                })),
            ]),
            _field('Quartier / Adresse', _quartierCtrl),

            // ── Équipements ─────────────────────────────────────────────────
            _section('Équipements'),
            _toggle('Parking', Icons.local_parking_rounded,
                _hasParking, (v) => setState(() => _hasParking = v)),
            _toggle('Ascenseur', Icons.elevator_rounded,
                _hasAscenseur, (v) => setState(() => _hasAscenseur = v)),
            _toggle('Climatisation', Icons.ac_unit_rounded,
                _hasAirConditioning, (v) => setState(() => _hasAirConditioning = v)),
            _toggle('Cuisine équipée', Icons.kitchen_rounded,
                _hasCuisineEquipee, (v) => setState(() => _hasCuisineEquipee = v)),
            _toggle('Groupe électrogène', Icons.electric_bolt_rounded,
                _hasElectricity, (v) => setState(() => _hasElectricity = v)),
            _toggle('Sécurité 24h/24', Icons.security_rounded,
                _hasWater, (v) => setState(() => _hasWater = v)),

            const SizedBox(height: 20),
            // ── Bouton Enregistrer ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Enregistrer les modifications',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
