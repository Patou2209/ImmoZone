import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import '../../../providers/auth_provider.dart';
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/property_card.dart';
import '../../../models/property_model.dart';
import '../../../models/user_model.dart';
import '../../auth/login_screen.dart';
import '../property_detail/property_detail_screen.dart';
import '../post_property/edit_property_screen.dart';
import '../../../services/data_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PropertyModel> _myProperties = [];
  bool _loading = true;
  int _availableCredits = 0;
  final DataService _ds = DataService();
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id;
    if (userId != null) {
      final credits = await _ds.getUserAvailableCredits(userId);
      if (mounted) setState(() => _availableCredits = credits);
    }
    if (auth.currentUser?.role == AppConstants.roleAnnonceur) {
      final props = await context.read<PropertyProvider>()
          .getUserProperties(auth.currentUser!.id);
      if (mounted) setState(() { _myProperties = props; _loading = false; });
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final isAnnonceur = user?.role == AppConstants.roleAnnonceur;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            title: const Text('Mon Profil',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            actions: [
              // ── Badge solde crédits dans l'AppBar ─────────────────────
              if (isAnnonceur)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    decoration: BoxDecoration(
                      color: _availableCredits > 0
                          ? AppTheme.accentColor.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _availableCredits > 0
                            ? AppTheme.accentColor
                            : Colors.white.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _availableCredits > 0
                              ? Icons.toll_rounded
                              : Icons.account_balance_wallet_outlined,
                          color: Colors.white,
                          size: 13,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$_availableCredits crédit${_availableCredits != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showEditProfile(context, user),
              ),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    onTap: () async {
                      await auth.logout();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (_) => false,
                      );
                    },
                    child: const ListTile(
                      leading: Icon(Icons.logout, color: Colors.red),
                      title: Text('Déconnexion',
                          style: TextStyle(color: Colors.red, fontFamily: 'Poppins')),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryDark, AppTheme.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      // ── Photo de profil (cliquable) ────────────────────────
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: user?.avatar != null && user!.avatar!.isNotEmpty
                                  ? () => _showFullscreenPhoto(context, user)
                                  : null,
                              child: CircleAvatar(
                                radius: 42,
                                backgroundColor: Colors.white.withValues(alpha: 0.25),
                                child: _buildAvatarContent(user),
                              ),
                            ),
                          ),
                          // Bouton modifier photo
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _uploadingPhoto ? null : () => _pickAndUploadPhoto(context, auth),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: _uploadingPhoto
                                      ? const Padding(
                                          padding: EdgeInsets.all(5),
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.camera_alt_rounded,
                                          color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        user?.name ?? '',
                        style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: Colors.white, fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 6),
                      // ── Solde crédits + Badge rôle ─────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Badge rôle
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isAnnonceur ? Icons.home_outlined : Icons.search,
                                  color: Colors.white, size: 13,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  user?.roleLabel ?? '',
                                  style: const TextStyle(
                                    fontSize: 11, color: Colors.white,
                                    fontWeight: FontWeight.w600, fontFamily: 'Poppins',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Badge solde crédits
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _availableCredits > 0
                                  ? AppTheme.accentColor.withValues(alpha: 0.85)
                                  : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _availableCredits > 0
                                    ? AppTheme.accentColor
                                    : Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _availableCredits > 0
                                      ? Icons.toll_rounded
                                      : Icons.account_balance_wallet_outlined,
                                  color: Colors.white, size: 13,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Solde : $_availableCredits crédit${_availableCredits != 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    fontSize: 11, color: Colors.white,
                                    fontWeight: FontWeight.w700, fontFamily: 'Poppins',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                // Info Card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    children: [
                      _infoRow(Icons.email_outlined, 'Email', user?.email ?? ''),
                      const Divider(height: 20),
                      _infoRow(Icons.phone_outlined, 'Téléphone', user?.phone ?? ''),
                      if (user?.city != null) ...[
                        const Divider(height: 20),
                        _infoRow(Icons.location_city_outlined, 'Ville', user!.city!),
                      ],
                    ],
                  ),
                ),

                // Stats for annonceurs
                if (isAnnonceur) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(child: _statCard('Actives',
                            '${_myProperties.where((p) => p.status == 'Actif' && !p.isExpired).length}',
                            Icons.check_circle_outline, AppTheme.successColor)),
                        const SizedBox(width: 12),
                        Expanded(child: _statCard('En attente',
                            '${_myProperties.where((p) => p.status == 'En attente').length}',
                            Icons.pending_outlined, AppTheme.warningColor)),
                        const SizedBox(width: 12),
                        Expanded(child: _statCard('Expirées',
                            '${_myProperties.where((p) => p.isExpired).length}',
                            Icons.timer_off_outlined, Colors.red)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // My Properties Tab
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicatorColor: AppTheme.primaryColor,
                              labelColor: AppTheme.primaryColor,
                              unselectedLabelColor: AppTheme.textSecondary,
                              labelStyle: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
                              tabs: const [
                                Tab(text: 'Mes annonces'),
                                Tab(text: 'Paramètres'),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 400,
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _myPropertiesTab(),
                                _settingsTab(context, auth),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  _settingsTab(context, auth),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Contenu de l'avatar (photo ou initiales) ─────────────────────────────
  Widget _buildAvatarContent(UserModel? user) {
    final avatarData = user?.avatar;
    if (avatarData != null && avatarData.isNotEmpty) {
      try {
        // L'avatar est stocké en base64 (data:image/jpeg;base64,...)
        final base64Str = avatarData.contains(',')
            ? avatarData.split(',').last
            : avatarData;
        final bytes = base64Decode(base64Str);
        return ClipOval(
          child: Image.memory(bytes,
              width: 84, height: 84, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initialsWidget(user)),
        );
      } catch (_) {
        return _initialsWidget(user);
      }
    }
    return _initialsWidget(user);
  }

  Widget _initialsWidget(UserModel? user) {
    return Text(
      user?.initials ?? '?',
      style: const TextStyle(
        fontSize: 28, fontWeight: FontWeight.w700,
        color: Colors.white, fontFamily: 'Poppins',
      ),
    );
  }

  // ── Affichage plein écran de la photo ─────────────────────────────────────
  void _showFullscreenPhoto(BuildContext context, UserModel user) {
    final avatarData = user.avatar;
    if (avatarData == null || avatarData.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          InteractiveViewer(
            child: Center(
              child: Builder(builder: (ctx) {
                try {
                  final base64Str = avatarData.contains(',')
                      ? avatarData.split(',').last
                      : avatarData;
                  final bytes = base64Decode(base64Str);
                  return Image.memory(bytes,
                      fit: BoxFit.contain,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height);
                } catch (_) {
                  return const Icon(Icons.broken_image, color: Colors.white, size: 64);
                }
              }),
            ),
          ),
          Positioned(
            top: 40, right: 16,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Sélectionner et enregistrer la photo de profil ────────────────────────
  Future<void> _pickAndUploadPhoto(BuildContext context, AuthProvider auth) async {
    final user = auth.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    try {
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (picked == null) return;

      setState(() => _uploadingPhoto = true);

      // Lire les bytes selon la plateforme
      final Uint8List bytes;
      if (kIsWeb) {
        bytes = await picked.readAsBytes();
      } else {
        bytes = await File(picked.path).readAsBytes();
      }

      // Encoder en base64 (data URL)
      final ext = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      final dataUrl = 'data:image/$ext;base64,${base64Encode(bytes)}';

      // Sauvegarder dans Firestore via updateUser
      final updatedUser = user.copyWith(avatar: dataUrl);
      await _ds.updateUser(updatedUser);

      // Mettre à jour la session locale dans AuthProvider
      auth.updateCurrentUserLocally(updatedUser);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Photo de profil mise à jour !',
                style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e',
                style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _myPropertiesTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accentColor));
    }
    if (_myProperties.isEmpty) {
      return const Center(
        child: Text('Aucune annonce publiée',
            style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Poppins')),
      );
    }

    // Séparer annonces actives/en attente et expirées
    final activeProps  = _myProperties.where((p) => !p.isExpired).toList();
    final expiredProps = _myProperties.where((p) => p.isExpired).toList();

    return ListView(
      padding: const EdgeInsets.only(top: 14),
      children: [
        // ── Annonces actives / en attente ────────────────────────────────
        if (activeProps.isNotEmpty) ...[
          ...activeProps.map((p) => _buildPropertyItem(p, expired: false)),
        ] else
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Center(
              child: Text('Aucune annonce active',
                  style: TextStyle(color: AppTheme.textSecondary,
                      fontFamily: 'Poppins', fontSize: 12)),
            ),
          ),

        // ── Section annonces expirées ─────────────────────────────────────
        if (expiredProps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.timer_off_outlined, color: Colors.red, size: 15),
              const SizedBox(width: 7),
              Text(
                'Annonces expirées (${expiredProps.length}) — '
                'non visibles au public',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: Colors.red),
              ),
            ]),
          ),
          ...expiredProps.map((p) => _buildPropertyItem(p, expired: true)),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  /// Construit la carte d'une annonce avec ses actions selon son état.
  Widget _buildPropertyItem(PropertyModel p, {required bool expired}) {
    final hoursElapsed = DateTime.now().difference(p.createdAt).inHours;
    final canEdit = !expired && hoursElapsed < 24;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Carte de l'annonce (avec opacité réduite si expirée)
          Opacity(
            opacity: expired ? 0.7 : 1.0,
            child: PropertyCard(
              property: p,
              showStatus: true,
              onShare: () => _shareProperty(p),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p))),
            ),
          ),

          // ── Barre d'actions ──────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: expired
                  ? Colors.red.withValues(alpha: 0.04)
                  : Colors.white,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              border: expired
                  ? Border.all(color: Colors.red.withValues(alpha: 0.2))
                  : null,
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4, offset: const Offset(0, 2),
              )],
            ),
            child: expired
                // ── ANNONCE EXPIRÉE : bouton Renouveler ─────────────────
                ? Row(children: [
                    const Icon(Icons.timer_off_outlined,
                        size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.expiresAt != null
                            ? 'Expirée le ${_formatDate(p.expiresAt!)}'
                            : 'Annonce expirée',
                        style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 10, color: Colors.red),
                      ),
                    ),
                    // Bouton Renouveler
                    ElevatedButton.icon(
                      onPressed: () => _confirmRenew(context, p),
                      icon: const Icon(Icons.refresh_rounded,
                          size: 14, color: Colors.white),
                      label: const Text('Renouveler',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 1,
                      ),
                    ),
                  ])
                // ── ANNONCE ACTIVE : Modifier (24h) + Supprimer ─────────
                : Row(children: [
                    const Spacer(),
                    if (canEdit) ...[
                      IconButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => EditPropertyScreen(property: p)),
                          );
                          if (result == true && mounted) _load();
                        },
                        icon: const Icon(Icons.edit_outlined,
                            size: 20, color: AppTheme.accentColor),
                        tooltip: 'Modifier',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      onPressed: () => _confirmDelete(context, p),
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: Colors.red),
                      tooltip: 'Supprimer',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                  ]),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  Future<void> _shareProperty(PropertyModel p) async {
    final ref = 'IZ${p.id.length >= 4 ? p.id.substring(p.id.length - 4).toUpperCase() : p.id.toUpperCase()}';
    final link = '${AppConstants.webBaseUrl}/property/${p.id}';
    final text = '${p.title} — Réf. $ref\n$link';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _confirmDelete(BuildContext ctx, PropertyModel p) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer l\'annonce',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 16)),
        content: Text(
          'Voulez-vous vraiment supprimer "${p.title}" ?\nCette action est irréversible.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Supprimer',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<PropertyProvider>().deleteProperty(p.id);
      setState(() => _myProperties.removeWhere((x) => x.id == p.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Annonce supprimée',
                style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Dialogue de confirmation de renouvellement
  Future<void> _confirmRenew(BuildContext ctx, PropertyModel p) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.refresh_rounded,
                color: AppTheme.primaryColor, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Renouveler l\'annonce',
              style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${p.title}"',
                style: const TextStyle(fontFamily: 'Poppins',
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'L\'annonce sera remise en attente de validation '
                'et redeviendra visible au public après approbation.\n\n'
                'Durée de renouvellement : 30 jours.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins',
                    color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dCtx, true),
            icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
            label: const Text('Renouveler',
                style: TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _ds.renewProperty(p.id, days: 30);
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '✅ Annonce renouvelée — en attente de validation',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              backgroundColor: AppTheme.primaryColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur : $e',
                  style: const TextStyle(fontFamily: 'Poppins')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _settingsTab(BuildContext context, AuthProvider auth) {
    return ListView(
      padding: const EdgeInsets.only(top: 14),
      children: [
        _settingsTile(Icons.notifications_outlined, 'Notifications', () {}),
        _settingsTile(Icons.security_outlined, 'Sécurité & Confidentialité', () {}),
        _settingsTile(Icons.help_outline, 'Aide & Support', () {}),
        _settingsTile(Icons.info_outline, 'À propos d\'ImmoZone', () {}),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: OutlinedButton.icon(
            onPressed: () async {
              await auth.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text('Déconnexion',
                style: TextStyle(color: Colors.red, fontFamily: 'Poppins')),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.accentColor, size: 18),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(
                fontSize: 11, color: AppTheme.textHint, fontFamily: 'Poppins')),
            Text(value, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'Poppins')),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700,
              color: color, fontFamily: 'Poppins')),
          Text(label, style: const TextStyle(
              fontSize: 10, color: AppTheme.textSecondary, fontFamily: 'Poppins')),
        ],
      ),
    );
  }

  Widget _settingsTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.accentColor, size: 18),
      ),
      title: Text(label, style: const TextStyle(
          fontSize: 14, fontFamily: 'Poppins', fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textHint),
      onTap: onTap,
    );
  }

  void _showEditProfile(BuildContext context, UserModel? user) {
    if (user == null) return;
    final nameCtrl = TextEditingController(text: user.name);
    final phoneCtrl = TextEditingController(text: user.phone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24, right: 24, top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Modifier le profil',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins')),
            const SizedBox(height: 20),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                prefixIcon: Icon(Icons.person_outline, color: AppTheme.accentColor),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                prefixIcon: Icon(Icons.phone_outlined, color: AppTheme.accentColor),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final updated = user.copyWith(
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                  );
                  await _ds.updateUser(updated);
                  await context.read<AuthProvider>().refreshUser();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profil mis à jour avec succès!'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                },
                child: const Text('Enregistrer'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
