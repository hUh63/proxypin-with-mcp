#Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class de.prosiebensat1digital.** { *; }

-dontwarn com.google.android.play.core.**

# ---------------------------------------------------------------------------
# Shizuku UserService
# Shizuku 服务端通过 Class.forName(类名) 反射加载并实例化该实现类，因此类名、
# 两个构造器（无参 / 带 Context）和方法名都必须保留，不能被 R8 重命名或删除。
# ---------------------------------------------------------------------------
-keep class com.network.proxy.shizuku.** { *; }

# ---------------------------------------------------------------------------
# Shizuku
# shellViaShizuku 会用 getDeclaredMethod 反射调用 Shizuku.newProcess（13.1.5 起为 private），
# 且 ShizukuProvider 需要在 AndroidManifest 里按原名引用，因此整体保留。
# ---------------------------------------------------------------------------
-keep class rikka.shizuku.** { *; }

# ---------------------------------------------------------------------------
# Dhizuku-API
# 该库内部引用了一批 hidden API stub（在库内以 compileOnly 引入，不会随 AAR 打包，
# 运行时由系统提供），R8 在 minify 时无需为这些引用报缺失警告。
# ---------------------------------------------------------------------------
-dontwarn com.rosan.dhizuku.**
-dontwarn android.app.ActivityThread
-dontwarn android.app.admin.**
-dontwarn android.content.pm.**
-dontwarn android.content.res.ApkAssets
-dontwarn android.os.IUserManager
-dontwarn android.os.ServiceManager
-dontwarn com.android.modules.utils.**
