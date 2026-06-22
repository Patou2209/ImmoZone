import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/data_service.dart';
import 'dashboard/admin_dashboard_screen.dart';
import 'reception/admin_reception_screen.dart';
import 'properties/admin_properties_screen.dart';
import 'users/admin_users_screen.dart';
import 'settings/admin_settings_screen.dart';
import 'ads/admin_ads_screen.dart';
import 'financier/admin_financier_home_screen.dart';
import 'service_client/admin_service_client_home_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPendingCount());
  }

  Future<void> _loadPendingCount() async {
    if (_isAdminFinancier || _isAdminServiceClient) return; // pas besoin
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -6, top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle),
              child: Text(count > 99 ? '99+' : '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 8,
                      fontWeight: FontWeight.w800, fontFamily: 'Poppins')),
            ),
          ),
      ],
    );
  }
}
