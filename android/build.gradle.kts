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

// Register the plugin's local Maven repo (libs-maven/) on every project of
// the consuming app's build — including :app, which is where the runtime
// classpath is resolved. A plain `allprojects` block inside a sub-project
// only configures that sub-project, not its siblings, so the AARs would
// resolve at compile time but the host app would fail to find them at
// :app:mergeReleaseNativeLibs. This pattern is intentionally consumer-
// invasive but is what's needed for a self-contained Flutter plugin
// shipping vendored AARs that AGP refuses to package via fileTree.
val aliyunLocalMaven = uri("$projectDir/libs-maven")
rootProject.allprojects {
    repositories {
        maven {
            name = "AliyunNumberAuthLocal"
            url = aliyunLocalMaven
        }
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
    // Aliyun ATAuth SDK, resolved from the local Maven repo at libs-maven/.
    // See the allprojects { repositories { ... } } block above.
    implementation("com.aliyun.atauth:auth_number_product:2.14.23@aar")
    implementation("com.aliyun.atauth:main:2.2.3@aar")
    implementation("com.aliyun.atauth:logger:2.2.2@aar")
    // The vendored AARs extend androidx.appcompat.app.AppCompatActivity
    // (LoginAuthActivity, PrivacyDialogActivity, AuthWebVeiwActivity) and use
    // androidx.activity's OnBackPressedDispatcher. They have no POM so their
    // transitive deps aren't resolved — declare them here or the auth page
    // crashes with ClassNotFoundException on hosts that don't pull appcompat.
    implementation("androidx.appcompat:appcompat:1.7.0")
}
