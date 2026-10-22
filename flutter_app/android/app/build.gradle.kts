import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val mapsProperties = Properties().apply {
    val config = rootProject.file("maps.local.properties")
    if (config.exists()) config.inputStream().use { load(it) }
}
val releaseProperties = Properties().apply {
    val config = rootProject.file("key.properties")
    if (config.exists()) config.inputStream().use { load(it) }
}
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (releaseRequested) {
    require(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
        !releaseProperties.getProperty(it).isNullOrBlank()
    }) { "Release signing is missing. Configure android/key.properties; debug keys cannot sign a release." }
    require(rootProject.file(releaseProperties.getProperty("storeFile")).isFile) {
        "Release keystore does not exist. Check storeFile in android/key.properties."
    }
}

android {
    namespace = "com.anajak.anajak_travel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.anajak.anajak_travel"
        manifestPlaceholders["MAPS_API_KEY"] = mapsProperties.getProperty("MAPS_API_KEY", "")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseProperties.getProperty("storeFile") != null) {
                storeFile = rootProject.file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
