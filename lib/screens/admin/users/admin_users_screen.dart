import 'package:flutter/material.dart';
import '../../../services/data_service.dart';
import '../../../models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final DataService _dataService = DataService();
  List<UserModel> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final users = await _dataService.getUsers();
      setState(() {
        _users = users.where((u) => u.role != AppConstants.roleAdmin).toList();
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = 'Erreur de chargement: $e';
      });
    }
  }

  List<UserModel> _filtered(String role) {
    return _users.where((u) {
      final matchRole = role == 'Tous' || u.role == role;
      final matchSearch = _searchQuery.isEmpty ||
          u.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          u.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (u.phone.contains(_searchQuery));
      return matchRole && matchSearch;
    }).toList();
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
        title: const Text('Gestion Utilisateurs'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un utilisateur...',
                    hintStyle: const TextStyle(
                        color: AppTheme.textHint, fontFamily: 'Poppins'),
                    prefixIcon: const Icon(Icons.search,
                        color: AppTheme.textHint, size: 20),
                    fillColor: const Color(0xFFEEF2FA),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              TabBar(
                controller: _tabCtrl,
                labelColor: const Color(0xFFFFA726),
                unselectedLabelColor: AppTheme.primaryColor,
                indicatorColor: const Color(0xFFFFA726),
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 12),
                tabs: [
                  Tab(text: 'Tous (${_filtered('Tous').length})'),
                  Tab(
                      text:
                          'Annonceurs (${_filtered(AppConstants.roleAnnonceur).length})'),
                  Tab(
                      text:
                          'Demandeurs (${_filtered(AppConstants.roleDemandeur).length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(_loadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: AppTheme.textSecondary,
                                fontSize: 12)),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadUsers,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer',
                            style: TextStyle(fontFamily: 'Poppins')),
                      ),
                    ],
                  ),
                )
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList('Tous'),
                _buildList(AppConstants.roleAnnonceur),
                _buildList(AppConstants.roleDemandeur),
              ],
            ),
    );
  }

  Widget _buildList(String role) {
    final items = _filtered(role);
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline,
                size: 64,
                color: AppTheme.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text('Aucun utilisateur trouvé',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Poppins')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadUsers,
      color: AppTheme.accentColor,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 72, endIndent: 16),
        itemBuilder: (context, index) {
          final user = items[index];
          return _UserTile(
            user: user,
            onToggleStatus: () async {
              await _dataService.toggleUserStatus(user.id);
              _loadUsers();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(user.isActive
                      ? 'Utilisateur désactivé'
                      : 'Utilisateur activé'),
                  backgroundColor: user.isActive
                      ? AppTheme.errorColor
                      : AppTheme.successColor,
                ));
              }
            },
            onDelete: () async {
              final confirm = await _confirmDelete(context, user.name);
              if (confirm == true) {
                await _dataService.deleteUser(user.id);
                _loadUsers();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Utilisateur supprimé'),
                        backgroundColor: AppTheme.errorColor),
                  );
                }
              }
            },
            onViewDetails: () => _showUserDetails(context, user),
          );
        },
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l\'utilisateur',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('Supprimer "$name" ? Cette action est irréversible.',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  void _showUserDetails(BuildContext context, UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.dividerColor,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.primaryColor,
                    child: Text(user.initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            fontFamily: 'Poppins')),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins')),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(user.roleLabel,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.accentColor,
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: user.isActive
                                  ? AppTheme.successColor.withValues(alpha: 0.1)
                                  : AppTheme.errorColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              user.isActive ? 'Actif' : 'Inactif',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: user.isActive
                                      ? AppTheme.successColor
                                      : AppTheme.errorColor,
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _detailRow(Icons.email_outlined, 'Email', user.email),
              _detailRow(Icons.phone_outlined, 'Téléphone', user.phone),
              if (user.city != null)
                _detailRow(Icons.location_city, 'Ville', user.city!),
              if (user.commune != null)
                _detailRow(Icons.location_on_outlined, 'Commune', user.commune!),
              _detailRow(Icons.calendar_today, 'Membre depuis',
                  '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}'),
              if (user.role == AppConstants.roleAnnonceur)
                _detailRow(Icons.home_outlined, 'Annonces publiées',
                    '${user.totalProperties}'),
              _detailRow(
                  Icons.verified_outlined,
                  'Vérifié',
                  user.isVerified ? 'Oui' : 'Non'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accentColor),
          const SizedBox(width: 12),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                  color: AppTheme.textPrimary)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'Poppins',
                    color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;
  final VoidCallback onViewDetails;

  const _UserTile({
    required this.user,
    required this.onToggleStatus,
    required this.onDelete,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: user.role == AppConstants.roleAnnonceur
                ? AppTheme.primaryColor
                : AppTheme.secondaryColor,
            child: Text(user.initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins')),
          ),
          if (!user.isActive)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: AppTheme.errorColor,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white, width: 1.5)),
              ),
            )
          else
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: AppTheme.successColor,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white, width: 1.5)),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(user.name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    color: AppTheme.textPrimary)),
          ),
          if (user.isVerified)
            const Icon(Icons.verified,
                color: AppTheme.accentColor, size: 16),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.email,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontFamily: 'Poppins')),
          Text(user.phone,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textHint,
                  fontFamily: 'Poppins')),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
        onSelected: (value) {
          if (value == 'details') onViewDetails();
          if (value == 'toggle') onToggleStatus();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
              value: 'details',
              child: Row(children: [
                Icon(Icons.info_outline, size: 18, color: AppTheme.accentColor),
                SizedBox(width: 10),
                Text('Voir détails',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              ])),
          PopupMenuItem(
              value: 'toggle',
              child: Row(children: [
                Icon(
                  user.isActive ? Icons.block : Icons.check_circle_outline,
                  size: 18,
                  color: user.isActive
                      ? AppTheme.warningColor
                      : AppTheme.successColor,
                ),
                const SizedBox(width: 10),
                Text(user.isActive ? 'Désactiver' : 'Activer',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 13)),
              ])),
          const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline,
                    size: 18, color: AppTheme.errorColor),
                SizedBox(width: 10),
                Text('Supprimer',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: AppTheme.errorColor)),
              ])),
        ],
      ),
      onTap: onViewDetails,
    );
  }
}
