plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.splurter.splurter_android"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.splurter.splurter"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    packaging {
        resources {
            excludes += listOf("META-INF/AL2.0", "META-INF/LGPL2.1")
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // Firebase BOM — controls all Firebase SDK versions consistently
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-messaging-ktx")
}

flutter {
    source = "../.."
}

tasks.register<Copy>("copyApkToFlutterBuild") {
    from(layout.buildDirectory.dir("outputs/flutter-apk"))
    into(file("../../build/app/outputs/flutter-apk"))
}

afterEvaluate {
    tasks.findByName("assembleDebug")?.finalizedBy("copyApkToFlutterBuild")
}
