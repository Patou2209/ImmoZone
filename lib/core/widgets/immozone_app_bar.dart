import 'dart:convert';
import 'package:flutter/material.dart';
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

  /// Rafraîchissement de la page : si fourni, un bouton ↻ apparaît dans
  /// l'AppBar (avant l'avatar). À brancher sur le rechargement des données
  /// de l'écran hôte. Laisser null pour masquer (ex: page d'accueil, paiements).
  final Future<void> Function()? onRefresh;

  const ImmoZoneAppBar({
    super.key,
    required this.title,
    this.onAvatarMenu,
    this.extraActions,
    this.onRefresh,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    // ── Leading : bouton retour + bouton refresh, tous deux à GAUCHE ──────
    final List<Widget> leadingChildren = [
      if (canPop) const BackButton(color: AppTheme.primaryColor),
      if (onRefresh != null) _RefreshButton(onRefresh: onRefresh!),
    ];
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
          automaticallyImplyLeading: false,
          leadingWidth: leadingChildren.length * 48.0 + 4,
          leading: leadingChildren.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: leadingChildren),
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

// ── Bouton Rafraîchir (spinner pendant le rechargement) ──────────────────────
class _RefreshButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  const _RefreshButton({required this.onRefresh});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _refreshing = false;

  Future<void> _handleTap() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Rafraîchir',
      onPressed: _refreshing ? null : _handleTap,
      icon: _refreshing
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: AppTheme.primaryColor),
            )
          : const Icon(Icons.refresh_rounded,
              color: AppTheme.primaryColor, size: 22),
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
        _item('parrainage', Icons.card_giftcard_rounded,
            'Parrainage', AppTheme.orangeColor),
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
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: color),
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
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: Colors.red),
        ),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w600, fontSize: 13, color: Colors.red)),
      ]),
    );
  }
}
