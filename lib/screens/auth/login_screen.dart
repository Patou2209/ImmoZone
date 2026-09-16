import 'dart:async';

import '../../core/utils/phone_utils.dart';

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

  // Normalisation intelligente : supprime le 0 national que l'utilisateur
  // ajoute souvent par habitude alors que l'indicatif (+243) est déjà là.
  // Ex: saisie '0812345678' → +243812345678 (et non +2430812345678).
  String get _fullPhone =>
      '$_countryCode${PhoneUtils.normalizeLocal(_phoneCtrl.text)}';

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
                    'Saisissez votre numéro de téléphone. Un code de vérification vous sera envoyé sur WhatsApp.',
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
                            // Supprime le 0 national saisi par habitude
                            full = '$selectedCode${PhoneUtils.normalizeLocal(number)}';
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
                                'Échec de l\'envoi du code WhatsApp. Réessayez.';
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
    // Supprime le 0 national saisi par habitude (081... → 81...)
    return '$code${PhoneUtils.normalizeLocal(number)}';
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

  // ───────────────────────────────────────────────────────────────────────────
  // Design « Premium bandeau marque » :
  //  - Bandeau dégradé bleu marine avec logo + slogan + cercles décoratifs
  //  - Panneau blanc à grands coins arrondis remontant sur le bandeau
  //  - Champs soulignés d'un trait fin (aucune bordure ni carte)
  //  - Bouton pilule dégradé bleu
  //  - Accents orange ImmoZone (#F06428) : « Zone » du logo, lien mot de
  //    passe oublié, lien inscription
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final selected = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _countryCode,
      orElse: () => AppConstants.countryCodes.first,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // top:false → le dégradé du bandeau s'étend sous la barre de statut
        // (le contenu du bandeau a son propre SafeArea interne).
        // bottom:true → rien ne passe sous la barre de navigation système.
        top: false,
        child: SingleChildScrollView(
        child: Column(children: [
          // ── Bandeau marque dégradé ────────────────────────────────────
          _brandHeader(context),

          // ── Panneau formulaire (fond blanc, sans carte ni bordure) ────
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Connexion',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 4),
                const Text('Heureux de vous revoir !',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 26),

                // ── Champ Téléphone (souligné) ─────────────────────────
                const Text('Numéro de téléphone',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.2)),
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: AppTheme.dividerColor, width: 1.5)),
                  ),
                  child: Row(children: [
                    // Bouton indicatif (sans séparateur vertical)
                    MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _showCountryPicker,
                          child: _codeButton(_countryCode, null,
                              flag: selected['flag']),
                        )),
                    // Numéro sans indicatif
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        // Enter → passe au champ mot de passe
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).nextFocus(),
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Numéro (ex : 812345678)',
                          hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              color: AppTheme.textHint,
                              fontSize: 12.5),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 15),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Numéro requis'
                            : null,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),

                // ── Champ Mot de passe (souligné) ──────────────────────
                const Text('Mot de passe',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.2)),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  // Enter → soumet le formulaire (même effet que « Se connecter »)
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!context.read<AuthProvider>().isLoading) _login();
                  },
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Votre mot de passe',
                    hintStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        color: AppTheme.textHint,
                        fontSize: 12.5),
                    filled: false,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 15),
                    border: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AppTheme.dividerColor, width: 1.5)),
                    enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AppTheme.dividerColor, width: 1.5)),
                    focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AppTheme.primaryColor, width: 1.5)),
                    errorBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AppTheme.errorColor, width: 1.5)),
                    focusedErrorBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AppTheme.errorColor, width: 1.5)),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppTheme.textHint,
                          size: 20),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => v == null || v.length < 4
                      ? 'Mot de passe trop court'
                      : null,
                ),
                const SizedBox(height: 8),

                // ── Mot de passe oublié (orange ImmoZone) ──────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _forgotPassword,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Mot de passe oublié ?',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.orangeColor)),
                  ),
                ),
                const SizedBox(height: 22),

                // ── Bouton pilule dégradé « Se connecter » ─────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xFF082F75),
                          AppTheme.primaryColor,
                          Color(0xFF1656C9),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(27),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor
                              .withValues(alpha: 0.32),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27)),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: const [
                                Text('Se connecter',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: Colors.white)),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 18, color: Colors.white),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Lien inscription ───────────────────────────────────
                Center(
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                              builder: (_) => const RegisterScreen())),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('S\'inscrire',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppTheme.orangeColor)),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ]),
        ),
      ),
    );
  }

  // ── Bandeau marque : dégradé bleu + logo + slogan + coins arrondis ────────
  Widget _brandHeader(BuildContext context) {
    return Stack(children: [
      // Fond dégradé avec cercles décoratifs
      Container(
        width: double.infinity,
        height: 252,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF082F75),
              AppTheme.primaryColor,
              Color(0xFF1656C9),
            ],
          ),
        ),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          // Cercles décoratifs subtils
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 70,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.orangeColor.withValues(alpha: 0.18),
              ),
            ),
          ),
          // Logo + slogan
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 34, 28, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Logo texte cliquable → accueil public
                MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => context.go('/public'),
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              height: 1.1),
                          children: [
                            TextSpan(
                                text: 'Immo',
                                style: TextStyle(color: Colors.white)),
                            TextSpan(
                                text: 'Zone',
                                style: TextStyle(
                                    color: AppTheme.orangeColor)),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: 10),
                Text(
                  'La 1ère plateforme de l\'immobilier en RD Congo et au Congo Brazzaville',
                  softWrap: true,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      height: 1.45,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              ]),
            ),
          ),
        ]),
      ),
      // Bande blanche arrondie qui remonte sur le bandeau
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          height: 28,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
        ),
      ),
    ]);
  }

  // ── Bouton indicatif pays (sans bordure, style souligné) ──────────────────
  Widget _codeButton(String code, VoidCallback? onTap, {String? flag}) {
    final entry = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == code,
      orElse: () => AppConstants.countryCodes.first,
    );
    return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 2, vertical: 15),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(flag ?? entry['flag'] ?? '',
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 5),
              Text(code,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: AppTheme.primaryColor)),
              const Icon(Icons.arrow_drop_down,
                  color: AppTheme.textHint, size: 18),
            ]),
          ),
        ));
  }


}
