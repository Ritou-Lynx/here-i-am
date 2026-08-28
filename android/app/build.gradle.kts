import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    fun loadKeystoreProperties(fileName: String): Pair<Properties, Boolean> {
        val properties = Properties()
        val propertiesFile = rootProject.file(fileName)
        if (propertiesFile.exists()) {
            properties.load(FileInputStream(propertiesFile))
        }

        val hasRequiredProperties = propertiesFile.exists() &&
            properties["keyAlias"] != null &&
            properties["keyPassword"] != null &&
            properties["storeFile"] != null &&
            properties["storePassword"] != null
        return properties to hasRequiredProperties
    }

    val (globalKeystoreProperties, hasGlobalKeystore) =
        loadKeystoreProperties("key-global.properties")
    val (cnKeystoreProperties, hasCnKeystore) =
        loadKeystoreProperties("key-cn.properties")
    val (earlyKeystoreProperties, hasEarlyKeystore) =
        loadKeystoreProperties("key-early.properties")
    val (hereIAmKeystoreProperties, hasHereIAmKeystore) =
        loadKeystoreProperties("key-hereiam.properties")

    namespace = "com.memexlab.memex"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.memexlab.memex"
        minSdk = 26  // Required by health plugin 13.2.1
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Shared debug keystore committed to the repo so debug APKs built on
        // any developer machine carry the same signature. Without this, AGP
        // falls back to ~/.android/debug.keystore which is unique per machine,
        // forcing uninstall+reinstall (and data loss) when switching machines.
        // Standard AOSP debug credentials — never use for release.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        if (hasGlobalKeystore) {
            create("globalRelease") {
                keyAlias = globalKeystoreProperties["keyAlias"] as String
                keyPassword = globalKeystoreProperties["keyPassword"] as String
                storeFile = file(globalKeystoreProperties["storeFile"] as String)
                storePassword = globalKeystoreProperties["storePassword"] as String
            }
        }
        if (hasCnKeystore) {
            create("cnRelease") {
                keyAlias = cnKeystoreProperties["keyAlias"] as String
                keyPassword = cnKeystoreProperties["keyPassword"] as String
                storeFile = file(cnKeystoreProperties["storeFile"] as String)
                storePassword = cnKeystoreProperties["storePassword"] as String
            }
        }
        if (hasEarlyKeystore) {
            create("earlyRelease") {
                keyAlias = earlyKeystoreProperties["keyAlias"] as String
                keyPassword = earlyKeystoreProperties["keyPassword"] as String
                storeFile = file(earlyKeystoreProperties["storeFile"] as String)
                storePassword = earlyKeystoreProperties["storePassword"] as String
            }
        }
        if (hasHereIAmKeystore) {
            create("hereIAmV3Release") {
                keyAlias = hereIAmKeystoreProperties["keyAlias"] as String
                keyPassword = hereIAmKeystoreProperties["keyPassword"] as String
                storeFile = file(hereIAmKeystoreProperties["storeFile"] as String)
                storePassword = hereIAmKeystoreProperties["storePassword"] as String
            }
        }
    }

    val globalApplicationId = "com.memexlab.memex"
    val cnApplicationId = "com.memexlab.memex.cn"
    val globalEarlyApplicationId = "com.memexlab.memex.early"
    val cnEarlyApplicationId = "com.memexlab.memex.cn.early"
    val globalDevApplicationId = "com.memexlab.memex.dev"
    val cnDevApplicationId = "com.memexlab.memex.cn.dev"
    val hereIAmDevApplicationId = "com.memexlab.hereiam.dev"
    val hereIAmV3ApplicationId = "com.memexlab.hereiam.v3"

    flavorDimensions += "market"
    productFlavors {
        create("global") {
            dimension = "market"
            applicationId = globalApplicationId
            manifestPlaceholders["appLabel"] = "Memex"
            resValue("string", "quick_action_target_package", globalApplicationId)
            if (hasGlobalKeystore) {
                signingConfig = signingConfigs.getByName("globalRelease")
            }
        }
        create("cn") {
            dimension = "market"
            applicationId = cnApplicationId
            manifestPlaceholders["appLabel"] = "Memex"
            resValue("string", "quick_action_target_package", cnApplicationId)
            if (hasCnKeystore) {
                signingConfig = signingConfigs.getByName("cnRelease")
            }
        }
        create("globalEarly") {
            dimension = "market"
            applicationId = globalEarlyApplicationId
            manifestPlaceholders["appLabel"] = "Memex Early"
            resValue(
                "string",
                "quick_action_target_package",
                globalEarlyApplicationId,
            )
            if (hasEarlyKeystore) {
                signingConfig = signingConfigs.getByName("earlyRelease")
            }
        }
        create("cnEarly") {
            dimension = "market"
            applicationId = cnEarlyApplicationId
            manifestPlaceholders["appLabel"] = "Memex Early CN"
            resValue("string", "quick_action_target_package", cnEarlyApplicationId)
            if (hasEarlyKeystore) {
                signingConfig = signingConfigs.getByName("earlyRelease")
            }
        }
        create("globalDev") {
            dimension = "market"
            applicationId = globalDevApplicationId
            manifestPlaceholders["appLabel"] = "Memex Dev"
            resValue("string", "quick_action_target_package", globalDevApplicationId)
        }
        create("cnDev") {
            dimension = "market"
            applicationId = cnDevApplicationId
            manifestPlaceholders["appLabel"] = "Memex Dev CN"
            resValue("string", "quick_action_target_package", cnDevApplicationId)
        }
        create("hereIAmDev") {
            dimension = "market"
            applicationId = hereIAmDevApplicationId
            manifestPlaceholders["appLabel"] = "故我在"
            resValue("string", "quick_action_target_package", hereIAmDevApplicationId)
        }
        create("hereIAmV3") {
            dimension = "market"
            applicationId = hereIAmV3ApplicationId
            manifestPlaceholders["appLabel"] = "故我在 V3"
            resValue("string", "quick_action_target_package", hereIAmV3ApplicationId)
            if (hasHereIAmKeystore) {
                signingConfig = signingConfigs.getByName("hereIAmV3Release")
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    applicationVariants.all {
        val variant = this
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            val appName = when (variant.flavorName) {
                "hereIAmDev" -> "here_i_am"
                "hereIAmV3" -> "here_i_am_v3"
                else -> "memex"
            }
            output.outputFileName = "${appName}_${variant.flavorName}_${variant.versionName}_${variant.versionCode}.apk"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.media:media:1.7.0")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
}
