package com.network.proxy.plugin

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.Executors

/**
 * 与 iOS 侧 `ios/Runner/Handlers/MethodHandler.swift` 对应的 Android 实现，通道 `com.proxypin/method`。
 *
 * 背景：Android 侧原先完全没有注册这个通道，而抓包自检页（lib/network/util/capture_diagnose.dart）
 * 在移动端会调用 isCaInstalled，于是在 Android 上抛 MissingPluginException，
 * 自检项被显示成「CA 根证书 读取失败」——看起来像证书坏了，其实只是没人实现这个方法。
 */
class MethodHandlerPlugin : AndroidFlutterPlugin() {

    /** 供 root 模式读取本 App uid（用于把自身流量排除在重定向之外，防止死循环） */
    private var appContext: Context? = null

    /**
     * su 调用必须离开 platform 主线程。
     *
     * 首次调用会弹 root 授权框（Magisk 默认 15s 超时），而 RootProxyManager.start()
     * 内部是 stop + start + verify，最多 6 次 su 进程 fork。放在主线程上执行
     * 会直接触发 ANR（输入事件 5s 无响应）。
     */
    private val rootExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** MethodChannel.Result 必须在 platform 主线程回调 */
    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: MethodChannel.Result, message: String?) {
        mainHandler.post { result.error("ERROR", message, null) }
    }

    companion object {
        private const val TAG = "MethodHandlerPlugin"
        const val CHANNEL = "com.proxypin/method"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        val channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        // 整个 handler 必须兜住异常并回 result：漏掉的话 Flutter 侧 await 会永久挂起
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // 本地网络访问权限只有 iOS 需要，Android 恒为可用
                    "requestLocalNetwork" -> result.success(true)

                    // 根证书是否已在信任库中（系统证书目录或用户凭据）
                    "isCaInstalled" -> result.success(isCaInstalled(call.argument<String>("pem")))

                    // Android 侧不做钥匙串级别的证书链信任校验，交回 Dart 侧按自身策略处理
                    "evaluateChainTrusted" -> result.success(false)

                    // 证书装在“系统信任库”还是“用户凭据”
                    // （上游 #200 / #652 / #728 / #741 这类“装了证书但抓不到 HTTPS”的诊断用）
                    "caInstallScope" -> result.success(caInstallScope(call.argument<String>("pem")))

                    // ---- root 模式抓包（上游 #839 Feature Request 2）----
                    // 只有用户在设置里主动开启时才会走到这几条。它们都会 fork su
                    // （首次还会弹授权框），不能在主线程执行，见 rootExecutor 注释。
                    "isRootAvailable", "isRootProxyRunning", "stopRootProxy", "cleanupRootProxy" -> {
                        rootExecutor.execute {
                            try {
                                val value: Any = when (call.method) {
                                    "isRootAvailable" -> RootProxyManager.isRootAvailable()
                                    "isRootProxyRunning" -> RootProxyManager.isRootProxyRunning()
                                    "stopRootProxy" -> mapOf("success" to RootProxyManager.stop())
                                    else -> RootProxyManager.cleanupStale()
                                }
                                postSuccess(result, value)
                            } catch (e: Throwable) {
                                Log.w(TAG, "root call ${call.method} failed", e)
                                postError(result, e.message)
                            }
                        }
                    }

                    "startRootProxy" -> {
                        val port = call.argument<Int>("port") ?: 0
                        val uid = appContext?.applicationInfo?.uid ?: -1
                        rootExecutor.execute {
                            try {
                                val started = RootProxyManager.start(port, uid)
                                postSuccess(result, mapOf("success" to started.first, "message" to started.second))
                            } catch (e: Throwable) {
                                Log.w(TAG, "startRootProxy failed", e)
                                postError(result, e.message)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                Log.w(TAG, "onMethodCall ${call.method} failed", e)
                result.error("ERROR", e.message, null)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        rootExecutor.shutdownNow()
        super.onDetachedFromEngine(binding)
    }

    /**
     * 给定 PEM 证书是否已安装到 Android 信任库。
     *
     * 通过 AndroidCAStore 读取，无需 root：以 "system:" 前缀出现的是预置/root 写入的证书
     * （Magisk 模块或写 /system/etc/security/cacerts、Android 14+ 的 /apex/com.android.conscrypt/cacerts），
     * 以 "user:" 前缀出现的是用户在「设置 → 安全 → 加密与凭据」里手动安装的证书。按 DER 字节比对。
     */
    /**
     * 证书到底装在哪：返回 "system" / "user" / "none"。
     *
     * AndroidCAStore 的 alias 前缀天然区分两者："system:" 是预置或 root 写入
     * 系统目录的，"user:" 是用户在「设置 → 安全 → 加密与凭据」里手动装的。
     * Android 7 起应用默认不信任用户证书——所以这个区分直接决定了
     * “抓不到 HTTPS”的原因归属（很多反馈里其实是装进了用户库）。
     */
    private fun caInstallScope(pem: String?): String {
        if (pem.isNullOrBlank()) {
            return "none"
        }

        val target = try {
            CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(pem.toByteArray(Charsets.UTF_8))) as X509Certificate
        } catch (e: Throwable) {
            Log.w(TAG, "parse pem failed", e)
            return "none"
        }

        return try {
            val keyStore = KeyStore.getInstance("AndroidCAStore")
            keyStore.load(null, null)
            val aliases = keyStore.aliases()
            var fallback = "none"
            while (aliases.hasMoreElements()) {
                val alias = aliases.nextElement()
                val certificate = keyStore.getCertificate(alias) as? X509Certificate ?: continue
                if (certificate.encoded.contentEquals(target.encoded)) {
                    // 系统库优先：只要有一处是系统库，对 App 就生效
                    if (alias.startsWith("system:")) return "system"
                    fallback = "user"
                }
            }
            fallback
        } catch (e: Throwable) {
            Log.w(TAG, "read AndroidCAStore failed", e)
            "none"
        }
    }

    private fun isCaInstalled(pem: String?): Boolean {
        if (pem.isNullOrBlank()) {
            return false
        }

        val target = try {
            CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(pem.toByteArray(Charsets.UTF_8))) as X509Certificate
        } catch (e: Throwable) {
            Log.w(TAG, "parse pem failed", e)
            return false
        }

        return try {
            val keyStore = KeyStore.getInstance("AndroidCAStore")
            keyStore.load(null, null)
            val aliases = keyStore.aliases()
            while (aliases.hasMoreElements()) {
                val alias = aliases.nextElement()
                val certificate = keyStore.getCertificate(alias) as? X509Certificate ?: continue
                if (certificate.encoded.contentEquals(target.encoded)) {
                    Log.d(TAG, "CA already installed, alias=$alias")
                    return true
                }
            }
            false
        } catch (e: Throwable) {
            Log.w(TAG, "read AndroidCAStore failed", e)
            false
        }
    }
}
