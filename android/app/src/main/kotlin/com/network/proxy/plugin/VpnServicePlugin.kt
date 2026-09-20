package com.network.proxy.plugin

import android.util.Log
import com.network.proxy.ProxyVpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class VpnServicePlugin : AndroidFlutterPlugin() {
    companion object {
        const val CHANNEL = "com.proxy/proxyVpn"
        const val REQUEST_CODE: Int = 24
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        // 整个 handler 必须兜住异常：漏掉的话 result 永不回调，
        // Flutter 侧 `await invokeMethod` 会永久挂起（VPN 状态、重启流程全部卡住）
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isRunning" -> {
                        result.success(ProxyVpnService.isRunning)
                    }

                    "getQuicBlockedCount" -> {
                        result.success(ProxyVpnService.quicBlockedCount.get())
                    }

                    "startVpn" -> {
                        val host = call.argument<String>("proxyHost")
                        val port = call.argument<Int>("proxyPort")
                        if (host == null || port == null) {
                            result.error("INVALID_ARGUMENT", "proxyHost/proxyPort is required", null)
                            return@setMethodCallHandler
                        }

                        val allowApps = call.argument<ArrayList<String>>("allowApps")
                        val disallowApps = call.argument<ArrayList<String>>("disallowApps")
                        val setSystemProxy = call.argument<Boolean>("setSystemProxy") ?: true
                        val proxyPassDomains = call.argument<ArrayList<String>>("proxyPassDomains")
                        val blockQuic = call.argument<Boolean>("blockQuic") ?: ProxyVpnService.blockQuic
                        val quicProbe = call.argument<Boolean>("quicProbe") ?: ProxyVpnService.quicProbeEnabled

                        val prepareVpn = ProxyVpnService.prepareVpn(
                            activity,
                            host,
                            port,
                            allowApps,
                            disallowApps,
                            setSystemProxy,
                            proxyPassDomains
                        )
                        if (prepareVpn) {
                            startVpn(
                                host,
                                port,
                                allowApps,
                                disallowApps,
                                setSystemProxy,
                                proxyPassDomains,
                                blockQuic,
                                quicProbe
                            )
                        }
                        result.success(prepareVpn)
                    }

                    "stopVpn" -> {
                        stopVpn()
                        result.success(null)
                    }

                    "restartVpn" -> {
                        val host = call.argument<String>("proxyHost")
                        val port = call.argument<Int>("proxyPort")
                        if (host == null || port == null) {
                            result.error("INVALID_ARGUMENT", "proxyHost/proxyPort is required", null)
                            return@setMethodCallHandler
                        }

                        val allowApps = call.argument<ArrayList<String>>("allowApps")
                        val disallowApps = call.argument<ArrayList<String>>("disallowApps")
                        val setSystemProxy = call.argument<Boolean>("setSystemProxy") ?: true
                        val proxyPassDomains = call.argument<ArrayList<String>>("proxyPassDomains")

                        val blockQuic = call.argument<Boolean>("blockQuic") ?: ProxyVpnService.blockQuic
                        val quicProbe = call.argument<Boolean>("quicProbe") ?: ProxyVpnService.quicProbeEnabled
                        stopVpn()
                        startVpn(
                            host,
                            port,
                            allowApps,
                            disallowApps,
                            setSystemProxy,
                            proxyPassDomains,
                            blockQuic,
                            quicProbe
                        )
                        result.success(null)
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Throwable) {
                Log.w("ProxyPin", "vpn method ${call.method} failed", e)
                result.error("VPN_ERROR", e.message ?: e.toString(), null)
            }
        }
    }

    /**
     * 启动vpn服务
     */
    private fun startVpn(
        host: String,
        port: Int,
        allowApps: ArrayList<String>? = arrayListOf(),
        disallowApps: ArrayList<String>? = arrayListOf(),
        setSystemProxy: Boolean = true,
        proxyPassDomains: ArrayList<String>? = null,
        blockQuic: Boolean = ProxyVpnService.blockQuic,
        quicProbeEnabled: Boolean = ProxyVpnService.quicProbeEnabled
    ) {
        val intent = ProxyVpnService.startVpnIntent(
            activity,
            host,
            port,
            allowApps,
            disallowApps,
            setSystemProxy,
            proxyPassDomains,
            blockQuic,
            quicProbeEnabled
        )
        activity.startService(intent)
    }

    /**
     * 停止vpn服务
     */
    private fun stopVpn() {
        activity.startService(ProxyVpnService.stopVpnIntent(activity))
    }
}