import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PhoneAuthService — gère le flux Firebase Phone Auth (SMS OTP)
//
// Flux Android (APK release signé) :
//  1. verifyPhoneNumber()  → Play Integrity vérifie l'app silencieusement
//  2. Firebase envoie le SMS OTP directement (aucune WebView, aucun reCAPTCHA)
//  3. Si auto-retrieval possible → onAutoVerified() déclenché automatiquement
//  4. Sinon → onCodeSent() → l'utilisateur saisit le code manuellement
//  5. verifyOtp() → crée le UserCredential Firebase
//
// NOTE : forceRecaptchaFlow: false est appliqué dans main.dart au démarrage.
// ─────────────────────────────────────────────────────────────────────────────

class PhoneAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  int?    _resendToken;

  String? get verificationId => _verificationId;

  // ── Lancer la vérification du numéro ─────────────────────────────────────
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(UserCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException e) onFailed,
    required void Function(String verificationId) onTimeout,
    // 120 secondes : laisse le temps à Play Integrity de répondre avant timeout
    Duration timeout = const Duration(seconds: 120),
    bool isResend = false,
  }) async {
    if (kDebugMode) {
      debugPrint('[PhoneAuthService] verifyPhoneNumber: $phoneNumber isResend=$isResend');
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: timeout,

      // Android auto-retrieval : Firebase récupère le code automatiquement
      verificationCompleted: (PhoneAuthCredential credential) async {
        if (kDebugMode) debugPrint('[PhoneAuthService] verificationCompleted (auto-retrieval)');
        try {
          final userCred = await _auth.signInWithCredential(credential);
          onAutoVerified(userCred);
        } on FirebaseAuthException catch (e) {
          onFailed(e);
        }
      },

      verificationFailed: (FirebaseAuthException e) {
        if (kDebugMode) {
          debugPrint('[PhoneAuthService] verificationFailed: ${e.code} — ${e.message}');
        }
        onFailed(e);
      },

      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken    = resendToken;
        if (kDebugMode) {
          debugPrint('[PhoneAuthService] codeSent verificationId=$verificationId resendToken=$resendToken');
        }
        onCodeSent(verificationId, resendToken);
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        if (kDebugMode) debugPrint('[PhoneAuthService] codeAutoRetrievalTimeout');
        _verificationId = verificationId;
        onTimeout(verificationId);
      },

      // forceResendingToken : utilisé uniquement pour les renvois
      forceResendingToken: isResend ? _resendToken : null,
    );
  }

  // ── Vérifier le code OTP saisi par l'utilisateur ─────────────────────────
  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return await _auth.signInWithCredential(credential);
  }

  // ── Renvoi du SMS (utilise forceResendingToken pour éviter reCAPTCHA) ─────
  Future<void> resendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException e) onFailed,
  }) async {
    await verifyPhoneNumber(
      phoneNumber: phoneNumber,
      onCodeSent:    onCodeSent,
      onAutoVerified: (_) {},
      onFailed:       onFailed,
      onTimeout:      (_) {},
      isResend:       true,   // utilise le token de renvoi stocké
    );
  }

  // ── Mapper les erreurs Firebase Phone Auth ────────────────────────────────
  static String mapPhoneAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Numéro de téléphone invalide. Vérifiez le format.';
      case 'too-many-requests':
        return 'Trop de tentatives sur ce numéro. Attendez 10 à 30 minutes avant de réessayer.';
      case 'quota-exceeded':
        return 'Quota SMS dépassé. Contactez le support.';
      case 'invalid-verification-code':
        return 'Code incorrect. Vérifiez le SMS et réessayez.';
      case 'invalid-verification-id':
        return 'Session expirée. Recommencez la vérification.';
      case 'session-expired':
        return 'Le code a expiré. Demandez un nouveau SMS.';
      case 'network-request-failed':
        return 'Erreur réseau. Vérifiez votre connexion.';
      case 'missing-phone-number':
        return 'Numéro de téléphone manquant.';
      case 'captcha-check-failed':
        return 'Vérification échouée. Réessayez.';
      case 'app-not-authorized':
        return 'Application non autorisée. Contactez le support.';
      default:
        return 'Erreur : ${e.message ?? e.code}';
    }
  }
}
