import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload-Schlüssel für den Google Play Store.
// Die Datei android/key.properties wird NICHT ins Repository eingecheckt
// (siehe android/key.properties.example und docs/STORE_ANLEITUNG.md).
// Auf Codemagic kommen die Werte aus Umgebungsvariablen.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
fun signingValue(key: String, env: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(env)

android {
    namespace = "ch.jassmobile.jass"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // App-Kennung im Play Store. PLATZHALTER: vor dem ersten Upload festlegen,
        // danach nie mehr ändern (siehe docs/STORE_ANLEITUNG.md).
        applicationId = "ch.jassmobile.jass"
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

    signingConfigs {
        create("release") {
            val storePath = signingValue("storeFile", "CM_KEYSTORE_PATH")
            if (storePath != null) {
                storeFile = file(storePath)
                storePassword = signingValue("storePassword", "CM_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "CM_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "CM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Mit Upload-Schlüssel signieren, falls vorhanden. Sonst (nur zum
            // Testen) mit dem Debug-Schlüssel, damit der Build trotzdem klappt.
            val release = signingConfigs.getByName("release")
            signingConfig = if (release.storeFile != null) release
                else signingConfigs.getByName("debug")
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
