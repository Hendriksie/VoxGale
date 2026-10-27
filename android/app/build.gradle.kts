import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (Phase 4): the keystore and its properties live OUTSIDE
// version control — android/.gitignore covers key.properties and *.jks.
// A release build without the key configured fails loudly (taskGraph check
// at the bottom of this file) instead of producing an unsigned or
// debug-signed artifact, per the release-distribution spec. Debug builds
// never need the key.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "dev.hendriksie.voxtral_live"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.hendriksie.voxtral_live"
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
        if (keystorePropertiesFile.exists()) {
            create("release") {
                fun prop(name: String): String =
                    keystoreProperties[name] as? String
                        ?: throw GradleException("$keystorePropertiesFile is missing '$name' — see README.md (Release signing).")
                keyAlias = prop("keyAlias")
                keyPassword = prop("keyPassword")
                storeFile = file(prop("storeFile"))
                storePassword = prop("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // No debug fallback: a release build without the key fails in the
            // taskGraph check below instead of shipping a debug-signed APK.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
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

// Fail a release build loudly when the signing key is not configured, rather
// than letting AGP emit an unsigned APK (release-distribution spec: no
// unsigned or debug-signed release artifacts).
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task ->
        task.name.startsWith("assembleRelease") || task.name.startsWith("bundleRelease")
    }
    if (buildingRelease && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Release signing key not configured: ${keystorePropertiesFile.absolutePath} is missing. " +
                "Generate the keystore and key.properties as described in README.md; a release " +
                "build without the key fails here instead of producing an unsigned APK.",
        )
    }
}
