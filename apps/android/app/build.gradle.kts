plugins { id("com.android.application"); id("org.jetbrains.kotlin.android"); id("org.jetbrains.kotlin.plugin.compose") }
val withNative = providers.gradleProperty("withNative").orNull == "true"
android {
    namespace = "io.magicmobile.android"
    testBuildType = providers.gradleProperty("androidTestBuildType").orNull ?: "debug"
    compileSdk = 35
    ndkVersion = "28.2.13676358"
    defaultConfig {
        applicationId = "com.calebfeliciano.magicmobile.android"
        minSdk = 26
        targetSdk = 35
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        versionCode = providers.gradleProperty("androidVersionCode").orNull?.toInt() ?: 2026092101
        versionName = providers.gradleProperty("androidVersionName").orNull ?: "0.1.1"
        buildConfigField("int", "RELEASE_BUILD", "7")
        val onlineURL = providers.gradleProperty("onlineServerUrl").orNull ?: ""
        require(onlineURL.isEmpty() || onlineURL.startsWith("https://")) { "Online service must use HTTPS" }
        buildConfigField("String", "ONLINE_SERVER_URL", "\"${onlineURL.replace("\\", "\\\\").replace("\"", "\\\"")}\"")
        ndk { abiFilters += "arm64-v8a" }
        buildConfigField("boolean", "NATIVE_ENGINE", withNative.toString())
        if(withNative) externalNativeBuild { cmake { arguments += "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON" } }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17; isCoreLibraryDesugaringEnabled = true }
    kotlinOptions { jvmTarget = "17" }
    if(withNative) externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/magicmobile-assets"))
    sourceSets["main"].res.srcDir(layout.buildDirectory.dir("generated/magicmobile-res"))
    // Compress the large AOT engine in the download; Android extracts its aligned
    // ELF at install time. The actual native ABI is unchanged.
    packaging { jniLibs { useLegacyPackaging = true; keepDebugSymbols += "**/libmmengine.so" } }
    val releaseStore = providers.environmentVariable("MM_ANDROID_KEYSTORE").orNull
    if(releaseStore != null) signingConfigs.create("distribution") {
        storeFile = file(releaseStore)
        storePassword = providers.environmentVariable("MM_ANDROID_STORE_PASSWORD").get()
        keyAlias = providers.environmentVariable("MM_ANDROID_KEY_ALIAS").orNull ?: "magicmobile"
        keyPassword = providers.environmentVariable("MM_ANDROID_KEY_PASSWORD").get()
    }
    buildTypes { debug { applicationIdSuffix = providers.gradleProperty("androidDebugSuffix").orNull ?: ".debug" }; release {
        isMinifyEnabled = false
        if(releaseStore != null) signingConfig = signingConfigs.getByName("distribution")
    } }
}
val prepareAssets by tasks.registering(Exec::class) {
    val script = rootProject.file("../../scripts/android/prepare_assets.py")
    inputs.file(script)
    inputs.file(rootProject.file("../ios/MagicMobile/Resources/ondevice-catalogue.json"))
    inputs.file(rootProject.file("../ios/MagicMobile/PreconCatalog.swift"))
    outputs.dir(layout.buildDirectory.dir("generated/magicmobile-assets"))
    commandLine("python3",script.absolutePath, rootProject.file("../..").absolutePath,layout.buildDirectory.dir("generated/magicmobile-assets").get().asFile.absolutePath)
}
val prepareBrandAssets by tasks.registering(Copy::class) {
    from(rootProject.file("../ios/MagicMobile/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")) {
        rename { "magicmobile_icon.png" }
    }
    from(rootProject.file("../ios/MagicMobile/Assets.xcassets")) {
        include("battlefield-*.imageset/battlefield-*.png")
        eachFile { path = name.replace('-', '_') }
        includeEmptyDirs = false
    }
    into(layout.buildDirectory.dir("generated/magicmobile-res/drawable"))
}
tasks.named("preBuild").configure { dependsOn(prepareAssets,prepareBrandAssets) }
if(withNative) {
    val verifyNative by tasks.registering(Exec::class) {
        commandLine("python3",rootProject.file("../../scripts/android/verify_native.py").absolutePath,rootProject.file("../..").absolutePath)
    }
    tasks.named("preBuild").configure { dependsOn(verifyNative) }
}
dependencies {
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("junit:junit:4.13.2")
    testImplementation("junit:junit:4.13.2")
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
tasks.register<JavaExec>("artworkCatalogueChecks") {
    dependsOn("testDebugUnitTest")
    classpath = files(layout.buildDirectory.dir("tmp/kotlin-classes/debugUnitTest"),
        layout.buildDirectory.dir("intermediates/javac/debugUnitTest/compileDebugUnitTestJavaWithJavac/classes")) +
        configurations["debugUnitTestRuntimeClasspath"]
    mainClass.set("io.magicmobile.android.ArtworkCatalogueChecksKt")
}
