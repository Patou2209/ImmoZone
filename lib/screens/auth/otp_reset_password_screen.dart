import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/phone_auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OtpResetPasswordScreen — Écran unique OTP + nouveau mot de passe
//
// LOGIQUE IMPORTANTE :
//   Firebase PhoneAuthCredential est à usage unique.
//   Si on appelle signInWithCredential() pour "vérifier" dans la Phase A,
//   le credential est consommé → "session-expired" en Phase B.
//
//   Solution : Firebase est appelé UNE SEULE FOIS lors de la soumission finale.
//   L'écran affiche d'abord les 6 cases OTP, puis (quand rempli) révèle
//   les champs mot de passe inline — sans aucun appel Firebase intermédiaire.
// ─────────────────────────────────────────────────────────────────────────────
class OtpResetPasswordScreen extends StatefulWidget {
  final String phoneNumber;    // numéro formaté affiché à l'utilisateur
  final String verificationId; // ID Firebase obtenu lors de l'envoi du SMS

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

  // ── OTP ──────────────────────────────────────────────────────────────────────
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  late String _currentVerificationId;
  bool _isResending    = false;
  int  _resendSeconds  = 90;
  Timer? _resendTimer;
  bool _showNoSmsHint  = false;

  // ── État de l'écran ───────────────────────────────────────────────────────────
  // Quand les 6 chiffres sont saisis, on révèle les champs mot de passe
  bool _otpComplete  = false; // true dès que les 6 chiffres sont remplis
  bool _isSaving     = false;
  bool _showSuccess  = false;

  // ── Mot de passe ─────────────────────────────────────────────────────────────
  final _newPwdCtrl     = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool  _obscureNew     = true;
  bool  _obscureConfirm = true;

  // ── Animations ────────────────────────────────────────────────────────────────
  late AnimationController _successAnimCtrl;
  late Animation<double>   _successAnim;

  // ScrollController pour descendre automatiquement quand les champs mdp apparaissent
  final ScrollController _scrollCtrl = ScrollController();

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
    _scrollCtrl.dispose();
    for (final c in _otpControllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Timer renvoi OTP
  // ─────────────────────────────────────────────────────────────────────────────
  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds  = 90;
      _showNoSmsHint  = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 1) {
        t.cancel();
        if (mounted) { setState(() {
          _resendSeconds = 0;
          _showNoSmsHint = true;
        }); }
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Helpers OTP
  // ─────────────────────────────────────────────────────────────────────────────
  String get _otpCode =>
      _otpControllers.map((c) => c.text).join();

  void _onOtpChanged(int index, String value) {
    // Gestion paste (6 chiffres collés d'un coup)
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 6) {
        for (int i = 0; i < 6; i++) {
          _otpControllers[i].text = digits[i];
        }
        _focusNodes[5].unfocus();
        _onOtpFilled();
        return;
      }
    }
    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        // Dernier chiffre saisi : révéler les champs mot de passe
        if (_otpCode.length == 6) _onOtpFilled();
      }
    } else {
      if (index > 0) _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  // Appelé quand les 6 cases sont remplies — révèle les champs mot de passe
  void _onOtpFilled() {
    if (_otpCode.length < 6) return;
    setState(() => _otpComplete = true);
    // Scroll vers les champs mot de passe
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearOtp() {
    for (final c in _otpControllers) { c.clear(); }
    setState(() => _otpComplete = false);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNodes[0].requestFocus());
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Soumission finale : vérifier OTP + sauvegarder le nouveau mot de passe
  // Firebase est appelé UNE SEULE FOIS ici.
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _saveNewPassword() async {
    final code    = _otpCode;
    final pwd     = _newPwdCtrl.text.trim();
    final confirm = _confirmPwdCtrl.text.trim();

    if (code.length < 6) {
      _showError('Veuillez saisir le code à 6 chiffres.');
      return;
    }
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
    // Un seul appel Firebase : verifyOtp() + updatePassword()
    final ok = await auth.verifyOtpAndResetPassword(
      verificationId: _currentVerificationId,
      smsCode: code,
      newPassword: pwd,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      setState(() => _showSuccess = true);
      await _successAnimCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mot de passe mis à jour ! Connectez-vous.',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final errMsg = auth.error ?? 'Erreur de vérification.';
      final isExpired = errMsg.contains('expiré') ||
          errMsg.contains('expired') ||
          errMsg.contains('session') ||
          errMsg.contains('Session') ||
          errMsg.contains('invalide') ||
          errMsg.contains('invalid-verification');
      if (isExpired) {
        // Code expiré ou session invalide → effacer l'OTP et montrer un message clair
        _clearOtp();
        _showErrorDialog(
          titre: 'Code expiré',
          message:
              'Le code SMS a expiré (valide 5 minutes).\n\nAppuyez sur "Renvoyer le code SMS" pour recevoir un nouveau code, puis saisissez-le rapidement.',
          icone: Icons.timer_off_rounded,
        );
      } else {
        _showError(errMsg);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Renvoi OTP — passe par AuthProvider.sendOtpForPasswordReset() pour réutiliser
  // l'instance PhoneAuthService qui possède le _resendToken original.
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _resendOtp() async {
    if (_resendSeconds > 0 || _isResending) return;
    setState(() => _isResending = true);
    _clearOtp();

    final auth = context.read<app_auth.AuthProvider>();
    await auth.sendOtpForPasswordReset(
      fullPhone: widget.phoneNumber,
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
  // Helpers UI
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

  Future<void> _showErrorDialog({
    required String titre,
    required String message,
    required IconData icone,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(icone, color: AppTheme.errorColor, size: 24),
          const SizedBox(width: 10),
          Flexible(
            child: Text(titre,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ),
        ]),
        content: Text(message,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 13, height: 1.5)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
          onPressed:
              _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          _showSuccess
              ? 'Succès'
              : _otpComplete
                  ? 'Nouveau mot de passe'
                  : 'Vérification SMS',
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppTheme.textPrimary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),

              // ── Icône (change selon l'état) ────────────────────────────────
              _buildHeaderIcon(),
              const SizedBox(height: 20),

              // ── Titre / sous-titre ─────────────────────────────────────────
              _buildHeaderText(),
              const SizedBox(height: 24),

              // ── Carte OTP ──────────────────────────────────────────────────
              _buildOtpCard(),
              const SizedBox(height: 16),

              // ── Banner aide SMS non reçu ───────────────────────────────────
              if (_showNoSmsHint && !_otpComplete) _buildNoSmsHint(),

              // ── Champs mot de passe (apparaissent après 6 chiffres) ────────
              if (_otpComplete && !_showSuccess) ...[
                const SizedBox(height: 8),
                _buildPasswordCard(),
                const SizedBox(height: 16),
              ],

              // ── Bouton modifier le numéro ──────────────────────────────────
              if (!_showSuccess)
                TextButton.icon(
                  onPressed:
                      _isSaving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Modifier le numéro',
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Icône header
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildHeaderIcon() {
    if (_showSuccess) {
      return ScaleTransition(
        scale: _successAnim,
        child: Container(
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
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
        ),
      );
    }
    if (_otpComplete) {
      return Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: AppTheme.successColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: AppTheme.successColor.withValues(alpha: 0.4), width: 2),
        ),
        child: const Icon(Icons.lock_open_rounded,
            color: AppTheme.successColor, size: 40),
      );
    }
    return Container(
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Texte header
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildHeaderText() {
    if (_showSuccess) {
      return const Text('Mot de passe mis à jour !',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.successColor));
    }
    if (_otpComplete) {
      return Column(children: [
        const Text('Nouveau mot de passe',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.check_circle_rounded,
              color: AppTheme.successColor, size: 14),
          const SizedBox(width: 4),
          Text('Code saisi · ${widget.phoneNumber}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppTheme.successColor)),
        ]),
      ]);
    }
    return Column(children: [
      const Text('Code de vérification',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary)),
      const SizedBox(height: 6),
      const Text('Code envoyé au',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: AppTheme.textSecondary)),
      const SizedBox(height: 2),
      Text(widget.phoneNumber,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor)),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Carte OTP
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildOtpCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: (_otpComplete ? AppTheme.successColor : AppTheme.accentColor)
                .withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: [
        Text(
          _otpComplete
              ? 'Code saisi avec succès'
              : 'Saisissez le code à 6 chiffres',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _otpComplete
                  ? AppTheme.successColor
                  : AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),

        // 6 cases OTP
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (i) => _buildOtpBox(i)),
        ),

        if (!_otpComplete) ...[
          const SizedBox(height: 20),

          // Bouton renvoyer
          if (_resendSeconds > 0)
            Text(
              'Renvoyer dans ${_resendSeconds >= 60 ? "${_resendSeconds ~/ 60}m${_resendSeconds % 60 > 0 ? " ${_resendSeconds % 60}s" : ""}" : "$_resendSeconds s"}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppTheme.textSecondary),
            )
          else
            _isResending
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                    onTap: _resendOtp,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded,
                              color: AppTheme.primaryColor, size: 16),
                          const SizedBox(width: 6),
                          Text('Renvoyer le code SMS',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryColor)),
                        ],
                      ),
                    ),
                  )),
        ] else ...[
          const SizedBox(height: 12),
          // Lien pour modifier le code si erreur
          MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
            onTap: _clearOtp,
            child: Text('Modifier le code',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    decoration: TextDecoration.underline)),
          )),
        ],
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Carte mot de passe (révélée après saisie OTP complète)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildPasswordCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.accentColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: [
        // Nouveau mot de passe
        TextField(
          controller: _newPwdCtrl,
          obscureText: _obscureNew,
          enabled: !_isSaving,
          decoration: InputDecoration(
            labelText: 'Nouveau mot de passe',
            labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            prefixIcon: const Icon(Icons.lock_outline,
                color: AppTheme.accentColor, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureNew ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.textSecondary,
                  size: 20),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.accentColor, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 12),

        // Confirmer mot de passe
        TextField(
          controller: _confirmPwdCtrl,
          obscureText: _obscureConfirm,
          enabled: !_isSaving,
          decoration: InputDecoration(
            labelText: 'Confirmer le mot de passe',
            labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            prefixIcon: const Icon(Icons.lock_outline,
                color: AppTheme.accentColor, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.textSecondary,
                  size: 20),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.accentColor, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 20),

        // Bouton Enregistrer
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Banner aide SMS non reçu
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildNoSmsHint() {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 400),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              Text('SMS non reçu ?',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.orange.shade800)),
            ]),
            const SizedBox(height: 6),
            Text(
              '• Vérifiez que le numéro est correct\n'
              '• Le SMS peut prendre 1-2 minutes\n'
              '• Vérifiez vos messages bloqués/spam\n'
              '• Appuyez sur "Renvoyer le code SMS" ci-dessus',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  height: 1.6,
                  color: Colors.orange.shade800),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Case OTP individuelle
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildOtpBox(int index) {
    final isFilled  = _otpControllers[index].text.isNotEmpty;
    final isFocused = _focusNodes[index].hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44, height: 54,
      decoration: BoxDecoration(
        color: isFilled
            ? (_otpComplete
                ? AppTheme.successColor.withValues(alpha: 0.07)
                : AppTheme.primaryColor.withValues(alpha: 0.07))
            : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _otpComplete
              ? AppTheme.successColor
              : isFocused
                  ? AppTheme.primaryColor
                  : isFilled
                      ? AppTheme.accentColor
                      : AppTheme.dividerColor,
          width: (isFocused || _otpComplete) ? 2 : 1.5,
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
            color: _otpComplete
                ? AppTheme.successColor
                : AppTheme.primaryColor,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            counterText: '',
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) => _onOtpChanged(index, v),
          enabled: !_isSaving && !_otpComplete,
        ),
      ),
    );
  }
}
