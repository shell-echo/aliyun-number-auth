group = "studio.echo.aliyun_number_auth"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "studio.echo.aliyun_number_auth"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar", "*.jar"))))
    // Aliyun SDK runtime dependencies. The AARs in libs/ ship classes that
    // extend androidx.appcompat.app.AppCompatActivity (LoginAuthActivity,
    // PrivacyDialogActivity, AuthWebVeiwActivity) and use androidx.activity's
    // OnBackPressedDispatcher. Because we import the AARs via fileTree, their
    // POM-declared transitive deps are NOT resolved by gradle — we must
    // declare them ourselves or the auth page will crash with
    // ClassNotFoundException at runtime on hosts that don't transitively
    // pull in appcompat (which a bare Flutter app may not).
    implementation("androidx.appcompat:appcompat:1.7.0")
}
