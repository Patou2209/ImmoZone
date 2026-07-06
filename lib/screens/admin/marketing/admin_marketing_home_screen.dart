import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/parrain_model.dart';
import '../../../models/platform_stats_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/data_service.dart';
import '../../../services/csv_export_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminMarketingHomeScreen
// 2 onglets :
//   0 — Statistiques plateforme (9 métriques + filtres géo/période + bar chart)
//   1 — Gestion Parrains (liste + création + stats 5 métriques)
// ─────────────────────────────────────────────────────────────────────────────

class AdminMarketingHomeScreen extends StatefulWidget {
  const AdminMarketingHomeScreen({super.key});

  @override
  State<AdminMarketingHomeScreen> createState() =>
      _AdminMarketingHomeScreenState();
}

class _AdminMarketingHomeScreenState extends State<AdminMarketingHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _ds = DataService();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Mktg & Commercial',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Déconnexion',
            onPressed: () async {
              final auth = Provider.of<AuthProvider>(context, listen: false);
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
              fontSize: 12),
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: 'Statistiques'),
            Tab(icon: Icon(Icons.group_add_rounded, size: 18), text: 'Parrains'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _StatsTab(ds: _ds),
          _ParrainsTab(ds: _ds),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 0 — Statistiques Plateforme
// ═════════════════════════════════════════════════════════════════════════════

class _StatsTab extends StatefulWidget {
  final DataService ds;
  const _StatsTab({required this.ds});

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  // ── Période ──────────────────────────────────────────────────────────────
  String _period = 'mois'; // jour | semaine | mois | annee | custom
  DateTimeRange? _custom;

  // ── Filtres géographiques ─────────────────────────────────────────────────
  String? _country;
  String? _province;
  String? _city;
  String? _commune;

  bool _loading = true;
  PlatformStats _stats = PlatformStats.empty();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  DateTimeRange get _range {
    final now = DateTime.now();
    switch (_period) {
      case 'jour':
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day), end: now);
      case 'semaine':
        return DateTimeRange(
            start: now.subtract(const Duration(days: 7)), end: now);
      case 'annee':
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case 'custom':
        return _custom ??
            DateTimeRange(
                start: DateTime(now.year, now.month, 1), end: now);
      default: // mois
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1), end: now);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final r = _range;
      final stats = await widget.ds.getPlatformStats(
        from: r.start,
        to: r.end,
        country: _country,
        province: _province,
        city: _city,
        commune: _commune,
      );
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: AppTheme.errorColor));
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: _custom,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primaryColor),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _period = 'custom';
      });
      _load();
    }
  }

  // Provinces selon pays sélectionné
  List<String> get _provinces {
    if (_country == null || _country!.isEmpty) return [];
    return AppConstants.getProvincesForCountry(_country!);
  }

  List<String> get _cities {
    if (_province == null || _province!.isEmpty) return [];
    return AppConstants.getCitiesForProvince(_country ?? 'Congo (RDC)', _province!);
  }

  List<String> get _communes {
    if (_city == null || _city!.isEmpty) return [];
    return AppConstants.getCommunesForCity(_city!);
  }

  // ── Export CSV — Statistiques plateforme ──────────────────────────────────
  Future<void> _exportStatsCsv() async {
    final r = _range;
    final buf = StringBuffer();

    // En-tête
    buf.writeln('Export Statistiques Plateforme ImmoZone');
    buf.writeln('Période,${CsvExportService.fmtDate(r.start)} → ${CsvExportService.fmtDate(r.end)}');
    if (_country != null) buf.writeln('Pays,${CsvExportService.q(_country)}');
    if (_province != null) buf.writeln('Province,${CsvExportService.q(_province)}');
    if (_city != null) buf.writeln('Ville,${CsvExportService.q(_city)}');
    if (_commune != null) buf.writeln('Commune,${CsvExportService.q(_commune)}');
    buf.writeln('Généré le,${CsvExportService.fmtDateTime(DateTime.now())}');
    buf.writeln();

    // KPIs
    buf.writeln('Indicateur,Valeur');
    buf.writeln('Total Dépôts (\$),${CsvExportService.fmtAmount(_stats.totalDeposits)}');
    buf.writeln('Crédits Consommés,${CsvExportService.fmtAmount(_stats.creditsConsumed)}');
    buf.writeln('Annonces Postées,${_stats.postedProperties}');
    buf.writeln('Annonces Expirées,${_stats.expiredProperties}');
    buf.writeln('Nouveaux Utilisateurs,${_stats.newUsersCount}');
    buf.writeln('Total Utilisateurs,${_stats.totalUsersCount}');
    buf.writeln('Utilisateurs Actifs,${_stats.activeUsersCount}');
    buf.writeln('Inactifs depuis 90j,${_stats.inactiveUsersCount}');
    buf.writeln();

    // Annonces clôturées par type
    if (_stats.closedByType.isNotEmpty) {
      buf.writeln('Annonces Clôturées par Type');
      buf.writeln('Type,Nombre');
      for (final entry in _stats.closedByType.entries) {
        buf.writeln('${CsvExportService.q(entry.key)},${entry.value}');
      }
      buf.writeln();
    }

    // Données graphique
    if (_stats.chartData.isNotEmpty) {
      buf.writeln('Évolution des Dépôts');
      buf.writeln('Date/Période,Montant (\$)');
      for (final entry in _stats.chartData.entries) {
        buf.writeln('${CsvExportService.q(entry.key)},${CsvExportService.fmtAmount(entry.value)}');
      }
    }

    final csv = buf.toString();
    final fname = CsvExportService.fileName('stats_plateforme');
    final path = await CsvExportService.export(csvContent: csv, fileName: fname);

    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('CSV exporté : $fname', style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erreur lors de l\'export', style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.errorColor,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentColor,
      child: ListView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
        children: [
          // ── Filtres période ──────────────────────────────────────────────
          _PeriodFilter(
            selected: _period,
            onChanged: (p) {
              setState(() {
                _period = p;
                if (p != 'custom') _custom = null;
              });
              if (p == 'custom') {
                _pickCustomRange();
              } else {
                _load();
              }
            },
            customRange: _custom,
          ),
          const SizedBox(height: 8),

          // ── Filtres géographiques ────────────────────────────────────────
          _GeoFilter(
            country: _country,
            province: _province,
            city: _city,
            commune: _commune,
            provinces: _provinces,
            cities: _cities,
            communes: _communes,
            onCountryChanged: (v) {
              setState(() {
                _country = v;
                _province = null;
                _city = null;
                _commune = null;
              });
              _load();
            },
            onProvinceChanged: (v) {
              setState(() {
                _province = v;
                _city = null;
                _commune = null;
              });
              _load();
            },
            onCityChanged: (v) {
              setState(() {
                _city = v;
                _commune = null;
              });
              _load();
            },
            onCommuneChanged: (v) {
              setState(() => _commune = v);
              _load();
            },
            onClear: () {
              setState(() {
                _country = null;
                _province = null;
                _city = null;
                _commune = null;
              });
              _load();
            },
          ),
          const SizedBox(height: 12),

          if (_loading)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            ))
          else ...[
            // ── Montant total dépôts (hero card) ─────────────────────────
            _HeroDepositCard(amount: _stats.totalDeposits),
            const SizedBox(height: 12),

            // ── Bar chart ─────────────────────────────────────────────────
            _RevenueBarChart(data: _stats.chartData),
            const SizedBox(height: 12),

            // ── Grille 9 KPI ──────────────────────────────────────────────
            _KpiGrid(stats: _stats),
            const SizedBox(height: 12),

            // ── Annonces clôturées par type ───────────────────────────────
            if (_stats.closedByType.isNotEmpty) ...[
              _ClosedByTypeCard(data: _stats.closedByType),
              const SizedBox(height: 12),
            ],

            // ── Bouton Export CSV ─────────────────────────────────────────
            _ExportCsvButton(onPressed: _exportStatsCsv, label: 'Exporter Statistiques CSV'),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 1 — Gestion Parrains
// ═════════════════════════════════════════════════════════════════════════════

class _ParrainsTab extends StatefulWidget {
  final DataService ds;
  const _ParrainsTab({required this.ds});

  @override
  State<_ParrainsTab> createState() => _ParrainsTabState();
}

class _ParrainsTabState extends State<_ParrainsTab> {
  List<ParrainModel> _parrains = [];
  bool _loading = true;

  // Période pour les stats parrains
  String _period = 'mois';
  DateTimeRange? _custom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  DateTimeRange get _range {
    final now = DateTime.now();
    switch (_period) {
      case 'jour':
        return DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
      case 'semaine':
        return DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
      case 'annee':
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case 'custom':
        return _custom ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      default:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final list = await widget.ds.getParrains();
    if (!mounted) return;
    setState(() {
      _parrains = list;
      _loading = false;
    });
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.group_add_rounded, color: AppTheme.primaryColor),
          SizedBox(width: 10),
          Text('Nouveau parrain',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Entrez le nom du parrain pour générer son code unique.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          TextFormField(
            controller: nameCtrl,
            autofocus: true,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ex : Patrick Okafor',
              hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint),
              prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primaryColor, size: 18),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFDDE3F0))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5)),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Créer',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final parrain = await widget.ds.createParrain(name: result);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Parrain "${parrain.name}" créé ! Code : ${parrain.code}',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    }
  }

  Future<void> _deleteParrain(ParrainModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Supprimer le parrain',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('Supprimer "${p.name}" (${p.code}) ?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Supprimer',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.ds.deleteParrain(p.id);
      await _load();
    }
  }

  Future<void> _showParrainStats(ParrainModel parrain) async {
    final r = _range;
    ParrainStats? stats;
    try {
      stats = await widget.ds.getParrainStats(
          sponsorCode: parrain.code, from: r.start, to: r.end);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: AppTheme.errorColor));
      return;
    }
    if (!mounted) return;
    if (stats == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.people_rounded, color: AppTheme.primaryColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(parrain.name,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(parrain.code,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor)),
              ),
            ]),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _statRow('Comptes associés (période)', '${stats!.associatedCount}', Icons.person_add_rounded, const Color(0xFF1565C0)),
          _statRow('Comptes actifs (période)', '${stats.activeCount}', Icons.check_circle_rounded, AppTheme.successColor),
          _statRow('Dépôts opérés (\$)', '\$${stats.depositsUsd.toStringAsFixed(2)}', Icons.attach_money_rounded, const Color(0xFF2E7D32)),
          _statRow('Annonces réalisées', '${stats.propertiesCount}', Icons.home_rounded, const Color(0xFFE65100)),
          _statRow('Inactifs depuis 90j', '${stats.inactiveCount}', Icons.timer_off_rounded, AppTheme.errorColor),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer',
                  style: TextStyle(fontFamily: 'Poppins', color: AppTheme.primaryColor))),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: AppTheme.textPrimary))),
        Text(value,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color)),
      ]),
    );
  }

  // ── Export CSV — liste des parrains ────────────────────────────────────────
  Future<void> _exportParrainsCsv() async {
    if (_parrains.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun parrain à exporter', style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.errorColor,
      ));
      return;
    }

    final buf = StringBuffer();
    buf.writeln('Export Parrains ImmoZone');
    buf.writeln('Généré le,${CsvExportService.fmtDateTime(DateTime.now())}');
    buf.writeln();
    buf.writeln('Nom,Code,Date Création,Actif');
    for (final p in _parrains) {
      buf.writeln(
          '${CsvExportService.q(p.name)},${CsvExportService.q(p.code)},'
          '${CsvExportService.fmtDate(p.createdAt)},${p.isActive ? "Oui" : "Non"}');
    }

    final csv = buf.toString();
    final fname = CsvExportService.fileName('parrains');
    final path = await CsvExportService.export(csvContent: csv, fileName: fname);

    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('CSV exporté : $fname', style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erreur lors de l\'export', style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.errorColor,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final fabBottom = 16.0 + bottomInset;

    return Stack(children: [
      Column(children: [
        // ── Filtre période + bouton export ─────────────────────────────────
        Container(
          color: AppTheme.primaryColor,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Expanded(
              child: _PeriodFilter(
                selected: _period,
                onChanged: (p) => setState(() => _period = p),
                customRange: _custom,
                compact: true,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Exporter CSV',
              child: Material(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _parrains.isEmpty ? null : _exportParrainsCsv,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(Icons.download_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ]),
        ),

        // ── Liste parrains ─────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accentColor))
              : _parrains.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.accentColor,
                      child: ListView.separated(
                        // extra bottom padding = FAB height (56) + FAB bottom offset + inset
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 72 + fabBottom),
                        itemCount: _parrains.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 56),
                        itemBuilder: (_, i) => _ParrainTile(
                          parrain: _parrains[i],
                          onStats: () => _showParrainStats(_parrains[i]),
                          onDelete: () => _deleteParrain(_parrains[i]),
                        ),
                      ),
                    ),
        ),
      ]),

      // ── FAB overlay — Nouveau parrain (respects system nav bar) ──────────
      Positioned(
        right: 16,
        bottom: fabBottom,
        child: FloatingActionButton.extended(
          heroTag: 'fab_parrain',
          onPressed: _showCreateDialog,
          backgroundColor: AppTheme.primaryColor,
          icon: const Icon(Icons.person_add_rounded, color: Colors.white),
          label: const Text('Nouveau parrain',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
      ),
    ]);
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.group_outlined,
              size: 64, color: AppTheme.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('Aucun parrain créé',
              style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
            label: const Text('Créer un parrain',
                style: TextStyle(fontFamily: 'Poppins')),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ParrainTile
// ─────────────────────────────────────────────────────────────────────────────
class _ParrainTile extends StatelessWidget {
  final ParrainModel parrain;
  final VoidCallback onStats;
  final VoidCallback onDelete;

  const _ParrainTile({
    required this.parrain,
    required this.onStats,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person_rounded,
            color: AppTheme.primaryColor, size: 22),
      ),
      title: Text(parrain.name,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.textPrimary)),
      subtitle: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Text(parrain.code,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor)),
        ),
        const SizedBox(width: 8),
        Text(
            '${parrain.createdAt.day.toString().padLeft(2, '0')}/'
            '${parrain.createdAt.month.toString().padLeft(2, '0')}/'
            '${parrain.createdAt.year}',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: AppTheme.textHint)),
      ]),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
        onSelected: (v) {
          if (v == 'stats') onStats();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
              value: 'stats',
              child: Row(children: [
                Icon(Icons.bar_chart_rounded, size: 18, color: AppTheme.accentColor),
                SizedBox(width: 10),
                Text('Voir statistiques',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              ])),
          const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                SizedBox(width: 10),
                Text('Supprimer',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: AppTheme.errorColor)),
              ])),
        ],
      ),
      onTap: onStats,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PeriodFilter widget
// ─────────────────────────────────────────────────────────────────────────────
class _PeriodFilter extends StatelessWidget {
  final String selected;
  final void Function(String) onChanged;
  final DateTimeRange? customRange;
  final bool compact;

  const _PeriodFilter({
    required this.selected,
    required this.onChanged,
    this.customRange,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final periods = [
      {'value': 'jour', 'label': 'Jour'},
      {'value': 'semaine', 'label': '7j'},
      {'value': 'mois', 'label': 'Mois'},
      {'value': 'annee', 'label': 'Année'},
      {'value': 'custom', 'label': 'Range'},
    ];

    return Row(
      children: periods.map((p) {
        final isActive = selected == p['value'];
        final label = p['value'] == 'custom' && customRange != null
            ? '${customRange!.start.day}/${customRange!.start.month}→${customRange!.end.day}/${customRange!.end.month}'
            : p['label']!;
        return Expanded(
          child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
            onTap: () => onChanged(p['value']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 4),
              padding: EdgeInsets.symmetric(vertical: compact ? 5 : 7),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFFFA726)
                    : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : Colors.white70)),
              ),
            ),
          )),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GeoFilter widget
// ─────────────────────────────────────────────────────────────────────────────
class _GeoFilter extends StatelessWidget {
  final String? country;
  final String? province;
  final String? city;
  final String? commune;
  final List<String> provinces;
  final List<String> cities;
  final List<String> communes;
  final void Function(String?) onCountryChanged;
  final void Function(String?) onProvinceChanged;
  final void Function(String?) onCityChanged;
  final void Function(String?) onCommuneChanged;
  final VoidCallback onClear;

  const _GeoFilter({
    required this.country,
    required this.province,
    required this.city,
    required this.commune,
    required this.provinces,
    required this.cities,
    required this.communes,
    required this.onCountryChanged,
    required this.onProvinceChanged,
    required this.onCityChanged,
    required this.onCommuneChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilter = country != null || province != null || city != null || commune != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.filter_list_rounded,
              size: 16, color: AppTheme.primaryColor),
          const SizedBox(width: 6),
          const Text('Filtre géographique',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const Spacer(),
          if (hasFilter)
            MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Effacer',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: AppTheme.errorColor,
                        fontWeight: FontWeight.w600)),
              ),
            )),
        ]),
        const SizedBox(height: 8),
        // Ligne 1 : Pays + Province
        Row(children: [
          // Pays
          Expanded(
              child: _DropdownGeo<String>(
            value: country,
            hint: 'Pays',
            items: AppConstants.filterCountries,
            onChanged: onCountryChanged,
          )),
          const SizedBox(width: 8),
          // Province
          Expanded(
              child: _DropdownGeo<String>(
            value: province,
            hint: 'Province',
            items: provinces,
            onChanged: provinces.isEmpty ? null : onProvinceChanged,
          )),
        ]),
        const SizedBox(height: 8),
        // Ligne 2 : Ville + Commune
        Row(children: [
          // Ville
          Expanded(
              child: _DropdownGeo<String>(
            value: city,
            hint: 'Ville',
            items: cities,
            onChanged: cities.isEmpty ? null : onCityChanged,
          )),
          const SizedBox(width: 8),
          // Commune
          Expanded(
              child: _DropdownGeo<String>(
            value: commune,
            hint: 'Commune',
            items: communes,
            onChanged: communes.isEmpty ? null : onCommuneChanged,
          )),
        ]),
      ]),
    );
  }
}

class _DropdownGeo<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<String> items;
  final void Function(String?)? onChanged;

  const _DropdownGeo({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDDE3F0)),
        borderRadius: BorderRadius.circular(8),
        color: onChanged == null ? Colors.grey.shade50 : Colors.white,
      ),
      child: DropdownButton<String>(
        value: value as String?,
        hint: Text(hint,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 10, color: AppTheme.textHint)),
        isExpanded: true,
        underline: const SizedBox(),
        style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 10, color: AppTheme.textPrimary),
        onChanged: onChanged,
        items: [
          DropdownMenuItem<String>(
              value: null,
              child: Text(hint,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: AppTheme.textHint))),
          ...items.map((s) => DropdownMenuItem<String>(
              value: s,
              child: Text(s,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 10),
                  overflow: TextOverflow.ellipsis))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HeroDepositCard
// ─────────────────────────────────────────────────────────────────────────────
class _HeroDepositCard extends StatelessWidget {
  final double amount;
  const _HeroDepositCard({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0A3A8F), Color(0xFF1A4FAF)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0A3A8F).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Montant Total Dépôts',
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 4),
        Text('\$${amount.toStringAsFixed(2)}',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 32,
                color: Colors.white)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RevenueBarChart
// ─────────────────────────────────────────────────────────────────────────────
class _RevenueBarChart extends StatelessWidget {
  final Map<String, double> data;
  const _RevenueBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
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
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Évolution des dépôts',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: CustomPaint(
            painter: _BarPainter(entries: entries, maxVal: maxVal),
            child: Container(),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 18,
          child: LayoutBuilder(builder: (ctx, constraints) {
            final w = constraints.maxWidth / entries.length;
            final showEvery = entries.length > 10 ? (entries.length ~/ 5) : 1;
            return Stack(
              children: List.generate(entries.length, (i) {
                if (i % showEvery != 0) return const SizedBox.shrink();
                return Positioned(
                  left: i * w,
                  width: w,
                  child: Center(
                    child: Text(entries[i].key,
                        style: const TextStyle(
                            fontSize: 8,
                            fontFamily: 'Poppins',
                            color: AppTheme.textHint)),
                  ),
                );
              }),
            );
          }),
        ),
      ]),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final double maxVal;

  _BarPainter({required this.entries, required this.maxVal});

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final barW = (size.width / entries.length) * 0.6;
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
            const Color(0xFFE65100).withValues(alpha: 0.7)
          ],
        ).createShader(Rect.fromLTWH(x, y, barW, h));

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barW, math.max(h, 2)),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.entries != entries || old.maxVal != maxVal;
}

// ─────────────────────────────────────────────────────────────────────────────
// _KpiGrid — 9 statistiques en grille
// ─────────────────────────────────────────────────────────────────────────────
class _KpiGrid extends StatelessWidget {
  final PlatformStats stats;
  const _KpiGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final kpis = [
      _KpiDef('Dépôts totaux', '\$${stats.totalDeposits.toStringAsFixed(2)}',
          Icons.account_balance_wallet_rounded, const Color(0xFF1B5E20)),
      _KpiDef('Crédits consommés', '${stats.creditsConsumed.toInt()}',
          Icons.toll_rounded, const Color(0xFF0D47A1)),
      _KpiDef('Annonces postées', '${stats.postedProperties}',
          Icons.home_rounded, const Color(0xFF4A148C)),
      _KpiDef('Annonces expirées', '${stats.expiredProperties}',
          Icons.timer_off_rounded, const Color(0xFFBF360C)),
      _KpiDef('Nouveaux utilisateurs', '${stats.newUsersCount}',
          Icons.person_add_rounded, const Color(0xFF00695C)),
      _KpiDef('Total utilisateurs', '${stats.totalUsersCount}',
          Icons.people_rounded, const Color(0xFF37474F)),
      _KpiDef('Utilisateurs actifs', '${stats.activeUsersCount}',
          Icons.check_circle_rounded, AppTheme.successColor),
      _KpiDef('Inactifs (90j)', '${stats.inactiveUsersCount}',
          Icons.hourglass_empty_rounded, const Color(0xFFAD1457)),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: kpis.length,
      itemBuilder: (_, i) => _KpiCard(kpi: kpis[i]),
    );
  }
}

class _KpiDef {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiDef(this.label, this.value, this.icon, this.color);
}

class _KpiCard extends StatelessWidget {
  final _KpiDef kpi;
  const _KpiCard({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kpi.color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: kpi.color.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: kpi.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(kpi.icon, color: kpi.color, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(kpi.value,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: kpi.color)),
              Text(kpi.label,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      color: AppTheme.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ClosedByTypeCard — annonces clôturées par catégorie
// ─────────────────────────────────────────────────────────────────────────────
class _ClosedByTypeCard extends StatelessWidget {
  final Map<String, int> data;
  const _ClosedByTypeCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0, (s, v) => s + v);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Annonces clôturées par catégorie',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        ...data.entries.map((e) {
          final pct = total > 0 ? e.value / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text(e.key,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: AppTheme.textPrimary))),
                Text('${e.value}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor)),
                const SizedBox(width: 6),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: AppTheme.textHint)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  minHeight: 5,
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _ExportCsvButton — bouton réutilisable d'export CSV (pleine largeur)
// ─────────────────────────────────────────────────────────────────────────────
class _ExportCsvButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const _ExportCsvButton({required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.download_rounded, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryColor,
          side: const BorderSide(color: AppTheme.primaryColor),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
