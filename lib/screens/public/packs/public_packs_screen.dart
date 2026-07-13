import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/immozone_app_bar.dart';
import '../../../services/data_service.dart';
import '../../../providers/auth_provider.dart';

class PublicPacksScreen extends StatefulWidget {
  const PublicPacksScreen({super.key});
  @override
  State<PublicPacksScreen> createState() => _PublicPacksScreenState();
}

class _PublicPacksScreenState extends State<PublicPacksScreen> {
  final _ds = DataService();
  List<Map<String, dynamic>> _packs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _ds.refreshPacksFromFirestore();
    if (!mounted) return;
    setState(() {
      _packs = List<Map<String, dynamic>>.from(_ds.subscriptionPacks)
          .where((p) => p['active'] == true)
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final subs = _packs.where((p) => p['type'] == 'subscription').toList();
    final pubs = _packs.where((p) => p['type'] != 'subscription').toList();

    // Card width: fixed 160px — same size on mobile AND desktop
    const double cardW = 160.0;
    const double cardH = 190.0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: const ImmoZoneAppBar(title: 'Recharger'),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
            : RefreshIndicator(
                color: AppTheme.accentColor,
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // ── ABONNEMENTS ─────────────────────────────────────────
                    if (subs.isNotEmpty) ...[
                      _sectionHeader('Abonnements Mensuels & Annuels'),
                      const SizedBox(height: 4),
                      const Text('Publications illimitées — idéal pour les professionnels',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                              color: AppTheme.textSecondary)),
                      const SizedBox(height: 14),
                      // Subscriptions also capped to 400px max
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          children: subs.map((s) => _subscriptionCard(s)).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── PACKS PUBLICATIONS ──────────────────────────────────
                    if (pubs.isNotEmpty) ...[
                      _sectionHeader('Packs de Publications'),
                      const SizedBox(height: 4),
                      const Text('Achetez des publications à l\'unité ou en lot',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                              color: AppTheme.textSecondary)),
                      const SizedBox(height: 14),
                      // Wrap = fixed 160px cards — never stretches on desktop
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: pubs.map((p) => SizedBox(
                          width: cardW,
                          height: cardH,
                          child: _pubPackCard(p),
                        )).toList(),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ]),
                ),
              ),
      ),
    );
  }

  // ── PAYMENT DIALOG ──────────────────────────────────────────────────────────

  void _showPaymentSheet(BuildContext ctx, Map<String, dynamic> pack) {
    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Veuillez vous connecter pour acheter un pack.',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.errorColor,
      ));
      return;
    }
    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => _PaymentDialog(pack: pack, user: user, ds: _ds),
    );
  }

  Widget _sectionHeader(String title) => Text(title,
      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
          fontSize: 16, color: AppTheme.textPrimary));

  Widget _subscriptionCard(Map<String, dynamic> pack) {
    final isMonthly = (pack['qty'] ?? 0) == -1;
    final isAnnual  = (pack['qty'] ?? 0) == -2;
    final price    = (pack['price'] as num).toDouble();
    final currency = pack['currency'] ?? 'USD';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isMonthly ? Icons.calendar_month_rounded : Icons.calendar_today_rounded,
                color: AppTheme.primaryColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pack['name'] ?? '',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 14, color: AppTheme.textPrimary)),
            Text(isMonthly ? 'Illimité par mois' : isAnnual ? 'Illimité par an' : 'Publications illimitées',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary)),
          ])),
          if (isAnnual)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('MEILLEURE OFFRE',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$price',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                  fontSize: 30, color: AppTheme.accentColor)),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(currency,
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 14, color: AppTheme.accentColor)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Text(isMonthly ? '/ mois' : '/ an',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.textSecondary)),
          ),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Choisir',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
        ),
      ]),
    );
  }

  Widget _pubPackCard(Map<String, dynamic> pack) {
    final qty      = pack['qty'] as int? ?? 1;
    final price    = (pack['price'] as num).toDouble();
    final currency = pack['currency'] ?? 'USD';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: AppTheme.accentColor, size: 18),
          ),
          const SizedBox(height: 8),
          Text(pack['name'] ?? '',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 11, color: AppTheme.textPrimary),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text('$price $currency',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                  fontSize: 15, color: AppTheme.accentColor)),
          Text('$qty publication${qty > 1 ? 's' : ''}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showPaymentSheet(context, pack),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 11),
              ),
              child: const Text('Choisir'),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PaymentDialog — Dialog (pas bottom sheet) pour éviter bugs de gestes web
// ══════════════════════════════════════════════════════════════════════════════
class _PaymentDialog extends StatefulWidget {
  final Map<String, dynamic> pack;
  final dynamic user;
  final DataService ds;
  const _PaymentDialog({required this.pack, required this.user, required this.ds});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  // Étapes : 0=choix opérateur, 1=saisie numéro+ref, 2=confirmation envoyée
  int _step = 0;
  String? _selectedOperator;
  final _phoneCtrl = TextEditingController();
  final _refCtrl   = TextEditingController();
  bool _sending = false;

  static const _operators = [
    {'id': 'orange_money',  'name': 'Orange Money',  'color': 0xFFFF6600, 'icon': Icons.cell_tower},
    {'id': 'mpesa',         'name': 'M-Pesa',         'color': 0xFF00A86B, 'icon': Icons.payments_outlined},
    {'id': 'airtel_money',  'name': 'Airtel Money',   'color': 0xFFE4002B, 'icon': Icons.account_balance_wallet_outlined},
  ];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    final phone = _phoneCtrl.text.trim();
    final ref   = _refCtrl.text.trim();
    if (phone.isEmpty) {
      _snack('Veuillez saisir votre numéro de téléphone.'); return;
    }
    if (ref.isEmpty) {
      _snack('Veuillez saisir la référence de transaction.'); return;
    }
    setState(() => _sending = true);
    try {
      final qty    = widget.pack['qty'] as int? ?? 0;
      final price  = (widget.pack['price'] as num).toDouble();
      final currency = widget.pack['currency'] ?? 'USD';
      final packName = widget.pack['name'] ?? '';

      await widget.ds.submitManualPaymentRequest(
        userId: widget.user.uid,
        userName: widget.user.displayName ?? widget.user.email ?? '',
        packId: widget.pack['id'] ?? '',
        packName: packName,
        credits: qty,
        amount: price,
        currency: currency,
        operator: _selectedOperator!,
        phoneNumber: phone,
        transactionRef: ref,
      );
      if (mounted) setState(() { _step = 2; _sending = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
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

  @override
  Widget build(BuildContext context) {
    final qty      = widget.pack['qty'] as int? ?? 0;
    final price    = (widget.pack['price'] as num).toDouble();
    final currency = widget.pack['currency'] ?? 'USD';
    final screenH  = MediaQuery.of(context).size.height;
    final screenW  = MediaQuery.of(context).size.width;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenW > 600 ? (screenW - 520) / 2 : 16,
        vertical: 32,
      ),
      child: SizedBox(
        width: 520,
        height: screenH * 0.82,
        child: Column(children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppTheme.accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.pack['name'] ?? '',
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700, fontSize: 15,
                          color: AppTheme.textPrimary)),
                  Text('$qty crédits · $price $currency',
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              )),
              if (_step < 2)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppTheme.textHint),
                ),
            ]),
          ),
          const Divider(height: 1),
          // ── Contenu — SingleChildScrollView simple, aucun controller partagé ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _step == 0
                  ? _buildOperatorStep()
                  : _step == 1
                      ? _buildDetailsStep()
                      : _buildConfirmationStep(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildOperatorStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Choisissez votre opérateur Mobile Money',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
              fontSize: 15, color: AppTheme.textPrimary)),
      const SizedBox(height: 6),
      const Text('Sélectionnez le service avec lequel vous effectuerez le paiement.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
              color: AppTheme.textSecondary, height: 1.5)),
      const SizedBox(height: 20),
      ..._operators.map((op) {
        final isSelected = _selectedOperator == op['id'];
        final color = Color(op['color'] as int);
        final opId  = op['id'] as String;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: isSelected ? color.withValues(alpha: 0.07) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _selectedOperator = opId),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? color : AppTheme.dividerColor,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(op['icon'] as IconData, color: color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(op['name'] as String,
                      style: TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700, fontSize: 14,
                          color: isSelected ? color : AppTheme.textPrimary))),
                  if (isSelected)
                    Icon(Icons.check_circle_rounded, color: color, size: 22),
                ]),
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _selectedOperator == null
              ? null
              : () => setState(() => _step = 1),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppTheme.dividerColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Continuer',
              style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    ]);
  }

  Widget _buildDetailsStep() {
    final op = _operators.firstWhere((o) => o['id'] == _selectedOperator);
    final opColor = Color(op['color'] as int);
    final price   = (widget.pack['price'] as num).toDouble();
    final currency = widget.pack['currency'] ?? 'USD';

    // Numéros marchands par opérateur
    const merchantNumbers = {
      'orange_money': '+243 8X XXX XXXX',
      'mpesa':        '+243 9X XXX XXXX',
      'airtel_money': '+243 9X XXX XXXX',
    };
    final merchantNum = merchantNumbers[_selectedOperator] ?? 'À configurer';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Opérateur sélectionné
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: opColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: opColor.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(op['icon'] as IconData, color: opColor, size: 20),
          const SizedBox(width: 10),
          Text(op['name'] as String,
              style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 13, color: opColor)),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() { _step = 0; _selectedOperator = null; }),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Changer',
                style: TextStyle(fontFamily: 'Poppins',
                    fontSize: 11, color: AppTheme.primaryColor,
                    decoration: TextDecoration.underline)),
          ),
        ]),
      ),
      const SizedBox(height: 16),

      // Instruction de paiement
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.info_outline, color: AppTheme.primaryColor, size: 18),
            const SizedBox(width: 8),
            const Text('Instructions de paiement',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 13, color: AppTheme.primaryColor)),
          ]),
          const SizedBox(height: 10),
          _instructionRow('1', 'Envoyez $price $currency au numéro ImmoZone :'),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(children: [
              const Icon(Icons.phone_rounded, color: AppTheme.accentColor, size: 16),
              const SizedBox(width: 8),
              Text(merchantNum,
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800, fontSize: 14,
                      color: AppTheme.textPrimary)),
            ]),
          ),
          const SizedBox(height: 10),
          _instructionRow('2', 'Notez la référence de la transaction reçue.'),
          const SizedBox(height: 6),
          _instructionRow('3', 'Remplissez le formulaire ci-dessous et soumettez.'),
        ]),
      ),
      const SizedBox(height: 20),

      // Formulaire
      const Text('Votre numéro de téléphone',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
              fontSize: 13, color: AppTheme.textPrimary)),
      const SizedBox(height: 6),
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Ex: +243 81 234 5678',
          hintStyle: const TextStyle(fontFamily: 'Poppins',
              fontSize: 13, color: AppTheme.textHint),
          prefixIcon: const Icon(Icons.phone_outlined, color: AppTheme.textHint, size: 20),
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
      const SizedBox(height: 16),
      const Text('Référence de transaction',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
              fontSize: 13, color: AppTheme.textPrimary)),
      const SizedBox(height: 6),
      TextField(
        controller: _refCtrl,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Ex: TXN-20241201-XXXXX',
          hintStyle: const TextStyle(fontFamily: 'Poppins',
              fontSize: 13, color: AppTheme.textHint),
          prefixIcon: const Icon(Icons.receipt_outlined, color: AppTheme.textHint, size: 20),
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
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _sending ? null : _submitPayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _sending
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Soumettre la demande',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    ]);
  }

  Widget _buildConfirmationStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
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
            _confirmRow(Icons.check_circle_outline, AppTheme.successColor,
                'Demande enregistrée'),
            const SizedBox(height: 10),
            _confirmRow(Icons.admin_panel_settings, AppTheme.warningColor,
                'Validation admin en cours'),
            const SizedBox(height: 10),
            _confirmRow(Icons.toll_outlined, AppTheme.textHint,
                'Crédits ajoutés après approbation'),
          ]),
        ),
        const SizedBox(height: 24),
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
    );
  }

  Widget _instructionRow(String num, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 20, height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          shape: BoxShape.circle,
        ),
        child: Text(num, style: const TextStyle(fontFamily: 'Poppins',
            fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
              color: AppTheme.textSecondary, height: 1.4))),
    ],
  );

  Widget _confirmRow(IconData icon, Color color, String text) => Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 10),
    Text(text, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
        color: AppTheme.textPrimary)),
  ]);
}
