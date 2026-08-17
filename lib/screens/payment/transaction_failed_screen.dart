import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/orange_money_logo.dart';

/// Écran affiché après un paiement Orange Money FAILED ou timeout
class TransactionFailedScreen extends StatefulWidget {
  final double amount;
  final String productLabel;
  final String reason;
  final String paymentId;
  final VoidCallback? onRetry;

  const TransactionFailedScreen({
    super.key,
    required this.amount,
    required this.productLabel,
    required this.reason,
    required this.paymentId,
    this.onRetry,
  });

  @override
  State<TransactionFailedScreen> createState() => _TransactionFailedScreenState();
}

class _TransactionFailedScreenState extends State<TransactionFailedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 1),

                  // ── Icône échec animée ─────────────────────────────────────
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withValues(alpha: 0.08),
                        border: Border.all(color: Colors.red.shade400, width: 3),
                      ),
                      child: Icon(
                        Icons.cancel_rounded,
                        color: Colors.red.shade500,
                        size: 72,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Logo Orange Money ──────────────────────────────────────
                  _orangeMoneyBadge(),
                  const SizedBox(height: 24),

                  // ── Titre ──────────────────────────────────────────────────
                  const Text(
                    'Paiement non abouti',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),

                  // ── Raison de l'échec ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: Colors.red.shade400, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.reason,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: Colors.red.shade700,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Récapitulatif ──────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE4E8F0)),
                    ),
                    child: Column(
                      children: [
                        _row('Produit', widget.productLabel),
                        _divider(),
                        _row('Montant', '${widget.amount.toStringAsFixed(2)} USD'),
                        _divider(),
                        _row('Opérateur', 'Orange Money'),
                        _divider(),
                        _row('Statut', 'Non confirmé',
                            valueColor: Colors.red.shade600),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Conseils ───────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.lightbulb_outline_rounded,
                              color: Colors.amber.shade700, size: 16),
                          const SizedBox(width: 8),
                          Text('Que faire ?',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber.shade800,
                              )),
                        ]),
                        const SizedBox(height: 8),
                        _tip('Vérifiez que votre solde Orange Money est suffisant'),
                        _tip('Assurez-vous d\'avoir confirmé le paiement USSD'),
                        _tip('Vérifiez votre connexion réseau Orange'),
                        _tip('Réessayez ou contactez le support ImmoZone'),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Boutons ────────────────────────────────────────────────
                  if (widget.onRetry != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop(); // retour au PaymentScreen
                          widget.onRetry!();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('Réessayer',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            )),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7900),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.home_rounded, size: 18),
                      label: const Text('Retour à l\'accueil',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          )),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _orangeMoneyBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF7900).withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo officiel Orange Money
          OrangeMoneyLogo(size: 22),
          SizedBox(width: 8),
          Text(
            'Orange Money',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF7900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: AppTheme.textSecondary,
              )),
          Text(value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppTheme.textPrimary,
              )),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 12, color: Color(0xFFE4E8F0));

  Widget _tip(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.arrow_right_rounded,
                color: Colors.amber.shade700, size: 16),
            const SizedBox(width: 4),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.amber.shade900,
                    height: 1.4,
                  )),
            ),
          ],
        ),
      );
}
