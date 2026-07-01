import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/payment_model.dart';
import '../../../services/data_service.dart';
import '../../../services/csv_export_service.dart';

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

  // ── ARPA : revenu moyen par annonceur unique ──────────────────────────────
  int get _uniqueAnnonceurCount {
    final ids = _filtered.map((p) => p.userId).toSet();
    return ids.isEmpty ? 1 : ids.length;
  }

  double get _arpaRevenue {
    if (_uniqueAnnonceurCount == 0) return 0.0;
    return _totalRevenue / _uniqueAnnonceurCount;
  }

  // ── Données cumulées pour la courbe ──────────────────────────────────────
  List<MapEntry<String, double>> _buildCumulativeData() {
    final periodic = _buildChartData();
    final entries = periodic.entries.toList();
    double cumul = 0.0;
    return entries.map((e) {
      cumul += e.value;
      return MapEntry(e.key, cumul);
    }).toList();
  }

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

  // ── Export CSV — transactions financières ──────────────────────────────────
  Future<void> _exportCsv() async {
    if (_filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucune transaction à exporter',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.errorColor,
      ));
      return;
    }

    final buf = StringBuffer();

    // En-tête
    buf.writeln('Export Finance & Revenus ImmoZone');
    buf.writeln('Période,${_selectedPeriod.toUpperCase()}');
    buf.writeln('Total Revenus (\$),${CsvExportService.fmtAmount(_totalRevenue)}');
    buf.writeln('Recharges (\$),${CsvExportService.fmtAmount(_rechargeRevenue)}');
    buf.writeln('Boosts (\$),${CsvExportService.fmtAmount(_boostRevenue)}');
    buf.writeln('Publicités (\$),${CsvExportService.fmtAmount(_adsRevenue)}');
    buf.writeln('Généré le,${CsvExportService.fmtDateTime(DateTime.now())}');
    buf.writeln();

    // Détail transactions
    buf.writeln('Date/Heure,Utilisateur,Téléphone,Type,Montant (USD),Référence');
    for (final p in _filtered) {
      buf.writeln(
          '${CsvExportService.fmtDateTime(p.createdAt)},'
          '${CsvExportService.q(p.userName)},'
          '${CsvExportService.q(p.phoneNumber)},'
          '${CsvExportService.q(p.productLabel)},'
          '${CsvExportService.fmtAmount(p.amount)},'
          '${CsvExportService.q(p.transactionReference)}');
    }

    final csv = buf.toString();
    final fname = CsvExportService.fileName('finance_revenus');
    final path = await CsvExportService.export(csvContent: csv, fileName: fname);

    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('CSV exporté : $fname',
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erreur lors de l\'export',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.errorColor,
      ));
    }
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
        // ── Carte principale : Recette totale ────────────────────────────────
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
              Row(
                children: [
                  const Icon(Icons.monetization_on_outlined,
                      color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Recette Totale',
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Poppins',
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _selectedPeriod == 'annee' ? 'Annuel' :
                      _selectedPeriod == 'mois'  ? 'Mensuel' :
                      _selectedPeriod == 'semaine' ? 'Hebdo' : 'Journalier',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
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
                '${_filtered.length} transaction(s) confirmee(s) · ${_uniqueAnnonceurCount} annonceur(s)',
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
        // ── Ligne 1 : Recharges + Boosts ─────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Recharges / Packs',
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
        const SizedBox(height: 10),
        // ── Ligne 2 : ARPA + Publicités ──────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'ARPA',
                value: '\$${_arpaRevenue.toStringAsFixed(2)}',
                icon: Icons.person_outline_rounded,
                color: const Color(0xFF006064),
                subtitle: 'Revenu moyen / annonceur',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: 'Publicites (Ads)',
                value: '\$${_adsRevenue.toStringAsFixed(2)}',
                icon: Icons.campaign_outlined,
                color: const Color(0xFF4A148C),
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
    final cumulData = _buildCumulativeData();
    final maxCumul = cumulData.isEmpty ? 1.0 :
        cumulData.fold(0.0, (m, e) => e.value > m ? e.value : m);

    return Column(
      children: [
        // ── Graphique 1 : Recette périodique (barres) ────────────────────────
        Container(
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
                children: [
                  const Icon(Icons.bar_chart_rounded,
                      color: Color(0xFFFFA726), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Recette périodique',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
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
              const SizedBox(height: 4),
              Text(
                'Total période : \$${_totalRevenue.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 160,
                child: CustomPaint(
                  painter: _BarChartPainter(entries: entries, maxVal: maxVal),
                  child: Container(),
                ),
              ),
              const SizedBox(height: 8),
              _buildXLabels(entries),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Graphique 2 : Recette cumulée (courbe) ────────────────────────────
        Container(
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
                children: [
                  const Icon(Icons.show_chart_rounded,
                      color: Color(0xFF006064), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Recette cumulée',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  // ARPA badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF006064).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'ARPA \$${_arpaRevenue.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: Color(0xFF006064),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Cumul total : \$${cumulData.isEmpty ? '0.00' : cumulData.last.value.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 160,
                child: CustomPaint(
                  painter: _LineChartPainter(
                    entries: cumulData,
                    maxVal: maxCumul,
                    lineColor: const Color(0xFF006064),
                    fillColor: const Color(0xFF006064),
                  ),
                  child: Container(),
                ),
              ),
              const SizedBox(height: 8),
              _buildXLabels(cumulData),
            ],
          ),
        ),
      ],
    );
  }

  // ── Helper : labels axe X ─────────────────────────────────────────────────
  Widget _buildXLabels(List<MapEntry<String, double>> entries) {
    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          if (entries.isEmpty) return const SizedBox.shrink();
          final w = constraints.maxWidth / entries.length;
          final showEvery = entries.length > 10 ? (entries.length ~/ 5) : 1;
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
    );
  }

  Widget _buildChannelBreakdown() {
    // ── Données pour le donut ─────────────────────────────────────────────────
    final segments = [
      _DonutSegment(
        label: 'Abonnements',
        amount: _rechargeRevenue,
        color: const Color(0xFF1B5E20),
        icon: Icons.account_balance_wallet_outlined,
      ),
      _DonutSegment(
        label: 'Boosting',
        amount: _boostRevenue,
        color: const Color(0xFFE65100),
        icon: Icons.rocket_launch_outlined,
      ),
      _DonutSegment(
        label: 'Publicité',
        amount: _adsRevenue,
        color: const Color(0xFF4A148C),
        icon: Icons.campaign_outlined,
      ),
    ];
    final total = _totalRevenue;

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
          // ── Titre ──────────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.donut_large_rounded,
                  color: Color(0xFF4A148C), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Répartition du revenu',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Donut + Légende côte à côte ────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Donut chart
              SizedBox(
                width: 140,
                height: 140,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    segments: segments,
                    total: total,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: AppTheme.textHint,
                          ),
                        ),
                        Text(
                          '\$${total.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Légende
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: segments.map((s) {
                    final pct = total > 0 ? (s.amount / total * 100) : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.label,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${pct.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: s.color,
                                ),
                              ),
                              Text(
                                '\$${s.amount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
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

// ── Painter pour le graphique en barres ────────────────────────────────────────

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

// ── Painter : courbe de recette cumulée ──────────────────────────────────────────

class _LineChartPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final double maxVal;
  final Color lineColor;
  final Color fillColor;

  _LineChartPainter({
    required this.entries,
    required this.maxVal,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty || maxVal <= 0) return;
    final n = entries.length;
    final stepX = n <= 1 ? size.width : size.width / (n - 1);

    // Calcul des points
    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = i * stepX;
      final y = size.height - (entries[i].value / maxVal) * (size.height - 6);
      points.add(Offset(x, y));
    }

    // Zone de remplissage (fill under curve)
    final fillPath = Path();
    fillPath.moveTo(points.first.dx, size.height);
    fillPath.lineTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cp1 = Offset(prev.dx + stepX * 0.4, prev.dy);
      final cp2 = Offset(curr.dx - stepX * 0.4, curr.dy);
      fillPath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, curr.dx, curr.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            fillColor.withValues(alpha: 0.3),
            fillColor.withValues(alpha: 0.02),
          ]).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Ligne de la courbe
    final linePath = Path();
    linePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cp1 = Offset(prev.dx + stepX * 0.4, prev.dy);
      final cp2 = Offset(curr.dx - stepX * 0.4, curr.dy);
      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, curr.dx, curr.dy);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // Points sur la courbe
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    final dotBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final showEvery = n > 12 ? (n ~/ 6) : 1;
    for (int i = 0; i < points.length; i++) {
      if (i % showEvery != 0 && i != points.length - 1) continue;
      canvas.drawCircle(points[i], 5, dotBorder);
      canvas.drawCircle(points[i], 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.entries != entries || old.maxVal != maxVal;
}

// ── Modèle segment donut ─────────────────────────────────────────────────────────

class _DonutSegment {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _DonutSegment({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });
}

// ── Painter : graphique anneau (donut) ────────────────────────────────────────────

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  final double total;

  _DonutChartPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeW = radius * 0.38;

    if (total <= 0) {
      // Anneau vide
      final emptyPaint = Paint()
        ..color = const Color(0xFFEEEEEE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW;
      canvas.drawCircle(center, radius - strokeW / 2, emptyPaint);
      return;
    }

    double startAngle = -math.pi / 2; // démarre en haut

    for (int i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s.amount <= 0) continue;
      final sweep = (s.amount / total) * 2 * math.pi;
      const gap = 0.03; // petit espace entre les segments

      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeW / 2),
        startAngle + gap / 2,
        sweep - gap,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutChartPainter old) =>
      old.segments != segments || old.total != total;
}

// ── Widget KPI Card ──────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
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
                if (subtitle != null) ...([
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      color: AppTheme.textHint,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
