import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/property_model.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../models/quota_model.dart';
import '../models/ad_model.dart';

import '../models/payment_model.dart';
import '../models/credit_model.dart';
import '../models/report_model.dart';
import '../models/audit_log_model.dart';
import '../models/app_notification_model.dart';
import '../models/parrain_model.dart';
import '../models/platform_stats_model.dart';
import '../core/constants/app_constants.dart';

class DataService {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  SharedPreferences? _prefs;

  // Collections Firestore
  CollectionReference get _propertiesCol => _db.collection('properties');
  CollectionReference get _usersCol => _db.collection('users');
  /// Accès public à la collection users — utilisé par ex. dans property_detail
  /// pour lire le champ brut 'createdAt' sans passer par UserModel.fromMap.
  CollectionReference get usersCollection => _db.collection('users');
  CollectionReference get _creditsCol => _db.collection('credits');
  CollectionReference get _notificationsCol => _db.collection('notifications');
  CollectionReference get _messagesCol => _db.collection('messages');
  CollectionReference get _paymentsCol => _db.collection('payments');
  CollectionReference get _reportsCol => _db.collection('reports');
  CollectionReference get _logsCol => _db.collection('audit_logs');
  CollectionReference get _contactLogsCol => _db.collection('contact_logs');
  CollectionReference get _quotasCol => _db.collection('quotas');
  DocumentReference get _settingsDoc => _db.collection('config').doc('system_settings');
  CollectionReference get _parrainCol => _db.collection('parrains');
  CollectionReference get _adsCol => _db.collection('ads');
  DocumentReference get _zonesDoc => _db.collection('config').doc('geographic_zones');
  DocumentReference get _zonesConfigDoc => _db.collection('config').doc('zones_config');
  DocumentReference get _paymentMethodsDoc => _db.collection('config').doc('payment_methods');
  DocumentReference get _packsDoc => _db.collection('config').doc('subscription_packs');
  DocumentReference get _contactsDoc => _db.collection('config').doc('admin_contacts');
  DocumentReference get _officialMsgDoc => _db.collection('config').doc('official_message');
  DocumentReference get _rechargeTiersDoc => _db.collection('config').doc('recharge_promo_tiers');

  // ─── INIT ────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Refresh settings and packs from Firestore at startup
    await _refreshSettingsCache();
    await _refreshPacksCache();
    await _refreshRechargeTiersCache();
  }

  // ─── SESSION LOCALE (SharedPreferences) ─────────────────────────────────────
  // L'auth session est gérée par Firebase Auth + SharedPreferences pour accès sync

  bool get isLoggedIn => _prefs?.getBool(AppConstants.keyIsLoggedIn) ?? false;
  String get currentUserId => _prefs?.getString(AppConstants.keyUserId) ?? '';
  String get currentUserRole => _prefs?.getString(AppConstants.keyUserRole) ?? '';
  String get currentUserName => _prefs?.getString(AppConstants.keyUserName) ?? '';
  String get currentUserEmail => _prefs?.getString(AppConstants.keyUserEmail) ?? '';

  Future<void> _saveSession(UserModel user) async {
    await _prefs?.setString(AppConstants.keyUserId, user.id);
    await _prefs?.setString(AppConstants.keyUserName, user.name);
    await _prefs?.setString(AppConstants.keyUserEmail, user.email);
    await _prefs?.setString(AppConstants.keyUserRole, user.role);
    await _prefs?.setBool(AppConstants.keyIsLoggedIn, true);
    // ── Cache du profil complet pour survie aux refreshs web (Firestore lent) ──
    try {
      await _prefs?.setString('cached_user_profile', jsonEncode(user.toMap()));
    } catch (_) {}
  }

  Future<void> _clearSession() async {
    await _prefs?.remove(AppConstants.keyUserId);
    await _prefs?.remove(AppConstants.keyUserName);
    await _prefs?.remove(AppConstants.keyUserEmail);
    await _prefs?.remove(AppConstants.keyUserRole);
    await _prefs?.setBool(AppConstants.keyIsLoggedIn, false);
    await _prefs?.remove('cached_user_profile');
  }

  /// Retourne le profil mis en cache lors du dernier login (fallback réseau).
  UserModel? getCachedUser() {
    final raw = _prefs?.getString('cached_user_profile');
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserModel.fromMap(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
  }

  // ─── PARAMÈTRES SYSTÈME ────────────────────────────────────────────────────

  Map<String, dynamic> _defaultSettings() => {
    'free_trial_enabled': false,
    'price_unit_publication': 2.0,
    'price_monthly_sub': 2.0,
    'price_annual_sub': 20.0,
    'home_title': 'Trouvez Votre\nMaison de Rêve',
    'home_subtitle': 'Des milliers de propriétés à votre portée',
    'pack_3_discount': 5.0,
    'pack_5_discount': 10.0,
    'pack_10_discount': 15.0,
    'pack_50_discount': 20.0,
    'boost_week_price': 1.0,
    'boost_month_price': 5.0,
    'monthly_free_quota': 3,
    'free_quota_count': 3,   // Nombre d'annonces gratuites offertes au nouvel utilisateur
    'free_quota_days': 30,   // Durée (en jours) de validité de chaque annonce gratuite
    'max_photos': 5,
    'min_photos': 1,
    'announcement_validity_days': 30,
    'default_publication_credits': 1,
    'credits_per_dollar': 10,
  };

  Future<Map<String, dynamic>> _getSettings() async {
    try {
      final snap = await _settingsDoc.get();
      if (snap.exists) return Map<String, dynamic>.from(snap.data() as Map);
    } catch (_) {}
    return _defaultSettings();
  }

  Map<String, dynamic> get systemSettings {
    // Retourne les settings en cache local ou defaults (sync getter)
    final raw = _prefs?.getString('system_settings_cache');
    if (raw != null) {
      try { return Map<String, dynamic>.from(jsonDecode(raw)); } catch (_) {}
    }
    return _defaultSettings();
  }

  /// Getter public async pour lire les settings depuis Firestore (ou cache).
  Future<Map<String, dynamic>> getSettingsMap() => _getSettings();

  Future<void> _refreshSettingsCache() async {
    final s = await _getSettings();
    await _prefs?.setString('system_settings_cache', jsonEncode(s));
  }

  Future<void> _refreshPacksCache() async {
    try {
      final snap = await _packsDoc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        final packs = (data['packs'] as List?)?.cast<Map<String, dynamic>>();
        if (packs != null && packs.isNotEmpty) {
          await _prefs?.setString('packs_cache', jsonEncode(packs));
        }
      }
    } catch (_) {}
  }

  /// Public method to refresh packs cache from Firestore (called when packs screen opens)
  Future<void> refreshPacksFromFirestore() => _refreshPacksCache();

  Future<void> _refreshRechargeTiersCache() async {
    try {
      final snap = await _rechargeTiersDoc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        final tiers = (data['tiers'] as List?)?.cast<Map<String, dynamic>>();
        if (tiers != null) {
          await _prefs?.setString('recharge_tiers_cache', jsonEncode(tiers));
        }
      }
    } catch (_) {}
  }

  bool get isFreeTrial => systemSettings['free_trial_enabled'] == true;
  bool get isPromoActive => systemSettings['promo_active'] == true;
  int get promoFreeAnnouncements =>
      (systemSettings['promo_free_announcements'] as num?)?.toInt() ?? 2;

  /// Titre affiché dans le hero de la page d'accueil (configurable depuis l'admin)
  String get homeTitle =>
      systemSettings['home_title'] as String? ??
      _prefs?.getString('home_title_cache') ??
      'Trouvez Votre\nMaison de Rêve';

  /// Sous-titre affiché dans le hero de la page d'accueil (configurable depuis l'admin)
  String get homeSubtitle =>
      systemSettings['home_subtitle'] as String? ??
      _prefs?.getString('home_subtitle_cache') ??
      'Des milliers de propriétés à votre portée';

  /// Met à jour le texte d'accueil (titre + sous-titre)
  Future<void> updateHomeText({required String title, required String subtitle}) async {
    await updateSettings({
      'home_title': title,
      'home_subtitle': subtitle,
    });
    await _prefs?.setString('home_title_cache', title);
    await _prefs?.setString('home_subtitle_cache', subtitle);
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    final current = await _getSettings();
    current.addAll(settings);
    await _settingsDoc.set(current, SetOptions(merge: true));
    await _prefs?.setString('system_settings_cache', jsonEncode(current));
  }

  Future<void> toggleFreeTrial(bool enable) async {
    await updateSettings({'free_trial_enabled': enable});
  }

  Future<Map<String, dynamic>> launchPromotion({
    required int freeAnnouncements,
    String reason = 'Promotion administrative',
    String? targetCountry,
    String? targetCity,
    String? targetZone, // Zone de publication : Standard / Intermédiaire / Premium / Luxe
  }) async {
    // Build promo scope label
    String scope = 'global';
    if (targetZone != null && targetZone.isNotEmpty) {
      scope = 'zone:$targetZone';
      if (targetCity != null && targetCity.isNotEmpty) scope += ':city:$targetCity';
      else if (targetCountry != null && targetCountry.isNotEmpty) scope += ':country:$targetCountry';
    } else if (targetCity != null && targetCity.isNotEmpty) {
      scope = 'city:$targetCity';
    } else if (targetCountry != null && targetCountry.isNotEmpty) {
      scope = 'country:$targetCountry';
    }

    await updateSettings({
      'promo_active': true,
      'promo_free_announcements': freeAnnouncements,
      'promo_reason': reason,
      'promo_launched_at': DateTime.now().toIso8601String(),
      'promo_scope': scope,
    });
    final users = await getUsers();
    int credited = 0;
    for (final user in users) {
      if (user.role == 'admin') continue;
      // Zone-based filtering: match users whose commune belongs to targetZone
      if (targetZone != null && targetZone.isNotEmpty) {
        final userZone = getZoneStanding(user.commune ?? '');
        if (userZone != targetZone) continue;
        // Additionally filter by city if specified
        if (targetCity != null && targetCity.isNotEmpty) {
          if ((user.city ?? '').toLowerCase() != targetCity.toLowerCase()) continue;
        }
      } else if (targetCity != null && targetCity.isNotEmpty) {
        if ((user.city ?? '').toLowerCase() != targetCity.toLowerCase()) continue;
      }
      // Note: country filter is informational only (users don't have country field yet)
      // Create a promo quota (year=8888 = push admin promo marker)
      final promoQuota = QuotaModel(
        id: 'quota_push_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        year: 8888,   // marqueur «quota push admin»
        month: 0,
        freeQuota: freeAnnouncements,
        usedFreeQuota: 0,
        resetDate: DateTime.now().add(const Duration(days: 365)),
      );
      await _quotasCol.doc(promoQuota.id).set(promoQuota.toMap());

      // Envoyer une notification à l'utilisateur avec les détails de la promotion
      final annoncePlural = freeAnnouncements > 1 ? 's' : '';
      await addNotification(AppNotification(
        id: 'notif_promo_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        type: 'promo',
        title: 'Promotion ImmoZone !',
        body: 'Félicitations ! Vous bénéficiez de $freeAnnouncements annonce$annoncePlural gratuite$annoncePlural offerte${annoncePlural.isEmpty ? '' : 's'} — $reason',
        createdAt: DateTime.now(),
      ));

      credited++;
    }
    return {'credited_users': credited, 'free_ads_per_user': freeAnnouncements};
  }

  Future<void> suspendPromotion() async {
    await updateSettings({
      'promo_active': false,
      'promo_suspended_at': DateTime.now().toIso8601String(),
    });
  }

  // ─── PROMOTIONS PAR PALIERS DE RECHARGE ────────────────────────────────────

  /// Paliers par défaut (3 niveaux configurables)
  static List<Map<String, dynamic>> _defaultRechargeTiers() => [
    {
      'enabled': true,
      'minAmount': 20.0,
      'maxAmount': 49.0,  // -1 = pas de plafond (dernier palier)
      'bonusCreditPct': 10,  // pourcentage de crédits bonus (0–100)
      'bonusFreeAds': 2,     // annonces gratuites offertes (0–5)
      'label': 'Palier 1',
      'targetCountry': null,
      'targetCity': null,
      'targetZone': null,
    },
    {
      'enabled': true,
      'minAmount': 50.0,
      'maxAmount': 99.0,
      'bonusCreditPct': 25,
      'bonusFreeAds': 3,
      'label': 'Palier 2',
      'targetCountry': null,
      'targetCity': null,
      'targetZone': null,
    },
    {
      'enabled': true,
      'minAmount': 100.0,
      'maxAmount': -1.0,   // pas de plafond
      'bonusCreditPct': 50,
      'bonusFreeAds': 5,
      'label': 'Palier 3',
      'targetCountry': null,
      'targetCity': null,
      'targetZone': null,
    },
  ];

  /// Retourne les paliers depuis le cache local (accès synchrone)
  List<Map<String, dynamic>> get rechargeTiers {
    final raw = _prefs?.getString('recharge_tiers_cache');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        return list.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    return _defaultRechargeTiers();
  }

  /// Active / désactive la promo par paliers globalement
  bool get isRechargeTiersPromoActive =>
      systemSettings['recharge_tiers_promo_active'] == true;

  /// Charge les paliers depuis Firestore et met à jour le cache
  Future<List<Map<String, dynamic>>> loadRechargeTiers() async {
    try {
      final snap = await _rechargeTiersDoc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        final list = (data['tiers'] as List?)?.cast<Map<String, dynamic>>()
            ?? _defaultRechargeTiers();
        await _prefs?.setString('recharge_tiers_cache', jsonEncode(list));
        return list;
      }
    } catch (_) {}
    return _defaultRechargeTiers();
  }

  /// Sauvegarde les paliers en Firestore + cache local
  Future<void> saveRechargeTiers(List<Map<String, dynamic>> tiers) async {
    await _rechargeTiersDoc.set({'tiers': tiers});
    await _prefs?.setString('recharge_tiers_cache', jsonEncode(tiers));
  }

  /// Active ou désactive la promo par paliers
  Future<void> setRechargeTiersPromoActive(bool active) async {
    await updateSettings({'recharge_tiers_promo_active': active});
  }

  /// Retourne le palier correspondant au montant donné (null si aucun match ou promo inactive)
  /// [userCommune] sert au filtrage optionnel par zone
  Map<String, dynamic>? getMatchingTier(double amountUsd, {String userCommune = ''}) {
    if (!isRechargeTiersPromoActive) return null;
    final tiers = rechargeTiers;
    for (final tier in tiers) {
      if (tier['enabled'] != true) continue;
      final min = (tier['minAmount'] as num?)?.toDouble() ?? 0;
      final max = (tier['maxAmount'] as num?)?.toDouble() ?? -1;
      if (amountUsd < min) continue;
      if (max >= 0 && amountUsd > max) continue;
      // Zone targeting (optional)
      final tZone = tier['targetZone'] as String?;
      if (tZone != null && tZone.isNotEmpty && userCommune.isNotEmpty) {
        final zone = getZoneStanding(userCommune);
        if (zone != tZone) continue;
      }
      return tier;
    }
    return null;
  }

  // ─── AUTH ───────────────────────────────────────────────────────────────────
  // Note: l'auth Firebase (email/password) est gérée dans AuthProvider via FirebaseAuth.
  // DataService gère les profils utilisateurs dans Firestore.

  Future<UserModel?> login(String email, String password) async {
    // Appelé par AuthProvider après validation Firebase Auth
    // On charge juste le profil Firestore
    try {
      final snap = await _usersCol
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final user = UserModel.fromMap(snap.docs.first.data() as Map<String, dynamic>);
      await _saveSession(user);
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<UserModel?> loginById(String uid) async {
    try {
      final snap = await _usersCol.doc(uid).get();
      if (!snap.exists) return null;
      final user = UserModel.fromMap(snap.data() as Map<String, dynamic>);
      await _saveSession(user);
      return user;
    } catch (e, st) {
      // Log l'erreur réelle pour faciliter le diagnostic
      if (kDebugMode) {
        debugPrint('[DataService.loginById] Erreur: $e');
        debugPrint('[DataService.loginById] Stack: $st');
      }
      return null;
    }
  }

  /// Cherche un utilisateur par numéro de téléphone (pour vérification doublon)
  Future<UserModel?> findUserByPhone(String phone) async {
    try {
      final snap = await _usersCol
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return UserModel.fromMap(snap.docs.first.data() as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<UserModel?> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    String? whatsApp,
    String? category,
    String? uid, // Firebase Auth UID
    bool isVerified = false, // true pour les comptes vérifiés par OTP
    String? sponsorCode, // code parrainage saisi à l'inscription
    String? province,    // province de résidence
    String? city,        // ville de résidence
    String? commune,     // commune de résidence
  }) async {
    final userId = uid ?? 'usr_${DateTime.now().millisecondsSinceEpoch}';

    // ── Forcer le refresh du token Firebase avant toute écriture Firestore.
    // Sans ça, les règles de sécurité reçoivent un token non encore propagé
    // et refusent l'écriture malgré un auth.currentUser valide.
    // Le délai de 500ms laisse le temps au token de se propager côté serveur.
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        await firebaseUser.getIdToken(true); // force refresh
        await Future.delayed(const Duration(milliseconds: 500)); // propagation token
      }
    } catch (_) {
      // non-bloquant si le refresh échoue
    }

    final newUser = UserModel(
      id: userId,
      name: name,
      email: email.toLowerCase(),
      phone: phone,
      role: role,
      category: category,
      whatsApp: whatsApp ?? phone,
      createdAt: DateTime.now(),
      isVerified: isVerified, // transmis depuis le flux d'inscription
      sponsorCode: sponsorCode,
      province: province,
      city: city,
      commune: commune,
    );

    // Écriture Firestore — on laisse remonter l'exception pour un vrai message d'erreur
    final firestoreData = _userToFirestore(newUser);
    // Stocker le mot de passe pour permettre la connexion aux comptes Phone Auth
    // (ces comptes n'ont pas de session Firebase Auth email, la vérif se fait côté Firestore)
    if (password.isNotEmpty) {
      firestoreData['password'] = password;
    }
    // Stocker le code parrainage si fourni
    if (sponsorCode != null && sponsorCode.isNotEmpty) {
      firestoreData['sponsorCode'] = sponsorCode;
    }
    await _usersCol.doc(userId).set(firestoreData);
    await _saveSession(newUser);

    // NOTE: Les 3 publications gratuites de bienvenue sont gérées exclusivement
    // par le système QuotaModel (getCurrentQuota crée le doc mensuel avec freeQuota=3).
    // Ne PAS ajouter de CreditModel ici — ce serait un double-comptage.
    return newUser;
  }

  Future<void> logout() async {
    await _clearSession();
  }

  // ─── CONNEXION DIRECTE (comptes Phone Auth sans session Firebase email) ────
  // Utilisé quand l'utilisateur s'est inscrit via OTP et n'a pas de compte
  // email virtuel Firebase Auth. On sauvegarde la session localement.
  Future<void> saveSessionDirectly(UserModel user) async {
    await _saveSession(user);
  }

  // ─── RÉCUPÉRATION MOT DE PASSE DEPUIS FIRESTORE ───────────────────────────
  // Permet de vérifier le mot de passe des comptes Phone Auth lors de la connexion.
  Future<String?> getUserPassword(String userId) async {
    try {
      final doc = await _usersCol.doc(userId).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      return data?['password'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ─── MISE À JOUR MOT DE PASSE DANS FIRESTORE ─────────────────────────────
  // Utilisé par le flux "mot de passe oublié" via OTP SMS.
  Future<bool> updateUserPassword(String userId, String newPassword) async {
    try {
      await _usersCol.doc(userId).update({'password': newPassword});
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.updateUserPassword] Erreur: $e');
      return false;
    }
  }

  // ─── USERS ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _userToFirestore(UserModel u) => {
    'id': u.id,
    'name': u.name,
    'email': u.email,
    'phone': u.phone,
    'role': u.role,
    'category': u.category,
    'avatar': u.avatar,
    'city': u.city,
    'commune': u.commune,
    'address': u.address,
    'isActive': u.isActive,
    'isVerified': u.isVerified,
    'createdAt': u.createdAt.toIso8601String(),
    'lastLogin': u.lastLogin?.toIso8601String(),
    'totalProperties': u.totalProperties,
    'description': u.description,
    'whatsApp': u.whatsApp,
  };

  /// Force-refresh du token Firebase Auth avant les lectures de collection admin.
  /// Évite les erreurs PERMISSION_DENIED dues à un token expiré ou non propagé.
  Future<void> _ensureFreshToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await user.getIdToken(true);
    } catch (_) {}
  }

  Future<List<UserModel>> getUsers() async {
    try {
      await _ensureFreshToken();
      final snap = await _usersCol.get();
      return snap.docs
          .map((d) => UserModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[DataService.getUsers] Erreur: $e');
        debugPrint('[DataService.getUsers] Stack: $st');
      }
      return [];
    }
  }

  // ── Cache avatar en mémoire (évite les N+1 queries) ─────────────────────
  final Map<String, String?> _avatarCache = {};

  /// Enrichit une liste de PropertyModel avec l'avatar de chaque annonceur.
  /// Utilise un cache en mémoire pour éviter les requêtes Firestore répétées.
  /// Groupement par ownerId → 1 requête par annonceur unique.
  Future<List<PropertyModel>> enrichWithAvatars(List<PropertyModel> props) async {
    // Collecter les ownerIds uniques qui ne sont pas encore dans le cache
    final missingIds = props
        .map((p) => p.ownerId)
        .toSet()
        .where((id) => id.isNotEmpty && !_avatarCache.containsKey(id))
        .toList();

    // Charger les avatars manquants
    await Future.wait(missingIds.map((id) async {
      try {
        final snap = await _usersCol.doc(id).get();
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>?;
          _avatarCache[id] = data?['avatar'] as String?;
        } else {
          _avatarCache[id] = null;
        }
      } catch (_) {
        _avatarCache[id] = null;
      }
    }));

    // Injecter les avatars dans les PropertyModel
    return props.map((p) => p.ownerId.isNotEmpty
        ? p.copyWith(ownerAvatar: _avatarCache[p.ownerId])
        : p).toList();
  }

  Future<UserModel?> getUserById(String id) async {
    if (id.isEmpty) return null;
    // ── Ne pas attraper les erreurs réseau ici — on les laisse remonter
    // pour que checkAuth() puisse distinguer "user inexistant" vs "réseau lent".
    final snap = await _usersCol.doc(id).get();
    if (!snap.exists) return null;
    // Injecter le document ID dans la map — Firestore ne l'inclut pas dans data()
    final data = Map<String, dynamic>.from(snap.data() as Map<String, dynamic>);
    data['id'] = snap.id;
    return UserModel.fromMap(data);
  }

  Future<void> updateUser(UserModel user) async {
    await _usersCol.doc(user.id).set(_userToFirestore(user), SetOptions(merge: true));
    // Mettre à jour la session locale si c'est l'utilisateur courant
    if (user.id == currentUserId) {
      await _saveSession(user);
    }
  }

  Future<void> toggleUserStatus(String userId) async {
    final user = await getUserById(userId);
    if (user == null) return;
    await _usersCol.doc(userId).update({'isActive': !user.isActive});
  }

  Future<void> deleteUser(String userId) async {
    await _usersCol.doc(userId).delete();
  }

  // ─── PROPERTIES ─────────────────────────────────────────────────────────────

  Map<String, dynamic> _propertyToFirestore(PropertyModel p) => {
    'id': p.id,
    'title': p.title,
    'description': p.description,
    'type': p.type,
    'transactionType': p.transactionType,
    'price': p.price,
    'currency': p.currency,
    'country': p.country,
    'province': p.province,
    'city': p.city,
    'commune': p.commune,
    'quartier': p.quartier,
    'address': p.address,
    'surface': p.surface,
    'bedrooms': p.bedrooms,
    'bathrooms': p.bathrooms,
    'floors': p.floors,
    'hasParking': p.hasParking,
    'hasWater': p.hasWater,
    'hasElectricity': p.hasElectricity,
    'amenities': p.amenities,
    'images': p.images,
    'mainImageIndex': p.mainImageIndex,
    'ownerId': p.ownerId,
    'ownerName': p.ownerName,
    'ownerPhone': p.ownerPhone,
    'ownerEmail': p.ownerEmail,
    'ownerWhatsApp': p.ownerWhatsApp,
    'ownerCategory': p.ownerCategory,
    'status': p.status,
    'isSold': p.isSold,
    'isRented': p.isRented,
    'createdAt': p.createdAt.toIso8601String(),
    'updatedAt': p.updatedAt?.toIso8601String(),
    'expiresAt': p.expiresAt?.toIso8601String(),
    'views': p.views,
    'isFeatured': p.isFeatured,
    'boostEnd': p.boostEnd?.toIso8601String(),
    'boostType': p.boostType,
    'latitude': p.latitude,
    'longitude': p.longitude,
    'pricePerNight': p.pricePerNight,
    'numberOfBeds': p.numberOfBeds,
    'hasAirConditioning': p.hasAirConditioning,
    'hasBreakfast': p.hasBreakfast,
    'pricePerDay': p.pricePerDay,
    'capacity': p.capacity,
    'minLeaseDuration': p.minLeaseDuration,
    'garantieMois': p.garantieMois,
    'hasCommission': p.hasCommission,
    'commissionPct': p.commissionPct,
    'hasAscenseur': p.hasAscenseur,
    'hasCuisineEquipee': p.hasCuisineEquipee,
    'longueurM': p.longueurM,
    'largeurM': p.largeurM,
  };

  Future<List<PropertyModel>> getProperties() async {
    try {
      await _ensureFreshToken();
      final snap = await _propertiesCol.get();
      return snap.docs
          .map((d) => PropertyModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.getProperties] Erreur: $e');
      return [];
    }
  }

  Future<List<PropertyModel>> getActiveProperties() async {
    try {
      final now = DateTime.now();
      final snap = await _propertiesCol.get();
      final all = snap.docs
          .map((d) => PropertyModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();

      final boosted = all.where((p) =>
          p.status == 'Actif' && p.isBoostActive && !p.isSold && !p.isRented).toList();
      final normal = all.where((p) =>
          p.status == 'Actif' && !p.isBoostActive && !p.isSold && !p.isRented).toList();
      final soldOccupied = all.where((p) {
        if (!(p.isSold || p.isRented)) return false;
        if (p.updatedAt == null) return false;
        return now.difference(p.updatedAt!).inHours < AppConstants.soldAutoDeleteHours;
      }).toList();

      final merged = [...boosted, ...normal, ...soldOccupied];
      // Enrichir avec les avatars annonceurs (cache groupé, 1 requête/annonceur unique)
      return enrichWithAvatars(merged);
    } catch (_) {
      return [];
    }
  }

  Future<List<PropertyModel>> getUserProperties(String userId) async {
    try {
      final snap = await _propertiesCol
          .where('ownerId', isEqualTo: userId)
          .get();
      final list = snap.docs
          .map((d) => PropertyModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<PropertyModel>> getPendingProperties() async {
    try {
      final snap = await _propertiesCol
          .where('status', isEqualTo: 'En attente')
          .get();
      return snap.docs
          .map((d) => PropertyModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Récupère une annonce par son identifiant depuis Firestore.
  /// Effectue un accès direct au document (plus fiable que la liste
  /// pour les documents contenant de grandes images base64).
  Future<PropertyModel?> getPropertyById(String id) async {
    try {
      final snap = await _propertiesCol.doc(id).get();
      if (!snap.exists) return null;
      return PropertyModel.fromMap(snap.data() as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> addProperty(PropertyModel property) async {
    await _propertiesCol.doc(property.id).set(_propertyToFirestore(property));
  }

  Future<void> updateProperty(PropertyModel property) async {
    await _propertiesCol.doc(property.id)
        .set(_propertyToFirestore(property), SetOptions(merge: true));
  }

  Future<void> deleteProperty(String id) async {
    // Récupérer l'annonce pour notification avant suppression
    try {
      final snap = await _propertiesCol.doc(id).get();
      if (snap.exists) {
        final prop = PropertyModel.fromMap(snap.data() as Map<String, dynamic>);
        if (prop.ownerId.isNotEmpty) {
          await notifyPropertyDeleted(prop);
        }
      }
    } catch (_) {}
    await _propertiesCol.doc(id).delete();
  }

  /// Suppression douce : marque status='Supprimé' + deletedAt, ne supprime pas de Firestore.
  /// La restauration est possible dans les 24 h.
  Future<void> softDeleteProperty(String id, String reason) async {
    final now = DateTime.now();
    // Récupérer l'annonce pour notification
    try {
      final snap = await _propertiesCol.doc(id).get();
      if (snap.exists) {
        final prop = PropertyModel.fromMap(snap.data() as Map<String, dynamic>);
        if (prop.ownerId.isNotEmpty) {
          await addNotification(AppNotification(
            id: 'notif_del_${prop.id}_${now.millisecondsSinceEpoch}',
            userId: prop.ownerId,
            type: 'suppression',
            title: 'Annonce supprimée',
            body: 'Votre annonce "${prop.title}" a été supprimée.\nMotif : $reason\n⚠️ Cette suppression est définitive et non remboursable.',
            propertyId: prop.id,
            propertyTitle: prop.title,
            createdAt: now,
          ));
        }
      }
    } catch (_) {}
    await _propertiesCol.doc(id).update({
      'status': 'Supprimé',
      'deletedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
  }

  /// Restaurer une annonce supprimée (dans les 24 h) → remet status='En attente'.
  Future<void> restoreProperty(String id) async {
    final now = DateTime.now();
    // Vérifier que deletedAt < 24 h
    final snap = await _propertiesCol.doc(id).get();
    if (!snap.exists) throw Exception('Annonce introuvable');
    final data = snap.data() as Map<String, dynamic>;
    final deletedAtStr = data['deletedAt'] as String?;
    if (deletedAtStr != null) {
      final deletedAt = DateTime.tryParse(deletedAtStr);
      if (deletedAt != null && now.difference(deletedAt).inHours >= 24) {
        throw Exception('Délai de restauration de 24 h dépassé');
      }
    }
    await _propertiesCol.doc(id).update({
      'status': 'En attente',
      'deletedAt': null,
      'updatedAt': now.toIso8601String(),
    });
    // Notifier l'annonceur
    try {
      final prop = PropertyModel.fromMap(data);
      if (prop.ownerId.isNotEmpty) {
        await addNotification(AppNotification(
          id: 'notif_restore_${prop.id}_${now.millisecondsSinceEpoch}',
          userId: prop.ownerId,
          type: 'restauration',
          title: '🔄 Annonce restaurée',
          body: 'Votre annonce "${prop.title}" a été restaurée et est à nouveau en cours de révision.',
          propertyId: prop.id,
          propertyTitle: prop.title,
          createdAt: now,
        ));
      }
    } catch (_) {}
  }

  Future<void> updatePropertyStatus(String id, String status) async {
    await _propertiesCol.doc(id).update({
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    // Notifier l'annonceur si l'annonce vient d'être approuvée
    if (status == 'Actif') {
      try {
        final snap = await _propertiesCol.doc(id).get();
        if (snap.exists) {
          final prop = PropertyModel.fromMap(snap.data() as Map<String, dynamic>);
          if (prop.ownerId.isNotEmpty) {
            await notifyPropertyApproved(prop);
          }
        }
      } catch (_) {}
    }
  }

  /// Renouvelle une annonce expirée : remet le statut à 'En attente' et
  /// repousse la date d'expiration de [days] jours à partir d'aujourd'hui.
  Future<void> renewProperty(String id, {int days = 30}) async {
    final now = DateTime.now();
    await _propertiesCol.doc(id).update({
      'status': 'En attente',
      'expiresAt': now.add(Duration(days: days)).toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
  }

  /// Incrémente atomiquement le compteur de vues d'une annonce.
  /// Retourne le nouveau total de vues, ou null en cas d'échec.
  Future<int?> incrementPropertyViews(String propertyId) async {
    try {
      // update() atomique — crée le champ s'il n'existe pas encore
      await _propertiesCol.doc(propertyId).update({
        'views': FieldValue.increment(1),
      });
      // Relire la valeur réelle après incrément
      final snap = await _propertiesCol.doc(propertyId).get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>?;
        return (data?['views'] as num?)?.toInt();
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Views] increment failed for $propertyId: $e');
      // Tentative de création du champ via set merge si update a échoué
      try {
        final snap = await _propertiesCol.doc(propertyId).get();
        if (snap.exists) {
          final current = ((snap.data() as Map<String, dynamic>?)?['views'] as num?)?.toInt() ?? 0;
          await _propertiesCol.doc(propertyId).set({'views': current + 1}, SetOptions(merge: true));
          return current + 1;
        }
      } catch (_) {}
      return null;
    }
  }

  Future<void> markPropertySoldOrRented(String id,
      {bool sold = false, bool rented = false}) async {
    await _propertiesCol.doc(id).update({
      'isSold': sold,
      'isRented': rented,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<int> clearSoldAndRentedProperties() async {
    try {
      final snap = await _propertiesCol
          .where('isSold', isEqualTo: true)
          .get();
      final snap2 = await _propertiesCol
          .where('isRented', isEqualTo: true)
          .get();
      final ids = <String>{
        ...snap.docs.map((d) => d.id),
        ...snap2.docs.map((d) => d.id),
      };
      for (final id in ids) {
        await _propertiesCol.doc(id).delete();
      }
      return ids.length;
    } catch (_) {
      return 0;
    }
  }

  /// Active le boost sur une annonce.
  /// [boostLevel] : 1=Standard, 2=Premium, 3=VIP
  /// [days]       : durée en jours (7, 15 ou 30)
  Future<void> boostProperty(String id, {
    required int boostLevel,
    required int days,
  }) async {
    final boostType = days <= 7 ? 'semaine' : days <= 15 ? '15jours' : 'mois';
    await _propertiesCol.doc(id).update({
      'isFeatured': true,
      'boostLevel': boostLevel,
      'boostEnd': DateTime.now().add(Duration(days: days)).toIso8601String(),
      'boostType': boostType,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Retire le boost d'une annonce.
  Future<void> removeBoost(String id) async {
    await _propertiesCol.doc(id).update({
      'isFeatured': false,
      'boostLevel': 0,
      'boostEnd': null,
      'boostType': null,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  // ─── QUOTAS ─────────────────────────────────────────────────────────────────

  Future<QuotaModel> getCurrentQuota(String userId) async {
    // Quota de bienvenue unique (non mensuel) : year=0, month=0
    // Une fois attribué, jamais réinitialisé.
    try {
      final snap = await _quotasCol
          .where('userId', isEqualTo: userId)
          .where('year', isEqualTo: 0)
          .where('month', isEqualTo: 0)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return QuotaModel.fromMap(snap.docs.first.data() as Map<String, dynamic>);
      }
    } catch (_) {}

    // Créer le quota de bienvenue une seule fois — lit les réglages admin
    final settings  = await _getSettings();
    final quotaCount = (settings['free_quota_count'] as num?)?.toInt() ?? 3;
    final quotaDays  = (settings['free_quota_days']  as num?)?.toInt() ?? 30;
    final welcomeQuota = QuotaModel(
      id: 'quota_${userId}_welcome',
      userId: userId,
      year: 0,   // marqueur «quota unique à vie»
      month: 0,
      freeQuota: quotaCount,
      usedFreeQuota: 0,
      resetDate: DateTime.now().add(Duration(days: quotaDays * quotaCount + 365)),
    );
    await _quotasCol.doc(welcomeQuota.id).set(welcomeQuota.toMap());
    return welcomeQuota;
  }

  Future<void> consumeFreeQuota(String userId) async {
    // Consomme une unité du quota de bienvenue unique (year=0, month=0)
    try {
      final snap = await _quotasCol
          .where('userId', isEqualTo: userId)
          .where('year', isEqualTo: 0)
          .where('month', isEqualTo: 0)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final q = QuotaModel.fromMap(snap.docs.first.data() as Map<String, dynamic>);
        await _quotasCol.doc(q.id).update({'usedFreeQuota': q.usedFreeQuota + 1});
      }
    } catch (_) {}
  }

  // ─── CRÉDITS ────────────────────────────────────────────────────────────────

  static const int creditsPerDollar = 10;

  Future<List<CreditModel>> getUserCredits(String userId) async {
    try {
      final snap = await _creditsCol
          .where('userId', isEqualTo: userId)
          .get();
      final all = snap.docs
          .map((d) => CreditModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      return all.where((c) => c.hasCredits).toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> getUserAvailableCredits(String userId) async {
    final credits = await getUserCredits(userId);
    return credits.fold<int>(0, (sum, c) => sum + c.remaining);
  }

  Future<void> addCredit(CreditModel credit) async {
    // Crédits payants (paiement_*, admin_manuel, promo_admin) → pas d'expiration
    // Quota gratuit mensuel → expiration 30 jours (cycle mensuel)
    final isPaidCredit = !credit.source.startsWith('quota_');
    final creditWithExpiry = (credit.expiresAt == null && !isPaidCredit)
        ? credit.copyWith(
            expiresAt: credit.createdAt.add(const Duration(days: 30)))
        : credit; // crédits payants : on garde expiresAt null = pas d'expiration
    await _creditsCol.doc(creditWithExpiry.id).set(creditWithExpiry.toMap());
  }

  Future<void> consumeCredits(String userId, int amount) async {
    int toConsume = amount;
    final credits = await getUserCredits(userId);
    for (final credit in credits) {
      if (toConsume <= 0) break;
      final use = credit.remaining >= toConsume ? toConsume : credit.remaining;
      await _creditsCol.doc(credit.id).update({'remaining': credit.remaining - use});
      toConsume -= use;
    }
  }

  Future<void> consumeCredit(String userId) => consumeCredits(userId, 1);

  // ─── NOTIFICATIONS ───────────────────────────────────────────────────────────

  Future<List<AppNotification>> getNotificationsForUser(String userId) async {
    try {
      final snap = await _notificationsCol
          .where('userId', isEqualTo: userId)
          .get();
      final list = snap.docs
          .map((d) => AppNotification.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<int> getUnreadNotificationCount(String userId) async {
    final notifs = await getNotificationsForUser(userId);
    return notifs.where((n) => !n.isRead).length;
  }

  Future<void> addNotification(AppNotification notif) async {
    await _notificationsCol.doc(notif.id).set(notif.toMap());
  }

  /// Récupère toutes les notifications (tous utilisateurs) — Admin Service Client
  Future<List<AppNotification>> getGlobalNotifications() async {
    try {
      final snap = await _notificationsCol.get();
      final list = snap.docs
          .map((d) => AppNotification.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> markNotificationRead(String notifId) async {
    await _notificationsCol.doc(notifId).update({'isRead': true});
  }

  Future<void> deleteNotification(String notifId) async {
    await _notificationsCol.doc(notifId).delete();
  }

  Future<void> markAllNotificationsRead(String userId) async {
    final snap = await _notificationsCol
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.update({'isRead': true});
    }
  }

  Future<void> notifyPropertyApproved(PropertyModel prop) async {
    await addNotification(AppNotification(
      id: 'notif_approved_${prop.id}_${DateTime.now().millisecondsSinceEpoch}',
      userId: prop.ownerId,
      type: 'approbation',
      title: '✅ Annonce approuvée et en ligne !',
      body: 'Félicitations ! Votre annonce "${prop.title}" a été approuvée par notre équipe et est maintenant visible en ligne.',
      propertyId: prop.id,
      propertyTitle: prop.title,
      createdAt: DateTime.now(),
    ));
  }

  Future<void> notifyPropertyRejected(PropertyModel prop, String reason) async {
    await addNotification(AppNotification(
      id: 'notif_rej_${prop.id}_${DateTime.now().millisecondsSinceEpoch}',
      userId: prop.ownerId,
      type: 'rejet',
      title: 'Annonce rejetée',
      body: 'Votre annonce "${prop.title}" a été rejetée.\nMotif : $reason',
      propertyId: prop.id,
      propertyTitle: prop.title,
      createdAt: DateTime.now(),
    ));
  }

  Future<void> notifyPropertyDeleted(PropertyModel prop) async {
    await addNotification(AppNotification(
      id: 'notif_del_${prop.id}_${DateTime.now().millisecondsSinceEpoch}',
      userId: prop.ownerId,
      type: 'suppression',
      title: 'Annonce supprimée',
      body: 'Votre annonce "${prop.title}" a été supprimée par l\'administrateur.',
      propertyId: prop.id,
      propertyTitle: prop.title,
      createdAt: DateTime.now(),
    ));
  }

  // ─── ZONES GÉOGRAPHIQUES ─────────────────────────────────────────────────────

  Map<String, dynamic> get geographicZones {
    final raw = _prefs?.getString('zones_cache');
    if (raw != null) {
      try { return Map<String, dynamic>.from(jsonDecode(raw)); } catch (_) {}
    }
    return {};
  }

  Future<void> saveGeographicZones(Map<String, dynamic> zones) async {
    await _zonesDoc.set(zones);
    await _prefs?.setString('zones_cache', jsonEncode(zones));
  }

  Future<void> refreshZonesCache() async {
    try {
      final snap = await _zonesDoc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        await _prefs?.setString('zones_cache', jsonEncode(data));
      }
    } catch (_) {}
  }

  // ── Zones config (unites par zone) ──────────────────────────────────────────

  Map<String, dynamic> get zonesConfig {
    final raw = _prefs?.getString('zones_config_cache');
    if (raw != null) {
      try { return Map<String, dynamic>.from(jsonDecode(raw)); } catch (_) {}
    }
    return {};
  }

  Future<void> saveZonesConfig(Map<String, dynamic> config) async {
    await _zonesConfigDoc.set(config);
    await _prefs?.setString('zones_config_cache', jsonEncode(config));
  }

  Future<void> refreshZonesConfigCache() async {
    try {
      final snap = await _zonesConfigDoc.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        await _prefs?.setString('zones_config_cache', jsonEncode(data));
      }
    } catch (_) {}
  }

  // Retourne le nombre d'unites pour une commune
  // Nouveau format : commune -> { zone: 'Standard' } + zones_config -> { Standard: { units: 1 } }
  // Ancien format  : commune -> { credits: 3, standing: 'Premium' }
  //
  /// Retourne le nombre d'unites requis pour publier dans [commune] pendant [days] jours.
  /// [days] doit etre 7, 15 ou 30 (defaut = 30).
  /// [transactionType] : 'Location' (defaut) ou 'Vente'.
  ///   Pour 'Vente', les unites Location sont multiplies par le coefficient vente
  ///   configure dans la zone (champ 'vente_coefficient', defaut = 2.0).
  int getCreditsForCommune(String commune,
      {int days = 30, String transactionType = 'Location'}) {
    final zones = geographicZones;
    final cfg   = zonesConfig;

    // Cle de la duree : 'units_7d' | 'units_15d' | 'units_30d'
    final dKey = days == 7 ? 'units_7d' : days == 15 ? 'units_15d' : 'units_30d';

    // Defaults par zone si pas encore configure
    const Map<String, Map<int, int>> fallbackDurations = {
      'Standard':      {7: 1,  15: 2,  30: 3},
      'Intermediaire': {7: 3,  15: 5,  30: 8},
      'Premium':       {7: 5,  15: 8,  30: 12},
      'Luxe':          {7: 10, 15: 15, 30: 20},
    };

    int baseUnits;

    if (zones.containsKey(commune)) {
      final data = zones[commune] as Map<String, dynamic>;
      // Nouveau format : via zone
      if (data.containsKey('zone')) {
        final zoneName = data['zone'] as String? ?? 'Standard';
        if (cfg.containsKey(zoneName)) {
          final zoneCfg = cfg[zoneName];
          if (zoneCfg is Map && zoneCfg.containsKey(dKey)) {
            baseUnits = (zoneCfg[dKey] as num?)?.toInt() ?? 1;
          } else if (zoneCfg is Map && zoneCfg.containsKey('units')) {
            // Ancien format (un seul 'units') — compatibilite
            baseUnits = (zoneCfg['units'] as num?)?.toInt() ?? 1;
          } else {
            baseUnits = fallbackDurations[zoneName]?[days] ?? 1;
          }

          // Appliquer le coefficient vente si applicable
          if (transactionType == 'Vente' && zoneCfg is Map) {
            final coeff = (zoneCfg['vente_coefficient'] as num?)?.toDouble() ?? 2.0;
            return (baseUnits * coeff).round();
          }
          return baseUnits;
        }
        baseUnits = fallbackDurations[zoneName]?[days] ?? 1;
        if (transactionType == 'Vente') {
          return (baseUnits * 2.0).round(); // coefficient defaut
        }
        return baseUnits;
      }
      // Ancien format : credits direct
      if (data.containsKey('credits')) {
        baseUnits = (data['credits'] as num?)?.toInt() ?? 1;
        if (transactionType == 'Vente') {
          return (baseUnits * 2.0).round();
        }
        return baseUnits;
      }
    }

    // Commune non configuree -> zone Standard par defaut
    if (cfg.containsKey('Standard')) {
      final stdCfg = cfg['Standard'];
      if (stdCfg is Map && stdCfg.containsKey(dKey)) {
        baseUnits = (stdCfg[dKey] as num?)?.toInt() ?? 1;
        if (transactionType == 'Vente') {
          final coeff = (stdCfg['vente_coefficient'] as num?)?.toDouble() ?? 2.0;
          return (baseUnits * coeff).round();
        }
        return baseUnits;
      }
    }
    baseUnits = fallbackDurations['Standard']?[days] ?? 1;
    if (transactionType == 'Vente') {
      return (baseUnits * 2.0).round();
    }
    return baseUnits;
  }

  String getZoneStanding(String commune) {
    final zones = geographicZones;
    if (zones.containsKey(commune)) {
      final data = zones[commune] as Map<String, dynamic>;
      // Nouveau format
      if (data.containsKey('zone')) return data['zone'] as String? ?? 'Standard';
      // Ancien format
      if (data.containsKey('standing')) return data['standing'] as String? ?? 'Standard';
    }
    return 'Standard';
  }

  // ─── MESSAGES ───────────────────────────────────────────────────────────────

  Future<List<MessageModel>> getMessages() async {
    try {
      await _ensureFreshToken();
      final snap = await _messagesCol.get();
      return snap.docs
          .map((d) => MessageModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.getMessages] Erreur: $e');
      return [];
    }
  }

  Future<List<MessageModel>> getConversation(String u1, String u2) async {
    try {
      final snap = await _messagesCol.get();
      final all = snap.docs
          .map((d) => MessageModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      return all.where((m) =>
          (m.senderId == u1 && m.receiverId == u2) ||
          (m.senderId == u2 && m.receiverId == u1)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> sendMessage(MessageModel message) async {
    await _messagesCol.doc(message.id).set(message.toMap());
  }

  // ─── FAVORIS (local uniquement) ──────────────────────────────────────────────

  Future<List<String>> getFavorites() async =>
      _prefs?.getStringList(AppConstants.keyFavorites) ?? [];

  Future<void> toggleFavorite(String propertyId) async {
    final favs = await getFavorites();
    if (favs.contains(propertyId)) {
      favs.remove(propertyId);
    } else {
      favs.add(propertyId);
    }
    await _prefs?.setStringList(AppConstants.keyFavorites, favs);
  }

  Future<bool> isFavorite(String propertyId) async =>
      (await getFavorites()).contains(propertyId);

  // ─── STATS PUBLIQUES ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPublicStats() async {
    final props = await getActiveProperties();
    final all   = await getProperties();
    final now   = DateTime.now();

    // Annonces fermées dans les 3 derniers jours (72h) — vendues ou louées/occupées
    final recentes = all.where((p) {
      if (!(p.isSold || p.isRented)) return false;
      if (p.updatedAt == null) return false;
      return now.difference(p.updatedAt!).inHours < 72; // 3 jours
    }).toList();

    return {
      // ── Disponibilités (annonces actives) — toutes catégories ──────────────
      'maisonVente':       props.where((p) => p.type == 'Maison' && p.transactionType == 'Vente').length,
      'maisonLocation':    props.where((p) => p.type == 'Maison' && p.transactionType == 'Location').length,
      'appartVente':       props.where((p) => p.type.contains('Appartement') && p.transactionType == 'Vente').length,
      'appartLocation':    props.where((p) => p.type.contains('Appartement') && p.transactionType == 'Location').length,
      'bureauLocation':    props.where((p) => p.type == 'Bureau' && p.transactionType == 'Location').length,
      'bureauVente':       props.where((p) => p.type == 'Bureau' && p.transactionType == 'Vente').length,
      'propCommerciale':   props.where((p) => p.type.contains('Commerciale')).length,
      'propIndustrielle':  props.where((p) => p.type.contains('Industrielle')).length,
      'terrainDispo':      props.where((p) => p.type.contains('Terrain')).length,
      'concessionDispo':   props.where((p) => p.type == 'Concession').length,
      'chambreHotel':      props.where((p) => p.type.contains('h\u00f4tel') || p.type.contains('hotel')).length,
      'salleFetes':        props.where((p) => p.type == 'Salle de F\u00eates').length,
      'sallePolyvalente':  props.where((p) => p.type == 'Salle polyvalente').length,
      'espaceFuneraire':   props.where((p) => p.type.contains('Fun\u00e9r') || p.type.contains('Funer')).length,
      'totalActif':        props.length,

      // ── Historique 3 jours (72h) — vendus / occup\u00e9s r\u00e9cemment ──────────────
      'hist72_maisonVendue':   recentes.where((p) => p.type == 'Maison' && p.isSold).length,
      'hist72_maisonOccupee':  recentes.where((p) => p.type == 'Maison' && p.isRented).length,
      'hist72_terrainVendu':   recentes.where((p) => p.type.contains('Terrain') && p.isSold).length,
      'hist72_appartVendu':    recentes.where((p) => p.type.contains('Appartement') && p.isSold).length,
      'hist72_appartOccupe':   recentes.where((p) => p.type.contains('Appartement') && p.isRented).length,
      'hist72_bureauOccupe':   recentes.where((p) => p.type == 'Bureau' && p.isRented).length,
      'hist72_salleOccupee':   recentes.where((p) => p.type.contains('Salle') && p.isRented).length,
      'hist72_total':          recentes.length,
    };
  }

  // ─── PAIEMENTS ──────────────────────────────────────────────────────────────

  Future<List<PaymentModel>> getPayments() async {
    try {
      await _ensureFreshToken();
      final snap = await _paymentsCol.get();
      return snap.docs
          .map((d) => PaymentModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.getPayments] Erreur: $e');
      return [];
    }
  }

  Future<List<PaymentModel>> getUserPayments(String userId) async {
    try {
      final snap = await _paymentsCol
          .where('userId', isEqualTo: userId)
          .get();
      return snap.docs
          .map((d) => PaymentModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addPayment(PaymentModel payment) async {
    await _paymentsCol.doc(payment.id).set(payment.toMap());
  }

  Future<void> confirmPayment(String paymentId) async {
    await _paymentsCol.doc(paymentId).update({
      'status': 'confirmed',
      'confirmedAt': DateTime.now().toIso8601String(),
      'isConfirmed': true,
    });
  }

  Future<void> rejectPayment(String paymentId) async {
    await _paymentsCol.doc(paymentId).update({'status': 'rejected'});
  }

  // ─── SIGNALEMENTS ───────────────────────────────────────────────────────────

  Future<List<ReportModel>> getPendingReports() async {
    try {
      final snap = await _reportsCol
          .where('status', isEqualTo: 'pending')
          .get();
      return snap.docs
          .map((d) => ReportModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addReport(ReportModel report) async {
    await _reportsCol.doc(report.id).set(report.toMap());
  }

  Future<void> resolveReport(String reportId) async {
    await _reportsCol.doc(reportId).update({'status': 'resolved'});
  }

  // ─── LOGS AUDIT ─────────────────────────────────────────────────────────────
  // Note: getAuditLogs() with optional limit is defined below near end of file.

  // ─── CONFIG PACKS & PAIEMENTS ────────────────────────────────────────────────

  List<Map<String, dynamic>> get paymentMethods {
    final raw = _prefs?.getString('payment_methods_cache');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        return list.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    return _defaultPaymentMethods();
  }

  List<Map<String, dynamic>> _defaultPaymentMethods() => [
    {'id': 'pm_1', 'name': 'M-Pesa (Vodacom)', 'number': '+243 81 000 0001', 'icon': 'mpesa', 'active': true},
    {'id': 'pm_2', 'name': 'Orange Money', 'number': '+243 84 000 0002', 'icon': 'orange', 'active': true},
    {'id': 'pm_3', 'name': 'Airtel Money', 'number': '+243 99 000 0003', 'icon': 'airtel', 'active': true},
  ];

  Future<void> savePaymentMethods(List<Map<String, dynamic>> methods) async {
    await _paymentMethodsDoc.set({'methods': methods});
    await _prefs?.setString('payment_methods_cache', jsonEncode(methods));
  }

  List<Map<String, dynamic>> get subscriptionPacks {
    final raw = _prefs?.getString('packs_cache');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        return list.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    return _defaultPacks();
  }

  List<Map<String, dynamic>> _defaultPacks() => [
    {'id': 'credits_10', 'name': 'Recharge 100 crédits', 'qty': 100, 'price': 10.0, 'currency': 'USD', 'active': true, 'type': 'credits', 'productType': 'souscription_credits_10', 'description': '10 \$ = 100 crédits'},
    {'id': 'credits_5',  'name': 'Recharge 50 crédits',  'qty': 50,  'price': 5.0,  'currency': 'USD', 'active': true, 'type': 'credits', 'productType': 'souscription_credits_5',  'description': '5 \$ = 50 crédits'},
    {'id': 'credits_20', 'name': 'Recharge 200 crédits', 'qty': 200, 'price': 20.0, 'currency': 'USD', 'active': true, 'type': 'credits', 'productType': 'souscription_credits_20', 'description': '20 \$ = 200 crédits'},
  ];

  Future<void> saveSubscriptionPacks(List<Map<String, dynamic>> packs) async {
    await _packsDoc.set({'packs': packs});
    await _prefs?.setString('packs_cache', jsonEncode(packs));
  }

  // ─── CONTACTS ADMIN ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get adminContacts {
    final raw = _prefs?.getString('contacts_cache');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        return list.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    return _defaultContacts();
  }

  List<Map<String, dynamic>> _defaultContacts() => [
    {'id': 'ct_1', 'label': 'WhatsApp ImmoZone', 'value': '+243 81 000 0001', 'type': 'whatsapp', 'hidden': false},
    {'id': 'ct_2', 'label': 'Téléphone Assistance', 'value': '+243 84 000 0002', 'type': 'phone', 'hidden': false},
    {'id': 'ct_3', 'label': 'Email Contact', 'value': 'contact@immozone.cd', 'type': 'email', 'hidden': false},
    {'id': 'ct_4', 'label': 'Page Facebook', 'value': 'facebook.com/immozone', 'type': 'facebook', 'hidden': false},
  ];

  Future<void> saveAdminContacts(List<Map<String, dynamic>> contacts) async {
    await _contactsDoc.set({'contacts': contacts});
    await _prefs?.setString('contacts_cache', jsonEncode(contacts));
  }

  // ─── MESSAGE OFFICIEL ────────────────────────────────────────────────────────

  String get officialMessage =>
      _prefs?.getString('official_message') ??
      'ImmoZone est une plateforme de mise en relation entre vendeurs, '
      'bailleurs et acquéreurs. Nous facilitons le contact entre les parties '
      'sans intervenir dans la suite de la procédure ni assumer aucune '
      'responsabilité quant aux transactions conclues entre elles. '
      'Vérifiez toujours l\'authenticité des documents avant toute transaction.';

  Future<void> saveOfficialMessage(String message) async {
    await _officialMsgDoc.set({'message': message});
    await _prefs?.setString('official_message', message);
  }

  // ─── NUMÉRO WHATSAPP CONTACT (bouton Contact bottom nav) ─────────────────────

  /// Numéro WhatsApp configurable par l'admin (ex: "243812345678" sans +).
  /// Stocké dans system_settings['whatsapp_contact_number'] + cache SharedPrefs.
  String get whatsappContactNumber =>
      systemSettings['whatsapp_contact_number'] as String? ??
      _prefs?.getString('whatsapp_contact_number_cache') ??      '';

  Future<void> saveWhatsappContactNumber(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    await updateSettings({'whatsapp_contact_number': cleaned});
    await _prefs?.setString('whatsapp_contact_number_cache', cleaned);
  }

  /// Numéro téléphone normal configurable par l'admin.
  /// Stocké dans system_settings['phone_contact_number'] + cache SharedPrefs.
  String get phoneContactNumber =>
      systemSettings['phone_contact_number'] as String? ??
      _prefs?.getString('phone_contact_number_cache') ?? '';

  Future<void> savePhoneContactNumber(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[\s\(\)]'), '');
    await updateSettings({'phone_contact_number': cleaned});
    await _prefs?.setString('phone_contact_number_cache', cleaned);
  }

  /// Email de contact configurable par l'admin.
  /// Stocké dans system_settings['email_contact'] + cache SharedPrefs.
  String get emailContact =>
      systemSettings['email_contact'] as String? ??
      _prefs?.getString('email_contact_cache') ?? '';

  Future<void> saveEmailContact(String email) async {
    final trimmed = email.trim();
    await updateSettings({'email_contact': trimmed});
    await _prefs?.setString('email_contact_cache', trimmed);
  }

  // ─── STATS ADMIN ────────────────────────────────────────────────────────────

  /// Sauvegarde la date de réinitialisation du CA dans Firestore settings.
  Future<void> setRevenueResetDate(DateTime date) async {
    try {
      await _settingsDoc.set(
        {'revenue_reset_date': date.toIso8601String()},
        SetOptions(merge: true),
      );
      // Mettre à jour le cache local
      await _refreshSettingsCache();
    } catch (e) {
      if (kDebugMode) debugPrint('setRevenueResetDate error: $e');
    }
  }

  Future<Map<String, dynamic>> getAdminStats() async {
    final props = await getProperties();
    final users = await getUsers();
    final msgs = await getMessages();
    final payments = await getPayments();
    final reports = await getPendingReports();

    // Lire la date de reset CA (si définie, ne compter que les paiements après)
    final settings = await _getSettings();
    final resetDateStr = settings['revenue_reset_date'] as String?;
    final resetDate = resetDateStr != null
        ? DateTime.tryParse(resetDateStr)
        : null;

    final confirmedPayments = payments.where((p) => p.isConfirmed);
    final revenuePayments = resetDate != null
        ? confirmedPayments.where((p) => p.createdAt.isAfter(resetDate))
        : confirmedPayments;

    final revenue = revenuePayments.fold(0.0, (sum, p) => sum + p.amount);

    return {
      'totalProperties': props.length,
      'activeProperties': props.where((p) => p.status == 'Actif').length,
      'pendingProperties': props.where((p) => p.status == 'En attente').length,
      'soldProperties': props.where((p) => p.isSold || p.isRented).length,
      'suspendedProperties': props.where((p) => p.status == 'Suspendu').length,
      'totalUsers': users.where((u) => u.role != 'admin').length,
      'annonceurs': users.where((u) => u.role == 'annonceur').length,
      'demandeurs': users.where((u) => u.role == 'demandeur').length,
      'totalMessages': msgs.length,
      'vente': props.where((p) => p.transactionType == 'Vente').length,
      'location': props.where((p) => p.transactionType == 'Location').length,
      'totalRevenue': revenue,
      'revenueResetDate': resetDateStr,
      'pendingPayments': payments.where((p) => p.status == 'awaiting_manual').length,
      'pendingReports': reports.length,
      'boostedProperties': props.where((p) => p.isBoostActive).length,
      'freeTrial': isFreeTrial,
    };
  }

  // ─── MESSAGES (USER) ────────────────────────────────────────────────────────

  Future<List<MessageModel>> getUserMessages(String userId) async {
    try {
      final snap = await _messagesCol.get();
      final all = snap.docs
          .map((d) => MessageModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      final filtered = all.where((m) =>
          m.senderId == userId || m.receiverId == userId).toList();
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return filtered;
    } catch (_) {
      return [];
    }
  }

  // ─── PAIEMENTS MANUELS ───────────────────────────────────────────────────────

  Future<List<PaymentModel>> getPendingManualPayments() async {
    try {
      final snap = await _paymentsCol
          .where('status', isEqualTo: 'awaiting_manual')
          .get();
      final list = snap.docs
          .map((d) => PaymentModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> createPayment(PaymentModel payment) async {
    await _paymentsCol.doc(payment.id).set(payment.toMap());
  }

  /// Soumet une demande de recharge manuelle depuis l'écran Recharger.
  /// Crée un PaymentModel avec status='awaiting_manual' que l'admin valide.
  Future<void> submitManualPaymentRequest({
    required String userId,
    required String userName,
    required String packId,
    required String packName,
    required int credits,
    required double amount,
    required String currency,
    required String operator,
    required String phoneNumber,
    required String transactionRef,
  }) async {
    final id = _paymentsCol.doc().id;
    final payment = PaymentModel(
      id: id,
      userId: userId,
      userName: userName,
      orderId: 'PACK-${DateTime.now().millisecondsSinceEpoch}',
      operator: operator,
      phoneNumber: phoneNumber,
      amount: amount,
      currency: currency,
      status: 'awaiting_manual',
      transactionReference: transactionRef,
      createdAt: DateTime.now(),
      productType: packId.isNotEmpty ? packId : 'pack_credits',
      creditsQty: credits,
    );
    await _paymentsCol.doc(id).set({
      ...payment.toMap(),
      'packName': packName,
      'packId': packId,
    });
  }

  Future<void> validatePaymentManually(
    String paymentId, {
    required String adminId,
    required String adminName,
    required bool approve,
    String? note,
  }) async {
    try {
      final snap = await _paymentsCol.doc(paymentId).get();
      if (!snap.exists) return;
      final payment = PaymentModel.fromMap(snap.data() as Map<String, dynamic>);

      if (approve) {
        await _paymentsCol.doc(paymentId).update({
          'status': 'confirmed',
          'isConfirmed': true,
          'confirmedAt': DateTime.now().toIso8601String(),
          'validatedBy': adminId,
          'manualNote': note,
        });
        // Créditer l'utilisateur :
        // Priorité 1 : creditsQty stocké dans le paiement (valeur exacte du pack)
        // Priorité 2 : déduire depuis productType (fallback)
        final qty = payment.creditsQty > 0
            ? payment.creditsQty
            : _creditsForProduct(payment.productType);
        if (qty > 0) {
          // ── Palier de recharge : bonus crédits + annonces gratuites ─────
          final tier = getMatchingTier(payment.amount);
          final bonusPct = tier != null ? (tier['bonusCreditPct'] as num?)?.toInt() ?? 0 : 0;
          final bonusFreeAds = tier != null ? (tier['bonusFreeAds'] as num?)?.toInt() ?? 0 : 0;
          final bonusCredits = bonusPct > 0 ? (qty * bonusPct / 100).round() : 0;
          final totalCredits = qty + bonusCredits;

          await addCredit(CreditModel(
            id: 'credit_${paymentId}_${DateTime.now().millisecondsSinceEpoch}',
            userId: payment.userId,
            quantity: totalCredits,
            remaining: totalCredits,
            source: 'paiement_${payment.productType}',
            createdAt: DateTime.now(),
          ));

          // Bonus annonces gratuites via quota promo
          if (bonusFreeAds > 0) {
            final quota = await getCurrentQuota(payment.userId);
            if (quota != null) {
              await _quotasCol.doc(quota.id).update({
                'freeQuota': quota.freeQuota + bonusFreeAds,
              });
            } else {
              // Créer un quota promo (année spéciale = 9999)
              final newQuota = QuotaModel(
                id: 'quota_promo_${payment.userId}_${DateTime.now().millisecondsSinceEpoch}',
                userId: payment.userId,
                year: 9999,
                month: 1,
                freeQuota: bonusFreeAds,
                usedFreeQuota: 0,
                resetDate: DateTime.now().add(const Duration(days: 365)),
              );
              await _quotasCol.doc(newQuota.id).set(newQuota.toMap());
            }
          }

          // Notification de recharge (sans mention de l'admin)
          String bonusMsg = '';
          if (bonusCredits > 0 && bonusFreeAds > 0) {
            bonusMsg = '\n+ $bonusCredits crédits bonus ($bonusPct%) + $bonusFreeAds annonce(s) gratuite(s) offerte(s) !';
          } else if (bonusCredits > 0) {
            bonusMsg = '\n+ $bonusCredits crédits bonus ($bonusPct%) offerts !';
          } else if (bonusFreeAds > 0) {
            bonusMsg = '\n+ $bonusFreeAds annonce(s) gratuite(s) offerte(s) !';
          }

          await addNotification(AppNotification(
            id: 'notif_pay_${paymentId}_${DateTime.now().millisecondsSinceEpoch}',
            userId: payment.userId,
            type: 'paiement',
            title: 'Recharge confirmée ✓',
            body: 'Vous avez reçu $totalCredits crédit${totalCredits > 1 ? 's' : ''}, valable 30 jours.$bonusMsg',
            createdAt: DateTime.now(),
          ));
        }
      } else {
        await _paymentsCol.doc(paymentId).update({
          'status': 'rejected',
          'validatedBy': adminId,
          'manualNote': note,
        });
        await addNotification(AppNotification(
          id: 'notif_payrej_${paymentId}_${DateTime.now().millisecondsSinceEpoch}',
          userId: payment.userId,
          type: 'paiement',
          title: 'Paiement rejeté',
          body: 'Votre demande de paiement a été rejetée.'
              '${note != null ? '\nMotif : $note' : ''}',
          createdAt: DateTime.now(),
        ));
      }
    } catch (e, st) {
      debugPrint('[validatePaymentManually] ERROR: $e\n$st');
      rethrow; // remonte l'erreur pour que l'admin voit un message d'échec
    }
  }

  int _creditsForProduct(String productType) {
    switch (productType) {
      case 'publication_unitaire': return 1;
      case 'souscription_credits_5': return 50;
      case 'souscription_credits_10': return 100;
      case 'souscription_credits_20': return 200;
      case 'pack_3': return 3;
      case 'pack_5': return 5;
      case 'pack_10': return 10;
      case 'pack_50': return 50;
      default:
        // Tenter d'extraire le nombre depuis le productType (ex: "credits_50" → 50)
        final match = RegExp(r'(\d+)').firstMatch(productType);
        return match != null ? int.tryParse(match.group(1)!) ?? 1 : 1;
    }
  }

  // ─── SIGNALEMENTS (ALL) ──────────────────────────────────────────────────────

  Future<List<ReportModel>> getReports() async {
    try {
      await _ensureFreshToken();
      final snap = await _reportsCol.get();
      final list = snap.docs
          .map((d) => ReportModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.getReports] Erreur: $e');
      return [];
    }
  }

  Future<void> handleReport(
    String reportId,
    String status, {
    String? adminNote,
  }) async {
    await _reportsCol.doc(reportId).update({
      'status': status,
      'adminNote': adminNote,
      'handledBy': currentUserId,
      'handledAt': DateTime.now().toIso8601String(),
    });
  }

  // ─── DROITS DE PUBLICATION ──────────────────────────────────────────────────
  // Retourne: 'free_trial' | 'free_quota' | 'paid_credit' | 'no_right'

  Future<String> checkPublicationRight(String userId,
      {String commune = '', int days = 30, String transactionType = 'Location'}) async {
    // 1. Free trial activé globalement ?
    if (isFreeTrial) return 'free_trial';

    // 2. Quota gratuit (bienvenue year=0, push promo year=8888, recharge promo year=9999)
    final quota = await getCurrentQuota(userId);
    if (quota.usedFreeQuota < quota.freeQuota) return 'free_quota';

    // 2b. Quotas promo supplémentaires (push admin year=8888, recharge tier year=9999)
    final promoQuota = await _getFirstAvailablePromoQuota(userId);
    if (promoQuota != null) return 'free_quota';

    // 3. Crédits payants disponibles ?
    // ── CORRECTION CRITIQUE : s'assurer que le cache des zones est chargé ────
    // geographicZones lit depuis SharedPreferences. Si le cache est vide
    // (premier lancement, cache expiré, ou nouvelle commune), la commune n'est
    // pas trouvée et required tombe à 1 — ce qui laisse passer n'importe quel
    // solde. On force un refresh Firestore si la commune n'est pas dans le cache.
    if (commune.isNotEmpty && !geographicZones.containsKey(commune)) {
      await refreshZonesCache();
      await refreshZonesConfigCache();
    }
    final required = commune.isNotEmpty
        ? getCreditsForCommune(commune, days: days, transactionType: transactionType)
        : 1;
    final available = await getUserAvailableCredits(userId);
    if (available >= required) return 'paid_credit';

    return 'no_right';
  }

  /// Retourne le premier quota promo disponible (year=8888 ou year=9999)
  Future<QuotaModel?> _getFirstAvailablePromoQuota(String userId) async {
    try {
      for (final promoYear in [8888, 9999]) {
        final snap = await _quotasCol
            .where('userId', isEqualTo: userId)
            .where('year', isEqualTo: promoYear)
            .get();
        for (final doc in snap.docs) {
          final q = QuotaModel.fromMap(doc.data() as Map<String, dynamic>);
          if (q.usedFreeQuota < q.freeQuota) return q;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Compte le total d'annonces promo disponibles (year=8888 push admin + year=9999 recharge)
  Future<int> getAvailablePromoQuotaCount(String userId) async {
    int total = 0;
    try {
      for (final promoYear in [8888, 9999]) {
        final snap = await _quotasCol
            .where('userId', isEqualTo: userId)
            .where('year', isEqualTo: promoYear)
            .get();
        for (final doc in snap.docs) {
          final q = QuotaModel.fromMap(doc.data() as Map<String, dynamic>);
          final remaining = q.freeQuota - q.usedFreeQuota;
          if (remaining > 0) total += remaining;
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> consumePublicationRight(String userId,
      {String commune = '', int days = 30, String transactionType = 'Location'}) async {
    // 1. Free trial : rien à consommer
    if (isFreeTrial) return;

    // 2. Quota bienvenue (year=0)
    final quota = await getCurrentQuota(userId);
    if (quota.usedFreeQuota < quota.freeQuota) {
      await consumeFreeQuota(userId);
      return;
    }

    // 2b. Quotas promo (year=8888 push admin, year=9999 recharge tier)
    final promoQuota = await _getFirstAvailablePromoQuota(userId);
    if (promoQuota != null) {
      await _quotasCol.doc(promoQuota.id).update({
        'usedFreeQuota': promoQuota.usedFreeQuota + 1,
      });
      return;
    }

    // 3. Crédits payants
    final required = commune.isNotEmpty
        ? getCreditsForCommune(commune, days: days, transactionType: transactionType)
        : 1;
    await consumeCredits(userId, required);
  }

  // ─── AUDIT LOGS (avec limit optionnel) ──────────────────────────────────────

  Future<List<AuditLogModel>> getAuditLogs({int? limit}) async {
    try {
      await _ensureFreshToken();
      final snap = await _logsCol.get();
      final list = snap.docs
          .map((d) => AuditLogModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (limit != null && list.length > limit) {
        return list.sublist(0, limit);
      }
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.getAuditLogs] Erreur: $e');
      return [];
    }
  }

  // ─── PUBLICITÉS INTERNES ────────────────────────────────────────────────────

  /// Récupère toutes les pubs (admin).
  Future<List<AdModel>> getAllAds() async {
    try {
      final snap = await _adsCol.orderBy('createdAt', descending: true).get();
      return snap.docs
          .map((d) => AdModel.fromMap(d.data() as Map<String, dynamic>, d.id))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.getAllAds] $e');
      return [];
    }
  }

  /// Récupère uniquement les pubs actives et dans leur période (côté public).
  Future<List<AdModel>> getLiveAds() async {
    try {
      final snap = await _adsCol
          .where('isActive', isEqualTo: true)
          .get();
      final now = DateTime.now();
      final list = snap.docs
          .map((d) => AdModel.fromMap(d.data() as Map<String, dynamic>, d.id))
          .where((a) => now.isAfter(a.startDate) && now.isBefore(a.endDate))
          .toList();
      // Trier par position puis date de création
      list.sort((a, b) => a.position.compareTo(b.position));
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.getLiveAds] $e');
      return [];
    }
  }

  /// Crée une nouvelle pub.
  Future<String> createAd(AdModel ad) async {
    try {
      final ref = _adsCol.doc();
      final data = ad.toMap();
      data['id'] = ref.id;
      await ref.set(data);
      return ref.id;
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.createAd] $e');
      rethrow;
    }
  }

  /// Met à jour une pub existante.
  Future<void> updateAd(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _adsCol.doc(id).update(data);
  }

  /// Active ou désactive une pub.
  Future<void> toggleAdStatus(String id, bool isActive) async {
    await _adsCol.doc(id).update({
      'isActive': isActive,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Supprime une pub.
  Future<void> deleteAd(String id) async {
    await _adsCol.doc(id).delete();
  }

  /// Incrémente le compteur de clics d'une pub.
  Future<void> recordAdClick(String id) async {
    try {
      await _adsCol.doc(id).update({
        'clicks': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  /// Incrémente le compteur d'impressions d'une pub.
  Future<void> recordAdImpression(String id) async {
    try {
      await _adsCol.doc(id).update({
        'impressions': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  // ─── REFRESH CACHES AU DÉMARRAGE ────────────────────────────────────────────

  Future<void> refreshAllCaches() async {
    await _refreshSettingsCache();
    await refreshZonesCache();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARRAINS — CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Génère un code parrainage unique à partir du nom (ex: PATOU-A3F2)
  String generateSponsorCode(String name) {
    final base = name.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').substring(0, name.length.clamp(0, 6));
    final suffix = (DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return '$base$suffix';
  }

  /// Crée un parrain avec un code unique.
  Future<ParrainModel> createParrain({required String name}) async {
    final code = generateSponsorCode(name);
    final id = 'parrain_${DateTime.now().millisecondsSinceEpoch}';
    final parrain = ParrainModel(
      id: id,
      name: name,
      code: code,
      createdById: currentUserId,
      createdAt: DateTime.now(),
    );
    await _parrainCol.doc(id).set(parrain.toMap());
    return parrain;
  }

  /// Retourne tous les parrains.
  Future<List<ParrainModel>> getParrains() async {
    try {
      final snap = await _parrainCol.get();
      return snap.docs
          .map((d) => ParrainModel.fromMap(d.data() as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  /// Supprime un parrain.
  Future<void> deleteParrain(String id) async {
    await _parrainCol.doc(id).delete();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTIQUES PLATEFORME (Marketing + Admin)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Retourne toutes les données brutes nécessaires aux stats en un seul appel
  /// (users, properties, payments, credits) avec filtre géographique optionnel.
  Future<PlatformStats> getPlatformStats({
    required DateTime from,
    required DateTime to,
    String? country,
    String? province,
    String? city,
    String? commune,
  }) async {
    final allUsers = await getUsers();
    final allProperties = await getProperties();
    final allPayments = await getPayments();

    // Crédits consommés (source != 'admin_manuel' pour ne compter que les vrais achats)
    List<Map<String, dynamic>> allCreditsRaw = [];
    try {
      final snap = await _creditsCol.get();
      allCreditsRaw = snap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();
    } catch (_) {}

    // Filtre géographique sur les utilisateurs
    bool matchUserGeo(UserModel u) {
      if (country != null && country.isNotEmpty && (u.country ?? '') != country) return false;
      if (province != null && province.isNotEmpty && (u.province ?? '') != province) return false;
      if (city != null && city.isNotEmpty && (u.city ?? '') != city) return false;
      if (commune != null && commune.isNotEmpty && (u.commune ?? '') != commune) return false;
      return true;
    }

    // Filtre géographique sur les annonces
    bool matchPropGeo(PropertyModel p) {
      if (country != null && country.isNotEmpty && p.country != country) return false;
      if (province != null && province.isNotEmpty && p.province != province) return false;
      if (city != null && city.isNotEmpty && p.city != city) return false;
      // commune : on filtre sur les annonces si le champ exist dans PropertyModel
      return true;
    }

    // Filtre période
    bool inPeriod(DateTime dt) => dt.isAfter(from) && dt.isBefore(to.add(const Duration(days: 1)));

    final cutoff90 = DateTime.now().subtract(const Duration(days: 90));

    // ── Calculs ──
    final geoUsers = allUsers.where(matchUserGeo).toList();
    final geoProps = allProperties.where(matchPropGeo).toList();

    // 1. Total dépôts (paiements confirmés dans la période)
    final deposits = allPayments
        .where((p) => p.isConfirmed && inPeriod(p.createdAt))
        .fold(0.0, (s, p) => s + p.amount);

    // 2. Total crédits consommés dans la période
    double creditsConsumed = 0;
    for (final c in allCreditsRaw) {
      final used = (c['quantity'] as num? ?? 0) - (c['remaining'] as num? ?? 0);
      if (used > 0) {
        DateTime? dt;
        try { dt = (c['createdAt'] as dynamic)?.toDate() as DateTime?; } catch (_) {
          try { dt = DateTime.parse(c['createdAt'].toString()); } catch (_) {}
        }
        if (dt != null && inPeriod(dt)) creditsConsumed += used;
      }
    }

    // 3. Annonces postées dans la période
    final postedProps = geoProps.where((p) => inPeriod(p.createdAt)).toList();

    // 4. Annonces expirées dans la période
    final expiredProps = geoProps
        .where((p) => p.status == AppConstants.statusExpired && inPeriod(p.createdAt))
        .toList();

    // 5. Annonces clôturées par les annonceurs (Vendu / Loué) dans la période
    final closedByType = <String, int>{};
    for (final p in geoProps) {
      if ((p.isSold || p.isRented) && inPeriod(p.createdAt)) {
        final key = '${p.transactionType} / ${p.type}';
        closedByType[key] = (closedByType[key] ?? 0) + 1;
      }
    }

    // 6. Nouveaux utilisateurs dans la période (hors admins)
    final newUsers = geoUsers
        .where((u) => !u.isAdminRole && inPeriod(u.createdAt))
        .toList();

    // 7. Total utilisateurs (hors admins)
    final totalUsers = geoUsers.where((u) => !u.isAdminRole).toList();

    // 8. Utilisateurs actifs (lastLogin dans les 30 derniers jours)
    final activeUsers = totalUsers
        .where((u) => u.lastLogin != null &&
            u.lastLogin!.isAfter(DateTime.now().subtract(const Duration(days: 30))))
        .toList();

    // 9. Utilisateurs inactifs depuis 90 jours
    final inactiveUsers = totalUsers
        .where((u) => u.lastLogin == null || u.lastLogin!.isBefore(cutoff90))
        .toList();

    // Bar chart data : dépôts par jour/semaine/mois selon la plage
    final chartData = _buildChartData(allPayments, from, to);

    return PlatformStats(
      totalDeposits: deposits,
      creditsConsumed: creditsConsumed,
      postedProperties: postedProps.length,
      expiredProperties: expiredProps.length,
      closedByType: closedByType,
      newUsersCount: newUsers.length,
      totalUsersCount: totalUsers.length,
      activeUsersCount: activeUsers.length,
      inactiveUsersCount: inactiveUsers.length,
      chartData: chartData,
    );
  }

  Map<String, double> _buildChartData(
      List<PaymentModel> payments, DateTime from, DateTime to) {
    final diff = to.difference(from).inDays;
    final result = <String, double>{};

    if (diff <= 31) {
      // Par jour
      for (int i = 0; i <= diff; i++) {
        final day = from.add(Duration(days: i));
        final label = '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
        result[label] = payments
            .where((p) =>
                p.isConfirmed &&
                p.createdAt.year == day.year &&
                p.createdAt.month == day.month &&
                p.createdAt.day == day.day)
            .fold(0.0, (s, p) => s + p.amount);
      }
    } else {
      // Par mois
      final months = <String>{};
      for (int i = 0; i <= diff; i++) {
        final day = from.add(Duration(days: i));
        months.add('${day.month.toString().padLeft(2, '0')}/${day.year}');
      }
      for (final m in months) {
        final parts = m.split('/');
        final month = int.parse(parts[0]);
        final year = int.parse(parts[1]);
        const monthNames = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];
        final label = '${monthNames[month - 1]} $year';
        result[label] = payments
            .where((p) =>
                p.isConfirmed &&
                p.createdAt.month == month &&
                p.createdAt.year == year)
            .fold(0.0, (s, p) => s + p.amount);
      }
    }
    return result;
  }

  /// Stats d'un parrain spécifique sur une période.
  Future<ParrainStats> getParrainStats({
    required String sponsorCode,
    required DateTime from,
    required DateTime to,
  }) async {
    final allUsers = await getUsers();
    final allProperties = await getProperties();
    final allPayments = await getPayments();

    bool inPeriod(DateTime dt) => dt.isAfter(from) && dt.isBefore(to.add(const Duration(days: 1)));
    final cutoff90 = DateTime.now().subtract(const Duration(days: 90));

    // Comptes associés à ce parrain
    final sponsored = allUsers
        .where((u) => (u.sponsorCode ?? '').toUpperCase() == sponsorCode.toUpperCase())
        .toList();

    // 10. Comptes associés dans la période
    final associatedInPeriod = sponsored.where((u) => inPeriod(u.createdAt)).toList();

    // 11. Comptes actifs dans la période (lastLogin dans la période)
    final activeInPeriod = sponsored
        .where((u) => u.lastLogin != null && inPeriod(u.lastLogin!))
        .toList();

    // 12. Dépôts en $ dans la période
    final sponsoredIds = sponsored.map((u) => u.id).toSet();
    final depositsInPeriod = allPayments
        .where((p) => p.isConfirmed && inPeriod(p.createdAt) && sponsoredIds.contains(p.userId))
        .fold(0.0, (s, p) => s + p.amount);

    // 13. Annonces réalisées dans la période
    final propsInPeriod = allProperties
        .where((p) => inPeriod(p.createdAt) && sponsoredIds.contains(p.ownerId))
        .length;

    // 14. Comptes inactifs depuis 90 jours
    final inactiveCount = sponsored
        .where((u) => u.lastLogin == null || u.lastLogin!.isBefore(cutoff90))
        .length;

    return ParrainStats(
      sponsorCode: sponsorCode,
      associatedCount: associatedInPeriod.length,
      activeCount: activeInPeriod.length,
      depositsUsd: depositsInPeriod,
      propertiesCount: propsInPeriod,
      inactiveCount: inactiveCount,
    );
  }

  // ── KPI 3 : Contact Logs (clics WhatsApp / Appel) ──────────────────────────

  /// Enregistre un clic de contact dans Firestore.
  /// [type] = 'whatsapp' | 'call'
  Future<void> logContactClick({
    required String propertyId,
    required String propertyTitle,
    required String ownerId,
    required String type, // 'whatsapp' | 'call'
    String? visitorId,
  }) async {
    try {
      await _contactLogsCol.add({
        'property_id':    propertyId,
        'property_title': propertyTitle,
        'owner_id':       ownerId,
        'type':           type,
        'visitor_id':     visitorId ?? '',
        'created_at':     FieldValue.serverTimestamp(),
        'created_at_iso': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.logContactClick] error: $e');
    }
  }

  /// Retourne tous les logs de contact (triés du plus récent au plus ancien).
  Future<List<Map<String, dynamic>>> getContactLogs() async {
    try {
      final snap = await _contactLogsCol
          .orderBy('created_at', descending: true)
          .get();
      return snap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[DataService.getContactLogs] error: $e');
      return [];
    }
  }
}
