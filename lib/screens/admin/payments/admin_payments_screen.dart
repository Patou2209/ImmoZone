import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/payment_model.dart';
import '../../../services/data_service.dart';

class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});
  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  late TabController _tabCtrl;
  List<PaymentModel> _allPayments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final payments = await _ds.getPayments();
    payments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      _allPayments = payments;
      _isLoading = false;
    });
  }

  List<PaymentModel> get _pending =>
      _allPayments.where((p) => p.status == 'awaiting_manual').toList();
  List<PaymentModel> get _confirmed =>
      _allPayments.where((p) => p.isConfirmed).toList();
  List<PaymentModel> get _failed =>
      _allPayments.where((p) => p.isFailed).toList();

  double get _totalRevenue => _confirmed.fold(0, (s, p) => s + p.amount);

  // ── Callback de validation — appelé depuis _PaymentTile ──────────────────
  Future<void> _onValidate(String paymentId, bool approve, String? note) async {
    // Capture approve avant _load() pour ne pas perdre la valeur après rebuild
    final wasApprove = approve;
    try {
      await _ds.validatePaymentManually(
        paymentId,
        adminId: _ds.currentUserId,
        adminName: _ds.currentUserName,
        approve: wasApprove,
        note: note,
      );
    } catch (e) {
      // Remonter l'exception : _PaymentTileState.catch l'affichera en rouge
      rethrow;
    }
    // Recharger la liste (peut déclencher un rebuild, d'où la capture wasApprove)
    await _load();
    // Afficher la confirmation APRÈS _load() pour s'assurer que le context est stable
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        wasApprove
            ? 'Paiement validé — crédits accordés automatiquement'
            : 'Paiement rejeté',
        style: const TextStyle(fontFamily: 'Poppins'),
      ),
      backgroundColor: wasApprove ? AppTheme.successColor : AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Gestion des Paiements'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12),
          tabs: [
            Tab(text: 'À valider (${_pending.length})'),
            Tab(text: 'Confirmés (${_confirmed.length})'),
            Tab(text: 'Rejetés (${_failed.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : Column(
              children: [
                // Bande revenu total
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: AppTheme.successColor.withValues(alpha: 0.08),
                  child: Row(children: [
                    const Icon(Icons.monetization_on,
                        color: AppTheme.successColor, size: 20),
                    const SizedBox(width: 8),
                    const Text('Revenu total confirmé : ',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            color: AppTheme.textSecondary)),
                    Text('\$${_totalRevenue.toStringAsFixed(2)} USD',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.successColor)),
                  ]),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildList(_pending, showActions: true),
                      _buildList(_confirmed),
                      _buildList(_failed),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildList(List<PaymentModel> items, {bool showActions = false}) {
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.payment_outlined, size: 56,
              color: AppTheme.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('Aucun paiement',
              style: TextStyle(fontFamily: 'Poppins',
                  color: AppTheme.textSecondary)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final payment = items[i]; // capture stable
          return _PaymentTile(
            key: ValueKey(payment.id),
            payment: payment,
            showActions: showActions,
            onValidate: showActions
                ? (approve, note) => _onValidate(payment.id, approve, note)
                : null,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PaymentTile — StatefulWidget pour gérer l'état _processing
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentTile extends StatefulWidget {
  final PaymentModel payment;
  final bool showActions;
  final Future<void> Function(bool approve, String? note)? onValidate;

  const _PaymentTile({
    super.key,
    required this.payment,
    this.showActions = false,
    this.onValidate,
  });

  @override
  State<_PaymentTile> createState() => _PaymentTileState();
}

class _PaymentTileState extends State<_PaymentTile> {
  bool _processing = false;

  Color _statusColor() {
    switch (widget.payment.status) {
      case 'confirmed':       return AppTheme.successColor;
      case 'awaiting_manual': return Colors.orange;
      case 'pending':         return AppTheme.statusPending;
      default:                return AppTheme.errorColor;
    }
  }

  // ── Ouvre le dialog de confirmation ──────────────────────────────────────
  void _showValidationDialog(BuildContext context, bool approve) {
    final noteCtrl = TextEditingController();
    final payment  = widget.payment;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            approve ? Icons.check_circle : Icons.cancel,
            color: approve ? AppTheme.successColor : AppTheme.errorColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              approve ? 'Valider le paiement' : 'Rejeter le paiement',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          // Info utilisateur
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (approve ? AppTheme.successColor : AppTheme.errorColor)
                  .withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.person_outline, size: 13,
                      color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(payment.userName.isNotEmpty
                      ? payment.userName : 'Utilisateur',
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.toll_rounded, size: 13,
                      color: AppTheme.accentColor),
                  const SizedBox(width: 6),
                  Text(
                    payment.creditsQty > 0
                        ? '${payment.creditsQty} crédit(s) à accorder'
                        : '${payment.productLabel} — \$${payment.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        color: AppTheme.textSecondary),
                  ),
                ]),
                if (payment.transactionReference != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.confirmation_number, size: 13,
                        color: AppTheme.textHint),
                    const SizedBox(width: 6),
                    Text('Réf : ${payment.transactionReference}',
                        style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, color: AppTheme.textHint)),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: approve ? 'Note optionnelle...' : 'Motif du rejet...',
              hintStyle: const TextStyle(fontFamily: 'Poppins',
                  color: AppTheme.textHint),
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
                style: TextStyle(fontFamily: 'Poppins',
                    color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              // 1. Lire la note avant de fermer
              final note = noteCtrl.text.trim().isEmpty
                  ? null
                  : noteCtrl.text.trim();
              // 2. Fermer le dialog
              Navigator.pop(ctx);
              // 3. Dispose du controller APRES fermeture
              noteCtrl.dispose();
              // 4. Lancer la validation avec état loading
              if (!mounted) return;
              setState(() => _processing = true);
              try {
                await widget.onValidate?.call(approve, note);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Erreur : $e',
                        style: const TextStyle(fontFamily: 'Poppins')),
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
            child: Text(
              approve ? 'Valider' : 'Rejeter',
              style: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: widget.showActions
            ? Border.all(color: Colors.orange.withValues(alpha: 0.4), width: 1.5)
            : null,
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header : icône + titre + montant ──────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _statusColor().withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.payment, color: _statusColor(), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(payment.productLabel,
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${payment.userName.isNotEmpty ? payment.userName : "Utilisateur"}'
                    ' • ${payment.operatorLabel}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('\$${payment.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentColor)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(payment.statusLabel,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _statusColor())),
              ),
            ]),
          ]),
          const SizedBox(height: 10),

          // ── Détails ───────────────────────────────────────────────────────
          if (payment.creditsQty > 0)
            _infoRow(Icons.toll_rounded,
                '${payment.creditsQty} crédit(s) commandé(s)',
                color: AppTheme.accentColor),
          _infoRow(Icons.phone, payment.phoneNumber),
          if (payment.transactionReference != null)
            _infoRow(Icons.confirmation_number,
                'Réf: ${payment.transactionReference!}'),
          _infoRow(Icons.schedule,
              '${payment.createdAt.day.toString().padLeft(2, '0')}/'
              '${payment.createdAt.month.toString().padLeft(2, '0')}/'
              '${payment.createdAt.year}  '
              '${payment.createdAt.hour.toString().padLeft(2, '0')}:'
              '${payment.createdAt.minute.toString().padLeft(2, '0')}'),
          if (payment.manualNote != null)
            _infoRow(Icons.note_outlined, payment.manualNote!),
          if (payment.confirmedAt != null)
            _infoRow(Icons.check_circle_outline,
                'Confirmé le ${payment.confirmedAt!.day.toString().padLeft(2, '0')}/'
                '${payment.confirmedAt!.month.toString().padLeft(2, '0')}/'
                '${payment.confirmedAt!.year}',
                color: AppTheme.successColor),

          // ── Boutons Rejeter / Valider ──────────────────────────────────
          if (widget.showActions && widget.onValidate != null) ...[
            const Divider(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _showValidationDialog(context, false),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Rejeter',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    side: const BorderSide(color: AppTheme.errorColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _showValidationDialog(context, true),
                  icon: _processing
                      ? const SizedBox(
                          width: 14, height: 14,
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
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Icon(icon, size: 13,
          color: color ?? AppTheme.textHint),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: color ?? AppTheme.textSecondary)),
      ),
    ]),
  );
}
