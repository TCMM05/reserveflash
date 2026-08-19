allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// R0.2 (hotfix decouvert par execution reelle, voir CHANGELOG.md pour
// l'historique complet des vagues successives) : `flutter build apk
// --debug` echouait sur `:camera_android_camerax:compileDebugJavaWithJavac`
// avec :
//   error: Cannot attach type annotations @org.jspecify.annotations.NonNull
//   to SurfaceRequest.mSurfaceRecreationCompleter:
//     class file for androidx.concurrent.futures.CallbackToFutureAdapter not
//     found
//
// Root cause (confirmee par le depot de reproduction officiel du bug,
// github.com/justshowcode/flutter_packages_camerax_repro) :
// `androidx.camera:camera-core:1.5.3` (utilise en transitif par le plugin
// `camera_android_camerax`) declare sa dependance vers
// `androidx.concurrent:concurrent-futures` avec la porte "runtime" dans
// son POM. Jusqu'a Gradle 8.x, Gradle "promouvait" silencieusement cette
// dependance runtime vers le classpath de COMPILATION des consommateurs.
// Gradle 9.x (utilise ici, voir gradle-9.3.1 dans les logs de build)
// applique un isolement de classpath plus strict et ne fait plus cette
// promotion - la classe devient invisible au compilateur Java au moment
// ou celui-ci doit attacher une annotation de type (`@NonNull`, jspecify)
// sur un champ dont le type resout vers cette classe absente.
//
// Correctif reel : injecter la dependance manquante dans les sous-
// projets Android de type "library" (donc `:camera_android_camerax` y
// compris), sans editer son fichier Gradle source dans le pub cache (qui
// serait de toute facon ecrase au prochain `flutter pub get`, sur cette
// machine comme sur n'importe quelle autre - une correction non
// reproductible sur un autre poste n'a aucune valeur pour ce projet).
//
// DEUX ESSAIS PRECEDENTS ONT ECHOUE, chacun prouve faux par une execution
// reelle qui plantait a l'identique :
//   1) Ajouter la dependance dans `android/app/build.gradle.kts` (module
//      `:app`) : aucun effet, l'erreur survient dans la compilation JAVA
//      DU MODULE DU PLUGIN LUI-MEME (`:camera_android_camerax`, un sous-
//      projet Gradle distinct, avec son PROPRE classpath) - une
//      dependance cote `:app` ne remonte jamais vers le classpath de
//      compilation d'un sous-projet dont `:app` DEPEND, seulement
//      l'inverse.
//   2) Ajouter un `subprojects { afterEvaluate { ... } }` PLACE APRES le
//      bloc `subprojects { project.evaluationDependsOn(":app") }`
//      (present par defaut dans le template Flutter, voir plus bas) :
//      plantait avec `Cannot run Project.afterEvaluate(Action) when the
//      project is already evaluated.` En appliquant `dev.flutter.
//      flutter-gradle-plugin`, l'evaluation de `:app` declenchee par
//      `evaluationDependsOn(":app")` force en cascade l'evaluation de
//      TOUS les sous-projets de plugins Flutter (le plugin loader doit
//      inspecter leur configuration AGP) - donc au moment ou un bloc
//      place APRES `evaluationDependsOn` s'execute, tous les sous-projets
//      sont deja evalues, quel que soit celui vise.
// Correctif qui fonctionne : enregistrer `afterEvaluate` ICI, AVANT le
// bloc `evaluationDependsOn(":app")` plus bas - donc avant que quoi que
// ce soit ne force une evaluation anticipee de qui que ce soit.
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            dependencies.add(
                "implementation",
                "androidx.concurrent:concurrent-futures:1.2.0",
            )
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
