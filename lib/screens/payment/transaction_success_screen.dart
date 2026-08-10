import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Écran affiché après confirmation SUCCESSFUL d'un paiement Orange Money
class TransactionSuccessScreen extends StatefulWidget {
  final int creditsQty;
  final double amount;
  final String productLabel;
  final String? omTransactionId;
  final String paymentId;

  const TransactionSuccessScreen({
    super.key,
    required this.creditsQty,
    required this.amount,
    required this.productLabel,
    this.omTransactionId,
    required this.paymentId,
  });

  @override
  State<TransactionSuccessScreen> createState() => _TransactionSuccessScreenState();
}

class _TransactionSuccessScreenState extends State<TransactionSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
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
      canPop: false, // forcer le bouton "Retour à l'accueil"
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

                  // ── Icône succès animée ────────────────────────────────────
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.successColor.withValues(alpha: 0.1),
                        border: Border.all(color: AppTheme.successColor, width: 3),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.successColor,
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
                    'Paiement confirmé !',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Votre paiement Orange Money a été validé avec succès.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // ── Carte crédits attribués ────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A6B3C), Color(0xFF28A965)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.successColor.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.stars_rounded,
                              color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Crédits ajoutés',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Colors.white70,
                                  )),
                              Text(
                                '+${widget.creditsQty} crédit${widget.creditsQty > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

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
                        _row('Montant payé', '${widget.amount.toStringAsFixed(2)} USD'),
                        _divider(),
                        _row('Opérateur', 'Orange Money'),
                        _divider(),
                        _row('Référence', widget.omTransactionId ?? widget.paymentId,
                            valueStyle: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            )),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Bouton retour ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Remonter jusqu'à la racine (ferme tout le flow paiement)
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.home_rounded, size: 20),
                      label: const Text('Retour à l\'accueil',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          )),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flèches Orange Money (logo simplifié)
          _orangeArrowIcon(),
          const SizedBox(width: 8),
          const Text(
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

  Widget _orangeArrowIcon() {
    return SizedBox(
      width: 28,
      height: 20,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Icon(Icons.north_east_rounded,
                color: Colors.black87, size: 14),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.south_west_rounded,
                color: const Color(0xFFFF7900), size: 14),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {TextStyle? valueStyle}) {
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
          Flexible(
            child: Text(value,
                style: valueStyle ??
                    const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 12, color: Color(0xFFE4E8F0));
}
