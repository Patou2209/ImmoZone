import 'package:flutter/material.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/property_card.dart';
import '../../../core/widgets/immozone_app_bar.dart';
import '../../../models/property_model.dart';
import '../../../services/data_service.dart';
import '../property_detail/property_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

/// Représente un favori dont l'annonce n'est plus disponible
/// (clôturée : vendue/louée/expirée — ou supprimée définitivement).
class _UnavailableFavorite {
  final String id;
  final String? title;   // titre si l'annonce existe encore (clôturée)
  final bool deleted;    // true = document supprimé de la base
  const _UnavailableFavorite({required this.id, this.title, required this.deleted});
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<PropertyModel> _favorites = [];
  List<_UnavailableFavorite> _unavailable = [];
  bool _loading = true;
  final DataService _ds = DataService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Les favoris sont stockés LOCALEMENT (SharedPreferences) : aucun compte
      // n'est nécessaire — les visiteurs peuvent donc avoir des favoris.
      final favIds = await _ds.getFavorites();
      final all = await _ds.getActiveProperties();
      final available = all.where((p) => favIds.contains(p.id)).toList();
      final availableIds = available.map((p) => p.id).toSet();

      // ── Annonces favorites qui ne sont plus dans la liste active ──────────
      // On vérifie leur existence pour distinguer « clôturée » de « supprimée »
      // et afficher un texte explicatif au lieu de les faire disparaître
      // silencieusement (ou pire, provoquer une erreur).
      final missingIds = favIds.where((id) => !availableIds.contains(id)).toList();
      final unavailable = <_UnavailableFavorite>[];
      for (final id in missingIds) {
        try {
          final p = await _ds.getPropertyById(id);
          if (p == null) {
            unavailable.add(_UnavailableFavorite(id: id, deleted: true));
          } else {
            unavailable.add(_UnavailableFavorite(id: id, title: p.title, deleted: false));
          }
        } catch (_) {
          // En cas d'erreur réseau ponctuelle, considérer comme clôturée (prudent)
          unavailable.add(_UnavailableFavorite(id: id, deleted: false));
        }
      }

      if (mounted) {
        setState(() {
          _favorites = available;
          _unavailable = unavailable;
          _loading = false;
        });
      }
    } catch (_) {
      // Ne jamais crasher l'écran favoris : afficher simplement l'état vide.
      if (mounted) {
        setState(() {
          _favorites = [];
          _unavailable = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _removeUnavailable(String id) async {
    await _ds.toggleFavorite(id); // retire l'id de la liste locale
    await _load();
  }

  Future<void> _toggleFavorite(String id) async {
    await _ds.toggleFavorite(id);
    await _load();
  }

  Future<void> _shareProperty(PropertyModel p) => ShareHelper.shareProperty(p);

  /// Carte affichée à la place d'une annonce favorite qui a été clôturée
  /// (vendue, louée, expirée) ou supprimée — évite toute erreur/crash et
  /// informe clairement l'utilisateur.
  Widget _buildUnavailableCard(_UnavailableFavorite u) {
    final String message = u.deleted
        ? 'Cette annonce a été supprimée par son annonceur.'
        : 'Cette annonce a été clôturée (vendue, louée ou expirée).';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              u.deleted ? Icons.delete_outline_rounded : Icons.lock_clock_rounded,
              color: Colors.grey.shade600,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (u.title != null && u.title!.trim().isNotEmpty)
                      ? u.title!
                      : 'Annonce indisponible',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Colors.grey.shade700,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Retirer des favoris
          InkWell(
            onTap: () => _removeUnavailable(u.id),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: ImmoZoneAppBar(
        title: 'Mes favoris',
        onRefresh: _load,
        extraActions: [
          if (_favorites.isNotEmpty || _unavailable.isNotEmpty)
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
                  '${_favorites.length + _unavailable.length}',
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
          : (_favorites.isEmpty && _unavailable.isEmpty)
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
                    itemCount: _favorites.length + _unavailable.length,
                    itemBuilder: (ctx, i) {
                      if (i < _favorites.length) {
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
                      }
                      // ── Carte annonce indisponible (clôturée ou supprimée) ──
                      final u = _unavailable[i - _favorites.length];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _buildUnavailableCard(u),
                      );
                    },
                  ),
                ),
      ),
    );
  }
}
