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
  //
  // ARCHITECTURE HYBRIDE :
  //   1. Essai Email virtuel (admin + anciens comptes)
  //   2. Si échec → chercher dans Firestore par numéro (comptes Phone Auth OTP)
  //      et vérifier le mot de passe manuellement
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> loginWithPhone(String fullPhone, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final normalizedPhone = _normalizePhone(fullPhone) ?? fullPhone.trim();
    final virtualEmail    = phoneToVirtualEmail(normalizedPhone);

    // ── Tentative 1 : Email virtuel Firebase Auth (admin + anciens comptes) ─
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: virtualEmail,
        password: password,
      );
      final uid = cred.user?.uid;
      if (uid != null) {
        final user = await _dataService.loginById(uid);
        if (user != null) {
          _currentUser = user;
          _isLoading = false;
          notifyListeners();
          return true;
        }
      }
    } on FirebaseAuthException catch (e) {
      // wrong-password / invalid-credential → mauvais mot de passe → erreur directe
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'too-many-requests') {
        _error = _mapFirebaseError(e.code);
        _isLoading = false;
        notifyListeners();
        return false;
      }
      // user-not-found / invalid-email → compte email virtuel inexistant
      // → continuer vers tentative 2 (compte Phone Auth)
    } catch (_) {
      // erreur réseau ou autre → continuer vers tentative 2
    }

    // ── Tentative 2 : Compte créé via OTP (Phone Auth) ──────────────────────
    // Ces comptes n'ont pas d'email virtuel Firebase Auth.
    // On vérifie le mot de passe directement dans Firestore.
    try {
      // Chercher le profil Firestore par numéro
      UserModel? userProfile = await _dataService.findUserByPhone(normalizedPhone);
      if (userProfile == null && normalizedPhone != fullPhone.trim()) {
        userProfile = await _dataService.findUserByPhone(fullPhone.trim());
      }

      if (userProfile == null) {
        _error = 'Aucun compte trouvé pour ce numéro. Inscrivez-vous.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Vérifier le mot de passe stocké dans Firestore
      final storedPassword = await _dataService.getUserPassword(userProfile.id);
      if (storedPassword == null || storedPassword != password) {
        _error = 'Mot de passe incorrect.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Mot de passe OK → connecter sans Firebase Auth session
      // (l'utilisateur Phone Auth n'a pas de session email)
      _currentUser = userProfile;
      await _dataService.saveSessionDirectly(userProfile);
      _isLoading = false;
      notifyListeners();
      return true;

    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider.loginWithPhone] Tentative 2 erreur: $e');
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
      final firebaseUser = cred.user;
      final uid = firebaseUser?.uid;
      if (uid == null || firebaseUser == null) {
        _error = 'Erreur de création de compte';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 2. CRITIQUE : forcer le refresh du token Firebase AVANT l'écriture Firestore.
      //    Sans ça, les règles de sécurité reçoivent un token non propagé
      //    et renvoient PERMISSION_DENIED même si l'auth est valide.
      try {
        await firebaseUser.getIdToken(true);
      } catch (_) {
        // non-bloquant si le refresh échoue — on tente quand même l'écriture
      }

      // 3. Créer le profil Firestore (avec retry automatique si permission-denied)
      UserModel? user;
      int attempts = 0;
      Exception? lastError;

      while (attempts < 3) {
        attempts++;
        try {
          user = await _dataService.register(
            name: name,
            email: recoveryEmail.trim().toLowerCase(),
            phone: phone,
            password: password,
            role: role,
            category: category,
            uid: uid,
          );
          lastError = null;
          break; // succès → sortir de la boucle
        } on FirebaseException catch (e) {
          lastError = e;
          if (e.code == 'permission-denied' && attempts < 3) {
            // Attendre que le token se propage, puis re-refresh avant retry
            await Future.delayed(Duration(seconds: attempts * 2));
            try { await firebaseUser.getIdToken(true); } catch (_) {}
          } else {
            break; // autre erreur Firebase → ne pas réessayer
          }
        } catch (e) {
          lastError = Exception(e.toString());
          break; // erreur inattendue → ne pas réessayer
        }
      }

      if (user != null) {
        _currentUser = user;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Échec de l'écriture Firestore après tous les essais
      if (kDebugMode) {
        debugPrint('[AuthProvider.register] Échec Firestore après $attempts tentatives: $lastError');
      }
      // Le compte Firebase Auth a été créé mais le profil Firestore n'a pas pu être sauvegardé.
      // On redirige quand même l'utilisateur (il est authentifié) mais on log l'erreur.
      // Un background retry va tenter de créer le profil.
      _currentUser = null;
      _isLoading = false;
      notifyListeners();

      // Dernier recours : réessai en arrière-plan après 5s
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          final fbUser = _auth.currentUser;
          if (fbUser != null) {
            await fbUser.getIdToken(true);
            final retryUser = await _dataService.register(
              name: name,
              email: recoveryEmail.trim().toLowerCase(),
              phone: phone,
              password: password,
              role: role,
              category: category,
              uid: uid,
            );
            if (retryUser != null) {
              _currentUser = retryUser;
              notifyListeners();
              if (kDebugMode) debugPrint('[AuthProvider.register] Background retry réussi pour uid=$uid');
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[AuthProvider.register] Background retry échoué: $e');
        }
      });

      return true; // Auth OK, profil en cours de création

    } on FirebaseAuthException catch (e) {
      _error = _mapFirebaseError(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider.register] Erreur inattendue: $e');
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
  // CHARGEMENT D'UN UTILISATEUR APRÈS SMS OTP
  //
  // PROBLÈME : L'app utilise un système "email virtuel" pour l'auth
  // (numéro → 243821908888@immozone.app). Quand Firebase Phone Auth crée
  // un nouveau compte via OTP, son UID est DIFFÉRENT de l'UID du compte
  // email virtuel existant dans Firestore.
  //
  // SOLUTION : Chercher d'abord par UID (cas account linking ou numéro test),
  // puis fallback par numéro de téléphone dans Firestore.
  // ─────────────────────────────────────────────────────────────────────────
  Future<UserModel?> loadUserByUid(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Tentative 1 : chercher par UID Firebase direct
      final user = await _dataService.getUserById(uid);
      if (user != null) {
        _currentUser = user;
        _isLoading = false;
        notifyListeners();
        return user;
      }
      // Si non trouvé par UID → l'OTP a créé un nouveau compte Firebase
      // sans profil Firestore (cas normal avec email virtuel). On retourne
      // null ici ; le flux OTP appellera ensuite loadUserByPhone().
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider.loadUserByUid] $e');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHARGEMENT PAR NUMÉRO DE TÉLÉPHONE (fallback après OTP)
  //
  // Cherche le profil Firestore par numéro de téléphone.
  // Utilisé quand le compte Phone Auth a un UID différent du compte
  // email virtuel existant dans Firestore.
  // ─────────────────────────────────────────────────────────────────────────
  Future<UserModel?> loadUserByPhone(String phoneNumber) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Normaliser le numéro
      final normalized = _normalizePhone(phoneNumber);
      UserModel? user;

      // Chercher avec numéro normalisé
      if (normalized != null) {
        user = await _dataService.findUserByPhone(normalized);
      }
      // Fallback avec numéro brut si normalisé échoue
      if (user == null && normalized != phoneNumber) {
        user = await _dataService.findUserByPhone(phoneNumber);
      }

      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return user;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider.loadUserByPhone] $e');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INSCRIPTION PAR OTP — Phone Auth uniquement
  //
  // Appelé depuis OtpRegisterScreen après que le code SMS a été vérifié.
  // Le UserCredential est déjà signé dans Firebase Auth via verifyOtp().
  // On crée uniquement le profil Firestore pour ce nouvel utilisateur.
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> registerWithPhoneCredential({
    required UserCredential credential,
    required String name,
    required String phone,
    required String password,
    required String role,
    String? category,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final firebaseUser = credential.user;
    final uid = firebaseUser?.uid;

    if (uid == null || firebaseUser == null) {
      _error = 'Erreur d\'authentification OTP.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    try {
      // Vérifier si un profil Firestore existe déjà pour cet UID
      final existing = await _dataService.getUserById(uid);
      if (existing != null) {
        // Compte déjà créé — on charge simplement le profil
        _currentUser = existing;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Vérifier si le numéro est déjà utilisé par un autre compte
      final byPhone = await _dataService.findUserByPhone(phone);
      if (byPhone != null) {
        _error = 'Ce numéro est déjà associé à un compte. Connectez-vous.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Forcer refresh du token avant écriture Firestore
      try {
        await firebaseUser.getIdToken(true);
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {}

      // Créer le profil Firestore (email vide — architecture phone-only)
      // isVerified: true car l'OTP a déjà prouvé que le numéro appartient au user
      UserModel? user;
      int attempts = 0;
      Exception? lastError;

      while (attempts < 3) {
        attempts++;
        try {
          user = await _dataService.register(
            name: name,
            email: '',          // phone-only : pas d'email de récupération
            phone: phone,
            password: password, // stocké pour la connexion ultérieure
            role: role,
            category: category,
            uid: uid,
            isVerified: true,   // ✅ OTP validé = numéro vérifié
          );
          lastError = null;
          break;
        } on FirebaseException catch (e) {
          lastError = e;
          if (e.code == 'permission-denied' && attempts < 3) {
            await Future.delayed(Duration(seconds: attempts * 2));
            try { await firebaseUser.getIdToken(true); } catch (_) {}
          } else {
            break;
          }
        } catch (e) {
          lastError = Exception(e.toString());
          break;
        }
      }

      if (user != null) {
        _currentUser = user;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      if (kDebugMode) {
        debugPrint('[AuthProvider.registerWithPhoneCredential] Échec Firestore après $attempts tentatives: $lastError');
      }

      // Retry en arrière-plan si Firestore a échoué mais Auth est OK
      _currentUser = null;
      _isLoading = false;
      notifyListeners();

      Future.delayed(const Duration(seconds: 5), () async {
        try {
          final fbUser = _auth.currentUser;
          if (fbUser != null) {
            await fbUser.getIdToken(true);
            final retryUser = await _dataService.register(
              name: name,
              email: '',
              phone: phone,
              password: password,
              role: role,
              category: category,
              uid: uid,
              isVerified: true, // ✅ OTP validé = numéro vérifié
            );
            if (retryUser != null) {
              _currentUser = retryUser;
              notifyListeners();
              if (kDebugMode) debugPrint('[AuthProvider.registerWithPhoneCredential] Background retry réussi uid=$uid');
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[AuthProvider.registerWithPhoneCredential] Background retry échoué: $e');
        }
      });

      return true; // Auth OK, profil en cours de création en arrière-plan

    } on FirebaseAuthException catch (e) {
      _error = _mapFirebaseError(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider.registerWithPhoneCredential] Erreur: $e');
      _error = 'Erreur lors de la création du compte. Réessayez.';
      _isLoading = false;
      notifyListeners();
      return false;
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
