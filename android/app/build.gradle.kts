import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release 签名从 `android/key.properties` 读。该文件不进版本库
// （见 `android/.gitignore`），本地和 CI 各自生成：CI 从 GitHub Secrets
// 解出 keystore 再写这个文件，见 `.github/workflows/release.yml`。
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.ling.cycling_app"
    // permission_handler_android 13.x 要求依赖方 compileSdk >= 37，
    // 而 flutter.compileSdkVersion 是 36，这里显式抬到 37。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ling.cycling_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 只有拿到正式 keystore 时才创建这条配置。否则留一条字段不全的
    // signingConfig，AGP 在配置阶段就会报错。
    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 没有 key.properties 时退回 debug 密钥，让本地 `flutter run --release`
            // 不必先配 keystore（沿用 Flutter 模板的默认行为）。CI 里没配 Secrets
            // 也会走到这里，构建仍然成功，但产物是 debug 签名——release.yml 会打印
            // 实际签名证书，以便分辨。
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
