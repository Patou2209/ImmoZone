import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/immozone_app_bar.dart';
import '../../../core/widgets/recharge_form_widget.dart';
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
    // Utilise le même flux éprouvé que post_property_screen (CAS 4b)
    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => RechargeDialog(
        user: user,
        ds: _ds,
        preselectedPack: pack,
      ),
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

// _PaymentDialog supprimé — remplacé par RechargeDialog (recharge_form_widget.dart)
// Le flux éprouvé de post_property_screen est maintenant partagé via ce widget.
