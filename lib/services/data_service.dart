import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/property_model.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../models/quota_model.dart';

import '../models/payment_model.dart';
import '../models/credit_model.dart';
import '../models/report_model.dart';
import '../models/audit_log_model.dart';
import '../models/app_notification_model.dart';
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
  CollectionReference get _creditsCol => _db.collection('credits');
  CollectionReference get _notificationsCol => _db.collection('notifications');
  CollectionReference get _messagesCol => _db.collection('messages');
  CollectionReference get _paymentsCol => _db.collection('payments');
  CollectionReference get _reportsCol => _db.collection('reports');
  CollectionReference get _logsCol => _db.collection('audit_logs');
  CollectionReference get _quotasCol => _db.collection('quotas');
  DocumentReference get _settingsDoc => _db.collection('config').doc('system_settings');
  DocumentReference get _zonesDoc => _db.collection('config').doc('geographic_zones');
  DocumentReference get _zonesConfigDoc => _db.collection('config').doc('zones_config');
  DocumentReference get _paymentMethodsDoc => _db.collection('config').doc('payment_methods');
  DocumentReference get _packsDoc => _db.collection('config').doc('subscription_packs');
  DocumentReference get _contactsDoc => _db.collection('config').doc('admin_contacts');
  DocumentReference get _officialMsgDoc => _db.collection('config').doc('official_message');

  // ─── INIT ────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
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
  }

  Future<void> _clearSession() async {
    await _prefs?.remove(AppConstants.keyUserId);
    await _prefs?.remove(AppConstants.keyUserName);
    await _prefs?.remove(AppConstants.keyUserEmail);
    await _prefs?.remove(AppConstants.keyUserRole);
    await _prefs?.setBool(AppConstants.keyIsLoggedIn, false);
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

  Future<void> _refreshSettingsCache() async {
    final s = await _getSettings();
    await _prefs?.setString('system_settings_cache', jsonEncode(s));
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
    String? targetCommune,
  }) async {
    // Build promo scope label
    String scope = 'global';
    if (targetCommune != null && targetCommune.isNotEmpty) {
      scope = 'commune:$targetCommune';
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
      // Zone filtering
      if (targetCommune != null && targetCommune.isNotEmpty) {
        if ((user.commune ?? '').toLowerCase() != targetCommune.toLowerCase()) continue;
      } else if (targetCity != null && targetCity.isNotEmpty) {
        if ((user.city ?? '').toLowerCase() != targetCity.toLowerCase()) continue;
      }
      // Note: country filter is informational only (users don't have country field yet)
      await addCredit(CreditModel(
        id: 'promo_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        quantity: freeAnnouncements,
        remaining: freeAnnouncements,
        source: 'promo_admin',
        createdAt: DateTime.now(),
      ));
      credited++;
    }
    return {'credited_users': credited, 'credits_per_user': freeAnnouncements};
  }

  Future<void> suspendPromotion() async {
    await updateSettings({
      'promo_active': false,
      'promo_suspended_at': DateTime.now().toIso8601String(),
    });
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
  }) async {
    final userId = uid ?? 'usr_${DateTime.now().millisecondsSinceEpoch}';

    // ── Forcer le refresh du token Firebase avant toute écriture Firestore.
    // Sans ça, les règles de sécurité reçoivent un token non encore propagé
    // et refusent l'écriture malgré un auth.currentUser valide.
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        await firebaseUser.getIdToken(true); // force refresh
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
    );

    // Écriture Firestore — on laisse remonter l'exception pour un vrai message d'erreur
    await _usersCol.doc(userId).set(_userToFirestore(newUser));
    await _saveSession(newUser);

    // NOTE: Les 3 publications gratuites de bienvenue sont gérées exclusivement
    // par le système QuotaModel (getCurrentQuota crée le doc mensuel avec freeQuota=3).
    // Ne PAS ajouter de CreditModel ici — ce serait un double-comptage.
    return newUser;
  }

  Future<void> logout() async {
    await _clearSession();
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

  Future<List<UserModel>> getUsers() async {
    try {
      final snap = await _usersCol.get();
      return snap.docs
          .map((d) => UserModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<UserModel?> getUserById(String id) async {
    if (id.isEmpty) return null;
    try {
      final snap = await _usersCol.doc(id).get();
      if (!snap.exists) return null;
      return UserModel.fromMap(snap.data() as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
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
      final snap = await _propertiesCol.get();
      return snap.docs
          .map((d) => PropertyModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
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

      return [...boosted, ...normal, ...soldOccupied];
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

  Future<void> updatePropertyStatus(String id, String status) async {
    await _propertiesCol.doc(id).update({
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
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

  Future<void> boostProperty(String id, String boostType) async {
    final duration = boostType == 'semaine' ? 7 : 30;
    await _propertiesCol.doc(id).update({
      'isFeatured': true,
      'boostEnd': DateTime.now().add(Duration(days: duration)).toIso8601String(),
      'boostType': boostType,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  // ─── QUOTAS ─────────────────────────────────────────────────────────────────

  Future<QuotaModel> getCurrentQuota(String userId) async {
    final now = DateTime.now();
    try {
      final snap = await _quotasCol
          .where('userId', isEqualTo: userId)
          .where('year', isEqualTo: now.year)
          .where('month', isEqualTo: now.month)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return QuotaModel.fromMap(snap.docs.first.data() as Map<String, dynamic>);
      }
    } catch (_) {}

    final settings = await _getSettings();
    final newQuota = QuotaModel(
      id: 'quota_${userId}_${now.year}_${now.month}',
      userId: userId,
      year: now.year,
      month: now.month,
      freeQuota: (settings['monthly_free_quota'] as num?)?.toInt() ?? 3,
      usedFreeQuota: 0,
      resetDate: DateTime(now.year, now.month + 1, 1),
    );
    await _quotasCol.doc(newQuota.id).set(newQuota.toMap());
    return newQuota;
  }

  Future<void> consumeFreeQuota(String userId) async {
    final now = DateTime.now();
    try {
      final snap = await _quotasCol
          .where('userId', isEqualTo: userId)
          .where('year', isEqualTo: now.year)
          .where('month', isEqualTo: now.month)
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
  /// Retourne le nombre d'unites requis pour publier dans [commune] pendant [days] jours.
  /// [days] doit etre 7, 15 ou 30 (defaut = 30).
  int getCreditsForCommune(String commune, {int days = 30}) {
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

    if (zones.containsKey(commune)) {
      final data = zones[commune] as Map<String, dynamic>;
      // Nouveau format : via zone
      if (data.containsKey('zone')) {
        final zoneName = data['zone'] as String? ?? 'Standard';
        if (cfg.containsKey(zoneName)) {
          final zoneCfg = cfg[zoneName];
          if (zoneCfg is Map && zoneCfg.containsKey(dKey)) {
            return (zoneCfg[dKey] as num?)?.toInt() ?? 1;
          }
          // Ancien format (un seul 'units') — compatibilite
          if (zoneCfg is Map && zoneCfg.containsKey('units')) {
            return (zoneCfg['units'] as num?)?.toInt() ?? 1;
          }
        }
        return fallbackDurations[zoneName]?[days] ?? 1;
      }
      // Ancien format : credits direct
      if (data.containsKey('credits')) {
        return (data['credits'] as num?)?.toInt() ?? 1;
      }
    }

    // Commune non configuree -> zone Standard par defaut
    if (cfg.containsKey('Standard')) {
      final stdCfg = cfg['Standard'];
      if (stdCfg is Map && stdCfg.containsKey(dKey)) {
        return (stdCfg[dKey] as num?)?.toInt() ?? 1;
      }
    }
    return fallbackDurations['Standard']?[days] ?? 1;
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
      final snap = await _messagesCol.get();
      return snap.docs
          .map((d) => MessageModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
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
    final all = await getProperties();
    return {
      'maisonVente': props.where((p) => p.type == 'Maison' && p.transactionType == 'Vente').length,
      'maisonVendue': all.where((p) => p.type == 'Maison' && p.isSold).length,
      'maisonLocation': props.where((p) => p.type == 'Maison' && p.transactionType == 'Location').length,
      'terrainDispo': props.where((p) => p.type.contains('Terrain')).length,
      'terrainVendu': all.where((p) => p.type.contains('Terrain') && p.isSold).length,
      'parcelleDispo': props.where((p) => p.type == 'Parcelle').length,
      'salleFetes': props.where((p) => p.type.contains('Salle')).length,
      'espaceFuneraire': props.where((p) => p.type.contains('Funer')).length,
      'bureauLocation': props.where((p) => p.type == 'Bureau' && p.transactionType == 'Location').length,
      'appartVente': props.where((p) => p.type.contains('Appartement') && p.transactionType == 'Vente').length,
      'appartLocation': props.where((p) => p.type.contains('Appartement') && p.transactionType == 'Location').length,
      'totalActif': props.length,
    };
  }

  // ─── PAIEMENTS ──────────────────────────────────────────────────────────────

  Future<List<PaymentModel>> getPayments() async {
    try {
      final snap = await _paymentsCol.get();
      return snap.docs
          .map((d) => PaymentModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
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

  Future<Map<String, dynamic>> getAdminStats() async {
    final props = await getProperties();
    final users = await getUsers();
    final msgs = await getMessages();
    final payments = await getPayments();
    final reports = await getPendingReports();

    final revenue = payments
        .where((p) => p.isConfirmed)
        .fold(0.0, (sum, p) => sum + p.amount);

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
          await addCredit(CreditModel(
            id: 'credit_${paymentId}_${DateTime.now().millisecondsSinceEpoch}',
            userId: payment.userId,
            quantity: qty,
            remaining: qty,
            source: 'paiement_${payment.productType}',
            createdAt: DateTime.now(),
          ));
          // Notification à l'utilisateur
          await addNotification(AppNotification(
            id: 'notif_pay_${paymentId}_${DateTime.now().millisecondsSinceEpoch}',
            userId: payment.userId,
            type: 'paiement',
            title: 'Paiement confirmé ✓',
            body: 'Votre paiement a été validé par $adminName. '
                '$qty crédit(s) ajouté(s) à votre compte.',
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
      final snap = await _reportsCol.get();
      final list = snap.docs
          .map((d) => ReportModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
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
      {String commune = '', int days = 30}) async {
    // 1. Free trial activé globalement ?
    if (isFreeTrial) return 'free_trial';

    // 2. Quota gratuit mensuel disponible ?
    final quota = await getCurrentQuota(userId);
    if (quota.usedFreeQuota < quota.freeQuota) return 'free_quota';

    // 3. Crédits payants disponibles ?
    final required = commune.isNotEmpty
        ? getCreditsForCommune(commune, days: days)
        : 1;
    final available = await getUserAvailableCredits(userId);
    if (available >= required) return 'paid_credit';

    return 'no_right';
  }

  Future<void> consumePublicationRight(String userId,
      {String commune = '', int days = 30}) async {
    // 1. Free trial : rien à consommer
    if (isFreeTrial) return;

    // 2. Quota gratuit mensuel
    final quota = await getCurrentQuota(userId);
    if (quota.usedFreeQuota < quota.freeQuota) {
      await consumeFreeQuota(userId);
      return;
    }

    // 3. Crédits payants
    final required = commune.isNotEmpty
        ? getCreditsForCommune(commune, days: days)
        : 1;
    await consumeCredits(userId, required);
  }

  // ─── AUDIT LOGS (avec limit optionnel) ──────────────────────────────────────

  Future<List<AuditLogModel>> getAuditLogs({int? limit}) async {
    try {
      final snap = await _logsCol.get();
      final list = snap.docs
          .map((d) => AuditLogModel.fromMap(d.data() as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (limit != null && list.length > limit) {
        return list.sublist(0, limit);
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  // ─── REFRESH CACHES AU DÉMARRAGE ────────────────────────────────────────────

  Future<void> refreshAllCaches() async {
    await _refreshSettingsCache();
    await refreshZonesCache();
  }
}
