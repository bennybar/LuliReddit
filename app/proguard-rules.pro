# kotlinx.serialization: keep generated serializers for @Serializable classes
# (navigation routes, persisted models).
-keepattributes *Annotation*, InnerClasses
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclasseswithmembers class **$$serializer { *; }
# WebView JavaScript bridges
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
