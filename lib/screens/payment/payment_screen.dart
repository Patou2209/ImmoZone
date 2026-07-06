import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/payment_model.dart';
import '../../services/data_service.dart';

class PaymentScreen extends StatefulWidget {
  final String productType;
  final double amount;
  final String productLabel;
  final String? propertyId;

  const PaymentScreen({
    super.key,
    required this.productType,
    required this.amount,
    required this.productLabel,
    this.propertyId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _ds = DataService();
  String _selectedOperator = 'mpesa';
  final _phoneCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  bool _isLoading = false;
  bool _paymentCreated = false;
  String? _paymentId;
  bool _useManualValidation = false;

  final _operators = [
    {'id': 'mpesa', 'name': 'M-Pesa', 'color': const Color(0xFF00B140), 'icon': Icons.phone_android},
    {'id': 'orange_money', 'name': 'Orange Money', 'color': const Color(0xFFFF7900), 'icon': Icons.account_balance_wallet},
    {'id': 'airtel_money', 'name': 'Airtel Money', 'color': const Color(0xFFE40000), 'icon': Icons.payment},
  ];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _initiatePayment() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      _showMsg('Veuillez entrer votre numéro de téléphone', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    final paymentId = 'pay_${DateTime.now().millisecondsSinceEpoch}';
    final orderId = 'ord_${DateTime.now().millisecondsSinceEpoch}';
    await _ds.createPayment(PaymentModel(
      id: paymentId,
      userId: _ds.currentUserId,
      orderId: orderId,
      operator: _useManualValidation ? 'manual' : _selectedOperator,
      phoneNumber: _phoneCtrl.text.trim(),
      amount: widget.amount,
      productType: widget.productType,
      status: _useManualValidation ? 'awaiting_manual' : 'pending',
      transactionReference: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      propertyId: widget.propertyId,
      createdAt: DateTime.now(),
    ));
    setState(() { _isLoading = false; _paymentCreated = true; _paymentId = paymentId; });
  }

  void _showMsg(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('Paiement Mobile Money')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _paymentCreated ? _buildConfirmation() : _buildPaymentForm(),
        ),
      ),
    );
  }

  Widget _buildPaymentForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Récapitulatif commande
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppTheme.primaryColor, AppTheme.primaryDark]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shopping_cart, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.productLabel,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('${widget.amount.toStringAsFixed(2)} USD',
                        style: const TextStyle(color: Colors.white, fontFamily: 'Poppins',
                            fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Mode de paiement
        Row(
          children: [
            _modeChip('Mobile Money', !_useManualValidation, () => setState(() => _useManualValidation = false)),
            const SizedBox(width: 10),
            _modeChip('Déjà payé (réf.)', _useManualValidation, () => setState(() => _useManualValidation = true)),
          ],
        ),
        const SizedBox(height: 20),

        if (!_useManualValidation) ...[
          const Text('Choisissez votre opérateur',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                  fontSize: 14, color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          Row(
            children: _operators.map((op) => Expanded(
              child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                onTap: () => setState(() => _selectedOperator = op['id'] as String),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _selectedOperator == op['id']
                        ? (op['color'] as Color).withValues(alpha: 0.12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedOperator == op['id']
                          ? op['color'] as Color
                          : AppTheme.dividerColor,
                      width: _selectedOperator == op['id'] ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(op['icon'] as IconData,
                          color: op['color'] as Color, size: 24),
                      const SizedBox(height: 4),
                      Text(op['name'] as String,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _selectedOperator == op['id']
                                  ? op['color'] as Color
                                  : AppTheme.textSecondary),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              )),
            )).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Numéro de téléphone
        _label('Numéro de téléphone Mobile Money *'),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 15),
          decoration: _inputDeco(
            hint: '+243 8XX XXX XXX',
            icon: Icons.phone,
          ),
        ),
        const SizedBox(height: 16),

        if (_useManualValidation) ...[
          _label('Référence de transaction *'),
          const SizedBox(height: 8),
          TextField(
            controller: _refCtrl,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 15),
            decoration: _inputDeco(
              hint: 'ex: MP240421001',
              icon: Icons.confirmation_number,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Soumettez votre référence de transaction. Un administrateur ImmoZone validera votre paiement dans les plus brefs délais.',
                    style: TextStyle(fontSize: 11, fontFamily: 'Poppins',
                        color: Color(0xFF5D4037), height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Instructions de paiement :',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                        fontSize: 12, color: Color(0xFF1B5E20))),
                const SizedBox(height: 6),
                _step('1', 'Ouvrez votre application Mobile Money'),
                _step('2', 'Envoyez ${widget.amount.toStringAsFixed(2)} USD au numéro ImmoZone'),
                _step('3', 'Notez la référence de transaction'),
                _step('4', 'Revenez ici pour confirmer'),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _initiatePayment,
            icon: _isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send, size: 18),
            label: Text(
              _useManualValidation ? 'Soumettre pour validation' : 'Initier le paiement',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmation() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppTheme.successColor.withValues(alpha: 0.2),
                blurRadius: 20, spreadRadius: 5)],
          ),
          child: Icon(
            _useManualValidation ? Icons.hourglass_top : Icons.check_circle,
            color: _useManualValidation ? Colors.orange : AppTheme.successColor,
            size: 64,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _useManualValidation ? 'En attente de validation' : 'Paiement initié !',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 22,
              fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          _useManualValidation
              ? 'Votre demande a été soumise. Un administrateur ImmoZone vérifiera votre référence de transaction et créditera vos droits de publication dans les plus brefs délais.'
              : 'Votre commande a été créée. Après confirmation du paiement Mobile Money, vos droits de publication seront crédités automatiquement.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Column(
            children: [
              _summaryRow('Produit', widget.productLabel),
              const Divider(height: 16),
              _summaryRow('Montant', '${widget.amount.toStringAsFixed(2)} USD'),
              const Divider(height: 16),
              _summaryRow('Réf. commande', _paymentId ?? '—'),
              const Divider(height: 16),
              _summaryRow('Statut',
                  _useManualValidation ? 'Vérification manuelle' : 'En attente de confirmation'),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Retour', style: TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _modeChip(String label, bool selected, VoidCallback onTap) => MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primaryColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? AppTheme.primaryColor : AppTheme.dividerColor),
      ),
      child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.textSecondary)),
    ),
  ));

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
          fontWeight: FontWeight.w600, color: AppTheme.textPrimary));

  InputDecoration _inputDeco({required String hint, required IconData icon}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppTheme.textHint, fontFamily: 'Poppins', fontSize: 13),
    prefixIcon: Icon(icon, color: AppTheme.accentColor, size: 20),
    filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.dividerColor)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.dividerColor)),
  );

  Widget _step(String num, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Container(
          width: 18, height: 18,
          decoration: const BoxDecoration(color: Color(0xFF1B5E20), shape: BoxShape.circle),
          child: Center(child: Text(num,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
            style: const TextStyle(fontSize: 11, fontFamily: 'Poppins', color: Color(0xFF1B5E20)))),
      ],
    ),
  );

  Widget _summaryRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
          color: AppTheme.textSecondary)),
      Flexible(child: Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
          fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          textAlign: TextAlign.right)),
    ],
  );
}
