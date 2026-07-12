import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, Persistence;
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

  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
    );
  }

  if (kIsWeb) {
    // ── Web : forcer la persistance LOCAL (survit aux refreshs de page) ──────
    // Sans cet appel, Firebase Auth utilise SESSION par défaut sur web,
    // ce qui détruit la session à chaque refresh de page.
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } catch (_) {}
  } else {
    try {
      await FirebaseAuth.instance.setSettings(
        forceRecaptchaFlow: false,
        appVerificationDisabledForTesting: false,
      );
    } catch (_) {}
  }

  await DataService().init();

  runApp(const ImmoZoneApp());
}

// ── Détection du deep-link au démarrage (avant GoRouter) ─────────────────
// Vrai si l'URL initiale est un deep-link /property/:id
// Utilisé par GoRouter redirect ET SplashScreen pour éviter tout conflit.
bool _isDeepLink = false;

String _getInitialLocation() {
  if (kIsWeb) {
    final path = Uri.base.path;
    if (path.startsWith('/property/')) {
      _isDeepLink = true;
      return path;
    }
  }
  return '/';
}

// ── GoRouter — gère le deep-linking web de façon fiable ───────────────────
final _router = GoRouter(
  // initialLocation calculé AVANT construction du router : si deep-link, on
  // démarre directement sur /property/:id — SplashScreen n'est JAMAIS créé.
  initialLocation: _getInitialLocation(),
  redirect: (context, state) {
    // Garde supplémentaire : si GoRouter tente quand même d'aller sur '/'
    // alors que l'URL réelle est un /property/:id, on redirige immédiatement.
    if (kIsWeb && state.matchedLocation == '/') {
      final path = Uri.base.path;
      if (path.startsWith('/property/')) {
        _isDeepLink = true;
        return path;
      }
    }
    return null; // pas de redirection — GoRouter gère normalement
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminHomeScreen(),
    ),
    GoRoute(
      path: '/public',
      builder: (context, state) => const PublicHomeScreen(),
    ),
    // ── Deep-link annonce : /property/:id ──────────────────────────────────
    GoRoute(
      path: '/property/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return PropertyDeepLinkScreen(propertyId: id);
      },
    ),
  ],
  // Toute route inconnue → accueil public
  errorBuilder: (context, state) => const PublicHomeScreen(),
);

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
      child: MaterialApp.router(
        title: 'ImmoZone',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: _router,
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // ── Protection deep-link ─────────────────────────────────────────────
    if (_isDeepLink) return;
    if (kIsWeb) {
      final path = Uri.base.path;
      if (path.startsWith('/property/')) {
        _isDeepLink = true;
        return;
      }
    }

    final auth = context.read<AuthProvider>();
    final propProvider = context.read<PropertyProvider>();

    if (kIsWeb) {
      // ── WEB : l'HTML overlay gère tout le visuel du splash.
      //
      // STRATÉGIE en 2 phases pour éviter le logout sur Windows/desktop :
      //
      // Phase 1 — auth UNIQUEMENT, timeout 12s (authStateChanges 5s +
      //   getUserById 6s = 11s max ; 12s = marge confortable).
      //   Auth doit TOUJOURS terminer avant la navigation — sinon la session
      //   est perdue sur les connexions lentes (Windows/desktop).
      //
      // Phase 2 — propriétés en parallèle, timeout 6s.
      //   Si le chargement des propriétés est trop lent, on navigue quand même
      //   (les propriétés se chargeront après la navigation).
      await Future.any([
        auth.checkAuth(),
        Future.delayed(const Duration(seconds: 14)),
      ]);
      // Lancer le chargement des propriétés (non bloquant pour la navigation)
      propProvider.loadAllProperties().ignore();
    } else {
      // ── MOBILE : on affiche notre propre splash Flutter.
      // Timer 4 s minimum, auth en parallèle.
      await Future.any([
        Future.wait([
          auth.checkAuth(),
          propProvider.loadAllProperties(),
        ]),
        Future.delayed(const Duration(seconds: 4)),
      ]);
    }

    if (!mounted || _isDeepLink || _navigating) return;
    _navigating = true;

    if (auth.isLoggedIn) {
      if (auth.isAnyAdmin) {
        context.go('/admin');
      } else {
        context.go('/public');
      }
    } else {
      context.go('/public');
    }
  }

  /// Taille du logo responsive selon la largeur de l'écran (mobile).
  double _logoWidth(double screenW) {
    if (screenW < 360) return screenW * 0.72;
    if (screenW < 480) return screenW * 0.68;
    if (screenW < 768) return screenW * 0.60;
    return screenW * 0.55;
  }

  @override
  Widget build(BuildContext context) {
    // ── WEB : fond blanc pur, aucun widget Flutter visible.
    // L'HTML overlay imz-loading recouvre tout jusqu'au premier frame.
    // Dès que Flutter rend ce Scaffold blanc, l'overlay se fond en lui
    // puis disparaît — transition imperceptible, zéro double-splash.
    if (kIsWeb) {
      return const Scaffold(backgroundColor: Colors.white);
    }

    // ── MOBILE : splash Flutter classique, propre, sans animation.
    final screenW = MediaQuery.of(context).size.width;
    final logoW = _logoWidth(screenW);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/immozone_logo.png',
              width: logoW,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.home_work_rounded,
                      size: logoW * 0.35, color: AppTheme.primaryColor),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: logoW * 0.13,
                        fontWeight: FontWeight.w800,
                      ),
                      children: const [
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
            const SizedBox(height: 48),
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                color: AppTheme.primaryColor,
                strokeWidth: 2.5,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 18),
            RichText(
              textAlign: TextAlign.center,
              maxLines: 2,
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textHint,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  letterSpacing: 0.1,
                ),
                children: [
                  const TextSpan(text: 'La '),
                  TextSpan(
                    text: '1ère',
                    style: TextStyle(color: AppTheme.orangeColor),
                  ),
                  const TextSpan(
                    text: ' plateforme de l\'immobilier en RD Congo et au Congo Brazzaville',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
