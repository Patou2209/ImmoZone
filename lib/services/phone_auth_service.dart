import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// PhoneAuthService — OTP par WHATSAPP (WhatsApp Business Cloud API via
// Cloud Functions) en remplacement du SMS Firebase Phone Auth, bloqué par
// Play Integrity sur la version Play Store ("Application non autorisée").
//
// Flux :
//  1. verifyPhoneNumber() → POST sendWhatsAppOtp (code 6 chiffres sur WhatsApp)
//  2. onCodeSent('wa:<msisdn>', null) — le "verificationId" transporte le numéro
//  3. verifyOtp() → POST verifyWhatsAppOtp → custom token Firebase
//  4. signInWithCustomToken() → UserCredential (même uid que l'ancien Phone Auth)
//
// L'INTERFACE PUBLIQUE EST IDENTIQUE à l'ancienne version (SMS Firebase) :
// aucun changement requis dans les écrans, hormis les textes "SMS" → "WhatsApp".
// Les erreurs sont remontées en FirebaseAuthException pour compatibilité totale.
// ─────────────────────────────────────────────────────────────────────────────

const String _kSendOtpUrl =
    'https://us-central1-immozone-d9a68.cloudfunctions.net/sendWhatsAppOtp';
const String _kVerifyOtpUrl =
    'https://us-central1-immozone-d9a68.cloudfunctions.net/verifyWhatsAppOtp';

class PhoneAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  String? _lastMsisdn;

  String? get verificationId => _verificationId;

  /// Normalise vers 243XXXXXXXXX (miroir de waNormalizeMsisdn côté fonctions).
  static String normalizeToWa(String phoneNumber) {
    var m = phoneNumber.replaceAll(RegExp(r'[\s\-]'), '');
    if (m.startsWith('+')) m = m.substring(1);
    if (m.startsWith('0') && m.length == 10) {
      m = '243${m.substring(1)}';
    } else if (m.length == 9 && !m.startsWith('243')) {
      m = '243$m';
    }
    return m;
  }

  // ── Lancer l'envoi du code WhatsApp ───────────────────────────────────────
  // Signature conservée. Avec WhatsApp il n'y a ni auto-retrieval ni timeout
  // de session côté client : onAutoVerified/onTimeout ne sont jamais appelés.
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(UserCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException e) onFailed,
    required void Function(String verificationId) onTimeout,
    Duration timeout = const Duration(seconds: 120),
    bool isResend = false,
  }) async {
    final msisdn = normalizeToWa(phoneNumber);
    if (kDebugMode) {
      debugPrint('[PhoneAuthService] sendWhatsAppOtp: $msisdn isResend=$isResend');
    }

    try {
      final resp = await http
          .post(
            Uri.parse(_kSendOtpUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phoneNumber': msisdn}),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200 && body['success'] == true) {
        _lastMsisdn = msisdn;
        _verificationId = 'wa:$msisdn';
        onCodeSent(_verificationId!, null);
        return;
      }

      // Mappage des erreurs backend → codes FirebaseAuthException compatibles
      final String errMsg = (body['error'] ?? 'Envoi impossible.').toString();
      String code;
      if (resp.statusCode == 429) {
        code = 'too-many-requests';
      } else if (body['waCode'] == 131026) {
        code = 'whatsapp-not-found';
      } else if (resp.statusCode == 400) {
        code = 'invalid-phone-number';
      } else {
        code = 'send-failed';
      }
      onFailed(FirebaseAuthException(code: code, message: errMsg));
    } catch (e) {
      if (kDebugMode) debugPrint('[PhoneAuthService] sendWhatsAppOtp error: $e');
      onFailed(FirebaseAuthException(
        code: 'network-request-failed',
        message: 'Erreur réseau. Vérifiez votre connexion.',
      ));
    }
  }

  // ── Vérifier le code saisi → connexion Firebase (custom token) ────────────
  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    // Le numéro voyage dans le verificationId ('wa:<msisdn>') pour que la
    // vérification fonctionne même depuis une autre instance du service.
    final msisdn = verificationId.startsWith('wa:')
        ? verificationId.substring(3)
        : (_lastMsisdn ?? '');
    if (msisdn.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-verification-id',
        message: 'Session expirée. Recommencez la vérification.',
      );
    }

    late http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(_kVerifyOtpUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phoneNumber': msisdn, 'code': smsCode.trim()}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw FirebaseAuthException(
        code: 'network-request-failed',
        message: 'Erreur réseau. Vérifiez votre connexion.',
      );
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;

    if (resp.statusCode == 200 && body['success'] == true) {
      // Connexion Firebase via custom token → même uid, mêmes données Firestore
      return await _auth.signInWithCustomToken(body['token'] as String);
    }

    final String errMsg = (body['error'] ?? 'Code incorrect.').toString();
    String code;
    if (errMsg.contains('expiré')) {
      code = 'session-expired';
    } else if (errMsg.contains('tentatives')) {
      code = 'too-many-requests';
    } else if (errMsg.contains('Aucun code') || errMsg.contains('déjà utilisé')) {
      code = 'invalid-verification-id';
    } else {
      code = 'invalid-verification-code';
    }
    throw FirebaseAuthException(code: code, message: errMsg);
  }

  // ── Renvoi du code WhatsApp ───────────────────────────────────────────────
  Future<void> resendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException e) onFailed,
  }) async {
    await verifyPhoneNumber(
      phoneNumber: phoneNumber,
      onCodeSent: onCodeSent,
      onAutoVerified: (_) {},
      onFailed: onFailed,
      onTimeout: (_) {},
      isResend: true,
    );
  }

  // ── Mapper les erreurs (codes SMS historiques + nouveaux codes WhatsApp) ──
  static String mapPhoneAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return e.message ?? 'Numéro de téléphone invalide. Vérifiez le format.';
      case 'too-many-requests':
        return e.message ??
            'Trop de demandes pour ce numéro.\nAttendez quelques minutes avant de réessayer.';
      case 'whatsapp-not-found':
        return 'Ce numéro ne semble pas avoir WhatsApp.\nUtilisez un numéro avec un compte WhatsApp actif.';
      case 'send-failed':
        return e.message ?? 'Envoi WhatsApp impossible. Réessayez plus tard.';
      case 'invalid-verification-code':
        return e.message ?? 'Code incorrect. Vérifiez le message WhatsApp et réessayez.';
      case 'invalid-verification-id':
        return e.message ?? 'Session expirée. Recommencez la vérification.';
      case 'session-expired':
        return e.message ?? 'Le code a expiré. Demandez un nouveau code.';
      case 'network-request-failed':
        return 'Erreur réseau. Vérifiez votre connexion.';
      case 'quota-exceeded':
        return 'Quota dépassé. Contactez le support.';
      case 'app-not-authorized':
        return 'Application non autorisée. Contactez le support.';
      default:
        return 'Erreur : ${e.message ?? e.code}';
    }
  }
}
