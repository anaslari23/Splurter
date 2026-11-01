import java.util.Properties

plugins { id("com.android.application"); id("org.jetbrains.kotlin.android"); id("org.jetbrains.kotlin.plugin.compose") }
val ks = rootProject.file("keystore.properties").takeIf { it.exists() }?.let { f -> Properties().also { it.load(f.inputStream()) } }

android {
    signingConfigs {
        if (ks != null) create("release") {
            storeFile = rootProject.file(ks.getProperty("storeFile")); storePassword = ks.getProperty("storePassword")
            keyAlias = ks.getProperty("keyAlias"); keyPassword = ks.getProperty("keyPassword")
        }
    }
    buildTypes {
        release { signingConfig = if (ks != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug") } // ponytail: no R8/minify; add when APK size matters
    }
    namespace = "app.splurter"
    compileSdk = 36
    defaultConfig { applicationId = "app.splurter"; minSdk = 33; targetSdk = 36; versionCode = 2; versionName = "0.2" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    buildFeatures { compose = true }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    implementation(platform("androidx.compose:compose-bom:2025.09.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.fragment:fragment:1.8.5") // the scanner library drags in fragment 1.0.0, which breaks the activity-result APIs
}
