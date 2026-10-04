plugins { id("com.android.application"); id("org.jetbrains.kotlin.android"); id("org.jetbrains.kotlin.plugin.compose"); id("org.jetbrains.kotlin.plugin.serialization") }
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
        versionCode = providers.gradleProperty("androidVersionCode").orNull?.toInt() ?: 2026100301
        versionName = providers.gradleProperty("androidVersionName").orNull ?: "0.1.1"
        buildConfigField("int", "RELEASE_BUILD", "14")
        ndk { abiFilters += "arm64-v8a" }
        buildConfigField("boolean", "NATIVE_ENGINE", withNative.toString())
        val relayURL = providers.gradleProperty("relayUrl").orNull ?: "https://magicmobile-relay.calebjfeliciano.workers.dev"
        require(relayURL.startsWith("https://")) { "The table relay must use HTTPS" }
        buildConfigField("String", "RELAY_URL", "\"$relayURL\"")
        if(withNative) externalNativeBuild { cmake { arguments += "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON" } }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17; isCoreLibraryDesugaringEnabled = true }
    kotlinOptions { jvmTarget = "17" }
    if(withNative) externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/magicmobile-assets"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/magicmobile-audio"))
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
// Sync, not Copy: drawables that stop being generated (the old background PNGs) must be removed,
// or they collide with src/main/res in existing build directories.
val prepareBrandAssets by tasks.registering(Sync::class) {
    val catalogue = rootProject.file("../ios/MagicMobile/Assets.xcassets")
    // The iOS asset catalogue is the source for the icon, launch mark and tavern art. The classic board
    // and menu backgrounds are lossy WebP in src/main/res/drawable (iOS ships JPEGs of the same art).
    into(layout.buildDirectory.dir("generated/magicmobile-res"))
    from(File(catalogue, "LaunchMark.imageset/launch-mark@3x.png")) { into("drawable"); rename { "launch_mark.png" } }
    // Walnut Tavern art (iOS builds 23-26), unscaled: the plates are drawn to fill the screen and the
    // UI kit sprites (rendered at 3 px per point) are drawn at explicit sizes, so density scaling
    // would only waste memory. The launcher icon is the iOS icon (mipmap-anydpi-v26/ic_launcher.xml).
    from(File(catalogue, "AppIcon.appiconset/AppIcon-1024.png")) { into("drawable-nodpi"); rename { "magicmobile_icon.png" } }
    from(catalogue) {
        include("battlefield-tavern-portrait.imageset/*.jpg", "battlefield-tavern-landscape.imageset/*.jpg",
            "menu-backdrop-tavern.imageset/*.jpg", "tavern-*.imageset/*.png")
        // Android resource names are lowercase with underscores: tavern-mana-B -> tavern_mana_b.
        eachFile { path = "drawable-nodpi/" + name.replace('-', '_').lowercase() }
        includeEmptyDirs = false
    }
}
val prepareAudio by tasks.registering(Exec::class) {
    val script = rootProject.file("../../scripts/android/prepare_audio.py")
    inputs.file(script)
    inputs.dir(rootProject.file("../ios/MagicMobile/Resources/Audio"))
    outputs.dir(layout.buildDirectory.dir("generated/magicmobile-audio"))
    commandLine("python3", script.absolutePath, rootProject.file("../..").absolutePath,
        layout.buildDirectory.dir("generated/magicmobile-audio").get().asFile.absolutePath)
}
tasks.named("preBuild").configure { dependsOn(prepareAssets,prepareBrandAssets,prepareAudio) }
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
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // WebSocket client for the cross-play table relay.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
tasks.register<JavaExec>("artworkCatalogueChecks") {
    dependsOn("testDebugUnitTest")
    classpath = files(layout.buildDirectory.dir("tmp/kotlin-classes/debugUnitTest"),
        layout.buildDirectory.dir("intermediates/javac/debugUnitTest/compileDebugUnitTestJavaWithJavac/classes")) +
        configurations["debugUnitTestRuntimeClasspath"]
    mainClass.set("io.magicmobile.android.ArtworkCatalogueChecksKt")
}
