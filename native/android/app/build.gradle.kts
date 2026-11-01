plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "app.splurter"
    compileSdk = 36
    defaultConfig { applicationId = "app.splurter"; minSdk = 33; targetSdk = 36; versionCode = 1; versionName = "0.1" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies { implementation("com.google.android.gms:play-services-code-scanner:16.1.0") }
