import java.util.Properties

plugins {
    id("com.android.application")
    // @Serializable in the vendored Tachiyomi source API (eu.kanade.tachiyomi).
    id("org.jetbrains.kotlin.plugin.serialization")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The shared release key, kept out of the repo (android/key.properties,
// gitignored). Without it the release build falls back to the debug key.
// scripts/build_android.sh then re-signs with a debug -> release rotation
// lineage (scripts/lib/signing.sh) so it installs over the debug-signed app.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.kuhy.kartka"

    signingConfigs {
        if (keystoreProperties.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }
    // 37: okhttp 5.5 (extension host) requires it.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kuhy.kartka"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 28: DelegateLastClassLoader + signing certificates for the in-app
        // extension loader (com.kuhy.kartka.ext).
        minSdk = maxOf(flutter.minSdkVersion, 28)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        // scripts/build_android.sh stamps the commit: versionCode = commit
        // count, versionName = <pubspec>-<short sha> (scripts/deploy.sh checks
        // both on the phone). A plain `flutter build` keeps the pubspec values.
        versionCode = providers.gradleProperty("kartkaVersionCode").orNull?.toInt()
            ?: flutter.versionCode
        versionName = flutter.versionName +
            (providers.gradleProperty("kartkaBuild").orNull?.let { "-$it" } ?: "")
    }

    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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

// The host side of the Tachiyomi extension API that loaded Keiyoushi APKs
// link against (extensions-lib 1.6; versions follow Mihon's catalogue).
dependencies {
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
    implementation("com.squareup.okhttp3:okhttp-brotli:5.5.1")
    // Keiyoushi lib 1.6 calls okhttp3.zstd.Zstd (Mihon ships it too).
    implementation("com.squareup.okhttp3:okhttp-zstd:5.5.1")
    implementation("org.jsoup:jsoup:1.24.1")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("uy.kohesive.injekt:injekt-core:1.16.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.preference:preference-ktx:1.2.1")
    implementation("androidx.webkit:webkit:1.18.0")
}
