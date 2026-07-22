import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../screens/public/home/public_home_screen.dart';
import '../../screens/public/packs/public_packs_screen.dart';
import '../../screens/public/parrainage/user_parrainage_screen.dart';

/// Handles avatar popup menu navigation from any screen.
/// Values: 'dashboard' | 'recharger' | 'parrainage' | 'reglages' | 'logout'
Future<void> handleImmoZoneAvatarNav(BuildContext context, String val) async {
  switch (val) {
    case 'dashboard':
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const UserDashboardScreen()));
      break;
    case 'recharger':
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const PublicPacksScreen()));
      break;
    case 'parrainage':
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const UserParrainageScreen()));
      break;
    case 'reglages':
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const UserReglagesScreen()));
      break;
    case 'logout':
      final authProv = context.read<AuthProvider>();
      await authProv.logout();
      if (context.mounted) context.go('/');
      break;
  }
}
