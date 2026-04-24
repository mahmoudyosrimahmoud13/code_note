# Google ML Kit Text Recognition Proguard rules
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.**

# Ignore missing classes from other ML Kit modules that might be referenced but not used
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
