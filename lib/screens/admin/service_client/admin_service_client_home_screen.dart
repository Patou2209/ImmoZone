import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/payment_model.dart';
import '../../../models/app_notification_model.dart';
import '../../../models/credit_model.dart';
import '../../../models/user_model.dart';
import '../../../services/data_service.dart';
import '../../../services/csv_export_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminServiceClientHomeScreen
// 4 tabs:
//   0 — Notifications recharges manuelles (awaiting_manual)
//   1 — Transactions dernière heure (confirmed, last 60 min)
//   2 — Crédit manuel
//   3 — Feedback & Plaintes
// ─────────────────────────────────────────────────────────────────────────────

class AdminServiceClientHomeScreen extends StatefulWidget {
  const AdminServiceClientHomeScreen({super.key});

  @override
  State<AdminServiceClientHomeScreen> createState() =>
      _AdminServiceClientHomeScreenState();
}

class _AdminServiceClientHomeScreenState
    extends State<AdminServiceClientHomeScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  late TabController _tabCtrl;

  // ── Shared data ──────────────────────────────────────────────────────────
  List<PaymentModel> _allPayments = [];
  List<AppNotification> _allNotifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final payments = await _ds.getPayments();
      payments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Notifications all users (service client sees feedback/complaints)
      // We query globally from Firestore for types feedback/plainte
      final notifs = await _ds.getGlobalNotifications();

      if (!mounted) return;
      setState(() {
        _allPayments = payments;
        _allNotifications = notifs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snackErr('Erreur de chargement : $e');
    }
  }

  // ── Computed lists ───────────────────────────────────────────────────────
  List<PaymentModel> get _awaitingManual =>
      _allPayments.where((p) => p.status == 'awaiting_manual').toList();

  List<PaymentModel> get _lastHourConfirmed {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    return _allPayments
        .where((p) => p.isConfirmed && p.createdAt.isAfter(cutoff))
        .toList();
  }

  List<AppNotification> get _feedbackNotifs => _allNotifications
      .where((n) => n.type == 'feedback' || n.type == 'plainte')
      .toList();

  // ── Helpers ──────────────────────────────────────────────────────────────
  void _snackOk(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _snackErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Export CSV — toutes les transactions Service Client ───────────────────
  Future<void> _exportCsv() async {
    if (_allPayments.isEmpty) {
      _snackErr('Aucune transaction à exporter');
      return;
    }

    final buf = StringBuffer();
    buf.writeln('Export Service Client ImmoZone');
    buf.writeln('Généré le,${CsvExportService.fmtDateTime(DateTime.now())}');
    buf.writeln('Total transactions,${_allPayments.length}');
    buf.writeln('En attente validation,${_awaitingManual.length}');
    buf.writeln('Transactions (dernière heure),${_lastHourConfirmed.length}');
    buf.writeln();

    buf.writeln('Date/Heure,Utilisateur,Téléphone,Type,Montant (USD),Statut,Référence');
    for (final p in _allPayments) {
      buf.writeln(
          '${CsvExportService.fmtDateTime(p.createdAt)},'
          '${CsvExportService.q(p.userName)},'
          '${CsvExportService.q(p.phoneNumber)},'
          '${CsvExportService.q(p.productLabel)},'
          '${CsvExportService.fmtAmount(p.amount)},'
          '${CsvExportService.q(p.status)},'
          '${CsvExportService.q(p.transactionReference)}');
    }

    final csv = buf.toString();
    final fname = CsvExportService.fileName('service_client_transactions');
    final path = await CsvExportService.export(csvContent: csv, fileName: fname);

    if (!mounted) return;
    if (path != null) {
      _snackOk('CSV exporté : $fname');
    } else {
      _snackErr('Erreur lors de l\'export');
    }
  }

  // ── Validate manual payment (service client can approve/reject) ──────────
  Future<void> _onValidate(
      String paymentId, bool approve, String? note) async {
    try {
      await _ds.validatePaymentManually(
        paymentId,
        adminId: _ds.currentUserId,
        adminName: _ds.currentUserName,
        approve: approve,
        note: note,
      );
    } catch (e) {
      rethrow;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        approve
            ? 'Recharge validée — crédits accordés'
            : 'Recharge rejetée',
        style: const TextStyle(fontFamily: 'Poppins'),
      ),
      backgroundColor:
          approve ? AppTheme.successColor : AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Service Client',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
            tooltip: 'Actualiser',
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            tooltip: 'Exporter CSV',
            onPressed: _isLoading ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Déconnexion',
            onPressed: () async {
              final auth =
                  Provider.of<AuthProvider>(context, listen: false);
              await auth.logout();
              if (!mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/login', (_) => false);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xFFFFA726),
          unselectedLabelColor: Colors.white,
          indicatorColor: const Color(0xFFFFA726),
          indicatorWeight: 3,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 10),
          tabs: [
            Tab(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.notifications_active_outlined, size: 16),
                const SizedBox(height: 2),
                Text(
                  'Recharges${_awaitingManual.isNotEmpty ? " (${_awaitingManual.length})" : ""}',
                  style: const TextStyle(fontSize: 9),
                ),
              ]),
            ),
            Tab(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.history_rounded, size: 16),
                const SizedBox(height: 2),
                Text(
                  'Dernière heure${_lastHourConfirmed.isNotEmpty ? " (${_lastHourConfirmed.length})" : ""}',
                  style: const TextStyle(fontSize: 9),
                ),
              ]),
            ),
            const Tab(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_card_rounded, size: 16),
                SizedBox(height: 2),
                Text('Crédit manuel', style: TextStyle(fontSize: 9)),
              ]),
            ),
            Tab(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.feedback_outlined, size: 16),
                const SizedBox(height: 2),
                Text(
                  'Feedback${_feedbackNotifs.isNotEmpty ? " (${_feedbackNotifs.length})" : ""}',
                  style: const TextStyle(fontSize: 9),
                ),
              ]),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                // Tab 0 — Recharges manuelles en attente
                _RechargeNotifTab(
                  payments: _awaitingManual,
                  onRefresh: _load,
                  onValidate: _onValidate,
                ),
                // Tab 1 — Transactions dernière heure
                _LastHourTransactionsTab(
                  payments: _lastHourConfirmed,
                  onRefresh: _load,
                ),
                // Tab 2 — Crédit manuel
                _ManualCreditTab(
                  dataService: _ds,
                  onSuccess: (msg) => _snackOk(msg),
                  onError: (msg) => _snackErr(msg),
                  onRefresh: _load,
                ),
                // Tab 3 — Feedback & Plaintes
                _FeedbackTab(
                  notifications: _feedbackNotifs,
                  onRefresh: _load,
                ),
              ],
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 0 — Notifications recharges manuelles
// ═════════════════════════════════════════════════════════════════════════════

class _RechargeNotifTab extends StatelessWidget {
  final List<PaymentModel> payments;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String, bool, String?) onValidate;

  const _RechargeNotifTab({
    required this.payments,
    required this.onRefresh,
    required this.onValidate,
  });

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.notifications_none_rounded,
              size: 64,
              color: AppTheme.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            'Aucune recharge manuelle en attente',
            style: TextStyle(
                fontFamily: 'Poppins', color: AppTheme.textSecondary),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.accentColor,
      child: Column(
        children: [
          // Badge résumé
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.pending_actions_rounded,
                  color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                '${payments.length} recharge(s) en attente de validation',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: payments.length,
              itemBuilder: (_, i) {
                final p = payments[i];
                return _PaymentActionTile(
                  key: ValueKey(p.id),
                  payment: p,
                  onValidate: (approve, note) =>
                      onValidate(p.id, approve, note),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 1 — Transactions dernière heure
// ═════════════════════════════════════════════════════════════════════════════

class _LastHourTransactionsTab extends StatelessWidget {
  final List<PaymentModel> payments;
  final Future<void> Function() onRefresh;

  const _LastHourTransactionsTab({
    required this.payments,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final total = payments.fold<double>(0, (s, p) => s + p.amount);

    if (payments.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.hourglass_empty_rounded,
              size: 64,
              color: AppTheme.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            'Aucune transaction dans la dernière heure',
            style: TextStyle(
                fontFamily: 'Poppins', color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Les transactions s\'actualisent en temps réel',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: AppTheme.textHint,
                fontSize: 11),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.accentColor,
      child: Column(
        children: [
          // Bande résumé
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.successColor.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.access_time_rounded,
                  color: AppTheme.successColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${payments.length} transaction(s) — ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.successColor),
                ),
              ),
              Text(
                '\$${total.toStringAsFixed(2)} USD',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.successColor),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: payments.length,
              itemBuilder: (_, i) {
                return _TransactionTile(payment: payments[i]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 2 — Crédit Manuel
// ═════════════════════════════════════════════════════════════════════════════

class _ManualCreditTab extends StatefulWidget {
  final DataService dataService;
  final void Function(String) onSuccess;
  final void Function(String) onError;
  final Future<void> Function() onRefresh;

  const _ManualCreditTab({
    required this.dataService,
    required this.onSuccess,
    required this.onError,
    required this.onRefresh,
  });

  @override
  State<_ManualCreditTab> createState() => _ManualCreditTabState();
}

class _ManualCreditTabState extends State<_ManualCreditTab> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _creditsCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  UserModel? _foundUser;
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _creditsCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() {
      _searching = true;
      _foundUser = null;
      _searchError = null;
    });
    try {
      final users = await widget.dataService.getUsers();
      final match = users.where((u) =>
          u.phone.replaceAll(RegExp(r'\s+'), '') ==
          phone.replaceAll(RegExp(r'\s+'), '')).toList();
      if (match.isNotEmpty) {
        setState(() {
          _foundUser = match.first;
          _searching = false;
        });
      } else {
        setState(() {
          _searchError = 'Aucun utilisateur trouvé avec ce numéro';
          _searching = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchError = 'Erreur de recherche : $e';
        _searching = false;
      });
    }
  }

  Future<void> _grantCredit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_foundUser == null) {
      widget.onError('Veuillez d\'abord rechercher un utilisateur');
      return;
    }
    final qty = int.tryParse(_creditsCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      widget.onError('Quantité de crédits invalide');
      return;
    }

    setState(() => _saving = true);
    try {
      final user = _foundUser!;
      final note = _noteCtrl.text.trim();
      final agentName = widget.dataService.currentUserName.isNotEmpty
          ? widget.dataService.currentUserName
          : 'Admin Service Client';

      // 1. Ajouter les crédits
      await widget.dataService.addCredit(CreditModel(
        id:
            'credit_manual_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        quantity: qty,
        remaining: qty,
        source: 'admin_manuel',
        createdAt: DateTime.now(),
      ));

      // 2. Notifier l'utilisateur
      await widget.dataService.addNotification(AppNotification(
        id:
            'notif_credit_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        type: 'paiement',
        title: 'Crédits ajoutés manuellement',
        body: '$qty crédit(s) ont été ajoutés à votre compte par $agentName.'
            '${note.isNotEmpty ? '\nNote : $note' : ''}',
        createdAt: DateTime.now(),
      ));

      // 3. Notifier les admins généraux
      await _notifyGeneralAdmins(user, qty, note, agentName);

      // 4. Feedback
      widget.onSuccess(
          '$qty crédit(s) accordés à ${user.name} (${user.phone})');
      _phoneCtrl.clear();
      _creditsCtrl.clear();
      _noteCtrl.clear();
      setState(() {
        _foundUser = null;
        _saving = false;
      });
      await widget.onRefresh();
    } catch (e) {
      setState(() => _saving = false);
      widget.onError('Erreur : $e');
    }
  }

  Future<void> _notifyGeneralAdmins(
      UserModel user, int qty, String note, String agentName) async {
    try {
      final allUsers = await widget.dataService.getUsers();
      final admins = allUsers.where((u) => u.role == 'admin').toList();
      for (final admin in admins) {
        await widget.dataService.addNotification(AppNotification(
          id:
              'notif_adm_credit_${admin.id}_${DateTime.now().millisecondsSinceEpoch}_${user.id}',
          userId: admin.id,
          type: 'info',
          title: 'Recharge manuelle effectuée',
          body: '$agentName a accordé $qty crédit(s) à ${user.name}'
              ' (${user.phone}).'
              '${note.isNotEmpty ? '\nNote : $note' : ''}',
          createdAt: DateTime.now(),
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ManualCredit] notify admins error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Titre ────────────────────────────────────────────────────────
          _sectionHeader('Crédit Manuel', Icons.add_card_rounded,
              AppTheme.accentColor),
          const SizedBox(height: 16),

          // ── Champ téléphone + recherche ──────────────────────────────────
          const Text('Numéro de téléphone',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style:
                    const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                decoration: InputDecoration(
                  hintText: '+243 8X XXX XXXX',
                  hintStyle: const TextStyle(
                      fontFamily: 'Poppins', color: AppTheme.textHint),
                  prefixIcon: const Icon(Icons.phone_outlined,
                      color: AppTheme.accentColor, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppTheme.dividerColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppTheme.dividerColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.accentColor, width: 1.5)),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Numéro requis'
                    : null,
                onFieldSubmitted: (_) => _searchUser(),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _searching ? null : _searchUser,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.search_rounded,
                      color: Colors.white, size: 20),
            ),
          ]),

          // ── Résultat recherche ───────────────────────────────────────────
          if (_searchError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.errorColor.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.errorColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_searchError!,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: AppTheme.errorColor)),
                ),
              ]),
            ),
          ],

          if (_foundUser != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.successColor.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryColor,
                  child: Text(
                    _foundUser!.initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_foundUser!.name,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                      Text(_foundUser!.phone,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_foundUser!.roleLabel,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.successColor)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.successColor, size: 22),
              ]),
            ),
          ],

          const SizedBox(height: 20),

          // ── Champ crédits ────────────────────────────────────────────────
          const Text('Nombre de crédits',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _creditsCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ex : 50',
              hintStyle: const TextStyle(
                  fontFamily: 'Poppins', color: AppTheme.textHint),
              prefixIcon: const Icon(Icons.toll_rounded,
                  color: AppTheme.accentColor, size: 18),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppTheme.dividerColor)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppTheme.dividerColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: AppTheme.accentColor, width: 1.5)),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Quantité requise';
              final n = int.tryParse(v.trim());
              if (n == null || n <= 0) return 'Nombre entier positif requis';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // ── Note optionnelle ─────────────────────────────────────────────
          const Text('Note (optionnelle)',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _noteCtrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Raison ou remarque pour les admins...',
              hintStyle: const TextStyle(
                  fontFamily: 'Poppins', color: AppTheme.textHint),
              prefixIcon: const Icon(Icons.note_outlined,
                  color: AppTheme.textHint, size: 18),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppTheme.dividerColor)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppTheme.dividerColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: AppTheme.accentColor, width: 1.5)),
            ),
          ),

          const SizedBox(height: 8),

          // ── Info auto-notification ───────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline,
                  size: 14,
                  color: AppTheme.primaryColor.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Les administrateurs généraux seront automatiquement notifiés de cette opération.',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppTheme.textSecondary),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Bouton Accorder ──────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_saving || _foundUser == null) ? null : _grantCredit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline,
                      color: Colors.white, size: 20),
              label: Text(
                _saving ? 'Attribution en cours...' : 'Accorder les crédits',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _foundUser != null
                    ? AppTheme.successColor
                    : Colors.grey.shade400,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 3 — Feedback & Plaintes
// ═════════════════════════════════════════════════════════════════════════════

class _FeedbackTab extends StatelessWidget {
  final List<AppNotification> notifications;
  final Future<void> Function() onRefresh;

  const _FeedbackTab({
    required this.notifications,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.feedback_outlined,
              size: 64,
              color: AppTheme.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            'Aucun feedback ou plainte',
            style: TextStyle(
                fontFamily: 'Poppins', color: AppTheme.textSecondary),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: notifications.length,
        itemBuilder: (_, i) {
          return _FeedbackTile(notif: notifications[i]);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PaymentActionTile — recharge avec boutons Rejeter / Valider
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentActionTile extends StatefulWidget {
  final PaymentModel payment;
  final Future<void> Function(bool approve, String? note) onValidate;

  const _PaymentActionTile({
    super.key,
    required this.payment,
    required this.onValidate,
  });

  @override
  State<_PaymentActionTile> createState() => _PaymentActionTileState();
}

class _PaymentActionTileState extends State<_PaymentActionTile> {
  bool _processing = false;

  void _showDialog(bool approve) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(approve ? Icons.check_circle : Icons.cancel,
              color: approve ? AppTheme.successColor : AppTheme.errorColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              approve ? 'Valider la recharge' : 'Rejeter la recharge',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dlgRow(Icons.person_outline,
                    widget.payment.userName.isNotEmpty
                        ? widget.payment.userName
                        : 'Utilisateur'),
                _dlgRow(Icons.phone, widget.payment.phoneNumber),
                _dlgRow(Icons.toll_rounded,
                    '\$${widget.payment.amount.toStringAsFixed(2)} USD'),
                if (widget.payment.transactionReference != null)
                  _dlgRow(Icons.confirmation_number,
                      'Réf : ${widget.payment.transactionReference}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            style:
                const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: approve
                  ? 'Note optionnelle...'
                  : 'Motif du rejet...',
              hintStyle: const TextStyle(
                  fontFamily: 'Poppins', color: AppTheme.textHint),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              noteCtrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Annuler',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final note = noteCtrl.text.trim().isEmpty
                  ? null
                  : noteCtrl.text.trim();
              Navigator.pop(ctx);
              noteCtrl.dispose();
              if (!mounted) return;
              setState(() => _processing = true);
              try {
                await widget.onValidate(approve, note);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Erreur : $e',
                        style:
                            const TextStyle(fontFamily: 'Poppins')),
                    backgroundColor: AppTheme.errorColor,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              } finally {
                if (mounted) setState(() => _processing = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  approve ? AppTheme.successColor : AppTheme.errorColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(approve ? 'Valider' : 'Rejeter',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _dlgRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 13, color: AppTheme.textHint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppTheme.textPrimary)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Colors.orange.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.payment_rounded,
                    color: Colors.orange, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.userName.isNotEmpty ? p.userName : 'Utilisateur',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                    Text(
                      p.phoneNumber,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  '\$${p.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentColor),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'En attente',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange),
                  ),
                ),
              ]),
            ]),

            const SizedBox(height: 8),
            _infoRow(
                Icons.schedule,
                '${p.createdAt.day.toString().padLeft(2, '0')}/'
                '${p.createdAt.month.toString().padLeft(2, '0')}/'
                '${p.createdAt.year}  '
                '${p.createdAt.hour.toString().padLeft(2, '0')}:'
                '${p.createdAt.minute.toString().padLeft(2, '0')}'),
            if (p.transactionReference != null)
              _infoRow(Icons.confirmation_number,
                  'Réf : ${p.transactionReference!}'),

            const Divider(height: 20),

            // ── Boutons ────────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _showDialog(false),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Rejeter',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    side: const BorderSide(color: AppTheme.errorColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _processing ? null : () => _showDialog(true),
                  icon: _processing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 16),
                  label: Text(
                    _processing ? 'Traitement...' : 'Valider',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 13, color: AppTheme.textHint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppTheme.textSecondary)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _TransactionTile — transaction lecture seule
// ─────────────────────────────────────────────────────────────────────────────
class _TransactionTile extends StatelessWidget {
  final PaymentModel payment;

  const _TransactionTile({required this.payment});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    return 'il y a ${diff.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.successColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline,
                color: AppTheme.successColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.userName.isNotEmpty ? p.userName : 'Utilisateur',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                ),
                Text(
                  p.phoneNumber,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppTheme.textSecondary),
                ),
                Text(
                  _timeAgo(p.createdAt),
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: AppTheme.textHint),
                ),
              ],
            ),
          ),
          Text(
            '\$${p.amount.toStringAsFixed(2)}',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.accentColor),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeedbackTile — notification feedback / plainte
// ─────────────────────────────────────────────────────────────────────────────
class _FeedbackTile extends StatelessWidget {
  final AppNotification notif;

  const _FeedbackTile({required this.notif});

  Color _typeColor() =>
      notif.type == 'plainte' ? AppTheme.errorColor : AppTheme.accentColor;

  IconData _typeIcon() =>
      notif.type == 'plainte' ? Icons.report_problem_outlined : Icons.feedback_outlined;

  String _typeLabel() =>
      notif.type == 'plainte' ? 'Plainte' : 'Feedback';

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return 'il y a ${diff.inDays}j';
    if (diff.inHours > 0) return 'il y a ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'il y a ${diff.inMinutes} min';
    return 'à l\'instant';
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_typeIcon(), color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notif.title.isNotEmpty ? notif.title : _typeLabel(),
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                    Text(
                      _timeAgo(notif.createdAt),
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: AppTheme.textHint),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _typeLabel(),
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color),
                ),
              ),
            ]),

            if (notif.body.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                notif.body,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.5),
              ),
            ],

            if (!notif.isRead) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Non lu',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionHeader(String title, IconData icon, Color color) {
  return Row(children: [
    Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    const SizedBox(width: 12),
    Text(
      title,
      style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: color),
    ),
  ]);
}
