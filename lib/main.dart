import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'web_storage_helper.dart' if (dart.library.io) 'web_storage_helper_stub.dart' as ws;
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
    // ── App Check : Play Integrity (production Play Store) ──────────────────
    // L'app doit être installée depuis le Play Store pour obtenir un verdict
    // Play Integrity valide. Pour un APK sideloadé (dev), utiliser
    // AndroidProvider.debug + debug token dans le manifest.
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
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

// ── Lecture synchrone du localStorage pour décider de la route initiale ────
// SharedPreferences web stocke ses clés sous le préfixe 'flutter.'.
// Cette lecture est synchrone (pas d'async) et se fait AVANT runApp().
String _getInitialLocation() {
  if (kIsWeb) {
    final path = Uri.base.path;

    // Deep-link /property/:id → toujours prioritaire
    if (path.startsWith('/property/')) {
      _isDeepLink = true;
      return path;
    }

    // Lire le localStorage directement (synchrone) pour savoir si
    // l'utilisateur est déjà connecté → sauter le SplashScreen.
    try {
      final isLoggedIn = ws.readLocal('flutter.is_logged_in');
      final userId     = ws.readLocal('flutter.user_id') ?? '';
      final userRole   = ws.readLocal('flutter.user_role') ?? '';
      final hasCache   = ws.readLocal('flutter.cached_user_profile') != null;

      if (isLoggedIn == 'true' && userId.isNotEmpty && hasCache) {
        // Utilisateur connu → aller directement à la bonne page.
        // L'AuthProvider rechargera le profil en arrière-plan.
        if (userRole == 'admin' ||
            userRole == 'admin_financier' ||
            userRole == 'admin_service_client') {
          return '/admin';
        }
        return '/public';
      }
    } catch (_) {
      // Pas de localStorage (SSR, incognito strict) → splash normal
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
        // ── Localisation FR : tooltips système ("Back" → "Retour", etc.) ──────
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // ── UX GLOBAL (v1.4.6) : retour haptique sur CHAQUE tap ────────────
        // Petite vibration à chaque clic (tap court sans déplacement =
        // pas de vibration pendant le scroll). L'utilisateur sent que son
        // clic a été pris en compte, plus besoin de cliquer plusieurs fois.
        builder: (context, child) =>
            _GlobalTapFeedback(child: child ?? const SizedBox.shrink()),
        routerConfig: _router,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _GlobalTapFeedback — retour haptique global sur chaque tap (v1.4.6)
// Un Listener transparent au-dessus de toute l'app : à chaque tap COURT et
// SANS déplacement (donc pas pendant un scroll/swipe), déclenche une petite
// vibration système (HapticFeedback.selectionClick — discrète).
// Zéro impact sur les gestes : le Listener n'intercepte rien, il écoute.
// ═══════════════════════════════════════════════════════════════════════════
class _GlobalTapFeedback extends StatefulWidget {
  final Widget child;
  const _GlobalTapFeedback({required this.child});

  @override
  State<_GlobalTapFeedback> createState() => _GlobalTapFeedbackState();
}

class _GlobalTapFeedbackState extends State<_GlobalTapFeedback> {
  Offset? _downPosition;
  DateTime? _downTime;

  void _onPointerDown(PointerDownEvent e) {
    _downPosition = e.position;
    _downTime = DateTime.now();
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downPosition;
    final time = _downTime;
    _downPosition = null;
    _downTime = null;
    if (down == null || time == null) return;

    // Tap court (< 350 ms) et quasi immobile (< 12 px) → c'est un CLIC,
    // pas un scroll ni un appui long.
    final moved = (e.position - down).distance;
    final elapsed = DateTime.now().difference(time).inMilliseconds;
    if (moved < 12 && elapsed < 350) {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      child: widget.child,
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
        Future.delayed(const Duration(seconds: 10)),
      ]);
      // Lancer le chargement des propriétés (non bloquant pour la navigation)
      // loadProperties() = annonces ACTIVES + avatars — exactement ce que
      // l'accueil affiche → il n'aura AUCUN nouveau fetch à faire.
      propProvider.loadProperties().ignore();
    } else {
      // ── MOBILE : on affiche notre propre splash Flutter (logo + slogan).
      // Durée GARANTIE de 5 s pour laisser le temps de lire le slogan
      // (Future.wait = on attend le timer ET le travail), avec plafond 10 s
      // si le réseau est lent (Future.any = on n'attend pas indéfiniment).
      // PERF : loadProperties() (annonces ACTIVES + avatars) est EXACTEMENT
      // ce que l'accueil affiche — le chargement se fait PENDANT les 5 s du
      // spinner et l'accueil s'affiche instantanément à l'arrivée (le cache
      // dédupliqué de DataService évite tout re-fetch).
      await Future.wait([
        Future.delayed(const Duration(seconds: 5)), // minimum incompressible
        Future.any([
          Future.wait([
            auth.checkAuth(),
            propProvider.loadProperties(),
          ]),
          Future.delayed(const Duration(seconds: 10)), // plafond réseau lent
        ]),
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
    final screenW = MediaQuery.of(context).size.width;
    final logoW   = _logoWidth(screenW);

    // Contenu splash identique sur web et mobile —
    // sur web il se superpose exactement à l'overlay HTML (même blanc, même logo),
    // donc quand l'overlay HTML disparaît au flutter-first-frame, la transition
    // est parfaitement continue : aucun blanc nu n'est visible.
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
            // Slogan dans le bleu EXACT du logo ImmoZone (uniformité visuelle)
            const Text(
              'La 1ère plateforme de l\'immobilier '
              'en RD Congo et au Congo Brazzaville',
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.logoBlue,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                height: 1.45,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
