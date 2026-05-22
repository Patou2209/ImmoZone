import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  // ── Photos ────────────────────────────────────────────────────────────────
  // null = utiliser les images existantes de la propriété (p.images)
  XFile? _newMainPhoto;                       // nouvelle photo principale (remplace [0])
  final List<XFile> _newSecondaryPhotos = []; // nouvelles photos secondaires (remplacent [1..3])
  bool _photosChanged = false;                // true = re-encoder à la sauvegarde
  final _picker = ImagePicker();

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

  // ── Photo helpers ─────────────────────────────────────────────────────────
  Future<void> _pickMainPhoto() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 50);
    if (picked != null) {
      setState(() {
        _newMainPhoto = picked;
        _photosChanged = true;
      });
    }
  }

  Future<void> _pickSecondaryPhoto() async {
    if (_newSecondaryPhotos.length >= 3) return;
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 50);
    if (picked != null) {
      setState(() {
        _newSecondaryPhotos.add(picked);
        _photosChanged = true;
      });
    }
  }

  void _removeSecondaryPhoto(int index) {
    setState(() {
      _newSecondaryPhotos.removeAt(index);
      _photosChanged = true;
    });
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

      // ── Encoder les nouvelles photos si modifiées ─────────────────────────
      List<String> finalImages = p.images; // conserver les anciennes par défaut
      if (_photosChanged && !kIsWeb) {
        final newImages = <String>[];
        int totalBytes = 0;
        const int maxDocBytes = 900000;
        final allNew = [
          if (_newMainPhoto != null) _newMainPhoto!,
          ..._newSecondaryPhotos,
        ];
        if (allNew.isNotEmpty) {
          for (final xfile in allNew) {
            if (totalBytes >= maxDocBytes) break;
            try {
              final bytes = await File(xfile.path).readAsBytes();
              if (totalBytes + bytes.length > maxDocBytes) break;
              final b64 = base64Encode(bytes);
              final ext = xfile.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
              newImages.add('data:image/$ext;base64,$b64');
              totalBytes += bytes.length;
            } catch (_) {}
          }
          finalImages = newImages;
        }
      }
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
        images:          finalImages,
        mainImageIndex:  0,
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

  // ── Photo editor ───────────────────────────────────────────────────────────
  Widget _buildPhotoEditor() {
    final existingImages = widget.property.images;

    // Photo principale : nouvelle si choisie, sinon première image existante
    Widget mainPhotoWidget;
    if (_newMainPhoto != null) {
      mainPhotoWidget = kIsWeb
          ? Container(color: AppTheme.primaryColor.withValues(alpha: 0.1),
              child: const Icon(Icons.image_rounded, size: 40, color: AppTheme.accentColor))
          : Image.file(File(_newMainPhoto!.path), fit: BoxFit.cover);
    } else if (existingImages.isNotEmpty) {
      final src = existingImages[0];
      if (src.startsWith('data:image')) {
        final b64 = src.split(',').last;
        mainPhotoWidget = Image.memory(base64Decode(b64), fit: BoxFit.cover);
      } else {
        mainPhotoWidget = Image.network(src, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded,
                color: AppTheme.textHint));
      }
    } else {
      mainPhotoWidget = const Icon(Icons.add_photo_alternate_outlined,
          size: 40, color: AppTheme.textHint);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Info
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.accentColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 14, color: AppTheme.accentColor),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Appuyez sur une photo pour la remplacer. Max 4 photos (1 principale + 3 secondaires).',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                color: AppTheme.accentColor),
          )),
        ]),
      ),
      const SizedBox(height: 12),

      // Photo principale
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Main photo slot
        GestureDetector(
          onTap: _pickMainPhoto,
          child: Stack(children: [
            Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _newMainPhoto != null
                      ? AppTheme.accentColor
                      : AppTheme.dividerColor,
                  width: _newMainPhoto != null ? 2 : 1,
                ),
                color: AppTheme.primaryColor.withValues(alpha: 0.04),
              ),
              clipBehavior: Clip.antiAlias,
              child: mainPhotoWidget,
            ),
            // Badge "Principale"
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.75),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(9),
                    bottomRight: Radius.circular(9),
                  ),
                ),
                child: const Center(child: Text('Principale',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                        color: Colors.white, fontWeight: FontWeight.w600))),
              ),
            ),
            // Edit icon overlay
            Positioned(
              top: 4, right: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_rounded, size: 12,
                    color: AppTheme.accentColor),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),

        // Secondary photos grid
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Photos secondaires',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                    color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              // Existing secondary photos (if no new ones chosen)
              if (_newSecondaryPhotos.isEmpty && existingImages.length > 1)
                ...List.generate(
                  (existingImages.length - 1).clamp(0, 3),
                  (i) {
                    final src = existingImages[i + 1];
                    Widget img;
                    if (src.startsWith('data:image')) {
                      img = Image.memory(base64Decode(src.split(',').last),
                          fit: BoxFit.cover);
                    } else {
                      img = Image.network(src, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_rounded, size: 18,
                              color: AppTheme.textHint));
                    }
                    return GestureDetector(
                      onTap: _pickSecondaryPhoto,
                      child: Container(
                        width: 70, height: 70,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.dividerColor),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: img,
                      ),
                    );
                  },
                ),

              // New secondary photos chosen
              ..._newSecondaryPhotos.asMap().entries.map((entry) {
                final i = entry.key;
                final xfile = entry.value;
                return Stack(children: [
                  Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.accentColor.withValues(alpha: 0.6)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: kIsWeb
                        ? Container(color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            child: const Icon(Icons.image_rounded,
                                color: AppTheme.accentColor))
                        : Image.file(File(xfile.path), fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2, right: 2,
                    child: GestureDetector(
                      onTap: () => _removeSecondaryPhoto(i),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ]);
              }),

              // Add button (if < 3 secondary)
              if (_newSecondaryPhotos.length < 3 ||
                  (_newSecondaryPhotos.isEmpty && existingImages.length < 4))
                GestureDetector(
                  onTap: _pickSecondaryPhoto,
                  child: Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.3),
                          style: BorderStyle.solid),
                      color: AppTheme.primaryColor.withValues(alpha: 0.04),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 22,
                            color: AppTheme.primaryColor),
                        SizedBox(height: 2),
                        Text('Ajouter', style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 9, color: AppTheme.primaryColor)),
                      ],
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ]),

      // "Remplacer toutes" button when new photos chosen
      if (_photosChanged) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.check_circle_rounded, size: 14,
              color: AppTheme.successColor),
          const SizedBox(width: 6),
          Text(
            '${(_newMainPhoto != null ? 1 : 0) + _newSecondaryPhotos.length} nouvelle(s) photo(s) '
            'sélectionnée(s) — seront enregistrées',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                color: AppTheme.successColor),
          ),
        ]),
      ],
    ]);
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
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w600,
            fontSize: 16, color: Colors.white),
        title: const Text('Modifier l\'annonce'),
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
      body: SafeArea(
        top: false,
        child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Photos ─────────────────────────────────────────────────────
            _section('Photos'),
            _buildPhotoEditor(),
            const SizedBox(height: 4),

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
      ),
    );
  }
}
