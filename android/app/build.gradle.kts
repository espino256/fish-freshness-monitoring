
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin must come after Android and Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// ============================================================
// AQUASENSE - ANDROID CONFIGURATION
// ============================================================

// Release application ID
val releaseApplicationId =
    System.getenv("ANDROID_APPLICATION_ID")
        ?.takeIf { it.isNotBlank() }

// Local credentials stay in the git-ignored android/key.properties file.
// Environment values take precedence for CI and existing configurations.
val releasePropertiesFile = rootProject.file("key.properties")
val releaseProperties = Properties().apply {
    if (releasePropertiesFile.isFile) {
        releasePropertiesFile.reader(Charsets.UTF_8).use { load(it) }
    }
}

fun signingValue(environmentName: String, propertyName: String): String? =
    System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: releaseProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStorePath =
    signingValue("ANDROID_KEYSTORE_PATH", "storeFile")

val releaseStorePassword =
    signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")

val releaseKeyAlias =
    signingValue("ANDROID_KEY_ALIAS", "keyAlias")

val releaseKeyPassword =
    signingValue("ANDROID_KEY_PASSWORD", "keyPassword")

// Check whether all release credentials are available.
val releaseSigningConfigured = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword
).all { !it.isNullOrBlank() }

// ============================================================
// ANDROID CONFIGURATION
// ============================================================

android {

    namespace = "com.example.aqua_sense"

    compileSdk = flutter.compileSdkVersion

    ndkVersion = flutter.ndkVersion

    // Java compilation compatibility
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ========================================================
    // APPLICATION CONFIGURATION
    // ========================================================

    defaultConfig {

        applicationId =
            releaseApplicationId ?: "com.example.aqua_sense"

        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode

        versionName = flutter.versionName
    }

    // ========================================================
    // SIGNING CONFIGURATIONS
    // ========================================================

    signingConfigs {

        // Android Gradle Plugin provides the standard
        // debug signing configuration automatically.

        // Only register release signing when all credentials
        // have been provided.
        if (releaseSigningConfigured) {

            create("release") {

                storeFile = file(releaseStorePath!!)

                storePassword = releaseStorePassword

                keyAlias = releaseKeyAlias

                keyPassword = releaseKeyPassword
            }
        }
    }

    // ========================================================
    // BUILD TYPES
    // ========================================================

    buildTypes {

        // DEBUG BUILD
        // Uses the standard Android debug signing key.
        getByName("debug") {

            signingConfig =
                signingConfigs.getByName("debug")

            isDebuggable = true
        }

        // RELEASE BUILD
        // Never fall back to the debug signing key.
        getByName("release") {

            if (releaseSigningConfigured) {

                signingConfig =
                    signingConfigs.getByName("release")

            } else {

                // Leave the release variant without a
                // signing configuration. The task-graph
                // guard below will reject release tasks.
                signingConfig = null
            }

            isDebuggable = false
        }
    }
}

// ============================================================
// RELEASE SIGNING SAFETY CHECK
// ============================================================

// Gradle configures multiple build types even when only a
// debug build is requested.
//
// Therefore, do not reject missing release credentials
// during the android { buildTypes { ... } } configuration.
//
// Check the resolved task graph instead.
//
// This also handles aggregate tasks such as "build" or
// "assemble" when they include release-variant tasks.

gradle.taskGraph.whenReady {

    val releaseTaskIncluded = allTasks.any { task ->

        task.project.path == project.path &&
            task.name.contains(
                "Release",
                ignoreCase = true
            )
    }

    if (releaseTaskIncluded && !releaseSigningConfigured) {

        throw GradleException(
            "AquaSense release signing is required. " +
                "Configure android/key.properties (see docs/ANDROID_RELEASE_GUIDE.md) " +
                "or set ANDROID_KEYSTORE_PATH, " +
                "ANDROID_KEYSTORE_PASSWORD, " +
                "ANDROID_KEY_ALIAS, and " +
                "ANDROID_KEY_PASSWORD before building " +
                "a release APK or App Bundle."
        )
    }

    if (releaseTaskIncluded && !file(releaseStorePath!!).isFile) {
        throw GradleException(
            "The AquaSense release keystore was not found. " +
                "Check storeFile in android/key.properties or ANDROID_KEYSTORE_PATH. " +
                "Relative paths are resolved from android/app."
        )
    }
}

// ============================================================
// KOTLIN COMPILER CONFIGURATION
// ============================================================

kotlin {

    compilerOptions {

        jvmTarget.set(
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        )
    }
}

// ============================================================
// FLUTTER CONFIGURATION
// ============================================================

flutter {

    source = "../.."
}
