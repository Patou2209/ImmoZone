import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/data_service.dart';
import '../../providers/auth_provider.dart';
import 'dashboard/admin_dashboard_screen.dart';
import 'reception/admin_reception_screen.dart';
import 'properties/admin_properties_screen.dart';
import 'users/admin_users_screen.dart';
import 'settings/admin_settings_screen.dart';
import 'ads/admin_ads_screen.dart';
import 'financier/admin_financier_home_screen.dart';
import 'service_client/admin_service_client_home_screen.dart';
import 'marketing/admin_marketing_home_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentIndex = 0;
  int _pendingCount = 0;
  final _ds = DataService();

  // Rôle courant (lu depuis SharedPreferences)
  String get _currentRole => _ds.currentUserRole;

  bool get _isAdminFinancier => _currentRole == AppConstants.roleAdminFinancier;
  bool get _isAdminServiceClient => _currentRole == AppConstants.roleAdminServiceClient;
  bool get _isAdminMarketing => _currentRole == AppConstants.roleAdminMarketing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPendingCount();
      // Si on arrive ici sans SplashScreen (refresh direct sur /admin),
      // déclencher checkAuth() en arrière-plan.
      final auth = context.read<AuthProvider>();
      if (!auth.isLoggedIn) {
        auth.checkAuth();
      }
    });
  }

  Future<void> _loadPendingCount() async {
    if (_isAdminFinancier || _isAdminServiceClient || _isAdminMarketing) return; // pas besoin
    final pending = await _ds.getPendingProperties();
    if (mounted) setState(() => _pendingCount = pending.length);
  }

  // ── Admin Financier — écran unique ──────────────────────────────────────
  Widget _buildFinancierScaffold() {
    return const AdminFinancierHomeScreen();
  }

  // ── Admin Service Client — écran unique ─────────────────────────────────
  Widget _buildServiceClientScaffold() {
    return const AdminServiceClientHomeScreen();
  }

  // ── Admin Marketing — écran unique ──────────────────────────────────────
  Widget _buildMarketingScaffold() {
    return const AdminMarketingHomeScreen();
  }

  final List<Widget> _screens = const [
    AdminDashboardScreen(),
    AdminReceptionScreen(),
    AdminPropertiesScreen(),
    AdminUsersScreen(),
    AdminAdsScreen(),
    AdminSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Rôles spéciaux : écran dédié sans bottom nav
    if (_isAdminFinancier) return _buildFinancierScaffold();
    if (_isAdminServiceClient) return _buildServiceClientScaffold();
    if (_isAdminMarketing) return _buildMarketingScaffold();

    // Admin général : navigation complète
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          setState(() => _currentIndex = i);
          if (i == 1) _loadPendingCount();
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFFA726),
        unselectedItemColor: Colors.white60,
        selectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 10),
        unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Colors.white60),
        backgroundColor: AppTheme.primaryColor,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: _badgeIcon(Icons.inbox_outlined, _pendingCount),
            activeIcon: _badgeIcon(Icons.inbox_rounded, _pendingCount, active: true),
            label: 'Réception',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_work_outlined),
            activeIcon: Icon(Icons.home_work),
            label: 'Annonces',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Utilisateurs',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            activeIcon: Icon(Icons.campaign_rounded),
            label: 'Publicités',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }

  Widget _badgeIcon(IconData icon, int count, {bool active = false}) {
    if (count <= 0) return Icon(icon);
    final label = count > 99 ? '99+' : '$count';
    // Badge bien visible : fond rouge vif, texte blanc gras, taille lisible
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -10, top: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4, offset: const Offset(0, 1))],
            ),
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w900, fontFamily: 'Poppins',
                    height: 1.1),
                textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
