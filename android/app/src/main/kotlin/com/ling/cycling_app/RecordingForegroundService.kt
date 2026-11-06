package com.ling.cycling_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.content.ContextCompat

/**
 * 记录期间的前台服务。
 *
 * 高德定位插件没有自己的前台服务；熄屏后系统可能冻结进程，定位回调随之中断。
 * 系统定位由 geolocator 的前台服务负责，这里只在高德试点源生效时由 Dart 侧启停。
 */
class RecordingForegroundService : Service() {

    /**
     * 记录期 CPU 唤醒锁。
     *
     * 前台服务只保证进程不被冻结，不保证 CPU 不休眠；长时间熄屏后 CPU 会睡下去，
     * 高德 SDK 的定位更新随之停摆（官方文档明确提到黑屏 / 锁屏场景需要主动叫醒
     * CPU）。geolocator 的前台服务用 `enableWakeLock` 做了同一件事，这里补齐。
     */
    private var wakeLock: PowerManager.WakeLock? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "运动记录",
                // 常驻提示不该发声或震动，用户正在骑行。
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("运动记录中")
            .setContentText("正在记录轨迹")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            createChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // 进不了前台（通知通道异常、系统限制等）就立刻退出这次启动。
            // 不退出的话，系统会在几秒后抛
            // ForegroundServiceDidNotStartInTimeException，把整个记录进程杀掉。
            stopSelf()
            return START_NOT_STICKY
        }
        acquireWakeLock()
        // 被系统回收后尽量恢复；真正的恢复逻辑在 Dart 侧（未完成记录会重新进入）。
        return START_STICKY
    }

    /** 只在进前台成功后持有，避免服务启动被拒时还占着 CPU。 */
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:recording")
            .apply {
                // 不做引用计数：启动被重复调用也只释放一次。
                setReferenceCounted(false)
                acquire()
            }
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "cycling_app.recording"
        private const val NOTIFICATION_ID = 1

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, RecordingForegroundService::class.java),
            )
        }

        fun stop(context: Context) {
            // 直接 stopService：从后台调 startService 在 O+ 会被系统拒绝。
            context.stopService(
                Intent(context, RecordingForegroundService::class.java),
            )
        }
    }
}
