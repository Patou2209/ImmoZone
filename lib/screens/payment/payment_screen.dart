import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/theme/app_theme.dart';
import '../../models/payment_model.dart';
import '../../services/data_service.dart';
import 'transaction_success_screen.dart';
import 'transaction_failed_screen.dart';

// ── URL Cloud Functions ImmoZone ───────────────────────────────────────────────
const _kInitiateUrl =
    'https://us-central1-immozone-d9a68.cloudfunctions.net/initiateOrangePayment';
const _kStatusUrl =
    'https://us-central1-immozone-d9a68.cloudfunctions.net/checkOrangePaymentStatus';

// ── Timeout USSD : 3 minutes max avant d'afficher l'échec ─────────────────────
const _kUssdTimeoutSeconds = 180;
// ── Polling toutes les 10 secondes ────────────────────────────────────────────
const _kPollingIntervalSeconds = 10;

class PaymentScreen extends StatefulWidget {
  final String productType;
  final double amount;
  final String productLabel;
  final String? propertyId;
  final int creditsQty;

  const PaymentScreen({
    super.key,
    required this.productType,
    required this.amount,
    required this.productLabel,
    this.propertyId,
    this.creditsQty = 0,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _ds = DataService();
  final _phoneCtrl = TextEditingController();
  final _refCtrl = TextEditingController();

  String _selectedOperator = 'orange_money';
  bool _isLoading = false;
  bool _useManualValidation = false;

  // ── État Orange Money spécifique ───────────────────────────────────────────
  bool _orangeWaitingUssd = false;  // spinner USSD en cours
  int _pollingSecondsElapsed = 0;
  Timer? _pollingTimer;
  String? _currentPaymentId;
  String? _omTransactionId;

  final _operators = [
    {
      'id': 'orange_money',
      'name': 'Orange Money',
      'color': const Color(0xFFFF7900),
      'bg': const Color(0xFFFFF3E0),
      'icon': null, // utilise le widget logo custom
    },
    {
      'id': 'mpesa',
      'name': 'M-Pesa',
      'color': const Color(0xFF00B140),
      'bg': const Color(0xFFE8F5E9),
      'icon': Icons.phone_android,
    },
    {
      'id': 'airtel_money',
      'name': 'Airtel Money',
      'color': const Color(0xFFE40000),
      'bg': const Color(0xFFFFEBEE),
      'icon': Icons.payment,
    },
  ];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _refCtrl.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ORANGE MONEY — Initier le paiement via Cloud Function
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _initiateOrangePayment() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _showMsg('Veuillez entrer votre numéro Orange Money', isError: true);
      return;
    }
    if (phone.length < 9) {
      _showMsg('Numéro de téléphone invalide', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    // Créer le document payment dans Firestore
    final paymentId = 'pay_${DateTime.now().millisecondsSinceEpoch}';
    final orderId = 'ord_${DateTime.now().millisecondsSinceEpoch}';

    final payment = PaymentModel(
      id: paymentId,
      userId: _ds.currentUserId,
      orderId: orderId,
      operator: 'orange_money',
      phoneNumber: phone,
      amount: widget.amount,
      productType: widget.productType,
      status: 'pending',
      creditsQty: widget.creditsQty,
      propertyId: widget.propertyId,
      createdAt: DateTime.now(),
    );
    await _ds.addPayment(payment);

    // Appeler la Cloud Function
    try {
      final response = await http.post(
        Uri.parse(_kInitiateUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'paymentId': paymentId,
          'phoneNumber': phone,
          'amount': widget.amount,
          'currency': 'USD',
          'creditsQty': widget.creditsQty,
          'userId': _ds.currentUserId,
          'productType': widget.productType,
          'orderId': orderId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] == true || data['transactionStatus'] == 'PENDING') {
        // ── SUCCÈS INITIATION → passer en mode attente USSD ───────────────
        _currentPaymentId = paymentId;
        _omTransactionId = data['omTransactionId'] as String?;
        setState(() {
          _isLoading = false;
          _orangeWaitingUssd = true;
          _pollingSecondsElapsed = 0;
        });
        _startPolling();
      } else {
        // ── ÉCHEC immédiat ─────────────────────────────────────────────────
        setState(() => _isLoading = false);
        if (!mounted) return;
        _navigateToFailed(
          paymentId: paymentId,
          reason: data['error'] ?? 'Le paiement Orange Money n\'a pas pu être initié.',
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      _showMsg('Erreur réseau: $e', isError: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // POLLING — Vérifier le statut toutes les 10s (fallback si webhook absent)
  // ─────────────────────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: _kPollingIntervalSeconds),
      (_) => _checkStatus(),
    );
  }

  Future<void> _checkStatus() async {
    if (!mounted || _currentPaymentId == null) return;

    setState(() => _pollingSecondsElapsed += _kPollingIntervalSeconds);

    // Timeout : 3 minutes sans réponse → échec
    if (_pollingSecondsElapsed >= _kUssdTimeoutSeconds) {
      _pollingTimer?.cancel();
      if (!mounted) return;
      setState(() => _orangeWaitingUssd = false);
      _navigateToFailed(
        paymentId: _currentPaymentId!,
        reason:
            'Le délai de confirmation USSD a expiré (${_kUssdTimeoutSeconds ~/ 60} minutes).\nVeuillez vérifier votre téléphone ou réessayer.',
      );
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$_kStatusUrl?paymentId=${_currentPaymentId!}'),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['transactionStatus'] as String? ?? 'PENDING';

      if (status == 'SUCCESSFUL') {
        _pollingTimer?.cancel();
        setState(() => _orangeWaitingUssd = false);
        _navigateToSuccess();
      } else if (status == 'FAILED' || status == 'CANCELLED') {
        _pollingTimer?.cancel();
        setState(() => _orangeWaitingUssd = false);
        _navigateToFailed(
          paymentId: _currentPaymentId!,
          reason:
              'Orange Money a refusé la transaction.\nVérifiez votre solde ou votre confirmation USSD.',
        );
      }
      // PENDING → continuer à attendre
    } catch (_) {
      // Erreur réseau temporaire → continuer le polling
    }
  }

  void _cancelUssdWait() {
    _pollingTimer?.cancel();
    setState(() {
      _orangeWaitingUssd = false;
      _currentPaymentId = null;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PAIEMENT MANUEL (M-Pesa, Airtel — inchangé)
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _initiateManualPayment() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      _showMsg('Veuillez entrer votre numéro de téléphone', isError: true);
      return;
    }
    setState(() => _isLoading = true);

    final paymentId = 'pay_${DateTime.now().millisecondsSinceEpoch}';
    final orderId = 'ord_${DateTime.now().millisecondsSinceEpoch}';

    await _ds.addPayment(PaymentModel(
      id: paymentId,
      userId: _ds.currentUserId,
      orderId: orderId,
      operator: _useManualValidation ? 'manual' : _selectedOperator,
      phoneNumber: _phoneCtrl.text.trim(),
      amount: widget.amount,
      productType: widget.productType,
      status: _useManualValidation ? 'awaiting_manual' : 'pending',
      transactionReference:
          _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      propertyId: widget.propertyId,
      creditsQty: widget.creditsQty,
      createdAt: DateTime.now(),
    ));

    setState(() => _isLoading = false);
    if (!mounted) return;
    _showManualConfirmation();
  }

  void _navigateToSuccess() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TransactionSuccessScreen(
          creditsQty: widget.creditsQty,
          amount: widget.amount,
          productLabel: widget.productLabel,
          omTransactionId: _omTransactionId,
          paymentId: _currentPaymentId ?? '',
        ),
      ),
    );
  }

  void _navigateToFailed({required String paymentId, required String reason}) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TransactionFailedScreen(
          amount: widget.amount,
          productLabel: widget.productLabel,
          reason: reason,
          paymentId: paymentId,
          onRetry: () {
            // Permettre de réessayer depuis l'écran d'échec
          },
        ),
      ),
    );
  }

  void _showManualConfirmation() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _useManualValidation ? Icons.hourglass_top : Icons.check_circle,
              color: _useManualValidation ? Colors.orange : AppTheme.successColor,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _useManualValidation
                  ? 'Demande soumise — en attente de validation'
                  : 'Commande créée — en attente de confirmation',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _useManualValidation
                  ? 'Un administrateur ImmoZone vérifiera votre référence et créditera votre compte.'
                  : 'Votre commande a été créée. Après confirmation du paiement, vos crédits seront attribués.',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // ferme bottom sheet
                  Navigator.pop(context); // retour écran précédent
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Compris',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
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

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text('Paiement',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE4E8F0)),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _orangeWaitingUssd
            ? _buildUssdWaitingScreen()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildPaymentForm(),
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ÉCRAN D'ATTENTE USSD (Orange Money uniquement)
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildUssdWaitingScreen() {
    final remaining = _kUssdTimeoutSeconds - _pollingSecondsElapsed;
    final progress = _pollingSecondsElapsed / _kUssdTimeoutSeconds;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(flex: 1),

          // ── Logo Orange Money ──────────────────────────────────────────────
          _buildOrangeMoneyLogo(size: 56),
          const SizedBox(height: 28),

          // ── Spinner animé ──────────────────────────────────────────────────
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: 1 - progress,
                  strokeWidth: 5,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  color: const Color(0xFFFF7900),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_iphone_rounded,
                      size: 30, color: Color(0xFFFF7900)),
                  Text(
                    '${remaining}s',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Message ────────────────────────────────────────────────────────
          const Text(
            'En attente de votre confirmation',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // ── Étapes USSD ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFFF7900).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.phone_in_talk_rounded,
                      color: Color(0xFFFF7900), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Vérifiez votre téléphone',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE65C00),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _ussdStep('1',
                    'Un message USSD s\'affiche sur votre téléphone Orange'),
                _ussdStep('2', 'Saisissez votre code PIN Orange Money'),
                _ussdStep('3', 'Confirmez le paiement de ${widget.amount.toStringAsFixed(2)} USD'),
                _ussdStep('4',
                    'Revenez ici — la confirmation est automatique'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Info montant ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Montant à confirmer',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: AppTheme.textSecondary)),
                Text(
                  '${widget.amount.toStringAsFixed(2)} USD',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFF7900),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(flex: 2),

          // ── Annuler ────────────────────────────────────────────────────────
          TextButton.icon(
            onPressed: _cancelUssdWait,
            icon: const Icon(Icons.close_rounded,
                size: 16, color: AppTheme.textSecondary),
            label: const Text('Annuler et revenir',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: AppTheme.textSecondary)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // FORMULAIRE DE PAIEMENT
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildPaymentForm() {
    final isOrange = _selectedOperator == 'orange_money' && !_useManualValidation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Récapitulatif commande ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.primaryDark]),
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
                child: const Icon(Icons.shopping_cart,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.productLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    Text('${widget.amount.toStringAsFixed(2)} USD',
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    if (widget.creditsQty > 0)
                      Text('${widget.creditsQty} crédit${widget.creditsQty > 1 ? 's' : ''}',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontFamily: 'Poppins',
                              fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Mode paiement ──────────────────────────────────────────────────
        Row(
          children: [
            _modeChip('Mobile Money', !_useManualValidation,
                () => setState(() => _useManualValidation = false)),
            const SizedBox(width: 10),
            _modeChip('Déjà payé (réf.)', _useManualValidation,
                () => setState(() => _useManualValidation = true)),
          ],
        ),
        const SizedBox(height: 20),

        // ── Sélection opérateur ────────────────────────────────────────────
        if (!_useManualValidation) ...[
          const Text('Choisissez votre opérateur',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          Row(
            children: _operators.map((op) {
              final id = op['id'] as String;
              final selected = _selectedOperator == id;
              final color = op['color'] as Color;
              final bg = op['bg'] as Color;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedOperator = id),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? bg : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? color : AppTheme.dividerColor,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Orange Money → logo custom, autres → icône
                        if (id == 'orange_money')
                          _buildOrangeMoneyLogo(size: 22)
                        else
                          Icon(op['icon'] as IconData,
                              color: color, size: 24),
                        const SizedBox(height: 4),
                        Text(op['name'] as String,
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: selected ? color : AppTheme.textSecondary),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // ── Numéro de téléphone ────────────────────────────────────────────
        _label(isOrange
            ? 'Numéro Orange Money *'
            : 'Numéro de téléphone Mobile Money *'),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 15),
          decoration: _inputDeco(
            hint: isOrange ? '+243 8XX XXX XXX' : '+243 8XX XXX XXX',
            icon: Icons.phone,
            borderColor: isOrange ? const Color(0xFFFF7900) : null,
          ),
        ),
        const SizedBox(height: 16),

        // ── Section spécifique selon opérateur ────────────────────────────
        if (_useManualValidation) ...[
          _label('Référence de transaction *'),
          const SizedBox(height: 8),
          TextField(
            controller: _refCtrl,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 15),
            decoration: _inputDeco(
                hint: 'ex: MP240421001',
                icon: Icons.confirmation_number),
          ),
          const SizedBox(height: 12),
          _infoBox(
            icon: Icons.info_outline,
            iconColor: Colors.amber,
            bgColor: const Color(0xFFFFF8E1),
            borderColor: Colors.amber.shade300,
            text:
                'Soumettez votre référence de transaction. Un administrateur ImmoZone validera votre paiement dans les plus brefs délais.',
          ),
        ] else if (isOrange) ...[
          // ── Info Orange Money ──────────────────────────────────────────
          _buildOrangeInfoBox(),
        ] else ...[
          // ── Info M-Pesa / Airtel (manuel) ─────────────────────────────
          _infoBox(
            icon: Icons.info_outline,
            iconColor: Colors.green.shade700,
            bgColor: const Color(0xFFE8F5E9),
            borderColor: Colors.green.shade300,
            text:
                'Envoyez ${widget.amount.toStringAsFixed(2)} USD au numéro ImmoZone, puis soumettez votre référence de transaction pour validation manuelle.',
          ),
        ],

        const SizedBox(height: 28),

        // ── Bouton principal ───────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () {
                    if (!_useManualValidation &&
                        _selectedOperator == 'orange_money') {
                      _initiateOrangePayment();
                    } else {
                      _initiateManualPayment();
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: isOrange
                  ? const Color(0xFFFF7900)
                  : AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isOrange) ...[
                        _buildOrangeMoneyLogo(
                            size: 18, whiteArrow: true),
                        const SizedBox(width: 10),
                      ] else
                        const Icon(Icons.send, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        isOrange
                            ? 'Payer avec Orange Money'
                            : _useManualValidation
                                ? 'Soumettre pour validation'
                                : 'Initier le paiement',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // WIDGETS HELPERS
  // ─────────────────────────────────────────────────────────────────────────────

  /// Logo Orange Money (2 flèches croisées)
  Widget _buildOrangeMoneyLogo({double size = 32, bool whiteArrow = false}) {
    final orangeColor = const Color(0xFFFF7900);
    final blackColor = whiteArrow ? Colors.white : Colors.black87;
    return SizedBox(
      width: size * 1.4,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Icon(Icons.north_east_rounded,
                color: blackColor, size: size * 0.65),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.south_west_rounded,
                color: orangeColor, size: size * 0.65),
          ),
        ],
      ),
    );
  }

  Widget _buildOrangeInfoBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFFF7900).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _buildOrangeMoneyLogo(size: 16),
            const SizedBox(width: 8),
            const Text('Comment ça fonctionne :',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE65C00))),
          ]),
          const SizedBox(height: 10),
          _ussdStep('1', 'Entrez votre numéro Orange Money ci-dessus'),
          _ussdStep('2', 'Cliquez "Payer avec Orange Money"'),
          _ussdStep('3',
              'Un message USSD s\'affiche sur votre téléphone — confirmez'),
          _ussdStep('4',
              'Vos crédits sont attribués automatiquement après confirmation'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF7900).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 14, color: Color(0xFFE65C00)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Délai de confirmation : jusqu\'à 3 minutes',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Color(0xFFE65C00),
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ussdStep(String num, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  color: Color(0xFFFF7900), shape: BoxShape.circle),
              child: Center(
                child: Text(num,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'Poppins',
                      color: Color(0xFF6D4C41),
                      height: 1.4)),
            ),
          ],
        ),
      );

  Widget _infoBox({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required String text,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Poppins',
                      color: iconColor,
                      height: 1.5)),
            ),
          ],
        ),
      );

  Widget _modeChip(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? AppTheme.primaryColor : AppTheme.dividerColor),
          ),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppTheme.textSecondary)),
        ),
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary));

  InputDecoration _inputDeco(
          {required String hint,
          required IconData icon,
          Color? borderColor}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: AppTheme.textHint, fontFamily: 'Poppins', fontSize: 13),
        prefixIcon: Icon(icon,
            color: borderColor ?? AppTheme.accentColor, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: borderColor ?? AppTheme.dividerColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: borderColor ?? AppTheme.accentColor, width: 2)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: borderColor?.withValues(alpha: 0.5) ??
                    AppTheme.dividerColor)),
      );
}
