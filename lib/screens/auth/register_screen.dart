import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/data_service.dart';
import '../../services/phone_auth_service.dart';
import 'otp_register_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RegisterScreen — Saisie des infos + envoi OTP pour vérifier le numéro
// Architecture : PHONE AUTH ONLY (plus d'email virtuel)
// ─────────────────────────────────────────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey         = GlobalKey<FormState>();
  final _nameCtrl        = TextEditingController();
  final _phoneNumberCtrl = TextEditingController();
  final _passwordCtrl    = TextEditingController();
  final _confirmCtrl     = TextEditingController();
  final _sponsorCtrl     = TextEditingController(); // code parrainage (optionnel)
  final _phoneAuthSvc    = PhoneAuthService();

  String  _phoneCountryCode = '+243';
  bool    _obscure          = true;
  bool    _obscureConfirm   = true;
  bool    _isSending        = false;
  String? _selectedCategory;
  String? _selectedProvince; // province de résidence (obligatoire)
  String? _selectedCity;     // ville de résidence (obligatoire)
  String? _selectedCommune;  // commune de résidence (optionnel)

  // Nombre d'annonces gratuites configuré par l'admin (lu depuis Firestore settings)
  int _freeQuotaCount = 3; // valeur par défaut avant chargement

  String get _fullPhone => '$_phoneCountryCode${_phoneNumberCtrl.text.trim()}';

  /// Mappe un indicatif téléphonique vers le nom de pays utilisé par AppConstants.
  String _phoneCountryToAppCountry(String code) {
    if (code == '+242') return 'Congo (Brazzaville)';
    return 'Congo (RDC)'; // default : +243 et tout autre code
  }

  @override
  void initState() {
    super.initState();
    _loadFreeQuota();
  }

  Future<void> _loadFreeQuota() async {
    try {
      final ds = DataService();
      final settings = await ds.getSettingsMap();
      final count = (settings['free_quota_count'] as num?)?.toInt() ?? 3;
      if (mounted) setState(() => _freeQuotaCount = count);
    } catch (_) {
      // Valeur par défaut conservée
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _sponsorCtrl.dispose();
    super.dispose();
  }

  // ── Étape 1 : valider le formulaire puis envoyer OTP ─────────────────────
  Future<void> _sendOtpAndRegister() async {
    if (_selectedCategory == null) {
      _showError('Veuillez sélectionner votre catégorie.');
      return;
    }
    if (_selectedProvince == null) {
      _showError('Veuillez sélectionner votre province de résidence.');
      return;
    }
    if (_selectedCity == null) {
      _showError('Veuillez sélectionner votre ville de résidence.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Avertissement numéro public
    final confirmed = await _showPhoneWarningDialog();
    if (!confirmed || !mounted) return;

    setState(() => _isSending = true);

    await _phoneAuthSvc.verifyPhoneNumber(
      phoneNumber: _fullPhone,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() => _isSending = false);
        // Naviguer vers l'écran OTP avec toutes les infos d'inscription
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OtpRegisterScreen(
            phoneNumber:    _fullPhone,
            name:           _nameCtrl.text.trim(),
            password:       _passwordCtrl.text.trim(),
            category:       _selectedCategory!,
            verificationId: verificationId,
            phoneAuthSvc:   _phoneAuthSvc,
            sponsorCode:    _sponsorCtrl.text.trim().isEmpty ? null : _sponsorCtrl.text.trim().toUpperCase(),
            province:       _selectedProvince,
            city:           _selectedCity,
            commune:        _selectedCommune,
          ),
        ));
      },
      onAutoVerified: (firebase_auth.UserCredential credential) async {
        if (!mounted) return;
        setState(() => _isSending = false);
        // Auto-verification Android → créer directement le compte
        final auth = context.read<app_auth.AuthProvider>();
        final ok = await auth.registerWithPhoneCredential(
          credential:  credential,
          name:        _nameCtrl.text.trim(),
          phone:       _fullPhone,
          password:    _passwordCtrl.text.trim(),
          role:        AppConstants.roleAnnonceur,
          category:    _selectedCategory,
          sponsorCode: _sponsorCtrl.text.trim().isEmpty ? null : _sponsorCtrl.text.trim().toUpperCase(),
          province:    _selectedProvince,
          city:        _selectedCity,
          commune:     _selectedCommune,
        );
        if (!mounted) return;
        if (ok) {
          Navigator.of(context).pushReplacementNamed('/public');
        } else {
          _showError(auth.error ?? 'Erreur lors de l\'inscription.');
        }
      },
      onFailed: (firebase_auth.FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isSending = false);
        final errMsg = PhoneAuthService.mapPhoneAuthError(e);
        // Pour "trop de demandes" : afficher un dialog plutôt qu'un snackbar
        if (e.code == 'too-many-requests') {
          showDialog<void>(
            context: context,
            builder: (dCtx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(children: [
                const Icon(Icons.timer_outlined,
                    color: AppTheme.warningColor, size: 24),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text('Inscription temporairement bloquée',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ]),
              content: const Text(
                'Ce numéro a reçu trop de codes SMS récemment '
                '(peut arriver si un compte a été supprimé puis recréé).\n\n'
                'Attendez environ 10 minutes et réessayez.\n\n'
                'Si le problème persiste, contactez le support.',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, height: 1.5),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(dCtx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('OK',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          );
        } else {
          _showError(errMsg);
        }
      },
      onTimeout: (_) {
        if (!mounted) return;
        setState(() => _isSending = false);
      },
    );
  }

  Future<bool> _showPhoneWarningDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF57C00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone_in_talk_rounded,
                    color: Color(0xFFF57C00), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Important — Numéro public',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ]),
            content: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF57C00).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFF57C00).withValues(alpha: 0.35)),
              ),
              child: const Text(
                'Ce numéro sera votre identifiant de connexion ET sera affiché '
                'publiquement sur toutes vos annonces.\n\n'
                'Les chercheurs pourront vous contacter directement via ce numéro.\n\n'
                'Assurez-vous d\'utiliser un numéro actif capable de recevoir des SMS.',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Color(0xFF7B4A00),
                    height: 1.6),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Modifier le numéro',
                    style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF57C00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('J\'ai compris',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Créer un compte',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rejoignez ImmoZone',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 24),

                // ── Catégorie ────────────────────────────────────────────
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        fontFamily: 'Poppins'),
                    children: [
                      TextSpan(text: 'Sélectionnez votre catégorie'),
                      TextSpan(
                        text: ' *',
                        style: TextStyle(
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Column(
                  children: AppConstants.annonceurCategories
                      .map((cat) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _categoryCard(cat),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),

                // ── Nom complet ──────────────────────────────────────────
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Nom complet',
                    hintText: 'Votre nom et prénom',
                    // Icône renforcée — fond coloré pour meilleure visibilité
                    prefixIcon: Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: AppTheme.primaryColor, size: 18),
                    ),
                    // Bordure visible en permanence (override du thème global)
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.primaryColor, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.primaryColor, width: 2.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.errorColor, width: 1.5),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.errorColor, width: 2),
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Nom requis' : null,
                ),
                const SizedBox(height: 14),

                // ── Téléphone ────────────────────────────────────────────
                _phoneField(),
                const SizedBox(height: 6),

                // Bannière numéro public
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF57C00).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF57C00).withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.campaign_rounded, color: Color(0xFFF57C00), size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ce numéro sera votre identifiant de connexion ET sera visible sur vos annonces.',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Color(0xFF7B4A00),
                              height: 1.5,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Mot de passe ─────────────────────────────────────────
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.accentColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.textSecondary),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8A96B0), width: 2.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8A96B0), width: 2.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.errorColor, width: 1.5),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.errorColor, width: 2),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Mot de passe requis';
                    if (v.length < 6) return 'Minimum 6 caractères';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Confirmation ─────────────────────────────────────────
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.accentColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.textSecondary),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8A96B0), width: 2.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8A96B0), width: 2.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.errorColor, width: 1.5),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.errorColor, width: 2),
                    ),
                  ),
                  validator: (v) =>
                      v != _passwordCtrl.text ? 'Les mots de passe ne correspondent pas' : null,
                ),
                const SizedBox(height: 14),

                // ── Localisation du compte (obligatoire) ──────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.location_on_rounded, color: AppTheme.accentColor, size: 16),
                        const SizedBox(width: 6),
                        const Text('Localisation du compte *',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor)),
                      ]),
                      const SizedBox(height: 4),
                      const Text(
                          'Ces informations ne vous empêchent pas de poster '
                          'des annonces partout ailleurs.',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10.5,
                              color: AppTheme.textSecondary,
                              height: 1.4)),
                      const SizedBox(height: 10),
                      // Province dropdown (dynamique selon préfixe téléphonique)
                      DropdownButtonFormField<String>(
                        value: _selectedProvince,
                        decoration: InputDecoration(
                          labelText: 'Province *',
                          prefixIcon: const Icon(Icons.map_outlined, color: AppTheme.accentColor),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.dividerColor)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.dividerColor)),
                        ),
                        hint: const Text('Sélectionner une province',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                        isExpanded: true,
                        items: AppConstants.getProvincesForCountry(
                                _phoneCountryToAppCountry(_phoneCountryCode))
                            .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12))))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _selectedProvince = v;
                          _selectedCity = null;
                          _selectedCommune = null;
                        }),
                      ),
                      const SizedBox(height: 10),
                      // Ville dropdown (cascadé par province)
                      DropdownButtonFormField<String>(
                        value: _selectedCity,
                        decoration: InputDecoration(
                          labelText: 'Ville *',
                          prefixIcon: const Icon(Icons.location_city_rounded, color: AppTheme.accentColor),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.dividerColor)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.dividerColor)),
                        ),
                        hint: Text(
                            _selectedProvince == null
                                ? "Choisissez d'abord une province"
                                : 'Sélectionner une ville',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                        isExpanded: true,
                        items: _selectedProvince == null
                            ? []
                            : AppConstants.getCitiesForProvince(
                                    _phoneCountryToAppCountry(_phoneCountryCode),
                                    _selectedProvince!)
                                .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12))))
                                .toList(),
                        onChanged: _selectedProvince == null
                            ? null
                            : (v) => setState(() {
                                _selectedCity = v;
                                _selectedCommune = null;
                              }),
                      ),
                      const SizedBox(height: 10),
                      // Commune dropdown (cascadé par ville)
                      DropdownButtonFormField<String>(
                        value: _selectedCommune,
                        decoration: InputDecoration(
                          labelText: 'Commune',
                          prefixIcon: const Icon(Icons.holiday_village_outlined, color: AppTheme.accentColor),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.dividerColor)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.dividerColor)),
                        ),
                        hint: Text(
                            _selectedCity == null
                                ? "Choisissez d'abord une ville"
                                : 'Sélectionner une commune',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                        isExpanded: true,
                        items: _selectedCity == null
                            ? []
                            : AppConstants.getCommunesForCity(_selectedCity!)
                                .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12))))
                                .toList(),
                        onChanged: _selectedCity == null
                            ? null
                            : (v) => setState(() => _selectedCommune = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Code parrainage (optionnel) ──────────────────────────
                TextFormField(
                  controller: _sponsorCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Code parrainage (optionnel)',
                    hintText: 'Ex : PATOU2025',
                    prefixIcon: const Icon(Icons.group_add_outlined, color: AppTheme.accentColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8A96B0), width: 2.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8A96B0), width: 2.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Cadeau annonces gratuites (valeur dynamique admin) ───
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.card_giftcard, color: AppTheme.successColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          '$_freeQuotaCount annonce${_freeQuotaCount > 1 ? 's' : ''} gratuite${_freeQuotaCount > 1 ? 's' : ''} offertes à l\'inscription !',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.successColor)),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),

                // Info SMS
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.sms_rounded, color: AppTheme.accentColor, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'Un code de vérification SMS sera envoyé à votre numéro.',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              height: 1.4)),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Bouton créer compte ──────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _sendOtpAndRegister,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                        _isSending ? 'Envoi du code SMS...' : 'Créer mon compte',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Déjà un compte ? ',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontFamily: 'Poppins')),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Se connecter',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneField() {
    final selected = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _phoneCountryCode,
      orElse: () => AppConstants.countryCodes.first,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Numéro de téléphone *',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: _showPhoneCountryPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
              decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: AppTheme.dividerColor))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(selected['flag'] ?? '', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(_phoneCountryCode,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.accentColor)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: AppTheme.accentColor, size: 18),
              ]),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: _phoneNumberCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Numéro (ex : 812345678)',
                hintStyle: TextStyle(
                    fontFamily: 'Poppins', color: AppTheme.textHint, fontSize: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Numéro requis';
                if (v.trim().length < 7) return 'Numéro trop court';
                return null;
              },
            ),
          ),
        ]),
      ),
    ]);
  }

  void _showPhoneCountryPicker() {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered = List.from(AppConstants.countryCodes);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          initialChildSize: 0.70,
          maxChildSize: 0.92,
          minChildSize: 0.40,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(children: [
              Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.dividerColor,
                      borderRadius: BorderRadius.circular(2))),
              const Text('Indicatif pays',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: searchCtrl,
                  onChanged: (q) => setModal(() {
                    filtered = AppConstants.countryCodes
                        .where((c) =>
                            (c['country'] ?? '').toLowerCase().contains(q.toLowerCase()) ||
                            (c['code'] ?? '').contains(q))
                        .toList();
                  }),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un pays…',
                    prefixIcon: const Icon(Icons.search, color: AppTheme.accentColor),
                    filled: true,
                    fillColor: AppTheme.backgroundColor,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final isSel = c['code'] == _phoneCountryCode;
                    return ListTile(
                      onTap: () {
                        setState(() {
                          _phoneCountryCode = c['code']!;
                          // Réinitialiser la localisation si le pays change
                          _selectedProvince = null;
                          _selectedCity     = null;
                          _selectedCommune  = null;
                        });
                        Navigator.pop(ctx);
                      },
                      leading: Text(c['flag'] ?? '', style: const TextStyle(fontSize: 24)),
                      title: Text(c['country'] ?? '',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                              color: isSel ? AppTheme.accentColor : AppTheme.textPrimary)),
                      trailing: Text(c['code'] ?? '',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              color: isSel ? AppTheme.accentColor : AppTheme.textSecondary)),
                      tileColor: isSel ? AppTheme.accentColor.withValues(alpha: 0.06) : null,
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _categoryCard(String category) {
    final isSelected = _selectedCategory == category;
    IconData icon;
    Color color;
    String subtitle;
    switch (category) {
      case AppConstants.categoryAgence:
        icon = Icons.business_rounded;
        color = const Color(0xFF1565C0);
        subtitle = 'Je gère plusieurs biens pour des clients';
        break;
      case AppConstants.categoryCommissionnaire:
        icon = Icons.handshake_rounded;
        color = const Color(0xFF6A1B9A);
        subtitle = 'Je mets en relation acheteurs et vendeurs';
        break;
      default:
        icon = Icons.home_rounded;
        color = const Color(0xFF2E7D32);
        subtitle = 'Je publie mon propre bien';
    }
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isSelected ? color : AppTheme.dividerColor,
              width: isSelected ? 2 : 1),
          boxShadow: [
            BoxShadow(
                color: isSelected
                    ? color.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: isSelected ? 10 : 4,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.2)
                  : color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: isSelected ? Colors.white : color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(category,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      color: isSelected ? Colors.white : AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Poppins',
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.85)
                          : AppTheme.textSecondary)),
            ]),
          ),
          if (isSelected)
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
        ]),
      ),
    );
  }
}
