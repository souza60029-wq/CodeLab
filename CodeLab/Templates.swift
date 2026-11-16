import Foundation

enum Templates {
    static func files(_ l: Lang, _ name: String) -> [String: String] {
        switch l {
        case .cpp:
            return [
                "main.cpp": "#include <iostream>\n\nint main() {\n    std::cout << \"Ola, mundo!\" << std::endl;\n    return 0;\n}\n",
                ".github/workflows/build.yml": cppWF
            ]
        case .java:
            return [
                "Main.java": "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Ola, mundo!\");\n    }\n}\n",
                ".github/workflows/build.yml": javaWF
            ]
        case .kotlin:
            return [
                "Main.kt": "fun main() {\n    println(\"Ola, mundo!\")\n}\n",
                ".github/workflows/build.yml": kotlinWF
            ]
        case .godot:
            return [
                "project.godot": "config_version=5\n\n[application]\nconfig/name=\"\(name)\"\n",
                "main.gd": "extends SceneTree\n\nfunc _init():\n\tprint(\"Ola, mundo!\")\n\tquit()\n",
                ".github/workflows/build.yml": godotWF
            ]
        case .android:
            return [
                "settings.gradle": "pluginManagement {\n    repositories { google(); mavenCentral(); gradlePluginPortal() }\n}\ndependencyResolutionManagement {\n    repositories { google(); mavenCentral() }\n}\nrootProject.name = \"\(name)\"\ninclude ':app'\n",
                "build.gradle": "plugins {\n    id 'com.android.application' version '8.2.0' apply false\n}\n",
                "gradle.properties": "android.useAndroidX=true\norg.gradle.jvmargs=-Xmx2g\n",
                "app/build.gradle": "plugins {\n    id 'com.android.application'\n}\n\nandroid {\n    namespace 'com.example.app'\n    compileSdk 34\n    defaultConfig {\n        applicationId \"com.example.app\"\n        minSdk 24\n        targetSdk 34\n        versionCode 1\n        versionName \"1.0\"\n    }\n    compileOptions {\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n    }\n}\n",
                "app/src/main/AndroidManifest.xml": "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n    <application android:label=\"\(name)\">\n        <activity android:name=\".MainActivity\" android:exported=\"true\">\n            <intent-filter>\n                <action android:name=\"android.intent.action.MAIN\" />\n                <category android:name=\"android.intent.category.LAUNCHER\" />\n            </intent-filter>\n        </activity>\n    </application>\n</manifest>\n",
                "app/src/main/java/com/example/app/MainActivity.java": "package com.example.app;\n\nimport android.app.Activity;\nimport android.os.Bundle;\nimport android.widget.TextView;\n\npublic class MainActivity extends Activity {\n    @Override\n    protected void onCreate(Bundle savedInstanceState) {\n        super.onCreate(savedInstanceState);\n        TextView tv = new TextView(this);\n        tv.setText(\"Ola, Android!\");\n        tv.setTextSize(24);\n        setContentView(tv);\n    }\n}\n",
                ".github/workflows/build.yml": androidWF
            ]
        case .ios:
            return [
                "project.yml": "name: \(name)\noptions:\n  bundleIdPrefix: com.rhuan\n  deploymentTarget:\n    iOS: \"15.0\"\ntargets:\n  \(name):\n    type: application\n    platform: iOS\n    sources: [App]\n    info:\n      path: Config/Info.plist\n      properties:\n        UILaunchScreen: {}\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: com.rhuan.\(name.lowercased().replacingOccurrences(of: \"-\", with: \"\").replacingOccurrences(of: \"_\", with: \"\"))\n        SWIFT_VERSION: \"5.0\"\n",
                "App/App.swift": "import SwiftUI\n\n@main\nstruct MyApp: App {\n    var body: some Scene {\n        WindowGroup { Text(\"Ola, iOS!\").font(.largeTitle) }\n    }\n}\n",
                ".github/workflows/build.yml": iosWF(name)
            ]
        }
    }

    static let cppWF = #"""
name: Build
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Compilar e executar
        run: |
          g++ -std=c++17 -Wall -Wextra *.cpp -o app
          ./app
"""#

    static let javaWF = #"""
name: Build
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - name: Compilar e executar
        run: |
          javac *.java
          java Main
"""#

    static let kotlinWF = #"""
name: Build
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - name: Instalar kotlinc
        run: |
          curl -sLO https://github.com/JetBrains/kotlin/releases/download/v1.9.22/kotlin-compiler-1.9.22.zip
          unzip -q kotlin-compiler-1.9.22.zip
      - name: Compilar e executar
        run: |
          ./kotlinc/bin/kotlinc Main.kt -include-runtime -d app.jar
          java -jar app.jar
"""#

    static let godotWF = #"""
name: Build
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: barichello/godot-ci:4.2.1
    steps:
      - uses: actions/checkout@v4
      - name: Executar script
        run: godot --headless --path . -s res://main.gd
"""#

    static let androidWF = #"""
name: Build APK
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - uses: gradle/actions/setup-gradle@v3
        with:
          gradle-version: 8.5
      - name: Montar APK
        run: gradle assembleDebug
      - uses: actions/upload-artifact@v4
        with:
          name: apk
          path: app/build/outputs/apk/debug/*.apk
"""#

    static func iosWF(_ name: String) -> String {
        return #"""
name: Build IPA
on: workflow_dispatch
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen generate
      - name: Compilar sem assinatura
        run: |
          xcodebuild -project NAME.xcodeproj -scheme NAME -configuration Release \
            -sdk iphoneos -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
      - name: Empacotar .ipa
        run: |
          mkdir Payload
          cp -R build/Build/Products/Release-iphoneos/NAME.app Payload/
          zip -r NAME.ipa Payload
      - uses: actions/upload-artifact@v4
        with:
          name: ipa
          path: NAME.ipa
"""#.replacingOccurrences(of: "NAME", with: name)
    }
}
