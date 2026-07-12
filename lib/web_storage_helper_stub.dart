// Mobile / non-web stub — localStorage does not exist on native platforms.
// Always returns null so the caller falls back to the SplashScreen flow.

/// Stub: always returns null on non-web platforms.
String? readLocal(String key) => null;
