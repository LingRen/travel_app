package com.amap.flutter.location;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

import com.amap.api.location.AMapLocation;
import com.amap.api.location.AMapLocationClient;
import com.amap.api.location.AMapLocationClientOption;
import com.amap.api.location.AMapLocationListener;

import java.util.Map;

import io.flutter.plugin.common.EventChannel;

/**
 * @author whm
 * @date 2020-04-16 15:49
 * @mail hongming.whm@alibaba-inc.com
 */
public class AMapLocationClientImpl implements AMapLocationListener {

    private static final String TAG = "AMapLocation";

    /** 后台定位前台服务的通知通道 / 通知 id。 */
    private static final String CHANNEL_ID = "amap_location_background";
    private static final int NOTIFICATION_ID = 2001;

    private Context mContext;
    private AMapLocationClientOption locationOption = new AMapLocationClientOption();
    private AMapLocationClient locationClient = null;
    private EventChannel.EventSink mEventSink;

    private String mPluginKey;

    /** 是否在后台（锁屏）继续定位。true 时启动后台定位前台服务。 */
    private boolean mEnableBackgroundLocation = false;

    public AMapLocationClientImpl(Context context, String pluginKey, EventChannel.EventSink eventSink) {
        mContext = context;
        mPluginKey = pluginKey;
        mEventSink = eventSink;
        try {
            if (null == locationClient) {
                locationClient = new AMapLocationClient(context);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    /**
     * 开始定位
     */
    public void startLocation() {
        try {
            if (null == locationClient) {
                locationClient = new AMapLocationClient(mContext);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        if (null != locationOption) {
            locationClient.setLocationOption(locationOption);
            locationClient.setLocationListener(this);
            locationClient.startLocation();
            if (mEnableBackgroundLocation) {
                try {
                    // 高德 SDK 默认在退后台/锁屏后暂停连续定位回调；开启后台定位后
                    // SDK 会用自己的前台服务 + 通知保持后台出点。
                    locationClient.enableBackgroundLocation(
                            NOTIFICATION_ID, buildBackgroundNotification());
                } catch (Exception e) {
                    Log.w(TAG, "enableBackgroundLocation failed", e);
                }
            }
        }
    }


    /**
     * 停止定位
     */
    public void stopLocation() {
        if (null != locationClient) {
            disableBackgroundLocation();
            locationClient.stopLocation();
            locationClient.onDestroy();
            locationClient = null;
        }
    }

    public void destroy() {
        if (null != locationClient) {
            disableBackgroundLocation();
            locationClient.onDestroy();
            locationClient = null;
        }
    }

    private void disableBackgroundLocation() {
        try {
            locationClient.disableBackgroundLocation(true);
        } catch (Exception e) {
            Log.w(TAG, "disableBackgroundLocation failed", e);
        }
    }

    /**
     * 定位回调
     *
     * @param location
     */
    @Override
    public void onLocationChanged(AMapLocation location) {
        if (null == mEventSink) {
            return;
        }
        Map<String, Object> result = Utils.buildLocationResultMap(location);
        result.put("pluginKey", mPluginKey);
        mEventSink.success(result);
    }


    /**
     * 设置定位参数
     *
     * @param optionMap
     */
    public void setLocationOption(Map optionMap) {
        if (null == locationOption) {
            locationOption = new AMapLocationClientOption();
        }

        if (optionMap.containsKey("locationInterval")) {
            locationOption.setInterval(((Integer) optionMap.get("locationInterval")).longValue());
        }

        if (optionMap.containsKey("needAddress")) {
            locationOption.setNeedAddress((boolean) optionMap.get("needAddress"));
        }

        if (optionMap.containsKey("locationMode")) {
            try {
                locationOption.setLocationMode(AMapLocationClientOption.AMapLocationMode.values()[(int) optionMap.get("locationMode")]);
            } catch (Throwable e) {
            }
        }

        if (optionMap.containsKey("geoLanguage")) {
            locationOption.setGeoLanguage(AMapLocationClientOption.GeoLanguage.values()[(int) optionMap.get("geoLanguage")]);
        }

        if (optionMap.containsKey("onceLocation")) {
            locationOption.setOnceLocation((boolean) optionMap.get("onceLocation"));
        }

        if (optionMap.containsKey("enableBackgroundLocation")) {
            mEnableBackgroundLocation = (boolean) optionMap.get("enableBackgroundLocation");
            if (mEnableBackgroundLocation) {
                // 运动记录场景：声明定位用途为 Sport，配合 enableBackgroundLocation
                // 让 SDK 在后台（锁屏）继续出点。
                locationOption.setLocationPurpose(AMapLocationClientOption.AMapLocationPurpose.Sport);
            }
        }

        if (null != locationClient) {
            locationClient.setLocationOption(locationOption);
        }
    }

    /**
     * 后台定位所需的前台服务通知。小图标复用宿主应用图标，与宿主自建的前台服务
     * 通知一致，避免插件另存一套资源。
     */
    private Notification buildBackgroundNotification() {
        NotificationManager manager =
                (NotificationManager) mContext.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = manager.getNotificationChannel(CHANNEL_ID);
            if (channel == null) {
                channel = new NotificationChannel(
                        CHANNEL_ID, "运动记录", NotificationManager.IMPORTANCE_LOW);
                manager.createNotificationChannel(channel);
            }
        }

        PendingIntent contentIntent = null;
        Intent launchIntent =
                mContext.getPackageManager().getLaunchIntentForPackage(mContext.getPackageName());
        if (launchIntent != null) {
            contentIntent = PendingIntent.getActivity(
                    mContext,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        }

        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(mContext, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(mContext);
        }
        builder.setContentTitle("运动记录中")
                .setContentText("正在记录轨迹")
                .setSmallIcon(mContext.getApplicationInfo().icon)
                .setOngoing(true);
        if (contentIntent != null) {
            builder.setContentIntent(contentIntent);
        }
        return builder.build();
    }
}
