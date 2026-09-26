plugins { id("org.jetbrains.kotlin.jvm"); id("org.jetbrains.kotlin.plugin.serialization") }
kotlin { jvmToolchain(17) }
dependencies {
    api("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}
sourceSets.main {
    java.srcDir("../../../packages/ondevice-engine/engine/core/src/main/java")
    java.include("io/magicmobile/core/Json.java", "io/magicmobile/core/BridgeException.java")
}
tasks.register<JavaExec>("contractChecks") {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("io.magicmobile.android.core.ContractChecksKt")
    args(rootProject.file("../..").absolutePath)
}
tasks.register<JavaExec>("deckStudioChecks") {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("io.magicmobile.android.core.DeckStudioChecksKt")
}
tasks.register<JavaExec>("providerChecks") {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("io.magicmobile.android.core.ProviderChecksKt")
}
tasks.register<JavaExec>("insightChecks") {
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("io.magicmobile.android.core.DeckInsightChecksKt")
}
tasks.test {
    systemProperty("magicmobile.repo", rootProject.file("../..").absolutePath)
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
