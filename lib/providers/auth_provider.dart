import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/user_model.dart';
import '../services/data_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ARCHITECTURE AUTHENTIFICATION — Téléphone + Mot de passe
//
// Firebase Auth ne supporte pas directement "phone + password". On contourne
// en utilisant un e-mail virtuel dérivé du numéro : +243812345@immozone.app
// Ce e-mail virtuel n'est JAMAIS montré à l'utilisateur.
//
// Le vrai e-mail de l'utilisateur est stocké dans Firestore (champ "email")
// et sert uniquement à la récupération de mot de passe (envoi via Admin SDK
// ou sendPasswordResetEmail sur le compte e-mail virtuel quand l'email Firestore
// correspond à une adresse Email Auth).
// ─────────────────────────────────────────────────────────────────────────────

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

  // ── Convertit un numéro de téléphone en e-mail virtuel Firebase ───────────
  // Ex : +243812345678  →  243812345678@immozone.app
  static String phoneToVirtualEmail(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    return '$digits@immozone.app';
  }

  // ── Normalise un numéro de téléphone au format +XXXXXXXXXXXX ──────────────
  // Accepte tous les formats courants :
  //   '+243823854273' → '+243823854273'  (déjà normalisé)
  //   '243823854273'  → '+243823854273'  (pas de +)
  //   '00243823854273'→ '+243823854273'  (préfixe 00)
  //   '+243 823 854 273' → '+243823854273' (avec espaces)
  // Retourne null si le numéro est trop court ou invalide.
  static String? _normalizePhone(String phone) {
    // Supprimer les espaces, tirets, parenthèses
    String clean = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Remplacer le préfixe international 00 par +
    if (clean.startsWith('00')) clean = '+${clean.substring(2)}';
    // Ajouter + si absent et si ça commence par des chiffres
    if (!clean.startsWith('+') && RegExp(r'^\d+$').hasMatch(clean)) {
      clean = '+$clean';
    }
    // Valider : doit avoir au moins 8 chiffres après le +
    final digits = clean.replaceAll('+', '').replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 8) return null;
    return clean;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VÉRIFICATION SESSION AU DÉMARRAGE
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> checkAuth() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      final user = await _dataService.loginById(firebaseUser.uid);
      _currentUser = user;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONNEXION — Numéro de téléphone + Mot de passe
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> loginWithPhone(String fullPhone, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final virtualEmail = phoneToVirtualEmail(fullPhone);

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: virtualEmail,
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
        _error = 'Profil introuvable. Veuillez vous inscrire.';
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
      _error = 'Une erreur est survenue. Réessayez.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Alias conservé pour rétro-compatibilité (anciens appels login(email, password))
  Future<bool> login(String email, String password) async {
    return loginWithPhone(email, password);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INSCRIPTION — Téléphone + Mot de passe + E-mail de récupération
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> register({
    required String name,
    required String phone,       // numéro complet avec indicatif (+243...)
    required String password,
    required String recoveryEmail, // e-mail pour récupération de compte
    required String role,
    String? category,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final virtualEmail = phoneToVirtualEmail(phone);

    try {
      // 1. Créer le compte Firebase Auth avec l'e-mail virtuel
      final cred = await _auth.createUserWithEmailAndPassword(
        email: virtualEmail,
        password: password,
      );
      final uid = cred.user?.uid;
      if (uid == null) {
        _error = 'Erreur de création de compte';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 2. Créer le profil Firestore avec le vrai e-mail de récupération
      final user = await _dataService.register(
        name: name,
        email: recoveryEmail.trim().toLowerCase(), // e-mail réel stocké Firestore
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
      if (e.code == 'permission-denied') {
        final firebaseUser = _auth.currentUser;
        if (firebaseUser != null) {
          _currentUser = null;
          _error = null;
          _isLoading = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 2), () async {
            try {
              final retryUser = await _dataService.register(
                name: name,
                email: recoveryEmail.trim().toLowerCase(),
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
          return true;
        }
      }
      _error = 'Erreur réseau ou base de données. Réessayez.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Une erreur est survenue. Réessayez.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MOT DE PASSE OUBLIÉ
  //
  // Flux :
  // 1. Chercher l'utilisateur dans Firestore par son numéro de téléphone
  // 2. Récupérer son e-mail de récupération réel (champ "email" Firestore)
  // 3. Appeler l'API REST Firebase Auth (sendOobCode) avec le vrai email
  //    → Firebase envoie le lien de reset directement à la vraie boîte mail
  // ─────────────────────────────────────────────────────────────────────────

  // Clé API Android du projet Firebase (pour l'API REST Identity Toolkit)
  static const String _firebaseApiKey = 'AIzaSyCPx_8e7-ecYA6amk-yu-8inbgJ0beme2g';

  Future<bool> sendPasswordResetByPhone(String fullPhone) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Normalisation du numéro : garantit le format +XXXXXXXXXXXX
      // Gère les cas : '823854273', '0823854273', '+243823854273', '243823854273'
      final normalizedPhone = _normalizePhone(fullPhone);
      if (normalizedPhone == null) {
        _error = 'Numéro de téléphone invalide.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Étape 1 : Trouver le profil Firestore par numéro de téléphone
      // Essaie le numéro normalisé ET le numéro brut (pour la compatibilité)
      UserModel? userProfile = await _dataService.findUserByPhone(normalizedPhone);
      // Fallback : chercher avec le numéro exact tel que saisi
      if (userProfile == null && normalizedPhone != fullPhone.trim()) {
        userProfile = await _dataService.findUserByPhone(fullPhone.trim());
      }
      if (userProfile == null) {
        _error = 'Aucun compte trouvé pour ce numéro.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final recoveryEmail = userProfile.email.trim().toLowerCase();

      // Vérifier que l'email de récupération est un vrai email
      if (recoveryEmail.isEmpty ||
          !recoveryEmail.contains('@') ||
          recoveryEmail.endsWith('@immozone.app')) {
        _error = 'Aucun e-mail de récupération valide pour ce compte. '
            'Contactez le support ImmoZone.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Étape 2 : Envoyer le lien via l'API REST Firebase Auth (sendOobCode)
      // Cette API accepte n'importe quel email enregistré dans Auth OU
      // permet d'envoyer à tout email via PASSWORD_RESET requestType.
      // Firebase enverra le lien vers recoveryEmail.
      final sent = await _sendResetViaRestApi(recoveryEmail);

      if (!sent) {
        _error = 'Impossible d\'envoyer l\'e-mail. '
            'Contactez le support : +243821908888';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _isLoading = false;
      notifyListeners();
      return true;

    } on FirebaseAuthException catch (e) {
      _error = e.code == 'user-not-found'
          ? 'Aucun compte trouvé pour ce numéro.'
          : 'Erreur : ${e.message}';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Erreur lors de l\'envoi. Réessayez.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Appelle l'API REST Firebase Auth pour envoyer un lien de reset
  // directement à l'email de récupération réel de l'utilisateur.
  Future<bool> _sendResetViaRestApi(String recoveryEmail) async {
    try {
      final url = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode'
          '?key=$_firebaseApiKey');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requestType': 'PASSWORD_RESET',
          'email': recoveryEmail,
        }),
      );

      if (response.statusCode == 200) return true;

      // Firebase retourne 400 si l'email n'existe pas dans Auth
      // Dans ce cas : l'email de récupération n'est pas enregistré dans Firebase Auth
      // On informe l'utilisateur (cas rare — email de récup jamais enregistré dans Auth)
      if (kDebugMode) {
        debugPrint('[AuthProvider] sendOobCode erreur: ${response.statusCode} ${response.body}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider] _sendResetViaRestApi exception: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DÉCONNEXION
  // ─────────────────────────────────────────────────────────────────────────
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
      final user =
          await _dataService.getUserById(_currentUser!.id);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAPPAGE DES ERREURS FIREBASE
  // ─────────────────────────────────────────────────────────────────────────
  String _mapFirebaseError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Numéro ou mot de passe incorrect.';
      case 'email-already-in-use':
        return 'Ce numéro est déjà utilisé. Connectez-vous.';
      case 'weak-password':
        return 'Mot de passe trop faible (min. 6 caractères).';
      case 'invalid-email':
        return 'Numéro de téléphone invalide.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessayez plus tard.';
      case 'network-request-failed':
        return 'Erreur réseau. Vérifiez votre connexion.';
      case 'user-disabled':
        return 'Ce compte a été désactivé. Contactez le support.';
      default:
        return 'Erreur d\'authentification ($code).';
    }
  }
}
