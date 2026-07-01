import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/phone_auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OtpRegisterScreen — Vérification OTP PUIS création du compte
// ─────────────────────────────────────────────────────────────────────────────
class OtpRegisterScreen extends StatefulWidget {
  final String          phoneNumber;
  final String          name;
  final String          password;
  final String          category;
  final String          verificationId;
  final PhoneAuthService phoneAuthSvc;
  final String?         sponsorCode; // code parrainage optionnel
  final String?         province;    // province de résidence (obligatoire)
  final String?         city;        // ville de résidence (obligatoire)
  final String?         commune;     // commune de résidence (optionnel)

  const OtpRegisterScreen({
    super.key,
    required this.phoneNumber,
    required this.name,
    required this.password,
    required this.category,
    required this.verificationId,
    required this.phoneAuthSvc,
    this.sponsorCode,
    this.province,
    this.city,
    this.commune,
  });

  @override
  State<OtpRegisterScreen> createState() => _OtpRegisterScreenState();
}

class _OtpRegisterScreenState extends State<OtpRegisterScreen>
    with TickerProviderStateMixin {
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  late String _currentVerificationId;
  bool _isVerifying  = false;
  bool _isResending  = false;
  bool _showSuccess  = false;
  int  _resendSeconds = 60;
  Timer? _resendTimer;

  late AnimationController _successAnimCtrl;
  late Animation<double>   _successAnim;

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
    _successAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _successAnim =
        CurvedAnimation(parent: _successAnimCtrl, curve: Curves.elasticOut);
    _startResendTimer();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNodes[0].requestFocus());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _successAnimCtrl.dispose();
    for (final c in _otpControllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  String get _otpCode => _otpControllers.map((c) => c.text).join();
  bool get _isOtpComplete => _otpCode.length == 6;

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 6) {
        for (int i = 0; i < 6; i++) {
          _otpControllers[i].text = digits[i];
        }
        _focusNodes[5].requestFocus();
        if (_isOtpComplete) _verifyAndRegister();
        return;
      }
    }
    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        if (_isOtpComplete) _verifyAndRegister();
      }
    } else {
      if (index > 0) _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  // ── Vérifier OTP puis créer le compte ─────────────────────────────────────
  Future<void> _verifyAndRegister() async {
    if (!_isOtpComplete || _isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      // 1. Vérifier le code OTP → obtenir le credential Firebase
      final credential = await widget.phoneAuthSvc.verifyOtp(
        verificationId: _currentVerificationId,
        smsCode: _otpCode,
      );

      if (!mounted) return;

      // 2. Créer le compte Firestore avec les infos d'inscription
      final auth = context.read<app_auth.AuthProvider>();
      final ok = await auth.registerWithPhoneCredential(
        credential:  credential,
        name:        widget.name,
        phone:       widget.phoneNumber,
        password:    widget.password,
        role:        AppConstants.roleAnnonceur,
        category:    widget.category,
        sponsorCode: widget.sponsorCode,
        province:    widget.province,
        city:        widget.city,
        commune:     widget.commune,
      );

      if (!mounted) return;

      if (ok) {
        // Animation succès
        setState(() => _showSuccess = true);
        await _successAnimCtrl.forward();
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        context.go('/public');
      } else {
        setState(() => _isVerifying = false);
        _clearOtp();
        _showError(auth.error ?? 'Erreur lors de la création du compte.');
      }
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      _clearOtp();
      _showError(PhoneAuthService.mapPhoneAuthError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      _clearOtp();
      _showError('Erreur de vérification. Réessayez.');
    }
  }

  Future<void> _resendOtp() async {
    if (_resendSeconds > 0 || _isResending) return;
    setState(() => _isResending = true);
    _clearOtp();

    await widget.phoneAuthSvc.resendOtp(
      phoneNumber: widget.phoneNumber,
      onCodeSent: (verificationId, _) {
        if (!mounted) return;
        setState(() {
          _currentVerificationId = verificationId;
          _isResending = false;
        });
        _startResendTimer();
        _showSuccess2('Nouveau code envoyé !');
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _focusNodes[0].requestFocus());
      },
      onFailed: (e) {
        if (!mounted) return;
        setState(() => _isResending = false);
        _showError(PhoneAuthService.mapPhoneAuthError(e));
      },
    );
  }

  void _clearOtp() {
    for (final c in _otpControllers) c.clear();
    setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNodes[0].requestFocus());
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess2(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: _isVerifying ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),

              // Icône
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _showSuccess
                    ? ScaleTransition(
                        scale: _successAnim,
                        child: Container(
                          key: const ValueKey('success'),
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: AppTheme.successColor,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                  color: AppTheme.successColor.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8))
                            ],
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 44),
                        ),
                      )
                    : Container(
                        key: const ValueKey('sms'),
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.primaryColor, AppTheme.accentColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                                color: AppTheme.primaryColor.withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 8))
                          ],
                        ),
                        child: const Icon(Icons.sms_rounded,
                            color: Colors.white, size: 40),
                      ),
              ),
              const SizedBox(height: 24),

              Text(_showSuccess ? 'Compte créé !' : 'Vérification du numéro',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text('Code envoyé au',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Text(widget.phoneNumber,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor)),
              const SizedBox(height: 8),
              Text('Bonjour ${widget.name} 👋',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 28),

              // ── Carte OTP ────────────────────────────────────────────────
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
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Column(children: [
                  const Text('Saisissez le code à 6 chiffres',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (i) => _buildOtpBox(i)),
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_isOtpComplete && !_isVerifying)
                          ? _verifyAndRegister
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppTheme.successColor.withValues(alpha: 0.4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_add_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Créer mon compte',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      _resendSeconds > 0
                          ? 'Renvoyer dans $_resendSeconds s'
                          : 'Pas reçu le code ?',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: AppTheme.textSecondary),
                    ),
                    if (_resendSeconds == 0) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _isResending ? null : _resendOtp,
                        child: _isResending
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('Renvoyer',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryColor,
                                    decoration: TextDecoration.underline)),
                      ),
                    ],
                  ]),
                ]),
              ),

              const SizedBox(height: 24),

              TextButton.icon(
                onPressed: _isVerifying ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Modifier mes informations',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final isFilled  = _otpControllers[index].text.isNotEmpty;
    final isFocused = _focusNodes[index].hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44, height: 54,
      decoration: BoxDecoration(
        color: isFilled
            ? AppTheme.successColor.withValues(alpha: 0.07)
            : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _showSuccess
              ? AppTheme.successColor
              : isFocused
                  ? AppTheme.primaryColor
                  : isFilled
                      ? AppTheme.accentColor
                      : AppTheme.dividerColor,
          width: isFocused ? 2 : 1.5,
        ),
      ),
      child: Focus(
        onFocusChange: (_) => setState(() {}),
        child: TextField(
          controller: _otpControllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _showSuccess ? AppTheme.successColor : AppTheme.primaryColor,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            counterText: '',
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) => _onOtpChanged(index, v),
          enabled: !_isVerifying,
        ),
      ),
    );
  }
}
