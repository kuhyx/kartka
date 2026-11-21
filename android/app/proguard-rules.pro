# In-app extensions (com.kuhy.kartka.ext): Keiyoushi APKs are loaded at
# runtime and call into these libraries, which R8 cannot see. Keep their
# public API unrenamed (Mihon's app/proguard-rules.pro, trimmed).
-dontobfuscate
-keepattributes Signature, *Annotation*, InnerClasses
-keep,allowshrinking class * extends uy.kohesive.injekt.api.FullTypeReference
-keep,allowoptimization class androidx.preference.** { public protected *; }
-keep,allowoptimization class kotlin.** { public protected *; }
-keep,allowoptimization class kotlinx.coroutines.** { public protected *; }
-keep,allowoptimization class kotlinx.serialization.** { public protected *; }
-keep,allowoptimization class okhttp3.** { public protected *; }
-keep,allowoptimization class okio.** { public protected *; }
-keep,allowoptimization class org.jsoup.** { public protected *; }
-keep,allowoptimization class rx.** { public protected *; }
-keep,allowoptimization class uy.kohesive.injekt.** { public protected *; }
-keep,allowoptimization class com.squareup.zstd.** { public protected *; }
-keep,allowoptimization class androidx.webkit.** { public protected *; }
-keep,allowoptimization class org.chromium.support_lib_boundary.** { *; }
# No allowoptimization here: extensions subclass these classes, and R8,
# seeing no override inside kartka, would make open members final
# ("overrides final method"). scripts/check_ext_api_open.py guards it.
-keep class eu.kanade.tachiyomi.** { public protected *; }
-keep class kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.** { <methods>; }
-keep,includedescriptorclasses class eu.kanade.**$$serializer { *; }
-keepclassmembers class eu.kanade.** { *** Companion; }
-keepclasseswithmembers class eu.kanade.** { kotlinx.serialization.KSerializer serializer(...); }
-dontwarn sun.misc.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
