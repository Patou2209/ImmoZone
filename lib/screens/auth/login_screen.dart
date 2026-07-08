import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import 'register_screen.dart';
import 'otp_reset_password_screen.dart';
import '../admin/admin_home_screen.dart';
import '../public/home/public_home_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _phoneCtrl   = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool  _obscure     = true;

  // Indicatif pays sélectionné
  String _countryCode = '+243';

  // ── Compteur de tentatives OTP mot de passe oublié ────────────────────────
  // Max 5 tentatives par session, puis blocage 10 minutes
  static const int _maxOtpAttempts   = 5;
  int   _otpAttemptCount  = 0;
  DateTime? _otpBlockedUntil;

  /// Retourne null si non bloqué, sinon le nombre de secondes restantes
  int? _otpBlockedSecondsRemaining() {
    if (_otpBlockedUntil == null) return null;
    final remaining = _otpBlockedUntil!.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      // Blocage expiré → réinitialiser
      _otpBlockedUntil  = null;
      _otpAttemptCount  = 0;
      return null;
    }
    return remaining;
  }

  String get _fullPhone =>
      '$_countryCode${_phoneCtrl.text.trim()}';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Connexion ─────────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithPhone(
        _fullPhone, _passwordCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      // Tous les rôles admin (admin, admin_financier, admin_service_client)
      // sont redirigés vers /admin — AdminHomeScreen affiche l'écran approprié
      //
      // NOTE: context.go() échoue sur Web quand LoginScreen est ouvert via
      // Navigator.push (modal). On utilise pushAndRemoveUntil pour garantir
      // la navigation dans tous les contextes (web + mobile).
      if (auth.isAnyAdmin) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
          (_) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PublicHomeScreen()),
          (_) => false,
        );
      }
    } else {
      _showError(auth.error ?? 'Numéro ou mot de passe incorrect.');
    }
  }

  // ── Mot de passe oublié — Envoi OTP puis navigation vers OtpResetPasswordScreen
  //
  // PROBLÈME CLEF : Firebase verifyPhoneNumber() est non-bloquante.
  // Le callback onCodeSent() arrive APRÈS le retour de await sendOtpForPasswordReset().
  // Solution : Completer<String?> — bloque jusqu'à ce que Firebase appelle onCodeSent
  // ou onFailed, puis showDialog retourne le verificationId via Navigator.pop(id).
  Future<void> _forgotPassword() async {
    // ── Vérifier si l'utilisateur est bloqué ─────────────────────────────────
    final blockedSecs = _otpBlockedSecondsRemaining();
    if (blockedSecs != null) {
      final mins = (blockedSecs / 60).ceil();
      await showDialog<void>(
        context: context,
        builder: (dCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.timer_outlined, color: AppTheme.warningColor, size: 24),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('Trop de demandes',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
          ]),
          content: Text(
            'Vous avez atteint le maximum de $_maxOtpAttempts demandes.\n\n'
            'Veuillez patienter encore $mins minute${mins > 1 ? 's' : ''} avant de réessayer.',
            style: const TextStyle(
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
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    final phoneCtrl = TextEditingController(text: _phoneCtrl.text.trim());
    String selectedCode = _countryCode;

    // showDialog retourne le verificationId via pop(verificationId), ou null si annulé
    final verificationId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // État local du dialog
        bool isSending = false;

        return StatefulBuilder(
          builder: (ctx2, setS) => StatefulBuilder(
            builder: (_, setSB) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: AppTheme.primaryColor, size: 22),
                ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text('Mot de passe oublié',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 17)),
                ),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Saisissez votre numéro de téléphone. Un code SMS de vérification vous sera envoyé.',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.5),
                  ),
                  // Compteur de tentatives (affiché dès la 1ère utilisation)
                  if (_otpAttemptCount > 0) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: _otpAttemptCount >= _maxOtpAttempts - 1
                            ? AppTheme.warningColor
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Tentative $_otpAttemptCount/$_maxOtpAttempts',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _otpAttemptCount >= _maxOtpAttempts - 1
                                ? AppTheme.warningColor
                                : AppTheme.textSecondary),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Row(children: [
                      _codeButton(selectedCode, () async {
                        final picked = await _pickCountryCode(ctx2);
                        if (picked != null) setS(() => selectedCode = picked);
                      }),
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Numéro (ex : 812345678)',
                            hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: AppTheme.textHint),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  if (isSending) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(ctx).pop(null),
                  child: const Text('Annuler',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final number = phoneCtrl.text.trim();
                          if (number.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Veuillez saisir votre numéro.',
                                    style: TextStyle(fontFamily: 'Poppins')),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          final String full;
                          if (number.startsWith('+') ||
                              number.startsWith('00')) {
                            full = number.replaceAll(RegExp(r'^00'), '+');
                          } else {
                            full = '$selectedCode$number';
                          }
                          setSB(() => isSending = true);

                          final auth = context.read<AuthProvider>();

                          // ── ÉTAPE 0 : vérifier si le numéro a un compte ──────
                          // sendOtpForPasswordReset() retourne false immédiatement
                          // si aucun compte Firestore n'est associé à ce numéro.
                          // On intercepte ce cas AVANT d'envoyer quoi que ce soit.
                          bool accountExists = true;
                          // Pré-vérification légère : on tente l'envoi et on
                          // capture le retour false = compte inexistant.
                          final completerPre = Completer<String?>();
                          final sentOk = await auth.sendOtpForPasswordReset(
                            fullPhone: full,
                            onCodeSent: (vId, _) {
                              if (!completerPre.isCompleted) completerPre.complete(vId);
                            },
                            onFailed: (FirebaseAuthException e) {
                              if (!completerPre.isCompleted) completerPre.complete(null);
                            },
                          );

                          if (!sentOk) {
                            // Numéro inconnu — alerte immédiate, pas d'OTP envoyé
                            accountExists = false;
                            if (ctx.mounted) setSB(() => isSending = false);
                            if (ctx.mounted) {
                              await showDialog<void>(
                                context: ctx,
                                builder: (dCtx) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  title: Row(children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.errorColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.person_off_outlined,
                                          color: AppTheme.errorColor, size: 22),
                                    ),
                                    const SizedBox(width: 10),
                                    const Flexible(
                                      child: Text('Aucun compte trouvé',
                                          style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16)),
                                    ),
                                  ]),
                                  content: const Text(
                                    'Aucun compte ImmoZone n\'est associé à ce numéro de téléphone.\n\n'
                                    'Vérifiez le numéro saisi ou créez un nouveau compte.',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        height: 1.5),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(dCtx).pop(),
                                      child: const Text('Fermer',
                                          style: TextStyle(
                                              fontFamily: 'Poppins',
                                              color: AppTheme.textSecondary)),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.of(dCtx).pop();
                                        Navigator.of(ctx).pop(null);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: const Text('Créer un compte',
                                          style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return;
                          }

                          // ── Compte trouvé : incrémenter tentatives + attendre OTP ──
                          _otpAttemptCount++;
                          final remainingAttempts =
                              _maxOtpAttempts - _otpAttemptCount;

                          // Attendre que Firebase appelle le callback (max 120 s)
                          final vId = await completerPre.future.timeout(
                            const Duration(seconds: 120),
                            onTimeout: () => null,
                          );

                          if (!ctx.mounted) return;
                          setSB(() => isSending = false);

                          if (vId != null && accountExists) {
                            // Succès : réinitialiser le compteur
                            _otpAttemptCount = 0;
                            _otpBlockedUntil = null;
                            Navigator.of(ctx).pop(vId);
                          } else {
                            // Erreur — bloquer si max atteint
                            if (_otpAttemptCount >= _maxOtpAttempts) {
                              _otpBlockedUntil = DateTime.now()
                                  .add(const Duration(minutes: 10));
                            }

                            final errMsg = auth.error ??
                                'Échec de l\'envoi du SMS. Réessayez.';
                            final isTooMany = errMsg.contains('Trop de') ||
                                errMsg.contains('too-many') ||
                                errMsg.contains('tentatives') ||
                                _otpAttemptCount >= _maxOtpAttempts;

                            // Message adapté selon le contexte
                            String displayMsg;
                            if (_otpAttemptCount >= _maxOtpAttempts) {
                              displayMsg =
                                  'Vous avez atteint le maximum de $_maxOtpAttempts demandes.\n\n'
                                  'Attendez 10 minutes avant de réessayer.';
                            } else if (isTooMany) {
                              displayMsg =
                                  'Ce numéro a reçu trop de codes récemment.\n\n'
                                  'Attendez environ 10 minutes et réessayez.\n\n'
                                  'Tentatives restantes : $remainingAttempts sur $_maxOtpAttempts';
                            } else {
                              displayMsg = errMsg +
                                  (remainingAttempts > 0
                                      ? '\n\nTentatives restantes : $remainingAttempts sur $_maxOtpAttempts'
                                      : '');
                            }

                            if (ctx.mounted) {
                              await showDialog<void>(
                                context: ctx,
                                builder: (dCtx) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  title: Row(children: [
                                    Icon(
                                      isTooMany
                                          ? Icons.timer_outlined
                                          : Icons.error_outline_rounded,
                                      color: isTooMany
                                          ? AppTheme.warningColor
                                          : AppTheme.errorColor,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        isTooMany ? 'Trop de demandes' : 'Envoi impossible',
                                        style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16)),
                                    ),
                                  ]),
                                  content: Text(displayMsg,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 13,
                                          height: 1.5)),
                                  actions: [
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.of(dCtx).pop();
                                        // Si max atteint → fermer aussi le dialog principal
                                        if (_otpAttemptCount >= _maxOtpAttempts
                                            && ctx.mounted) {
                                          Navigator.of(ctx).pop(null);
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                      child: const Text('OK',
                                          style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Envoyer le code',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      },
    );

    final fullPhone = _buildFullPhone(phoneCtrl.text.trim(), selectedCode);
    phoneCtrl.dispose();

    // Annulation ou échec → s'arrêter ici
    if (!mounted || verificationId == null) return;

    // ─── ÉTAPES 2 & 3 : Page dédiée OTP + nouveau mot de passe ───────────────
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpResetPasswordScreen(
          phoneNumber: fullPhone,
          verificationId: verificationId,
        ),
      ),
    );
  }

  // Reconstitue le numéro complet (utilisé après dispose du controller)
  String _buildFullPhone(String number, String code) {
    if (number.startsWith('+') || number.startsWith('00')) {
      return number.replaceAll(RegExp(r'^00'), '+');
    }
    return '$code$number';
  }

  // ── Sélecteur d'indicatif pays ────────────────────────────────────────────
  Future<String?> _pickCountryCode(
      BuildContext parentCtx) async {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered =
        List.from(AppConstants.countryCodes);
    String? picked;

    await showModalBottomSheet(
      context: parentCtx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          void onSearch(String q) {
            setModal(() {
              filtered = AppConstants.countryCodes
                  .where((c) =>
                      (c['country'] ?? '')
                          .toLowerCase()
                          .contains(q.toLowerCase()) ||
                      (c['code'] ?? '').contains(q))
                  .toList();
            });
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.70,
            maxChildSize: 0.92,
            minChildSize: 0.40,
            builder: (_, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Column(children: [
                Container(
                  margin: const EdgeInsets.symmetric(
                      vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.dividerColor,
                      borderRadius:
                          BorderRadius.circular(2)),
                ),
                const Text('Indicatif pays',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un pays…',
                      hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13),
                      prefixIcon: const Icon(
                          Icons.search,
                          color: AppTheme.accentColor),
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12),
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
                      final c = filtered[i];
                      final isSel =
                          c['code'] == _countryCode;
                      return ListTile(
                        onTap: () {
                          picked = c['code'];
                          Navigator.pop(ctx);
                        },
                        leading: Text(c['flag'] ?? '',
                            style: const TextStyle(
                                fontSize: 24)),
                        title: Text(c['country'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: isSel
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontSize: 14,
                                color: isSel
                                    ? AppTheme.accentColor
                                    : AppTheme
                                        .textPrimary)),
                        trailing: Text(c['code'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight:
                                    FontWeight.w700,
                                fontSize: 13,
                                color: isSel
                                    ? AppTheme.accentColor
                                    : AppTheme
                                        .textSecondary)),
                        tileColor: isSel
                            ? AppTheme.accentColor
                                .withValues(alpha: 0.07)
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
    return picked;
  }

  void _showCountryPicker() async {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered =
        List.from(AppConstants.countryCodes);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          void onSearch(String q) {
            setModal(() {
              filtered = AppConstants.countryCodes
                  .where((c) =>
                      (c['country'] ?? '')
                          .toLowerCase()
                          .contains(q.toLowerCase()) ||
                      (c['code'] ?? '').contains(q))
                  .toList();
            });
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.70,
            maxChildSize: 0.92,
            minChildSize: 0.40,
            builder: (_, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Column(children: [
                Container(
                  margin: const EdgeInsets.symmetric(
                      vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.dividerColor,
                      borderRadius:
                          BorderRadius.circular(2)),
                ),
                const Text('Indicatif pays',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un pays…',
                      hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13),
                      prefixIcon: const Icon(
                          Icons.search,
                          color: AppTheme.accentColor),
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12),
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
                      final c = filtered[i];
                      final isSel =
                          c['code'] == _countryCode;
                      return ListTile(
                        onTap: () {
                          setState(() =>
                              _countryCode = c['code']!);
                          Navigator.pop(ctx);
                        },
                        leading: Text(c['flag'] ?? '',
                            style: const TextStyle(
                                fontSize: 24)),
                        title: Text(c['country'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: isSel
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontSize: 14,
                                color: isSel
                                    ? AppTheme.accentColor
                                    : AppTheme
                                        .textPrimary)),
                        trailing: Text(c['code'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight:
                                    FontWeight.w700,
                                fontSize: 13,
                                color: isSel
                                    ? AppTheme.accentColor
                                    : AppTheme
                                        .textSecondary)),
                        tileColor: isSel
                            ? AppTheme.accentColor
                                .withValues(alpha: 0.07)
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final selected = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _countryCode,
      orElse: () => AppConstants.countryCodes.first,
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 16),
          child: Column(children: [
            const SizedBox(height: 32),

            // ── Logo (cliquable → accueil) ─────────────────────────────
            MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
              onTap: () => context.go('/public'),
              child: LayoutBuilder(builder: (ctx, _) {
                final w = MediaQuery.of(ctx).size.width;
                final logoW = w < 480 ? 180.0 : w < 768 ? 210.0 : w < 1024 ? 240.0 : 280.0;
                return Image.asset(
                  'assets/images/immozone_logo_text.png',
                  width: logoW,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: logoW * 0.14,
                          fontWeight: FontWeight.w800),
                      children: const [
                        TextSpan(text: 'Immo',
                            style: TextStyle(color: Color(0xFF2B5BE8))),
                        TextSpan(text: 'Zone',
                            style: TextStyle(color: Color(0xFFED5C1F))),
                      ],
                    ),
                  ),
                );
              }),
            )),
            const SizedBox(height: 28),

            // ── Carte formulaire ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppTheme.accentColor
                        .withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                  const Text('Connexion',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 4),
                  const Text(
                      'Connectez-vous avec votre numéro de téléphone',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 22),

                  // ── Champ Téléphone ─────────────────────────────────
                  const Text('Numéro de téléphone',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.dividerColor),
                    ),
                    child: Row(children: [
                      // Bouton indicatif
                      MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                        onTap: _showCountryPicker,
                        child: _codeButton(
                            _countryCode, null,
                            flag: selected['flag']),
                      )),
                      // Numéro sans indicatif
                      Expanded(
                        child: TextFormField(
                          controller: _phoneCtrl,
                          keyboardType:
                              TextInputType.phone,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13),
                          decoration: const InputDecoration(
                            hintText:
                                'Numéro (ex : 812345678)',
                            hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                color: AppTheme.textHint,
                                fontSize: 12),
                            border: InputBorder.none,
                            enabledBorder:
                                InputBorder.none,
                            focusedBorder:
                                InputBorder.none,
                            errorBorder: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14),
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty
                                  ? 'Numéro requis'
                                  : null,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),

                  // ── Champ Mot de passe ──────────────────────────────
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: AppTheme.accentColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppTheme.textSecondary,
                            size: 20),
                        onPressed: () => setState(
                            () => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.length < 4
                            ? 'Mot de passe trop court'
                            : null,
                  ),

                  // ── Mot de passe oublié ─────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize:
                            MaterialTapTargetSize
                                .shrinkWrap,
                      ),
                      child: const Text(
                          'Mot de passe oublié ?',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentColor)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Bouton Se connecter ─────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          auth.isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          side: const BorderSide(
                              color: AppTheme.accentColor,
                              width: 1.5),
                        ),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(
                                      color: AppTheme
                                          .accentColor,
                                      strokeWidth: 2))
                          : const Text('Se connecter',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight:
                                      FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 18),

            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              const Text('Pas encore de compte ? ',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontFamily: 'Poppins')),
              TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const RegisterScreen())),
                child: const Text('S\'inscrire',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  // ── Bouton indicatif pays ─────────────────────────────────────────────────
  Widget _codeButton(String code, VoidCallback? onTap,
      {String? flag}) {
    final entry = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == code,
      orElse: () => AppConstants.countryCodes.first,
    );
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
              right:
                  BorderSide(color: AppTheme.dividerColor)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(flag ?? entry['flag'] ?? '',
              style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 4),
          Text(code,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.accentColor)),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down,
              color: AppTheme.accentColor, size: 18),
        ]),
      ),
    ));
  }


}
