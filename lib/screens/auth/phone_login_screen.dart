import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/phone_auth_service.dart';
import 'otp_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PhoneLoginScreen — Saisie du numéro + envoi du SMS OTP
// ─────────────────────────────────────────────────────────────────────────────
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneCtrl      = TextEditingController();
  final _formKey        = GlobalKey<FormState>();
  final _phoneAuthSvc   = PhoneAuthService();

  String _countryCode   = '+243';
  bool   _isSending     = false;

  String get _fullPhone => '$_countryCode${_phoneCtrl.text.trim()}';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Envoyer le SMS OTP ────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    await _phoneAuthSvc.verifyPhoneNumber(
      phoneNumber: _fullPhone,

      // ── SMS envoyé → naviguer vers l'écran OTP ─────────────────────
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() => _isSending = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              phoneNumber:    _fullPhone,
              verificationId: verificationId,
              phoneAuthSvc:   _phoneAuthSvc,
            ),
          ),
        );
      },

      // ── Auto-retrieval Android (code détecté automatiquement) ───────
      onAutoVerified: (firebase_auth.UserCredential credential) async {
        if (!mounted) return;
        setState(() => _isSending = false);
        await _handleSuccessfulAuth(credential);
      },

      // ── Erreur ─────────────────────────────────────────────────────
      onFailed: (firebase_auth.FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isSending = false);
        _showError(PhoneAuthService.mapPhoneAuthError(e));
      },

      onTimeout: (_) {
        if (!mounted) return;
        setState(() => _isSending = false);
      },
    );
  }

  // ── Connexion réussie → charger le profil Firestore ───────────────────────
  // Stratégie double : UID d'abord, puis fallback par numéro de téléphone
  // Nécessaire car l'app utilise des "emails virtuels" pour l'auth existante
  // (ex: 243821908888@immozone.app) → l'UID Phone Auth ≠ UID email virtuel
  Future<void> _handleSuccessfulAuth(firebase_auth.UserCredential credential) async {
    final auth  = context.read<app_auth.AuthProvider>();
    final uid   = credential.user?.uid;
    final phone = _fullPhone; // ex: +243821908888
    if (uid == null) {
      _showError('Erreur d\'authentification inattendue.');
      return;
    }
    // Tentative 1 — par UID Firebase direct
    var user = await auth.loadUserByUid(uid);
    if (!mounted) return;
    // Tentative 2 — fallback par numéro de téléphone (cas email virtuel)
    if (user == null) {
      user = await auth.loadUserByPhone(phone);
      if (!mounted) return;
    }
    if (user != null) {
      if (auth.isAdmin) {
        Navigator.of(context).pushNamedAndRemoveUntil('/admin',   (_) => false);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/public',  (_) => false);
      }
    } else {
      _showError(
        'Ce numéro n\'est pas encore enregistré dans ImmoZone. '
        'Veuillez créer un compte.',
      );
    }
  }

  // ── Sélecteur d'indicatif pays ────────────────────────────────────────────
  void _showCountryPicker() async {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered = List.from(AppConstants.countryCodes);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          return DraggableScrollableSheet(
            initialChildSize: 0.70,
            maxChildSize: 0.92,
            minChildSize: 0.40,
            builder: (_, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(children: [
                // Poignée
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text('Indicatif pays',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 10),
                // Recherche
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
                      hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.accentColor),
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c     = filtered[i];
                      final isSel = c['code'] == _countryCode;
                      return ListTile(
                        onTap: () {
                          setState(() => _countryCode = c['code']!);
                          Navigator.pop(ctx);
                        },
                        leading: Text(c['flag'] ?? '', style: const TextStyle(fontSize: 24)),
                        title: Text(c['country'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                                fontSize: 14,
                                color: isSel ? AppTheme.accentColor : AppTheme.textPrimary)),
                        trailing: Text(c['code'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isSel ? AppTheme.accentColor : AppTheme.textSecondary)),
                        tileColor: isSel
                            ? AppTheme.accentColor.withValues(alpha: 0.07)
                            : null,
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final selected = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _countryCode,
      orElse: () => AppConstants.countryCodes.first,
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── Icône + Titre ─────────────────────────────────────────────
              Center(
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor,
                        AppTheme.accentColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.phone_android_rounded,
                      color: Colors.white, size: 40),
                ),
              ),
              const SizedBox(height: 28),

              Center(
                child: Text('Connexion par SMS',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Recevez un code OTP par SMS\npour vous connecter rapidement.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.6),
                ),
              ),
              const SizedBox(height: 36),

              // ── Formulaire ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.accentColor.withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Numéro de téléphone',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),

                      // Champ téléphone avec sélecteur d'indicatif
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.dividerColor),
                        ),
                        child: Row(children: [
                          // Indicatif pays
                          GestureDetector(
                            onTap: _showCountryPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                border: Border(
                                    right: BorderSide(
                                        color: AppTheme.dividerColor)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(selected['flag'] ?? '🌍',
                                      style: const TextStyle(fontSize: 20)),
                                  const SizedBox(width: 6),
                                  Text(_countryCode,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_drop_down_rounded,
                                      size: 18, color: AppTheme.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          // Champ numéro
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Ex : 812 345 678',
                                hintStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: AppTheme.textHint),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Numéro requis';
                                }
                                if (v.trim().length < 7) {
                                  return 'Numéro trop court';
                                }
                                return null;
                              },
                            ),
                          ),
                        ]),
                      ),

                      const SizedBox(height: 8),
                      // Numéro complet prévisualisé
                      AnimatedBuilder(
                        animation: _phoneCtrl,
                        builder: (_, __) => Text(
                          _phoneCtrl.text.isNotEmpty
                              ? 'Numéro complet : $_fullPhone'
                              : '',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppTheme.accentColor),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Bouton Envoyer le code ─────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSending ? null : _sendOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                AppTheme.primaryColor.withValues(alpha: 0.5),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isSending
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.send_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Envoyer le code SMS',
                                        style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Info sécurité ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.accentColor.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_rounded,
                        color: AppTheme.accentColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Un code de vérification à 6 chiffres sera envoyé '
                        'par SMS au numéro indiqué. Des frais SMS peuvent s\'appliquer.',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
