import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/property_image.dart';
import '../../../models/property_model.dart';
import '../../../models/payment_model.dart';
import '../../../services/data_service.dart';
import '../properties/admin_property_detail_screen.dart';
import '../payments/admin_payments_screen.dart';
import '../../public/home/public_home_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _ds = DataService();
  Map<String, dynamic> _stats = {};
  List<PropertyModel> _pendingProps = [];
  List<PaymentModel> _pendingPayments = [];
  bool _isLoading = true;
  bool _isFreeTrial = false;
  bool _isTogglingTrial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final provider = context.read<PropertyProvider>();
    final stats = await provider.getStats();
    final pending = await provider.getPendingProperties();
    final pendingPays = await _ds.getPendingManualPayments();
    setState(() {
      _stats = stats;
      _pendingProps = pending;
      _pendingPayments = pendingPays;
      _isFreeTrial = _ds.isFreeTrial;
      _isLoading = false;
    });
  }

  Future<void> _validatePaymentFromDashboard(PaymentModel payment, bool approve) async {
    final auth = context.read<AuthProvider>();
    final wasApprove = approve; // capture avant tout rebuild
    final userName = payment.userName.isNotEmpty ? payment.userName : payment.userId;
    try {
      await _ds.validatePaymentManually(
        payment.id,
        adminId: auth.currentUser?.id ?? _ds.currentUserId,
        adminName: auth.currentUser?.name ?? _ds.currentUserName,
        approve: wasApprove,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        wasApprove
            ? '✅ Paiement validé — crédits accordés à $userName'
            : '❌ Paiement rejeté',
        style: const TextStyle(fontFamily: 'Poppins'),
      ),
      backgroundColor: wasApprove ? AppTheme.successColor : AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _toggleFreeTrial() async {
    setState(() => _isTogglingTrial = true);
    final newVal = !_isFreeTrial;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(newVal ? Icons.free_breakfast : Icons.lock_clock,
              color: newVal ? AppTheme.successColor : AppTheme.warningColor),
          const SizedBox(width: 10),
          Text(newVal ? 'Activer Free Trial' : 'Désactiver Free Trial',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          newVal
              ? 'En activant le Free Trial, TOUS les utilisateurs pourront publier un nombre illimité d\'annonces GRATUITEMENT sans aucune restriction.\n\nÀ désactiver manuellement quand vous souhaitez revenir aux règles normales.'
              : 'En désactivant le Free Trial, les règles normales reprennent : 1 annonce gratuite/mois puis 2 USD par publication.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
            onPressed: () async {
              await _ds.toggleFreeTrial(newVal);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: newVal ? AppTheme.successColor : AppTheme.warningColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(newVal ? 'Activer' : 'Désactiver',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    setState(() {
      _isFreeTrial = _ds.isFreeTrial;
      _isTogglingTrial = false;
    });
  }

  Future<void> _clearSoldProperties() async {
    final soldCount = (_stats['soldProperties'] ?? 0) as int;
    if (soldCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucune annonce marquée vendue à effacer',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.textSecondary,
      ));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.cleaning_services, color: AppTheme.errorColor),
          SizedBox(width: 10),
          Text('Effacer les annonces vendues', style: TextStyle(
              fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Cette action va supprimer DÉFINITIVEMENT les $soldCount annonce(s) marquées "Vendu" ou "En location".\nCette opération est irréversible.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_sweep, size: 16),
            label: const Text('Effacer tout', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final deleted = await _ds.clearSoldAndRentedProperties();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🧹 $deleted annonce(s) supprimée(s) définitivement',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.accentColor,
              child: CustomScrollView(
                slivers: [
                  // ── Header ────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 50, 20, 28),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                          colors: [AppTheme.primaryDark, AppTheme.primaryLight],
                        ),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Tableau de Bord',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                                      color: Colors.white, fontFamily: 'Poppins')),
                              Text('Bienvenue, ${auth.currentUser?.name.split(' ').first ?? 'Admin'}',
                                  style: const TextStyle(fontSize: 13, color: Colors.white70, fontFamily: 'Poppins')),
                            ]),
                            // Badge rôle admin
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.accentColor.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.5)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.admin_panel_settings_rounded,
                                      color: AppTheme.accentColor, size: 16),
                                  SizedBox(width: 6),
                                  Text('Admin', style: TextStyle(
                                      fontFamily: 'Poppins', fontSize: 11,
                                      color: AppTheme.accentColor, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          _quickStat('${_stats['totalProperties'] ?? 0}', 'Annonces', Icons.home_work),
                          const SizedBox(width: 10),
                          _quickStat('${_stats['pendingProperties'] ?? 0}', 'En attente',
                              Icons.pending_outlined, isAlert: (_stats['pendingProperties'] ?? 0) > 0),
                          const SizedBox(width: 10),
                          _quickStat('${_stats['totalUsers'] ?? 0}', 'Utilisateurs', Icons.people),
                        ]),
                      ]),
                    ),
                  ),

                  // ── Notification paiements en attente ──────────────────
                  if (_pendingPayments.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // En-tête notification
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                                child: Row(children: [
                                  Stack(
                                    children: [
                                      const Icon(Icons.notifications_active_rounded,
                                          color: Colors.orange, size: 26),
                                      Positioned(
                                        right: 0, top: 0,
                                        child: Container(
                                          width: 10, height: 10,
                                          decoration: const BoxDecoration(
                                              color: AppTheme.errorColor, shape: BoxShape.circle),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(
                                        '${_pendingPayments.length} paiement${_pendingPayments.length > 1 ? 's' : ''} en attente de validation',
                                        style: const TextStyle(fontFamily: 'Poppins',
                                            fontSize: 13, fontWeight: FontWeight.w800,
                                            color: Colors.orange),
                                      ),
                                      const Text(
                                        'Des utilisateurs ont soumis des demandes de recharge de crédits.',
                                        style: TextStyle(fontFamily: 'Poppins',
                                            fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                    ]),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const AdminPaymentsScreen()),
                                    ).then((_) => _load()),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('Voir tout',
                                          style: TextStyle(fontFamily: 'Poppins',
                                              fontSize: 11, fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ),
                                  ),
                                ]),
                              ),
                              // Cartes des paiements en attente
                              ...(_pendingPayments.take(3).map((pay) => _pendingPaymentCard(pay))),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // ── Boutons d'action admin ─────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Actions Administrateur',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary, fontFamily: 'Poppins')),
                        const SizedBox(height: 14),

                        // ── FREE TRIAL TOGGLE ──────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _isFreeTrial ? AppTheme.successColor : AppTheme.dividerColor,
                              width: _isFreeTrial ? 2 : 1,
                            ),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                          ),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (_isFreeTrial ? AppTheme.successColor : AppTheme.textHint)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.free_breakfast,
                                  color: _isFreeTrial ? AppTheme.successColor : AppTheme.textHint, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  const Text('Mode Free Trial',
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                          fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                                  const SizedBox(width: 8),
                                  if (_isFreeTrial)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.successColor, borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('ACTIF',
                                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                              fontWeight: FontWeight.w800, color: Colors.white)),
                                    ),
                                ]),
                                Text(
                                  _isFreeTrial
                                      ? 'Publication illimitée et gratuite pour tous'
                                      : 'Règles normales : 1 gratuit/mois puis 2 USD',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                      color: _isFreeTrial ? AppTheme.successColor : AppTheme.textSecondary),
                                ),
                              ]),
                            ),
                            Switch(
                              value: _isFreeTrial,
                              onChanged: _isTogglingTrial ? null : (_) => _toggleFreeTrial(),
                              activeThumbColor: AppTheme.successColor,
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),

                        // ── EFFACER ANNONCES VENDUES ───────────────────────
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                          ),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.errorColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.cleaning_services, color: AppTheme.errorColor, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Effacer annonces vendues',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                      fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                              Text(
                                '${_stats['soldProperties'] ?? 0} annonce(s) marquée(s) vendues/louées',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                    color: AppTheme.textSecondary),
                              ),
                            ])),
                            ElevatedButton(
                              onPressed: _clearSoldProperties,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Effacer tout',
                                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),

                        // ── DÉCONNEXION ────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                          ),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.textSecondary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.logout, color: AppTheme.textSecondary, size: 24),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Déconnexion',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                      fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                              Text('Quitter le panneau d\'administration',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                      color: AppTheme.textSecondary)),
                            ])),
                            ElevatedButton(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Row(children: [
                                      Icon(Icons.logout, color: AppTheme.textSecondary),
                                      SizedBox(width: 10),
                                      Text('Déconnexion', style: TextStyle(
                                          fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700)),
                                    ]),
                                    content: const Text(
                                      'Voulez-vous vraiment vous déconnecter du panneau d\'administration ?',
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                          color: AppTheme.textSecondary, height: 1.5),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins'))),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text('Déconnecter', style: TextStyle(
                                            fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true && mounted) {
                                  await context.read<AuthProvider>().logout();
                                  if (mounted) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(builder: (_) => const PublicHomeScreen()),
                                      (route) => false,
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.textSecondary.withValues(alpha: 0.15),
                                foregroundColor: AppTheme.textPrimary,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Quitter', style: TextStyle(
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),

                  // ── Statistiques ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Statistiques Générales',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary, fontFamily: 'Poppins')),
                        const SizedBox(height: 14),
                        GridView.count(
                          crossAxisCount: 2, shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.4,
                          children: [
                            _statCard('Annonces actives', '${_stats['activeProperties'] ?? 0}',
                                Icons.check_circle_outline, AppTheme.successColor),
                            _statCard('Boosts actifs', '${_stats['boostedProperties'] ?? 0}',
                                Icons.rocket_launch, Colors.purple),
                            _statCard('Annonceurs', '${_stats['annonceurs'] ?? 0}',
                                Icons.home_outlined, AppTheme.primaryColor),
                            _statCard('Demandeurs', '${_stats['demandeurs'] ?? 0}',
                                Icons.search, AppTheme.accentColor),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Revenu + alertes
                        Row(children: [
                          Expanded(child: _alertCard(
                            '${_stats['pendingPayments'] ?? 0}', 'Paiements à valider',
                            Icons.payment, Colors.orange,
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _alertCard(
                            '${_stats['pendingReports'] ?? 0}', 'Signalements',
                            Icons.flag, Colors.red,
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _alertCard(
                            '\$${(_stats['totalRevenue'] ?? 0.0).toStringAsFixed(0)}',
                            'Revenu (USD)',
                            Icons.monetization_on, AppTheme.successColor,
                          )),
                        ]),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: _transactionCard('Vente',
                              '${_stats['vente'] ?? 0}', AppTheme.primaryColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _transactionCard('Location',
                              '${_stats['location'] ?? 0}', AppTheme.successColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _transactionCard('Messages',
                              '${_stats['totalMessages'] ?? 0}', AppTheme.warningColor)),
                        ]),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),

                  // ── Annonces en attente ───────────────────────────────────
                  if (_pendingProps.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: AppTheme.warningColor, borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.pending_outlined, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Text('En attente (${_pendingProps.length})',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary, fontFamily: 'Poppins')),
                        ]),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final prop = _pendingProps[i];
                          final provider = context.read<PropertyProvider>();
                          final messenger = ScaffoldMessenger.of(ctx);
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: _PendingPropertyCard(
                              property: prop,
                              onApprove: () async {
                                await provider.updateStatus(prop.id, 'Actif');
                                _load();
                                messenger.showSnackBar(const SnackBar(
                                  content: Text('✅ Annonce approuvée !',
                                      style: TextStyle(fontFamily: 'Poppins')),
                                  backgroundColor: AppTheme.successColor,
                                ));
                              },
                              onReject: () async {
                                await provider.updateStatus(prop.id, 'Rejeté');
                                _load();
                                messenger.showSnackBar(const SnackBar(
                                  content: Text('Annonce rejetée.',
                                      style: TextStyle(fontFamily: 'Poppins')),
                                  backgroundColor: AppTheme.errorColor,
                                ));
                              },
                              onTap: () => Navigator.push(ctx, MaterialPageRoute(
                                  builder: (_) => AdminPropertyDetailScreen(property: prop))),
                            ),
                          );
                        },
                        childCount: _pendingProps.length,
                      ),
                    ),
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
    );
  }

  Widget _quickStat(String value, String label, IconData icon, {bool isAlert = false}) =>
    Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isAlert ? Colors.amber.withValues(alpha: 0.3) : AppTheme.accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: isAlert ? Border.all(color: Colors.amber, width: 1.5) : null,
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: Colors.white, fontFamily: 'Poppins')),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white70, fontFamily: 'Poppins')),
        ]),
      ]),
    ));

  Widget _statCard(String label, String value, IconData icon, Color color) =>
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
              color: color, fontFamily: 'Poppins')),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontFamily: 'Poppins')),
        ]),
      ]),
    );

  Widget _alertCard(String value, String label, IconData icon, Color color) =>
    Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color, fontFamily: 'Poppins')),
        Text(label, style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary, fontFamily: 'Poppins'),
            textAlign: TextAlign.center),
      ]),
    );

  Widget _transactionCard(String label, String value, Color color) =>
    Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color, fontFamily: 'Poppins')),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontFamily: 'Poppins')),
      ]),
    );

  // ── Carte paiement en attente dans la notification dashboard ───────────────
  Widget _pendingPaymentCard(PaymentModel pay) {
    final timeAgo = _timeAgo(pay.createdAt);
    final displayName = pay.userName.isNotEmpty ? pay.userName : 'Utilisateur (${pay.userId.length > 8 ? pay.userId.substring(0, 8) : pay.userId}...)';
    // Priorité 1 : creditsQty stocké dans le paiement (valeur exacte du pack)
    // Priorité 2 : fallback 1 USD = 10 crédits (anciens paiements sans creditsQty)
    final credits = pay.creditsQty > 0 ? pay.creditsQty : (pay.amount * 10).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── En-tête : nom utilisateur + horodatage ─────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Row(children: [
            // Avatar avec initiale
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800, fontSize: 14, color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(displayName,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('Demande de recharge • $timeAgo',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      color: AppTheme.textSecondary)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('En attente',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                      fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
        ),

        // ── Détails paiement ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(children: [
            // Montant + crédits
            Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(children: [
                    const Text('Montant', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 9, color: AppTheme.textSecondary)),
                    Text('\$${pay.amount.toStringAsFixed(2)} USD',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                            fontWeight: FontWeight.w800, color: AppTheme.accentColor)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(children: [
                    const Text('Crédits à accorder', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 9, color: AppTheme.textSecondary)),
                    Text('$credits crédits',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                            fontWeight: FontWeight.w800, color: AppTheme.successColor)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // Opérateur + référence
            Row(children: [
              Icon(Icons.payment_rounded, size: 13, color: AppTheme.textHint),
              const SizedBox(width: 5),
              Text(pay.operatorLabel,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      color: AppTheme.textSecondary)),
              if (pay.transactionReference != null) ...[
                const SizedBox(width: 10),
                Icon(Icons.confirmation_number_outlined, size: 13, color: AppTheme.textHint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text('Réf: ${pay.transactionReference}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ]),
          ]),
        ),

        // ── Boutons Rejeter / Valider ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _validatePaymentFromDashboard(pay, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.errorColor, width: 1.5),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.close_rounded, size: 14, color: AppTheme.errorColor),
                    SizedBox(width: 5),
                    Text('Rejeter', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.errorColor)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => _validatePaymentFromDashboard(pay, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text('Valider & Accorder $credits crédits',
                        style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    return 'Il y a ${diff.inDays}j';
  }
}

class _PendingPropertyCard extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onTap;
  const _PendingPropertyCard({required this.property, required this.onApprove,
      required this.onReject, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.4)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            child: PropertyImage(
                src: property.mainImage, width: 90, height: 90,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                placeholder: Container(width: 90, height: 90,
                    color: AppTheme.primaryLight.withValues(alpha: 0.2),
                    child: const Icon(Icons.home, color: AppTheme.accentColor))),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(property.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins', color: AppTheme.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${property.commune}, ${property.city}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontFamily: 'Poppins')),
                Text('Par: ${property.ownerName}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontFamily: 'Poppins')),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: onApprove,
                    child: Container(padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.successColor, borderRadius: BorderRadius.circular(8)),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.check, color: Colors.white, size: 12),
                          SizedBox(width: 3),
                          Text('Approuver', style: TextStyle(color: Colors.white, fontSize: 10,
                              fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                        ])),
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: GestureDetector(
                    onTap: onReject,
                    child: Container(padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.errorColor, borderRadius: BorderRadius.circular(8)),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.close, color: Colors.white, size: 12),
                          SizedBox(width: 3),
                          Text('Rejeter', style: TextStyle(color: Colors.white, fontSize: 10,
                              fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                        ])),
                  )),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
