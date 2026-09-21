package com.network.proxy.plugin

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

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

                    // ---- root 模式抓包（上游 #839 Feature Request 2）----
                    // 只有用户在设置里主动开启时才会走到这几条，
                    // 它们会执行 su，首次调用弹出 root 授权框属预期行为。
                    "isRootAvailable" -> result.success(RootProxyManager.isRootAvailable())

                    "isRootProxyRunning" -> result.success(RootProxyManager.isRootProxyRunning())

                    "startRootProxy" -> {
                        val port = call.argument<Int>("port") ?: 0
                        val uid = appContext?.applicationInfo?.uid ?: -1
                        val started = RootProxyManager.start(port, uid)
                        result.success(mapOf("success" to started.first, "message" to started.second))
                    }

                    "stopRootProxy" -> result.success(mapOf("success" to RootProxyManager.stop()))

                    "cleanupRootProxy" -> result.success(RootProxyManager.cleanupStale())

                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                Log.w(TAG, "onMethodCall ${call.method} failed", e)
                result.error("ERROR", e.message, null)
            }
        }
    }

    /**
     * 给定 PEM 证书是否已安装到 Android 信任库。
     *
     * 通过 AndroidCAStore 读取，无需 root：以 "system:" 前缀出现的是预置/root 写入的证书
     * （Magisk 模块或写 /system/etc/security/cacerts、Android 14+ 的 /apex/com.android.conscrypt/cacerts），
     * 以 "user:" 前缀出现的是用户在「设置 → 安全 → 加密与凭据」里手动安装的证书。按 DER 字节比对。
     */
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
