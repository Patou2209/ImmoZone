// ============================================================================
// RechargeFormWidget — Formulaire de recharge Mobile Money autonome
//
// Extrait du flux éprouvé de post_property_screen.dart (CAS 4b).
// À utiliser dans :
//   • PublicPacksScreen  (bouton "Choisir" d'un pack)
//   • ProfileScreen      (bouton "Recharger")
//   • Tout autre endroit nécessitant une recharge
//
// Usage :
//   showDialog(
//     context: context,
//     builder: (_) => RechargeDialog(
//       user: authProvider.currentUser!,
//       ds: DataService(),
//       preselectedPack: pack,          // optionnel — pré-sélectionne un pack
//     ),
//   );
// ============================================================================

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/payment_model.dart';
import '../../services/data_service.dart';
import '../../screens/payment/payment_screen.dart';

// ─── Widget Dialog public ────────────────────────────────────────────────────
class RechargeDialog extends StatelessWidget {
  final dynamic user;           // UserModel (dynamic pour éviter l'import circulaire)
  final DataService ds;
  final Map<String, dynamic>? preselectedPack; // optionnel

  const RechargeDialog({
    super.key,
    required this.user,
    required this.ds,
    this.preselectedPack,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenW > 600 ? (screenW - 520) / 2 : 16,
        vertical: 28,
      ),
      child: SizedBox(
        width: 520,
        height: screenH * 0.88,
        child: _RechargeFormContent(
          user: user,
          ds: ds,
          preselectedPack: preselectedPack,
        ),
      ),
    );
  }
}

// ─── Contenu StatefulWidget interne ─────────────────────────────────────────
class _RechargeFormContent extends StatefulWidget {
  final dynamic user;
  final DataService ds;
  final Map<String, dynamic>? preselectedPack;

  const _RechargeFormContent({
    required this.user,
    required this.ds,
    this.preselectedPack,
  });

  @override
  State<_RechargeFormContent> createState() => _RechargeFormContentState();
}

class _RechargeFormContentState extends State<_RechargeFormContent> {
  Map<String, dynamic>? _selectedPack;
  Map<String, dynamic>? _selectedMethod;
  // 🆕 Flux manuel : le user fournit le NUMÉRO qui a effectué le dépôt
  // et le MONTANT envoyé (remplace l'ancienne référence de transaction).
  final _refCtrl = TextEditingController(text: '+243 ');
  final _sentAmountCtrl = TextEditingController();
  bool _howItWorksOpen = false; // chevron « Comment ça marche ? »

  List<Map<String, dynamic>> _packs   = [];
  List<Map<String, dynamic>> _methods = [];
  bool _loading         = true;
  bool _submitting      = false;
  bool _submitted       = false;

  @override
  void initState() {
    super.initState();
    _selectedPack = widget.preselectedPack;
    _loadData();
  }

  Future<void> _loadData() async {
    await widget.ds.refreshPacksFromFirestore();
    await widget.ds.refreshPaymentMethodsFromFirestore();
    if (!mounted) return;
    setState(() {
      _packs = List<Map<String, dynamic>>.from(widget.ds.subscriptionPacks)
          .where((p) => p['active'] == true && p['type'] != 'subscription')
          .toList();
      _methods = widget.ds.paymentMethods
          .where((m) => m['active'] == true)
          .toList()
        // Orange Money (paiement automatique) toujours en premier
        ..sort((a, b) {
          final ao = (a['icon'] == 'orange') ? 0 : 1;
          final bo = (b['icon'] == 'orange') ? 0 : 1;
          return ao.compareTo(bo);
        });
      // Orange Money PRÉ-SÉLECTIONNÉ par défaut (paiement automatique).
      // L'utilisateur peut toujours choisir un autre moyen en le sélectionnant.
      if (_selectedMethod == null && _methods.isNotEmpty) {
        _selectedMethod = _methods.firstWhere(
          _isOrange,
          orElse: () => _methods.first,
        );
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _sentAmountCtrl.dispose();
    super.dispose();
  }

  bool _isOrange(Map<String, dynamic>? m) => (m?['icon'] ?? '') == 'orange';

  // ── Paiement automatique Orange Money ─────────────────────────────────────
  // Ferme le dialog et ouvre PaymentScreen (flux automatique : USSD + PIN,
  // crédits ajoutés automatiquement — aucune référence manuelle).
  void _payWithOrange() {
    if (_selectedPack == null) {
      _snack('Veuillez choisir un pack de recharge.'); return;
    }
    final pack  = _selectedPack!;
    final price = (pack['price'] as num?)?.toDouble() ?? 0.0;
    final qty   = (pack['qty'] as num?)?.toInt() ?? 0;
    final productType = pack['productType'] as String? ?? 'souscription_credits_10';
    final nav = Navigator.of(context);
    nav.pop(); // ferme le dialog de recharge
    nav.push(MaterialPageRoute(
      builder: (_) => PaymentScreen(
        productType: productType,
        amount: price,
        productLabel: pack['name'] as String? ?? 'Recharge de crédits',
        creditsQty: qty,
      ),
    ));
  }

  // ── Soumission (flux manuel : M-Pesa / Airtel) ─────────────────────────────
  Future<void> _submit() async {
    if (_selectedPack == null) {
      _snack('Veuillez choisir un pack de recharge.'); return;
    }
    if (_selectedMethod == null) {
      _snack('Veuillez choisir un moyen de paiement.'); return;
    }
    // Orange Money → jamais de flux manuel : redirige vers le flux automatique
    if (_isOrange(_selectedMethod)) { _payWithOrange(); return; }
    // 🆕 Validation : numéro de téléphone du dépôt + montant envoyé
    final depositPhone = PhoneUtils.normalizeMsisdn(_refCtrl.text);
    if (depositPhone.isEmpty || depositPhone.length < 9) {
      _snack('Veuillez saisir le numéro de téléphone qui a effectué le dépôt.');
      return;
    }
    final sentAmount = double.tryParse(
        _sentAmountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (sentAmount <= 0) {
      _snack('Veuillez saisir le montant que vous avez envoyé.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final pack   = _selectedPack!;
      final method = _selectedMethod!;
      final price  = (pack['price'] as num?)?.toDouble() ?? 0.0;
      final qty    = (pack['qty'] as num?)?.toInt() ?? 0;
      final productType = pack['productType'] as String? ?? 'souscription_credits_10';

      final payment = PaymentModel(
        id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
        userId:   widget.user.id as String,
        userName: (widget.user.name as String?) ?? (widget.user.email as String?) ?? '',
        orderId: 'ord_${DateTime.now().millisecondsSinceEpoch}',
        operator: method['icon'] ?? 'mpesa',
        phoneNumber: method['number'] ?? '',
        amount: price,
        currency: pack['currency'] ?? 'USD',
        status: 'awaiting_manual',
        transactionReference:
            'Tél. dépôt : ${_refCtrl.text.trim()} — Montant envoyé : ${_sentAmountCtrl.text.trim()} ${pack['currency'] ?? 'USD'}',
        createdAt: DateTime.now(),
        productType: productType,
        creditsQty: qty,
      );
      await widget.ds.createPayment(payment);
      if (mounted) setState(() { _submitting = false; _submitted = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack('Erreur lors de l\'envoi. Veuillez réessayer.');
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
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
              Text('Paiement Mobile Money',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          )),
          if (!_submitted)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: AppTheme.textHint),
            ),
        ]),
      ),
      const Divider(height: 1),

      // Corps
      Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _submitted
              ? _buildSuccess()
              : _buildForm(),
      ),
    ]);
  }

  // ── Formulaire ─────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── ÉTAPE 1 : Pack ────────────────────────────────────────────────
        // Si un pack a été pré-sélectionné (ex: depuis l'écran des packs),
        // on affiche UNIQUEMENT ce pack (verrouillé) — pas de redondance.
        if (widget.preselectedPack != null) ...[
          _stepBadge('1', 'Votre pack sélectionné'),
          const SizedBox(height: 10),
          _packTile(_selectedPack!, locked: true),
        ] else ...[
          _stepBadge('1', 'Choisissez une recharge de crédits'),
          const SizedBox(height: 10),
          if (_packs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Aucun pack disponible pour le moment.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      color: AppTheme.textSecondary)),
            )
          else
            ..._packs.map((pack) => _packTile(pack)),
        ],
        const SizedBox(height: 20),

        // ── ÉTAPE 2 : Choisir le moyen de paiement ─────────────────────────
        _stepBadge('2', 'Choisissez votre moyen de paiement'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
          ),
          child: Text(
            _isOrange(_selectedMethod)
                ? 'Orange Money : paiement automatique — vous recevrez une '
                  'demande de confirmation sur votre téléphone (code PIN).'
                : 'M-Pesa / Airtel : envoyez le montant au numéro correspondant, '
                  'puis indiquez ci-dessous le numéro qui a effectué le dépôt '
                  'et le montant envoyé.',
            style: const TextStyle(fontSize: 12, fontFamily: 'Poppins',
                color: AppTheme.textSecondary, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        if (_methods.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Aucun moyen de paiement configuré.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: AppTheme.textSecondary)),
          )
        else ...[
          // Orange Money (automatique) d'abord
          ..._methods.where(_isOrange).map((m) => _methodTile(m)),
          // Séparateur si les deux familles existent
          if (_methods.any(_isOrange) &&
              _methods.any((m) => !_isOrange(m))) ...[
            const SizedBox(height: 2),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('ou avec validation manuelle',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        color: AppTheme.textHint.withValues(alpha: 0.9))),
              ),
              const Expanded(child: Divider()),
            ]),
            // 🆕 « Comment ça marche ? » — chevron dépliable (flux manuel)
            InkWell(
              onTap: () => setState(() => _howItWorksOpen = !_howItWorksOpen),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Comment ça marche ?',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentColor.withValues(alpha: 0.9))),
                      const SizedBox(width: 3),
                      Icon(
                        _howItWorksOpen
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: AppTheme.accentColor.withValues(alpha: 0.9),
                      ),
                    ]),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: _howItWorksOpen
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                margin: const EdgeInsets.only(bottom: 8, top: 2),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.accentColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _howStep('1️⃣', 'Choisissez le pack qui vous convient.'),
                    _howStep('2️⃣',
                        'Envoyez le montant via M-Pesa ou Airtel Money '
                        '(depuis votre téléphone, en dehors de l\'app) '
                        'au numéro affiché ci-dessous.'),
                    _howStep('3️⃣',
                        'Revenez dans l\'app et indiquez le numéro qui a '
                        'effectué le dépôt ainsi que le montant envoyé.'),
                    _howStep('✅',
                        'Notre équipe vérifie le dépôt et vos crédits sont '
                        'ajoutés — vous recevez une notification !'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          ..._methods.where((m) => !_isOrange(m)).map((m) => _methodTile(m)),
        ],
        const SizedBox(height: 20),

        // ── ÉTAPE 3 : selon le moyen choisi ────────────────────────────────
        // Orange Money → flux AUTOMATIQUE (PaymentScreen : USSD + PIN + polling)
        // M-Pesa / Airtel → flux MANUEL (référence + validation admin)
        if (_isOrange(_selectedMethod)) ...[
          _stepBadge('3', 'Payez automatiquement avec Orange Money'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF7900).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFFF7900).withValues(alpha: 0.35)),
            ),
            child: const Row(children: [
              Icon(Icons.flash_on_rounded, color: Color(0xFFFF7900), size: 20),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Paiement instantané : confirmez avec votre code PIN, '
                'vos crédits sont ajoutés automatiquement. '
                'Aucune référence à envoyer.',
                style: TextStyle(fontSize: 12, fontFamily: 'Poppins',
                    color: AppTheme.textSecondary, height: 1.5),
              )),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _payWithOrange,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7900),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.flash_on_rounded, size: 18),
              label: const Text(
                'Payer avec Orange Money',
                style: TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Vous serez redirigé(e) vers l\'écran de paiement Orange Money.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: AppTheme.textHint, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ] else ...[
        _stepBadge('3', 'Numéro de téléphone du dépôt'),
        const SizedBox(height: 10),
        // 🆕 Numéro de téléphone qui a effectué le dépôt (+243 pré-rempli)
        TextField(
          controller: _refCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Numéro de téléphone',
            labelStyle: const TextStyle(fontFamily: 'Poppins',
                fontSize: 13, color: AppTheme.textHint),
            hintText: 'Ex : +243 0800000...',
            hintStyle: const TextStyle(fontFamily: 'Poppins',
                fontSize: 13, color: AppTheme.textHint),
            prefixIcon: const Icon(Icons.phone_android_rounded,
                color: AppTheme.textHint, size: 20),
            filled: true, fillColor: const Color(0xFFF5F7FA),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.dividerColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          ),
        ),
        const SizedBox(height: 10),
        // 🆕 Montant envoyé
        TextField(
          controller: _sentAmountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Montant envoyé (USD)',
            labelStyle: const TextStyle(fontFamily: 'Poppins',
                fontSize: 13, color: AppTheme.textHint),
            hintText: 'Ex : 10',
            hintStyle: const TextStyle(fontFamily: 'Poppins',
                fontSize: 13, color: AppTheme.textHint),
            prefixIcon: const Icon(Icons.attach_money_rounded,
                color: AppTheme.textHint, size: 20),
            filled: true, fillColor: const Color(0xFFF5F7FA),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.dividerColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _submitting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            // 🆕 Sans gras + taille réduite + 1 seule ligne (ne se coupe plus
            // en deux sur les petits écrans)
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _submitting ? 'Envoi en cours...' : 'Soumettre ma demande de recharge',
                maxLines: 1,
                style: const TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500, fontSize: 12.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Après soumission, l\'administrateur validera votre paiement '
          'et ajoutera vos crédits.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: AppTheme.textHint, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ],
      ]),
    );
  }

  // ── Écran de succès ────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
          const Text('Demande envoyée !',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                  fontSize: 20, color: AppTheme.textPrimary)),
          const SizedBox(height: 10),
          const Text(
            'Votre demande de recharge a été transmise à l\'administrateur.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.35)),
            ),
            child: Column(children: [
              _waitingRow(Icons.check_circle_outline, AppTheme.successColor,
                  'Paiement soumis',
                  'Votre numéro de dépôt et le montant ont été enregistrés.'),
              const SizedBox(height: 12),
              _waitingRow(Icons.admin_panel_settings, AppTheme.warningColor,
                  'Validation admin en cours',
                  'L\'administrateur va vérifier et approuver votre paiement.'),
              const SizedBox(height: 12),
              _waitingRow(Icons.toll_outlined, AppTheme.textHint,
                  'Crédits ajoutés après approbation',
                  'Vous serez notifié(e) dès que vos crédits seront disponibles.'),
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Fermer',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tiles ─────────────────────────────────────────────────────────────────
  Widget _packTile(Map<String, dynamic> pack, {bool locked = false}) {
    final isSelected = locked || _selectedPack?['id'] == pack['id'];
    final qty   = (pack['qty'] as num?)?.toInt() ?? 0;
    final price = (pack['price'] as num?)?.toDouble() ?? 0.0;
    final cur   = pack['currency'] ?? 'USD';

    return MouseRegion(
      cursor: locked ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: locked ? null : () => setState(() => _selectedPack = pack),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.accentColor : AppTheme.dividerColor,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.2)
                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.toll_outlined,
                  color: isSelected ? Colors.white : AppTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pack['name'] ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  )),
              Text('$qty crédit${qty > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
                    color: isSelected ? Colors.white70 : AppTheme.textSecondary,
                  )),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accentColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '\$${price.toStringAsFixed(2)} $cur',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.accentColor : AppTheme.textHint, size: 22,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _methodTile(Map<String, dynamic> m) {
    final isSelected = _selectedMethod?['id'] == m['id'];
    final isOrange   = _isOrange(m);
    const orangeColor = Color(0xFFFF7900);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _selectedMethod = m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? (isOrange
                    ? orangeColor.withValues(alpha: 0.06)
                    : AppTheme.primaryColor.withValues(alpha: 0.06))
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? (isOrange ? orangeColor : AppTheme.accentColor)
                  : (isOrange
                      ? orangeColor.withValues(alpha: 0.4)
                      : AppTheme.dividerColor),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(children: [
            _operatorLogo(m['icon'] ?? 'other'),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(m['name'] ?? '',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700, fontSize: 14,
                        color: AppTheme.textPrimary))),
                if (isOrange) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A651),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.flash_on_rounded,
                          color: Colors.white, size: 11),
                      Text('AUTOMATIQUE',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontWeight: FontWeight.w800, fontSize: 9,
                              color: Colors.white)),
                    ]),
                  ),
                ],
              ]),
              if (isOrange)
                const Text('Paiement instantané — aucune référence à envoyer',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w600, color: orangeColor))
              else
                Text(m['number'] ?? '',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                        fontWeight: FontWeight.w800, color: AppTheme.accentColor,
                        letterSpacing: 0.5)),
            ])),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected
                  ? (isOrange ? orangeColor : AppTheme.accentColor)
                  : AppTheme.textHint,
              size: 22,
            ),
          ]),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  // 🆕 Ligne d'étape du « Comment ça marche ? »
  Widget _howStep(String emoji, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary, height: 1.45)),
          ),
        ]),
      );

  Widget _stepBadge(String number, String label) {
    return Row(children: [
      Container(
        width: 24, height: 24,
        decoration: const BoxDecoration(color: AppTheme.accentColor, shape: BoxShape.circle),
        child: Center(child: Text(number,
            style: const TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white))),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(label,
          style: const TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary))),
    ]);
  }

  Widget _waitingRow(IconData icon, Color color, String title, String subtitle) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
            fontWeight: FontWeight.w700, color: color)),
        Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
            color: AppTheme.textSecondary, height: 1.4)),
      ])),
    ]);
  }

  Widget _operatorLogo(String type) {
    // Logos officiels embarqués (assets locaux, pas de réseau requis)
    const assets = <String, String>{
      'mpesa':  'assets/images/mpesa_logo.png',
      'orange': 'assets/images/orange_money_logo.png',
      'airtel': 'assets/images/airtel_money_logo.png',
    };
    const colors = <String, Color>{
      'mpesa':  Color(0xFF00A651),
      'orange': Color(0xFFFF7900),
      'airtel': Color(0xFFE40000),
    };
    const size = 52.0;
    final asset = assets[type];
    final color = colors[type] ?? AppTheme.accentColor;

    if (asset != null) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 6)],
        ),
        padding: const EdgeInsets.all(5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(asset, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.payment, color: color, size: size * 0.5)),
        ),
      );
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Icon(Icons.payment, color: color, size: size * 0.5),
    );
  }
}
