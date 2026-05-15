import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../providers/auth_provider.dart';
import '../../../providers/property_provider.dart';
import '../../../models/property_model.dart';
import '../../../models/payment_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/data_service.dart';

class PostPropertyScreen extends StatefulWidget {
  const PostPropertyScreen({super.key});
  @override
  State<PostPropertyScreen> createState() => _PostPropertyScreenState();
}

class _PostPropertyScreenState extends State<PostPropertyScreen> {
  int _step = 0;
  final PageController _pageCtrl = PageController();
  bool _submitting = false;

  // ── Etape 1 — Informations personnelles & adresse ─────────────────────────
  final _nomCtrl      = TextEditingController();
  // WhatsApp: indicatif pays + 9 chiffres
  String _waCountryCode = '+243';
  final _waNumberCtrl = TextEditingController();   // 9 chiffres seulement
  final _emailCtrl    = TextEditingController();
  // Pays : selecteur (pas de saisie manuelle)
  String _selectedCountry  = AppConstants.defaultCountry;
  String _selectedProvince = 'Kinshasa';
  String _selectedCity     = 'Kinshasa';
  String _selectedCommune  = 'Gombe';
  final _quartierCtrl  = TextEditingController();
  String _selectedType = AppConstants.propertyTypes.first;
  String _selectedTransaction = AppConstants.transactionTypes.first;
  final _descCtrl     = TextEditingController();
  final _priceCtrl    = TextEditingController();
  String _selectedCurrency = 'USD';
  final _surfaceCtrl  = TextEditingController();
  final _bedroomsCtrl = TextEditingController();
  final _bathroomsCtrl = TextEditingController(); // SDB

  // ── Champs conditionnels selon la catégorie ──────────────────────────────
  final _floorsCtrl    = TextEditingController(); // Maison, Appartement, Bureau
  bool _hasParking        = false;
  bool _hasElectricity     = true;
  bool _hasWater           = true;
  bool _hasAscenseur       = false;
  bool _hasAirConditioning = false; // Climatisation (Appart/Maison/Bureau/Hotel)
  bool _hasCuisineEquipee  = false;
  // Chambre d'hotel
  final _numberOfBedsCtrl = TextEditingController();
  bool _hasBreakfast       = false;
  final _pricePerNightCtrl = TextEditingController();
  // Salle de fêtes / Espace Funéraire / Salle Polyvalente
  final _capacityCtrl    = TextEditingController();
  final _pricePerDayCtrl = TextEditingController();
  // Concession (superficie en ha)
  final _hectaresCtrl = TextEditingController();
  // Terrain à bâtir (dimensions L×l)
  final _longueurCtrl = TextEditingController();
  final _largeurCtrl  = TextEditingController();
  // Location: garantie (mois) + commission
  int _garantieMois = 0;           // 0 = pas de garantie
  bool _hasCommission = false;
  final _commissionPctCtrl = TextEditingController();

  // ── Etape 2 — Images ──────────────────────────────────────────────────────
  final List<String> _imageUrls = [];
  final List<XFile> _localImages = [];
  final ImagePicker _picker = ImagePicker();
  final _imageUrlCtrl = TextEditingController();

  // ── Etape 3 — Paiement ────────────────────────────────────────────────────
  Map<String, dynamic>? _selectedPack;
  Map<String, dynamic>? _selectedPaymentMethod;
  final _transactionRefCtrl = TextEditingController();
  // Credit check state
  int _userAvailableCredits = 0;
  int _requiredCredits = 1;
  int _freeQuotaAvailable = 0; // nombre d'annonces gratuites disponibles
  bool _hasEnoughCredits = false;
  bool _creditChecked = false;
  String _publicationRight = 'no_right'; // 'free_trial' | 'free_quota' | 'paid_credit' | 'no_right'
  // Payment submission state (when balance insufficient)
  bool _paymentSubmitted = false;  // user submitted payment ref → waiting admin
  bool _submittingPayment = false; // loading while saving payment request
  String? _pendingPaymentId;       // ID of the pending payment for tracking

  // ── Etape 4 — Confirmation ────────────────────────────────────────────────
  bool _submitted = false;
  // ignore: unused_field
  String? _createdPropertyId;

  // Devise locale selon pays
  String get _localCurrency {
    if (_selectedCountry == 'Congo (RDC)') return 'CDF';
    if (_selectedCountry == 'Congo (Brazzaville)') return 'XAF';
    if (_selectedCountry == 'Angola') return 'AOA';
    if (_selectedCountry == 'Rwanda') return 'RWF';
    if (_selectedCountry == 'Burundi') return 'BIF';
    return 'USD';
  }

  // Listes dynamiques selon selections
  List<String> get _availableCities =>
      AppConstants.getCitiesForProvince(_selectedCountry, _selectedProvince);

  List<String> get _availableCommunes =>
      AppConstants.getCommunesForCity(_selectedCity);

  List<String> get _availableProvinces =>
      AppConstants.getProvincesForCountry(_selectedCountry);

  @override
  void initState() {
    super.initState();
    // Pre-remplir avec les infos de l'utilisateur connecte
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillUserInfo());
    // Rafraîchir l'aperçu L×l en temps réel
    _longueurCtrl.addListener(() => setState(() {}));
    _largeurCtrl.addListener(() => setState(() {}));
  }

  void _prefillUserInfo() {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user != null) {
      _nomCtrl.text   = user.name;
      _emailCtrl.text = user.email;
      // Extraire l'indicatif + numero si deja format international
      final phone = user.phone ?? '';
      if (phone.startsWith('+')) {
        // Trouver l'indicatif correspondant
        final match = AppConstants.countryCodes.firstWhere(
          (c) => phone.startsWith(c['code']!),
          orElse: () => {'code': '+243', 'country': 'Congo (RDC)', 'flag': '🇨🇩'},
        );
        _waCountryCode = match['code']!;
        _waNumberCtrl.text = phone.substring(match['code']!.length).replaceAll(' ', '');
      } else {
        _waNumberCtrl.text = phone.replaceAll(' ', '');
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in [
      _nomCtrl, _waNumberCtrl, _emailCtrl, _quartierCtrl,
      _descCtrl, _priceCtrl, _surfaceCtrl, _bedroomsCtrl, _bathroomsCtrl,
      _floorsCtrl, _numberOfBedsCtrl, _pricePerNightCtrl,
      _capacityCtrl, _pricePerDayCtrl, _hectaresCtrl,
      _longueurCtrl, _largeurCtrl,
      _commissionPctCtrl,
      _imageUrlCtrl, _transactionRefCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  void _goTo(int step) {
    // Reset credit check when entering step 3 (in case commune changed)
    if (step == 2) {
      setState(() {
        _creditChecked = false;
        _hasEnoughCredits = false;
        _publicationRight = 'no_right';
      });
    }
    setState(() => _step = step);
    _pageCtrl.animateToPage(step,
      duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  String get _fullWhatsApp => '$_waCountryCode${_waNumberCtrl.text.trim()}';

  bool _validateStep1() {
    final auth = context.read<AuthProvider>();
    final isLoggedIn = auth.isLoggedIn;
    // Si non connecte, verifier les coordonnees
    if (!isLoggedIn) {
      if (_nomCtrl.text.trim().isEmpty)  { _err('Nom complet requis'); return false; }
      if (_waNumberCtrl.text.trim().isEmpty) { _err('Numero WhatsApp requis'); return false; }
      if (_emailCtrl.text.trim().isEmpty) { _err('Email requis'); return false; }
    }
    // Quartier est optionnel
    if (_priceCtrl.text.trim().isEmpty)    { _err('Prix requis'); return false; }
    // Chambres & SDB obligatoires pour Maison et Appartement/Flat
    final requiresRooms = _selectedType == 'Maison' || _selectedType == 'Appartement / Flat';
    if (requiresRooms) {
      if (_bedroomsCtrl.text.trim().isEmpty || int.tryParse(_bedroomsCtrl.text.trim()) == null) {
        _err('Nombre de chambres requis pour ce type de bien'); return false;
      }
      if (_bathroomsCtrl.text.trim().isEmpty || int.tryParse(_bathroomsCtrl.text.trim()) == null) {
        _err('Nombre de salles de bain requis pour ce type de bien'); return false;
      }
    }
    // Superficie obligatoire pour Bureau, Propriété Commerciale, Propriété Industrielle
    if (AppConstants.catWithSurfaceRequired.contains(_selectedType)) {
      if (_surfaceCtrl.text.trim().isEmpty || double.tryParse(_surfaceCtrl.text.trim()) == null) {
        _err('La superficie (m²) est obligatoire pour ce type de bien'); return false;
      }
    }
    // Dimensions obligatoires pour Terrain à bâtir
    if (_selectedType == 'Terrain à bâtir') {
      if (_longueurCtrl.text.trim().isEmpty || double.tryParse(_longueurCtrl.text.trim()) == null) {
        _err('La longueur (m) est obligatoire pour un terrain à bâtir'); return false;
      }
      if (_largeurCtrl.text.trim().isEmpty || double.tryParse(_largeurCtrl.text.trim()) == null) {
        _err('La largeur (m) est obligatoire pour un terrain à bâtir'); return false;
      }
    }
    return true;
  }

  bool _validateStep2() {
    final total = _imageUrls.length + _localImages.length;
    if (total < 4) {
      _err('Veuillez ajouter au moins 4 photos du bien (${total}/4)'); return false;
    }
    return true;
  }

  bool _validateStep3() {
    // If user has enough credits, no payment needed
    if (_hasEnoughCredits) return true;
    // If payment is pending admin approval, block progression
    if (_paymentSubmitted) {
      _err('Votre recharge est en attente de validation par l\'administrateur. Vous serez notifié(e) dès qu\'elle sera approuvée.');
      return false;
    }
    // Otherwise need to submit payment first
    _err('Veuillez soumettre votre demande de recharge avant de continuer.');
    return false;
  }

  Future<void> _submitPaymentRequest() async {
    if (_selectedPack == null)          { _err('Veuillez choisir un pack de recharge'); return; }
    if (_selectedPaymentMethod == null) { _err('Veuillez choisir un moyen de paiement'); return; }
    if (_transactionRefCtrl.text.trim().isEmpty) {
      _err('Veuillez saisir la référence de votre paiement'); return;
    }
    setState(() => _submittingPayment = true);
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    final ds = DataService();
    final pack = _selectedPack!;
    final method = _selectedPaymentMethod!;
    final price = (pack['price'] as num?)?.toDouble() ?? 0.0;
    final productType = pack['productType'] as String? ?? 'souscription_credits_10';
    // Stocker le qty exact du pack pour que l'admin puisse créditer le bon montant
    final creditsQty = (pack['qty'] as num?)?.toInt() ?? 0;
    final payment = PaymentModel(
      id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
      userId: user.id,
      userName: user.name,
      orderId: 'ord_${DateTime.now().millisecondsSinceEpoch}',
      operator: method['icon'] ?? 'mpesa',
      phoneNumber: method['number'] ?? '',
      amount: price,
      currency: 'USD',
      status: 'awaiting_manual',
      transactionReference: _transactionRefCtrl.text.trim(),
      createdAt: DateTime.now(),
      productType: productType,
      creditsQty: creditsQty,
    );
    await ds.createPayment(payment);
    if (mounted) {
      setState(() {
        _submittingPayment = false;
        _paymentSubmitted = true;
        _pendingPaymentId = payment.id;
      });
    }
  }

  Future<void> _checkUserCredits() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    final ds = DataService();
    final userId = auth.currentUser!.id;
    final required = ds.getCreditsForCommune(_selectedCommune);
    // Count paid credits only (free quota handled separately via checkPublicationRight)
    final available = await ds.getUserAvailableCredits(userId);
    // Use the authoritative publication right check (free trial, free quota, paid credit, no right)
    final right = await ds.checkPublicationRight(userId, commune: _selectedCommune);
    // "enough" = free trial active, OR free monthly quota still available, OR sufficient paid credits
    final enough = (right == 'free_trial') || (right == 'free_quota') || (right == 'paid_credit');
    // Récupérer le quota gratuit disponible pour affichage dynamique
    final quota = await ds.getCurrentQuota(userId);
    final freeLeft = quota.freeQuota - quota.usedFreeQuota;
    if (mounted) {
      setState(() {
        _requiredCredits = required;
        _userAvailableCredits = available;
        _freeQuotaAvailable = freeLeft.clamp(0, 999);
        _hasEnoughCredits = enough;
        _publicationRight = right;
        _creditChecked = true;
        // Reset payment submitted state when re-checking credits
        // (e.g. admin just approved and user re-entered step 3)
        if (enough && _paymentSubmitted) {
          _paymentSubmitted = false;
          _pendingPaymentId = null;
        }
      });
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _submitAnnonce() async {
    setState(() => _submitting = true);
    try {
      final auth = context.read<AuthProvider>();
      final user = auth.currentUser!;

      // Consume the publication right (handles free trial, free quota, or paid credits)
      if (_hasEnoughCredits) {
        final ds = DataService();
        await ds.consumePublicationRight(user.id, commune: _selectedCommune);
      }

      // ── Convertir les fichiers locaux en base64 ──────────────────────────────
      // Les chemins locaux (/data/user/0/...) ne sont accessibles que sur l'appareil
      // de l'annonceur. On encode en base64 pour que tous les appareils voient les photos.
      // Limite Firestore : 1 Mo par document. imageQuality:40 ≈ 80–150 KB/photo → 5×150=750KB OK.
      final images = [..._imageUrls]; // URLs réseau conservées telles quelles
      if (!kIsWeb) {
        int totalBytes = 0;
        const int maxDocBytes = 900000; // 900 KB marge de sécurité sous 1 MB
        for (final xfile in _localImages) {
          if (totalBytes >= maxDocBytes) break; // ne pas dépasser la limite
          try {
            final bytes = await File(xfile.path).readAsBytes();
            if (totalBytes + bytes.length > maxDocBytes) break; // photo ferait dépasser
            final b64 = base64Encode(bytes);
            final ext = xfile.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
            images.add('data:image/$ext;base64,$b64');
            totalBytes += bytes.length;
          } catch (_) {
            // Photo ignorée si lecture échoue
          }
        }
      }
      final finalImages = images;

      // Utiliser les infos du compte connecte ou ce qui a ete saisi
      final ownerName     = _nomCtrl.text.trim().isNotEmpty ? _nomCtrl.text.trim() : user.name;
      final ownerEmail    = _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : user.email;
      final ownerWhatsApp = _waNumberCtrl.text.trim().isNotEmpty
          ? _fullWhatsApp
          : (user.phone ?? '');

      final property = PropertyModel(
        id: 'prop_${DateTime.now().millisecondsSinceEpoch}',
        title: '$_selectedType \u2013 ${_quartierCtrl.text.trim().isNotEmpty ? "${_quartierCtrl.text.trim()}, " : ""}$_selectedCity',
        description: _descCtrl.text.trim().isNotEmpty
            ? _descCtrl.text.trim()
            : '$_selectedType a $_selectedTransaction \u2013 ${_quartierCtrl.text.trim().isNotEmpty ? "${_quartierCtrl.text.trim()}, " : ""}$_selectedCommune, $_selectedCity',
        type: _selectedType,
        transactionType: _selectedTransaction,
        price: double.tryParse(_priceCtrl.text.trim()) ?? 0,
        currency: _selectedCurrency,
        country: _selectedCountry,
        province: _selectedProvince,
        city: _selectedCity,
        commune: _selectedCommune,
        quartier: _quartierCtrl.text.trim(),
        address: _quartierCtrl.text.trim(),
        surface: double.tryParse(_surfaceCtrl.text.trim()) ??
                 double.tryParse(_hectaresCtrl.text.trim()),
        longueurM: double.tryParse(_longueurCtrl.text.trim()),
        largeurM:  double.tryParse(_largeurCtrl.text.trim()),
        bedrooms: int.tryParse(_bedroomsCtrl.text.trim()),
        bathrooms: int.tryParse(_bathroomsCtrl.text.trim()),
        floors: int.tryParse(_floorsCtrl.text.trim()),
        hasParking: _hasParking,
        hasElectricity: _hasElectricity,
        hasWater: _hasWater,
        hasAscenseur: _hasAscenseur,
        hasCuisineEquipee: _hasCuisineEquipee,
        numberOfBeds: int.tryParse(_numberOfBedsCtrl.text.trim()),
        hasAirConditioning: _hasAirConditioning,
        hasBreakfast: _hasBreakfast,
        pricePerNight: double.tryParse(_pricePerNightCtrl.text.trim()),
        capacity: int.tryParse(_capacityCtrl.text.trim()),
        pricePerDay: double.tryParse(_pricePerDayCtrl.text.trim()),
        garantieMois: _garantieMois > 0 ? _garantieMois : null,
        hasCommission: _hasCommission,
        commissionPct: _hasCommission ? double.tryParse(_commissionPctCtrl.text.trim()) : null,
        images: finalImages,
        ownerId: user.id,
        ownerName: ownerName,
        ownerPhone: ownerWhatsApp,
        ownerEmail: ownerEmail,
        ownerWhatsApp: ownerWhatsApp,
        ownerCategory: user.category ?? '',
        status: AppConstants.statusPending,
        createdAt: DateTime.now(),
      );

      await context.read<PropertyProvider>().addProperty(property);
      _createdPropertyId = property.id;

      if (!mounted) return;
      setState(() { _submitting = false; _submitted = true; });
      _goTo(4);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _err('Erreur lors de la soumission : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        title: const Text('Publier une annonce',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _buildStepIndicator(),
        ),
      ),
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildStep1(),
          _buildStep2(),
          _buildStep3(),
          _buildStep4(),
          _buildStep5(),
        ],
      ),
    );
  }

  // ── Indicateur d'etapes ───────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    final labels = ['Infos', 'Photos', 'Paiement', 'Envoi', 'Confirmation'];
    return Container(
      color: AppTheme.primaryColor,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(5, (i) {
          final isDone   = _step > i;
          final isActive = _step == i;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? AppTheme.accentColor
                              : isActive
                                  ? Colors.white
                                  : Colors.white24,
                          border: isActive
                              ? Border.all(color: AppTheme.accentColor, width: 2)
                              : null,
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(Icons.check, color: Colors.white, size: 14)
                              : Text('${i+1}', style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  fontFamily: 'Poppins',
                                  color: isActive ? AppTheme.accentColor : Colors.white54)),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(labels[i], style: TextStyle(
                        fontSize: 9, fontFamily: 'Poppins',
                        color: isActive || isDone ? Colors.white : Colors.white38,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                      )),
                    ],
                  ),
                ),
                if (i < 4)
                  Container(
                    height: 2, width: 12,
                    color: _step > i ? AppTheme.accentColor : Colors.white24,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ETAPE 1 — Coordonnees + adresse du bien
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStep1() {
    final auth    = context.watch<AuthProvider>();
    final isLoggedIn = auth.isLoggedIn;
    final user    = auth.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepHeader('Etape 1', 'Coordonnees & adresse du bien', Icons.person_pin_rounded),
        const SizedBox(height: 20),

        // ── Coordonnees annonceur ───────────────────────────────────────────
        if (isLoggedIn) ...[
          // Afficher les infos du compte : pas de saisie requise
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accentColor, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800, fontSize: 18,
                        color: AppTheme.accentColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.name ?? '',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700, fontSize: 14,
                        color: AppTheme.textPrimary)),
                Text(user?.email ?? '',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 12, color: AppTheme.textSecondary)),
                if ((user?.phone ?? '').isNotEmpty)
                  Text(user!.phone!,
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 12, color: AppTheme.accentColor)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.4)),
                ),
                child: const Text('Connecte',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.w700, color: AppTheme.successColor)),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          const Text(
            'Vos coordonnees seront utilisees pour cette annonce.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 20),
        ] else ...[
          // Non connecte : saisie des coordonnees
          _sectionLabel('Vos coordonnees'),
          const SizedBox(height: 10),
          _field(_nomCtrl, 'Nom complet *', Icons.person_outline, 'Jean Dupont'),
          // WhatsApp avec selecteur d'indicatif
          _whatsAppField(),
          _field(_emailCtrl, 'Adresse email *', Icons.email_outlined,
              'email@exemple.com', type: TextInputType.emailAddress),
          const SizedBox(height: 20),
        ],

        // ── Type de propriété & transaction ──────────────────────────────────────
        _sectionLabel('Type de propriété'),
        const SizedBox(height: 10),
        _dropdown('Type de propriété *', _selectedType, AppConstants.propertyTypes,
            Icons.home_outlined, (v) => setState(() => _selectedType = v!)),
        _dropdown('Type de transaction *', _selectedTransaction,
            AppConstants.transactionTypes, Icons.swap_horiz,
            (v) => setState(() => _selectedTransaction = v!)),
        _field(_priceCtrl, 'Prix *', Icons.attach_money, '0',
            type: TextInputType.number, suffix: _currencyDropdown()),

        // ── Champs conditionnels selon la catégorie ─────────────────────────
        _buildCategoryFields(),
        const SizedBox(height: 20),

        // ── Adresse du bien ────────────────────────────────────────────────
        _sectionLabel('Adresse complete du bien'),
        const SizedBox(height: 10),

        // Pays : selecteur (pas de saisie manuelle)
        _countryDropdown(),
        const SizedBox(height: 12),

        // Province dynamique selon le pays
        _dropdown('Province *', _selectedProvince,
            _availableProvinces.isEmpty ? AppConstants.provinces : _availableProvinces,
            Icons.map_outlined, (v) {
          if (v != null) {
            setState(() {
              _selectedProvince = v;
              final cities = AppConstants.getCitiesForProvince(_selectedCountry, v);
              _selectedCity    = cities.isNotEmpty ? cities.first : '';
              final communes   = AppConstants.getCommunesForCity(_selectedCity);
              _selectedCommune = communes.isNotEmpty ? communes.first : '';
            });
          }
        }),

        // Ville dynamique selon province
        if (_availableCities.isNotEmpty) ...[
          _dropdown('Ville *', _selectedCity, _availableCities,
              Icons.location_city, (v) {
            if (v != null) {
              setState(() {
                _selectedCity = v;
                final communes = AppConstants.getCommunesForCity(v);
                _selectedCommune = communes.isNotEmpty ? communes.first : '';
              });
            }
          }),
        ],

        // Commune dynamique selon ville
        if (_availableCommunes.isNotEmpty)
          _dropdown('Commune *', _selectedCommune, _availableCommunes,
              Icons.location_on_outlined,
              (v) => setState(() => _selectedCommune = v ?? '')),

        _field(_quartierCtrl, 'Quartier (optionnel)', Icons.holiday_village_outlined, 'Ex: Matonge'),
        const SizedBox(height: 10),
        _field(_descCtrl, 'Description (optionnel)', Icons.description_outlined,
            'Decrivez votre bien...', maxLines: 4),
        const SizedBox(height: 28),

        _navButtons(
          onNext: () { if (_validateStep1()) _goTo(1); },
          showBack: false,
        ),
        const SizedBox(height: 30),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHAMPS CONDITIONNELS selon catégorie de bien
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildCategoryFields() {
    final type = _selectedType;
    final isLocationTx = _selectedTransaction == 'Location';

    // Helpers locaux
    Widget yesNoToggle(String label, IconData icon, bool value,
        void Function(bool) onChanged) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(children: [
            Icon(icon, color: AppTheme.accentColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppTheme.textPrimary)),
            ),
            GestureDetector(
              onTap: () => onChanged(false),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: !value
                      ? AppTheme.errorColor
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(8)),
                  border: Border.all(
                      color: !value
                          ? AppTheme.errorColor
                          : AppTheme.dividerColor),
                ),
                child: Text('Non',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: !value ? Colors.white : AppTheme.textHint)),
              ),
            ),
            GestureDetector(
              onTap: () => onChanged(true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: value
                      ? AppTheme.successColor
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.horizontal(right: Radius.circular(8)),
                  border: Border.all(
                      color: value
                          ? AppTheme.successColor
                          : AppTheme.dividerColor),
                ),
                child: Text('Oui',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: value ? Colors.white : AppTheme.textHint)),
              ),
            ),
          ]),
        ),
      );
    }

    final fields = <Widget>[];

    // ── Maison & Appartement / Flat ─────────────────────────────────────────
    if (type == 'Maison' || type == 'Appartement / Flat') {
      fields.addAll([
        _field(_surfaceCtrl, 'Superficie (m²) — optionnel', Icons.square_foot, '',
            type: TextInputType.number),
        _field(_bedroomsCtrl, 'Nombre de chambres *', Icons.bed_outlined, '0',
            type: TextInputType.number),
        _field(_bathroomsCtrl, 'Nombre de salles de bain *',
            Icons.bathtub_outlined, '0',
            type: TextInputType.number),
        _field(_floorsCtrl, 'Nombre d\'étages', Icons.layers_outlined, '1',
            type: TextInputType.number),
        yesNoToggle('Parking', Icons.local_parking_rounded, _hasParking,
            (v) => setState(() => _hasParking = v)),
        yesNoToggle('Ascenseur', Icons.elevator_rounded, _hasAscenseur,
            (v) => setState(() => _hasAscenseur = v)),
        yesNoToggle('Climatisation', Icons.ac_unit_rounded, _hasAirConditioning,
            (v) => setState(() => _hasAirConditioning = v)),
        yesNoToggle('Cuisine équipée', Icons.kitchen_rounded, _hasCuisineEquipee,
            (v) => setState(() => _hasCuisineEquipee = v)),
        yesNoToggle('Groupe Électrogène/Panneau Solaire', Icons.electric_bolt_rounded, _hasElectricity,
            (v) => setState(() => _hasElectricity = v)),
        yesNoToggle('Sécurité 24h/24', Icons.security_rounded, _hasWater,
            (v) => setState(() => _hasWater = v)),
        if (isLocationTx) ...[
          _garantieDropdown(),
          _commissionField(),
        ],
      ]);
    }

    // ── Bureau ──────────────────────────────────────────────────────────────
    else if (type == 'Bureau') {
      fields.addAll([
        _field(_surfaceCtrl, 'Superficie (m²) *', Icons.square_foot, '0',
            type: TextInputType.number),
        _field(_floorsCtrl, 'Étage / Niveau', Icons.layers_outlined, '1',
            type: TextInputType.number),
        yesNoToggle('Parking', Icons.local_parking_rounded, _hasParking,
            (v) => setState(() => _hasParking = v)),
        yesNoToggle('Ascenseur', Icons.elevator_rounded, _hasAscenseur,
            (v) => setState(() => _hasAscenseur = v)),
        yesNoToggle('Climatisation', Icons.ac_unit_rounded, _hasAirConditioning,
            (v) => setState(() => _hasAirConditioning = v)),
        yesNoToggle('Groupe Électrogène/Panneau Solaire', Icons.electric_bolt_rounded, _hasElectricity,
            (v) => setState(() => _hasElectricity = v)),
        yesNoToggle('Sécurité 24h/24', Icons.security_rounded, _hasWater,
            (v) => setState(() => _hasWater = v)),
        if (isLocationTx) ...[
          _garantieDropdown(),
          _commissionField(),
        ],
      ]);
    }

    // ── Propriété Commerciale & Industrielle ────────────────────────────────
    else if (type == 'Propriété Commerciale' ||
        type == 'Propriété Industrielle') {
      fields.addAll([
        _field(_surfaceCtrl, 'Superficie (m²) *', Icons.square_foot, '0',
            type: TextInputType.number),
        yesNoToggle('Parking', Icons.local_parking_rounded, _hasParking,
            (v) => setState(() => _hasParking = v)),
        yesNoToggle('Groupe Électrogène/Panneau Solaire', Icons.electric_bolt_rounded, _hasElectricity,
            (v) => setState(() => _hasElectricity = v)),
        yesNoToggle('Sécurité 24h/24', Icons.security_rounded, _hasWater,
            (v) => setState(() => _hasWater = v)),
        if (isLocationTx) ...[
          _garantieDropdown(),
          _commissionField(),
        ],
      ]);
    }

    // ── Terrain à bâtir — longueur × largeur ─────────────────────────────────
    else if (type == 'Terrain à bâtir') {
      fields.addAll([
        _dimensionsTerrainField(),
        yesNoToggle('Groupe Électrogène/Panneau Solaire', Icons.electric_bolt_rounded,
            _hasElectricity, (v) => setState(() => _hasElectricity = v)),
        yesNoToggle('Clôture', Icons.fence_rounded, _hasWater,
            (v) => setState(() => _hasWater = v)),
      ]);
    }

    // ── Concession — superficie en ha ─────────────────────────────────────────
    else if (type == 'Concession') {
      fields.addAll([
        _field(_hectaresCtrl, 'Superficie (ha) *', Icons.landscape_outlined, '0',
            type: TextInputType.number,
            suffix: const Text('ha',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    color: AppTheme.accentColor, fontSize: 13))),
        yesNoToggle('Groupe Électrogène/Panneau Solaire', Icons.electric_bolt_rounded,
            _hasElectricity, (v) => setState(() => _hasElectricity = v)),
        yesNoToggle('Sécurité 24h/24', Icons.security_rounded, _hasWater,
            (v) => setState(() => _hasWater = v)),
      ]);
    }

    // ── Chambre d'hôtel ─────────────────────────────────────────────────────
    else if (type == 'Chambre d\'hôtel') {
      fields.addAll([
        _field(_numberOfBedsCtrl, 'Nombre de lits', Icons.single_bed_rounded,
            '1',
            type: TextInputType.number),
        _field(_pricePerNightCtrl, 'Prix par nuit (USD)',
            Icons.nights_stay_outlined, '0',
            type: TextInputType.number),
        yesNoToggle('Climatisation', Icons.ac_unit_rounded, _hasAirConditioning,
            (v) => setState(() => _hasAirConditioning = v)),
        yesNoToggle('Petit-déjeuner inclus', Icons.free_breakfast_outlined,
            _hasBreakfast, (v) => setState(() => _hasBreakfast = v)),
        yesNoToggle('Groupe Électrogène/Panneau Solaire', Icons.electric_bolt_rounded, _hasElectricity,
            (v) => setState(() => _hasElectricity = v)),
        yesNoToggle('Sécurité 24h/24', Icons.security_rounded, _hasWater,
            (v) => setState(() => _hasWater = v)),
      ]);
    }

    // ── Salle de Fêtes / Espace Funéraire / Salle Polyvalente ───────────────
    else if (type == 'Salle de Fêtes' ||
        type == 'Espace Funéraire' ||
        type == 'Salle Polyvalente') {
      fields.addAll([
        _field(_capacityCtrl, 'Capacité (personnes)', Icons.event_seat_rounded,
            '100',
            type: TextInputType.number),
        _field(_surfaceCtrl, 'Superficie (m²) — optionnel', Icons.square_foot, '',
            type: TextInputType.number),
        _field(_pricePerDayCtrl, 'Prix par jour (USD)',
            Icons.calendar_today_outlined, '0',
            type: TextInputType.number),
        yesNoToggle('Parking', Icons.local_parking_rounded, _hasParking,
            (v) => setState(() => _hasParking = v)),
        yesNoToggle('Groupe Électrogène/Panneau Solaire', Icons.electric_bolt_rounded, _hasElectricity,
            (v) => setState(() => _hasElectricity = v)),
        yesNoToggle('Sécurité 24h/24', Icons.security_rounded, _hasWater,
            (v) => setState(() => _hasWater = v)),
      ]);
    }

    if (fields.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.tune_rounded, color: AppTheme.accentColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Caractéristiques — $_selectedType',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.accentColor),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        ...fields,
      ],
    );
  }

  // ── Widget dimensions Terrain à bâtir (longueur × largeur) ──────────────
  Widget _dimensionsTerrainField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Dimensions du terrain *',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        Row(children: [
          // Longueur
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Row(children: [
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Icon(Icons.straighten, color: AppTheme.accentColor, size: 18),
                ),
                Expanded(
                  child: TextField(
                    controller: _longueurCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Longueur',
                      hintStyle: TextStyle(fontFamily: 'Poppins',
                          color: AppTheme.textHint, fontSize: 12),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Text('m', style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, color: AppTheme.accentColor, fontSize: 13)),
                ),
              ]),
            ),
          ),
          // Séparateur ×
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('×', style: TextStyle(fontFamily: 'Poppins',
                fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
          ),
          // Largeur
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Row(children: [
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Icon(Icons.straighten, color: AppTheme.accentColor, size: 18),
                ),
                Expanded(
                  child: TextField(
                    controller: _largeurCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Largeur',
                      hintStyle: TextStyle(fontFamily: 'Poppins',
                          color: AppTheme.textHint, fontSize: 12),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Text('m', style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, color: AppTheme.accentColor, fontSize: 13)),
                ),
              ]),
            ),
          ),
        ]),
        // Aperçu dynamique ex: "20m sur 30m"
        if (_longueurCtrl.text.trim().isNotEmpty || _largeurCtrl.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Affichage : ${_longueurCtrl.text.trim().isNotEmpty ? _longueurCtrl.text.trim() : "?"}m sur ${_largeurCtrl.text.trim().isNotEmpty ? _largeurCtrl.text.trim() : "?"}m',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: AppTheme.accentColor, fontStyle: FontStyle.italic),
            ),
          ),
      ]),
    );
  }

  // ── Widget champ WhatsApp avec selecteur indicatif ────────────────────────
  Widget _whatsAppField() {
    final selectedCountryData = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _waCountryCode,
      orElse: () => AppConstants.countryCodes.first,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Numero WhatsApp *',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(children: [
            // Selecteur d'indicatif
            GestureDetector(
              onTap: () => _showCountryCodePicker(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: AppTheme.dividerColor)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(selectedCountryData['flag'] ?? '',
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(_waCountryCode,
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700, fontSize: 13,
                          color: AppTheme.accentColor)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, color: AppTheme.accentColor, size: 18),
                ]),
              ),
            ),
            // Saisie des 9 chiffres
            Expanded(
              child: TextField(
                controller: _waNumberCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 9,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '9 chiffres (ex: 812345678)',
                  hintStyle: TextStyle(fontFamily: 'Poppins',
                      color: AppTheme.textHint, fontSize: 12),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  void _showCountryCodePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.90,
        minChildSize: 0.40,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Selectionnez un indicatif',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 16,
                      color: AppTheme.textPrimary)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: AppConstants.countryCodes.length,
                itemBuilder: (_, i) {
                  final c = AppConstants.countryCodes[i];
                  final isSelected = c['code'] == _waCountryCode;
                  return ListTile(
                    onTap: () {
                      setState(() => _waCountryCode = c['code']!);
                      Navigator.pop(context);
                    },
                    leading: Text(c['flag'] ?? '',
                        style: const TextStyle(fontSize: 24)),
                    title: Text(c['country'] ?? '',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                            fontSize: 14,
                            color: isSelected ? AppTheme.accentColor : AppTheme.textPrimary)),
                    trailing: Text(c['code'] ?? '',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700, fontSize: 13,
                            color: isSelected ? AppTheme.accentColor : AppTheme.textSecondary)),
                    tileColor: isSelected
                        ? AppTheme.accentColor.withValues(alpha: 0.06)
                        : null,
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Sélecteur Garantie (0-12 mois) ──────────────────────────────────────
  Widget _garantieDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(children: [
          const Icon(Icons.security_rounded, color: AppTheme.accentColor, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Garantie (mois)',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: AppTheme.textPrimary)),
          ),
          DropdownButton<int>(
            value: _garantieMois,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppTheme.accentColor, fontWeight: FontWeight.w700),
            items: List.generate(13, (i) => DropdownMenuItem(
              value: i,
              child: Text(i == 0 ? 'Aucune' : '$i mois',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 13,
                    color: i == 0 ? AppTheme.textHint : AppTheme.accentColor,
                    fontWeight: i == _garantieMois ? FontWeight.w700 : FontWeight.w400,
                  )),
            )),
            onChanged: (v) => setState(() => _garantieMois = v ?? 0),
          ),
        ]),
      ),
    );
  }

  // ── Champ Commission (Oui/Non + %) ────────────────────────────────────────
  Widget _commissionField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(children: [
        // Toggle Commission Oui/Non
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft: Radius.circular(_hasCommission ? 0 : 10),
              bottomRight: Radius.circular(_hasCommission ? 0 : 10),
            ),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(children: [
            const Icon(Icons.handshake_rounded, color: AppTheme.accentColor, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Commission',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      color: AppTheme.textPrimary)),
            ),
            GestureDetector(
              onTap: () => setState(() => _hasCommission = false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: !_hasCommission ? AppTheme.errorColor : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                  border: Border.all(color: !_hasCommission ? AppTheme.errorColor : AppTheme.dividerColor),
                ),
                child: Text('Non',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: !_hasCommission ? Colors.white : AppTheme.textHint)),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _hasCommission = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _hasCommission ? AppTheme.successColor : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                  border: Border.all(color: _hasCommission ? AppTheme.successColor : AppTheme.dividerColor),
                ),
                child: Text('Oui',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _hasCommission ? Colors.white : AppTheme.textHint)),
              ),
            ),
          ]),
        ),
        // Champ % — visible & actif si Oui, grisé si Non
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _hasCommission ? Colors.white : Colors.grey.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            border: Border(
              left: BorderSide(color: AppTheme.dividerColor),
              right: BorderSide(color: AppTheme.dividerColor),
              bottom: BorderSide(color: AppTheme.dividerColor),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _commissionPctCtrl,
                  enabled: _hasCommission,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 13,
                    color: _hasCommission ? AppTheme.textPrimary : AppTheme.textHint,
                  ),
                  decoration: InputDecoration(
                    hintText: _hasCommission
                        ? 'Taux de commission (0 – 100 %)'
                        : 'Aucune commission',
                    hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        color: AppTheme.textHint.withValues(alpha: _hasCommission ? 1.0 : 0.5)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              Text('%',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _hasCommission ? AppTheme.accentColor : AppTheme.textHint.withValues(alpha: 0.4))),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Selecteur de pays (dropdown) ──────────────────────────────────────────
  Widget _countryDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: DropdownButtonFormField<String>(
        value: _selectedCountry,
        decoration: InputDecoration(
          labelText: 'Pays *',
          prefixIcon: const Icon(Icons.public, color: AppTheme.accentColor, size: 18),
          filled: true, fillColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.dividerColor)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.dividerColor)),
        ),
        items: AppConstants.countries.map((c) => DropdownMenuItem(
          value: c,
          child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        )).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _selectedCountry  = v;
              // Reset devise selon le pays
              _selectedCurrency = v == 'Congo (RDC)' ? 'CDF'
                  : v == 'Congo (Brazzaville)' ? 'XAF' : 'USD';
              final prov = AppConstants.getProvincesForCountry(v);
              _selectedProvince = prov.isNotEmpty ? prov.first : '';
              final cits = AppConstants.getCitiesForProvince(v, _selectedProvince);
              _selectedCity     = cits.isNotEmpty ? cits.first : '';
              final communes    = AppConstants.getCommunesForCity(_selectedCity);
              _selectedCommune  = communes.isNotEmpty ? communes.first : '';
            });
          }
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ETAPE 2 — Photos du bien (min 4)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepHeader('Etape 2', 'Photos du bien (minimum 4)', Icons.photo_library_rounded),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: AppTheme.accentColor, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Ajoutez au moins 4 photos claires de votre bien. Des photos de qualite augmentent vos chances de vente.',
              style: TextStyle(fontSize: 12, fontFamily: 'Poppins', color: AppTheme.accentColor),
            )),
          ]),
        ),
        const SizedBox(height: 20),

        // Boutons d'import local (Galerie + Camera)
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _pickLocalImages,
              icon: const Icon(Icons.photo_library_outlined, size: 18, color: Colors.white),
              label: const Text('Galerie', style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: AppTheme.accentColor, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: kIsWeb ? null : _pickCameraImage,
              icon: Icon(Icons.camera_alt_outlined, size: 18,
                  color: kIsWeb ? Colors.white38 : Colors.white),
              label: Text('Camera', style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  color: kIsWeb ? Colors.white38 : Colors.white, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // Separateur OU
        Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('OU par URL', style: TextStyle(fontFamily: 'Poppins',
                fontSize: 11, color: AppTheme.textHint)),
          ),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: 12),

        // Saisie URL d'image
        Row(children: [
          Expanded(
            child: TextField(
              controller: _imageUrlCtrl,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'URL de l\'image...',
                hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint),
                prefixIcon: const Icon(Icons.link, color: AppTheme.accentColor, size: 18),
                filled: true, fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.dividerColor)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () {
              final url = _imageUrlCtrl.text.trim();
              if (url.isNotEmpty && !_imageUrls.contains(url)) {
                setState(() { _imageUrls.add(url); _imageUrlCtrl.clear(); });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ]),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _addSampleImages,
          icon: const Icon(Icons.auto_fix_high, size: 16, color: AppTheme.accentColor),
          label: const Text('Utiliser des exemples (test)',
              style: TextStyle(fontSize: 12, fontFamily: 'Poppins', color: AppTheme.accentColor)),
        ),
        const SizedBox(height: 16),

        // Afficher les images locales
        if (_localImages.isNotEmpty) ...[
          const Text('Photos importees localement :',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1,
            ),
            itemCount: _localImages.length,
            itemBuilder: (_, i) => Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: kIsWeb
                      ? Container(color: AppTheme.accentColor.withValues(alpha: 0.1),
                          child: const Icon(Icons.image, color: AppTheme.accentColor))
                      : Image.file(File(_localImages[i].path), fit: BoxFit.cover),
                ),
                Positioned(top: 2, right: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _localImages.removeAt(i)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 10),
                    ),
                  ),
                ),
                if (i == 0 && _imageUrls.isEmpty)
                  Positioned(bottom: 2, left: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(4)),
                      child: const Text('Principale', style: TextStyle(color: Colors.white, fontSize: 7,
                          fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Afficher les images par URL
        if (_imageUrls.isEmpty && _localImages.isEmpty)
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined, size: 36, color: AppTheme.accentColor),
                SizedBox(height: 6),
                Text('Aucune photo ajoutee', style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textSecondary)),
              ],
            )),
          )
        else if (_imageUrls.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.4,
            ),
            itemCount: _imageUrls.length,
            itemBuilder: (_, i) => Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(_imageUrls[i], fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      child: const Icon(Icons.broken_image, color: AppTheme.accentColor),
                    ),
                  ),
                ),
                Positioned(
                  top: 4, right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _imageUrls.removeAt(i)),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: AppTheme.errorColor, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 12),
                    ),
                  ),
                ),
                if (i == 0)
                  Positioned(
                    bottom: 4, left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Photo principale',
                          style: TextStyle(color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Builder(builder: (ctx) {
          final total = _imageUrls.length + _localImages.length;
          return Row(children: [
            Icon(total >= 4 ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18, color: total >= 4 ? AppTheme.successColor : AppTheme.textHint),
            const SizedBox(width: 8),
            Text('$total/4 photos minimum (${_localImages.length} locale(s), ${_imageUrls.length} URL)',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: total >= 4 ? AppTheme.successColor : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                )),
          ]);
        }),
        const SizedBox(height: 28),
        _navButtons(
          onNext: () { if (_validateStep2()) _goTo(2); },
          onBack: () => _goTo(0),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }

  Future<void> _pickLocalImages() async {
    try {
      final List<XFile> picked = await _picker.pickMultiImage(
        imageQuality: 40,   // compression agressive pour rester sous 1MB Firestore
        maxWidth: 1024,     // max 1024px de large
        maxHeight: 1024,
        limit: 5,           // max 5 photos
      );
      if (picked.isNotEmpty) {
        setState(() {
          for (final img in picked) {
            if (!_localImages.any((e) => e.path == img.path)) {
              _localImages.add(img);
            }
          }
        });
      }
    } catch (e) {
      _err('Impossible d\'ouvrir la galerie: $e');
    }
  }

  Future<void> _pickCameraImage() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 40,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (photo != null) {
        setState(() => _localImages.add(photo));
      }
    } catch (e) {
      _err('Impossible d\'ouvrir la camera: $e');
    }
  }

  void _addSampleImages() {
    setState(() {
      _imageUrls.clear();
      _imageUrls.addAll([
        'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=800',
        'https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=800',
        'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=800',
        'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800',
        'https://images.unsplash.com/photo-1613490493576-7fde63acd811?w=800',
      ]);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ETAPE 3 — Crédits / Paiement (intelligent)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStep3() {
    final ds      = DataService();
    final packs   = ds.subscriptionPacks.where((p) => p['active'] == true).toList();
    final methods = ds.paymentMethods.where((m) => m['active'] == true).toList();

    // Trigger credit check when entering this step
    if (!_creditChecked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkUserCredits());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepHeader('Etape 3', 'Crédits & Paiement', Icons.toll_outlined),
        const SizedBox(height: 16),

        if (!_creditChecked)
          // Loading
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: const Row(children: [
              SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor)),
              SizedBox(width: 12),
              Text('Vérification de votre solde...',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      color: AppTheme.textSecondary)),
            ]),
          )
        else ...
          _buildCreditStatus(packs, methods),

        const SizedBox(height: 28),

        // ── Navigation buttons ─────────────────────────────────────────────────
        // CAS 1 : Solde suffisant → Continuer normal
        if (_creditChecked && _hasEnoughCredits)
          _navButtons(
            onNext: () { if (_validateStep3()) _goTo(3); },
            onBack: () => _goTo(1),
          )

        // CAS 2 : Paiement soumis, en attente admin → seul bouton Retour
        else if (_creditChecked && !_hasEnoughCredits && _paymentSubmitted)
          _backButton()

        // CAS 3 : Solde insuffisant, pas encore soumis → seul bouton Retour
        else if (_creditChecked && !_hasEnoughCredits)
          _backButton(),

        const SizedBox(height: 30),
      ]),
    );
  }

  List<Widget> _buildCreditStatus(
      List<Map<String, dynamic>> packs, List<Map<String, dynamic>> methods) {
    final costUsd = (_requiredCredits * 0.1).toStringAsFixed(2);

    // ── Détermine l'affichage du solde selon le TYPE de droit ─────────────────
    // free_trial  → badge "Mode gratuit actif"
    // free_quota  → badge "1 publication gratuite ce mois"  (PAS "0 crédits ✅")
    // paid_credit → solde en crédits payants
    // no_right    → 0 crédit ❌

    final bool isFreeRight = _publicationRight == 'free_trial' || _publicationRight == 'free_quota';

    // Texte + couleur du bloc "Votre solde"
    String balanceLabel;
    Color balanceColor;
    IconData balanceIcon;

    switch (_publicationRight) {
      case 'free_trial':
        balanceLabel = 'Mode gratuit';
        balanceColor = AppTheme.successColor;
        balanceIcon  = Icons.free_breakfast;
        break;
      case 'free_quota':
        balanceLabel = '$_freeQuotaAvailable pub. gratuite${_freeQuotaAvailable > 1 ? 's' : ''}';
        balanceColor = AppTheme.successColor;
        balanceIcon  = Icons.card_giftcard;
        break;
      case 'paid_credit':
        balanceLabel = '$_userAvailableCredits crédit${_userAvailableCredits != 1 ? 's' : ''}';
        balanceColor = AppTheme.successColor;
        balanceIcon  = Icons.check_circle;
        break;
      default: // no_right
        balanceLabel = '$_userAvailableCredits crédit${_userAvailableCredits != 1 ? 's' : ''}';
        balanceColor = AppTheme.errorColor;
        balanceIcon  = Icons.warning_rounded;
    }

    // ── Header: commune + coût + solde ──────────────────────────────────────────
    final headerCard = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.6)),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.location_on, color: AppTheme.accentColor, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Publication dans : $_selectedCommune${_selectedCity.isNotEmpty ? ", $_selectedCity" : ""}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w600, color: Colors.white),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          // Bloc "Requis" — affiché uniquement si paiement par crédit nécessaire
          if (!isFreeRight) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  const Text('Requis', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 10, color: Colors.white70)),
                  const SizedBox(height: 2),
                  Text('$_requiredCredits crédit${_requiredCredits > 1 ? 's' : ''}',
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                  Text('≈ \$$costUsd', style: const TextStyle(fontFamily: 'Poppins',
                      fontSize: 11, color: Colors.white70)),
                ]),
              ),
            ),
            const SizedBox(width: 10),
          ],
          // Bloc "Votre solde / droit"
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: balanceColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: balanceColor.withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                Text(
                  isFreeRight ? 'Votre droit' : 'Votre solde',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontSize: 10, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(balanceLabel,
                    style: TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800, fontSize: 15,
                        color: balanceColor),
                    textAlign: TextAlign.center),
                const SizedBox(height: 2),
                Icon(balanceIcon, size: 14, color: balanceColor),
              ]),
            ),
          ),
        ]),
      ]),
    );

    // ══════════════════════════════════════════════════════════════════
    // CAS 1 — FREE TRIAL : publication illimitée gratuite
    // ══════════════════════════════════════════════════════════════════
    if (_publicationRight == 'free_trial') {
      return [
        headerCard,
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.successColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.free_breakfast,
                  color: AppTheme.successColor, size: 28),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mode Free Trial actif !',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800, fontSize: 15,
                        color: AppTheme.successColor)),
                SizedBox(height: 4),
                Text(
                  'La publication est gratuite et illimitée pour tous les utilisateurs en ce moment.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: AppTheme.textSecondary, height: 1.4),
                ),
              ],
            )),
          ]),
        ),
      ];
    }

    // ══════════════════════════════════════════════════════════════════
    // CAS 2 — FREE QUOTA : 1 publication gratuite mensuelle disponible
    // ══════════════════════════════════════════════════════════════════
    if (_publicationRight == 'free_quota') {
      return [
        headerCard,
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.successColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.card_giftcard,
                  color: AppTheme.successColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_freeQuotaAvailable publication${_freeQuotaAvailable > 1 ? 's' : ''} gratuite${_freeQuotaAvailable > 1 ? 's' : ''} disponible${_freeQuotaAvailable > 1 ? 's' : ''}',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800, fontSize: 15,
                      color: AppTheme.successColor),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vous bénéficiez de $_freeQuotaAvailable publication${_freeQuotaAvailable > 1 ? 's' : ''} gratuite${_freeQuotaAvailable > 1 ? 's' : ''}. Elle${_freeQuotaAvailable > 1 ? 's' : ''} sera${_freeQuotaAvailable > 1 ? 'ont' : ''} utilisée${_freeQuotaAvailable > 1 ? 's' : ''} pour vos prochaines annonces.',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: AppTheme.textSecondary, height: 1.4),
                ),
              ],
            )),
          ]),
        ),
      ];
    }

    // ══════════════════════════════════════════════════════════════════
    // CAS 3 — PAID CREDIT : crédits payants suffisants
    // ══════════════════════════════════════════════════════════════════
    if (_publicationRight == 'paid_credit') {
      return [
        headerCard,
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.successColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppTheme.successColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Solde suffisant !',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800, fontSize: 15,
                        color: AppTheme.successColor)),
                const SizedBox(height: 4),
                Text(
                  '$_userAvailableCredits crédit${_userAvailableCredits != 1 ? 's' : ''} disponible${_userAvailableCredits != 1 ? 's' : ''}. $_requiredCredits crédit${_requiredCredits != 1 ? 's' : ''} sera débité à la soumission.',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: AppTheme.textSecondary, height: 1.4),
                ),
              ],
            )),
          ]),
        ),
      ];
    }

    // ══════════════════════════════════════════════════════════════════
    // CAS 4 — NO RIGHT : solde insuffisant
    // ══════════════════════════════════════════════════════════════════

    // Sous-cas 4a : paiement déjà soumis, en attente admin
    if (_paymentSubmitted) {
      return [
        headerCard,
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.warningColor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded,
                    color: AppTheme.warningColor, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Demande envoyée — en attente de validation',
                      style: TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800, fontSize: 14,
                          color: AppTheme.warningColor)),
                  SizedBox(height: 3),
                  Text('L\'administrateur va vérifier et approuver votre paiement.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          color: AppTheme.textSecondary)),
                ],
              )),
            ]),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _waitingStepRow(Icons.check_circle_outline, AppTheme.successColor,
                'Paiement soumis',
                'Votre référence de transaction a été enregistrée.'),
            const SizedBox(height: 10),
            _waitingStepRow(Icons.admin_panel_settings, AppTheme.warningColor,
                'Validation admin en cours',
                'L\'administrateur vérifie et approuve votre paiement.'),
            const SizedBox(height: 10),
            _waitingStepRow(Icons.toll_outlined, AppTheme.textHint,
                'Crédits ajoutés automatiquement',
                'Dès approbation, vos crédits sont crédités et le bouton "Continuer" se débloque.'),
          ]),
        ),
      ];
    }

    // Sous-cas 4b : solde insuffisant, formulaire de recharge à afficher
    return [
      headerCard,
      const SizedBox(height: 16),
      // Alerte rouge claire
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: AppTheme.errorColor, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Solde insuffisant',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 14,
                      color: AppTheme.errorColor)),
              const SizedBox(height: 4),
              Text(
                'Vous avez $_userAvailableCredits crédit${_userAvailableCredits != 1 ? 's' : ''} et il vous faut $_requiredCredits crédit${_requiredCredits != 1 ? 's' : ''}. Rechargez ci-dessous.',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.textSecondary, height: 1.4),
              ),
            ],
          )),
        ]),
      ),
      const SizedBox(height: 20),

      // ── ETAPE A : Choisir le pack ─────────────────────────────────────
      _stepBadge('1', 'Choisissez une recharge de crédits'),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.accentColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '10 USD = 100 crédits — les crédits restants sont conservés pour vos prochaines annonces.',
          style: TextStyle(fontSize: 11, fontFamily: 'Poppins',
              color: AppTheme.accentColor, height: 1.4),
        ),
      ),
      const SizedBox(height: 10),
      ...packs.map((pack) => _packTile(pack)),
      const SizedBox(height: 20),

      // ── ETAPE B : Choisir le moyen de paiement ──────────────────────
      _stepBadge('2', 'Effectuez le paiement Mobile Money'),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
        ),
        child: const Text(
          'Envoyez le montant au numéro correspondant, puis saisissez votre référence de transaction ci-dessous.',
          style: TextStyle(fontSize: 12, fontFamily: 'Poppins',
              color: AppTheme.textSecondary, height: 1.5),
        ),
      ),
      const SizedBox(height: 12),
      ...methods.map((m) => _paymentMethodTile(m)),
      const SizedBox(height: 20),

      // ── ETAPE C : Référence + Soumettre ────────────────────────────
      _stepBadge('3', 'Saisissez votre référence de paiement'),
      const SizedBox(height: 10),
      _field(_transactionRefCtrl, 'Référence / Code de transaction *',
          Icons.receipt_long_outlined, 'Ex: TXN123456789'),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _submittingPayment ? null : _submitPaymentRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: _submittingPayment
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
          label: Text(
            _submittingPayment ? 'Envoi en cours...' : 'Soumettre ma demande de recharge',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Après soumission, l\'administrateur validera votre paiement et ajoutera vos crédits. Le bouton "Continuer" sera alors débloqué.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
            color: AppTheme.textHint, height: 1.4),
        textAlign: TextAlign.center,
      ),
    ];
  }

  // Helper: ligne étape d'attente après soumission paiement
  Widget _waitingStepRow(IconData icon, Color color, String title, String subtitle) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
            fontWeight: FontWeight.w700, color: color)),
        Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
            color: AppTheme.textSecondary, height: 1.4)),
      ])),
    ]);
  }

  // Badge numéroté pour les sous-étapes du formulaire de paiement
  Widget _stepBadge(String number, String label) {
    return Row(children: [
      Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: AppTheme.accentColor,
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(number,
            style: const TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white))),
      ),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontFamily: 'Poppins',
          fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
    ]);
  }

  Widget _packTile(Map<String, dynamic> pack) {
    final isSelected = _selectedPack?['id'] == pack['id'];
    final qty = (pack['qty'] as num?)?.toInt() ?? 0;
    final price = (pack['price'] as num?)?.toDouble() ?? 0.0;
    final credits = (qty > 0) ? qty : (price * DataService.creditsPerDollar).round();
    final isCredits = pack['type'] == 'credits';
    final desc = pack['description'] as String?;
    return GestureDetector(
      onTap: () => setState(() => _selectedPack = pack),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: isSelected ? 0.25 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCredits ? Icons.toll_outlined : Icons.inventory_2_outlined,
              color: AppTheme.accentColor, size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pack['name'] ?? '', style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
              color: isSelected ? Colors.white : AppTheme.textPrimary,
            )),
            if (isCredits)
              Text('$credits crédits — 10\$ = 100 crédits', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                color: isSelected ? Colors.white70 : AppTheme.accentColor,
                fontWeight: FontWeight.w600,
              ))
            else if (qty > 0)
              Text('$qty crédit(s)', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                color: isSelected ? Colors.white70 : AppTheme.textSecondary,
              )),
            if (desc != null)
              Text(desc, style: TextStyle(
                fontFamily: 'Poppins', fontSize: 10,
                color: isSelected ? Colors.white54 : AppTheme.textHint,
              )),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.accentColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '\$${price.toStringAsFixed(2)} ${pack['currency'] ?? 'USD'}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isSelected ? AppTheme.accentColor : AppTheme.textHint, size: 22,
          ),
        ]),
      ),
    );
  }

  Widget _paymentMethodTile(Map<String, dynamic> m) {
    final isSelected = _selectedPaymentMethod?['id'] == m['id'];
    return GestureDetector(
      onTap: () => setState(() => _selectedPaymentMethod = m),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          _operatorLogoWidget(m['icon'] ?? 'other', size: 52),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m['name'] ?? '', style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
              color: AppTheme.textPrimary,
            )),
            Text(m['number'] ?? '', style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800,
              color: AppTheme.accentColor, letterSpacing: 0.5,
            )),
          ])),
          Icon(
            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isSelected ? AppTheme.accentColor : AppTheme.textHint, size: 22,
          ),
        ]),
      ),
    );
  }

  Widget _operatorLogoWidget(String type, {double size = 44}) {
    final logos = <String, String>{
      'mpesa':  'https://upload.wikimedia.org/wikipedia/commons/thumb/1/15/M-PESA_LOGO-01.svg/320px-M-PESA_LOGO-01.svg.png',
      'orange': 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Orange_logo.svg/240px-Orange_logo.svg.png',
      'airtel': 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/Airtel_Africa_logo.svg/320px-Airtel_Africa_logo.svg.png',
    };
    final colors = <String, Color>{
      'mpesa':  const Color(0xFF00A651),
      'orange': const Color(0xFFFF7900),
      'airtel': const Color(0xFFE40000),
    };
    final url   = logos[type];
    final color = colors[type] ?? AppTheme.accentColor;
    if (url != null) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 6)],
        ),
        padding: const EdgeInsets.all(5),
        child: Image.network(url, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(Icons.payment, color: color, size: size * 0.5)),
      );
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.payment, color: color, size: size * 0.5),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ETAPE 4 — Envoi de l'annonce
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStep4() {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final displayName  = _nomCtrl.text.isNotEmpty ? _nomCtrl.text : (user?.name ?? '');
    final displayEmail = _emailCtrl.text.isNotEmpty ? _emailCtrl.text : (user?.email ?? '');
    final displayWa    = _waNumberCtrl.text.isNotEmpty
        ? _fullWhatsApp
        : (user?.phone ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepHeader('Etape 4', 'Recapitulatif & Envoi', Icons.send_rounded),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _recapRow('Annonceur',   displayName,        Icons.person_outline),
            _recapRow('WhatsApp',    displayWa,          Icons.phone),
            _recapRow('Email',       displayEmail,       Icons.email_outlined),
            const Divider(height: 20),
            _recapRow('Type',        _selectedType,      Icons.home_outlined),
            _recapRow('Transaction', _selectedTransaction, Icons.swap_horiz),
            _recapRow('Pays',        _selectedCountry,   Icons.public),
            _recapRow('Ville',       _selectedCity,      Icons.location_city),
            _recapRow('Commune',     _selectedCommune,   Icons.map_outlined),
            if (_quartierCtrl.text.isNotEmpty)
              _recapRow('Quartier',    _quartierCtrl.text, Icons.holiday_village_outlined),
            const Divider(height: 20),
            _recapRow('Photos', '${_imageUrls.length + _localImages.length} photo(s)', Icons.photo_library_outlined),
            if (_hasEnoughCredits) ...[
              _recapRow('Paiement', 'Crédits disponibles ($_userAvailableCredits)', Icons.toll_outlined),
              _recapRow('Coût', '$_requiredCredits crédit(s) débité(s)', Icons.check_circle_outline),
            ] else ...[
              _recapRow('Pack',      _selectedPack?['name'] ?? '—', Icons.inventory_2_outlined),
              _recapRow('Paiement',  _selectedPaymentMethod?['name'] ?? '—', Icons.payment),
              _recapRow('Référence', _transactionRefCtrl.text, Icons.receipt_long_outlined),
            ],
          ]),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.warningColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: AppTheme.warningColor, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Votre annonce sera examinee par l\'equipe ImmoZone. Apres validation de votre paiement, elle sera publiee en environ 1h.',
              style: TextStyle(fontSize: 12, fontFamily: 'Poppins',
                  color: AppTheme.warningColor, height: 1.5),
            )),
          ]),
        ),
        const SizedBox(height: 28),

        _navButtons(
          nextLabel: 'Soumettre l\'annonce',
          nextIcon: Icons.send_rounded,
          onNext: _submitAnnonce,
          onBack: () => _goTo(2),
          isLoading: _submitting,
        ),
        const SizedBox(height: 30),
      ]),
    );
  }

  Widget _recapRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: AppTheme.accentColor),
        const SizedBox(width: 10),
        SizedBox(width: 90, child: Text('$label :', style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ))),
        Expanded(child: Text(value, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textPrimary,
          fontWeight: FontWeight.w500,
        ), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ETAPE 5 — Confirmation
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStep5() {
    // _submitted used implicitly to confirm submission
    assert(_submitted || !_submitted); // suppress lint
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentColor.withValues(alpha: 0.12),
              border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.4), width: 2),
            ),
            child: const Icon(Icons.check_circle_rounded, color: AppTheme.accentColor, size: 72),
          ),
          const SizedBox(height: 28),
          const Text('Annonce soumise avec succes !',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                fontFamily: 'Poppins', color: AppTheme.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
            ),
            child: const Column(children: [
              _ConfirmStep(
                icon: Icons.send_rounded, color: AppTheme.accentColor,
                title: 'Annonce recue', isDone: true,
                desc: 'Votre annonce a ete transmise a l\'equipe ImmoZone.',
              ),
              SizedBox(height: 12),
              _ConfirmStep(
                icon: Icons.payment_rounded, color: AppTheme.warningColor,
                title: 'Verification du paiement', isDone: false,
                desc: 'Nous verifions votre paiement Mobile Money (~1h).',
              ),
              SizedBox(height: 12),
              _ConfirmStep(
                icon: Icons.fact_check_rounded, color: AppTheme.primaryLight,
                title: 'Moderation de l\'annonce', isDone: false,
                desc: 'Notre equipe examine les photos et informations.',
              ),
              SizedBox(height: 12),
              _ConfirmStep(
                icon: Icons.verified_rounded, color: AppTheme.successColor,
                title: 'Publication', isDone: false,
                desc: 'Votre annonce sera visible sur ImmoZone.',
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
            ),
            child: const Row(children: [
              Icon(Icons.notifications_active_outlined, color: AppTheme.accentColor, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text(
                'Vous serez notifie(e) par email et WhatsApp des que votre annonce sera approuvee.',
                style: TextStyle(fontSize: 12, fontFamily: 'Poppins',
                    color: AppTheme.textSecondary, height: 1.5),
              )),
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.accentColor, width: 1.5),
                ),
              ),
              icon: const Icon(Icons.home_rounded, color: AppTheme.accentColor),
              label: const Text('Retour a l\'accueil',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 15, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ── Widgets helpers ────────────────────────────────────────────────────────
  Widget _stepHeader(String step, String title, IconData icon) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentColor, width: 1.5),
        ),
        child: Icon(icon, color: AppTheme.accentColor, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(step, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 12, color: AppTheme.accentColor,
          fontWeight: FontWeight.w600,
        )),
        Text(title, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        )),
      ])),
    ]);
  }

  Widget _sectionLabel(String label) {
    return Text(label, style: const TextStyle(
      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
      fontSize: 13, color: AppTheme.textPrimary,
    ));
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, String hint, {
    TextInputType type = TextInputType.text, int maxLines = 1, Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppTheme.accentColor, size: 18),
          suffix: suffix,
          filled: true, fillColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary),
          hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint, fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.dividerColor)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.dividerColor)),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items,
      IconData icon, void Function(String?) onChanged) {
    final safeItems = items.isNotEmpty ? items : [value];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: safeItems.contains(value) ? value : safeItems.first,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppTheme.accentColor, size: 18),
          filled: true, fillColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.dividerColor)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.dividerColor)),
        ),
        items: safeItems.map((t) => DropdownMenuItem(
          value: t,
          child: Text(t, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        )).toList(),
        onChanged: onChanged,
      ),
    );
  }

  List<String> get _currencyOptions {
    final local = _localCurrency;
    final options = ['USD', 'EUR'];
    if (!options.contains(local)) options.add(local);
    return options;
  }

  Widget _currencyDropdown() {
    final safeValue = _currencyOptions.contains(_selectedCurrency)
        ? _selectedCurrency : _currencyOptions.first;
    return DropdownButton<String>(
      value: safeValue,
      underline: const SizedBox(),
      items: _currencyOptions.map((c) => DropdownMenuItem(
        value: c,
        child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
            fontWeight: FontWeight.w700, color: AppTheme.accentColor)),
      )).toList(),
      onChanged: (v) => setState(() => _selectedCurrency = v!),
    );
  }

  Widget _navButtons({
    required VoidCallback onNext,
    VoidCallback? onBack,
    bool showBack = true,
    String nextLabel = 'Continuer',
    IconData? nextIcon,
    bool isLoading = false,
  }) {
    return Row(children: [
      if (showBack && onBack != null) ...[
        Expanded(
          flex: 1,
          child: OutlinedButton.icon(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.dividerColor),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
            label: const Text('Retour', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(
        flex: 2,
        child: ElevatedButton.icon(
          onPressed: isLoading ? null : onNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.accentColor, width: 1.5),
            ),
          ),
          icon: isLoading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor))
              : Icon(nextIcon ?? Icons.arrow_forward_ios_rounded,
                  size: 16, color: AppTheme.accentColor),
          label: Text(nextLabel, style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
          )),
        ),
      ),
    ]);
  }

  // Bouton Retour seul (centré, pleine largeur)
  Widget _backButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _goTo(1),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          side: const BorderSide(color: AppTheme.dividerColor),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
        label: const Text('Retour', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// Widget de confirmation step
class _ConfirmStep extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final bool isDone;
  const _ConfirmStep({required this.icon, required this.color,
      required this.title, required this.desc, required this.isDone});
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDone ? 0.15 : 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isDone ? color : color.withValues(alpha: 0.5), size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: TextStyle(
            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
            color: isDone ? AppTheme.textPrimary : AppTheme.textSecondary,
          )),
          if (isDone) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check_circle, color: AppTheme.accentColor, size: 14),
          ],
        ]),
        Text(desc, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary, height: 1.4,
        )),
      ])),
    ]);
  }
}
