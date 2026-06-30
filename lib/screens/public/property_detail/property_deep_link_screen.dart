import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/data_service.dart';
import '../../../models/property_model.dart';
import 'property_detail_screen.dart';

/// Écran intermédiaire pour les deep-links web de type /property/:id
/// Il charge le PropertyModel depuis Firestore puis redirige vers PropertyDetailScreen.
class PropertyDeepLinkScreen extends StatefulWidget {
  final String propertyId;

  const PropertyDeepLinkScreen({super.key, required this.propertyId});

  @override
  State<PropertyDeepLinkScreen> createState() => _PropertyDeepLinkScreenState();
}

class _PropertyDeepLinkScreenState extends State<PropertyDeepLinkScreen> {
  final DataService _ds = DataService();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProperty();
  }

  Future<void> _loadProperty() async {
    try {
      final PropertyModel? property =
          await _ds.getPropertyById(widget.propertyId);

      if (!mounted) return;

      if (property == null) {
        setState(() {
          _error = 'Annonce introuvable.\nElle a peut-être été supprimée ou expirée.';
          _loading = false;
        });
        return;
      }

      // Remplace cet écran par PropertyDetailScreen (aucun retour possible
      // vers "l'écran de chargement")
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PropertyDetailScreen(property: property),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger l\'annonce.\nVérifiez votre connexion.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _loading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                      strokeWidth: 3,
                      backgroundColor:
                          AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Chargement de l\'annonce...',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.link_off_rounded,
                        size: 64, color: AppTheme.textHint),
                    const SizedBox(height: 20),
                    Text(
                      _error ?? 'Annonce introuvable.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                        fontFamily: 'Poppins',
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .pushReplacementNamed('/public');
                      },
                      icon: const Icon(Icons.home_rounded),
                      label: const Text(
                        'Retour à l\'accueil',
                        style: TextStyle(fontFamily: 'Poppins'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
