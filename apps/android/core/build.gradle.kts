plugins { id("org.jetbrains.kotlin.jvm") }
kotlin { jvmToolchain(17) }
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
