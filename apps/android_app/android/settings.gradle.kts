pluginManagement {
    includeBuild("/opt/homebrew/share/flutter/packages/flutter")
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "splurter_android"
include(":app")
