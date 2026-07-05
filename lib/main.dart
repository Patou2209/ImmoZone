import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
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

  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
    );
  }

  if (!kIsWeb) {
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
    // ── Protection deep-link : GoRouter ne devrait JAMAIS instancier
    // SplashScreen si l'URL est /property/:id (grâce à initialLocation +
    // redirect). Ce check est une sécurité supplémentaire.
    if (_isDeepLink) return;
    if (kIsWeb) {
      final path = Uri.base.path;
      if (path.startsWith('/property/')) {
        _isDeepLink = true;
        return;
      }
    }

    // ── Vérification auth avec timeout 3 s maximum ────────────────────────
    // On lance checkAuth() ET un timer de 3 s en parallèle.
    // On navigue dès que l'un des deux se termine en premier.
    // Plus aucun délai artificiel — l'écran splash s'affiche max 3 secondes.
    final auth = context.read<AuthProvider>();
    await Future.any([
      auth.checkAuth(),
      Future.delayed(const Duration(seconds: 3)),
    ]);
    if (!mounted || _isDeepLink) return;

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
