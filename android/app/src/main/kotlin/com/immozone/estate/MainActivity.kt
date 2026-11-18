package com.immozone.estate

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    // ── Sécurité : interdiction des captures d'écran ─────────────────────────
    // FLAG_SECURE bloque screenshots + enregistrement d'écran + aperçu dans
    // les applis récentes, sur TOUTES les versions d'Android.
    // Sur Android 14+ (API 34), on détecte en plus la TENTATIVE de capture
    // pour afficher un message sympa à l'utilisateur.

    private var captureCallback: Activity.ScreenCaptureCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= 34) {
            // try/catch de sécurité : si la permission DETECT_SCREEN_CAPTURE
            // manque ou qu'un OEM se comporte mal, on NE crashe JAMAIS —
            // FLAG_SECURE protège déjà, le toast est juste un bonus UX.
            try {
                val cb = Activity.ScreenCaptureCallback {
                    Toast.makeText(
                        this,
                        "\uD83D\uDE0A Pour protéger les annonces et vos données, " +
                            "ImmoZone n'autorise pas les captures d'écran. " +
                            "Partagez plutôt l'annonce via le bouton Partager !",
                        Toast.LENGTH_LONG
                    ).show()
                }
                registerScreenCaptureCallback(mainExecutor, cb)
                captureCallback = cb
            } catch (_: Exception) {
                captureCallback = null
            }
        }
    }

    override fun onStop() {
        super.onStop()
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                captureCallback?.let { unregisterScreenCaptureCallback(it) }
            } catch (_: Exception) {
            }
            captureCallback = null
        }
    }
}
