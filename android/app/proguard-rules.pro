# Keep PDFBox classes (loaded reflectively; optional JP2/JBIG2 codecs are absent)
-keep class com.tom_roush.pdfbox.** { *; }
-keep class com.tom_roush.fontbox.** { *; }
-keep class com.tom_roush.harmony.** { *; }
-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.filter.**

# Keep Tesseract JNI bindings
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }

# Keep Kotlin coroutines
-keepclassmembers class kotlinx.coroutines.** { *; }

# Keep Flutter
-keep class io.flutter.** { *; }

# Keep Google ML Kit
-keep class com.google.mlkit.** { *; }

# Keep AdMob
-keep class com.google.android.gms.ads.** { *; }

# Flutter's engine references Play Core for deferred components (dynamic feature
# downloads). This app doesn't use them, so the library isn't bundled.
-dontwarn com.google.android.play.core.**
