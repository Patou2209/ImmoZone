import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/immozone_app_bar.dart';
import '../../../core/widgets/immozone_nav_helper.dart';
import '../../../models/user_model.dart';
import '../../../models/payment_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/data_service.dart';

// ─── Données combinées filleul + première recharge ──────────────────────────
class _FilleulInfo {
  final UserModel user;
  final PaymentModel? firstRecharge; // null si pas encore rechargé

  const _FilleulInfo({required this.user, this.firstRecharge});
}

class UserParrainageScreen extends StatefulWidget {
  const UserParrainageScreen({super.key});

  @override
  State<UserParrainageScreen> createState() => _UserParrainageScreenState();
}

class _UserParrainageScreenState extends State<UserParrainageScreen> {
  final DataService _ds = DataService();

  bool _loading = true;
  String _myCode = '';
  int _totalCredits = 0;
  int _monthCredits = 0;
  List<_FilleulInfo> _filleuls = [];

  // Filtre mois
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    // S'assurer que l'utilisateur a son propre code parrain
    final code = await _ds.ensureUserReferralCode(user);
    // Si le code vient d'être créé et différent de celui en mémoire, mettre à jour
    if (user.myReferralCode != code) {
      auth.updateCurrentUserLocally(user.copyWith(myReferralCode: code));
    }

    // Crédits totaux + crédits du mois sélectionné
    final total = await _ds.getUserParrainageCreditsTotal(user.id);
    final monthCredits = await _ds.getUserParrainageCreditsByMonth(
        user.id, _selectedYear, _selectedMonth);

    // Filleuls
    final filleulUsers = await _ds.getUserFilleuls(code);
    final List<_FilleulInfo> infos = [];
    for (final f in filleulUsers) {
      final payments = await _ds.getFilleulFirstRecharge(f.id);
      infos.add(_FilleulInfo(
        user: f,
        firstRecharge: payments.isNotEmpty ? payments.first : null,
      ));
    }

    if (mounted) {
      setState(() {
        _myCode = code;
        _totalCredits = total;
        _monthCredits = monthCredits;
        _filleuls = infos;
        _loading = false;
      });
    }
  }

  Future<void> _reloadMonth() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null || _myCode.isEmpty) return;
    final mc = await _ds.getUserParrainageCreditsByMonth(
        user.id, _selectedYear, _selectedMonth);
    if (mounted) setState(() => _monthCredits = mc);
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _myCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Code copié dans le presse-papier !',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _monthName(int m) {
    const months = [
      '', 'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
    ];
    return months[m];
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: ImmoZoneAppBar(
        title: 'Mes Parrainages',
        onAvatarMenu: (val) => handleImmoZoneAvatarNav(context, val),
        extraActions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryColor),
            tooltip: 'Actualiser',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.accentColor,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
                children: [
                  // ── 1. Mon code parrain ─────────────────────────────────
                  _buildCodeCard(),
                  const SizedBox(height: 16),

                  // ── 2. Stats crédits ────────────────────────────────────
                  _buildStatsRow(),
                  const SizedBox(height: 16),

                  // ── 3. Filtre mensuel ───────────────────────────────────
                  _buildMonthFilter(),
                  const SizedBox(height: 20),

                  // ── 4. Comment ça marche ────────────────────────────────
                  _buildHowItWorks(),
                  const SizedBox(height: 20),

                  // ── 5. Liste des filleuls ───────────────────────────────
                  _buildFilleulHeader(),
                  const SizedBox(height: 10),
                  if (_filleuls.isEmpty)
                    _buildEmptyFilleuls()
                  else
                    ..._filleuls.map((f) => _buildFilleulCard(f)),
                ],
              ),
            ),
    );
  }

  // ─── CARTE CODE PARRAIN ───────────────────────────────────────────────────
  Widget _buildCodeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.people_alt_rounded,
                    color: AppTheme.primaryColor, size: 22),
              ),
              const SizedBox(width: 10),
              const Text(
                'Mon code parrain',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    SizedBox(width: 4),
                    Text('Parrain actif',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Code affiché
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _myCode,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2.5),
                ),
                GestureDetector(
                  onTap: _copyCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Copier',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Partagez ce code avec vos contacts.\nQuand ils s\'inscrivent avec ce code et font leur première recharge, vous recevez le même nombre de crédits !',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.5),
          ),
        ],
      ),
    );
  }

  // ─── STATS CRÉDITS (total + mois) ─────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.toll_rounded,
            label: 'Crédits totaux gagnés',
            value: '$_totalCredits',
            color: AppTheme.successColor,
            bg: const Color(0xFFE8F5E9),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            icon: Icons.people_alt_rounded,
            label: 'Filleuls inscrits',
            value: '${_filleuls.length}',
            color: AppTheme.primaryColor,
            bg: const Color(0xFFE8EAF6),
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  // ─── FILTRE MENSUEL ────────────────────────────────────────────────────────
  Widget _buildMonthFilter() {
    final now = DateTime.now();
    // Générer les 12 derniers mois
    final List<DateTime> months = List.generate(12, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return DateTime(d.year, d.month, 1);
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded,
                  color: AppTheme.primaryColor, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Crédits du mois',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Sélecteur mois
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: months.length,
              itemBuilder: (_, i) {
                final m = months[i];
                final selected =
                    m.year == _selectedYear && m.month == _selectedMonth;
                return GestureDetector(
                  onTap: () async {
                    setState(() {
                      _selectedYear = m.year;
                      _selectedMonth = m.month;
                    });
                    await _reloadMonth();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primaryColor
                          : AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primaryColor
                            : AppTheme.dividerColor,
                      ),
                    ),
                    child: Text(
                      '${_monthName(m.month)} ${m.year}',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : AppTheme.textSecondary),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          // Résultat mois
          Row(
            children: [
              const Icon(Icons.toll_rounded,
                  color: AppTheme.accentColor, size: 16),
              const SizedBox(width: 6),
              Text(
                '$_monthCredits crédit${_monthCredits != 1 ? 's' : ''} reçu${_monthCredits != 1 ? 's' : ''} en ${_monthName(_selectedMonth)} $_selectedYear',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── COMMENT ÇA MARCHE ────────────────────────────────────────────────────
  Widget _buildHowItWorks() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC02).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.warningColor, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Comment ça marche ?',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.warningColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _howStep('1', 'Partagez votre code parrain avec vos contacts.'),
          _howStep('2',
              'Votre contact s\'inscrit sur ImmoZone et saisit votre code.'),
          _howStep('3',
              'Dès sa première recharge, vous recevez automatiquement le même nombre de crédits.'),
          _howStep('4',
              'La commission ne se fait qu\'une seule fois par filleul (première recharge uniquement).'),
        ],
      ),
    );
  }

  Widget _howStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: const BoxDecoration(
              color: AppTheme.warningColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ─── EN-TÊTE LISTE FILLEULS ───────────────────────────────────────────────
  Widget _buildFilleulHeader() {
    return Row(
      children: [
        const Icon(Icons.people_rounded, color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 8),
        Text(
          'Mes filleuls (${_filleuls.length})',
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppTheme.textPrimary),
        ),
      ],
    );
  }

  // ─── ÉTAT VIDE ────────────────────────────────────────────────────────────
  Widget _buildEmptyFilleuls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(Icons.group_add_outlined,
              size: 54, color: AppTheme.textHint.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          const Text(
            'Aucun filleul pour l\'instant',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Partagez votre code parrain\npour commencer à gagner des crédits !',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }

  // ─── CARTE FILLEUL ────────────────────────────────────────────────────────
  Widget _buildFilleulCard(_FilleulInfo info) {
    final user = info.user;
    final recharge = info.firstRecharge;
    final hasRecharged = recharge != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasRecharged
              ? AppTheme.successColor.withValues(alpha: 0.4)
              : AppTheme.dividerColor,
          width: hasRecharged ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          // Avatar initiales
          CircleAvatar(
            radius: 22,
            backgroundColor: hasRecharged
                ? AppTheme.successColor.withValues(alpha: 0.15)
                : AppTheme.primaryColor.withValues(alpha: 0.1),
            child: Text(
              user.initials,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: hasRecharged
                      ? AppTheme.successColor
                      : AppTheme.primaryColor),
            ),
          ),
          const SizedBox(width: 12),
          // Infos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nom
                Text(
                  user.name,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                // Date inscription
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 11, color: AppTheme.textHint),
                    const SizedBox(width: 4),
                    Text(
                      'Inscrit le ${_formatDate(user.createdAt)}',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: AppTheme.textHint),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // Statut recharge
                if (hasRecharged) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.successColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 11, color: AppTheme.successColor),
                            const SizedBox(width: 4),
                            Text(
                              '${recharge.creditsQty} crédit${recharge.creditsQty != 1 ? 's' : ''} rechargé${recharge.creditsQty != 1 ? 's' : ''}',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.successColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(recharge.confirmedAt ?? recharge.createdAt),
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10.5,
                            color: AppTheme.textHint),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hourglass_empty_rounded,
                            size: 11, color: AppTheme.warningColor),
                        SizedBox(width: 4),
                        Text(
                          'Pas encore rechargé',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.warningColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Crédits commission à droite (si rechargé)
          if (hasRecharged)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+${recharge.creditsQty}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'crédits',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: AppTheme.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
