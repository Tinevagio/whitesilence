package app.whitesilence.whitesilence

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground Service GPS — WhiteSilence
 *
 * Maintient le GPS actif quand l'écran est verrouillé ou quand l'app est
 * en arrière-plan. Sans ce service, Android 8+ suspend le stream GPS
 * dès que l'app quitte le foreground.
 *
 * Philosophie WhiteSilence :
 *   - Le service démarre quand l'app passe en arrière-plan (onPause)
 *   - Il s'arrête quand l'app revient au premier plan (onResume)
 *   - Il s'arrête aussi si l'utilisateur retire la notification
 *   - On n'utilise PAS ACCESS_BACKGROUND_LOCATION (nécessite review Google)
 *
 * Ce service ne collecte aucune donnée lui-même : il se contente de
 * maintenir le processus Flutter en vie pour que GpsService.dart
 * continue de recevoir les positions via geolocator.
 *
 * Démarré/arrêté depuis GpsService.dart via MethodChannel
 * "gps_foreground_service/control" avec les méthodes "start" et "stop".
 */
class GpsForegroundService : Service() {

    companion object {
        const val CHANNEL_ID      = "ws_gps_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP     = "app.whitesilence.STOP_GPS_SERVICE"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        // Android 14+ (targetSDK ≥ 34) : startForeground() lève une
        // SecurityException si ACCESS_FINE_LOCATION n'est pas encore granted
        // au moment de l'appel — même si la permission est déclarée dans le
        // manifest. On attrape l'exception pour éviter le crash fatal.
        // Le GPS continuera de fonctionner sans foreground service tant que
        // l'app est au premier plan ; le service sera retranté à la prochaine
        // mise en arrière-plan une fois la permission confirmée.
        try {
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (e: SecurityException) {
            android.util.Log.w("GpsFGS",
                "startForeground refusé — permission GPS non accordée : ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // L'utilisateur a swipé l'app → on arrête proprement
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun buildNotification(): Notification {
        // Intent pour ouvrir l'app au tap sur la notification
        val openIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val openPending = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Bouton "Arrêter" dans la notification
        val stopIntent = Intent(this, GpsForegroundService::class.java)
            .apply { action = ACTION_STOP }
        val stopPending = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("WhiteSilence")
            .setContentText("GPS actif — acquisition en cours")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(openPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Arrêter", stopPending)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "GPS WhiteSilence",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Maintient le GPS actif en arrière-plan"
            setShowBadge(false)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }
}
