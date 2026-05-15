import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/report_model.dart';
import '../../../services/data_service.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  late TabController _tabCtrl;
  List<ReportModel> _all = [];
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
    setState(() => _isLoading = true);
    _all = await _ds.getReports();
    setState(() => _isLoading = false);
  }

  List<ReportModel> _byStatus(String s) => _all.where((r) => r.status == s).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Signalements'),
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12),
          tabs: [
            Tab(text: 'En attente (${_byStatus('pending').length})'),
            Tab(text: 'Traités (${_byStatus('treated').length})'),
            Tab(text: 'Classés (${_byStatus('dismissed').length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(_byStatus('pending'), showActions: true),
                _buildList(_byStatus('treated')),
                _buildList(_byStatus('dismissed')),
              ],
            ),
    );
  }

  Widget _buildList(List<ReportModel> items, {bool showActions = false}) {
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.flag_outlined, size: 56, color: AppTheme.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('Aucun signalement', style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) => _ReportTile(
          report: items[i],
          showActions: showActions,
          onHandle: showActions ? (status, note) async {
            await _ds.handleReport(items[i].id, status, adminNote: note);
            await _load();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Signalement ${status == 'treated' ? 'traité' : 'classé'}',
                    style: const TextStyle(fontFamily: 'Poppins')),
                backgroundColor: AppTheme.successColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
            }
          } : null,
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final ReportModel report;
  final bool showActions;
  final Function(String status, String? note)? onHandle;

  const _ReportTile({required this.report, this.showActions = false, this.onHandle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: showActions
            ? Border.all(color: Colors.orange.withValues(alpha: 0.4), width: 1.5)
            : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flag, color: Colors.red, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(report.propertyTitle,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('Signalé par ${report.reporterName}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      color: AppTheme.textSecondary)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
              ),
              child: Text(report.reasonLabel,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w600, color: Colors.red)),
            ),
          ]),
          if (report.description != null && report.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8),
              ),
              child: Text(report.description!,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: AppTheme.textSecondary, height: 1.4)),
            ),
          ],
          const SizedBox(height: 8),
          Text('${report.createdAt.day}/${report.createdAt.month}/${report.createdAt.year}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppTheme.textHint)),
          if (report.adminNote != null) ...[
            const SizedBox(height: 6),
            Text('Note admin: ${report.adminNote}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontStyle: FontStyle.italic, color: AppTheme.textSecondary)),
          ],
          if (showActions && onHandle != null) ...[
            const Divider(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _handleDialog(context, 'dismissed'),
                  icon: const Icon(Icons.archive_outlined, size: 14),
                  label: const Text('Classer', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.dividerColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _handleDialog(context, 'treated'),
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Traiter', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  void _handleDialog(BuildContext context, String status) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(status == 'treated' ? 'Traiter le signalement' : 'Classer sans suite',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Note administrative (optionnelle)...',
            hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () { noteCtrl.dispose(); Navigator.pop(ctx); },
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
            onPressed: () {
              final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();
              noteCtrl.dispose();
              Navigator.pop(ctx);
              onHandle?.call(status, note);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirmer', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
