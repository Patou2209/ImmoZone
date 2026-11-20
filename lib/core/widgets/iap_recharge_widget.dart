// ============================================================================
// IapRechargeContent — Recharge de crédits via Apple In-App Purchase (iOS)
//
// Affiché UNIQUEMENT sur iOS natif (AppConstants.isIosNative) à la place du
// formulaire mobile money (Apple 3.1.1 : aucun moyen de paiement externe
// visible sur iOS pour du contenu numérique).
//
// • Les 6 produits viennent de StoreKit (prix localisés par Apple).
// • Les crédits affichés viennent de config/iap_packs (Firestore, modifiable
//   par l'admin sans re-review) avec fallback sur les valeurs par défaut.
// • Le créditage est fait CÔTÉ SERVEUR par verifyAppleReceipt après
//   validation du reçu — le client n'écrit jamais de crédits.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../theme/app_theme.dart';
import '../../services/iap_service.dart';

class IapRechargeContent extends StatefulWidget {
  const IapRechargeContent({super.key});

  @override
  State<IapRechargeContent> createState() => _IapRechargeContentState();
}

class _IapRechargeContentState extends State<IapRechargeContent> {
  final IapService _iap = IapService.instance;

  bool _loading = true;
  bool _verifying = false;   // reçu en cours de validation serveur
  bool _buying = false;      // feuille de paiement Apple ouverte
  IapResult? _result;        // résultat final (succès / échec)

  @override
  void initState() {
    super.initState();
    _iap.onVerifying = () {
      if (mounted) setState(() { _verifying = true; _buying = false; });
    };
    _iap.onPurchaseResult = (r) {
      if (mounted) {
        setState(() { _verifying = false; _buying = false; _result = r; });
      }
    };
    _init();
  }

  Future<void> _init() async {
    await _iap.init();
    if (_iap.products.isEmpty) await _iap.loadProducts();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    // On détache les callbacks UI (le service reste vivant : il doit pouvoir
    // traiter les transactions rejouées par StoreKit en arrière-plan).
    _iap.onVerifying = null;
    _iap.onPurchaseResult = null;
    super.dispose();
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() { _result = null; _buying = true; });
    final launched = await _iap.buy(product);
    if (!launched && mounted) {
      setState(() {
        _buying = false;
        _result = const IapResult(
            false, 'Impossible d\'ouvrir le paiement. Réessayez.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Header ──
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: AppTheme.accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recharger mon compte',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 15,
                      color: AppTheme.textPrimary)),
              Text('Achat intégré App Store',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          )),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: AppTheme.textHint),
          ),
        ]),
      ),
      const Divider(height: 1),

      // ── Corps ──
      Expanded(child: _buildBody()),
    ]);
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accentColor));
    }
    if (_verifying) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppTheme.accentColor),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Validation de votre achat en cours...',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: AppTheme.textSecondary),
            ),
          ),
        ],
      ));
    }
    if (_result?.success == true) return _buildSuccess(_result!);

    if (!_iap.isAvailable || _iap.products.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.storefront_outlined,
              color: AppTheme.textHint, size: 44),
          const SizedBox(height: 14),
          const Text(
            'La boutique n\'est pas disponible pour le moment. '
            'Vérifiez votre connexion puis réessayez.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () async {
              setState(() => _loading = true);
              await _iap.loadProducts();
              if (mounted) setState(() => _loading = false);
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Réessayer',
                style: TextStyle(fontFamily: 'Poppins')),
          ),
        ]),
      ));
    }

    // ── Grille des packs ──
    final products =
        _iap.products.where((p) => _iap.isPackActive(p.id)).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_result != null && !_result!.success) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.errorColor.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline,
                  color: AppTheme.errorColor, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(_result!.message,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: AppTheme.textSecondary, height: 1.4))),
            ]),
          ),
        ],
        const Text('Choisissez votre pack de crédits',
            style: TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, fontSize: 14,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        const Text(
          'Le paiement est effectué via votre compte Apple. '
          'Vos crédits sont ajoutés automatiquement.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
              color: AppTheme.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 14),
        ...products.map(_productTile),
        const SizedBox(height: 10),
        const Text(
          'Les crédits achetés sont utilisables sur toutes les plateformes '
          'ImmoZone (iOS, Android, web).',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
              color: AppTheme.textHint, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _productTile(ProductDetails p) {
    final credits = _iap.creditsFor(p.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.toll_outlined,
              color: AppTheme.accentColor, size: 20),
        ),
        title: Text('$credits crédits',
            style: const TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, fontSize: 14,
                color: AppTheme.textPrimary)),
        subtitle: Text(p.price, // prix localisé par Apple
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                color: AppTheme.textSecondary)),
        trailing: ElevatedButton(
          onPressed: _buying ? null : () => _buy(p),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentColor,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(_buying ? '...' : 'Acheter',
              style: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      ),
    );
  }

  Widget _buildSuccess(IapResult r) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.successColor.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: AppTheme.successColor, size: 56),
        ),
        const SizedBox(height: 20),
        const Text('Achat réussi !',
            style: TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w800, fontSize: 20,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 10),
        Text(
          r.message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Fermer',
                style: TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]),
    );
  }
}
