import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/property_card.dart';
import '../../../core/widgets/property_image.dart';
import '../../../core/widgets/ad_banner_card.dart';
import '../../../models/ad_model.dart';
import '../../../services/data_service.dart';
import '../../../models/property_model.dart';
import '../../../models/user_model.dart';
import '../../../models/app_notification_model.dart';
import '../property_detail/property_detail_screen.dart';
import '../favorites/favorites_screen.dart';
import '../post_property/post_property_screen.dart';
import '../post_property/edit_property_screen.dart';
import '../../auth/login_screen.dart';
import '../../admin/admin_home_screen.dart';
import '../search/search_screen.dart';

class PublicHomeScreen extends StatefulWidget {
  const PublicHomeScreen({super.key});
  @override
  State<PublicHomeScreen> createState() => _PublicHomeScreenState();
}

class _PublicHomeScreenState extends State<PublicHomeScreen> {
  int _currentIndex = 0;
  int _unreadNotifCount = 0;
  final DataService _ds = DataService();

  final List<Widget> _pages = const [
    _HomeTab(),
    FavoritesScreen(),
    _AlertsTab(),
  ];

  // Coordonnées contact récupérées depuis DataService
  String _waContactNumber = '';
  String _phoneContactNumber = '';
  String _emailContact = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUnreadCount();
      _loadWaContact();
    });
  }

  Future<void> _loadWaContact() async {
    // Recharger le cache depuis Firestore pour avoir les dernières coordonnées
    await _ds.refreshAllCaches();
    if (mounted) setState(() {
      _waContactNumber    = _ds.whatsappContactNumber;
      _phoneContactNumber = _ds.phoneContactNumber;
      _emailContact       = _ds.emailContact;
    });
  }

  Future<void> _loadUnreadCount() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    final count = await _ds.getUnreadNotificationCount(userId);
    if (mounted) setState(() => _unreadNotifCount = count);
  }

  // ── CONTACT SHEET ────────────────────────────────────────────────────────
  void _openContactSheet() {
    final hasWa    = _waContactNumber.isNotEmpty;
    final hasPhone = _phoneContactNumber.isNotEmpty;
    final hasEmail = _emailContact.isNotEmpty;

    if (!hasWa && !hasPhone && !hasEmail) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Coordonnées non configurées. Contactez l\'administrateur.',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.of(ctx).viewPadding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Contacter ImmoZone',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                      fontSize: 16, color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              const Text('Choisissez votre mode de contact',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 20),

              // WhatsApp
              if (hasWa)
                _contactOption(
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF25D366),
                  label: 'WhatsApp',
                  subtitle: '+${_waContactNumber.replaceAll(RegExp(r'[^0-9]'), '')}',
                  onTap: () {
                    Navigator.pop(context);
                    _launchWhatsApp();
                  },
                ),

              if (hasWa && (hasPhone || hasEmail)) const SizedBox(height: 10),

              // Appel Normal
              if (hasPhone)
                _contactOption(
                  icon: Icons.phone_rounded,
                  color: AppTheme.accentColor,
                  label: 'Appel Normal',
                  subtitle: _phoneContactNumber,
                  onTap: () {
                    Navigator.pop(context);
                    _launchPhone();
                  },
                ),

              if (hasPhone && hasEmail) const SizedBox(height: 10),

              // Email
              if (hasEmail)
                _contactOption(
                  icon: Icons.email_outlined,
                  color: AppTheme.primaryColor,
                  label: 'E-Mail',
                  subtitle: _emailContact,
                  onTap: () {
                    Navigator.pop(context);
                    _launchEmail();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactOption({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 14, color: color)),
              Text(subtitle, style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: AppTheme.textSecondary)),
            ],
          )),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color.withValues(alpha: 0.6)),
        ]),
      ),
    ));
  }

  Future<void> _launchWhatsApp() async {
    final number = _waContactNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (number.isEmpty) return;
    final message = Uri.encodeComponent(
        'Bonjour ImmoZone, je vous contacte depuis l\'application.');
    final nativeUri = Uri.parse('whatsapp://send?phone=$number&text=$message');
    try {
      await launchUrl(nativeUri, mode: LaunchMode.externalNonBrowserApplication);
      return;
    } catch (_) {}
    try {
      await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}
    final webUri = Uri.parse('https://wa.me/$number?text=$message');
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}
    await Clipboard.setData(ClipboardData(text: '+$number'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('WhatsApp indisponible — Numéro copié : +$number',
          style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFF25D366),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _launchPhone() async {
    final number = _phoneContactNumber.trim();
    if (number.isEmpty) return;
    final uri = Uri.parse('tel:$number');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: number));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Appel indisponible — Numéro copié : $number',
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.accentColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _launchEmail() async {
    final email = _emailContact.trim();
    if (email.isEmpty) return;
    final uri = Uri.parse('mailto:$email?subject=Contact%20ImmoZone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: email));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Email copié : $email',
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Nav items row
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _navItem(0, Icons.search_rounded, Icons.search_rounded, 'Recherche'),
                        _navItem(1, Icons.favorite_border_rounded, Icons.favorite_rounded, 'Favoris'),
                        // Spacer for FAB center
                        const SizedBox(width: 64),
                        // Alertes
                        _navItemWithBadge(2, Icons.notifications_none_rounded, Icons.notifications_rounded, 'Alertes', _unreadNotifCount),
                        // Contact
                        MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                          onTap: _openContactSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.chat_rounded,
                                    color: AppTheme.textHint, size: 22),
                                const SizedBox(height: 2),
                                const Text('Contact',
                                    style: TextStyle(
                                      fontSize: 9, fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textHint,
                                    )),
                              ],
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
                // FAB circle Publier — floating above nav bar
                Positioned(
                  top: -20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                      onTap: () => _openPublish(context, auth),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(alpha: 0.40),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 30),
                      ),
                    )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    return _navItemWithBadge(index, icon, activeIcon, label, 0);
  }

  Widget _navItemWithBadge(int index, IconData icon, IconData activeIcon, String label, int badge) {
    final isSelected = _currentIndex == index;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        if (index == 2) _loadUnreadCount();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                  size: 22,
                ),
                if (badge > 0)
                  Positioned(
                    top: -4, right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                      child: Text('$badge',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 8,
                              fontWeight: FontWeight.w800, fontFamily: 'Poppins')),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: 9, fontFamily: 'Poppins',
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                )),
          ],
        ),
      ),
    ));
  }

  void _openPublish(BuildContext context, AuthProvider auth) {
    if (!auth.isLoggedIn) {
      _showLoginRequired(context,
          message: 'Vous devez creer un compte pour publier une annonce.');
      return;
    }
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PostPropertyScreen()));
  }


  static void _showLoginRequired(BuildContext context, {required String message}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.lock_outline_rounded, color: AppTheme.accentColor, size: 22),
          SizedBox(width: 10),
          Text('Connexion requise',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 15, color: AppTheme.textPrimary)),
        ]),
        content: Text(message,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppTheme.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Se connecter',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ONGLET ALERTES (placeholder)
// ══════════════════════════════════════════════════════════════════════════════
class _AlertsTab extends StatefulWidget {
  const _AlertsTab();
  @override
  State<_AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<_AlertsTab> {
  final _ds = DataService();
  List<AppNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    if (userId.isEmpty) { setState(() => _isLoading = false); return; }
    final notifs = await _ds.getNotificationsForUser(userId);
    await _ds.markAllNotificationsRead(userId);
    if (mounted) setState(() { _notifications = notifs; _isLoading = false; });
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'rejet': return Icons.cancel_rounded;
      case 'suppression': return Icons.delete_forever_rounded;
      case 'approbation': return Icons.check_circle_rounded;
      default: return Icons.info_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'rejet': return AppTheme.errorColor;
      case 'suppression': return Colors.deepOrange;
      case 'approbation': return AppTheme.successColor;
      default: return AppTheme.accentColor;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'il y a ${diff.inDays}j';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text('Notifications',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryColor),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE9EBF0)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_none_rounded,
                          size: 56, color: AppTheme.accentColor),
                    ),
                    const SizedBox(height: 20),
                    const Text('Aucune notification',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                            fontSize: 18, color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Vous serez notifié ici de toute action sur vos annonces.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            color: AppTheme.textSecondary, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _notifications.length,
                  itemBuilder: (_, i) {
                    final n = _notifications[i];
                    final color = _colorForType(n.type);
                    return Dismissible(
                      key: Key(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_rounded, color: Colors.white, size: 24),
                            SizedBox(height: 4),
                            Text('Supprimer',
                                style: TextStyle(fontFamily: 'Poppins',
                                    fontSize: 11, color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      onDismissed: (_) async {
                        final removed = _notifications[i];
                        setState(() => _notifications.removeAt(i));
                        await _ds.deleteNotification(removed.id);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: color.withValues(alpha: 0.25)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 6, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                          leading: Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_iconForType(n.type), color: color, size: 22),
                          ),
                          title: Text(n.title,
                              style: TextStyle(
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                  fontSize: 13, color: color)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(n.body,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 12,
                                      color: AppTheme.textSecondary, height: 1.4)),
                              const SizedBox(height: 6),
                              Text(_timeAgo(n.createdAt),
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 10,
                                      color: AppTheme.textHint)),
                            ],
                          ),
                          isThreeLine: true,
                          // Bouton X de suppression explicite
                          trailing: IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 18, color: AppTheme.textHint.withValues(alpha: 0.6)),
                            tooltip: 'Supprimer cette notification',
                            onPressed: () async {
                              final removed = _notifications[i];
                              setState(() => _notifications.removeAt(i));
                              await _ds.deleteNotification(removed.id);
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ONGLET PRINCIPAL (accueil avec filtres selon wireframe)
// ══════════════════════════════════════════════════════════════════════════════
class _HomeTab extends StatefulWidget {
  const _HomeTab();
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab>
    with SingleTickerProviderStateMixin {
  late TabController _modeCtrl;

  // Mode actif : 'Location' ou 'Achat'
  String _activeMode = AppConstants.defaultMode;
  // Categorie selectionnee
  String _selectedCategory = AppConstants.defaultCategory;
  // Filtres
  String _country = AppConstants.defaultCountry; // mutable: changed via country selector
  String? _province;
  String? _city;
  String? _commune;
  String _searchQuery = '';
  // Filtres avances
  int? _minRooms;      // 1+ 2+ 3+ 4+ 5+ (dropdown, min uniquement)
  int? _minBaths;      // 1+ 2+ 3+ 4+ 5+ (dropdown, min uniquement)
  double? _minPrice;
  double? _maxPrice;
  // superficie supprimée des filtres (v1.2.16)
  int? _minSeats;
  int? _maxSeats;
  double? _minHectares;
  double? _maxHectares;
  int? _minBeds;
  int? _maxBeds;
  // Filtres booléens
  bool? _filterParking;       // null=tous, true=avec parking
  bool? _filterGroupeElec;    // null=tous, true=avec groupe électrogène
  bool? _filterSecurite;      // null=tous, true=avec sécurité 24h/24
  // Afficher plus
  int _displayCount = 4;
  // Stats
  Map<String, dynamic> _stats = {};
  bool _statsLoading = true;
  // Favoris
  List<String> _favorites = [];
  final DataService _ds = DataService();
  bool _filtersExpanded = false;
  bool _hasSearched = false; // true apres une vraie recherche
  List<AdModel> _liveAds = [];
  // Index de rotation des pubs — persisté entre sessions
  int _adRotationIndex = 0;
  static const _kAdRotKey = 'ad_rotation_index';

  @override
  void initState() {
    super.initState();
    _modeCtrl = TabController(length: 2, vsync: this);
    _modeCtrl.addListener(() {
      if (!_modeCtrl.indexIsChanging) {
        setState(() {
          _activeMode = _modeCtrl.index == 0 ? 'Location' : 'Achat';
          _selectedCategory = _currentCategories[0];
          _resetFilters(clearSearch: false); // garde le texte de recherche au changement de mode
          _displayCount = 4;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _loadFavorites();
      _loadStats();
    });
  }

  @override
  void dispose() {
    _modeCtrl.dispose();
    super.dispose();
  }

  List<String> get _currentCategories =>
      _activeMode == 'Location'
          ? AppConstants.categoriesLocation
          : AppConstants.categoriesAchat;

  Future<void> _loadData() async {
    await context.read<PropertyProvider>().loadProperties();
    final ads = await _ds.getLiveAds();
    if (!mounted) return;
    // Récupérer l'index de rotation sauvegardé
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_kAdRotKey) ?? 0;
    setState(() {
      _liveAds = ads;
      _adRotationIndex = savedIndex;
    });
  }

  Future<void> _loadFavorites() async {
    final f = await _ds.getFavorites();
    if (mounted) setState(() => _favorites = f);
  }

  Future<void> _loadStats() async {
    final s = await _ds.getPublicStats();
    if (mounted) setState(() { _stats = s; _statsLoading = false; });
  }

  void _resetFilters({bool clearSearch = true}) {
    _minRooms = _minBaths = null;
    _minBeds = _maxBeds = _minSeats = _maxSeats = null;
    _minPrice = _maxPrice = null;
    _minHectares = _maxHectares = null;
    _province = _city = _commune = null;
    _country = AppConstants.defaultCountry;
    _filterParking = _filterGroupeElec = _filterSecurite = null;
    if (clearSearch) {
      _searchQuery = '';
      _hasSearched = false;
    }
  }

  Future<void> _toggleFavorite(String id) async {
    await _ds.toggleFavorite(id);
    await _loadFavorites();
  }

  Future<void> _shareProperty(PropertyModel p) async {
    final ref = 'IZ${p.id.length >= 4 ? p.id.substring(p.id.length - 4).toUpperCase() : p.id.toUpperCase()}';
    final link = '${AppConstants.webBaseUrl}/property/${p.id}';
    final text = '${p.title} — Réf. $ref\n$link';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  // Filtrer les annonces selon mode + categorie + filtres
  // Les annonces vendues/occupees restent visibles pendant 72h
  List<PropertyModel> get _filteredProperties {
    final provider = context.read<PropertyProvider>();
    final now = DateTime.now();
    final all = provider.properties.where((p) {
      // Annonces actives normales
      if (p.status == 'Actif' && !p.isSold && !p.isRented) return true;
      // Annonces vendues/occupees : visibles jusqu'a 72h apres fermeture
      if ((p.isSold || p.isRented) && p.updatedAt != null) {
        return now.difference(p.updatedAt!).inHours < AppConstants.soldAutoDeleteHours;
      }
      return false;
    }).toList();

    // Quand une recherche texte est active, on cherche dans TOUTES les
    // categories (comportement identique aux ecrans admin/user posts).
    // Le filtre categorie est suspendu pour ne pas bloquer les resultats.
    final bool isTextSearch = _searchQuery.isNotEmpty;

    return all.where((p) {
      // Mode (Location vs Achat) — suspendu si recherche texte active
      // (l'utilisateur peut taper "Location maison" sans changer le tab)
      if (!isTextSearch) {
        final modeMatch = _activeMode == 'Location'
            ? p.transactionType == 'Location'
            : p.transactionType == 'Vente';
        if (!modeMatch) return false;
      }

      // Categorie (court-circuitee quand recherche texte active)
      if (!isTextSearch) {
        final catNorm = _normalize(_selectedCategory);
        final typeNorm = _normalize(p.type);
        if (!typeNorm.contains(catNorm) && !catNorm.contains(typeNorm)) return false;
      }

      // ── Pays — toujours appliqué, y compris pour le pays par défaut ────────
      // BUG CORRIGÉ : avant, le filtre pays était désactivé quand _country ==
      // defaultCountry, ce qui laissait passer des annonces de Brazzaville.
      if (_country.isNotEmpty) {
        if (!_normalize(p.country ?? '').contains(_normalize(_country)) &&
            !_normalize(_country).contains(_normalize(p.country ?? ''))) {
          return false;
        }
      }

      // ── Province — filtre optionnel (aucune province par défaut) ───────────
      if (_province != null && _province!.isNotEmpty &&
          !_normalize(p.province).contains(_normalize(_province!))) return false;
      if (_city != null && _city!.isNotEmpty &&
          !_normalize(p.city).contains(_normalize(_city!))) return false;
      if (_commune != null && _commune!.isNotEmpty &&
          !_normalize(p.commune).contains(_normalize(_commune!))) return false;

      // Recherche texte multi-mots : chaque mot doit trouver une correspondance
      // dans au moins un champ — "Location maison Lemba" / "NGANDU BENA" → OR logique
      if (isTextSearch) {
        final keywords = _searchQuery.toLowerCase().trim().split(RegExp(r'\s+'));
        final searchable = [
          p.title, p.city, p.province, p.type,
          p.description, p.commune, p.country ?? '',
          p.transactionType, p.id,
          // ← recherche par nom d'annonceur
          p.ownerName, p.ownerPhone,
        ].map((s) => s.toLowerCase()).join(' ');
        // Au moins un mot-clé doit matcher (OR logique)
        final anyMatch = keywords.any((kw) => kw.isNotEmpty && searchable.contains(kw));
        if (!anyMatch) return false;
      }

      // Filtres prix
      if (_minPrice != null && p.price < _minPrice!) return false;
      if (_maxPrice != null && p.price > _maxPrice!) return false;

      // Filtres chambres (min uniquement — dropdown 1+ 2+ ...)
      if (_minRooms != null && (p.bedrooms ?? 0) < _minRooms!) return false;

      // Filtres SDB (min uniquement — dropdown 1+ 2+ ...)
      if (_minBaths != null && (p.bathrooms ?? 0) < _minBaths!) return false;

      // Filtres booléens
      if (_filterParking == true && !p.hasParking) return false;
      if (_filterGroupeElec == true && !p.hasElectricity) return false;
      if (_filterSecurite == true && !p.hasWater) return false;

      // Filtres places assises
      if (_minSeats != null && (p.capacity ?? 0) < _minSeats!) return false;
      if (_maxSeats != null && (p.capacity ?? 0) > _maxSeats!) return false;

      // Filtres lits (hotel)
      if (_minBeds != null && (p.numberOfBeds ?? 0) < _minBeds!) return false;
      if (_maxBeds != null && (p.numberOfBeds ?? 0) > _maxBeds!) return false;

      return true;
    }).toList()
      ..sort((a, b) {
        // Boostes en premier
        if (a.isBoostActive && !b.isBoostActive) return -1;
        if (!a.isBoostActive && b.isBoostActive) return 1;
        // Trier par date de validation (updatedAt)
        final aDate = a.updatedAt ?? a.createdAt;
        final bDate = b.updatedAt ?? b.createdAt;
        return bDate.compareTo(aDate);
      });
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Convertit un nom de catégorie en étiquette respectant la grammaire française :
  /// seul le premier mot prend une majuscule, les suivants sont en minuscules.
  /// Exceptions : sigles et noms propres courts (ex: "Flat", "/").
  String _displayCategory(String cat) {
    const Map<String, String> _labels = {
      'Appartement / Flat'       : 'Appartement / flat',
      'Propriété Commerciale'    : 'Propriété commerciale',
      'Propriété Industrielle'   : 'Propriété industrielle',
      'Salle de Fêtes'           : 'Salle de fêtes',
      'Espace Funéraire'         : 'Espace funéraire',
      'Salle Polyvalente'        : 'Salle polyvalente',
      'Chambre d\'hôtel'         : 'Chambre d\'hôtel',
      'Terrain à bâtir'          : 'Terrain à bâtir',
    };
    return _labels[cat] ?? cat;
  }

  bool get _hasCatRooms => AppConstants.catWithRooms.any(
      (c) => _normalize(c) == _normalize(_selectedCategory));
  bool get _hasCatBeds => AppConstants.catWithBeds.any(
      (c) => _normalize(c) == _normalize(_selectedCategory));
  bool get _hasCatSurface => AppConstants.catWithSurface.any(
      (c) => _normalize(c) == _normalize(_selectedCategory));
  bool get _hasCatSeats => AppConstants.catWithSeats.any(
      (c) => _normalize(c) == _normalize(_selectedCategory));
  bool get _hasCatHectares => AppConstants.catWithHectares.any(
      (c) => _normalize(c) == _normalize(_selectedCategory));

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PropertyProvider>();
    final filtered = _filteredProperties;
    final displayed = filtered.take(_displayCount).toList();
    final hasMore = filtered.length > _displayCount;

    // Annonces boostées filtrées selon le contexte courant
    final boosted = provider.getBoostedProperties(
      country: _country != AppConstants.defaultCountry ? _country : null,
      province: _province,
      city: _city,
      commune: _commune,
      transactionType: _activeMode == 'Location' ? 'Location' : 'Vente',
      propertyType: _searchQuery.isEmpty ? _selectedCategory : null,
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(children: [
          // ── TOP BAR seul reste fixe (logo + cloche + avatar) ─────────────
          _buildTopBar(context),

          // ── BODY entierement scrollable (hero + tabs + chips + search + liste)
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.accentColor,
              onRefresh: () async { await _loadData(); await _loadStats(); },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(children: [
                  // Hero + Tabs + Chips + Search (tout scrolle avec la liste)
                  _buildScrollableHeader(context, filteredCount: filtered.length),

                  // Filtres avances
                  if (_filtersExpanded) _buildAdvancedFilters(),

                  // ── Section Offres Spéciales (boostées) ───────────────────────
                  if (boosted.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSectionHeader(
                      icon: Icons.workspace_premium_rounded,
                      label: 'Offres Spéciales',
                      color: const Color(0xFFE65100),
                    ),
                    const SizedBox(height: 8),
                    _buildGrid(context, boosted),
                    _buildSectionDivider(),
                  ],

                  const SizedBox(height: 12),

                  // Bandeau nombre de resultats
                  if (displayed.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppTheme.accentColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.home_work_rounded,
                                size: 13, color: AppTheme.accentColor),
                            const SizedBox(width: 5),
                            Text(
                              '${filtered.length} '
                              'propriété${filtered.length > 1 ? 's' : ''} trouvée${filtered.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ),

                  // Titre section liste normale (seulement si boostées visibles)
                  if (boosted.isNotEmpty && displayed.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildSectionHeader(
                      icon: Icons.home_work_rounded,
                      label: 'Toutes les annonces',
                      color: AppTheme.primaryColor,
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Liste ou etat vide
                  if (displayed.isEmpty)
                    _buildEmptyWithSimilar([])
                  else
                    _buildGridWithAds(context, displayed),

                  // Voir plus
                  if (hasMore) _buildVoirPlus(filtered.length),

                  // Stats footer
                  _buildStatsFooter(),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── SÉPARATEURS DE SECTION BOOST ───────────────────────────────────────────
  Widget _buildSectionHeader({required IconData icon, required String label, required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.75)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.white,
              )),
        ]),
      ),
    );
  }

  Widget _buildSectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Container(height: 1, color: const Color(0xFFE4E8F0))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('Annonces disponibles',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: Colors.grey[400], fontWeight: FontWeight.w500)),
        ),
        Expanded(child: Container(height: 1, color: const Color(0xFFE4E8F0))),
      ]),
    );
  }


  // ── HEADER ─────────────────────────────────────────────────────────────────
  // ── TOP BAR (fixe — ne scrolle pas) ─────────────────────────────────────

  /// Logo texte ImmoZone — taille responsive selon la largeur de l'écran.
  /// Ratio du PNG : 1024×223 ≈ 4.59:1 (horizontal).
  /// Principe : plus le viewport est large, plus le logo est grand.
  /// Cercle avatar 42px dans la top-bar : photo base64 ou initiales.
  Widget _buildTopBarAvatar(UserModel? user) {
    final avatarData = user?.avatar;
    Widget inner;
    if (avatarData != null && avatarData.isNotEmpty) {
      try {
        final b64 = avatarData.contains(',') ? avatarData.split(',').last : avatarData;
        final bytes = base64Decode(b64);
        inner = Image.memory(bytes, width: 42, height: 42, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _topBarInitials(user));
      } catch (_) {
        inner = _topBarInitials(user);
      }
    } else {
      inner = _topBarInitials(user);
    }
    return Container(
      width: 42, height: 42,
      decoration: const BoxDecoration(
        color: Color(0xFFD8E0EE), shape: BoxShape.circle),
      child: ClipOval(child: inner),
    );
  }

  Widget _topBarInitials(UserModel? user) {
    final name = user?.name ?? '';
    final initials = name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      color: const Color(0xFFD8E0EE),
      child: Center(child: Text(initials,
          style: const TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 13,
              color: AppTheme.textPrimary))),
    );
  }

  Widget _buildResponsiveLogo(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final screenW = MediaQuery.of(context).size.width;
      // Hauteur de base 32px (mobile <480), monte progressivement
      double h;
      if (screenW < 480) {
        h = 30;
      } else if (screenW < 768) {
        h = 34;
      } else if (screenW < 1024) {
        h = 40;
      } else if (screenW < 1440) {
        h = 46;
      } else {
        h = 52;
      }
      return Image.asset(
        'assets/images/immozone_logo_text.png',
        height: h,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => RichText(
          text: TextSpan(
            style: TextStyle(fontFamily: 'Poppins', fontSize: h * 0.55),
            children: const [
              TextSpan(text: 'Immo',
                  style: TextStyle(fontWeight: FontWeight.w800,
                      color: Color(0xFF2B5BE8))),
              TextSpan(text: 'Zone',
                  style: TextStyle(fontWeight: FontWeight.w800,
                      color: Color(0xFFED5C1F))),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildTopBar(BuildContext context) {
    return Column(children: [
      // Barre blanche : logo + cloche + avatar/connexion
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          // Logo texte ImmoZone responsive
          _buildResponsiveLogo(context),
          const Spacer(),
          // Avatar / bouton Connexion
          Builder(builder: (ctx) {
            final auth = ctx.watch<AuthProvider>();
            if (auth.isLoggedIn) {
              // Admin : accès direct au panneau admin
              if (auth.isAdmin) {
                return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                  onTap: () => Navigator.pushAndRemoveUntil(context,
                      MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
                      (route) => false),
                  child: Container(
                    width: 42, height: 42,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryColor, shape: BoxShape.circle),
                    child: const Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.white, size: 20),
                  ),
                ));
              }
              // Annonceur connecté : avatar photo/initiales + PopupMenu
              final user = auth.currentUser;
              return PopupMenuButton<String>(
                offset: const Offset(0, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 8,
                onSelected: (val) {
                  if (val == 'dashboard') {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const _UserDashboardScreen()));
                  } else if (val == 'reglages') {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const _UserReglagesScreen()));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'dashboard',
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.dashboard_rounded,
                            size: 18, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(width: 12),
                      const Text('Mon tableau de bord',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'reglages',
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.settings_rounded,
                            size: 18, color: AppTheme.accentColor),
                      ),
                      const SizedBox(width: 12),
                      const Text('Réglages',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ]),
                  ),
                ],
                child: _buildTopBarAvatar(user),
              );
            }
            return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.30),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text('Connexion',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 13, color: Colors.white)),
              ),
            ));
          }),
        ]),
      ),
      // Ombre portee sous la barre fixe
      Container(height: 1, color: const Color(0xFFE4E8F0)),
    ]);
  }

  // ── HEADER SCROLLABLE (hero + search + tabs + chips + pays/province + filtres)
  Widget _buildScrollableHeader(BuildContext context, {int filteredCount = 0}) {
    // Listes dynamiques selon le pays sélectionné (utilisées ici pour les dropdowns inline)
    final provinces = AppConstants.getProvincesForCountry(_country);

    return Column(children: [
      // ══ PARTIE 2 : Hero gradient ══════════════════════════════════════════
      Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFB8D0F5),
              Color(0xFFCADCF8),
              Color(0xFFE8F1FD),
              Color(0xFFFFFFFF),
            ],
            stops: [0.0, 0.35, 0.70, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
        child: Column(children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFFA726), Color(0xFF0A3A8F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              _ds.homeTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _ds.homeSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // ══ BARRE DE RECHERCHE GLOBALE (dans le hero, avant les filtres) ══
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              onChanged: (v) => setState(() {
                _searchQuery = v;
                _displayCount = 4;
                _hasSearched = v.isNotEmpty;
              }),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Recherche par mots-clés, type, ville, annonceur...',
                hintStyle: TextStyle(fontFamily: 'Poppins',
                    fontSize: 12, color: AppTheme.textHint),
                prefixIcon: Icon(Icons.search_rounded,
                    color: AppTheme.primaryColor, size: 22),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ]),
      ),

      // ══ PARTIE 3 : Label + Tabs Location / Achat ════════════════════════
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Recherche par filtre :',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FA),
              borderRadius: BorderRadius.circular(30),
            ),
            padding: const EdgeInsets.all(3),
            child: TabBar(
              controller: _modeCtrl,
              indicator: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(text: 'Location'),
                Tab(text: 'Achat'),
              ],
            ),
          ),
        ]),
      ),

      // ══ PARTIE 4 : Chips categories ══════════════════════════════════════
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
        child: SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _currentCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final cat = _currentCategories[i];
              final selected = cat == _selectedCategory;
              return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                onTap: () => setState(() {
                  _selectedCategory = cat;
                  _resetFilters(clearSearch: false);
                  _displayCount = 4;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primaryColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: selected ? AppTheme.primaryColor : const Color(0xFFCDD4E4),
                      width: 1.5,
                    ),
                  ),
                  child: Text(_displayCategory(cat),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 12,
                        color: selected ? Colors.white : AppTheme.textSecondary,
                      )),
                ),
              ));
            },
          ),
        ),
      ),

      // ══ PARTIE 5 : Pays + Province + Plus de filtres ═════════════════════
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Ligne Pays + Province (inline)
          Row(children: [
            // Dropdown Pays
            Expanded(
              child: _inlineDropdown(
                icon: Icons.public_rounded,
                label: 'Pays',
                value: _country,
                items: AppConstants.filterCountries,
                onChanged: (v) {
                  final selected = v ?? AppConstants.defaultCountry;
                  setState(() {
                    _country = selected;
                    _city = null;
                    // Province par défaut selon le pays
                    if (selected == 'Congo (Brazzaville)') {
                      _province = 'Brazzaville';
                    } else {
                      // RDC → reset (hint affiche Kinshasa)
                      _province = null;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            // Dropdown Province
            Expanded(
              child: _inlineDropdown(
                icon: Icons.location_city_rounded,
                label: 'Province',
                value: _province,
                items: provinces,
                // hint dynamique selon le pays
                hint: 'Sélectionnez votre province',
                onChanged: (v) => setState(() {
                  _province = v;
                  _city = null;
                }),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Bouton "Plus de filtres" (pleine largeur)
          MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
            onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
            child: Container(
              width: double.infinity,
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _filtersExpanded
                    ? AppTheme.primaryColor
                    : const Color(0xFFEEF2FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _filtersExpanded
                      ? AppTheme.primaryColor
                      : const Color(0xFFDDE3F0),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune_rounded,
                      color: _filtersExpanded ? Colors.white : AppTheme.textSecondary,
                      size: 17),
                  const SizedBox(width: 6),
                  Text(
                    _filtersExpanded ? 'Masquer les filtres' : 'Plus de filtres',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _filtersExpanded ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _filtersExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _filtersExpanded ? Colors.white : AppTheme.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          )),
        ]),
      ),

      // Ligne séparatrice
      const Divider(height: 1, color: Color(0xFFE4E8F0)),
    ]);
  }

  // ── Dropdown compact inline (Pays / Province) ─────────────────────────────
  Widget _inlineDropdown({
    required IconData icon,
    required String label,
    required String? value,
    required List<String> items,
    String? hint,
    required void Function(String?) onChanged,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: (value != null && items.contains(value)) ? value : null,
          hint: Row(children: [
            Icon(icon, size: 14, color: AppTheme.textHint),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                hint ?? label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppTheme.textHint,
                ),
              ),
            ),
          ]),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: AppTheme.textHint),
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(item, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
          )).toList(),
          onChanged: onChanged,
          selectedItemBuilder: (ctx) => items.map((item) => Row(children: [
            Icon(icon, size: 14, color: AppTheme.primaryColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(item,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11,
                  color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
              ),
            ),
          ])).toList(),
        ),
      ),
    );
  }

  // ── ANCIENNE METHODE _buildHeader (supprimee — remplacee par _buildTopBar + _buildScrollableHeader)
  // ignore: unused_element
  Widget _buildHeader(BuildContext context, {int filteredCount = 0}) => const SizedBox.shrink();

    // ── FILTRES AVANCES ────────────────────────────────────────────────────────
  Widget _buildAdvancedFilters() {
    // Listes dynamiques selon le pays sélectionné
    final provinces = AppConstants.getProvincesForCountry(_country);
    final cities = _province != null
        ? AppConstants.getCitiesForProvince(_country, _province!)
        : AppConstants.cities;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Localisation — Ville + Commune en cascade (Pays+Province déjà au-dessus)
        const Text('Localisation', style: TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        // Ville (selon province sélectionnée)
        _filterDropdown('Ville', cities, _city,
            (v) => setState(() {
              _city = v;
              _commune = null;
              _displayCount = 4;
            })),
        // Commune (cascade depuis Ville)
        if (_city != null && _city!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _filterDropdown(
            'Commune',
            AppConstants.getCommunesForCity(_city!),
            _commune,
            (v) => setState(() { _commune = v; _displayCount = 4; }),
          ),
        ],

        // Filtres avances selon categorie
        if (_hasCatRooms) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Chambres', style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              _dropFilter(
                value: _minRooms == null ? "N'importe" : '${_minRooms!}+',
                items: const ["N'importe", '1+', '2+', '3+', '4+', '5+'],
                onChanged: (v) => setState(() {
                  _minRooms = (v == "N'importe") ? null : int.parse(v!.replaceAll('+', ''));
                  _displayCount = 4;
                }),
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Salles de bain', style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              _dropFilter(
                value: _minBaths == null ? "N'importe" : '${_minBaths!}+',
                items: const ["N'importe", '1+', '2+', '3+', '4+', '5+'],
                onChanged: (v) => setState(() {
                  _minBaths = (v == "N'importe") ? null : int.parse(v!.replaceAll('+', ''));
                  _displayCount = 4;
                }),
              ),
            ])),
          ]),
        ],

        if (_hasCatBeds) ...[
          const SizedBox(height: 12),
          const Text('Nombre de lits', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField('Min lits', _minBeds?.toString() ?? '',
                (v) => setState(() => _minBeds = int.tryParse(v)))),
            const SizedBox(width: 8),
            Expanded(child: _numField('Max lits', _maxBeds?.toString() ?? '',
                (v) => setState(() => _maxBeds = int.tryParse(v)))),
          ]),
        ],

        if (_hasCatSeats) ...[
          const SizedBox(height: 12),
          const Text('Places assises', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField('Min places', _minSeats?.toString() ?? '',
                (v) => setState(() => _minSeats = int.tryParse(v)))),
            const SizedBox(width: 8),
            Expanded(child: _numField('Max places', _maxSeats?.toString() ?? '',
                (v) => setState(() => _maxSeats = int.tryParse(v)))),
          ]),
        ],

        if (_hasCatHectares) ...[
          const SizedBox(height: 12),
          const Text('Superficie (hectares)', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField('Min Ha', _minHectares?.toString() ?? '',
                (v) => setState(() => _minHectares = double.tryParse(v)))),
            const SizedBox(width: 8),
            Expanded(child: _numField('Max Ha', _maxHectares?.toString() ?? '',
                (v) => setState(() => _maxHectares = double.tryParse(v)))),
          ]),
        ],

        // Prix — dropdowns adapt\u00e9s au mode Location / Achat
        const SizedBox(height: 12),
        Builder(builder: (ctx) {
          // Taux de conversion USD → monnaie locale selon pays s\u00e9lectionn\u00e9
          final localCurrencyInfo = _getLocalCurrencyInfo(_country);
          final showConversion = localCurrencyInfo != null;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Prix', style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
              const SizedBox(width: 6),
              Text('(USD${showConversion ? " ≈ ${localCurrencyInfo!['code']}" : ""})',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
            ]),

            const SizedBox(height: 8),
            Row(children: [
              // Min — toujours affich\u00e9 (Location et Achat)
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Min', style: TextStyle(fontFamily: 'Poppins',
                    fontSize: 11, color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                _dropFilter(
                  value: _minPrice == null ? "N'importe" : _formatPriceLabelFull(_minPrice!, localCurrencyInfo),
                  items: _activeMode == 'Location'
                    ? _buildPriceItems(_priceListLocation, localCurrencyInfo)
                    : _buildPriceItems(_priceListAchat, localCurrencyInfo),
                  onChanged: (v) => setState(() {
                    _minPrice = _parsePriceLabel(v);
                    _displayCount = 4;
                  }),
                ),
              ])),
              const SizedBox(width: 12),
              // Max
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Max', style: TextStyle(fontFamily: 'Poppins',
                    fontSize: 11, color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                _dropFilter(
                  value: _maxPrice == null ? "N'importe" : _formatPriceLabelFull(_maxPrice!, localCurrencyInfo),
                  items: _activeMode == 'Location'
                    ? _buildPriceItems(_priceListLocationMax, localCurrencyInfo)
                    : _buildPriceItems(_priceListAchatMax, localCurrencyInfo),
                  onChanged: (v) => setState(() {
                    _maxPrice = _parsePriceLabel(v);
                    _displayCount = 4;
                  }),
                ),
              ])),
            ]),
          ]);
        }),

        // Équipements / Options — masqués pour les cat. sans ces caract\u00e9ristiques
        Builder(builder: (ctx) {
          final noEquip = _selectedCategory == 'Terrain \u00e0 b\u00e2tir' ||
              _selectedCategory == 'Concession' ||
              _selectedCategory == 'Propri\u00e9t\u00e9 Commerciale' ||
              _selectedCategory == 'Propri\u00e9t\u00e9 Industrielle';
          if (noEquip) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 12),
            const Text('Équipements', style: TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            _boolFilterChip(
              label: 'Parking',
              icon: Icons.local_parking_rounded,
              value: _filterParking,
              onChanged: (v) => setState(() { _filterParking = v; _displayCount = 4; }),
            ),
            const SizedBox(height: 6),
            _boolFilterChip(
              label: 'Groupe \u00c9lectrog\u00e8ne / Panneau Solaire',
              icon: Icons.electric_bolt_rounded,
              value: _filterGroupeElec,
              onChanged: (v) => setState(() { _filterGroupeElec = v; _displayCount = 4; }),
            ),
            const SizedBox(height: 6),
            _boolFilterChip(
              label: 'S\u00e9curit\u00e9 24h/24',
              icon: Icons.security_rounded,
              value: _filterSecurite,
              onChanged: (v) => setState(() { _filterSecurite = v; _displayCount = 4; }),
            ),
          ]);
        }),

        const SizedBox(height: 12),
        // Bouton reset
        OutlinedButton.icon(
          onPressed: () => setState(() { _resetFilters(); _displayCount = 4; _hasSearched = false; }),
          icon: const Icon(Icons.clear_rounded, size: 16, color: AppTheme.accentColor),
          label: const Text('Réinitialiser les filtres',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                  fontSize: 12, color: AppTheme.accentColor)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
            side: const BorderSide(color: AppTheme.accentColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    );
  }

  Widget _filterDropdown(String hint, List<String> items, String? value,
      void Function(String?) onChanged, {bool allowNull = true, String? currentValue}) {
    final safeItems = items.isEmpty ? <String>[] : items;
    // Pour allowNull=false (ex: Pays), on utilise currentValue comme valeur forcee
    final effectiveValue = !allowNull ? (currentValue ?? (safeItems.isNotEmpty ? safeItems.first : null))
        : (safeItems.contains(value) ? value : null);
    return DropdownButtonFormField<String>(
      value: effectiveValue,
      hint: Text(hint, style: const TextStyle(fontFamily: 'Poppins',
          fontSize: 12, color: AppTheme.textHint)),
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
          color: AppTheme.textPrimary),
      items: [
        if (allowNull)
          DropdownMenuItem<String>(value: null, child: Text('Tous ($hint)',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12))),
        ...safeItems.map((v) => DropdownMenuItem(value: v,
            child: Text(v, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5)),
        filled: true, fillColor: AppTheme.backgroundColor,
      ),
      isExpanded: true,
    );
  }

  Widget _numField(String label, String value, void Function(String) onChanged) {
    return TextField(
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) { onChanged(v); setState(() => _displayCount = 4); },
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(fontFamily: 'Poppins',
            fontSize: 11, color: AppTheme.textHint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5)),
        filled: true, fillColor: AppTheme.backgroundColor,
      ),
    );
  }

  // ── Dropdown filtre générique ──────────────────────────────────────────────
  Widget _dropFilter({
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButton<String>(
        value: items.contains(value) ? value : items.first,
        isExpanded: true,
        underline: const SizedBox(),
        isDense: true,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
            color: AppTheme.textPrimary),
        icon: const Icon(Icons.expand_more_rounded, size: 18,
            color: AppTheme.textSecondary),
        items: items.map((e) => DropdownMenuItem(
          value: e,
          child: Text(e, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
        )).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ── Helpers formatage prix dropdown ───────────────────────────────────────
  String _formatPriceLabel(double v) {
    // Formate sans point décimal : 1500 → "1 500 $", 10000 → "10 000 $"
    final intVal = v.toInt();
    final s = intVal.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u00a0'); // espace insécable
      buf.write(s[i]);
    }
    return '$buf \$';
  }

  double? _parsePriceLabel(String? label) {
    if (label == null || label == "N'importe") return null;
    // Supprimer le symbole $, les espaces normaux et insécables
    final cleaned = label
        .replaceAll('\$', '')
        .replaceAll(' ', '')
        .replaceAll('\u00a0', '')
        .trim();
    return double.tryParse(cleaned);
  }

  // ── Listes de prix par mode ────────────────────────────────────────────────
  // Location (loyer mensuel / nuit en USD)
  static const List<double> _priceListLocation    = [50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 2500];
  static const List<double> _priceListLocationMax = [50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 2500, 5000, 7500, 10000];

  // Achat (vente immobili\u00e8re RDC — march\u00e9 r\u00e9el)
  static const List<double> _priceListAchat = [
    5000, 8000, 10000, 15000, 20000, 25000, 30000,
    40000, 50000, 75000, 100000, 150000, 200000, 250000, 300000,
  ];
  static const List<double> _priceListAchatMax = [
    5000, 8000, 10000, 15000, 20000, 25000, 30000,
    40000, 50000, 75000, 100000, 150000, 200000, 250000, 300000,
    400000, 500000, 750000, 1000000,
  ];


  // Formate un montant pour le dropdown :
  // • RDC  → "500 $"
  // • Autre → uniquement le montant converti arrondi ex: "327 000 FCFA"
  String _formatPriceLabelFull(double v, Map<String, dynamic>? localCurrencyInfo) {
    if (localCurrencyInfo == null) return _formatPriceLabel(v);
    final localStr = _formatLocalAmount(v, localCurrencyInfo);
    return '$localStr ${localCurrencyInfo["code"]}';
  }

  // Construit la liste compl\u00e8te des items pour un dropdown (N'importe + chaque prix)
  List<String> _buildPriceItems(List<double> prices, Map<String, dynamic>? localCurrencyInfo) {
    return [
      "N'importe",
      ...prices.map((p) => _formatPriceLabelFull(p, localCurrencyInfo)),
    ];
  }

  // ── Conversion USD → monnaie locale ──────────────────────────────────────
  // Retourne null si le pays s\u00e9lectionn\u00e9 est la RDC (affichage USD uniquement)
  Map<String, dynamic>? _getLocalCurrencyInfo(String country) {
    const Map<String, Map<String, dynamic>> currencyMap = {
      'Congo (Brazzaville)': {'code': 'FCFA', 'rate': 655.0,   'decimals': 0},
      'Angola':              {'code': 'AOA',  'rate': 900.0,   'decimals': 0},
      'Rwanda':              {'code': 'RWF',  'rate': 1300.0,  'decimals': 0},
      'Burundi':             {'code': 'BIF',  'rate': 2850.0,  'decimals': 0},
      'Tanzanie':            {'code': 'TZS',  'rate': 2500.0,  'decimals': 0},
      'Zambie':              {'code': 'ZMW',  'rate': 27.0,    'decimals': 2},
      'Autre':               {'code': 'USD',  'rate': 1.0,     'decimals': 2},
    };
    if (country == AppConstants.defaultCountry || country.isEmpty) return null;
    return currencyMap[country]; // null si pays non trouv\u00e9 (affiche USD seulement)
  }

  // Formate un montant converti, arrondi au multiple de 1 000 le plus proche
  // Ex: 50 USD × 655 = 32 750 → arrondi → 33 000
  String _formatLocalAmount(double usdAmount, Map<String, dynamic> info) {
    final rate = (info['rate'] as double);
    final decimals = (info['decimals'] as int);
    final converted = usdAmount * rate;
    if (decimals == 0) {
      // Arrondir au multiple de 1 000
      final rounded = ((converted / 5000).round() * 5000);
      // Formater avec espaces insécables comme séparateurs de milliers
      final s = rounded.toString();
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u00a0');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return converted.toStringAsFixed(decimals);
  }

  // Chip tri-état : null=tous / true=oui / (on ne propose que null/true ici)
  Widget _boolFilterChip({
    required String label,
    required IconData icon,
    required bool? value,
    required void Function(bool?) onChanged,
  }) {
    final active = value == true;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: () => onChanged(active ? null : true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accentColor.withValues(alpha: 0.12)
              : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppTheme.accentColor : AppTheme.dividerColor,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(icon,
              size: 16,
              color: active ? AppTheme.accentColor : AppTheme.textHint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? AppTheme.accentColor : AppTheme.textSecondary)),
          ),
          Icon(
            active ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 16,
            color: active ? AppTheme.accentColor : AppTheme.textHint,
          ),
        ]),
      ),
    ));
  }

  // ── GRILLE RESPONSIVE : colonnes de 400px, 1 col min si écran < 400px ──
  Widget _buildGrid(BuildContext context, List<PropertyModel> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = (width / 400).floor().clamp(1, 99);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 400 / 450,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final p = items[index];
              return PropertyCard(
                property: p,
                isFavorite: _favorites.contains(p.id),
                onFavorite: () => _toggleFavorite(p.id),
                onShare: () => _shareProperty(p),
                selectedCountry: _country,
                onTap: () async {
                  await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p)));
                  if (mounted) _loadData();
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Construit la grille principale unifiée annonces + publicités.
  ///
  /// Les publicités occupent exactement 1 slot de grille (400×450, gridMode: true),
  /// intercalées parmi les annonces :
  ///   • 0–4 annonces → 1 pub après la dernière annonce
  ///   • 5+ annonces  → 2 pubs : après l'index 3 + après la dernière
  ///
  /// Rotation : chaque chargement avance _adRotationIndex de +1 ou +2.
  Widget _buildGridWithAds(BuildContext context, List<PropertyModel> items) {
    if (_liveAds.isEmpty) return _buildGrid(context, items);

    final n = items.length;
    final totalAds = _liveAds.length;
    final twoAds = n >= 5;

    // Sélectionner la ou les pubs de cette session
    final AdModel adFirst  = _liveAds[_adRotationIndex % totalAds];
    final AdModel adSecond = _liveAds[(_adRotationIndex + 1) % totalAds];

    // Avancer l'index pour le prochain chargement et persister
    _persistAdRotation(twoAds ? 2 : 1);

    // ── Construire la liste mixte (PropertyModel | AdModel) ─────────────────
    final List<Object> mixedItems = [];
    if (twoAds) {
      mixedItems.addAll(items.sublist(0, 4));
      mixedItems.add(adFirst);
      mixedItems.addAll(items.sublist(4));
      mixedItems.add(adSecond);
    } else {
      mixedItems.addAll(items);
      mixedItems.add(adFirst);
    }

    // ── Un seul GridView responsive avec slots mixtes ────────────────────────
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final cols = (constraints.maxWidth / 400).floor().clamp(1, 99);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 400 / 450,
            ),
            itemCount: mixedItems.length,
            itemBuilder: (gridCtx, i) {
              final item = mixedItems[i];
              if (item is AdModel) {
                // Slot publicitaire — même taille qu'une annonce
                return AdBannerCard(
                  key: ValueKey('ad_${item.id}_$i'),
                  ad: item,
                  gridMode: true,
                );
              }
              // Slot annonce normale
              final p = item as PropertyModel;
              return PropertyCard(
                property: p,
                isFavorite: _favorites.contains(p.id),
                onFavorite: () => _toggleFavorite(p.id),
                onShare: () => _shareProperty(p),
                selectedCountry: _country,
                onTap: () async {
                  await Navigator.push(gridCtx,
                      MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p)));
                  if (mounted) _loadData();
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Persiste l'index de rotation dans shared_preferences
  void _persistAdRotation(int advance) {
    if (_liveAds.isEmpty) return;
    final next = (_adRotationIndex + advance) % _liveAds.length;
    SharedPreferences.getInstance().then(
        (p) => p.setInt(_kAdRotKey, next));
  }

  // ── ANNONCES RECENTES (quand la categorie n'a pas de resultat) ──────────
  List<PropertyModel> _getRecentListings() {
    final provider = context.read<PropertyProvider>();
    final now = DateTime.now();
    return provider.properties
        .where((p) {
          // Meme logique de visibilite : actif + vendues/occupees dans 72h
          final visible = (p.status == 'Actif' && !p.isSold && !p.isRented) ||
              ((p.isSold || p.isRented) && p.updatedAt != null &&
                  now.difference(p.updatedAt!).inHours < AppConstants.soldAutoDeleteHours);
          if (!visible) return false;
          return (_activeMode == 'Location' && p.transactionType == 'Location') ||
              (_activeMode == 'Achat' && p.transactionType == 'Vente');
        })
        .toList()
        ..sort((a, b) {
          final aDate = a.updatedAt ?? a.createdAt;
          final bDate = b.updatedAt ?? b.createdAt;
          return bDate.compareTo(aDate);
        });
  }

  Widget _buildEmptyWithSimilar(List<PropertyModel> similar) {
    final bool hasActiveFilter = _searchQuery.isNotEmpty || _hasSearched ||
        _province != null || _city != null ||
        _commune != null || _minRooms != null || _minBaths != null ||
        _minPrice != null || _maxPrice != null ||
        _minSeats != null || _maxSeats != null || _minBeds != null ||
        _maxBeds != null || _minHectares != null || _maxHectares != null ||
        _filterParking != null || _filterGroupeElec != null || _filterSecurite != null;

    // Si aucune recherche active → afficher les annonces récentes
    if (!hasActiveFilter) {
      final recent = _getRecentListings();
      if (recent.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              const Text('Annonces récentes',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 14, color: AppTheme.textPrimary)),
            ]),
            const SizedBox(height: 10),
            _buildGrid(context, recent.take(8).toList()),
          ]),
        );
      }
      // Aucune annonce du tout dans cette catégorie/mode
      return const SizedBox.shrink();
    }

    // Recherche active mais aucun résultat
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.warningColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded,
                color: AppTheme.warningColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _searchQuery.isNotEmpty
                    ? 'Aucun résultat pour "$_searchQuery" en $_activeMode. Essayez un autre mot-clé.'
                    : 'Aucune annonce ne correspond à vos critères pour "$_selectedCategory" en $_activeMode.',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    color: AppTheme.warningColor, height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Row(children: [
          const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.accentColor),
          const SizedBox(width: 6),
          const Text('Annonces récentes',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 14, color: AppTheme.textPrimary)),
        ]),
        const SizedBox(height: 10),
        _buildGrid(context, _getRecentListings().take(4).toList()),
      ]),
    );
  }

  // ── VOIR PLUS ─────────────────────────────────────────────────────────────
  Widget _buildVoirPlus(int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: OutlinedButton(
        onPressed: () => setState(() => _displayCount += 8),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 46),
          side: const BorderSide(color: AppTheme.accentColor, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.expand_more_rounded, color: AppTheme.accentColor, size: 20),
          const SizedBox(width: 8),
          Text('Voir plus (${total - _displayCount} annonces restantes)',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 13, color: AppTheme.accentColor)),
        ]),
      ),
    );
  }

  // ── STATS FOOTER ──────────────────────────────────────────────────────────
  Widget _buildStatsFooter() {
    return Column(children: [
      // ── Tableau 1 : Disponibilités ──────────────────────────────────────
      _buildStatsCard(
        icon: Icons.store_rounded,
        accentIconColor: const Color(0xFFFFA726),     // icône container orange
        title: 'Marché Immobilier — Disponibilités',
        tooltipMsg: 'Cliquez sur une catégorie pour filtrer les annonces',
        rows: !_statsLoading ? [
          _statRow('Maisons en vente',                    _stats['maisonVente'] ?? 0,        AppTheme.accentColor,
              typeFilter: 'Maison',                   transactionFilter: 'Vente'),
          _statRow('Maisons en location',                 _stats['maisonLocation'] ?? 0,     const Color(0xFF4FC3F7),
              typeFilter: 'Maison',                   transactionFilter: 'Location'),
          _statRow('Appartements en vente',               _stats['appartVente'] ?? 0,        AppTheme.accentColor,
              typeFilter: 'Appartement / flat',        transactionFilter: 'Vente'),
          _statRow('Appartements en location',            _stats['appartLocation'] ?? 0,     const Color(0xFF4FC3F7),
              typeFilter: 'Appartement / flat',        transactionFilter: 'Location'),
          _statRow('Bureaux en location',                 _stats['bureauLocation'] ?? 0,     const Color(0xFFA0C4FF),
              typeFilter: 'Bureau',                   transactionFilter: 'Location'),
          _statRow('Bureaux en vente',                    _stats['bureauVente'] ?? 0,        const Color(0xFFA0C4FF),
              typeFilter: 'Bureau',                   transactionFilter: 'Vente'),
          _statRow('Propriétés commerciales',             _stats['propCommerciale'] ?? 0,    Colors.teal.shade300,
              typeFilter: 'Propriété commerciale'),
          _statRow('Propriétés industrielles',            _stats['propIndustrielle'] ?? 0,   Colors.teal.shade200,
              typeFilter: 'Propriété industrielle'),
          _statRow('Terrains disponibles',                _stats['terrainDispo'] ?? 0,       AppTheme.warningColor,
              typeFilter: 'Terrain à bâtir',         transactionFilter: 'Vente'),
          _statRow('Concessions disponibles',             _stats['concessionDispo'] ?? 0,    Colors.orange.shade200,
              typeFilter: 'Concession'),
          _statRow('Chambres d’hôtel en location',       _stats['chambreHotel'] ?? 0,       Colors.pink.shade200,
              typeFilter: 'Chambre d’hôtel',          transactionFilter: 'Location'),
          _statRow('Salles des fêtes disponibles',        _stats['salleFetes'] ?? 0,         Colors.purple.shade300,
              typeFilter: 'Salle de fêtes'),
          _statRow('Salles polyvalentes disponibles',      _stats['sallePolyvalente'] ?? 0,   Colors.purple.shade200,
              typeFilter: 'Salle polyvalente'),
          _statRow('Espaces funéraires disponibles',      _stats['espaceFuneraire'] ?? 0,    Colors.blueGrey.shade300,
              typeFilter: 'Espace funéraire'),
          const Divider(height: 1, color: Colors.white12),
          _statRow('Total annonces actives',              _stats['totalActif'] ?? 0,         AppTheme.accentColor,
              total: true),
        ] : [],
      ),

      const SizedBox(height: 10),

      // ── Tableau 2 : Historique 3 jours ──────────────────────────────────────
      _buildStatsCard(
        icon: Icons.history_rounded,
        title: 'Historique des 3 derniers jours',
        tooltipMsg: 'Biens vendus ou occupés — cliquez pour voir les annonces',
        headerColor: const Color(0xFFE65100), // orange foncé professionnel
        accentIconColor: AppTheme.primaryColor,
        rows: !_statsLoading ? [
          _statRow('Maisons vendues',          _stats['hist72_maisonVendue'] ?? 0,  Colors.orange.shade300,
              typeFilter: 'Maison',          transactionFilter: 'Vente',    initialHistorique: true),
          _statRow('Maisons occupées',         _stats['hist72_maisonOccupee'] ?? 0, Colors.amber.shade300,
              typeFilter: 'Maison',          transactionFilter: 'Location', initialHistorique: true),
          _statRow('Terrains vendus',          _stats['hist72_terrainVendu'] ?? 0,  Colors.orange.shade200,
              typeFilter: 'Terrain à bâtir', transactionFilter: 'Vente',    initialHistorique: true),
          _statRow('Appartements vendus',      _stats['hist72_appartVendu'] ?? 0,   Colors.orange.shade300,
              typeFilter: 'Appartement / flat', transactionFilter: 'Vente',  initialHistorique: true),
          _statRow('Appartements occupés',     _stats['hist72_appartOccupe'] ?? 0,  Colors.amber.shade300,
              typeFilter: 'Appartement / flat', transactionFilter: 'Location', initialHistorique: true),
          _statRow('Bureaux occupés',          _stats['hist72_bureauOccupe'] ?? 0,  Colors.orange.shade200,
              typeFilter: 'Bureau',          transactionFilter: 'Location', initialHistorique: true),
          _statRow('Salles occupées',          _stats['hist72_salleOccupee'] ?? 0,  Colors.amber.shade200,
              typeFilter: 'Salle de fêtes',                                 initialHistorique: true),
          const Divider(height: 1, color: Colors.white12),
          _statRow('Total transactions récentes', _stats['hist72_total'] ?? 0,     Colors.amber.shade300,
              total: true),
        ] : [],
      ),
    ]);
  }

  // ── Carte stats réutilisable ─────────────────────────────────────────────
  Widget _buildStatsCard({
    required IconData icon,
    required String title,
    required String tooltipMsg,
    required List<Widget> rows,
    Color? headerColor,
    Color? accentIconColor,
    IconData? titleIcon, // petite icône optionnelle affichée à côté du titre
  }) {
    final Color iconColor = accentIconColor ?? AppTheme.accentColor;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        color: headerColor ?? AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: iconColor.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        // En-tête
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(title,
                      style: const TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 13, color: Colors.white)),
                ),
                if (titleIcon != null) ...
                  [const SizedBox(width: 6),
                   Icon(titleIcon, color: const Color(0xFFFFA726), size: 10)],
              ]),
            ),
            if (_statsLoading)
              SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: iconColor, strokeWidth: 2))
            else
              Tooltip(
                message: tooltipMsg,
                child: Icon(Icons.touch_app_rounded,
                    color: iconColor.withValues(alpha: 0.8), size: 16),
              ),
          ]),
        ),
        if (!_statsLoading && rows.isNotEmpty) ...[
          const Divider(height: 1, color: Colors.white12),
          ...rows,
          const SizedBox(height: 8),
        ],
      ]),
    );
  }

  Widget _statRow(
    String label,
    int count,
    Color color, {
    bool total = false,
    String? typeFilter,
    String? transactionFilter,
    bool initialHistorique = false, // true pour les lignes Historique 72h
  }) {
    final bool clickable = !total && (typeFilter != null || transactionFilter != null);

    Widget row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: total ? 10 : 6),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            if (clickable) ...
              [const Icon(Icons.arrow_forward_ios_rounded,
                  size: 10, color: Colors.white38),
              const SizedBox(width: 5)],
            Expanded(
              child: Text(label,
                  style: TextStyle(fontFamily: 'Poppins',
                      fontSize: total ? 13 : 12,
                      fontWeight: total ? FontWeight.w700 : FontWeight.w400,
                      color: total ? Colors.white : Colors.white70)),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: total ? 0.25 : 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text('$count',
              style: TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: total ? 14 : 12,
                  color: Colors.white)),
        ),
      ]),
    );

    if (!clickable) return row;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        splashColor: color.withValues(alpha: 0.15),
        highlightColor: color.withValues(alpha: 0.08),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SearchScreen(
              initialType: typeFilter,
              initialTransaction: transactionFilter,
              initialHistorique: initialHistorique,
            ),
          ),
        ),
        child: row,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DASHBOARD UTILISATEUR CONNECTE
// ══════════════════════════════════════════════════════════════════════════════
class _UserDashboardScreen extends StatefulWidget {
  const _UserDashboardScreen();
  @override
  State<_UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<_UserDashboardScreen> {
  final DataService _ds = DataService();
  List<PropertyModel> _myProperties = [];
  bool _loading = true;
  int _availableCredits = 0;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = _ds.currentUserId;
    final credits = await _ds.getUserAvailableCredits(userId);
    final all = await _ds.getUserProperties(userId);
    await _checkAutoDelete(all);
    final updated = await _ds.getUserProperties(userId);
    if (mounted) setState(() {
      _availableCredits = credits;
      _myProperties = updated;
      _loading = false;
    });
  }

  Future<void> _checkAutoDelete(List<PropertyModel> props) async {
    final now = DateTime.now();
    for (final p in props) {
      if ((p.isSold || p.isRented) && p.updatedAt != null) {
        final diff = now.difference(p.updatedAt!);
        if (diff.inHours >= AppConstants.soldAutoDeleteHours) {
          await _ds.deleteProperty(p.id);
        }
      }
    }
  }

  Future<void> _markSold(PropertyModel p) async {
    final confirmed = await _confirmDialog(
      title: 'Marquer comme vendue',
      message: 'Cette annonce sera marquée comme VENDUE et supprimée automatiquement après 72 heures.',
      confirmLabel: 'Confirmer',
      confirmColor: AppTheme.accentColor,
    );
    if (confirmed != true) return;
    await _ds.markPropertySoldOrRented(p.id, sold: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Annonce marquée comme vendue. Suppression dans 72h.',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ));
    }
    _load();
  }

  Future<void> _markOccupied(PropertyModel p) async {
    final confirmed = await _confirmDialog(
      title: 'Marquer comme occupée',
      message: 'Cette annonce sera marquée comme OCCUPÉE (bien loué). Elle sera supprimée après 72 heures.',
      confirmLabel: 'Confirmer',
      confirmColor: const Color(0xFF4FC3F7),
    );
    if (confirmed != true) return;
    await _ds.markPropertySoldOrRented(p.id, rented: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Annonce marquée comme occupée. Suppression dans 72h.',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.primaryLight,
        behavior: SnackBarBehavior.floating,
      ));
    }
    _load();
  }

  Future<void> _deleteProperty(PropertyModel p) async {
    final confirmed = await _confirmDialog(
      title: 'Supprimer l\'annonce',
      message: 'Supprimer « ${p.title} » définitivement ? Cette action est irréversible.',
      confirmLabel: 'Supprimer',
      confirmColor: AppTheme.errorColor,
    );
    if (confirmed != true) return;
    await _ds.deleteProperty(p.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Annonce supprimée.', style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
      ));
    }
    _load();
  }

  Future<bool?> _confirmDialog({
    required String title, required String message,
    required String confirmLabel, required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary)),
        content: Text(message, style: const TextStyle(fontFamily: 'Poppins',
            fontSize: 13, color: AppTheme.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmLabel,
                style: const TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // ── Garde admin : l'admin ne doit JAMAIS voir le dashboard utilisateur ───
    // Si un admin arrive ici (ex: via lien direct ou navigation résiduelle),
    // on le redirige immédiatement vers son panneau d'administration.
    if (auth.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
            (route) => false,
          );
        }
      });
      // Afficher un indicateur pendant la redirection
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.accentColor)),
      );
    }

    final user = auth.currentUser;
    final actives    = _myProperties.where((p) => p.status == 'Actif' && !p.isMarkedClosed).toList();
    final pending    = _myProperties.where((p) => p.status == 'En attente').toList();
    final closed     = _myProperties.where((p) => p.isMarkedClosed).toList();
    final rejected   = _myProperties.where((p) => p.status == 'Rejete').toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Mon Tableau de Bord',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: () async {
              await auth.logout();
              if (mounted) context.go('/');
            },
            tooltip: 'Deconnexion',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : RefreshIndicator(
              color: AppTheme.accentColor,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // ── Solde de crédits ─────────────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _availableCredits > 0
                            ? AppTheme.accentColor.withValues(alpha: 0.12)
                            : Colors.red.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _availableCredits > 0
                              ? AppTheme.accentColor
                              : Colors.red.shade300,
                          width: 1,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _availableCredits > 0
                              ? Icons.toll_rounded
                              : Icons.warning_amber_rounded,
                          color: _availableCredits > 0
                              ? AppTheme.accentColor
                              : Colors.red,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_availableCredits crédit${_availableCredits > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _availableCredits > 0
                                ? AppTheme.accentColor
                                : Colors.red,
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Statistiques rapides
                  Row(children: [
                    _statCard('Actives', actives.length, Icons.check_circle_outline_rounded,
                        AppTheme.successColor),
                    const SizedBox(width: 10),
                    _statCard('En attente', pending.length, Icons.hourglass_top_rounded,
                        AppTheme.warningColor),
                    const SizedBox(width: 10),
                    _statCard('Fermées', closed.length, Icons.lock_outline_rounded,
                        AppTheme.accentColor),
                    const SizedBox(width: 10),
                    _statCard('Rejetées', rejected.length, Icons.cancel_outlined,
                        AppTheme.errorColor),
                  ]),
                  const SizedBox(height: 24),

                  // Bouton publier
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const PostPropertyScreen()))
                          .then((_) => _load()),
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          color: Colors.white, size: 20),
                      label: const Text('Publier une nouvelle annonce',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Liste des annonces
                  _sectionTitle('Mes annonces (${_myProperties.length})'),
                  const SizedBox(height: 12),

                  if (_myProperties.isEmpty)
                    _buildEmpty()
                  else
                    ..._myProperties.map((p) => _buildPropertyCard(p)),
                ]),
              ),
            ),
    );
  }

  Widget _statCard(String label, int count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text('$count',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                  fontSize: 18, color: color)),
          Text(label, style: const TextStyle(fontFamily: 'Poppins',
              fontSize: 9, color: AppTheme.textSecondary),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
          fontSize: 15, color: AppTheme.textPrimary));

  Widget _buildEmpty() {
    return Center(
      child: Column(children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.home_work_outlined, size: 48, color: AppTheme.accentColor),
        ),
        const SizedBox(height: 16),
        const Text('Aucune annonce publi\u00e9e',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                fontSize: 15, color: AppTheme.textPrimary)),
        const SizedBox(height: 6),
        const Text('Publiez votre première annonce pour commencer.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                color: AppTheme.textSecondary)),
      ]),
    );
  }

  Widget _buildPropertyCard(PropertyModel p) {
    final isSold    = p.isSold;
    final isRented  = p.isRented;
    final isClosed  = isSold || isRented;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isSold) {
      statusColor = AppTheme.successColor;
      statusLabel = 'Vendu';
      statusIcon  = Icons.check_circle_rounded;
    } else if (isRented) {
      statusColor = const Color(0xFF4FC3F7);
      statusLabel = 'Occupé';
      statusIcon  = Icons.lock_rounded;
    } else if (p.status == 'En attente') {
      statusColor = AppTheme.warningColor;
      statusLabel = 'En attente';
      statusIcon  = Icons.hourglass_top_rounded;
    } else if (p.status == 'Rejete') {
      statusColor = AppTheme.errorColor;
      statusLabel = 'Rejeté';
      statusIcon  = Icons.cancel_rounded;
    } else {
      statusColor = AppTheme.statusActive;
      statusLabel = 'Disponible';
      statusIcon  = Icons.check_circle_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Status banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Icon(statusIcon, color: statusColor, size: 14),
            const SizedBox(width: 6),
            Text(statusLabel,
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: statusColor)),
            const Spacer(),
            Text(_formatDate(p.createdAt),
                style: const TextStyle(fontFamily: 'Poppins',
                    fontSize: 10, color: AppTheme.textHint)),
            if (isClosed) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Suppression dans 72h',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 9, color: AppTheme.errorColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        ),

        // Contenu
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Image
            PropertyImage(
              src: p.images.isNotEmpty ? p.images[0] : '',
              width: 80, height: 80,
              borderRadius: BorderRadius.circular(10),
              placeholder: _imgPlaceholder(),
            ),
            const SizedBox(width: 12),
            // Infos
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 13, color: AppTheme.textPrimary),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text('${p.type} - ${p.transactionType}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 12, color: AppTheme.textHint),
                const SizedBox(width: 2),
                Expanded(child: Text('${p.commune}, ${p.city}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 4),
              Text(p.formattedPrice,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                      fontSize: 14, color: AppTheme.accentColor)),
            ])),
          ]),
        ),

        // Actions
        if (!isClosed && p.status != 'Rejete') ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              // Marquer vendu (si vente)
              if (p.transactionType == 'Vente')
                Expanded(child: _actionButton(
                  icon: Icons.sell_rounded,
                  label: 'Marquer vendu',
                  color: AppTheme.successColor,
                  onTap: () => _markSold(p),
                )),
              // Marquer occupé (si location)
              if (p.transactionType == 'Location') ...[
                Expanded(child: _actionButton(
                  icon: Icons.lock_rounded,
                  label: 'Marquer occupé',
                  color: const Color(0xFF4FC3F7),
                  onTap: () => _markOccupied(p),
                )),
              ],
              const SizedBox(width: 8),
              // Bouton Modifier — disponible seulement dans les 24h après publication
              Builder(builder: (ctx) {
                final age = DateTime.now().difference(p.createdAt);
                final canEdit = age.inHours < 24;
                return _iconAction(
                  Icons.edit_outlined,
                  canEdit ? AppTheme.accentColor : AppTheme.textHint,
                  canEdit
                      ? () async {
                          final updated = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditPropertyScreen(property: p),
                            ),
                          );
                          if (updated == true && mounted) _load();
                        }
                      : () {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(
                              age.inHours == 0
                                  ? 'Modification disponible uniquement dans les 24h suivant la publication.'
                                  : 'Délai de modification dépassé (${age.inHours}h écoulées). La modification n\'est plus possible.',
                              style: const TextStyle(fontFamily: 'Poppins'),
                            ),
                            backgroundColor: AppTheme.textSecondary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ));
                        },
                );
              }),
              const SizedBox(width: 8),
              // Supprimer
              _iconAction(Icons.delete_outline_rounded, AppTheme.errorColor,
                  () => _deleteProperty(p)),
            ]),
          ),
        ] else if (isClosed) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Builder(builder: (ctx) {
              // Calcul du temps ecoulé depuis la fermeture
              final closedAt = p.updatedAt ?? p.createdAt;
              final elapsed = DateTime.now().difference(closedAt);
              final canDelete = elapsed.inHours >= AppConstants.soldAutoDeleteHours;
              final hoursLeft = AppConstants.soldAutoDeleteHours - elapsed.inHours;

              return Row(children: [
                const Icon(Icons.schedule_rounded, size: 14, color: AppTheme.textHint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    canDelete
                        ? 'Vous pouvez maintenant supprimer cette annonce.'
                        : 'Suppression disponible dans ${hoursLeft}h.',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11,
                      color: canDelete ? AppTheme.errorColor : AppTheme.textHint,
                      fontStyle: FontStyle.italic,
                      fontWeight: canDelete ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                // Bouton supprimer uniquement disponible après 72h
                if (canDelete)
                  _iconAction(Icons.delete_outline_rounded, AppTheme.errorColor,
                      () => _deleteProperty(p))
                else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.textHint.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.textHint.withValues(alpha: 0.15)),
                    ),
                    child: const Icon(Icons.lock_clock_outlined,
                        color: AppTheme.textHint, size: 18),
                  ),
              ]);
            }),
          ),
        ],
      ]),
    );
  }

  Widget _actionButton({
    required IconData icon, required String label,
    required Color color, required VoidCallback onTap,
  }) {
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 11, color: color)),
        ]),
      ),
    ));
  }

  Widget _iconAction(IconData icon, Color color, VoidCallback onTap) {
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    ));
  }

  Widget _imgPlaceholder() => Container(
    width: 80, height: 80,
    decoration: BoxDecoration(
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.home_outlined, size: 32, color: AppTheme.accentColor),
  );

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ═══════════════════════════════════════════════════════════════════════════════
// ÉCRAN RÉGLAGES — Photo de profil + Message d'accueil
// ═══════════════════════════════════════════════════════════════════════════════

class _UserReglagesScreen extends StatefulWidget {
  const _UserReglagesScreen();
  @override
  State<_UserReglagesScreen> createState() => _UserReglagesScreenState();
}

class _UserReglagesScreenState extends State<_UserReglagesScreen> {
  final DataService _ds = DataService();
  bool _uploadingPhoto = false;
  bool _savingDesc     = false;
  bool _editingDesc    = false;
  static const int _maxDescChars = 1000;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final u = context.read<AuthProvider>().currentUser;
      _descCtrl.text = u?.description ?? '';
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Photo upload ─────────────────────────────────────────────────────────────
  Future<void> _pickAndUploadPhoto(AuthProvider auth) async {
    final user = auth.currentUser;
    if (user == null) return;
    final picker = ImagePicker();
    try {
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50, maxWidth: 512, maxHeight: 512,
      );
      if (picked == null) return;
      setState(() => _uploadingPhoto = true);
      final Uint8List bytes = kIsWeb
          ? await picked.readAsBytes()
          : await File(picked.path).readAsBytes();
      final ext = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      final dataUrl = 'data:image/$ext;base64,${base64Encode(bytes)}';
      final updatedUser = user.copyWith(avatar: dataUrl);
      await _ds.updateUser(updatedUser);
      auth.updateCurrentUserLocally(updatedUser);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Photo mise à jour !',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        setState(() {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Description save ─────────────────────────────────────────────────────────
  Future<void> _saveDescription(AuthProvider auth) async {
    final user = auth.currentUser;
    if (user == null) return;
    setState(() => _savingDesc = true);
    try {
      final updatedUser = user.copyWith(description: _descCtrl.text.trim());
      await _ds.updateUser(updatedUser);
      auth.updateCurrentUserLocally(updatedUser);
      if (mounted) setState(() => _editingDesc = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Message d\'accueil enregistré !',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _savingDesc = false);
    }
  }

  // ── Avatar widget ─────────────────────────────────────────────────────────────
  Widget _buildAvatarWidget(UserModel? user, AuthProvider auth) {
    final avatarData = user?.avatar;
    Widget avatarInner;
    if (avatarData != null && avatarData.isNotEmpty) {
      try {
        final b64 = avatarData.contains(',') ? avatarData.split(',').last : avatarData;
        final bytes = base64Decode(b64);
        avatarInner = Image.memory(bytes, width: 100, height: 100, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsWidget(user));
      } catch (_) {
        avatarInner = _initialsWidget(user);
      }
    } else {
      avatarInner = _initialsWidget(user);
    }
    return Stack(alignment: Alignment.bottomRight, children: [
      GestureDetector(
        onTap: avatarData != null && avatarData.isNotEmpty
            ? () => _showFullscreen(avatarData)
            : null,
        child: Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFA726).withValues(alpha: 0.2),
            border: Border.all(color: const Color(0xFFFFA726), width: 2.5),
          ),
          child: ClipOval(child: avatarInner),
        ),
      ),
      Positioned(
        bottom: 0, right: 0,
        child: GestureDetector(
          onTap: _uploadingPhoto ? null : () => _pickAndUploadPhoto(auth),
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppTheme.accentColor, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: _uploadingPhoto
                ? const Padding(padding: EdgeInsets.all(5),
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
          ),
        ),
      ),
    ]);
  }

  Widget _initialsWidget(UserModel? user) {
    final name = user?.name ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      color: const Color(0xFFFFA726).withValues(alpha: 0.2),
      child: Center(child: Text(initial,
          style: const TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w800, fontSize: 36,
              color: Color(0xFFFFA726)))),
    );
  }

  void _showFullscreen(String avatarData) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          InteractiveViewer(
            child: Center(child: Builder(builder: (ctx) {
              try {
                final b64 = avatarData.contains(',')
                    ? avatarData.split(',').last : avatarData;
                final bytes = base64Decode(b64);
                return Image.memory(bytes, fit: BoxFit.contain,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height);
              } catch (_) {
                return const Icon(Icons.broken_image, color: Colors.white, size: 64);
              }
            })),
          ),
          Positioned(
            top: 40, right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final descLength = _descCtrl.text.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        centerTitle: false,
        title: const Text('Réglages',
            style: TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, fontSize: 18,
                color: AppTheme.textPrimary)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE8ECF4), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Section : Photo de profil ───────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Photo de profil',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 15,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              const Text('Visible par les visiteurs sur vos annonces.',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 12, color: AppTheme.textHint)),
              const SizedBox(height: 20),
              Center(child: _buildAvatarWidget(user, auth)),
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: _uploadingPhoto ? null : () => _pickAndUploadPhoto(auth),
                  icon: const Icon(Icons.photo_library_rounded, size: 16),
                  label: const Text('Changer la photo',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.accentColor),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // ── Section : Message d'accueil ─────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Message d\'accueil',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700, fontSize: 15,
                        color: AppTheme.textPrimary)),
                if (!_editingDesc)
                  TextButton.icon(
                    onPressed: () => setState(() => _editingDesc = true),
                    icon: const Icon(Icons.edit_rounded, size: 15),
                    label: const Text('Modifier',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                  ),
              ]),
              const SizedBox(height: 4),
              const Text('Présenté sur votre profil public (max 1000 caractères).',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 12, color: AppTheme.textHint)),
              const SizedBox(height: 14),
              if (_editingDesc) ...[
                TextField(
                  controller: _descCtrl,
                  maxLines: 5,
                  maxLength: _maxDescChars,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Présentez-vous, vos services, votre expérience...',
                    hintStyle: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 12, color: AppTheme.textHint),
                    filled: true,
                    fillColor: const Color(0xFFF4F6FB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryColor),
                    ),
                    counterText: '${descLength}/$_maxDescChars',
                    counterStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
                  ),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => setState(() => _editingDesc = false),
                    child: const Text('Annuler',
                        style: TextStyle(fontFamily: 'Poppins',
                            color: AppTheme.textHint)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _savingDesc ? null : () => _saveDescription(auth),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: _savingDesc
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Enregistrer',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600)),
                  ),
                ]),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6FB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    (user?.description?.isNotEmpty == true)
                        ? user!.description!
                        : 'Aucun message d\'accueil défini.',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      color: (user?.description?.isNotEmpty == true)
                          ? AppTheme.textPrimary : AppTheme.textHint,
                      fontStyle: (user?.description?.isNotEmpty == true)
                          ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ]),
          ),

          const SizedBox(height: 16),

          // ── Section : Infos du compte (lecture seule) ───────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Informations du compte',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 15,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 16),
              _infoRow(Icons.person_rounded, 'Nom', user?.name ?? '—'),
              const Divider(height: 20),
              _infoRow(Icons.email_rounded, 'Email', user?.email ?? '—'),
              const Divider(height: 20),
              _infoRow(Icons.phone_rounded, 'Téléphone', user?.phone ?? '—'),
              const Divider(height: 20),
              _infoRow(Icons.business_center_rounded, 'Catégorie',
                  user?.category ?? '—'),
            ]),
          ),

          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 16, color: AppTheme.primaryColor),
      const SizedBox(width: 10),
      Text('$label : ',
          style: const TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w600, fontSize: 12,
              color: AppTheme.textSecondary)),
      Expanded(child: Text(value,
          style: const TextStyle(fontFamily: 'Poppins',
              fontSize: 12, color: AppTheme.textPrimary),
          overflow: TextOverflow.ellipsis)),
    ]);
  }
}
