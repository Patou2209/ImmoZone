import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/data_service.dart';

class AuthProvider extends ChangeNotifier {
  final DataService _dataService = DataService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  // ── Phone OTP state ──────────────────────────────────────────────────────
  String? _phoneVerificationId;
  bool _codeSent = false;
  bool _otpVerifying = false;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.role == 'admin';
  bool get isAnnonceur => _currentUser?.role == 'annonceur';
  bool get isDemandeur => _currentUser?.role == 'demandeur';
  bool get codeSent => _codeSent;
  bool get otpVerifying => _otpVerifying;

  Future<void> checkAuth() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      final user = await _dataService.loginById(firebaseUser.uid);
      _currentUser = user;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user?.uid;
      if (uid == null) {
        _error = 'Erreur d\'authentification';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final user = await _dataService.loginById(uid);
      if (user != null) {
        _currentUser = user;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Profil utilisateur introuvable';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on FirebaseAuthException catch (e) {
      _error = _mapFirebaseError(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Une erreur est survenue';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    String? category,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user?.uid;
      if (uid == null) {
        _error = 'Erreur de création de compte';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final user = await _dataService.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
        role: role,
        category: category,
        uid: uid,
      );
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _mapFirebaseError(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } on FirebaseException catch (e) {
      // Erreur Firestore (permissions, réseau, etc.)
      if (e.code == 'permission-denied') {
        // Le compte Auth est créé mais Firestore a refusé — on continue quand même
        // car le profil sera recréé au prochain login via loginById
        final firebaseUser = _auth.currentUser;
        if (firebaseUser != null) {
          _currentUser = null; // pas de profil local pour l'instant
          _error = null;
          _isLoading = false;
          notifyListeners();
          // Retenter l'écriture du profil après un court délai
          Future.delayed(const Duration(seconds: 2), () async {
            try {
              final retryUser = await _dataService.register(
                name: name,
                email: email,
                phone: phone,
                password: password,
                role: role,
                category: category,
                uid: firebaseUser.uid,
              );
              if (retryUser != null) {
                _currentUser = retryUser;
                notifyListeners();
              }
            } catch (_) {}
          });
          return true; // Auth réussie, profil en cours de création
        }
      }
      _error = 'Erreur réseau ou de base de données. Réessayez.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Une erreur est survenue. Réessayez.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ── Connexion par numéro de téléphone (étape 1 : envoi OTP) ────────────────
  Future<void> sendPhoneOtp(String fullPhoneNumber) async {
    _isLoading = true;
    _error = null;
    _codeSent = false;
    notifyListeners();
    await _auth.verifyPhoneNumber(
      phoneNumber: fullPhoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential cred) async {
        // Auto-résolution (Android uniquement)
        await _signInWithPhoneCredential(cred);
      },
      verificationFailed: (FirebaseAuthException e) {
        _error = _mapPhoneError(e.code);
        _isLoading = false;
        _codeSent = false;
        notifyListeners();
      },
      codeSent: (String verificationId, int? resendToken) {
        _phoneVerificationId = verificationId;
        _isLoading = false;
        _codeSent = true;
        notifyListeners();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _phoneVerificationId = verificationId;
      },
    );
  }

  // ── Connexion par numéro de téléphone (étape 2 : vérification OTP) ─────────
  Future<bool> verifyPhoneOtp(String smsCode) async {
    if (_phoneVerificationId == null) {
      _error = 'Session expirée. Veuillez réessayer.';
      notifyListeners();
      return false;
    }
    _otpVerifying = true;
    _error = null;
    notifyListeners();
    final cred = PhoneAuthProvider.credential(
      verificationId: _phoneVerificationId!,
      smsCode: smsCode,
    );
    return _signInWithPhoneCredential(cred);
  }

  Future<bool> _signInWithPhoneCredential(PhoneAuthCredential cred) async {
    try {
      final result = await _auth.signInWithCredential(cred);
      final uid = result.user?.uid;
      if (uid == null) {
        _error = 'Erreur d\'authentification';
        _isLoading = false;
        _otpVerifying = false;
        notifyListeners();
        return false;
      }
      final user = await _dataService.loginById(uid);
      if (user != null) {
        _currentUser = user;
        _isLoading = false;
        _otpVerifying = false;
        _codeSent = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Aucun compte ImmoZone associé à ce numéro.\nVeuillez vous inscrire d\'abord.';
        _isLoading = false;
        _otpVerifying = false;
        notifyListeners();
        return false;
      }
    } on FirebaseAuthException catch (e) {
      _error = _mapPhoneError(e.code);
      _isLoading = false;
      _otpVerifying = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Une erreur est survenue.';
      _isLoading = false;
      _otpVerifying = false;
      notifyListeners();
      return false;
    }
  }

  void resetPhoneAuth() {
    _phoneVerificationId = null;
    _codeSent = false;
    _otpVerifying = false;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  String _mapPhoneError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Numéro de téléphone invalide.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez plus tard.';
      case 'invalid-verification-code':
        return 'Code SMS incorrect. Vérifiez et réessayez.';
      case 'session-expired':
        return 'Code SMS expiré. Demandez un nouveau code.';
      case 'quota-exceeded':
        return 'Quota SMS dépassé. Réessayez plus tard.';
      default:
        return 'Erreur téléphone : $code';
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _dataService.logout();
    _currentUser = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    if (_currentUser != null) {
      final user = await _dataService.getUserById(_currentUser!.id);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }
    }
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email ou mot de passe incorrect';
      case 'email-already-in-use':
        return 'Cet email est déjà utilisé';
      case 'weak-password':
        return 'Mot de passe trop faible (min. 6 caractères)';
      case 'invalid-email':
        return 'Email invalide';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez plus tard.';
      case 'network-request-failed':
        return 'Erreur réseau. Vérifiez votre connexion.';
      default:
        return 'Erreur d\'authentification';
    }
  }
}
