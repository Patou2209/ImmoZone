import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../../../providers/auth_provider.dart' as immo_auth;
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/property_image.dart';
import '../../../models/property_model.dart';
import '../../../models/payment_model.dart';
import '../../../models/user_model.dart';
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
  // ── KPI Performance du Marché & Monétisation ──────────────────────
  List<PaymentModel> _confirmedPayments = [];
  String _kpiPeriod = 'mois'; // jour | semaine | mois | annee
  // ── KPI 2 Attraction & Engagement ────────────────────────────────────
  List<UserModel> _allUsers = [];
  List<PropertyModel> _allProperties = [];
  // ── KPI 3 Matchmaking ────────────────────────────────────────────────
  List<Map<String, dynamic>> _contactLogs = [];

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
    // Charger les paiements confirmés pour KPI
    final allPayments = await _ds.getPayments();
    // Charger users + properties pour KPI 2
    final allUsers = await _ds.getUsers();
    final allProperties = await _ds.getProperties();
    // Charger logs de contact pour KPI 3
    final contactLogs = await _ds.getContactLogs();
    setState(() {
      _stats = stats;
      _pendingProps = pending;
      _pendingPayments = pendingPays;
        _confirmedPayments = allPayments.where((p) => p.isConfirmed).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _allUsers = allUsers;
        _allProperties = allProperties;
        _contactLogs = contactLogs;
        _isFreeTrial = _ds.isFreeTrial;
      _isLoading = false;
    });
  }

  Future<void> _validatePaymentFromDashboard(PaymentModel payment, bool approve) async {
    final auth = context.read<immo_auth.AuthProvider>();
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

  // ── Réinitialiser le chiffre d'affaire ────────────────────────────────────
  Future<void> _resetRevenue() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.restart_alt_rounded, color: Color(0xFF1A237E), size: 26),
          SizedBox(width: 10),
          Expanded(child: Text('Réinitialiser le CA',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w700))),
        ]),
        content: const Text(
          'Cette action remet le chiffre d\'affaire affiché à \$0.00 en posant une date de référence maintenant.\n\n'
          'Les anciens paiements ne seront PAS supprimés — ils sont archivés et ne comptent plus dans les statistiques.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Réinitialiser',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    // Sauvegarder la date de reset dans les settings Firestore
    await _ds.setRevenueResetDate(DateTime.now());
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('✅ Chiffre d\'affaire réinitialisé à \$0.00',
          style: TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
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

  // ── Supprimer TOUTES les annonces (avec confirmation mot de passe) ─────────
  Future<void> _deleteAllProperties() async {
    final auth = context.read<immo_auth.AuthProvider>();
    // Utiliser le virtual email dérivé du téléphone (pas l'email de récupération Firestore)
    final adminPhone = auth.currentUser?.phone ?? '';
    final adminEmail = adminPhone.isNotEmpty
        ? immo_auth.AuthProvider.phoneToVirtualEmail(adminPhone)
        : (fb_auth.FirebaseAuth.instance.currentUser?.email ?? '');
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    String? errorMsg;

    // Étape 1 — Confirmation initiale
    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: Colors.red, size: 28),
          SizedBox(width: 10),
          Expanded(child: Text('Supprimer TOUT', style: TextStyle(
              fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700,
              color: Colors.red))),
        ]),
        content: const Text(
          'Cette action va supprimer TOUTES les annonces. Cette operation est IRREVERSIBLE.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Continuer', style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    // Étape 2 — Confirmation mot de passe admin
    final step2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.lock_outline_rounded, color: AppTheme.primaryColor, size: 24),
            SizedBox(width: 10),
            Text('Confirmer votre mot de passe', style: TextStyle(
                fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Entrez votre mot de passe admin pour confirmer la suppression de TOUTES les annonces.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.textSecondary, height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordCtrl,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                labelStyle: const TextStyle(fontFamily: 'Poppins'),
                prefixIcon: const Icon(Icons.lock_rounded, color: AppTheme.primaryColor),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                      color: AppTheme.textSecondary),
                  onPressed: () => setStateDialog(() => obscure = !obscure),
                ),
                errorText: errorMsg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins'))),
            ElevatedButton(
              onPressed: () async {
                final pwd = passwordCtrl.text.trim();
                if (pwd.isEmpty) {
                  setStateDialog(() => errorMsg = 'Mot de passe requis');
                  return;
                }
                // Ré-authentifier via Firebase
                try {
                  final credential = fb_auth.EmailAuthProvider.credential(
                    email: adminEmail, password: pwd);
                  await fb_auth.FirebaseAuth.instance.currentUser
                      ?.reauthenticateWithCredential(credential);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setStateDialog(() => errorMsg = 'Mot de passe incorrect');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Confirmer', style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    passwordCtrl.dispose();
    if (step2 != true || !mounted) return;

    // Exécution de la suppression
    final provider = context.read<PropertyProvider>();
    final all = provider.properties;
    int deleted = 0;
    for (final p in all) {
      await _ds.deleteProperty(p.id);
      deleted++;
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🗑️ $deleted annonce(s) supprimée(s) définitivement',
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<immo_auth.AuthProvider>();
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
                            // Badge rôle admin — orange pour contraste sur fond bleu
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFA726).withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFFA726).withValues(alpha: 0.7)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.admin_panel_settings_rounded,
                                      color: Color(0xFFFFA726), size: 15),
                                  SizedBox(width: 5),
                                  Text('Admin', style: TextStyle(
                                      fontFamily: 'Poppins', fontSize: 11,
                                      color: Color(0xFFFFA726), fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),

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

                        // ── RÉINITIALISER CHIFFRE D'AFFAIRE ───────────────
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFF1A237E).withValues(alpha: 0.2)),
                            boxShadow: [BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                          ),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.restart_alt_rounded,
                                  color: Color(0xFF1A237E), size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Réinitialiser le CA',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary)),
                              Text(
                                'Revenu actuel : \$${(_stats['totalRevenue'] ?? 0.0).toStringAsFixed(2)}',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                    color: AppTheme.textSecondary),
                              ),
                            ])),
                            ElevatedButton(
                              onPressed: _resetRevenue,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A237E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Remettre à 0',
                                  style: TextStyle(fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700, fontSize: 12)),
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
                                  await context.read<immo_auth.AuthProvider>().logout();
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
                            _statCard('Visiteurs', '${_stats['demandeurs'] ?? 0}',
                                Icons.visibility_outlined, AppTheme.accentColor),
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

                  // ── 1. Performance du Marché & Monétisation ──────────
                  SliverToBoxAdapter(child: _buildKpiMarche()),

                  // ── 2. Attraction & Engagement de l'Audience ─────────
                  SliverToBoxAdapter(child: _buildKpiAudience()),

                  // ── 3. Efficacité du Matchmaking ─────────────────────────
                  SliverToBoxAdapter(child: _buildKpiMatchmaking()),

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

                  // ── Zone dangereuse ────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          const Text('Zone Dangereuse',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                  color: Colors.red, fontFamily: 'Poppins')),
                        ]),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Supprimer toutes les annonces',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                    fontSize: 14, color: Colors.red)),
                            const SizedBox(height: 4),
                            const Text('Supprime DÉFINITIVEMENT toutes les annonces de la plateforme. Nécessite la confirmation de votre mot de passe.',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                    color: AppTheme.textSecondary, height: 1.4)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _deleteAllProperties,
                                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                                label: const Text('Supprimer toutes les annonces',
                                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),

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

  // ── Getters KPI Performance du Marché & Monétisation ─────────────────
  List<PaymentModel> get _kpiFiltered {
    final now = DateTime.now();
    DateTime from;
    switch (_kpiPeriod) {
      case 'jour': from = DateTime(now.year, now.month, now.day); break;
      case 'semaine': from = now.subtract(const Duration(days: 7)); break;
      case 'annee': from = DateTime(now.year, 1, 1); break;
      default: from = DateTime(now.year, now.month, 1); // mois
    }
    // Respecter aussi la date de réinitialisation du CA
    final resetDateStr = _stats['revenueResetDate'] as String?;
    final resetDate = resetDateStr != null ? DateTime.tryParse(resetDateStr) : null;
    if (resetDate != null && resetDate.isAfter(from)) {
      from = resetDate;
    }
    return _confirmedPayments.where((p) => p.createdAt.isAfter(from)).toList();
  }

  double get _kpiTotalRevenue => _kpiFiltered.fold(0.0, (s, p) => s + p.amount);

  double get _kpiRechargeRevenue => _kpiFiltered
      .where((p) => p.productType.contains('souscription') ||
          p.productType.contains('pack') || p.productType == 'publication_unitaire')
      .fold(0.0, (s, p) => s + p.amount);

  double get _kpiBoostRevenue => _kpiFiltered
      .where((p) => p.productType.contains('boost'))
      .fold(0.0, (s, p) => s + p.amount);

  double get _kpiAdsRevenue => _kpiFiltered
      .where((p) => p.productType == 'ads')
      .fold(0.0, (s, p) => s + p.amount);

  int get _kpiUniqueAnnonceurs {
    final ids = _kpiFiltered.map((p) => p.userId).toSet();
    return ids.isEmpty ? 1 : ids.length;
  }

  double get _kpiArpa =>
      _kpiUniqueAnnonceurs > 0 ? _kpiTotalRevenue / _kpiUniqueAnnonceurs : 0.0;

  // Données périodiques (barres)
  Map<String, double> _kpiBuildChartData() {
    final result = <String, double>{};
    final now = DateTime.now();
    if (_kpiPeriod == 'annee') {
      for (int m = 1; m <= 12; m++) {
        const months = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];
        final sum = _kpiFiltered
            .where((p) => p.createdAt.month == m && p.createdAt.year == now.year)
            .fold(0.0, (s, p) => s + p.amount);
        result[months[m - 1]] = sum;
      }
    } else {
      final days = _kpiPeriod == 'jour' ? 1 : _kpiPeriod == 'semaine' ? 7 : 30;
      for (int i = days - 1; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final label = '${day.day}/${day.month}';
        final sum = _kpiFiltered
            .where((p) => p.createdAt.year == day.year &&
                p.createdAt.month == day.month && p.createdAt.day == day.day)
            .fold(0.0, (s, p) => s + p.amount);
        result[label] = sum;
      }
    }
    return result;
  }

  // Données cumulées (courbe)
  List<MapEntry<String, double>> _kpiBuildCumulativeData() {
    final entries = _kpiBuildChartData().entries.toList();
    double cumul = 0.0;
    return entries.map((e) { cumul += e.value; return MapEntry(e.key, cumul); }).toList();
  }

  // ── Construire le bloc KPI complet ────────────────────────────────────
  Widget _buildKpiMarche() {
    final chartData = _kpiBuildChartData();
    final cumulData = _kpiBuildCumulativeData();
    final entries = chartData.entries.toList();
    final maxBar  = entries.isEmpty ? 1.0 : entries.fold(0.0, (m, e) => e.value > m ? e.value : m);
    final maxCumul = cumulData.isEmpty ? 1.0 : cumulData.fold(0.0, (m, e) => e.value > m ? e.value : m);
    // Segments donut
    final segments = [
      _KpiDonutSeg('Abonnements', _kpiRechargeRevenue, const Color(0xFF1B5E20)),
      _KpiDonutSeg('Boosting',    _kpiBoostRevenue,   const Color(0xFFE65100)),
      _KpiDonutSeg('Publicité',   _kpiAdsRevenue,     const Color(0xFF4A148C)),
    ];
    final periods = [
      {'v': 'jour', 'l': 'Jour'}, {'v': 'semaine', 'l': 'Sem.'},
      {'v': 'mois', 'l': 'Mois'}, {'v': 'annee', 'l': 'Année'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Titre de section ─────────────────────────────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('1',
              style: TextStyle(color: Colors.white, fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Performance du Marché & Monétisation',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary, fontFamily: 'Poppins')),
          ),
        ]),
        const SizedBox(height: 12),

        // ── Filtre période ────────────────────────────────────────────────
        Row(
          children: periods.map((p) => Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _kpiPeriod = p['v']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _kpiPeriod == p['v']
                      ? const Color(0xFF1A237E)
                      : AppTheme.dividerColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(p['l']!,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _kpiPeriod == p['v'] ? Colors.white : AppTheme.textSecondary,
                  ))),
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 12),

        // ── Cartes KPI Commerciaux ────────────────────────────────────────
        // Ligne 1 : Recette + ARPA
        Row(children: [
          Expanded(child: _kpiCard(
            label: 'Recette',
            value: '\$${_kpiTotalRevenue.toStringAsFixed(2)}',
            icon: Icons.monetization_on_outlined,
            color: const Color(0xFF1A237E),
            sub: '${_kpiFiltered.length} transactions',
          )),
          const SizedBox(width: 10),
          Expanded(child: _kpiCard(
            label: 'ARPA',
            value: '\$${_kpiArpa.toStringAsFixed(2)}',
            icon: Icons.person_outline_rounded,
            color: const Color(0xFF006064),
            sub: 'Revenu / annonceur',
          )),
        ]),
        const SizedBox(height: 10),
        // Ligne 2 : Abonnements + Boosting + Publicité
        Row(children: [
          Expanded(child: _kpiCardSmall(
            'Abonnements', '\$${_kpiRechargeRevenue.toStringAsFixed(0)}',
            const Color(0xFF1B5E20))),
          const SizedBox(width: 8),
          Expanded(child: _kpiCardSmall(
            'Boosting', '\$${_kpiBoostRevenue.toStringAsFixed(0)}',
            const Color(0xFFE65100))),
          const SizedBox(width: 8),
          Expanded(child: _kpiCardSmall(
            'Publicité', '\$${_kpiAdsRevenue.toStringAsFixed(0)}',
            const Color(0xFF4A148C))),
        ]),
        const SizedBox(height: 16),

        // ── Courbe : Recette périodique + cumulée ─────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Sous-titre + badge ARPA
            Row(children: [
              const Icon(Icons.show_chart_rounded, color: Color(0xFF1A237E), size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text('Courbe — Recette cumulée & périodique',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: AppTheme.textPrimary))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF006064).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('ARA \$${_kpiArpa.toStringAsFixed(1)}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 9,
                      fontWeight: FontWeight.w700, color: Color(0xFF006064))),
              ),
            ]),
            const SizedBox(height: 10),
            // Légende
            Row(children: [
              Container(width: 12, height: 3,
                decoration: BoxDecoration(color: const Color(0xFFFFA726),
                    borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 5),
              const Text('Périodique',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: AppTheme.textHint)),
              const SizedBox(width: 14),
              Container(width: 12, height: 3,
                decoration: BoxDecoration(color: const Color(0xFF006064),
                    borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 5),
              const Text('Cumulée',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: AppTheme.textHint)),
            ]),
            const SizedBox(height: 8),
            // Graphique superposé : barres (périodique) + courbe (cumulée)
            SizedBox(
              height: 150,
              child: CustomPaint(
                painter: _KpiDualChartPainter(
                  barEntries: entries,
                  lineEntries: cumulData,
                  maxBar: maxBar,
                  maxLine: maxCumul,
                ),
                child: Container(),
              ),
            ),
            const SizedBox(height: 6),
            // Labels X
            _kpiXLabels(entries),
          ]),
        ),
        const SizedBox(height: 12),

        // ── Anneau (donut) : Répartition du revenu ───────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.donut_large_rounded, color: Color(0xFF4A148C), size: 16),
              const SizedBox(width: 6),
              const Text('Anneau — Répartition du revenu',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: AppTheme.textPrimary)),
            ]),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Donut
              SizedBox(
                width: 130, height: 130,
                child: CustomPaint(
                  painter: _KpiDonutPainter(segments: segments, total: _kpiTotalRevenue),
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Total', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 9, color: AppTheme.textHint)),
                    Text('\$${_kpiTotalRevenue.toStringAsFixed(0)}',
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800, fontSize: 15,
                          color: AppTheme.textPrimary)),
                  ])),
                ),
              ),
              const SizedBox(width: 14),
              // Légende
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: segments.map((s) {
                  final pct = _kpiTotalRevenue > 0
                      ? (s.amount / _kpiTotalRevenue * 100) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(children: [
                      Container(width: 11, height: 11,
                        decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                      const SizedBox(width: 7),
                      Expanded(child: Text(s.label,
                        style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, color: AppTheme.textPrimary))),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${pct.toStringAsFixed(0)}%',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 11, fontWeight: FontWeight.w700, color: s.color)),
                        Text('\$${s.amount.toStringAsFixed(0)}',
                          style: const TextStyle(fontFamily: 'Poppins',
                              fontSize: 9, color: AppTheme.textSecondary)),
                      ]),
                    ]),
                  );
                }).toList(),
              )),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  // Carte KPI grande
  Widget _kpiCard({required String label, required String value,
      required IconData icon, required Color color, String? sub}) =>
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 6)],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontFamily: 'Poppins',
              fontSize: 10, color: AppTheme.textSecondary)),
          Text(value, style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          if (sub != null) Text(sub, style: const TextStyle(fontFamily: 'Poppins',
              fontSize: 9, color: AppTheme.textHint)),
        ])),
      ]),
    );

  // Carte KPI petite (3 colonnes)
  Widget _kpiCardSmall(String label, String value, Color color) =>
    Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w800, fontSize: 14, color: color)),
        Text(label, style: const TextStyle(fontFamily: 'Poppins',
            fontSize: 9, color: AppTheme.textSecondary), textAlign: TextAlign.center),
      ]),
    );


  // ── Getters KPI 2 : Audience ──────────────────────────────────────────────

  // Visiteurs = utilisateurs avec role 'demandeur', filtrés sur la période KPI
  List<UserModel> get _kpi2Visitors {
    final now = DateTime.now();
    DateTime from;
    switch (_kpiPeriod) {
      case 'jour':    from = DateTime(now.year, now.month, now.day); break;
      case 'semaine': from = now.subtract(const Duration(days: 7)); break;
      case 'annee':   from = DateTime(now.year, 1, 1); break;
      default:        from = DateTime(now.year, now.month, 1);
    }
    return _allUsers.where((u) =>
        u.role == 'demandeur' && u.createdAt.isAfter(from)).toList();
  }

  // Tous les demandeurs (toutes périodes, pour le gauge)
  List<UserModel> get _kpi2AllVisitors =>
      _allUsers.where((u) => u.role == 'demandeur').toList();

  // Annonceurs actifs (ont au moins 1 annonce active)
  int get _kpi2ActiveAnnonceurs {
    final ids = _allProperties
        .where((p) => p.status == 'Actif' && !p.isExpired)
        .map((p) => p.ownerId)
        .toSet();
    return ids.length;
  }

  // Taux de renouvellement = annonceurs qui ont republié (propriété créée dans
  // les 15 jours après expiration d'une annonce précédente du même owner).
  // Approx : ratio annonceurs ayant ≥2 annonces / total annonceurs.
  double get _kpi2RenewalRate {
    if (_allProperties.isEmpty) return 0.0;
    final byOwner = <String, int>{};
    for (final p in _allProperties) {
      byOwner[p.ownerId] = (byOwner[p.ownerId] ?? 0) + 1;
    }
    final owners = byOwner.length;
    if (owners == 0) return 0.0;
    final renewed = byOwner.values.where((c) => c >= 2).length;
    return renewed / owners;
  }

  // Classement villes par nombre d'utilisateurs (demandeurs)
  List<MapEntry<String, int>> get _kpi2CityRanking {
    final counts = <String, int>{};
    for (final u in _kpi2AllVisitors) {
      final city = (u.city ?? '').trim();
      if (city.isEmpty) continue;
      counts[city] = (counts[city] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  // Classement communes par nombre d'utilisateurs (demandeurs)
  List<MapEntry<String, int>> get _kpi2CommuneRanking {
    final counts = <String, int>{};
    for (final u in _kpi2AllVisitors) {
      final commune = (u.commune ?? '').trim();
      if (commune.isEmpty) continue;
      counts[commune] = (counts[commune] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  // Histogramme visiteurs par période (même logique que KPI1 mais avec users)
  Map<String, int> _kpi2BuildVisitorChart() {
    final result = <String, int>{};
    final now = DateTime.now();
    if (_kpiPeriod == 'annee') {
      const months = ['Jan','Fév','Mar','Avr','Mai','Jun',
                       'Jul','Aoû','Sep','Oct','Nov','Déc'];
      for (int m = 1; m <= 12; m++) {
        result[months[m - 1]] = _kpi2Visitors
            .where((u) => u.createdAt.month == m && u.createdAt.year == now.year)
            .length;
      }
    } else {
      final days = _kpiPeriod == 'jour' ? 1 :
                   _kpiPeriod == 'semaine' ? 7 : 30;
      for (int i = days - 1; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final label = '${day.day}/${day.month}';
        result[label] = _kpi2Visitors.where((u) =>
          u.createdAt.year == day.year &&
          u.createdAt.month == day.month &&
          u.createdAt.day == day.day).length;
      }
    }
    return result;
  }

  // ── Construire le bloc KPI 2 ───────────────────────────────────────────────
  Widget _buildKpiAudience() {
    final visitorChart = _kpi2BuildVisitorChart();
    final chartEntries  = visitorChart.entries.toList();
    final maxVisitors   = chartEntries.isEmpty ? 1.0
        : chartEntries.fold(0.0, (m, e) => e.value > m ? e.value.toDouble() : m);
    final cityRanking    = _kpi2CityRanking;
    final communeRanking = _kpi2CommuneRanking;
    final maxCity    = cityRanking.isEmpty    ? 1 : cityRanking.first.value;
    final maxCommune = communeRanking.isEmpty ? 1 : communeRanking.first.value;
    final totalVisitors  = _kpi2AllVisitors.length;
    final activeAnnonc   = _kpi2ActiveAnnonceurs;
    final renewalRate    = _kpi2RenewalRate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Titre ─────────────────────────────────────────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00695C),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('2',
              style: TextStyle(color: Colors.white, fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text("Attraction & Engagement de l'Audience",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary, fontFamily: 'Poppins')),
          ),
        ]),
        const SizedBox(height: 12),

        // ── Ligne 1 : Visiteurs uniques + Annonceurs actifs ───────────────
        Row(children: [
          Expanded(child: _kpiCard(
            label: 'Visiteurs uniques',
            value: '$totalVisitors',
            icon: Icons.people_outline_rounded,
            color: const Color(0xFF00695C),
            sub: '${_kpi2Visitors.length} ce mois',
          )),
          const SizedBox(width: 10),
          Expanded(child: _kpiCard(
            label: 'Annonceurs actifs',
            value: '$activeAnnonc',
            icon: Icons.store_outlined,
            color: const Color(0xFF1565C0),
            sub: 'annonces non expirées',
          )),
        ]),
        const SizedBox(height: 10),

        // ── Jauge taux de renouvellement ─────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.speed_rounded, color: Color(0xFF6A1B9A), size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text('Taux de renouvellement',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: AppTheme.textPrimary))),
              Text('${(renewalRate * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800, fontSize: 14,
                    color: Color(0xFF6A1B9A))),
            ]),
            const SizedBox(height: 10),
            // Barre de jauge
            Stack(children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              FractionallySizedBox(
                widthFactor: renewalRate.clamp(0.0, 1.0),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFFCE93D8)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Annonceurs ayant au moins 2 annonces / total annonceurs',
              style: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 9, color: AppTheme.textHint),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // ── Histogramme visiteurs uniques par période ─────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.bar_chart_rounded,
                  color: Color(0xFF00695C), size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text('Visiteurs uniques — Histogramme',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: AppTheme.textPrimary))),
            ]),
            const SizedBox(height: 10),
            chartEntries.isEmpty
                ? const Center(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Aucune donnée',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          color: AppTheme.textHint)),
                  ))
                : Column(children: [
                    SizedBox(
                      height: 120,
                      child: CustomPaint(
                        painter: _Kpi2BarPainter(
                          entries: chartEntries
                              .map((e) => MapEntry(e.key, e.value.toDouble()))
                              .toList(),
                          maxVal: maxVisitors,
                          barColor: const Color(0xFF00695C),
                        ),
                        child: Container(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _kpiXLabels(chartEntries
                        .map((e) => MapEntry(e.key, e.value.toDouble()))
                        .toList()),
                  ]),
          ]),
        ),
        const SizedBox(height: 12),

        // ── Classements villes + communes ─────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Villes
          Expanded(child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.location_city_rounded,
                    color: Color(0xFF1565C0), size: 14),
                const SizedBox(width: 5),
                const Expanded(child: Text('Villes',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 11,
                      color: AppTheme.textPrimary))),
              ]),
              const SizedBox(height: 8),
              if (cityRanking.isEmpty)
                const Text('Aucune donnée',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      color: AppTheme.textHint))
              else
                ...cityRanking.asMap().entries.map((e) {
                  final rank = e.key + 1;
                  final entry = e.value;
                  final pct = maxCity > 0 ? entry.value / maxCity : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Container(
                          width: 16, height: 16,
                          decoration: BoxDecoration(
                            color: rank == 1
                                ? const Color(0xFF1565C0)
                                : const Color(0xFF1565C0).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(child: Text('$rank',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: rank == 1 ? Colors.white
                                  : const Color(0xFF1565C0)))),
                        ),
                        const SizedBox(width: 5),
                        Expanded(child: Text(entry.key,
                          style: const TextStyle(fontFamily: 'Poppins',
                              fontSize: 10, color: AppTheme.textPrimary),
                          overflow: TextOverflow.ellipsis)),
                        Text('${entry.value}',
                          style: const TextStyle(fontFamily: 'Poppins',
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: Color(0xFF1565C0))),
                      ]),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 4,
                          backgroundColor: const Color(0xFFE3F2FD),
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF1565C0)),
                        ),
                      ),
                    ]),
                  );
                }),
            ]),
          )),
          const SizedBox(width: 10),
          // Communes
          Expanded(child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.map_outlined,
                    color: Color(0xFF00838F), size: 14),
                const SizedBox(width: 5),
                const Expanded(child: Text('Communes',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 11,
                      color: AppTheme.textPrimary))),
              ]),
              const SizedBox(height: 8),
              if (communeRanking.isEmpty)
                const Text('Aucune donnée',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      color: AppTheme.textHint))
              else
                ...communeRanking.asMap().entries.map((e) {
                  final rank = e.key + 1;
                  final entry = e.value;
                  final pct = maxCommune > 0 ? entry.value / maxCommune : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Container(
                          width: 16, height: 16,
                          decoration: BoxDecoration(
                            color: rank == 1
                                ? const Color(0xFF00838F)
                                : const Color(0xFF00838F).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(child: Text('$rank',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: rank == 1 ? Colors.white
                                  : const Color(0xFF00838F)))),
                        ),
                        const SizedBox(width: 5),
                        Expanded(child: Text(entry.key,
                          style: const TextStyle(fontFamily: 'Poppins',
                              fontSize: 10, color: AppTheme.textPrimary),
                          overflow: TextOverflow.ellipsis)),
                        Text('${entry.value}',
                          style: const TextStyle(fontFamily: 'Poppins',
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: Color(0xFF00838F))),
                      ]),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 4,
                          backgroundColor: const Color(0xFFE0F7FA),
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF00838F)),
                        ),
                      ),
                    ]),
                  );
                }),
            ]),
          )),
        ]),
        const SizedBox(height: 12),

        // ── Classements : ville + type & commune + type (sans résultats) ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppTheme.dividerColor.withValues(alpha: 0.4)),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.search_off_rounded,
                  color: Color(0xFFE65100), size: 15),
              const SizedBox(width: 6),
              const Expanded(child: Text(
                'Recherches sans résultats (villes & communes / type)',
                style: TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 11,
                    color: AppTheme.textPrimary))),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded,
                    color: Color(0xFFE65100), size: 14),
                SizedBox(width: 8),
                Expanded(child: Text(
                  "Ce KPI nécessite l'enregistrement des requêtes "
                  "de recherche dans Firestore (collection search_logs). "
                  "Activez le suivi des recherches pour alimenter ce graphique.",
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                      color: Color(0xFFE65100)),
                )),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }


  // ── Getters KPI 3 : Matchmaking ───────────────────────────────────────────

  /// Filtre les contact_logs sur la période courante (_kpiPeriod).
  List<Map<String, dynamic>> get _kpi3Filtered {
    final now = DateTime.now();
    DateTime from;
    switch (_kpiPeriod) {
      case 'jour':    from = DateTime(now.year, now.month, now.day); break;
      case 'semaine': from = now.subtract(const Duration(days: 7)); break;
      case 'annee':   from = DateTime(now.year, 1, 1); break;
      default:        from = DateTime(now.year, now.month, 1);
    }
    return _contactLogs.where((log) {
      final raw = log['created_at_iso'] as String?;
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw);
      return dt != null && dt.isAfter(from);
    }).toList();
  }

  int get _kpi3WaClicks =>
      _kpi3Filtered.where((l) => l['type'] == 'whatsapp').length;

  int get _kpi3CallClicks =>
      _kpi3Filtered.where((l) => l['type'] == 'call').length;

  int get _kpi3TotalLeads => _kpi3WaClicks + _kpi3CallClicks;

  /// Taux de conversion : leads / annonces actives (≤ 1.0 pour affichage jauge)
  double get _kpi3ConversionRate {
    final active = _allProperties
        .where((p) => p.status == 'Actif' && !p.isExpired)
        .length;
    if (active == 0) return 0.0;
    final ratio = _kpi3TotalLeads / active;
    return ratio.clamp(0.0, double.infinity); // peut dépasser 1
  }

  /// Histogramme mensuel : retourne 12 mois avec wa+call counts
  List<_Kpi3MonthBar> _kpi3BuildMonthlyData() {
    const months = ['Jan','Fév','Mar','Avr','Mai','Jun',
                     'Jul','Aoû','Sep','Oct','Nov','Déc'];
    final now = DateTime.now();
    return List.generate(12, (i) {
      final m = i + 1;
      final wa   = _contactLogs.where((l) {
        final raw = l['created_at_iso'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw);
        return dt != null && dt.year == now.year && dt.month == m
            && l['type'] == 'whatsapp';
      }).length;
      final call = _contactLogs.where((l) {
        final raw = l['created_at_iso'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw);
        return dt != null && dt.year == now.year && dt.month == m
            && l['type'] == 'call';
      }).length;
      return _Kpi3MonthBar(label: months[i], wa: wa, call: call);
    });
  }

  // ── Bloc KPI 3 ────────────────────────────────────────────────────────────
  Widget _buildKpiMatchmaking() {
    final monthData = _kpi3BuildMonthlyData();
    final maxBar = monthData.isEmpty ? 1
        : monthData.fold(0, (m, e) => (e.wa + e.call) > m ? (e.wa + e.call) : m);
    final convRate = _kpi3ConversionRate;
    final convDisplay = convRate > 1.0
        ? '${convRate.toStringAsFixed(1)}× '
        : '${(convRate * 100).toStringAsFixed(1)}%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Titre ────────────────────────────────────────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF880E4F),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('3',
              style: TextStyle(color: Colors.white, fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Efficacité du "Matchmaking"',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary, fontFamily: 'Poppins')),
          ),
        ]),
        const SizedBox(height: 12),

        // ── KPI cards : Volume Leads + Taux Conversion ───────────────────
        Row(children: [
          Expanded(child: _kpiCard(
            label: 'Volume de Leads',
            value: '$_kpi3TotalLeads',
            icon: Icons.connect_without_contact_rounded,
            color: const Color(0xFF880E4F),
            sub: '${_kpi3WaClicks} WA · ${_kpi3CallClicks} Appels',
          )),
          const SizedBox(width: 10),
          Expanded(child: _kpiCard(
            label: 'Taux Lead→Contact',
            value: convDisplay,
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF00695C),
            sub: 'clics / annonces actives',
          )),
        ]),
        const SizedBox(height: 10),

        // ── Jauge taux de conversion ─────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.ads_click_rounded,
                  color: Color(0xFF880E4F), size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text('Jauge — Engagement (clics / annonces actives)',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: AppTheme.textPrimary))),
              Text(convDisplay,
                style: const TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w800, fontSize: 14,
                    color: Color(0xFF880E4F))),
            ]),
            const SizedBox(height: 10),
            Stack(children: [
              Container(height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE4EC),
                  borderRadius: BorderRadius.circular(6)),
              ),
              FractionallySizedBox(
                widthFactor: (convRate / (convRate > 2.0 ? convRate : 2.0)).clamp(0.0, 1.0),
                child: Container(height: 12,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF880E4F), Color(0xFFE91E63)]),
                    borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Un ratio > 1 indique que chaque annonce génère en moyenne plus d\'1 clic de contact.',
              style: TextStyle(fontFamily: 'Poppins',
                  fontSize: 9, color: AppTheme.textHint)),
          ]),
        ),
        const SizedBox(height: 12),

        // ── Histogramme mensuel WA vs Appel ──────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.bar_chart_rounded,
                  color: Color(0xFF880E4F), size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text('Volume mensuel — WhatsApp vs Appel',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: AppTheme.textPrimary))),
            ]),
            const SizedBox(height: 8),
            // Légende
            Row(children: [
              Container(width: 10, height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366), shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text('WhatsApp',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                    color: AppTheme.textHint)),
              const SizedBox(width: 14),
              Container(width: 10, height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0), shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text('Appel',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                    color: AppTheme.textHint)),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: 130,
              child: CustomPaint(
                painter: _Kpi3DualBarPainter(
                  data: monthData,
                  maxVal: maxBar.toDouble(),
                ),
                child: Container(),
              ),
            ),
            const SizedBox(height: 4),
            // Labels X
            SizedBox(
              height: 16,
              child: Row(
                children: monthData.map((m) => Expanded(
                  child: Center(child: Text(m.label,
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 7, color: AppTheme.textHint))),
                )).toList(),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  // Labels axe X
  Widget _kpiXLabels(List<MapEntry<String, double>> entries) =>
    SizedBox(
      height: 18,
      child: LayoutBuilder(builder: (ctx, constraints) {
        if (entries.isEmpty) return const SizedBox.shrink();
        final w = constraints.maxWidth / entries.length;
        final showEvery = entries.length > 10 ? (entries.length ~/ 5) : 1;
        return Stack(children: List.generate(entries.length, (i) {
          if (i % showEvery != 0) return const SizedBox.shrink();
          return Positioned(left: i * w, width: w,
            child: Center(child: Text(entries[i].key,
              style: const TextStyle(fontSize: 8, fontFamily: 'Poppins',
                  color: AppTheme.textHint))));
        }));
      }),
    );

}




// ── Modèle barre mensuelle KPI 3 ─────────────────────────────────────────────

class _Kpi3MonthBar {
  final String label;
  final int wa;
  final int call;
  const _Kpi3MonthBar({required this.label, required this.wa, required this.call});
}

// ── Painter : histogramme double KPI 3 (WA vert + Appel bleu) ────────────────

class _Kpi3DualBarPainter extends CustomPainter {
  final List<_Kpi3MonthBar> data;
  final double maxVal;
  const _Kpi3DualBarPainter({required this.data, required this.maxVal});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final n      = data.length;
    final slotW  = size.width / n;
    final barW   = slotW * 0.28;
    final maxH   = size.height - 4;
    const waColor   = Color(0xFF25D366);
    const callColor = Color(0xFF1565C0);

    for (int i = 0; i < n; i++) {
      final d = data[i];
      final baseX = i * slotW;

      // WA bar (left)
      final hWa = maxVal > 0 ? (d.wa / maxVal) * maxH : 0.0;
      if (hWa > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(baseX + slotW * 0.05, size.height - hWa, barW, math.max(hWa, 2)),
            topLeft: const Radius.circular(2), topRight: const Radius.circular(2),
          ),
          Paint()..color = waColor.withValues(alpha: 0.85),
        );
      }

      // Call bar (right)
      final hCall = maxVal > 0 ? (d.call / maxVal) * maxH : 0.0;
      if (hCall > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(baseX + slotW * 0.05 + barW + 2, size.height - hCall, barW, math.max(hCall, 2)),
            topLeft: const Radius.circular(2), topRight: const Radius.circular(2),
          ),
          Paint()..color = callColor.withValues(alpha: 0.85),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Kpi3DualBarPainter old) =>
      old.data != data || old.maxVal != maxVal;
}

// ── Painter : histogramme simple KPI 2 (visiteurs) ────────────────────────

class _Kpi2BarPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final double maxVal;
  final Color barColor;
  const _Kpi2BarPainter({
    required this.entries,
    required this.maxVal,
    required this.barColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final n     = entries.length;
    final slotW = size.width / n;
    final barW  = slotW * 0.55;
    final maxH  = size.height - 4;

    for (int i = 0; i < n; i++) {
      final val = entries[i].value;
      final h   = maxVal > 0 ? (val / maxVal) * maxH : 0.0;
      final x   = i * slotW + (slotW - barW) / 2;
      final y   = size.height - h;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barW, math.max(h, 2)),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [barColor, barColor.withValues(alpha: 0.55)],
          ).createShader(Rect.fromLTWH(x, y, barW, h)),
      );
    }
  }

  @override
  bool shouldRepaint(_Kpi2BarPainter old) =>
      old.entries != entries || old.maxVal != maxVal;
}

// ── Painter : graphique dual (barres périodiques + courbe cumulée) ─────────────

class _KpiDualChartPainter extends CustomPainter {
  final List<MapEntry<String, double>> barEntries;
  final List<MapEntry<String, double>> lineEntries;
  final double maxBar;
  final double maxLine;

  _KpiDualChartPainter({
    required this.barEntries,
    required this.lineEntries,
    required this.maxBar,
    required this.maxLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barEntries.isEmpty) return;
    final n = barEntries.length;
    final slotW = size.width / n;
    final barW = slotW * 0.55;
    final maxH = size.height - 4;

    // ── Barres (recette périodique) ──
    for (int i = 0; i < n; i++) {
      final val = barEntries[i].value;
      final h = maxBar > 0 ? (val / maxBar) * maxH : 0.0;
      final x = i * slotW + (slotW - barW) / 2;
      final y = size.height - h;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [const Color(0xFFFFA726), const Color(0xFFE65100).withValues(alpha: 0.7)],
        ).createShader(Rect.fromLTWH(x, y, barW, h));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barW, math.max(h, 2)),
          topLeft: const Radius.circular(3), topRight: const Radius.circular(3),
        ),
        paint,
      );
    }

    // ── Courbe (recette cumulée) ──
    if (lineEntries.length < 2) return;
    final stepX = size.width / (lineEntries.length - 1);
    final points = <Offset>[];
    for (int i = 0; i < lineEntries.length; i++) {
      final x = i * stepX;
      final y = size.height - (maxLine > 0 ? (lineEntries[i].value / maxLine) * maxH : 0.0);
      points.add(Offset(x, y));
    }

    // Fill
    final fillPath = Path()
      ..moveTo(points.first.dx, size.height)
      ..lineTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final p = points[i - 1]; final c = points[i];
      final cp1 = Offset(p.dx + stepX * 0.4, p.dy);
      final cp2 = Offset(c.dx - stepX * 0.4, c.dy);
      fillPath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, c.dx, c.dy);
    }
    fillPath..lineTo(points.last.dx, size.height)..close();
    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [const Color(0xFF006064).withValues(alpha: 0.25),
                 const Color(0xFF006064).withValues(alpha: 0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill);

    // Ligne
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final p = points[i - 1]; final c = points[i];
      linePath.cubicTo(p.dx + stepX * 0.4, p.dy, c.dx - stepX * 0.4, c.dy, c.dx, c.dy);
    }
    canvas.drawPath(linePath, Paint()
      ..color = const Color(0xFF006064)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round);

    // Points clés
    final showEvery = lineEntries.length > 12 ? (lineEntries.length ~/ 6) : 1;
    for (int i = 0; i < points.length; i++) {
      if (i % showEvery != 0 && i != points.length - 1) continue;
      canvas.drawCircle(points[i], 4.5, Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(points[i], 3.0, Paint()..color = const Color(0xFF006064)..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_KpiDualChartPainter old) =>
      old.barEntries != barEntries || old.lineEntries != lineEntries;
}

// ── Modèle segment donut KPI ──────────────────────────────────────────────────

class _KpiDonutSeg {
  final String label;
  final double amount;
  final Color color;
  const _KpiDonutSeg(this.label, this.amount, this.color);
}

// ── Painter : graphique anneau (donut) KPI ────────────────────────────────────

class _KpiDonutPainter extends CustomPainter {
  final List<_KpiDonutSeg> segments;
  final double total;
  const _KpiDonutPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeW = radius * 0.36;
    if (total <= 0) {
      canvas.drawCircle(center, radius - strokeW / 2, Paint()
        ..color = const Color(0xFFEEEEEE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW);
      return;
    }
    double startAngle = -math.pi / 2;
    for (final s in segments) {
      if (s.amount <= 0) continue;
      final sweep = (s.amount / total) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeW / 2),
        startAngle + 0.025, sweep - 0.05, false,
        Paint()..color = s.color..style = PaintingStyle.stroke
               ..strokeWidth = strokeW..strokeCap = StrokeCap.butt,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_KpiDonutPainter old) =>
      old.segments != segments || old.total != total;
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
