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

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.role == 'admin';
  bool get isAnnonceur => _currentUser?.role == 'annonceur';
  bool get isDemandeur => _currentUser?.role == 'demandeur';

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
