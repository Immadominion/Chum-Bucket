import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // Crashlytics needs its Gradle plugin at build time: it stamps the build id
    // the SDK checks for at startup. Collection itself is opt-in at runtime
    // (lib/core/crash/crash_reporting.dart) and off in the manifest.
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing
//
// The upload key never lives in git. Gradle reads a key.properties file from
// $CHUMBUCKET_KEY_PROPERTIES (an absolute path, e.g. on an encrypted volume)
// or, failing that, android/key.properties (gitignored). It must contain:
//
//   storeFile=/absolute/or/relative/to/key.properties/upload-keystore.jks
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
//
// The Solana dApp Store pins the signing certificate (publishing/config.yaml,
// cert_fingerprint 315b22c7...e1c7), so a release must be signed with the
// ORIGINAL upload key; scripts/build_release.sh checks the fingerprint of
// every APK it produces. A release build with no key.properties fails here
// with instructions instead of quietly producing an unsigned or wrongly
// signed APK.
//
// CHUMBUCKET_ALLOW_DEBUG_SIGNED_RELEASE=true exists ONLY so CI and local
// compile checks can prove the R8/minified release build compiles. It signs
// with the throwaway debug key, which the dApp Store would reject and which
// scripts/build_release.sh refuses.
// ---------------------------------------------------------------------------

val keyPropertiesFile: File? =
    (System.getenv("CHUMBUCKET_KEY_PROPERTIES")?.takeIf { it.isNotBlank() }?.let { File(it) }
        ?: rootProject.file("key.properties"))
        .takeIf { it.isFile }

val keyProperties = Properties().apply {
    keyPropertiesFile?.let { f -> FileInputStream(f).use { load(it) } }
}

val requiredSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingSigningKeys =
    if (keyPropertiesFile == null) requiredSigningKeys
    else requiredSigningKeys.filter { keyProperties.getProperty(it).isNullOrBlank() }

val releaseKeystore: File? =
    keyProperties.getProperty("storeFile")?.takeIf { it.isNotBlank() }?.let { path ->
        val f = File(path)
        if (f.isAbsolute) f else File(keyPropertiesFile!!.parentFile, path)
    }

val hasReleaseSigning: Boolean =
    missingSigningKeys.isEmpty() && releaseKeystore?.isFile == true

val allowDebugSignedRelease: Boolean =
    System.getenv("CHUMBUCKET_ALLOW_DEBUG_SIGNED_RELEASE") == "true"

android {
    namespace = "dev.cleva.chumbucket"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Enable core library desugaring for flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        applicationId = "dev.cleva.chumbucket"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // API 28: privy_flutter (the Chumbucket wallet) requires it.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml `version:` (name+code). Must exceed the last
        // published code: dApp Store version_code 2, sideloaded builds up to 33.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseSigning -> signingConfigs.getByName("release")
                allowDebugSignedRelease -> signingConfigs.getByName("debug")
                else -> null
            }
            isShrinkResources = true
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                // Uploading the R8 mapping needs network and Firebase access.
                // scripts/build_release.sh turns it on; CI compile checks don't.
                mappingFileUploadEnabled =
                    System.getenv("CHUMBUCKET_UPLOAD_CRASHLYTICS_MAPPING") == "true"
            }
        }
    }
}

// Fail a release build early and clearly when the upload key is missing,
// instead of letting AGP produce an unsigned APK that Flutter then can't find.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { task ->
        task.project == project &&
            Regex("^(assemble|bundle|package|sign)\\w*Release$").matches(task.name)
    }
    if (!buildsRelease || hasReleaseSigning) return@whenReady
    if (allowDebugSignedRelease) {
        logger.warn(
            "\nWARNING: CHUMBUCKET_ALLOW_DEBUG_SIGNED_RELEASE=true - this release " +
                "build is signed with the DEBUG key. It is a compile check only and " +
                "can never be published.\n",
        )
        return@whenReady
    }
    val where = System.getenv("CHUMBUCKET_KEY_PROPERTIES")?.takeIf { it.isNotBlank() }
        ?: rootProject.file("key.properties").path
    val problem = when {
        keyPropertiesFile == null -> "no key.properties at $where"
        missingSigningKeys.isNotEmpty() ->
            "key.properties ($keyPropertiesFile) is missing: ${missingSigningKeys.joinToString()}"
        else -> "the keystore named in key.properties does not exist: $releaseKeystore"
    }
    throw GradleException(
        """
        |Release signing is not configured: $problem.
        |
        |Release builds must be signed with the ORIGINAL Chumbucket upload key: the
        |Solana dApp Store pins its certificate (SHA-256 315b22c7...e1c7, see
        |publishing/config.yaml). Restore that keystore from secure storage, then
        |either set CHUMBUCKET_KEY_PROPERTIES=/path/to/key.properties or create
        |android/key.properties (gitignored) containing:
        |
        |  storeFile=/path/to/upload-keystore.jks
        |  storePassword=...
        |  keyAlias=...
        |  keyPassword=...
        |
        |Never commit the keystore or key.properties. For a compile-only check, set
        |CHUMBUCKET_ALLOW_DEBUG_SIGNED_RELEASE=true (debug-signed, not publishable).
        """.trimMargin(),
    )
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // Block Store: keeps the session and the on-phone wallet key across
    // reinstall (BlockStoreChannel.kt). End-to-end encrypted when backed up.
    implementation("com.google.android.gms:play-services-auth-blockstore:16.4.0")
}

flutter {
    source = "../.."
}
