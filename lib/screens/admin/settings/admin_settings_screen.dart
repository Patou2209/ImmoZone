import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/data_service.dart';
import '../../../core/constants/app_constants.dart';
import '../contacts/admin_contacts_screen.dart';
import '../zones/admin_zones_screen.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _settings = {};
  late TabController _tabCtrl;


  // ── Packs ────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _packs = [];

  // ── Moyens de paiement ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> _paymentMethods = [];

  // ── Texte d'accueil (hero page d'accueil) ──────────────────────────────────
  late TextEditingController _homeTitleCtrl;
  late TextEditingController _homeSubtitleCtrl;
  bool _isSavingHomeText = false;

  // ── Message officiel ─────────────────────────────────────────────────────────
  late TextEditingController _officialMsgCtrl;

  // ── Contacts bouton Contact (WhatsApp + Téléphone + Email) ────────────────────
  late TextEditingController _waContactCtrl;
  late TextEditingController _phoneContactCtrl;
  late TextEditingController _emailContactCtrl;
  bool _isSavingWa = false;
  bool _isSavingPhone = false;
  bool _isSavingEmail = false;

  // ── Mode plateforme ──────────────────────────────────────────────────────────
  bool _isFreeTrial = false;

  // ── Quota de bienvenue (annonces gratuites pour nouveaux utilisateurs) ──────
  late TextEditingController _freeQuotaCountCtrl;   // nb d’annonces
  late TextEditingController _freeQuotaDaysCtrl;    // durée en jours
  // ignore: unused_field
  bool _isSavingQuota = false;

  // ── Promotions — annonces gratuites (admin push) ────────────────────────
  bool _isPromoActive = false;
  late TextEditingController _promoQtyCtrl;
  late TextEditingController _promoReasonCtrl;
  bool _isLaunchingPromo = false;

  // ── Promotions — ciblage par zone ────────────────────────────────────────
  // 0 = tous les utilisateurs, 1 = par zone
  int _promoScopeIndex = 0;
  String? _promoTargetCountry;
  String? _promoTargetCity;
  String? _promoTargetZone;

  // ── Promotions — paliers de recharge ─────────────────────────────────────
  bool _isTiersPromoActive = false;
  bool _isSavingTiers = false;
  List<Map<String, dynamic>> _tiers = [];
  final List<TextEditingController> _tierMinCtrl  = [];
  final List<TextEditingController> _tierMaxCtrl  = [];
  final List<TextEditingController> _tierPctCtrl  = [];
  final List<int> _tierFreeAds = [2, 3, 5];
  final List<String?> _tierTargetZone    = [null, null, null];

  // ── Zone partagée pour tous les paliers ──────────────────────────────────
  String? _sharedTierTargetCountry;
  String? _sharedTierTargetCity;
  String? _sharedTierTargetZone;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _initControllers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _initControllers() {
    _homeTitleCtrl      = TextEditingController();
    _homeSubtitleCtrl   = TextEditingController();
    _officialMsgCtrl    = TextEditingController();
    _waContactCtrl      = TextEditingController();
    _phoneContactCtrl   = TextEditingController();
    _emailContactCtrl   = TextEditingController();
    _promoQtyCtrl       = TextEditingController(text: '2');
    _promoReasonCtrl = TextEditingController(text: 'Promotion spéciale ImmoZone');
    _freeQuotaCountCtrl = TextEditingController(text: '3');
    _freeQuotaDaysCtrl  = TextEditingController(text: '30');
    for (int i = 0; i < 3; i++) {
      _tierMinCtrl.add(TextEditingController());
      _tierMaxCtrl.add(TextEditingController());
      _tierPctCtrl.add(TextEditingController());
    }

    // Live preview listeners for home text
    _homeTitleCtrl.addListener(() => setState(() {}));
    _homeSubtitleCtrl.addListener(() => setState(() {}));
    // Live preview listener for official message
    _officialMsgCtrl.addListener(() => setState(() {}));
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _settings         = _ds.systemSettings;
    _isFreeTrial      = _settings['free_trial_enabled'] == true;
    _freeQuotaCountCtrl.text = '${(_settings['free_quota_count'] as num?)?.toInt() ?? 3}';
    _freeQuotaDaysCtrl.text  = '${(_settings['free_quota_days']  as num?)?.toInt() ?? 30}';
    _isPromoActive    = _ds.isPromoActive;
    _isTiersPromoActive = _ds.isRechargeTiersPromoActive;
    _homeTitleCtrl.text    = _ds.homeTitle;
    _homeSubtitleCtrl.text  = _ds.homeSubtitle;
    _officialMsgCtrl.text   = _ds.officialMessage;
    _waContactCtrl.text     = _ds.whatsappContactNumber;
    _phoneContactCtrl.text  = _ds.phoneContactNumber;
    _emailContactCtrl.text  = _ds.emailContact;
    _packs          = List<Map<String, dynamic>>.from(_ds.subscriptionPacks);
    _paymentMethods = List<Map<String, dynamic>>.from(_ds.paymentMethods);
    final loadedTiers = await _ds.loadRechargeTiers();
    _tiers = List<Map<String, dynamic>>.from(loadedTiers);
    _initTierControllers();
    setState(() => _isLoading = false);
  }

  void _initTierControllers() {
    const defaultMin  = [20.0, 50.0, 100.0];
    const defaultMax  = [49.0, 99.0, -1.0];
    const defaultPct  = [10,   25,    50  ];
    const defaultFree = [2,    3,     5   ];
    for (int i = 0; i < 3; i++) {
      if (_tierMinCtrl.length <= i) continue;
      final t = i < _tiers.length ? _tiers[i] : <String, dynamic>{};
      _tierMinCtrl[i].text = ((t['minAmount'] as num?) ?? defaultMin[i]).toStringAsFixed(0);
      final mx = (t['maxAmount'] as num?)?.toDouble() ?? defaultMax[i];
      _tierMaxCtrl[i].text = mx < 0 ? '' : mx.toStringAsFixed(0);
      _tierPctCtrl[i].text = '${(t['bonusCreditPct'] as num?)?.toInt() ?? defaultPct[i]}';
      _tierFreeAds[i]      = (t['bonusFreeAds']    as num?)?.toInt() ?? defaultFree[i];
      _tierTargetZone[i]   =  t['targetZone']      as String?;
    }
    // Restaurer zone partagée depuis le premier palier (tous partagent la même)
    if (_tiers.isNotEmpty) {
      _sharedTierTargetCountry = _tiers[0]['targetCountry'] as String?;
      _sharedTierTargetCity    = _tiers[0]['targetCity']    as String?;
      _sharedTierTargetZone    = _tiers[0]['targetZone']    as String?;
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in [
        _homeTitleCtrl, _homeSubtitleCtrl,
        _officialMsgCtrl, _waContactCtrl, _phoneContactCtrl, _emailContactCtrl,
        _promoQtyCtrl, _promoReasonCtrl,
        _freeQuotaCountCtrl, _freeQuotaDaysCtrl,
        ..._tierMinCtrl, ..._tierMaxCtrl, ..._tierPctCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _savePlatformSettings() async {
    setState(() => _isSaving = true);
    final count = int.tryParse(_freeQuotaCountCtrl.text.trim()) ?? 3;
    final days  = int.tryParse(_freeQuotaDaysCtrl.text.trim())  ?? 30;
    await _ds.updateSettings({
      'free_trial_enabled': _isFreeTrial,
      'free_quota_count':   count.clamp(0, 99),
      'free_quota_days':    days.clamp(1, 365),
    });
    setState(() => _isSaving = false);
    _snackOk('✅ Paramètres plateforme sauvegardés');
  }

  Future<void> _savePacks() async {
    await _ds.saveSubscriptionPacks(_packs);
    _snackOk('✅ Packs sauvegardés');
  }

  Future<void> _savePaymentMethods() async {
    await _ds.savePaymentMethods(_paymentMethods);
    _snackOk('✅ Moyens de paiement sauvegardés');
  }

  Future<void> _saveHomeText() async {
    final title    = _homeTitleCtrl.text.trim();
    final subtitle = _homeSubtitleCtrl.text.trim();
    if (title.isEmpty) { _snackErr('Le titre d\'accueil ne peut pas être vide.'); return; }
    setState(() => _isSavingHomeText = true);
    await _ds.updateHomeText(title: title, subtitle: subtitle);
    if (mounted) {
      setState(() => _isSavingHomeText = false);
      _snackOk('✅ Texte d\'accueil sauvegardé');
    }
  }

  Future<void> _saveOfficialMessage() async {
    await _ds.saveOfficialMessage(_officialMsgCtrl.text.trim());
    _snackOk('✅ Message officiel sauvegardé');
  }

  Future<void> _saveWhatsappContact() async {
    final number = _waContactCtrl.text.trim();
    if (number.isEmpty) {
      _snackErr('Entrez un numéro WhatsApp valide.');
      return;
    }
    setState(() => _isSavingWa = true);
    await _ds.saveWhatsappContactNumber(number);
    setState(() => _isSavingWa = false);
    _snackOk('✅ Numéro WhatsApp Contact sauvegardé');
  }

  Future<void> _savePhoneContact() async {
    final number = _phoneContactCtrl.text.trim();
    if (number.isEmpty) {
      _snackErr('Entrez un numéro de téléphone valide.');
      return;
    }
    setState(() => _isSavingPhone = true);
    await _ds.savePhoneContactNumber(number);
    setState(() => _isSavingPhone = false);
    _snackOk('✅ Numéro de téléphone sauvegardé');
  }

  Future<void> _saveEmailContact() async {
    final email = _emailContactCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snackErr('Entrez une adresse email valide.');
      return;
    }
    setState(() => _isSavingEmail = true);
    await _ds.saveEmailContact(email);
    setState(() => _isSavingEmail = false);
    _snackOk('✅ Email de contact sauvegardé');
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

  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Paramètres', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFFFFA726),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFFA726),
          unselectedLabelColor: AppTheme.primaryColor,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 11),
          tabs: const [
            Tab(icon: Icon(Icons.tune_rounded, size: 16), text: 'Plateforme'),
            Tab(icon: Icon(Icons.inventory_2_outlined, size: 16), text: 'Packs'),
            Tab(icon: Icon(Icons.phone_android, size: 16), text: 'Paiements'),
            Tab(icon: Icon(Icons.map_outlined, size: 16), text: 'Zones'),
            Tab(icon: Icon(Icons.campaign_rounded, size: 16), text: 'Message'),
            Tab(icon: Icon(Icons.local_offer_rounded, size: 16), text: 'Promotions'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildPlatformTab(),
                _buildPacksTab(),
                _buildPaymentsTab(),
                _buildZonesTab(),
                _buildMessageTab(),
                _buildPromotionsTab(),
              ],
            ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ONGLET 1 — PLATEFORME (mode gratuit/payant + tarifs + durée validation)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildPlatformTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── MODE PLATEFORME ──────────────────────────────────────────────────
        _sectionHeader('Mode de la plateforme'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(children: [
            // Statut actuel
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _isFreeTrial
                    ? AppTheme.successColor.withValues(alpha: 0.1)
                    : AppTheme.accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isFreeTrial ? AppTheme.successColor : AppTheme.accentColor,
                  width: 1.5,
                ),
              ),
              child: Column(children: [
                Icon(
                  _isFreeTrial ? Icons.lock_open_rounded : Icons.lock_rounded,
                  color: _isFreeTrial ? AppTheme.successColor : AppTheme.accentColor,
                  size: 32,
                ),
                const SizedBox(height: 6),
                Text(
                  _isFreeTrial ? 'MODE GRATUIT ACTIVÉ' : 'MODE PAYANT ACTIVÉ',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 14,
                    color: _isFreeTrial ? AppTheme.successColor : AppTheme.accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isFreeTrial
                      ? 'Toutes les publications sont gratuites et illimitées'
                      : 'Les utilisateurs doivent payer pour publier',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Boutons basculement
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isFreeTrial ? null : () => _confirmModeChange(true),
                  icon: Icon(Icons.lock_open_rounded, size: 16,
                      color: _isFreeTrial ? Colors.white54 : Colors.white),
                  label: Text('Mode Gratuit',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        color: _isFreeTrial ? Colors.white54 : Colors.white, fontSize: 12,
                      )),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFreeTrial ? AppTheme.successColor : Colors.grey[400],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: !_isFreeTrial ? null : () => _confirmModeChange(false),
                  icon: Icon(Icons.lock_rounded, size: 16,
                      color: !_isFreeTrial ? Colors.white54 : Colors.white),
                  label: Text('Mode Payant',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        color: !_isFreeTrial ? Colors.white54 : Colors.white, fontSize: 12,
                      )),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_isFreeTrial ? AppTheme.accentColor : Colors.grey[400],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 20),

        // ── QUOTA DE BIENVENUE ────────────────────────────────────────────────
        _sectionHeader('Annonces gratuites (nouveaux utilisateurs)'),
        const SizedBox(height: 10),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.successColor, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Chaque nouvel utilisateur reçoit ces annonces gratuites une seule fois, '
                'valables pendant la durée configurée. Ces paramètres s\'appliquent uniquement '
                'aux nouveaux comptes.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.successColor, height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _numField(
              'Nombre d\'annonces gratuites',
              _freeQuotaCountCtrl,
              Icons.card_giftcard_outlined,
              isInt: true,
            )),
            const SizedBox(width: 12),
            Expanded(child: _numField(
              'Durée par annonce (jours)',
              _freeQuotaDaysCtrl,
              Icons.calendar_today_outlined,
              isInt: true,
            )),
          ]),
          _saveBar('Sauvegarder', _savePlatformSettings),
        ])),
        const SizedBox(height: 20),

        // ── CONTACTS BOUTON CONTACT (WhatsApp + Téléphone + Email) ──────────
        _sectionHeader('Bouton "Contact" — Coordonnées'),
        const SizedBox(height: 10),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.accentColor, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Ces coordonnées s\'affichent dans le menu "Contact" de la navigation. '
                'Le visiteur choisit WhatsApp, appel normal ou email.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.accentColor, height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 16),

          // ── WhatsApp ──────────────────────────────────────────────────────
          const Text('WhatsApp', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _waContactCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText: '243812345678 (avec indicatif, sans +)',
              hintStyle: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 12, color: AppTheme.textHint),
              prefixIcon: const Icon(Icons.chat_rounded,
                  color: Color(0xFF25D366), size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.dividerColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF25D366), width: 2)),
              filled: true, fillColor: AppTheme.backgroundColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingWa ? null : _saveWhatsappContact,
              icon: _isSavingWa
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, color: Colors.white, size: 16),
              label: Text(_isSavingWa ? 'Sauvegarde...' : 'Sauvegarder WhatsApp',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Téléphone normal ──────────────────────────────────────────────
          const Text('Téléphone (Appel Normal)', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _phoneContactCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText: '+243 81 234 5678',
              hintStyle: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 12, color: AppTheme.textHint),
              prefixIcon: const Icon(Icons.phone_rounded,
                  color: AppTheme.accentColor, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.dividerColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
              filled: true, fillColor: AppTheme.backgroundColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingPhone ? null : _savePhoneContact,
              icon: _isSavingPhone
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, color: Colors.white, size: 16),
              label: Text(_isSavingPhone ? 'Sauvegarde...' : 'Sauvegarder Téléphone',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Email ─────────────────────────────────────────────────────────
          const Text('Email de contact', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _emailContactCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'contact@immozone.cd',
              hintStyle: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 12, color: AppTheme.textHint),
              prefixIcon: const Icon(Icons.email_outlined,
                  color: AppTheme.accentColor, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.dividerColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
              filled: true, fillColor: AppTheme.backgroundColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingEmail ? null : _saveEmailContact,
              icon: _isSavingEmail
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, color: Colors.white, size: 16),
              label: Text(_isSavingEmail ? 'Sauvegarde...' : 'Sauvegarder Email',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ])),
        const SizedBox(height: 20),

        // ── CONTACTS ADMIN ────────────────────────────────────────────────────
        _sectionHeader('Gestion des contacts'),
        const SizedBox(height: 10),
        _card(Column(children: [
          const Text(
            'Gérez les contacts affichés sur la plateforme publique (WhatsApp, téléphone, email, réseaux sociaux).',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminContactsScreen())),
              icon: const Icon(Icons.contacts_rounded, color: Colors.white, size: 18),
              label: const Text('Gérer les contacts',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ])),
        const SizedBox(height: 24),

        // ── BOUTON SAUVEGARDER ────────────────────────────────────────────────
        _saveBar('Sauvegarder les paramètres plateforme', _savePlatformSettings),
        const SizedBox(height: 40),
      ]),
    );
  }

  // ── MÉTHODES PROMOTION ─────────────────────────────────────────────────────

  /// Construit le widget principal de la section Promotions.
  /// Utilise StatefulBuilder pour que les dropdowns pays/ville/commune
  /// se raffraichissent localement sans rebuild global.
  Widget _buildPromoSection() {
    return StatefulBuilder(
      builder: (ctx, setPromo) {
        final countries = AppConstants.countries;
        final citiesForCountry = _promoTargetCountry != null
            ? AppConstants.getCitiesForCountry(_promoTargetCountry!)
            : <String>[];
        const zoneNames = ['Standard', 'Intermédiaire', 'Premium', 'Luxe'];

        String scopeLabel;
        if (_promoScopeIndex == 0) {
          scopeLabel = 'Tous les utilisateurs';
        } else if (_promoTargetZone != null) {
          final cityPart = _promoTargetCity != null ? ' • Ville : $_promoTargetCity' : '';
          final countryPart = _promoTargetCountry != null ? ' • $_promoTargetCountry' : '';
          scopeLabel = 'Zone : $_promoTargetZone$cityPart$countryPart';
        } else if (_promoTargetCity != null) {
          scopeLabel = 'Ville : $_promoTargetCity';
        } else if (_promoTargetCountry != null) {
          scopeLabel = 'Pays : $_promoTargetCountry';
        } else {
          scopeLabel = 'Choisir une zone...';
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Statut promo ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isPromoActive
                  ? AppTheme.successColor.withValues(alpha: 0.1)
                  : AppTheme.errorColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isPromoActive ? AppTheme.successColor : AppTheme.errorColor,
                width: 1.2,
              ),
            ),
            child: Row(children: [
              Icon(
                _isPromoActive ? Icons.campaign_rounded : Icons.campaign_outlined,
                color: _isPromoActive ? AppTheme.successColor : AppTheme.errorColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(
                _isPromoActive
                    ? 'Promotion en cours'
                    : 'Aucune promotion active',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                  color: _isPromoActive ? AppTheme.successColor : AppTheme.errorColor,
                ),
              )),
              if (_isPromoActive)
                TextButton(
                  onPressed: _isLaunchingPromo ? null : _suspendPromotion,
                  child: const Text('Suspendre',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          fontWeight: FontWeight.w700, color: AppTheme.errorColor)),
                ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Toggle global / par zone ────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(children: [
              _promoScopeBtn(setPromo, 0, Icons.public_rounded, 'Tous les users'),
              _promoScopeBtn(setPromo, 1, Icons.location_on_rounded, 'Par zone'),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Selecteurs de zone (mode par zone) ─────────────────────────
          if (_promoScopeIndex == 1) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.filter_alt_outlined, size: 16, color: AppTheme.accentColor),
                  SizedBox(width: 6),
                  Text('Filtrer par zone',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 12, color: AppTheme.textPrimary)),
                ]),
                const SizedBox(height: 12),

                // Pays
                _promoDropdown<String>(
                  icon: Icons.flag_outlined,
                  hint: 'Selectionner un pays',
                  value: _promoTargetCountry,
                  items: countries,
                  labelOf: (c) => c,
                  onChanged: (v) => setPromo(() {
                    _promoTargetCountry = v;
                    _promoTargetCity = null;
                    _promoTargetZone = null;
                  }),
                ),
                const SizedBox(height: 10),

                // Ville (optionnel)
                if (_promoTargetCountry != null) ...[
                  _promoDropdown<String>(
                    icon: Icons.location_city_outlined,
                    hint: 'Choisir une ville (optionnel)',
                    value: _promoTargetCity,
                    items: citiesForCountry,
                    labelOf: (c) => c,
                    onChanged: (v) => setPromo(() {
                      _promoTargetCity = v;
                      _promoTargetZone = null;
                    }),
                    nullable: true,
                    nullLabel: 'Tout le pays',
                  ),
                  const SizedBox(height: 10),
                ],

                // Zone de publication (Standard / Intermédiaire / Premium / Luxe)
                _promoDropdown<String>(
                  icon: Icons.layers_rounded,
                  hint: 'Choisir une zone (optionnel)',
                  value: _promoTargetZone,
                  items: zoneNames,
                  labelOf: (z) => z,
                  onChanged: (v) => setPromo(() => _promoTargetZone = v),
                  nullable: true,
                  nullLabel: 'Toutes les zones',
                ),
                const SizedBox(height: 10),

                // Recap cible
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.my_location_rounded, size: 14, color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Cible : $scopeLabel',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          fontWeight: FontWeight.w600, color: AppTheme.accentColor),
                    )),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          // ── Quantite + raison ───────────────────────────────────────────
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _promoQtyCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Nb annonces',
                  labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                  prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _promoReasonCtrl,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Raison / libelle',
                  labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                  prefixIcon: const Icon(Icons.label_outline, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Bouton lancer ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLaunchingPromo
                  ? null
                  : () => _launchPromotion(setPromo),
              icon: _isLaunchingPromo
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 16, color: Colors.white),
              label: Text(
                _isLaunchingPromo
                    ? 'Envoi en cours...'
                    : 'Lancer — $scopeLabel',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _promoScopeBtn(StateSetter setPromo, int index, IconData icon, String label) {
    final selected = _promoScopeIndex == index;
    return Expanded(
      child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
        onTap: () => setPromo(() {
          _promoScopeIndex = index;
          if (index == 0) {
            _promoTargetCountry = null;
            _promoTargetCity = null;
            _promoTargetZone = null;
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15,
                color: selected ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppTheme.textSecondary,
            )),
          ]),
        ),
      )),
    );
  }

  Widget _promoDropdown<T>({
    required IconData icon,
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
    bool nullable = false,
    String nullLabel = 'Tous',
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(icon, size: 18, color: AppTheme.accentColor),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.dividerColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.dividerColor)),
      ),
      hint: Text(hint, style: const TextStyle(fontFamily: 'Poppins',
          fontSize: 12, color: AppTheme.textHint)),
      onChanged: onChanged,
      items: [
        if (nullable)
          DropdownMenuItem<T>(
            value: null,
            child: Text(nullLabel, style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic)),
          ),
        ...items.map((item) => DropdownMenuItem<T>(
          value: item,
          child: Text(labelOf(item), style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textPrimary)),
        )),
      ],
    );
  }

  Future<void> _launchPromotion([StateSetter? setPromo]) async {
    final qty = int.tryParse(_promoQtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      _snackErr("Entrez un nombre valide d'annonces gratuites (minimum 1)");
      return;
    }
    final reason = _promoReasonCtrl.text.trim().isEmpty
        ? 'Promotion administrative'
        : _promoReasonCtrl.text.trim();

    String scopeDesc;
    if (_promoScopeIndex == 0) {
      scopeDesc = 'TOUS les utilisateurs de la plateforme';
    } else if (_promoTargetZone != null) {
      final cityPart = _promoTargetCity != null ? ' • Ville : $_promoTargetCity' : '';
      final countryPart = _promoTargetCountry != null ? ' ($_promoTargetCountry)' : '';
      scopeDesc = 'Zone : $_promoTargetZone$cityPart$countryPart';
    } else if (_promoTargetCity != null) {
      scopeDesc = 'Ville : $_promoTargetCity (toutes zones)';
    } else if (_promoTargetCountry != null) {
      scopeDesc = 'Pays : $_promoTargetCountry (toutes zones)';
    } else {
      _snackErr('Selectionnez au moins un pays pour une promo par zone.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.campaign_rounded, color: Color(0xFFFF6B35)),
          SizedBox(width: 10),
          Expanded(child: Text('Confirmer la promotion',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Offrir $qty annonce(s) gratuite(s) aux utilisateurs :',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFFF6B35)),
              const SizedBox(width: 8),
              Expanded(child: Text(scopeDesc,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w700, color: Color(0xFFFF6B35)))),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Raison : $reason',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: AppTheme.textHint)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Confirmer',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLaunchingPromo = true);
    if (setPromo != null) setPromo(() {});
    try {
      final result = await _ds.launchPromotion(
        freeAnnouncements: qty,
        reason: reason,
        targetCountry: _promoScopeIndex == 1 ? _promoTargetCountry : null,
        targetCity: _promoScopeIndex == 1 ? _promoTargetCity : null,
        targetZone: _promoScopeIndex == 1 ? _promoTargetZone : null,
      );
      setState(() {
        _isPromoActive = true;
        _isLaunchingPromo = false;
      });
      if (setPromo != null) setPromo(() {});
      final count = result['credited_users'] as int? ?? 0;
      _snackOk('Promotion lanc\u00e9e ! $count utilisateur(s) ont re\u00e7u $qty annonce(s) gratuite(s)');
    } catch (e) {
      setState(() => _isLaunchingPromo = false);
      if (setPromo != null) setPromo(() {});
      _snackErr('Erreur lors du lancement : $e');
    }
  }

  Future<void> _suspendPromotion() async {
    setState(() => _isLaunchingPromo = true);
    try {
      await _ds.suspendPromotion();
      setState(() {
        _isPromoActive = false;
        _isLaunchingPromo = false;
      });
      _snackOk('✅ Promotion suspendue');
    } catch (e) {
      setState(() => _isLaunchingPromo = false);
      _snackErr('Erreur : $e');
    }
  }

  void _confirmModeChange(bool toFree) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(toFree ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: toFree ? AppTheme.successColor : AppTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(child: Text(
            toFree ? 'Passer en mode Gratuit ?' : 'Passer en mode Payant ?',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
          )),
        ]),
        content: Text(
          toFree
              ? 'En mode GRATUIT, tous les utilisateurs peuvent publier sans restriction. Cette action prend effet immédiatement.'
              : 'En mode PAYANT, les utilisateurs devront souscrire à un pack pour publier. Cette action prend effet immédiatement.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isFreeTrial = toFree);
              _ds.toggleFreeTrial(toFree);
              _snackOk(toFree ? '✅ Mode Gratuit activé !' : '✅ Mode Payant activé !');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: toFree ? AppTheme.successColor : AppTheme.accentColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(toFree ? 'Activer Gratuit' : 'Activer Payant',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ONGLET 2 — PACKS D'ABONNEMENT
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildPacksTab() {
    final publications = _packs.where((p) => p['type'] != 'subscription').toList();

    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Banner info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: AppTheme.accentColor, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Les packs actifs sont automatiquement visibles sur l\'espace public lors de la publication.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.accentColor, height: 1.4),
                )),
              ]),
            ),
            const SizedBox(height: 16),

            // Packs de crédits
            _sectionHeader('Packs de publications'),
            const SizedBox(height: 10),
            ...publications.asMap().entries.map((e) => _packCard(e.value, _packs.indexOf(e.value))),
            const SizedBox(height: 12),

            // Bouton ajouter
            OutlinedButton.icon(
              onPressed: () => _showPackDialog(),
              icon: const Icon(Icons.add_circle_outline, color: AppTheme.accentColor),
              label: const Text('Ajouter un pack',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: AppTheme.accentColor, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ),
      ),
      _saveBar('Sauvegarder les packs', _savePacks),
    ]);
  }

  Widget _packCard(Map<String, dynamic> pack, int index) {
    final isActive = pack['active'] == true;
    final isSub = pack['type'] == 'subscription';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? (isSub ? AppTheme.primaryLight.withValues(alpha: 0.5) : AppTheme.accentColor.withValues(alpha: 0.35))
              : AppTheme.dividerColor,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isSub ? AppTheme.primaryLight : AppTheme.accentColor).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isSub ? Icons.card_membership_rounded : Icons.inventory_2_outlined,
            color: isSub ? AppTheme.primaryLight : AppTheme.accentColor, size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pack['name'] ?? '', style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary,
          )),
          const SizedBox(height: 3),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accentColor, borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '\$${(pack['price'] as num).toStringAsFixed(2)} ${pack['currency'] ?? 'USD'}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            if ((pack['qty'] ?? 0) > 0)
              Text('${pack['qty']} crédits', style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary,
              )),
            if ((pack['qty'] ?? 0) == -1)
              const Text('Illimité/mois', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary,
              )),
            if ((pack['qty'] ?? 0) == -2)
              const Text('Illimité/an', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary,
              )),
          ]),
        ])),
        Switch(
          value: isActive,
          activeThumbColor: AppTheme.accentColor,
          onChanged: (v) => setState(() => _packs[index]['active'] = v),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 16, color: AppTheme.accentColor),
                  SizedBox(width: 8), Text('Modifier', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                ])),
            const PopupMenuItem(value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 16, color: AppTheme.errorColor),
                  SizedBox(width: 8),
                  Text('Supprimer', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.errorColor)),
                ])),
          ],
          onSelected: (val) {
            if (val == 'edit') {
              _showPackDialog(index: index);
            }
            if (val == 'delete') {
              _confirmDelete(
                onConfirm: () => setState(() => _packs.removeAt(index)),
                label: pack['name'] ?? 'ce pack',
              );
            }
          },
        ),
      ]),
    );
  }

  void _showPackDialog({int? index}) {
    final isEdit = index != null;
    final pack = isEdit ? Map<String, dynamic>.from(_packs[index]) : <String, dynamic>{
      'id': 'pack_${DateTime.now().millisecondsSinceEpoch}',
      'name': '', 'qty': 1, 'price': 2.0, 'currency': 'USD', 'active': true, 'type': 'publication',
    };
    final nameCtrl  = TextEditingController(text: pack['name'] ?? '');
    final qtyCtrl   = TextEditingController(text: (pack['qty'] ?? 1).toString());
    final priceCtrl = TextEditingController(text: (pack['price'] ?? 2.0).toString());
    String currency = pack['currency'] ?? 'USD';
    String type     = pack['type'] ?? 'publication';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'Modifier le pack' : 'Nouveau pack',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _dlgField(nameCtrl, 'Nom du pack *', Icons.label_outline),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _dlgField(priceCtrl, 'Prix *', Icons.attach_money, type: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: currency,
              onChanged: (v) => setS(() => currency = v!),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textPrimary),
              items: ['USD', 'CDF', 'EUR'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            ),
          ]),
          const SizedBox(height: 12),
          _dlgField(qtyCtrl, 'Qté (-1=illimité mensuel, -2=annuel)', Icons.numbers, type: TextInputType.number),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: _dlgDeco('Type', Icons.category_outlined),
            onChanged: (v) => setS(() => type = v!),
            items: const [
              DropdownMenuItem(value: 'publication', child: Text('Pack publications', style: TextStyle(fontFamily: 'Poppins', fontSize: 13))),
              DropdownMenuItem(value: 'subscription', child: Text('Abonnement', style: TextStyle(fontFamily: 'Poppins', fontSize: 13))),
            ],
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              final updated = {...pack, 'name': nameCtrl.text.trim(),
                'qty': int.tryParse(qtyCtrl.text) ?? 1,
                'price': double.tryParse(priceCtrl.text) ?? 2.0,
                'currency': currency, 'type': type};
              setState(() { isEdit ? _packs[index] = updated : _packs.add(updated); });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(isEdit ? 'Modifier' : 'Ajouter',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      )),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ONGLET 3 — MOYENS DE PAIEMENT (avec vrais logos)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildPaymentsTab() {
    return Column(children: [
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _paymentMethods.length + 1,
          itemBuilder: (_, i) {
            if (i == _paymentMethods.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () => _showPaymentDialog(),
                  icon: const Icon(Icons.add_circle_outline, color: AppTheme.accentColor),
                  label: const Text('Ajouter un moyen de paiement',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    side: const BorderSide(color: AppTheme.accentColor, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              );
            }
            return _paymentCard(_paymentMethods[i], i);
          },
        ),
      ),
      _saveBar('Sauvegarder les moyens de paiement', _savePaymentMethods),
    ]);
  }

  Widget _paymentCard(Map<String, dynamic> pm, int index) {
    final isActive = pm['active'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppTheme.accentColor.withValues(alpha: 0.3) : AppTheme.dividerColor,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Row(children: [
        // Logo opérateur
        _operatorLogo(pm['icon'] ?? 'other', size: 48),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pm['name'] ?? '', style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary,
          )),
          const SizedBox(height: 2),
          Text(pm['number'] ?? '', style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.accentColor,
          )),
        ])),
        Switch(value: isActive, activeThumbColor: AppTheme.accentColor,
            onChanged: (v) => setState(() => _paymentMethods[index]['active'] = v)),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit',
                child: Row(children: [Icon(Icons.edit_outlined, size: 16, color: AppTheme.accentColor),
                  SizedBox(width: 8), Text('Modifier', style: TextStyle(fontFamily: 'Poppins', fontSize: 13))])),
            const PopupMenuItem(value: 'delete',
                child: Row(children: [Icon(Icons.delete_outline, size: 16, color: AppTheme.errorColor),
                  SizedBox(width: 8),
                  Text('Supprimer', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.errorColor))])),
          ],
          onSelected: (val) {
            if (val == 'edit') {
              _showPaymentDialog(index: index);
            }
            if (val == 'delete') {
              _confirmDelete(
                onConfirm: () => setState(() => _paymentMethods.removeAt(index)),
                label: pm['name'] ?? 'ce moyen de paiement',
              );
            }
          },
        ),
      ]),
    );
  }

  // ── Logo opérateur (SVG/Image réseau avec fallback) ───────────────────────
  Widget _operatorLogo(String type, {double size = 40}) {
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
    final url = logos[type];
    final color = colors[type] ?? AppTheme.accentColor;

    if (url != null) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 6)],
        ),
        padding: const EdgeInsets.all(4),
        child: Image.network(url, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(Icons.payment, color: color, size: size * 0.55)),
      );
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.payment, color: color, size: size * 0.55),
    );
  }

  void _showPaymentDialog({int? index}) {
    final isEdit = index != null;
    final pm = isEdit ? Map<String, dynamic>.from(_paymentMethods[index]) : <String, dynamic>{
      'id': 'pm_${DateTime.now().millisecondsSinceEpoch}',
      'name': '', 'number': '', 'icon': 'other', 'active': true,
    };
    final nameCtrl   = TextEditingController(text: pm['name'] ?? '');
    final numberCtrl = TextEditingController(text: pm['number'] ?? '');
    String icon = pm['icon'] ?? 'other';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'Modifier' : 'Nouveau moyen de paiement',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Aperçu logo
          Center(child: _operatorLogo(icon, size: 60)),
          const SizedBox(height: 14),
          _dlgField(nameCtrl, 'Nom (ex: M-Pesa Vodacom) *', Icons.label_outline),
          const SizedBox(height: 12),
          _dlgField(numberCtrl, 'Numéro Mobile Money *', Icons.phone, type: TextInputType.phone),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: icon,
            decoration: _dlgDeco('Opérateur', Icons.sim_card_outlined),
            onChanged: (v) => setS(() => icon = v!),
            items: const [
              DropdownMenuItem(value: 'mpesa',  child: Text('M-Pesa (Vodacom)',  style: TextStyle(fontFamily: 'Poppins', fontSize: 13))),
              DropdownMenuItem(value: 'orange', child: Text('Orange Money',      style: TextStyle(fontFamily: 'Poppins', fontSize: 13))),
              DropdownMenuItem(value: 'airtel', child: Text('Airtel Money',      style: TextStyle(fontFamily: 'Poppins', fontSize: 13))),
              DropdownMenuItem(value: 'other',  child: Text('Autre opérateur',   style: TextStyle(fontFamily: 'Poppins', fontSize: 13))),
            ],
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || numberCtrl.text.trim().isEmpty) {
                _snackErr('Nom et numéro requis'); return;
              }
              final updated = {...pm, 'name': nameCtrl.text.trim(), 'number': numberCtrl.text.trim(), 'icon': icon};
              setState(() { isEdit ? _paymentMethods[index] = updated : _paymentMethods.add(updated); });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(isEdit ? 'Modifier' : 'Ajouter',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      )),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ONGLET 4 — ZONES GÉOGRAPHIQUES
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildZonesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Bouton d'accès à l'écran complet
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdminZonesScreen())).then((_) => _load()),
            icon: const Icon(Icons.edit_location_alt_rounded, color: Colors.white, size: 18),
            label: const Text('Gérer les zones géographiques',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.accentColor, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ONGLET 5 — MESSAGE OFFICIEL
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildMessageTab() {
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ══ TEXTE D'ACCUEIL ═══════════════════════════════════════════════
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFA726).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFA726).withValues(alpha: 0.35)),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.home_rounded, color: Color(0xFFFFA726), size: 20),
                  SizedBox(width: 8),
                  Text('Texte d\'accueil (page principale)', style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFFFA726),
                  )),
                ]),
                SizedBox(height: 6),
                Text(
                  'Le titre et le sous-titre s\'affichent dans la bannière hero de la page d\'accueil. '
                  'Utilisez \\n pour créer un saut de ligne dans le titre.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Color(0xFFFFA726), height: 1.5),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            _sectionHeader('Titre principal'),
            const SizedBox(height: 8),
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _homeTitleCtrl,
                maxLines: 2,
                maxLength: 80,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ex: Trouvez Votre\\nMaison de Rêve',
                  hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint, fontSize: 12),
                  filled: true, fillColor: AppTheme.backgroundColor,
                  helperText: 'Utilisez \\n pour un saut de ligne (ex: "Ligne 1\\nLigne 2")',
                  helperStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppTheme.textHint),
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.dividerColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFA726), width: 2)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.dividerColor)),
                ),
              ),
            ])),
            const SizedBox(height: 12),

            _sectionHeader('Sous-titre'),
            const SizedBox(height: 8),
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _homeSubtitleCtrl,
                maxLines: 2,
                maxLength: 120,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ex: Des milliers de propriétés à votre portée',
                  hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint, fontSize: 12),
                  filled: true, fillColor: AppTheme.backgroundColor,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.dividerColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFA726), width: 2)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.dividerColor)),
                ),
              ),
            ])),
            const SizedBox(height: 8),

            // Aperçu live du hero
            _sectionHeader('Aperçu du hero'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB8D0F5), Color(0xFFCADCF8), Color(0xFFE8F1FD), Colors.white],
                  stops: [0.0, 0.35, 0.70, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(children: [
                Text(
                  _homeTitleCtrl.text.isEmpty ? 'Titre ici' : _homeTitleCtrl.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                      fontSize: 20, color: AppTheme.textPrimary, height: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  _homeSubtitleCtrl.text.isEmpty ? 'Sous-titre ici' : _homeSubtitleCtrl.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: _homeSubtitleCtrl.text.isEmpty ? AppTheme.textHint : AppTheme.textSecondary),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            if (!_isSavingHomeText)
              _saveBar('Sauvegarder le texte d\'accueil', _saveHomeText)
            else
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: null,
                    icon: const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    label: const Text('Sauvegarde...',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFA726),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),

            const Divider(height: 32),

            // ══ MESSAGE OFFICIEL ══════════════════════════════════════════════

            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.campaign_rounded, color: AppTheme.accentColor, size: 20),
                  SizedBox(width: 8),
                  Text('Message officiel ImmoZone', style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.accentColor,
                  )),
                ]),
                SizedBox(height: 6),
                Text(
                  'Ce message apparaît sur chaque annonce visible sur la plateforme publique. '
                  'Utilisez-le pour des avertissements légaux, conseils de sécurité ou informations importantes.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.accentColor, height: 1.5),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            _sectionHeader('Rédiger le message'),
            const SizedBox(height: 10),
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _officialMsgCtrl,
                maxLines: 8,
                maxLength: 500,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textPrimary, height: 1.6),
                decoration: InputDecoration(
                  hintText: 'Saisissez ici le message officiel qui apparaîtra sur chaque annonce...',
                  hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint, fontSize: 12),
                  filled: true, fillColor: AppTheme.backgroundColor,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.dividerColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.dividerColor)),
                ),
              ),
              const SizedBox(height: 14),
              // Aperçu
              const Text('Aperçu sur l\'annonce :',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.campaign_rounded, color: AppTheme.accentColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    _officialMsgCtrl.text.isEmpty
                        ? 'Le message apparaîtra ici...'
                        : _officialMsgCtrl.text,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, height: 1.5,
                      color: _officialMsgCtrl.text.isEmpty ? AppTheme.textHint : AppTheme.textSecondary,
                      fontStyle: _officialMsgCtrl.text.isEmpty ? FontStyle.italic : FontStyle.normal,
                    ),
                  )),
                ]),
              ),
            ])),
            const SizedBox(height: 16),

            // Modèles prédéfinis
            _sectionHeader('Modèles prédéfinis'),
            const SizedBox(height: 10),
            _card(Column(children: [
              _templateBtn(
                '⚠️ Avertissement légal',
                'ImmoZone n\'est qu\'un intermédiaire. Vérifiez toujours l\'authenticité des documents avant toute transaction. Ne versez aucune somme sans avoir visité le bien physiquement.',
              ),
              const Divider(height: 16),
              _templateBtn(
                '🔒 Conseil de sécurité',
                'Pour votre sécurité, ne communiquez jamais vos informations bancaires. Méfiez-vous des prix trop bas. ImmoZone ne demande jamais de paiement avant visite.',
              ),
              const Divider(height: 16),
              _templateBtn(
                'Contact support',
                'Pour toute réclamation ou assistance, contactez notre équipe via WhatsApp ou email. Nous répondons dans les 24h ouvrables.',
              ),
            ])),
          ]),
        ),
      ),
      _saveBar('Sauvegarder le message officiel', _saveOfficialMessage),
    ]);
  }

  Widget _templateBtn(String title, String msg) => InkWell(
    onTap: () => setState(() => _officialMsgCtrl.text = msg),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
              fontSize: 12, color: AppTheme.textPrimary)),
          const SizedBox(height: 3),
          Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textSecondary)),
        ])),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppTheme.accentColor),
      ]),
    ),
  );

  // ── Helpers communs ────────────────────────────────────────────────────────
  void _confirmDelete({required VoidCallback onConfirm, required String label}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmer la suppression', style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary)),
        content: Text('Supprimer "$label" définitivement ?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); onConfirm(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _saveBar(String label, VoidCallback onSave) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 24),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : onSave,
        icon: _isSaving
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save_rounded, color: Colors.white, size: 16),
        label: Text(label, style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 13, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentColor,
          padding: const EdgeInsets.symmetric(vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
  );

  Widget _sectionHeader(String title) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border(left: BorderSide(color: AppTheme.primaryColor, width: 3)),
    ),
    child: Text(title, style: const TextStyle(fontFamily: 'Poppins',
        fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary)),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
    ),
    child: child,
  );

  Widget _numField(String label, TextEditingController ctrl, IconData icon, {bool isInt = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
            fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: isInt ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
          decoration: InputDecoration(
            hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint),
            prefixIcon: Icon(icon, color: AppTheme.accentColor, size: 18),
            filled: true, fillColor: AppTheme.backgroundColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.dividerColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.dividerColor)),
          ),
        ),
      ]),
    );

  Widget _dlgField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType type = TextInputType.text}) =>
    TextField(
      controller: ctrl, keyboardType: type,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: _dlgDeco(hint, icon),
    );

  InputDecoration _dlgDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint, fontSize: 12),
    prefixIcon: Icon(icon, color: AppTheme.accentColor, size: 18),
    filled: true, fillColor: AppTheme.backgroundColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.dividerColor)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.dividerColor)),
  );
  // ════════════════════════════════════════════════════════════════════════════
  // ONGLET 6 — PROMOTIONS (annonces gratuites + paliers de recharge)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildPromotionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── PROMOTION ANNONCES GRATUITES (push admin) ─────────────────────
        _sectionHeader('Promotion — Annonces gratuites (push admin)'),
        const SizedBox(height: 10),
        _card(_buildPromoSection()),
        const SizedBox(height: 24),

        // ── PROMOTION PALIERS DE RECHARGE ─────────────────────────────────
        _sectionHeader('Promotion — Bonus de recharge par paliers'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(11),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A3A8F).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF0A3A8F).withValues(alpha: 0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Color(0xFF0A3A8F), size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              "Quand un utilisateur recharge, le palier correspondant s'applique automatiquement a la validation du paiement : credits bonus + annonces gratuites offerts.",
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Color(0xFF0A3A8F), height: 1.4),
            )),
          ]),
        ),

        // Toggle activer/désactiver
        _card(Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Activer la promotion par paliers',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 13, color: AppTheme.textPrimary)),
            Text(
              _isTiersPromoActive ? 'Active — bonus appliqué à chaque recharge éligible' : 'Désactivée',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: _isTiersPromoActive ? AppTheme.successColor : AppTheme.textHint),
            ),
          ])),
          Switch(
            value: _isTiersPromoActive,
            activeColor: AppTheme.successColor,
            onChanged: (v) async {
              setState(() => _isTiersPromoActive = v);
              await _ds.setRechargeTiersPromoActive(v);
              _snackOk(v ? 'Promotion paliers activée' : 'Promotion paliers désactivée');
            },
          ),
        ])),
        const SizedBox(height: 16),

        // ── Zone cible partagée pour tous les paliers ──────────────────────
        _buildSharedTierZoneFilter(),
        const SizedBox(height: 12),

        // Les 3 paliers
        ...List.generate(3, (i) => _buildTierCard(i)),
        const SizedBox(height: 8),

        // Bouton sauvegarder
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSavingTiers ? null : _saveRechargeTiers,
            icon: _isSavingTiers
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded, color: Colors.white, size: 16),
            label: Text(_isSavingTiers ? 'Sauvegarde...' : 'Sauvegarder les paliers',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 13, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _buildSharedTierZoneFilter() {
    const zoneNames = ['Standard', 'Intermédiaire', 'Premium', 'Luxe'];
    final countries  = AppConstants.countries;

    String cibleLabel;
    if (_sharedTierTargetZone != null) {
      cibleLabel = _sharedTierTargetZone!;
      if (_sharedTierTargetCity != null) cibleLabel += ' — $_sharedTierTargetCity';
      if (_sharedTierTargetCountry != null) cibleLabel += ' ($_sharedTierTargetCountry)';
    } else if (_sharedTierTargetCountry != null) {
      cibleLabel = 'Tout le pays : $_sharedTierTargetCountry';
    } else {
      cibleLabel = 'Tous les utilisateurs';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.filter_alt_outlined, size: 16, color: AppTheme.accentColor),
          SizedBox(width: 8),
          Expanded(child: Text('Zone cible (commune aux 3 paliers)',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 12, color: AppTheme.textPrimary))),
        ]),
        const SizedBox(height: 3),
        const Text("Laissez vide = s'applique a tous les utilisateurs",
            style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                color: AppTheme.textHint)),
        const SizedBox(height: 12),

        // Pays
        _promoDropdown<String>(
          icon: Icons.flag_outlined,
          hint: 'Selectionner un pays',
          value: _sharedTierTargetCountry,
          items: countries,
          labelOf: (c) => c,
          onChanged: (v) => setState(() {
            _sharedTierTargetCountry = v;
            _sharedTierTargetCity = null;
            _sharedTierTargetZone = null;
          }),
        ),
        const SizedBox(height: 8),

        // Ville (si pays choisi)
        if (_sharedTierTargetCountry != null) ...[
          _promoDropdown<String>(
            icon: Icons.location_city_outlined,
            hint: 'Choisir une ville (optionnel)',
            value: _sharedTierTargetCity,
            items: AppConstants.getCitiesForCountry(_sharedTierTargetCountry!),
            labelOf: (c) => c,
            onChanged: (v) => setState(() {
              _sharedTierTargetCity = v;
              _sharedTierTargetZone = null;
            }),
            nullable: true,
            nullLabel: 'Tout le pays',
          ),
          const SizedBox(height: 8),
        ],

        // Zone de publication
        _promoDropdown<String>(
          icon: Icons.layers_rounded,
          hint: 'Toutes les zones',
          value: _sharedTierTargetZone,
          items: zoneNames,
          labelOf: (z) => z,
          onChanged: (v) => setState(() => _sharedTierTargetZone = v),
          nullable: true,
          nullLabel: 'Toutes les zones',
        ),
        const SizedBox(height: 10),

        // Cible recap
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.my_location_rounded, size: 14, color: AppTheme.accentColor),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Cible : $cibleLabel',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: AppTheme.accentColor),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildTierCard(int i) {
    const tierColors = [Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFF2E7D32)];
    const tierLabels = ['Palier 1', 'Palier 2', 'Palier 3'];
    const tierIcons  = [Icons.looks_one_rounded, Icons.looks_two_rounded, Icons.looks_3_rounded];
    final color = tierColors[i];
    final isLast = i == 2;
    final freeAdsOptions = [0, 1, 2, 3, 4, 5];
    final maxHint = isLast ? 'Illimité (pas de plafond)' : 'Max \$ (ex: 99)';

    return StatefulBuilder(builder: (ctx, setTile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(tierIcons[i], color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(tierLabels[i],
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 14, color: color))),
          ]),
          const SizedBox(height: 14),

          // Seuils min / max
          Row(children: [
            Expanded(child: _tileField(_tierMinCtrl[i], 'Min \$ (ex: 20)',
                Icons.arrow_downward_rounded, color)),
            const SizedBox(width: 10),
            Expanded(child: _tileField(_tierMaxCtrl[i], maxHint,
                Icons.arrow_upward_rounded, color,
                hint: isLast ? 'Laisser vide = illimité' : null)),
          ]),
          const SizedBox(height: 10),

          // Bonus crédits %
          _tileField(_tierPctCtrl[i], 'Bonus crédits % (0–100)',
              Icons.percent_rounded, color),
          const SizedBox(height: 10),

          // Annonces gratuites — dropdown 0..5
          Row(children: [
            const Icon(Icons.confirmation_number_outlined, size: 18, color: AppTheme.accentColor),
            const SizedBox(width: 8),
            const Expanded(child: Text('Annonces gratuites offertes',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
            DropdownButton<int>(
              value: _tierFreeAds[i],
              items: freeAdsOptions.map((v) => DropdownMenuItem(
                value: v,
                child: Text('$v', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              )).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _tierFreeAds[i] = v);
                setTile(() {});
              },
            ),
          ]),
          const SizedBox(height: 10),


        ]),
      );
    });
  }

  Widget _tileField(TextEditingController ctrl, String label, IconData icon, Color color,
      {String? hint}) =>
    TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppTheme.textHint),
        prefixIcon: Icon(icon, color: color, size: 18),
        filled: true, fillColor: AppTheme.backgroundColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.dividerColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: color, width: 2)),
      ),
    );

  Future<void> _saveRechargeTiers() async {
    setState(() => _isSavingTiers = true);
    final tiers = <Map<String, dynamic>>[];
    const defaultMin  = [20.0, 50.0, 100.0];
    const defaultMax  = [49.0, 99.0, -1.0];
    const defaultPct  = [10, 25, 50];
    const tierLabels  = ['Palier 1', 'Palier 2', 'Palier 3'];
    for (int i = 0; i < 3; i++) {
      final minVal = double.tryParse(_tierMinCtrl[i].text.trim()) ?? defaultMin[i];
      final maxTxt = _tierMaxCtrl[i].text.trim();
      final maxVal = maxTxt.isEmpty ? -1.0 : (double.tryParse(maxTxt) ?? defaultMax[i]);
      final pct    = int.tryParse(_tierPctCtrl[i].text.trim()) ?? defaultPct[i];
      tiers.add({
        'enabled': true,
        'label': tierLabels[i],
        'minAmount': minVal,
        'maxAmount': maxVal,
        'bonusCreditPct': pct.clamp(0, 100),
        'bonusFreeAds': _tierFreeAds[i],
        'targetCountry': _sharedTierTargetCountry,
        'targetCity': _sharedTierTargetCity,
        'targetZone': _sharedTierTargetZone,
      });
    }
    await _ds.saveRechargeTiers(tiers);
    setState(() {
      _tiers = tiers;
      _isSavingTiers = false;
    });
    _snackOk('Paliers de recharge sauvegardés');
  }


}
