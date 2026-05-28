import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/phone_auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OtpResetPasswordScreen — Vérification OTP PUIS réinitialisation du mot de passe
// Étape A : 6 cases OTP (code SMS reçu)
// Étape B : Saisie du nouveau mot de passe (affiché inline après vérification OTP)
// ─────────────────────────────────────────────────────────────────────────────
class OtpResetPasswordScreen extends StatefulWidget {
  final String phoneNumber;     // numéro formaté affiché à l'utilisateur
  final String verificationId;  // ID Firebase obtenu lors de l'envoi du SMS

  const OtpResetPasswordScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  State<OtpResetPasswordScreen> createState() => _OtpResetPasswordScreenState();
}

class _OtpResetPasswordScreenState extends State<OtpResetPasswordScreen>
    with TickerProviderStateMixin {
  // ── OTP ─────────────────────────────────────────────────────────────────────
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  late String _currentVerificationId;
  bool _isVerifying = false;
  bool _isResending = false;
  int  _resendSeconds = 60;
  Timer? _resendTimer;

  // ── État de l'écran ──────────────────────────────────────────────────────────
  // Phase A : saisie OTP / Phase B : saisie nouveau mot de passe
  bool _otpVerified   = false;
  bool _isSaving      = false;
  bool _showSuccess   = false;

  // ── Mot de passe ─────────────────────────────────────────────────────────────
  final _newPwdCtrl     = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool  _obscureNew     = true;
  bool  _obscureConfirm = true;

  // ── Animations ────────────────────────────────────────────────────────────────
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
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Timer renvoi OTP
  // ─────────────────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Helpers OTP
  // ─────────────────────────────────────────────────────────────────────────────
  String get _otpCode => _otpControllers.map((c) => c.text).join();
  bool   get _isOtpComplete => _otpCode.length == 6;

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
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
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        if (_isOtpComplete) _verifyOtp();
      }
    } else {
      if (index > 0) _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  void _clearOtp() {
    for (final c in _otpControllers) c.clear();
    setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNodes[0].requestFocus());
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Étape A : Vérifier le code OTP
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    if (!_isOtpComplete || _isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      // On vérifie juste que le code OTP est valide via Firebase Auth.
      // On récupère le credential mais on ne se connecte pas encore —
      // verifyOtpAndResetPassword() s'en chargera.
      final svc = PhoneAuthService();
      await svc.verifyOtp(
        verificationId: _currentVerificationId,
        smsCode: _otpCode,
      );

      if (!mounted) return;

      // OTP valide → passer à la phase B (saisie du nouveau mot de passe)
      setState(() {
        _isVerifying = false;
        _otpVerified = true;
      });

      // Focus sur le champ nouveau mot de passe
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus(FocusNode());
      });
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Étape B : Sauvegarder le nouveau mot de passe
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _saveNewPassword() async {
    final pwd     = _newPwdCtrl.text.trim();
    final confirm = _confirmPwdCtrl.text.trim();

    if (pwd.length < 6) {
      _showError('Minimum 6 caractères requis.');
      return;
    }
    if (pwd != confirm) {
      _showError('Les mots de passe ne correspondent pas.');
      return;
    }

    setState(() => _isSaving = true);

    final auth = context.read<app_auth.AuthProvider>();
    final ok = await auth.verifyOtpAndResetPassword(
      verificationId: _currentVerificationId,
      smsCode: _otpCode,
      newPassword: pwd,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      // Animation succès
      setState(() => _showSuccess = true);
      await _successAnimCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      // Retour à l'écran de connexion avec snackbar succès
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mot de passe mis à jour ! Connectez-vous.',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      _showError(auth.error ?? 'Erreur lors de la mise à jour.');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Renvoi de l'OTP
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _resendOtp() async {
    if (_resendSeconds > 0 || _isResending) return;
    setState(() => _isResending = true);
    _clearOtp();

    final svc = PhoneAuthService();
    await svc.resendOtp(
      phoneNumber: widget.phoneNumber,
      onCodeSent: (verificationId, _) {
        if (!mounted) return;
        setState(() {
          _currentVerificationId = verificationId;
          _isResending = false;
        });
        _startResendTimer();
        _showSuccessSnack('Nouveau code envoyé !');
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Snackbars
  // ─────────────────────────────────────────────────────────────────────────────
  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccessSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
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
          onPressed: (_isVerifying || _isSaving)
              ? null
              : () => Navigator.of(context).pop(),
        ),
        title: Text(
          _otpVerified ? 'Nouveau mot de passe' : 'Vérification SMS',
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppTheme.textPrimary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: _otpVerified ? _buildPasswordPhase() : _buildOtpPhase(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Phase A : Saisie OTP
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildOtpPhase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),

        // Icône SMS
        Container(
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
                  offset: const Offset(0, 8)),
            ],
          ),
          child: const Icon(Icons.sms_rounded, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 24),

        const Text('Code de vérification',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        const Text('Code envoyé au',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(widget.phoneNumber,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor)),
        const SizedBox(height: 28),

        // ── Carte OTP ──────────────────────────────────────────────────────────
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
                  offset: const Offset(0, 4)),
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

            // Bouton Valider le code
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_isOtpComplete && !_isVerifying) ? _verifyOtp : null,
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
                            color: Colors.white, strokeWidth: 2.5))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Valider le code',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 20),

            // Renvoi
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                _resendSeconds > 0
                    ? 'Renvoyer dans $_resendSeconds s'
                    : 'Pas reçu le code ?',
                style: const TextStyle(
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
          label: const Text('Modifier le numéro',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Phase B : Nouveau mot de passe
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildPasswordPhase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),

        // Icône succès OTP ou lock
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
                            offset: const Offset(0, 8)),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 44),
                  ),
                )
              : Container(
                  key: const ValueKey('lock'),
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: AppTheme.successColor.withValues(alpha: 0.3),
                        width: 2),
                  ),
                  child: const Icon(Icons.lock_open_rounded,
                      color: AppTheme.successColor, size: 40),
                ),
        ),
        const SizedBox(height: 24),

        Text(
          _showSuccess ? 'Mot de passe mis à jour !' : 'Nouveau mot de passe',
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Code OTP vérifié avec succès.\nChoisissez un nouveau mot de passe.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5),
        ),
        const SizedBox(height: 28),

        if (!_showSuccess) ...[
          // ── Carte formulaire ─────────────────────────────────────────────────
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
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(children: [
              // Champ nouveau mot de passe
              TextField(
                controller: _newPwdCtrl,
                obscureText: _obscureNew,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  labelStyle:
                      const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: AppTheme.accentColor, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.textSecondary,
                        size: 20),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppTheme.accentColor, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),

              // Champ confirmation
              TextField(
                controller: _confirmPwdCtrl,
                obscureText: _obscureConfirm,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  labelStyle:
                      const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: AppTheme.accentColor, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppTheme.textSecondary,
                        size: 20),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppTheme.accentColor, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),

              // Bouton enregistrer
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveNewPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppTheme.successColor.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Enregistrer le mot de passe',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Case OTP individuelle (même style que OtpRegisterScreen)
  // ─────────────────────────────────────────────────────────────────────────────
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
          color: isFocused
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
            color: AppTheme.primaryColor,
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
