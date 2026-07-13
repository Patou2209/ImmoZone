import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../theme/app_theme.dart';
import 'immozone_nav_helper.dart';

/// Callback invoked when the user selects a menu item from the avatar popup.
/// The host screen is responsible for navigating to the right screen.
typedef AvatarMenuCallback = void Function(String value);

/// Shared ImmoZone AppBar — white background, blue back button, centered title,
/// avatar with orange border → popup (dashboard / recharger / réglages / logout).
///
/// Pass [onAvatarMenu] to handle navigation from the popup — the widget gives
/// you the selected value: 'dashboard', 'recharger', 'reglages', 'logout'.
///
/// If you don't pass [onAvatarMenu], a sensible default is used (go('/') on logout,
/// pop on others — works for most inner screens).
class ImmoZoneAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final AvatarMenuCallback? onAvatarMenu;
  final List<Widget>? extraActions;

  const ImmoZoneAppBar({
    super.key,
    required this.title,
    this.onAvatarMenu,
    this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.textPrimary,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: AppTheme.primaryColor),
          title: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: AppTheme.textPrimary,
            ),
          ),
          actions: [
            if (extraActions != null) ...extraActions!,
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Builder(builder: (ctx) {
                final auth = ctx.watch<AuthProvider>();
                if (!auth.isLoggedIn) return const SizedBox.shrink();
                final user = auth.currentUser;
                return _AvatarPopupMenu(
                  user: user,
                  onSelected: (val) async {
                    if (onAvatarMenu != null) {
                      onAvatarMenu!(val);
                    } else {
                      await handleImmoZoneAvatarNav(ctx, val);
                    }
                  },
                );
              }),
            ),
          ],
        ),
        Container(height: 1, color: const Color(0xFFE4E8F0)),
      ],
    );
  }
}

// ── Avatar circle + popup ─────────────────────────────────────────────────────
class _AvatarPopupMenu extends StatelessWidget {
  final UserModel? user;
  final void Function(String) onSelected;

  const _AvatarPopupMenu({required this.user, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 8,
      onSelected: onSelected,
      itemBuilder: (_) => [
        _item('dashboard', Icons.dashboard_rounded,
            'Mon tableau de bord', AppTheme.primaryColor),
        _item('recharger', Icons.add_circle_outline_rounded,
            'Recharger', AppTheme.accentColor),
        _item('reglages', Icons.settings_rounded,
            'Réglages', Colors.blueGrey),
        const PopupMenuDivider(height: 1),
        _itemRed('logout', Icons.logout_rounded, 'Déconnexion'),
      ],
      child: _avatar(),
    );
  }

  Widget _avatar() {
    final data = user?.avatar;
    Widget inner;
    if (data != null && data.isNotEmpty) {
      try {
        final b64 = data.contains(',') ? data.split(',').last : data;
        final bytes = base64Decode(b64);
        inner = Image.memory(bytes, width: 36, height: 36, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initials());
      } catch (_) {
        inner = _initials();
      }
    } else {
      inner = _initials();
    }
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.accentColor, width: 2.0),
      ),
      child: ClipOval(child: Container(
        color: const Color(0xFFD8E0EE),
        child: inner,
      )),
    );
  }

  Widget _initials() {
    final name = user?.name ?? '';
    final letters = name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Center(child: Text(letters,
        style: const TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w700, fontSize: 13,
            color: AppTheme.textPrimary)));
  }

  PopupMenuItem<String> _item(
      String val, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: val,
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }

  PopupMenuItem<String> _itemRed(String val, IconData icon, String label) {
    return PopupMenuItem(
      value: val,
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: Colors.red),
        ),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w600, fontSize: 13, color: Colors.red)),
      ]),
    );
  }
}
