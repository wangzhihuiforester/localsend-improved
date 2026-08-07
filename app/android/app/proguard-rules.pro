# Flutter InAppWebView
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }

# Flutter plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }

# Keep Flutter generated classes
-keep class **.GeneratedPluginRegistrant { *; }

# Keep all classes with native methods (JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enum values
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Rust FFI (flutter_rust_bridge)
-keep class ffi.** { *; }
-keep class **_ffi.** { *; }

# Keep Dart-generated classes referenced via reflection
-keep class com.ryanheise.** { *; }
-keep class dev.flutter.** { *; }

# LocalSend specific
-keep class org.localsend.** { *; }

# Keep model/data classes
-keep class **.model.** { *; }
-keep class **.dto.** { *; }
-keep class **.gen.** { *; }

# Keep annotation classes
-keep class androidx.annotation.** { *; }
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,Signature,InnerClasses,EnclosingMethod

# Suppress warnings
-dontwarn javax.lang.model.**
-dontwarn com.google.errorprone.**
