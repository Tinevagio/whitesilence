import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // Le plugin Flutter gère désormais Kotlin de manière intégrée.
    id("dev.flutter.flutter-gradle-plugin")
}

// Récupération des propriétés du keystore pour la signature de l'application
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.whitesilence.whitesilence"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    @Suppress("DEPRECATION")
    kotlinOptions {
        // Syntaxe propre sous forme de chaîne de caractères, universelle pour Kotlin DSL
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "app.whitesilence.whitesilence"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            storeFile = if (storeFilePath != null) file(storeFilePath) else null
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        getByName("release") {
            // Associe la configuration de signature créée ci-dessus
            signingConfig = signingConfigs.getByName("release")
            
            // Syntaxe Kotlin DSL corrigée (isMinifyEnabled et isShrinkResources)
            isMinifyEnabled = true
            isShrinkResources = true
            
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Votre bibliothèque openwakeword bien placée à la racine du fichier
    implementation("xyz.rementia:openwakeword:0.1.5")
}