import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/phone_auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OtpScreen — 6 cases individuelles + timer de renvoi + vérification Firebase
// ─────────────────────────────────────────────────────────────────────────────
class OtpScreen extends StatefulWidget {
  final String          phoneNumber;
  final String          verificationId;
  final PhoneAuthService phoneAuthSvc;

  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    required this.phoneAuthSvc,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with TickerProviderStateMixin {
  // 6 contrôleurs + focus pour les cases OTP
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  late String          _currentVerificationId;
  bool                 _isVerifying    = false;
  bool                 _isResending    = false;

  // Timer de renvoi (60 secondes)
  int                  _resendSeconds  = 60;
  Timer?               _resendTimer;

  // Animation de succès
  late AnimationController _successAnimCtrl;
  late Animation<double>   _successAnim;
  bool                     _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;

    // Animation succès
    _successAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successAnim = CurvedAnimation(
        parent: _successAnimCtrl, curve: Curves.elasticOut);

    _startResendTimer();
    // Focus automatique sur la 1ère case
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusNodes[0].requestFocus());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _successAnimCtrl.dispose();
    for (final c in _otpControllers) { c.dispose(); }
    for (final f in _focusNodes)     { f.dispose(); }
    super.dispose();
  }

  // ── Timer renvoi SMS ──────────────────────────────────────────────────────
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

  // ── Obtenir le code OTP complet ───────────────────────────────────────────
  String get _otpCode =>
      _otpControllers.map((c) => c.text).join();

  bool get _isOtpComplete => _otpCode.length == 6;

  // ── Gérer la saisie dans chaque case ─────────────────────────────────────
  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      // Coller un code complet (6 chiffres)
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 6) {
        for (int i = 0; i < 6; i++) {
          _otpControllers[i].text = digits[i];
        }
        _focusNodes[5].requestFocus();
        if (_isOtpComplete) _verifyOtp();
        return;
      }
    }

    if (value.isNotEmpty) {
      // Avancer au champ suivant
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        if (_isOtpComplete) _verifyOtp();
      }
    } else {
      // Reculer si effacement
      if (index > 0) _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  // ── Vérifier le code OTP ──────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    if (!_isOtpComplete || _isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      final credential = await widget.phoneAuthSvc.verifyOtp(
        verificationId: _currentVerificationId,
        smsCode:        _otpCode,
      );

      if (!mounted) return;

      // Animation succès
      setState(() => _showSuccess = true);
      await _successAnimCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 800));

      await _handleSuccessfulAuth(credential);

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

  // ── Chargement du profil après auth réussie ─────────────────────────────
  // STRATÉGIE double :
  //  1. Chercher par UID Firebase (cas compte lié ou numéro test Firestore)
  //  2. Fallback par numéro de téléphone (cas email virtuel existant)
  Future<void> _handleSuccessfulAuth(firebase_auth.UserCredential credential) async {
    final auth  = context.read<app_auth.AuthProvider>();
    final uid   = credential.user?.uid;
    final phone = widget.phoneNumber; // ex: +243821908888

    if (uid == null) {
      _showError('Erreur d\'authentification inattendue.');
      setState(() { _isVerifying = false; _showSuccess = false; });
      return;
    }

    // Tentative 1 — par UID direct
    var user = await auth.loadUserByUid(uid);
    if (!mounted) return;

    // Tentative 2 — par numéro de téléphone (email virtuel existant)
    if (user == null) {
      user = await auth.loadUserByPhone(phone);
      if (!mounted) return;
    }

    if (user != null) {
      if (auth.isAdmin) {
        context.go('/admin');
      } else {
        context.go('/public');
      }
    } else {
      setState(() { _isVerifying = false; _showSuccess = false; });
      _showError(
        'Ce numéro n\'est pas encore enregistré dans ImmoZone. '
        'Veuillez créer un compte.',
      );
    }
  }

  // ── Renvoi du SMS ─────────────────────────────────────────────────────────
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
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _focusNodes[0].requestFocus());
      },
      onFailed: (e) {
        if (!mounted) return;
        setState(() => _isResending = false);
        _showError(PhoneAuthService.mapPhoneAuthError(e));
      },
    );
  }

  void _clearOtp() {
    for (final c in _otpControllers) { c.clear(); }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusNodes[0].requestFocus());
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
              const SizedBox(height: 20),

              // ── Icône succès animée OU icône SMS ──────────────────────────
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
                                color: AppTheme.successColor
                                    .withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
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
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.sms_rounded,
                            color: Colors.white, size: 40),
                      ),
              ),
              const SizedBox(height: 28),

              Text('Vérification SMS',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'Code envoyé au',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                widget.phoneNumber,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 36),

              // ── 6 cases OTP ───────────────────────────────────────────────
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
                child: Column(children: [
                  const Text('Saisissez le code à 6 chiffres',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 20),

                  // 6 cases
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (i) => _buildOtpBox(i)),
                  ),

                  const SizedBox(height: 28),

                  // ── Bouton Confirmer ─────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_isOtpComplete && !_isVerifying)
                          ? _verifyOtp
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppTheme.primaryColor.withValues(alpha: 0.4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.verified_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Confirmer le code',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Renvoi du code ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _resendSeconds > 0
                            ? 'Renvoyer dans $_resendSeconds s'
                            : 'Vous n\'avez pas reçu le code ?',
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
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : Text('Renvoyer',
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryColor,
                                      decoration:
                                          TextDecoration.underline)),
                        ),
                      ],
                    ],
                  ),
                ]),
              ),

              const SizedBox(height: 24),

              // ── Changer de numéro ─────────────────────────────────────────
              TextButton.icon(
                onPressed: _isVerifying ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Changer de numéro',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── Case OTP individuelle ─────────────────────────────────────────────────
  Widget _buildOtpBox(int index) {
    final isFilled  = _otpControllers[index].text.isNotEmpty;
    final isFocused = _focusNodes[index].hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44, height: 54,
      decoration: BoxDecoration(
        color: isFilled
            ? AppTheme.primaryColor.withValues(alpha: 0.07)
            : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isVerifying && _showSuccess
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
          focusNode:  _focusNodes[index],
          textAlign:  TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6), // permet le coller
          ],
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _showSuccess
                ? AppTheme.successColor
                : AppTheme.primaryColor,
          ),
          decoration: const InputDecoration(
            border:         InputBorder.none,
            enabledBorder:  InputBorder.none,
            focusedBorder:  InputBorder.none,
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
