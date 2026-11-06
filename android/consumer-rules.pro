# Consumer ProGuard/R8 rules, applied to every app that uses this plugin.
#
# The Organic Maps engine is native code that finds its Java classes, fields and
# methods by name (JNI), for example BookmarkManager.INSTANCE. R8 cannot see
# those lookups, so without this rule it removes or renames them in a release
# build and the app aborts at start-up with
#   java.lang.NoSuchFieldError: no "...BookmarkManager;" field "INSTANCE"
#
# The organicmaps-sdk 0.1.x AAR carried this rule itself; 0.2.0 does not, so the
# plugin ships it.
-keep class app.organicmaps.sdk.** { *; }
