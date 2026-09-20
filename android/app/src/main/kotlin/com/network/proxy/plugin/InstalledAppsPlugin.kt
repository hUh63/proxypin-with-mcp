package com.network.proxy.plugin

import android.content.pm.ApplicationInfo
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * 已经安装应用列表
 *
 * @author wanghongen
 */
class InstalledAppsPlugin : AndroidFlutterPlugin() {
    var channel: MethodChannel? = null

    companion object {
        const val CHANNEL = "com.proxy/installedApps"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)

        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    val withIcon = call.argument<Boolean>("withIcon") ?: false
                    val packageNamePrefix = call.argument<String>("packageNamePrefix") ?: ""
                    val includeSystemApps = call.argument<Boolean>("includeSystemApps") ?: false
                    // 默认不查版本号：逐个应用 getPackageInfo 是跨进程调用，冷启动时可能累计数秒
                    val withVersion = call.argument<Boolean>("withVersion") ?: false
                    Thread {
                        // 任何异常都必须回 result：否则 Flutter 侧 await 永久挂起，
                        // 应用选择页会一直停在 loading（上游 #783）
                        try {
                            result.success(
                                getInstalledApps(
                                    withIcon,
                                    packageNamePrefix,
                                    includeSystemApps,
                                    withVersion
                                )
                            )
                        } catch (e: Throwable) {
                            Log.w("ProxyPin", "getInstalledApps failed", e)
                            result.error("APPS_FAILED", e.message ?: e.toString(), null)
                        }
                    }.start()
                }

                "getAppInfo" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    // 放到工作线程：这里要 loadIcon 并压成 PNG，在主线程做会卡 UI。
                    // 另外包已被卸载时会抛 NameNotFoundException——Dart 侧本来就写了
                    // catchError 兜底（构造 inValid 占位），但原生不回 result 的话那个
                    // catchError 永远不会触发，白名单页会卡在 loading。
                    Thread {
                        try {
                            result.success(getAppInfo(packageName))
                        } catch (e: Throwable) {
                            Log.w("ProxyPin", "getAppInfo failed: $packageName", e)
                            result.error("APP_NOT_FOUND", e.message ?: e.toString(), null)
                        }
                    }.start()
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun getAppInfo(packageName: String): ProcessInfo {
        val packageManager = activity.packageManager
        packageManager.getApplicationInfo(packageName, 0).let { app ->
            return ProcessInfo.create(packageManager, app, true, true)
        }
    }

    private fun isSystemApp(applicationInfo: ApplicationInfo?): Boolean {
        if (applicationInfo == null) return false
        return (applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
    }

    private fun getInstalledApps(
        withIcon: Boolean,
        packageNamePrefix: String,
        includeSystemApps: Boolean,
        withVersion: Boolean = false
    ): List<ProcessInfo> {
        val packageManager = activity.packageManager
        var installedApps = packageManager.getInstalledApplications(0)

        if (!includeSystemApps) {
            installedApps =
                installedApps.filter { app -> !isSystemApp(app) }
        }

        if (packageNamePrefix.isNotEmpty()) {
            installedApps = installedApps.filter { app ->
                app.packageName.startsWith(
                    packageNamePrefix.lowercase(Locale.ENGLISH)
                )
            }
        }

        if (withIcon) {
            // 使用线程池并发加载图标，提升性能
            val threadPoolExecutor = Executors.newFixedThreadPool(3)
            installedApps.map { app ->
                val task: Callable<ProcessInfo> = Callable {
                    ProcessInfo.create(packageManager, app, withIcon, withVersion)
                }
                threadPoolExecutor.submit(task)
            }.map { future ->
                future.get()
            }.let {
                threadPoolExecutor.shutdown()
                threadPoolExecutor.awaitTermination(3, TimeUnit.SECONDS)
                return it
            }
        } else {
            // 不需要图标，直接创建ProcessInfo对象
            return installedApps.map { app ->
                ProcessInfo.create(packageManager, app, false, withVersion)
            }
        }
    }

}
