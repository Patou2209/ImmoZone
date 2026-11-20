// ============================================================================
// IapService — Achats intégrés Apple (StoreKit) pour les packs de crédits iOS
//
// ARCHITECTURE (décision user — parité totale, Apple 3.1.3(b) conforme) :
//   • Les produits App Store Connect sont des paliers de PRIX figés
//     (consommables) : credits_3usd … credits_100usd.
//   • Les CRÉDITS livrés pour chaque produit viennent de Firestore
//     (config/iap_packs — modifiable par l'admin SANS re-review Apple).
//   • La validation du reçu + le créditage se font CÔTÉ SERVEUR via la
//     Cloud Function `verifyAppleReceipt` (anti-rejeu par transactionId) :
//     le client n'écrit JAMAIS de crédits lui-même.
//   • Les crédits sont cross-platform : achetés sur iOS, utilisables
//     partout, et inversement (exigence Apple 3.1.3(b) respectée).
//
// FLUX :
//   1. loadProducts()  → StoreKit renvoie prix localisés des 6 produits.
//   2. buy(productId)  → feuille de paiement Apple native.
//   3. purchaseStream  → PurchaseStatus.purchased/restored
//        → _verifyAndCredit() POST vers verifyAppleReceipt
//        → la CF valide via l'App Store Server API, crée le PaymentModel
//          'confirmed' (operator 'apple_iap'), le CreditModel, et déclenche
//          le parrainage — exactement comme confirmPayment().
//        → completePurchase() UNIQUEMENT si la CF a répondu OK
//          (sinon la transaction reste en file → retry au prochain launch).
//   4. restorePurchases() n'est pas exposé (consommables), mais les
//      transactions non terminées sont rejouées automatiquement par
//      StoreKit au démarrage via le même stream.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

/// Résultat livré à l'UI après le traitement d'un achat.
class IapResult {
  final bool success;
  final String message;
  final int creditsDelivered;
  const IapResult(this.success, this.message, {this.creditsDelivered = 0});
}

class IapService {
  IapService._();
  static final IapService instance = IapService._();

  // ── Produits ASC (IDs figés — NE PAS MODIFIER sans créer le produit ASC) ──
  static const String _idPrefix = 'com.immozone.estate.';
  static const List<String> productIds = [
    '${_idPrefix}credits_3usd',
    '${_idPrefix}credits_5usd',
    '${_idPrefix}credits_10usd',
    '${_idPrefix}credits_20usd',
    '${_idPrefix}credits_50usd',
    '${_idPrefix}credits_100usd',
  ];

  /// Fallback si config/iap_packs est absent — DOIT refléter les packs
  /// actuels (parité Android/web). La vérité modifiable vit dans Firestore.
  static const Map<String, int> _defaultCredits = {
    '${_idPrefix}credits_3usd': 30,
    '${_idPrefix}credits_5usd': 55,
    '${_idPrefix}credits_10usd': 120,
    '${_idPrefix}credits_20usd': 250,
    '${_idPrefix}credits_50usd': 700,
    '${_idPrefix}credits_100usd': 1600,
  };

  static const String _verifyUrl =
      'https://us-central1-immozone-d9a68.cloudfunctions.net/verifyAppleReceipt';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  List<ProductDetails> _products = [];
  Map<String, int> _creditsMap = Map.of(_defaultCredits);
  final Map<String, dynamic> _packMeta = {}; // meta facultative (badge, actif…)

  /// Callback UI : résultat d'un achat (succès/échec après vérif serveur).
  void Function(IapResult result)? onPurchaseResult;

  /// Callback UI : un achat est en cours de vérification serveur.
  void Function()? onVerifying;

  bool get isAvailable => _available;
  List<ProductDetails> get products => List.unmodifiable(_products);

  /// Crédits livrés pour un productId (config Firestore, fallback défauts).
  int creditsFor(String productId) =>
      _creditsMap[productId] ?? _defaultCredits[productId] ?? 0;

  /// Un pack peut être désactivé côté admin sans toucher à ASC.
  bool isPackActive(String productId) {
    final meta = _packMeta[productId];
    if (meta is Map && meta['active'] == false) return false;
    return true;
  }

  // ── Initialisation (à appeler une fois, au premier affichage iOS) ─────────
  Future<void> init() async {
    if (_sub != null) return; // déjà initialisé
    _available = await _iap.isAvailable();
    if (!_available) {
      if (kDebugMode) debugPrint('[IAP] Store indisponible');
      return;
    }
    // Écoute AVANT toute requête : StoreKit rejoue ici les transactions
    // interrompues (app tuée pendant un achat, vérif serveur échouée…).
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        if (kDebugMode) debugPrint('[IAP] purchaseStream error: $e');
      },
    );
    await Future.wait([_loadCreditsConfig(), loadProducts()]);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  // ── Mapping crédits depuis Firestore (modifiable sans re-review) ──────────
  Future<void> _loadCreditsConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('iap_packs')
          .get();
      final data = doc.data();
      if (data == null) return;
      final packs = data['packs'];
      if (packs is Map) {
        final merged = Map.of(_defaultCredits);
        packs.forEach((key, value) {
          final id = key.toString();
          if (value is num) {
            merged[id] = value.toInt();
          } else if (value is Map) {
            final c = value['credits'];
            if (c is num) merged[id] = c.toInt();
            _packMeta[id] = value;
          }
        });
        _creditsMap = merged;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[IAP] config iap_packs: $e (fallback défauts)');
    }
  }

  // ── Chargement des produits StoreKit (prix localisés) ─────────────────────
  Future<void> loadProducts() async {
    if (!_available) return;
    try {
      final resp = await _iap.queryProductDetails(productIds.toSet());
      if (resp.notFoundIDs.isNotEmpty && kDebugMode) {
        debugPrint('[IAP] produits introuvables: ${resp.notFoundIDs}');
      }
      _products = resp.productDetails
        ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    } catch (e) {
      if (kDebugMode) debugPrint('[IAP] queryProductDetails: $e');
    }
  }

  // ── Achat ──────────────────────────────────────────────────────────────────
  Future<bool> buy(ProductDetails product) async {
    if (!_available) return false;
    try {
      return await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[IAP] buy: $e');
      return false;
    }
  }

  // ── Traitement du stream de transactions ──────────────────────────────────
  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // Feuille de paiement Apple affichée / Ask to Buy — rien à faire.
          break;
        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          onPurchaseResult?.call(const IapResult(false, 'Achat annulé.'));
          break;
        case PurchaseStatus.error:
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          onPurchaseResult?.call(IapResult(
              false, 'Erreur d\'achat : ${p.error?.message ?? 'inconnue'}'));
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          onVerifying?.call();
          final result = await _verifyAndCredit(p);
          // completePurchase SEULEMENT si le serveur a crédité (ou rejeu
          // déjà traité) — sinon la transaction reste en file pour retry.
          if (result.success && p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          onPurchaseResult?.call(result);
          break;
      }
    }
  }

  // ── Vérification serveur + créditage (Cloud Function) ─────────────────────
  Future<IapResult> _verifyAndCredit(PurchaseDetails p) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const IapResult(false,
          'Session expirée. Reconnectez-vous puis relancez l\'application : '
          'votre achat sera automatiquement récupéré.');
    }
    try {
      final idToken = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse(_verifyUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'productId': p.productID,
              'transactionId': p.purchaseID ?? '',
              'receiptData': p.verificationData.serverVerificationData,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        final credits = (body['credits'] as num?)?.toInt() ?? 0;
        final already = body['alreadyProcessed'] == true;
        return IapResult(
          true,
          already
              ? 'Achat déjà crédité.'
              : '$credits crédits ajoutés à votre compte !',
          creditsDelivered: credits,
        );
      }
      return IapResult(false,
          (body['error'] as String?) ?? 'La vérification de l\'achat a échoué. '
              'Elle sera retentée automatiquement au prochain démarrage.');
    } catch (e) {
      if (kDebugMode) debugPrint('[IAP] verifyAppleReceipt: $e');
      return const IapResult(false,
          'Connexion impossible pour valider l\'achat. '
          'Il sera automatiquement validé au prochain démarrage.');
    }
  }
}
