import Foundation

enum Templates {
    static func files(_ l: Lang, _ name: String, kotlin: Bool = false, minSdk: Int = 24) -> [String: String] {
        let bundleSuffix = name.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch l {
        case .cpp:
            return [
                "main.cpp": "#include <iostream>\n\nint main() {\n    std::cout << \"Ola, mundo!\" << std::endl;\n    return 0;\n}\n"
            ]
        case .java:
            return [
                "Main.java": "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Ola, mundo!\");\n    }\n}\n"
            ]
        case .godot:
            return [
                "project.godot": "config_version=5\n\n[application]\nconfig/name=\"\(name)\"\n",
                "main.gd": "extends SceneTree\n\nfunc _init():\n\tprint(\"Ola, mundo!\")\n\tquit()\n",
                ".github/workflows/build.yml": godotWF
            ]
        case .android:
            return android(name, kotlin: kotlin, minSdk: minSdk)
        case .ios:
            return [
                "project.yml": "name: \(name)\noptions:\n  bundleIdPrefix: com.rhuan\n  deploymentTarget:\n    iOS: \"15.0\"\ntargets:\n  \(name):\n    type: application\n    platform: iOS\n    sources: [App]\n    info:\n      path: Config/Info.plist\n      properties:\n        UILaunchScreen: {}\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: com.rhuan.\(bundleSuffix)\n        SWIFT_VERSION: \"5.0\"\n",
                "App/App.swift": "import SwiftUI\n\n@main\nstruct MyApp: App {\n    var body: some Scene {\n        WindowGroup { Text(\"Ola, iOS!\").font(.largeTitle) }\n    }\n}\n",
                ".github/workflows/build.yml": iosWF(name)
            ]
        }
    }


    static func android(_ name: String, kotlin: Bool, minSdk: Int) -> [String: String] {
        var f: [String: String] = [:]
        f["settings.gradle"] = #"""
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}
rootProject.name = "\#(name)"
include ':app'

"""#
        f["build.gradle"] = kotlin ? #"""
plugins {
    id 'com.android.application' version '8.2.0' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.22' apply false
}

"""# : #"""
plugins {
    id 'com.android.application' version '8.2.0' apply false
}

"""#
        f["gradle.properties"] = "android.useAndroidX=true\norg.gradle.jvmargs=-Xmx2g\n"
        let kPlugin = kotlin ? "    id 'org.jetbrains.kotlin.android'\n" : ""
        let kOpts = kotlin ? "    kotlinOptions { jvmTarget = '17' }\n" : ""
        f["app/build.gradle"] = #"""
plugins {
    id 'com.android.application'
\#(kPlugin)}

android {
    namespace 'com.example.app'
    compileSdk 34
    defaultConfig {
        applicationId "com.example.app"
        minSdk \#(minSdk)
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
\#(kOpts)}

"""#
        f["app/src/main/AndroidManifest.xml"] = #"""
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="\#(name)">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>

"""#
        if kotlin {
            f["app/src/main/java/com/example/app/MainActivity.kt"] = #"""
package com.example.app

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val tv = TextView(this)
        tv.text = "Ola, Android (Kotlin)!"
        tv.textSize = 24f
        setContentView(tv)
    }
}

"""#
        } else {
            f["app/src/main/java/com/example/app/MainActivity.java"] = #"""
package com.example.app;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView tv = new TextView(this);
        tv.setText("Ola, Android (Java)!");
        tv.setTextSize(24);
        setContentView(tv);
    }
}

"""#
        }
        f[".github/workflows/build.yml"] = androidWF
        return f
    }

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
    runs-on: macos-15
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
