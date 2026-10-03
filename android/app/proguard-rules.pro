# R8 rules for the release build (isMinifyEnabled = true).
#
# Flutter's Gradle plugin already adds the engine's own rules, and Firebase
# (core, messaging, crashlytics) ships consumer rules inside its AARs. What is
# below covers the plugins that reach code through reflection, JNI or
# serialization and do not ship complete rules of their own. Each block names
# the plugin it is for, so a rule can be dropped when its plugin is.

# --- Crash reports: keep file/line info so Crashlytics stack traces are usable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
-keep public class * extends java.lang.Exception

# --- Generic attributes reflection-based libraries rely on (Gson, Kotlin).
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*

# --- Solana Mobile Wallet Adapter (solana_mobile_client -> mobile-wallet-adapter-clientlib).
# The client parses wallet JSON-RPC responses and talks to the wallet app over
# a local association; keep its protocol and scenario classes intact.
-keep class com.solana.mobilewalletadapter.** { *; }
-keep class com.solanamobile.** { *; }
-dontwarn com.solana.mobilewalletadapter.**

# --- flutter_local_notifications: serializes notification details with Gson
# and restores them by reflection (TypeToken). Without these, R8 strips the
# generic signatures and the plugin throws "Missing type parameter".
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn com.google.gson.**

# --- Firebase Messaging background handler: the plugin starts a FlutterEngine
# from a service; keep the plugin classes it instantiates by name.
-keep class io.flutter.plugins.firebase.** { *; }

# --- flutter_secure_storage (AndroidX Security / Tink). Tink references
# annotation-only and optional classes that are not on the runtime classpath.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.google.api.client.http.**
-dontwarn org.joda.time.**

# --- Rive (rive_common): native runtime loaded over JNI.
-keep class app.rive.** { *; }

# --- webview_flutter, url_launcher, share_plus, app_links,
# sqflite, path_provider, shared_preferences, connectivity_plus: plugin entry
# points are registered by name from GeneratedPluginRegistrant.
-keep class io.flutter.plugins.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.llfbandit.app_links.** { *; }
-keep class com.tekartik.sqflite.** { *; }

# --- Flutter deferred components reference Play Core, which this app does not
# ship (no deferred components). Silence the missing-class errors only.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
