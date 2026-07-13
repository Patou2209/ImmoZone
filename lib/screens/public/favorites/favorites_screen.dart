import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/property_card.dart';
import '../../../core/widgets/immozone_app_bar.dart';
import '../../../models/property_model.dart';
import '../../../services/data_service.dart';
import '../../../core/constants/app_constants.dart';
import '../property_detail/property_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<PropertyModel> _favorites = [];
  bool _loading = true;
  final DataService _ds = DataService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final favIds = await _ds.getFavorites();
    final all = await _ds.getActiveProperties();
    if (mounted) {
      setState(() {
        _favorites = all.where((p) => favIds.contains(p.id)).toList();
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite(String id) async {
    await _ds.toggleFavorite(id);
    await _load();
  }

  Future<void> _shareProperty(PropertyModel p) async {
    final ref = 'IZ${p.id.length >= 4 ? p.id.substring(p.id.length - 4).toUpperCase() : p.id.toUpperCase()}';
    final link = '${AppConstants.webBaseUrl}/property/${p.id}';
    final text = '${p.title} — Réf. $ref\n$link';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: ImmoZoneAppBar(
        title: 'Mes Favoris',
        extraActions: [
          if (_favorites.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${_favorites.length}',
                  style: const TextStyle(
                    color: AppTheme.accentColor,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite_outline,
                            size: 64, color: Colors.red),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Aucun favori pour l\'instant',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ajoutez des biens à vos favoris\nen cliquant sur le cœur',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontFamily: 'Poppins',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.accentColor,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _favorites.length,
                    itemBuilder: (ctx, i) {
                      final p = _favorites[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: PropertyCard(
                          property: p,
                          isFavorite: true,
                          onFavorite: () => _toggleFavorite(p.id),
                          onShare: () => _shareProperty(p),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    PropertyDetailScreen(property: p)),
                          ).then((_) => _load()),
                        ),
                      );
                    },
                  ),
                ),
      ),
    );
  }
}
