import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/payment_model.dart';
import '../../../services/data_service.dart';

class AdminFinancierHomeScreen extends StatefulWidget {
  const AdminFinancierHomeScreen({super.key});

  @override
  State<AdminFinancierHomeScreen> createState() =>
      _AdminFinancierHomeScreenState();
}

class _AdminFinancierHomeScreenState extends State<AdminFinancierHomeScreen>
    with SingleTickerProviderStateMixin {
  final _ds = DataService();
  late TabController _tabCtrl;

  List<PaymentModel> _payments = [];
  bool _isLoading = true;
  String _selectedPeriod = 'mois'; // jour | semaine | mois | annee
  DateTimeRange? _customRange;

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
    setState(() => _isLoading = true);
    final all = await _ds.getPayments();
    if (mounted) {
      setState(() {
        _payments = all.where((p) => p.isConfirmed).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _isLoading = false;
      });
    }
  }

  // Filtre selon la periode selectionnee
  List<PaymentModel> get _filtered {
    final now = DateTime.now();
    DateTime from;
    switch (_selectedPeriod) {
      case 'jour':
        from = DateTime(now.year, now.month, now.day);
        break;
      case 'semaine':
        from = now.subtract(const Duration(days: 7));
        break;
      case 'annee':
        from = DateTime(now.year, 1, 1);
        break;
      case 'custom':
        if (_customRange != null) {
          return _payments
              .where((p) =>
                  p.createdAt.isAfter(_customRange!.start) &&
                  p.createdAt
                      .isBefore(_customRange!.end.add(const Duration(days: 1))))
              .toList();
        }
        return _payments;
      default: // mois
        from = DateTime(now.year, now.month, 1);
    }
    return _payments.where((p) => p.createdAt.isAfter(from)).toList();
  }

  double get _totalRevenue => _filtered.fold(0, (s, p) => s + p.amount);
  double get _rechargeRevenue => _filtered
      .where((p) =>
          p.productType.contains('souscription') ||
          p.productType.contains('pack') ||
          p.productType == 'publication_unitaire')
      .fold(0, (s, p) => s + p.amount);
  double get _boostRevenue => _filtered
      .where((p) => p.productType.contains('boost'))
      .fold(0, (s, p) => s + p.amount);
  double get _adsRevenue => _filtered
      .where((p) => p.productType == 'ads')
      .fold(0, (s, p) => s + p.amount);

  // Donnees par jour pour le graphique
  Map<String, double> _buildChartData() {
    final result = <String, double>{};
    final now = DateTime.now();
    int days;
    switch (_selectedPeriod) {
      case 'jour':
        days = 1;
        break;
      case 'semaine':
        days = 7;
        break;
      case 'annee':
        days = 30; // par mois
        break;
      default:
        days = 30;
    }

    if (_selectedPeriod == 'annee') {
      for (int m = 1; m <= 12; m++) {
        final label = _monthLabel(m);
        final sum = _filtered
            .where((p) => p.createdAt.month == m && p.createdAt.year == now.year)
            .fold(0.0, (s, p) => s + p.amount);
        result[label] = sum;
      }
    } else {
      for (int i = days - 1; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final label = '${day.day}/${day.month}';
        final sum = _filtered
            .where((p) =>
                p.createdAt.year == day.year &&
                p.createdAt.month == day.month &&
                p.createdAt.day == day.day)
            .fold(0.0, (s, p) => s + p.amount);
        result[label] = sum;
      }
    }
    return result;
  }

  String _monthLabel(int m) {
    const months = [
      'Jan', 'Fev', 'Mar', 'Avr', 'Mai', 'Jun',
      'Jul', 'Aou', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m - 1];
  }

  // Export CSV
  void _exportCsv() {
    final buf = StringBuffer();
    buf.writeln('Date,Utilisateur,Telephone,Type,Montant (USD),Reference');
    for (final p in _filtered) {
      final date =
          '${p.createdAt.day}/${p.createdAt.month}/${p.createdAt.year}';
      buf.writeln(
          '$date,"${p.userName}","${p.phoneNumber}","${p.productLabel}",${p.amount},"${p.transactionReference ?? ''}"');
    }
    final csv = buf.toString();

    // Sur web, afficher dans une dialog; sur mobile, copier dans le presse-papiers
    if (kIsWeb) {
      _showCsvDialog(csv);
    } else {
      _showCsvDialog(csv);
    }
  }

  void _showCsvDialog(String csv) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.download_outlined, color: AppTheme.accentColor),
            const SizedBox(width: 8),
            const Text('Export CSV',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(
            children: [
              const Text(
                'Copiez ce contenu dans un fichier .csv',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDDD)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      csv,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer',
                style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Finance & Revenus',
            style: TextStyle(color: Colors.white, fontFamily: 'Poppins')),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _buildPeriodFilter(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.accentColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _buildKpiCards(),
                    const SizedBox(height: 16),
                    _buildRevenueChart(),
                    const SizedBox(height: 16),
                    _buildChannelBreakdown(),
                    const SizedBox(height: 16),
                    _buildTransactionList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPeriodFilter() {
    final periods = [
      {'value': 'jour', 'label': 'Jour'},
      {'value': 'semaine', 'label': 'Semaine'},
      {'value': 'mois', 'label': 'Mois'},
      {'value': 'annee', 'label': 'Annee'},
    ];
    return Container(
      color: AppTheme.primaryColor,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          ...periods.map((p) => Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPeriod = p['value']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: _selectedPeriod == p['value']
                          ? const Color(0xFFFFA726)
                          : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        p['label']!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _selectedPeriod == p['value']
                              ? Colors.white
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildKpiCards() {
    return Column(
      children: [
        // Total revenu - carte principale
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF283593)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A237E).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Revenu Total',
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Poppins',
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${_totalRevenue.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 32,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_filtered.length} transaction(s) confirmee(s)',
                style: const TextStyle(
                  color: Colors.white60,
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Recharges',
                value: '\$${_rechargeRevenue.toStringAsFixed(2)}',
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFF1B5E20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: 'Boosts',
                value: '\$${_boostRevenue.toStringAsFixed(2)}',
                icon: Icons.rocket_launch_outlined,
                color: const Color(0xFFE65100),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRevenueChart() {
    final data = _buildChartData();
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVal = data.values.fold(0.0, (m, v) => v > m ? v : m);
    final entries = data.entries.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Evolution des revenus',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedPeriod == 'annee' ? 'Par mois' : 'Par jour',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: AppTheme.accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _BarChartPainter(entries: entries, maxVal: maxVal),
              child: Container(),
            ),
          ),
          const SizedBox(height: 8),
          // Labels X
          SizedBox(
            height: 20,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final w = constraints.maxWidth / entries.length;
                final showEvery =
                    entries.length > 10 ? (entries.length ~/ 5) : 1;
                return Stack(
                  children: List.generate(entries.length, (i) {
                    if (i % showEvery != 0) return const SizedBox.shrink();
                    return Positioned(
                      left: i * w,
                      width: w,
                      child: Center(
                        child: Text(
                          entries[i].key,
                          style: const TextStyle(
                            fontSize: 9,
                            fontFamily: 'Poppins',
                            color: AppTheme.textHint,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBreakdown() {
    final channels = [
      {
        'label': 'Recharges / Packs',
        'amount': _rechargeRevenue,
        'color': const Color(0xFF1B5E20),
        'icon': Icons.account_balance_wallet_outlined,
      },
      {
        'label': 'Boosts annonces',
        'amount': _boostRevenue,
        'color': const Color(0xFFE65100),
        'icon': Icons.rocket_launch_outlined,
      },
      {
        'label': 'Publicites (Ads)',
        'amount': _adsRevenue,
        'color': const Color(0xFF4A148C),
        'icon': Icons.campaign_outlined,
      },
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Repartition par canal',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...channels.map((c) {
            final amount = c['amount'] as double;
            final pct = _totalRevenue > 0 ? (amount / _totalRevenue) : 0.0;
            final color = c['color'] as Color;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(c['icon'] as IconData, color: color, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c['label'] as String,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '\$${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(pct * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: AppTheme.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: color.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    final items = _filtered.take(50).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Transactions recentes',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                TextButton.icon(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.download_outlined,
                      size: 16, color: AppTheme.accentColor),
                  label: const Text(
                    'CSV',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucune transaction pour cette periode',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: AppTheme.textHint,
                  fontSize: 13,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 56),
              itemBuilder: (_, i) {
                final p = items[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        AppTheme.successColor.withValues(alpha: 0.12),
                    child: const Icon(Icons.check,
                        color: AppTheme.successColor, size: 16),
                  ),
                  title: Text(
                    p.productLabel,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${p.userName.isEmpty ? p.phoneNumber : p.userName} • ${p.createdAt.day}/${p.createdAt.month}/${p.createdAt.year}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  trailing: Text(
                    '\$${p.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.successColor,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Painter pour le graphique en barres ──────────────────────────────────────

class _BarChartPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final double maxVal;

  _BarChartPainter({required this.entries, required this.maxVal});

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final barWidth = (size.width / entries.length) * 0.6;
    final spacing = (size.width / entries.length) * 0.4;
    final maxH = size.height - 4;

    for (int i = 0; i < entries.length; i++) {
      final val = entries[i].value;
      final h = maxVal > 0 ? (val / maxVal) * maxH : 0.0;
      final x = i * (size.width / entries.length) + spacing / 2;
      final y = size.height - h;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFA726),
            const Color(0xFFE65100).withValues(alpha: 0.7),
          ],
        ).createShader(Rect.fromLTWH(x, y, barWidth, h));

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barWidth, math.max(h, 2)),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.entries != entries || old.maxVal != maxVal;
}

// ── Widget KPI Card ──────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
