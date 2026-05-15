import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/audit_log_model.dart';
import '../../../services/data_service.dart';

class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key});
  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  final _ds = DataService();
  List<AuditLogModel> _logs = [];
  bool _isLoading = true;
  String _filter = 'all';

  final _filters = [
    {'id': 'all', 'label': 'Tous'},
    {'id': 'property', 'label': 'Annonces'},
    {'id': 'payment', 'label': 'Paiements'},
    {'id': 'user', 'label': 'Utilisateurs'},
    {'id': 'system', 'label': 'Système'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _logs = await _ds.getAuditLogs(limit: 200);
    setState(() => _isLoading = false);
  }

  List<AuditLogModel> get _filtered => _filter == 'all'
      ? _logs
      : _logs.where((l) => l.entityType == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Journal d\'Audit'),
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(
        children: [
          // Filtres
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final selected = _filter == f['id'];
                  return GestureDetector(
                    onTap: () => setState(() => _filter = f['id']!),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.primaryColor : AppTheme.backgroundColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? AppTheme.primaryColor : AppTheme.dividerColor,
                        ),
                      ),
                      child: Text(f['label']!,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : AppTheme.textSecondary)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
                : _filtered.isEmpty
                    ? Center(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.history, size: 56,
                              color: AppTheme.textHint.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text('Aucun log', style: TextStyle(
                              fontFamily: 'Poppins', color: AppTheme.textSecondary)),
                        ]),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.accentColor,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _LogTile(log: _filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final AuditLogModel log;
  const _LogTile({required this.log});

  Color _typeColor() {
    switch (log.entityType) {
      case 'property': return AppTheme.primaryColor;
      case 'payment': return AppTheme.successColor;
      case 'user': return Colors.purple;
      case 'system': return Colors.orange;
      default: return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _typeColor().withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                log.entityType == 'property' ? '📢'
                    : log.entityType == 'payment' ? '💳'
                    : log.entityType == 'user' ? '👤'
                    : '⚙️',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(log.actionLabel,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(log.description,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      color: AppTheme.textSecondary, height: 1.4)),
              const SizedBox(height: 4),
              Row(children: [
                if (log.actorName != null) ...[
                  Icon(Icons.person_outline, size: 11, color: AppTheme.textHint),
                  const SizedBox(width: 3),
                  Text(log.actorName!,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                          color: AppTheme.textHint)),
                  const SizedBox(width: 10),
                ],
                Icon(Icons.schedule, size: 11, color: AppTheme.textHint),
                const SizedBox(width: 3),
                Text(
                  '${log.createdAt.day}/${log.createdAt.month}/${log.createdAt.year} '
                  '${log.createdAt.hour.toString().padLeft(2,'0')}:${log.createdAt.minute.toString().padLeft(2,'0')}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      color: AppTheme.textHint)),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}
