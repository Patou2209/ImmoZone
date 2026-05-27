import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PhoneAuthService — gère le flux Firebase Phone Auth (SMS OTP)
//
// Flux Android :
//  1. verifyPhoneNumber()  → Firebase envoie un SMS (sans reCAPTCHA)
//  2. Si auto-retrieval possible → onAutoVerified() appelé automatiquement
//  3. Sinon → onCodeSent()  → l'utilisateur saisit le code
//  4. verifyOtp()          → crée/récupère le UserCredential Firebase
//
// NOTE RECAPTCHA :
//  Sur Android, Firebase utilise SafetyNet/Play Integrity pour vérifier l'app
//  sans afficher de reCAPTCHA visible. Le reCAPTCHA visible n'apparaît que si
//  SafetyNet échoue (APK non signé ou émulateur).
//  → Solution : s'assurer que l'APK est bien signé (release build).
//  → Sur l'appareil physique avec APK release signé : pas de reCAPTCHA visible.
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
    Duration timeout = const Duration(seconds: 60),
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

      // forceResendingToken uniquement pour les renvois (évite reCAPTCHA inutile)
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
        return 'Trop de tentatives. Réessayez dans quelques minutes.';
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
