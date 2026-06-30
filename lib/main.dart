import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/property_provider.dart';
import 'providers/message_provider.dart';
import 'services/data_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/public/home/public_home_screen.dart';
import 'screens/public/property_detail/property_deep_link_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── URL propres sans # pour le deep-linking web (/property/:id) ──────────
  usePathUrlStrategy();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Firebase App Check — debug token (APK sideload / hors Play Store) ────────
  // Désactivé sur Web : AppCheck Android ne s'applique pas au navigateur.
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
    );
  }

  // ── Désactiver reCAPTCHA visible — forcer Play Integrity (Android) ──────────
  // Sans cette ligne, Firebase Auth 5.x affiche un reCAPTCHA web dans une
  // WebView chaque fois que Play Integrity n'est pas immédiatement disponible.
  // forceRecaptchaFlow: false  → Firebase utilise toujours SafetyNet/Play Integrity
  // en priorité, jamais le reCAPTCHA visible. Si Play Integrity échoue,
  // l'OTP est quand même envoyé via silent push notification.
  if (!kIsWeb) {
    try {
      await FirebaseAuth.instance.setSettings(
        forceRecaptchaFlow: false,
        appVerificationDisabledForTesting: false,
      );
    } catch (_) {
      // Non-bloquant — l'app fonctionne même si setSettings échoue
    }
  }

  await DataService().init();

  runApp(const ImmoZoneApp());
}

class ImmoZoneApp extends StatelessWidget {
  const ImmoZoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PropertyProvider()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
      ],
      child: MaterialApp(
        title: 'ImmoZone',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/admin': (context) => const AdminHomeScreen(),
          '/public': (context) => const PublicHomeScreen(),
        },
        // ── Deep-link web : /property/:id ──────────────────────────────────
        onGenerateRoute: (settings) {
          final uri = Uri.tryParse(settings.name ?? '');
          if (uri != null &&
              uri.pathSegments.length == 2 &&
              uri.pathSegments[0] == 'property') {
            final id = uri.pathSegments[1];
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PropertyDeepLinkScreen(propertyId: id),
            );
          }
          // Fallback : accueil public
          return MaterialPageRoute(
            builder: (_) => const PublicHomeScreen(),
          );
        },
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut),
    );
    _animCtrl.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    await auth.checkAuth();
    if (!mounted) return;

    // ── Détecter un deep-link initial (ex: /property/abc123) ─────────────────
    // Si l'URL courante contient un path spécifique, on y navigue directement
    // au lieu d'écraser avec /public — sinon le deep-link serait perdu.
    final currentPath = _getInitialPath();
    if (currentPath != null && currentPath != '/' && currentPath != '/public'
        && currentPath != '/login' && currentPath != '/admin') {
      Navigator.of(context).pushReplacementNamed(currentPath);
      return;
    }

    if (auth.isLoggedIn) {
      // Tous les rôles admin (general, financier, service client) → /admin
      // AdminHomeScreen détecte ensuite le rôle et affiche l'écran approprié
      if (auth.isAnyAdmin) {
        Navigator.of(context).pushReplacementNamed('/admin');
      } else {
        Navigator.of(context).pushReplacementNamed('/public');
      }
    } else {
      // Unauthenticated users go to the public home to browse freely
      Navigator.of(context).pushReplacementNamed('/public');
    }
  }

  /// Retourne le path courant du navigateur web (ex: "/property/abc123").
  /// Retourne null sur mobile ou si le path est la racine.
  String? _getInitialPath() {
    if (!kIsWeb) return null;
    try {
      // ignore: avoid_web_libraries_in_flutter
      final path = Uri.base.path;
      if (path.isEmpty || path == '/') return null;
      return path;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo officiel ImmoZone sur fond blanc ───────────
                Image.asset(
                  'assets/images/immozone_logo.png',
                  width: 260,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_work_rounded,
                          size: 80, color: AppTheme.primaryColor),
                      const SizedBox(height: 12),
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 36, fontWeight: FontWeight.w800),
                          children: [
                            TextSpan(text: 'Immo',
                                style: TextStyle(color: AppTheme.primaryColor)),
                            TextSpan(text: 'Zone',
                                style: TextStyle(color: AppTheme.accentColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 64),

                // ── Spinner sur fond blanc ──────────────────────────
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                    strokeWidth: 2.5,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Chargement...',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textHint,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
