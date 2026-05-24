import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/data_service.dart';
import '../../auth/login_screen.dart';
import '../../auth/register_screen.dart';

class PublicPacksScreen extends StatefulWidget {
  const PublicPacksScreen({super.key});
  @override
  State<PublicPacksScreen> createState() => _PublicPacksScreenState();
}

class _PublicPacksScreenState extends State<PublicPacksScreen> {
  final _ds = DataService();
  List<Map<String, dynamic>> _packs = [];
  bool _isFreeTrial = false;
  bool _loading = true;
  String _officialMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Refresh packs from Firestore to ensure latest admin changes are visible
    await _ds.refreshPacksFromFirestore();
    if (!mounted) return;
    final settings = _ds.systemSettings;
    setState(() {
      _isFreeTrial = settings['free_trial_enabled'] == true;
      _packs = List<Map<String, dynamic>>.from(_ds.subscriptionPacks)
          .where((p) => p['active'] == true)
          .toList();
      _officialMessage = _ds.officialMessage;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final subs = _packs.where((p) => p['type'] == 'subscription').toList();
    final pubs = _packs.where((p) => p['type'] != 'subscription').toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Offres & Abonnements',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── MODE GRATUIT BANNER ─────────────────────────────────────
                if (_isFreeTrial) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: AppTheme.successColor.withValues(alpha: 0.3),
                            blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.celebration_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('MODE GRATUIT ACTIF',
                              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                                  fontSize: 15, color: Colors.white)),
                          Text('Publication illimitee sans frais',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                  color: Colors.white70)),
                        ]),
                      ]),
                      const SizedBox(height: 14),
                      const Text(
                        'La plateforme est actuellement en mode gratuit. Vous pouvez publier vos annonces sans aucun frais.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            color: Colors.white, height: 1.5),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.successColor,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Créer un compte gratuitement',
                              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  // ── HERO SECTION ──────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryDark, AppTheme.primaryColor, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.4)),
                      boxShadow: [
                        BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.4),
                            blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Logo sur fond blanc pour lisibilité sur fond bleu
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.asset(
                          'assets/images/immozone_logo.png',
                          height: 36,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => RichText(
                            text: const TextSpan(
                              style: TextStyle(fontFamily: 'Poppins',
                                  fontSize: 18, fontWeight: FontWeight.w800),
                              children: [
                                TextSpan(text: 'Immo',
                                    style: TextStyle(color: AppTheme.primaryColor)),
                                TextSpan(text: 'Zone',
                                    style: TextStyle(color: AppTheme.accentColor)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Plateforme immobiliere N°1 en RDC',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                              color: Colors.white70)),
                      const SizedBox(height: 16),
                      const Text(
                        'Publiez vos biens immobiliers et touchez des milliers d\'acheteurs et locataires potentiels.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            color: Colors.white, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const LoginScreen())),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.accentColor,
                              side: const BorderSide(color: AppTheme.accentColor),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Se connecter',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const RegisterScreen())),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentColor,
                              foregroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('S\'inscrire',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── AVANTAGES ───────────────────────────────────────────────
                _sectionHeader('Pourquoi publier sur ImmoZone ?'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
                  ),
                  child: Column(children: [
                    _advantageRow(Icons.people_alt_rounded, 'Audience qualifiee',
                        'Des milliers de visiteurs actifs chaque jour'),
                    _divider(),
                    _advantageRow(Icons.visibility_rounded, 'Visibilite maximale',
                        'Vos annonces sont mises en avant sur la plateforme'),
                    _divider(),
                    _advantageRow(Icons.shield_rounded, 'Plateforme securisee',
                        'Toutes les annonces sont verifiees par notre equipe'),
                    _divider(),
                    _advantageRow(Icons.support_agent_rounded, 'Support dedie',
                        'Notre equipe vous accompagne a chaque etape'),
                  ]),
                ),
                const SizedBox(height: 24),

                // ── ABONNEMENTS ─────────────────────────────────────────────
                if (subs.isNotEmpty) ...[
                  _sectionHeader('Abonnements Mensuels & Annuels'),
                  const SizedBox(height: 4),
                  const Text('Publications illimitees — ideal pour les professionnels',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 14),
                  ...subs.map((s) => _subscriptionCard(s, highlight: true)),
                  const SizedBox(height: 24),
                ],

                // ── PACKS PUBLICATIONS ──────────────────────────────────────
                if (pubs.isNotEmpty) ...[
                  _sectionHeader('Packs de Publications'),
                  const SizedBox(height: 4),
                  const Text('Achetez des publications a l\'unite ou en lot',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.05,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: pubs.length,
                    itemBuilder: (_, i) => _pubPackCard(pubs[i]),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── MESSAGE OFFICIEL ────────────────────────────────────────
                if (_officialMessage.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.4)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.verified_rounded, color: AppTheme.accentColor, size: 16),
                        SizedBox(width: 8),
                        Text('Message Officiel ImmoZone',
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                fontSize: 12, color: AppTheme.accentColor)),
                      ]),
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 10),
                      Text(_officialMessage,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                              color: Colors.white70, height: 1.6)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── CTA FINAL ───────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: AppTheme.accentColor.withValues(alpha: 0.4),
                          blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(children: [
                    const Icon(Icons.home_work_rounded, color: AppTheme.primaryColor, size: 36),
                    const SizedBox(height: 10),
                    const Text('Prêt à publier votre bien ?',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                            fontSize: 16, color: AppTheme.primaryColor),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    const Text('Creez votre compte en moins de 2 minutes',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen())),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Créer mon compte maintenant',
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 32),
              ]),
            ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title,
        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
            fontSize: 16, color: AppTheme.textPrimary));
  }

  Widget _divider() => const Divider(height: 1, color: AppTheme.dividerColor,
      indent: 52);

  Widget _advantageRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.accentColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
              fontSize: 13, color: AppTheme.textPrimary)),
          Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: AppTheme.textSecondary, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _subscriptionCard(Map<String, dynamic> pack, {bool highlight = false}) {
    final isMonthly = (pack['qty'] ?? 0) == -1;
    final price = (pack['price'] as num).toDouble();
    final currency = pack['currency'] ?? 'USD';
    final isAnnual = (pack['qty'] ?? 0) == -2;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: highlight
            ? const LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.primaryLight],
                begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
        color: highlight ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? AppTheme.accentColor.withValues(alpha: 0.5) : AppTheme.dividerColor,
          width: highlight ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlight
                ? AppTheme.primaryColor.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isMonthly ? Icons.calendar_month_rounded : Icons.calendar_today_rounded,
              color: AppTheme.accentColor, size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pack['name'] ?? '',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: highlight ? Colors.white : AppTheme.textPrimary)),
            Text(
              isMonthly ? 'Illimite par mois' : isAnnual ? 'Illimite par an' : 'Publications illimitees',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: highlight ? Colors.white60 : AppTheme.textSecondary),
            ),
          ])),
          if (isAnnual)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('MEILLEURE OFFRE',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                      fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
            ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$price',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                  fontSize: 32, color: AppTheme.accentColor)),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(currency,
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 14, color: AppTheme.accentColor)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 5, left: 4),
            child: Text(isMonthly ? '/ mois' : '/ an',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: highlight ? Colors.white60 : AppTheme.textSecondary)),
          ),
        ]),
        if (isAnnual && isMonthly == false) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Economisez jusqu\'a 20% vs mensuel',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: AppTheme.successColor)),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RegisterScreen())),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              foregroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Commencer maintenant',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  Widget _pubPackCard(Map<String, dynamic> pack) {
    final qty = pack['qty'] as int? ?? 1;
    final price = (pack['price'] as num).toDouble();
    final currency = pack['currency'] ?? 'USD';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.inventory_2_outlined, color: AppTheme.accentColor, size: 20),
        ),
        const SizedBox(height: 10),
        Text(pack['name'] ?? '',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 12, color: AppTheme.textPrimary),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const Spacer(),
        Text('$price $currency',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                fontSize: 16, color: AppTheme.accentColor)),
        Text('$qty publication${qty > 1 ? 's' : ''}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RegisterScreen())),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 11),
            ),
            child: const Text('Choisir'),
          ),
        ),
      ]),
    );
  }
}
