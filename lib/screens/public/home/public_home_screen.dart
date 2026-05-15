import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/property_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/property_card.dart';
import '../../../core/widgets/property_image.dart';
import '../../../services/data_service.dart';
import '../../../models/property_model.dart';
import '../../../models/app_notification_model.dart';
import '../property_detail/property_detail_screen.dart';
import '../favorites/favorites_screen.dart';
import '../post_property/post_property_screen.dart';
import '../post_property/edit_property_screen.dart';
import '../../auth/login_screen.dart';
import '../../admin/admin_home_screen.dart';

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    );
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.search_rounded, Icons.search_rounded, 'Recherche'),
                _navItem(1, Icons.favorite_border_rounded, Icons.favorite_rounded, 'Favoris'),
                // Bouton publier central
                GestureDetector(
                  onTap: () => _openPublish(context, auth),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.6), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: AppTheme.accentColor.withValues(alpha: 0.25),
                            blurRadius: 8, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline_rounded,
                            color: AppTheme.accentColor, size: 18),
                        SizedBox(width: 6),
                        Text('Publier',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                              fontSize: 13, color: Colors.white,
                            )),
                      ],
                    ),
                  ),
                ),
                // Alertes (anciennement Offres)
                _navItemWithBadge(2, Icons.notifications_none_rounded, Icons.notifications_rounded, 'Alertes', _unreadNotifCount),
                // Contact (BottomSheet : WhatsApp + Appel + Email)
                GestureDetector(
                  onTap: _openContactSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_rounded,
                            color: AppTheme.textHint, size: 22),
                        SizedBox(height: 2),
                        Text('Contact',
                            style: TextStyle(
                              fontSize: 9, fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textHint,
                            )),
                      ],
                    ),
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
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        if (index == 2) _loadUnreadCount();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected ? AppTheme.accentColor : AppTheme.textHint,
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
                  color: isSelected ? AppTheme.accentColor : AppTheme.textHint,
                )),
          ],
        ),
      ),
    );
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
        backgroundColor: AppTheme.primaryColor,
        title: const Text('Notifications',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                color: Colors.white)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
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
                    return Container(
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
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
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
  int? _minRooms;
  int? _maxRooms;
  int? _minBaths;
  int? _maxBaths;
  double? _minPrice;
  double? _maxPrice;
  double? _minSurface;
  double? _maxSurface;
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
    _minRooms = _maxRooms = _minBaths = _maxBaths = null;
    _minBeds = _maxBeds = _minSeats = _maxSeats = null;
    _minPrice = _maxPrice = _minSurface = _maxSurface = null;
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
      // Mode (Location vs Achat) — toujours applique
      final modeMatch = _activeMode == 'Location'
          ? p.transactionType == 'Location'
          : p.transactionType == 'Vente';
      if (!modeMatch) return false;

      // Categorie (court-circuitee quand recherche texte active)
      if (!isTextSearch) {
        final catNorm = _normalize(_selectedCategory);
        final typeNorm = _normalize(p.type);
        if (!typeNorm.contains(catNorm) && !catNorm.contains(typeNorm)) return false;
      }

      // Pays (filtre avance — uniquement si different du defaut)
      if (_country.isNotEmpty && _country != AppConstants.defaultCountry) {
        // Le modele PropertyModel stocke le pays dans p.country
        if (!_normalize(p.country ?? '').contains(_normalize(_country)) &&
            !_normalize(_country).contains(_normalize(p.country ?? ''))) {
          return false;
        }
      }

      // Province / Ville / Commune (filtres avances optionnels)
      if (_province != null && _province!.isNotEmpty &&
          !_normalize(p.province).contains(_normalize(_province!))) return false;
      if (_city != null && _city!.isNotEmpty &&
          !_normalize(p.city).contains(_normalize(_city!))) return false;
      if (_commune != null && _commune!.isNotEmpty &&
          !_normalize(p.commune).contains(_normalize(_commune!))) return false;

      // Recherche texte — meme logique que admin/user posts :
      // titre, ville, province, type de propriété, description
      if (isTextSearch) {
        final q = _searchQuery.toLowerCase();
        if (!p.title.toLowerCase().contains(q) &&
            !p.city.toLowerCase().contains(q) &&
            !p.province.toLowerCase().contains(q) &&
            !p.type.toLowerCase().contains(q) &&
            !p.description.toLowerCase().contains(q)) return false;
      }

      // Filtres prix
      if (_minPrice != null && p.price < _minPrice!) return false;
      if (_maxPrice != null && p.price > _maxPrice!) return false;

      // Filtres chambres
      if (_minRooms != null && (p.bedrooms ?? 0) < _minRooms!) return false;
      if (_maxRooms != null && (p.bedrooms ?? 0) > _maxRooms!) return false;

      // Filtres SDB
      if (_minBaths != null && (p.bathrooms ?? 0) < _minBaths!) return false;
      if (_maxBaths != null && (p.bathrooms ?? 0) > _maxBaths!) return false;

      // Filtres surface
      if (_minSurface != null && (p.surface ?? 0) < _minSurface!) return false;
      if (_maxSurface != null && (p.surface ?? 0) > _maxSurface!) return false;

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
    context.watch<PropertyProvider>();
    final filtered = _filteredProperties;
    final displayed = filtered.take(_displayCount).toList();
    final hasMore = filtered.length > _displayCount;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(children: [
          // ── HEADER fixe ─────────────────────────────────────────────────
          _buildHeader(context),

          // ── BODY scrollable ─────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.accentColor,
              onRefresh: () async { await _loadData(); await _loadStats(); },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(children: [
                  // Filtres avances
                  if (_filtersExpanded) _buildAdvancedFilters(),

                  const SizedBox(height: 12),

                  // Liste ou etat vide
                  if (displayed.isEmpty)
                    _buildEmptyWithSimilar([])
                  else
                    _buildGrid(context, displayed),

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

  // ── HEADER ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      color: AppTheme.primaryColor,
      child: Column(children: [
        // Logo + bouton connexion
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            // Logo
            Image.asset('assets/images/app_logo.png', height: 36,
                errorBuilder: (_, __, ___) => const Text('ImmoZone',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w900,
                        fontSize: 18, color: AppTheme.accentColor))),
            const Spacer(),
            // Connexion
            Builder(builder: (ctx) {
              final auth = ctx.watch<AuthProvider>();
              if (auth.isLoggedIn) {
                return GestureDetector(
                  onTap: () {
                    // L'admin est redirigé vers son panneau, jamais vers le dashboard utilisateur
                    if (auth.isAdmin) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
                        (route) => false,
                      );
                    } else {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const _UserDashboardScreen()));
                    }
                  },
                  child: auth.isAdmin
                    // Badge spécial admin — icône bouclier, libellé "Admin"
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentColor, width: 1.5),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.admin_panel_settings_rounded,
                              color: AppTheme.accentColor, size: 16),
                          SizedBox(width: 6),
                          Text('Admin Panel',
                              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                  fontSize: 12, color: AppTheme.accentColor)),
                        ]),
                      )
                    // Bouton Mon compte standard pour les utilisateurs normaux
                    : Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.person_rounded, color: AppTheme.accentColor, size: 16),
                          const SizedBox(width: 6),
                          Text(auth.currentUser?.name.split(' ').first ?? '',
                              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                  fontSize: 12, color: AppTheme.accentColor)),
                        ]),
                      ),
                );
              }
              return GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Se connecter',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 12, color: AppTheme.primaryColor)),
                ),
              );
            }),
          ]),
        ),

        const SizedBox(height: 12),

        // Tabs Location / Achat
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _modeCtrl,
              indicator: BoxDecoration(
                color: AppTheme.accentColor,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(text: 'Location'),
                Tab(text: 'Achat'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Barre de recherche + favoris
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  onChanged: (v) => setState(() {
                    _searchQuery = v;
                    _displayCount = 4;
                    _hasSearched = v.isNotEmpty;
                  }),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Rechercher (maison, quartier...)',
                    hintStyle: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 12, color: AppTheme.textHint),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppTheme.accentColor, size: 20),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Icone favoris cote de la recherche
            GestureDetector(
              onTap: () {
                final parent = context.findAncestorStateOfType<_PublicHomeScreenState>();
                if (parent != null) {
                  parent.setState(() => parent._currentIndex = 1);
                }
              },
              child: Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Icon(Icons.favorite_border_rounded,
                          color: AppTheme.accentColor, size: 20),
                    ),
                    if (_favorites.isNotEmpty)
                      Positioned(
                        right: 6, top: 6,
                        child: Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Bouton filtres
            GestureDetector(
              onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _filtersExpanded ? AppTheme.accentColor : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.tune_rounded,
                      color: _filtersExpanded ? AppTheme.primaryColor : AppTheme.accentColor,
                      size: 18),
                  const SizedBox(width: 4),
                  Text('Filtres',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: _filtersExpanded ? AppTheme.primaryColor : AppTheme.accentColor)),
                ]),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 12),

        // Categories horizontales
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _currentCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final cat = _currentCategories[i];
              final selected = cat == _selectedCategory;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedCategory = cat;
                  _resetFilters(clearSearch: false); // garde le texte de recherche
                  _displayCount = 4;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.accentColor : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppTheme.accentColor : Colors.white30,
                    ),
                  ),
                  child: Text(cat,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 12,
                        color: selected ? AppTheme.primaryColor : Colors.white,
                      )),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),
      ]),
    );
  }

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
        // Localisation — Pays + Province + Ville en cascade
        const Text('Localisation', style: TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        // Ligne 1 : Pays (pleine largeur)
        _filterDropdown(
          'Pays',
          AppConstants.filterCountries,
          _country,
          (v) => setState(() {
            _country = v ?? AppConstants.defaultCountry;
            _province = null; // reset cascade
            _city = null;
            _displayCount = 4;
          }),
          allowNull: false,
          currentValue: _country,
        ),
        const SizedBox(height: 8),
        // Ligne 2 : Province + Ville
        Row(children: [
          Expanded(child: _filterDropdown('Province', provinces, _province,
              (v) => setState(() {
                _province = v;
                _city = null; // reset ville quand province change
                _displayCount = 4;
              }))),
          const SizedBox(width: 8),
          Expanded(child: _filterDropdown('Ville', cities, _city,
              (v) => setState(() {
                _city = v;
                _commune = null; // reset commune when ville changes
                _displayCount = 4;
              }))),
        ]),
        // Ligne 3 : Commune (cascade depuis Ville)
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
          const Text('Chambres', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField('Min chambres', _minRooms?.toString() ?? '',
                (v) => setState(() => _minRooms = int.tryParse(v)))),
            const SizedBox(width: 8),
            Expanded(child: _numField('Max chambres', _maxRooms?.toString() ?? '',
                (v) => setState(() => _maxRooms = int.tryParse(v)))),
          ]),
          const SizedBox(height: 8),
          const Text('Salles de bain', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField('Min SDB', _minBaths?.toString() ?? '',
                (v) => setState(() => _minBaths = int.tryParse(v)))),
            const SizedBox(width: 8),
            Expanded(child: _numField('Max SDB', _maxBaths?.toString() ?? '',
                (v) => setState(() => _maxBaths = int.tryParse(v)))),
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

        // Superficie (m²) — uniquement pour les catégories qui en ont besoin
        if (_hasCatSurface) ...[
          const SizedBox(height: 12),
          const Text('Superficie (m²)', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField('Min m²', _minSurface?.toString() ?? '',
                (v) => setState(() => _minSurface = double.tryParse(v)))),
            const SizedBox(width: 8),
            Expanded(child: _numField('Max m²', _maxSurface?.toString() ?? '',
                (v) => setState(() => _maxSurface = double.tryParse(v)))),
          ]),
        ],

        // Prix
        const SizedBox(height: 12),
        const Text('Prix (USD)', style: TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _numField('Prix min', _minPrice?.toString() ?? '',
              (v) => setState(() => _minPrice = double.tryParse(v)))),
          const SizedBox(width: 8),
          Expanded(child: _numField('Prix max', _maxPrice?.toString() ?? '',
              (v) => setState(() => _maxPrice = double.tryParse(v)))),
        ]),

        // Équipements / Options
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
          label: 'Groupe Électrogène / Panneau Solaire',
          icon: Icons.electric_bolt_rounded,
          value: _filterGroupeElec,
          onChanged: (v) => setState(() { _filterGroupeElec = v; _displayCount = 4; }),
        ),
        const SizedBox(height: 6),
        _boolFilterChip(
          label: 'Sécurité 24h/24',
          icon: Icons.security_rounded,
          value: _filterSecurite,
          onChanged: (v) => setState(() { _filterSecurite = v; _displayCount = 4; }),
        ),

        const SizedBox(height: 12),
        // Bouton reset
        OutlinedButton.icon(
          onPressed: () => setState(() { _resetFilters(); _displayCount = 4; _hasSearched = false; }),
          icon: const Icon(Icons.clear_rounded, size: 16, color: AppTheme.accentColor),
          label: const Text('Reinitialiser les filtres',
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

  // Chip tri-état : null=tous / true=oui / (on ne propose que null/true ici)
  Widget _boolFilterChip({
    required String label,
    required IconData icon,
    required bool? value,
    required void Function(bool?) onChanged,
  }) {
    final active = value == true;
    return GestureDetector(
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
    );
  }

  // ── LISTE 1 CARTE PAR LIGNE ───────────────────────────────────────────────
  Widget _buildGrid(BuildContext context, List<PropertyModel> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) {
          final p = items[i];
          return PropertyCard(
            property: p,
            isFavorite: _favorites.contains(p.id),
            onFavorite: () => _toggleFavorite(p.id),
            onTap: () => Navigator.push(ctx,
                MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p))),
          );
        },
      ),
    );
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
        _commune != null || _minRooms != null || _maxRooms != null ||
        _minPrice != null || _maxPrice != null || _minBaths != null ||
        _maxBaths != null || _minSurface != null || _maxSurface != null ||
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        // En-tete
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.bar_chart_rounded, color: AppTheme.accentColor, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Marche Immobilier - Disponibilites',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 13, color: Colors.white)),
            ),
            if (_statsLoading)
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: AppTheme.accentColor, strokeWidth: 2)),
          ]),
        ),
        if (!_statsLoading) ...[
          const Divider(height: 1, color: Colors.white12),
          _statRow('Maisons en vente',          _stats['maisonVente'] ?? 0,      AppTheme.accentColor),
          _statRow('Maisons en location',       _stats['maisonLocation'] ?? 0,   const Color(0xFF4FC3F7)),
          _statRow('Maisons vendues',           _stats['maisonVendue'] ?? 0,     AppTheme.successColor),
          _statRow('Terrains disponibles',      _stats['terrainDispo'] ?? 0,     AppTheme.warningColor),
          _statRow('Terrains vendus',           _stats['terrainVendu'] ?? 0,     AppTheme.successColor),
          _statRow('Appartements en vente',     _stats['appartVente'] ?? 0,      AppTheme.accentColor),
          _statRow('Appartements en location',  _stats['appartLocation'] ?? 0,   const Color(0xFF4FC3F7)),
          _statRow('Bureaux en location',       _stats['bureauLocation'] ?? 0,   const Color(0xFFA0C4FF)),
          _statRow('Salles de fetes dispo.',    _stats['salleFetes'] ?? 0,       Colors.purple.shade300),
          _statRow('Espaces funeraires dispo.', _stats['espaceFuneraire'] ?? 0,  Colors.blueGrey.shade300),
          const Divider(height: 1, color: Colors.white12),
          _statRow('Total annonces actives',    _stats['totalActif'] ?? 0,       AppTheme.accentColor, total: true),
          const SizedBox(height: 8),
        ],
      ]),
    );
  }

  Widget _statRow(String label, int count, Color color, {bool total = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: total ? 10 : 6),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(fontFamily: 'Poppins',
                  fontSize: total ? 13 : 12,
                  fontWeight: total ? FontWeight.w700 : FontWeight.w400,
                  color: total ? Colors.white : Colors.white70)),
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
                  color: color)),
        ),
      ]),
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

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = _ds.currentUserId;
    // Charger les credits disponibles
    final credits = await _ds.getUserAvailableCredits(userId);
    final all = await _ds.getUserProperties(userId);
    // Verifier et supprimer auto les annonces vendues de plus de 72h
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
      title: 'Marquer comme vendu',
      message: 'Cette annonce sera marquee comme VENDUE et supprimee automatiquement apres 72 heures.',
      confirmLabel: 'Confirmer',
      confirmColor: AppTheme.accentColor,
    );
    if (confirmed != true) return;
    await _ds.markPropertySoldOrRented(p.id, sold: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Annonce marquee comme vendue. Suppression dans 72h.',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ));
    }
    _load();
  }

  Future<void> _markOccupied(PropertyModel p) async {
    final confirmed = await _confirmDialog(
      title: 'Marquer comme occupe',
      message: 'Cette annonce sera marquee comme OCCUPEE (bien loue). Elle sera supprimee apres 72 heures.',
      confirmLabel: 'Confirmer',
      confirmColor: const Color(0xFF4FC3F7),
    );
    if (confirmed != true) return;
    await _ds.markPropertySoldOrRented(p.id, rented: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Annonce marquee comme occupee. Suppression dans 72h.',
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
      message: 'Supprimer "${p.title}" definitivement ? Cette action est irreversible.',
      confirmLabel: 'Supprimer',
      confirmColor: AppTheme.errorColor,
    );
    if (confirmed != true) return;
    await _ds.deleteProperty(p.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Annonce supprimee.', style: TextStyle(fontFamily: 'Poppins')),
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
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: () async {
              await auth.logout();
              if (mounted) Navigator.of(context).pushReplacementNamed('/');
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

                  // Profil utilisateur
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppTheme.primaryColor, AppTheme.primaryLight]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 54, height: 54,
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.accentColor, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                            style: const TextStyle(fontFamily: 'Poppins',
                                fontWeight: FontWeight.w800, fontSize: 20,
                                color: AppTheme.accentColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Nom + badge solde sur la meme ligne
                        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Expanded(
                            child: Text(user?.name ?? '',
                                style: const TextStyle(fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _availableCredits > 0
                                  ? AppTheme.accentColor.withValues(alpha: 0.85)
                                  : Colors.red.withValues(alpha: 0.85),
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
                                color: Colors.white, size: 11,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_availableCredits cr.',
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 10,
                                  fontWeight: FontWeight.w700, color: Colors.white,
                                ),
                              ),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(user?.email ?? '',
                            style: const TextStyle(fontFamily: 'Poppins',
                                fontSize: 11, color: Colors.white60)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(user?.role ?? '',
                              style: const TextStyle(fontFamily: 'Poppins',
                                  fontSize: 10, fontWeight: FontWeight.w700,
                                  color: AppTheme.accentColor)),
                        ),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Statistiques rapides
                  Row(children: [
                    _statCard('Actives', actives.length, Icons.check_circle_outline_rounded,
                        AppTheme.successColor),
                    const SizedBox(width: 10),
                    _statCard('En attente', pending.length, Icons.hourglass_top_rounded,
                        AppTheme.warningColor),
                    const SizedBox(width: 10),
                    _statCard('Fermees', closed.length, Icons.lock_outline_rounded,
                        AppTheme.accentColor),
                    const SizedBox(width: 10),
                    _statCard('Rejetees', rejected.length, Icons.cancel_outlined,
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
        const Text('Aucune annonce publiee',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                fontSize: 15, color: AppTheme.textPrimary)),
        const SizedBox(height: 6),
        const Text('Publiez votre premiere annonce pour commencer.',
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
      statusLabel = 'Occupe';
      statusIcon  = Icons.lock_rounded;
    } else if (p.status == 'En attente') {
      statusColor = AppTheme.warningColor;
      statusLabel = 'En attente';
      statusIcon  = Icons.hourglass_top_rounded;
    } else if (p.status == 'Rejete') {
      statusColor = AppTheme.errorColor;
      statusLabel = 'Rejete';
      statusIcon  = Icons.cancel_rounded;
    } else {
      statusColor = AppTheme.statusActive;
      statusLabel = 'Actif';
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
              // Marquer occupe (si location)
              if (p.transactionType == 'Location') ...[
                Expanded(child: _actionButton(
                  icon: Icons.lock_rounded,
                  label: 'Marquer occupe',
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
    return GestureDetector(
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
    );
  }

  Widget _iconAction(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
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
    );
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
