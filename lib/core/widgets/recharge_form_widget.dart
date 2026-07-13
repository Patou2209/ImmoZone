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
import '../../models/payment_model.dart';
import '../../services/data_service.dart';

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
  final _refCtrl = TextEditingController();

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
          .toList();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  // ── Soumission ─────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_selectedPack == null) {
      _snack('Veuillez choisir un pack de recharge.'); return;
    }
    if (_selectedMethod == null) {
      _snack('Veuillez choisir un moyen de paiement.'); return;
    }
    if (_refCtrl.text.trim().isEmpty) {
      _snack('Veuillez saisir la référence de votre paiement.'); return;
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
        transactionReference: _refCtrl.text.trim(),
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

        // ── ÉTAPE 1 : Choisir le pack ──────────────────────────────────────
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
        const SizedBox(height: 20),

        // ── ÉTAPE 2 : Choisir le moyen de paiement ─────────────────────────
        _stepBadge('2', 'Effectuez le paiement Mobile Money'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
          ),
          child: const Text(
            'Envoyez le montant au numéro correspondant, '
            'puis saisissez votre référence de transaction ci-dessous.',
            style: TextStyle(fontSize: 12, fontFamily: 'Poppins',
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
        else
          ..._methods.map((m) => _methodTile(m)),
        const SizedBox(height: 20),

        // ── ÉTAPE 3 : Référence + Soumettre ────────────────────────────────
        _stepBadge('3', 'Saisissez votre référence de paiement'),
        const SizedBox(height: 10),
        TextField(
          controller: _refCtrl,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Ex: TXN-20241201-XXXXX',
            hintStyle: const TextStyle(fontFamily: 'Poppins',
                fontSize: 13, color: AppTheme.textHint),
            prefixIcon: const Icon(Icons.receipt_long_outlined,
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
            label: Text(
              _submitting ? 'Envoi en cours...' : 'Soumettre ma demande de recharge',
              style: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 14),
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
                  'Votre référence de transaction a été enregistrée.'),
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
  Widget _packTile(Map<String, dynamic> pack) {
    final isSelected = _selectedPack?['id'] == pack['id'];
    final qty   = (pack['qty'] as num?)?.toInt() ?? 0;
    final price = (pack['price'] as num?)?.toDouble() ?? 0.0;
    final cur   = pack['currency'] ?? 'USD';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _selectedPack = pack),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _selectedMethod = m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.accentColor : AppTheme.dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(children: [
            _operatorLogo(m['icon'] ?? 'other'),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['name'] ?? '',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 14,
                      color: AppTheme.textPrimary)),
              Text(m['number'] ?? '',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                      fontWeight: FontWeight.w800, color: AppTheme.accentColor,
                      letterSpacing: 0.5)),
            ])),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.accentColor : AppTheme.textHint, size: 22,
            ),
          ]),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
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
    const logos = <String, String>{
      'mpesa':  'https://upload.wikimedia.org/wikipedia/commons/thumb/1/15/M-PESA_LOGO-01.svg/320px-M-PESA_LOGO-01.svg.png',
      'orange': 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Orange_logo.svg/240px-Orange_logo.svg.png',
      'airtel': 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/Airtel_Africa_logo.svg/320px-Airtel_Africa_logo.svg.png',
    };
    const colors = <String, Color>{
      'mpesa':  Color(0xFF00A651),
      'orange': Color(0xFFFF7900),
      'airtel': Color(0xFFE40000),
    };
    const size = 52.0;
    final url   = logos[type];
    final color = colors[type] ?? AppTheme.accentColor;

    if (url != null) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 6)],
        ),
        padding: const EdgeInsets.all(5),
        child: Image.network(url, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.payment, color: color, size: size * 0.5)),
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
