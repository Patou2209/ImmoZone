import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/data_service.dart';
import '../services/phone_auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ARCHITECTURE AUTHENTIFICATION — Téléphone + Mot de passe
//
// Inscription  : OTP SMS → verifyPhoneNumber() → profil Firestore
// Connexion    : numéro + mot de passe → Firestore lookup
// Mot de passe oublié : OTP SMS → verifyOtp() → update Firestore password
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

  /// Met à jour l'utilisateur courant en mémoire et notifie les listeners.
  /// Utile après modification du profil (photo, nom, etc.) sans rechargement complet.
  void updateCurrentUserLocally(UserModel updated) {
    _currentUser = updated;
    notifyListeners();
  }
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.role == 'admin';
  bool get isAdminFinancier => _currentUser?.role == 'admin_financier';
  bool get isAdminServiceClient => _currentUser?.role == 'admin_service_client';
  bool get isAdminMarketing => _currentUser?.role == 'admin_marketing';
  bool get isAnyAdmin => _currentUser?.isAdminRole ?? false;
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
  //
  // LOGIQUE :
  //   1. Si session SharedPrefs existe (isLoggedIn + userId) → recharger le
  //      profil Firestore par ID. Couvre TOUS les comptes (OTP + admin).
  //   2. Fallback : Firebase Auth currentUser (pour les comptes email virtuel
  //      dont la session Firebase est encore active).
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> checkAuth() async {
    // Priorité 1 : session locale SharedPreferences (persiste entre les lancements)
    if (_dataService.isLoggedIn && _dataService.currentUserId.isNotEmpty) {
      final user = await _dataService.getUserById(_dataService.currentUserId);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
        return;
      }
    }

    // Priorité 2 : session Firebase Auth active (admin email virtuel)
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      final user = await _dataService.loginById(firebaseUser.uid);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }
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

    try {
      // ── ÉTAPE 1 : Chercher le profil dans Firestore par numéro ──────────────
      // C'est la source de vérité unique pour TOUS les utilisateurs.
      // L'admin a aussi son profil Firestore avec son numéro.
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

      // ── ÉTAPE 2 : Vérifier le mot de passe stocké dans Firestore ────────────
      // Tous les comptes (admin inclus) ont leur mot de passe dans Firestore.
      final storedPassword = await _dataService.getUserPassword(userProfile.id);

      if (storedPassword == null || storedPassword != password) {
        _error = 'Numéro ou mot de passe incorrect.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // ── ÉTAPE 3 : Connexion réussie ──────────────────────────────────────────
      // Pour tous les rôles admin (admin, admin_financier, admin_service_client) :
      // tenter la connexion Firebase Auth (email virtuel) pour maintenir la
      // session Firebase et accéder à Firestore de façon sécurisée.
      if (userProfile.isAdminRole) {
        try {
          final virtualEmail = phoneToVirtualEmail(normalizedPhone);
          await _auth.signInWithEmailAndPassword(
            email: virtualEmail,
            password: password,
          );
        } catch (_) {
          // Non-bloquant : l'admin peut quand même accéder via session Firestore
        }
      }

      _currentUser = userProfile;
      await _dataService.saveSessionDirectly(userProfile);
      _isLoading = false;
      notifyListeners();
      return true;

    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider.loginWithPhone] Erreur: $e');
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
  // INSCRIPTION — Téléphone + Mot de passe (SANS email de récupération)
  // Conservé pour compatibilité avec les anciens appels — délègue vers
  // registerWithPhoneCredential() après OTP. Cette méthode n'est plus appelée
  // directement dans le flux d'inscription normal (OTP via register_screen.dart).
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> register({
    required String name,
    required String phone,       // numéro complet avec indicatif (+243...)
    required String password,
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

      // 2. Forcer le refresh du token Firebase AVANT l'écriture Firestore.
      try {
        await firebaseUser.getIdToken(true);
      } catch (_) {}

      // 3. Créer le profil Firestore (avec retry automatique si permission-denied)
      UserModel? user;
      int attempts = 0;
      Exception? lastError;

      while (attempts < 3) {
        attempts++;
        try {
          user = await _dataService.register(
            name: name,
            email: '',           // phone-only : pas d'email de récupération
            phone: phone,
            password: password,
            role: role,
            category: category,
            uid: uid,
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
        debugPrint('[AuthProvider.register] Échec Firestore après $attempts tentatives: $lastError');
      }
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

      return true;

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
  // MOT DE PASSE OUBLIÉ — Étape 1 : vérifier que le numéro existe
  //
  // Flux OTP SMS :
  //   1. findUserByPhone() → vérifier que le compte existe
  //   2. sendOtpForPasswordReset() → PhoneAuthService.verifyPhoneNumber()
  //   3. verifyOtpAndResetPassword() → vérifier l'OTP + update Firestore
  // ─────────────────────────────────────────────────────────────────────────

  // Garde une référence sur l'utilisateur en cours de reset (entre étapes)
  UserModel? _resetUser;
  UserModel? get resetUser => _resetUser;

  // Étape 1 : Vérifier que le numéro existe et envoyer l'OTP
  Future<bool> sendOtpForPasswordReset({
    required String fullPhone,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException e) onFailed,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final normalizedPhone = _normalizePhone(fullPhone);
    if (normalizedPhone == null) {
      _error = 'Numéro de téléphone invalide.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Vérifier que le compte existe dans Firestore
    UserModel? userProfile = await _dataService.findUserByPhone(normalizedPhone);
    if (userProfile == null && normalizedPhone != fullPhone.trim()) {
      userProfile = await _dataService.findUserByPhone(fullPhone.trim());
    }
    if (userProfile == null) {
      _error = 'Aucun compte trouvé pour ce numéro.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Mémoriser l'utilisateur pour l'étape 3
    _resetUser = userProfile;

    _isLoading = false;
    notifyListeners();

    // Envoyer le SMS OTP
    final svc = PhoneAuthService();
    await svc.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      onCodeSent: onCodeSent,
      onAutoVerified: (_) {}, // non utilisé dans ce flux
      onFailed: (e) {
        _error = PhoneAuthService.mapPhoneAuthError(e);
        notifyListeners();
        onFailed(e);
      },
      onTimeout: (_) {},
    );
    return true;
  }

  // Étape 3 : Vérifier l'OTP puis mettre à jour le mot de passe dans Firestore
  //
  // IMPORTANT — Gestion du conflit de session Firebase :
  //   signInWithCredential() échoue avec "session-expired" si un autre compte
  //   Firebase est déjà connecté (même anonyme). On déconnecte d'abord Firebase
  //   Auth, on vérifie le code OTP, puis on restaure la session Firestore
  //   depuis SharedPreferences (checkAuth() gère ça via _dataService).
  Future<bool> verifyOtpAndResetPassword({
    required String verificationId,
    required String smsCode,
    required String newPassword,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    if (_resetUser == null) {
      _error = 'Session expirée. Recommencez depuis le début.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Sauvegarder le profil utilisateur avant toute déconnexion Firebase
    final userToUpdate = _resetUser!;

    try {
      // ── Étape A : Déconnecter Firebase Auth pour éviter les conflits ─────────
      // signInWithCredential() peut échouer avec "session-expired" si un compte
      // Firebase est déjà actif (email virtuel, anonymous, etc.).
      try {
        await _auth.signOut();
      } catch (_) {
        // Non-bloquant : si signOut échoue, on continue quand même
      }

      // ── Étape B : Vérifier le code OTP via Firebase Phone Auth ───────────────
      final svc = PhoneAuthService();
      await svc.verifyOtp(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      // ── Étape C : OTP valide → mettre à jour le mot de passe dans Firestore ──
      final updated = await _dataService.updateUserPassword(
          userToUpdate.id, newPassword);

      if (!updated) {
        // Restaurer la session si la mise à jour Firestore échoue
        _currentUser = userToUpdate;
        _resetUser = null;
        _error = 'Impossible de mettre à jour le mot de passe. Réessayez.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // ── Étape D : Nettoyer l'état ─────────────────────────────────────────────
      // _currentUser est intentionnellement laissé intact :
      // si l'utilisateur était connecté (rôle admin), la session Firestore
      // SharedPrefs reste valide et checkAuth() la restaurera au prochain démarrage.
      _resetUser = null;
      _isLoading = false;
      notifyListeners();
      return true;

    } on FirebaseAuthException catch (e) {
      // Restaurer la session Firestore même en cas d'erreur Firebase
      _currentUser ??= userToUpdate;
      _error = PhoneAuthService.mapPhoneAuthError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider.verifyOtpAndResetPassword] Erreur: $e');
      _currentUser ??= userToUpdate;
      _error = 'Erreur lors de la vérification. Réessayez.';
      _isLoading = false;
      notifyListeners();
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
    String? sponsorCode,
    String? province,
    String? city,
    String? commune,
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
            sponsorCode: sponsorCode,
            province: province,
            city: city,
            commune: commune,
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
              province: province,
              city: city,
              commune: commune,
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
