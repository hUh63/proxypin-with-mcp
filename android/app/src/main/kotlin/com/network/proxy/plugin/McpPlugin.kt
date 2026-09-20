package com.network.proxy.plugin

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * MCP Plugin for Flutter
 *
 * Bridges MCP (Model Context Protocol) commands from the Dart side to Android native
 * accessibility and shell capabilities. Registers a MethodChannel "com.proxy/mcpScreen".
 *
 * Supported methods:
 * - getDeviceInfo: returns device model, brand, Android version, WiFi IP, root/accessibility status
 * - getCurrentActivity: returns the current foreground activity
 * - dumpUi: dumps the current UI hierarchy (via accessibility service or root uiautomator)
 * - tap: performs a tap at (x, y)
 * - click: performs a long press at (x, y) for a given duration
 * - swipe: performs a swipe from (x1,y1) to (x2,y2)
 * - keyEvent: performs a global action (HOME/BACK/RECENTS/POWER/MENU)
 * - inputText: sets text on the focused element
 * - screenshot: takes a screenshot (requires root)
 * - openAccessibilitySettings: opens Android accessibility settings
 * - shell: executes a shell command (with or without su)
 *
 * Falls back to root (su) commands when the accessibility service is not available.
 */
class McpPlugin : FlutterPlugin {

    companion object {
        private const val CHANNEL_NAME = "com.proxy/mcpScreen"
        private const val SHIZUKU_REQUEST_CODE = 631

        // 原生 → Flutter 事件通道（悬浮球面板"跳转 MCP 设置"等）
        private const val TO_FLUTTER_CHANNEL = "com.proxy/toFlutter"
        @Volatile
        private var binaryMessenger: io.flutter.plugin.common.BinaryMessenger? = null

        /** 由 MainActivity 在收到跳转 MCP 设置页的 intent 时调用 */
        @JvmStatic
        fun requestOpenMcpSettings() {
            val m = binaryMessenger ?: return
            try {
                io.flutter.plugin.common.MethodChannel(m, TO_FLUTTER_CHANNEL)
                    .invokeMethod("openMcpSettings", null)
            } catch (_: Exception) {}
        }

        /**
         * 悬浮球面板内修改配置后通知 Flutter：原生直接写 FlutterSharedPreferences 时，
         * Dart 侧 SharedPreferences 内存缓存不会自动失效，设置页会读到旧值（如
         * "关闭悬浮球后进入设置页又自动启用"）；此通知让 Dart 侧同步缓存。
         */
        @JvmStatic
        fun notifyFloatingBallConfigChanged(
            enabled: Boolean? = null,
            autoDock: Boolean? = null,
            color: Int? = null,
            alpha: Int? = null
        ) {
            val m = binaryMessenger ?: return
            val payload = HashMap<String, Any?>()
            enabled?.let { payload["enabled"] = it }
            autoDock?.let { payload["autoDock"] = it }
            color?.let { payload["color"] = it }
            alpha?.let { payload["alpha"] = it }
            try {
                io.flutter.plugin.common.MethodChannel(m, TO_FLUTTER_CHANNEL)
                    .invokeMethod("floatingBallConfigChanged", payload)
            } catch (_: Exception) {}
        }
    }

    /** 悬浮球服务控制：start / stop */
    private fun handleFloatingBall(call: MethodCall): Map<String, Any> {
        val ctx = context ?: return mapOf("success" to false, "error" to "no context")
        // 权限状态查询：不触发跳转，任何情况下都返回实际状态
        if (call.method == "checkOverlay") {
            return mapOf("granted" to Settings.canDrawOverlays(ctx))
        }
        // 主动跳转悬浮窗权限设置页（由 Flutter 侧权限入口调用）
        if (call.method == "openOverlaySettings") {
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:${ctx.packageName}"))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            return mapOf("success" to true)
        }
        if (!Settings.canDrawOverlays(ctx)) {
            // 冷启动静默恢复场景不做跳转打扰；用户主动开启（非 silent）才跳权限页引导
            if (call.method == "start" && call.argument<Boolean>("silent") == true) {
                return mapOf("success" to false, "error" to "no overlay permission")
            }
            // 引导开启悬浮窗权限
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:${ctx.packageName}"))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            return mapOf("success" to false, "needOverlayPermission" to true)
        }
        val intent = Intent(ctx, FloatingBallService::class.java)
        when (call.method) {
            "start" -> {
                try {
                    intent.putExtra("autoDock", call.argument<Boolean>("autoDock") ?: true)
                    // 注意：Dart int 超出 Int 范围时（如 ARGB 颜色值）会解码为 Long，必须按 Number 取值再转 Int
                    intent.putExtra("color", (call.argument<Any?>("color") as? Number)?.toInt() ?: 0xFF6750A4.toInt())
                    intent.putExtra("alpha", (call.argument<Any?>("alpha") as? Number)?.toInt() ?: 230)
                    intent.putExtra("running", call.argument<Boolean>("running") ?: false)
                    ctx.startForegroundService(intent)
                } catch (e: Exception) {
                    // 前台服务启动失败（系统限制等）必须反馈给用户，避免"开了但没反应"
                    return mapOf("success" to false, "error" to (e.message ?: "前台服务启动失败"))
                }
            }
            "stop" -> {
                intent.action = "STOP"
                try {
                    ctx.startService(intent)
                } catch (e: Exception) {
                    return mapOf("success" to false, "error" to (e.message ?: "服务停止失败"))
                }
            }
        }
        return mapOf("success" to true)
    }

    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        binaryMessenger = binding.binaryMessenger
        // 悬浮球服务通道
        io.flutter.plugin.common.MethodChannel(binding.binaryMessenger, "com.proxy/floatingBall")
            .setMethodCallHandler { call, result ->
                Thread {
                    try {
                        val response = handleFloatingBall(call)
                        result.success(response)
                    } catch (e: Throwable) {
                        // 捕 Throwable：这里会走到 Shizuku / root / 反射相关代码，
                        // 类加载失败等 Error 不是 Exception，漏掉就会不回 result
                        Log.w("ProxyPin", "floatingBall ${call.method} failed", e)
                        result.error("FB_ERROR", e.message ?: e.toString(), null)
                    }
                }.start()
            }
        MethodChannel(binding.binaryMessenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            Thread {
                try {
                    val method = call.method
                    val args = (call.arguments as? Map<*, *>)?.mapKeys { it.key.toString() } ?: emptyMap()
                    val response = handleMethod(method, args)
                    result.success(response)
                } catch (e: Throwable) {
                    // 同上：Shizuku / 无障碍 / 反射路径可能抛 Error，必须回 result
                    Log.w("ProxyPin", "mcp method failed", e)
                    result.error("MCP_ERROR", e.message ?: e.toString(), null)
                }
            }.start()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = null
        binaryMessenger = null
    }

    /**
     * Main dispatch method for handling MCP tool calls.
     */
    @Suppress("UNCHECKED_CAST")
    private fun handleMethod(method: String, args: Map<String, Any?>): Any? {
        return when (method) {
            "getDeviceInfo" -> getDeviceInfo()
            "getCurrentActivity" -> getCurrentActivity()
            "dumpUi" -> {
                val clickableOnly = args["clickableOnly"] as? Boolean ?: false
                val packageFilter = args["packageFilter"] as? String
                dumpUi(clickableOnly, packageFilter)
            }
            "tap" -> {
                val x = (args["x"] as? Number)?.toInt() ?: 0
                val y = (args["y"] as? Number)?.toInt() ?: 0
                tap(x, y)
            }
            "click" -> {
                val x = (args["x"] as? Number)?.toInt() ?: 0
                val y = (args["y"] as? Number)?.toInt() ?: 0
                val duration = (args["duration"] as? Number)?.toLong() ?: 50L
                click(x, y, duration)
            }
            "swipe" -> {
                val x1 = (args["x1"] as? Number)?.toInt() ?: 0
                val y1 = (args["y1"] as? Number)?.toInt() ?: 0
                val x2 = (args["x2"] as? Number)?.toInt() ?: 0
                val y2 = (args["y2"] as? Number)?.toInt() ?: 0
                val duration = (args["duration"] as? Number)?.toLong() ?: 300L
                swipe(x1, y1, x2, y2, duration)
            }
            "keyEvent" -> {
                val keycode = (args["keycode"] as? Number)?.toInt() ?: 0
                keyEvent(keycode)
            }
            "inputText" -> {
                val text = args["text"] as? String ?: ""
                inputText(text)
            }
            "screenshot" -> screenshot()
            "openAccessibilitySettings" -> openAccessibilitySettings()
            "openShizukuSettings" -> openShizukuSettings()
            "requestShizukuAuthorization" -> requestShizukuAuthorization()
            "requestDhizukuAuthorization" -> requestDhizukuAuthorization()
            "requestRootAuthorization" -> requestRootAuthorization()
            "shell" -> {
                val command = args["command"] as? String ?: ""
                val useSu = args["useSu"] as? Boolean ?: false
                val mode = args["mode"] as? String
                val timeoutMs = (args["timeoutMs"] as? Number)?.toLong() ?: 10000L
                if (mode != null) shellWithMode(command, mode, timeoutMs) else shell(command, useSu, timeoutMs)
            }
            else -> throw UnsupportedOperationException("Unknown method: $method")
        }
    }

    // ==================== Device Info ====================

    private fun getDeviceInfo(): Map<String, Any> {
        val model = Build.MODEL ?: "unknown"
        val brand = Build.BRAND ?: "unknown"
        val androidVersion = Build.VERSION.RELEASE ?: "unknown"
        val sdkVersion = Build.VERSION.SDK_INT
        val wifiIp = getWifiIpAddress()
        val hasRoot = hasRoot()
        val accessibilityEnabled = McpAccessibilityService.isRunning()
        val hasShizuku = hasShizuku()
        val hasDhizuku = hasDhizuku()

        val mode = when {
            hasRoot -> "root"
            hasShizuku -> "shizuku"
            hasDhizuku -> "dhizuku"
            accessibilityEnabled -> "accessibility"
            else -> "none"
        }

        return mapOf(
            "model" to model,
            "brand" to brand,
            "androidVersion" to androidVersion,
            "sdkVersion" to sdkVersion,
            "wifiIp" to wifiIp,
            "hasRoot" to hasRoot,
            "hasShizuku" to hasShizuku,
            // 注意：hasShizuku 只代表 Shizuku binder 已连接（运行中），不代表本应用已获授权；
            // 「请求 Shizuku 授权」按钮的显隐必须依据 shizukuGranted
            "shizukuGranted" to (hasShizuku && runCatching {
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            }.getOrDefault(false)),
            "hasDhizuku" to hasDhizuku,
            "accessibilityEnabled" to accessibilityEnabled,
            "mode" to mode
        )
    }

    private fun getCurrentActivity(): String {
        if (McpAccessibilityService.isRunning() && McpAccessibilityService.currentPackage.isNotEmpty()) {
            return "${McpAccessibilityService.currentPackage}/${McpAccessibilityService.currentClassName}"
        }
        if (hasRoot()) {
            return shell("dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity'", true, 3000L)["stdout"].toString()
        }
        return "unknown (no root or accessibility)"
    }

    // ==================== UI Dump ====================

    private fun dumpUi(clickableOnly: Boolean, packageFilter: String?): String {
        val service = McpAccessibilityService.instance
        if (service != null) {
            return service.dumpUi(clickableOnly, packageFilter)
        }
        if (hasRoot()) {
            return dumpUiViaRoot(clickableOnly, packageFilter)
        }
        throw UnsupportedOperationException("No accessibility service or root available. Enable accessibility in settings.")
    }

    /**
     * Dump UI hierarchy via root uiautomator command.
     */
    private fun dumpUiViaRoot(clickableOnly: Boolean, packageFilter: String?): String {
        val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "uiautomator dump /dev/fd/1"))
        val xml = BufferedReader(InputStreamReader(process.inputStream, Charsets.UTF_8)).readText()
        val stderr = BufferedReader(InputStreamReader(process.errorStream, Charsets.UTF_8)).readText()
        val exitCode = process.waitFor()
        
        if (exitCode != 0 || xml.isBlank()) {
            throw RuntimeException("uiautomator dump failed (exit=$exitCode): $stderr")
        }

        // Extract the XML hierarchy content
        val xmlContent = if (xml.startsWith("<?xml")) {
            val startIdx = xml.indexOf("<?xml")
            val endIdx = xml.indexOf("</hierarchy>")
            if (endIdx >= 0) {
                xml.substring(startIdx, endIdx + 12)
            } else {
                xml.substring(startIdx)
            }
        } else {
            xml
        }

        return parseUiautomatorXml(xmlContent, clickableOnly, packageFilter).toString()
    }

    /**
     * Parse uiautomator XML dump into a JSONArray.
     */
    private fun parseUiautomatorXml(xml: String, clickableOnly: Boolean, packageFilter: String?): JSONArray {
        val jsonArray = JSONArray()
        val nodeRegex = Regex("<node\\s+([^>]+?)(?:/>|>)")
        val attrRegex = Regex("(\\w+)=\"([^\"]*)\"")
        val boundsRegex = Regex("\\[(\\d+),(\\d+)]\\[(\\d+),(\\d+)]")

        for (match in nodeRegex.findAll(xml)) {
            val attrs = attrRegex.findAll(match.groupValues[1]).associate { it.groupValues[1] to it.groupValues[2] }

            val clickable = attrs["clickable"] == "true"
            val packageName = attrs["package"] ?: ""

            if (clickableOnly && !clickable) continue
            if (packageFilter != null && packageName != packageFilter) continue

            val boundsStr = attrs["bounds"] ?: ""
            val boundsMatch = boundsRegex.find(boundsStr)
            val centerX: Int
            val centerY: Int
            if (boundsMatch != null) {
                val (x1, y1, x2, y2) = boundsMatch.destructured
                centerX = (x1.toInt() + x2.toInt()) / 2
                centerY = (y1.toInt() + y2.toInt()) / 2
            } else {
                centerX = 0
                centerY = 0
            }

            val resourceId = attrs["resource-id"] ?: ""
            val json = JSONObject()
            json.put("text", attrs["text"] ?: "")
            json.put("contentDesc", attrs["content-desc"] ?: "")
            json.put("resourceId", resourceId)
            json.put("resId", resolveResourceId(resourceId))
            json.put("className", attrs["class"] ?: "")
            json.put("packageName", packageName)
            json.put("clickable", clickable)
            json.put("enabled", attrs["enabled"] == "true")
            json.put("focusable", attrs["focusable"] == "true")
            json.put("scrollable", attrs["scrollable"] == "true")
            json.put("bounds", boundsStr)
            json.put("centerX", centerX)
            json.put("centerY", centerY)
            jsonArray.put(json)
        }

        return jsonArray
    }

    // ==================== Actions ====================

    private fun tap(x: Int, y: Int): Boolean {
        val service = McpAccessibilityService.instance
        if (service != null) {
            val latch = CountDownLatch(1)
            var result = false
            service.tap(x, y) { success ->
                result = success
                latch.countDown()
            }
            latch.await(10, TimeUnit.SECONDS)
            return result
        }
        if (hasRoot()) {
            shell("input tap $x $y", true, 10000L)
            return true
        }
        throw UnsupportedOperationException("No accessibility service or root available")
    }

    private fun click(x: Int, y: Int, duration: Long): Boolean {
        val service = McpAccessibilityService.instance
        if (service != null) {
            val latch = CountDownLatch(1)
            var result = false
            service.click(x, y, duration) { success ->
                result = success
                latch.countDown()
            }
            latch.await(10, TimeUnit.SECONDS)
            return result
        }
        if (hasRoot()) {
            shell("input swipe $x $y $x $y $duration", true, 10000L)
            return true
        }
        throw UnsupportedOperationException("No accessibility service or root available")
    }

    private fun swipe(x1: Int, y1: Int, x2: Int, y2: Int, duration: Long): Boolean {
        val service = McpAccessibilityService.instance
        if (service != null) {
            val latch = CountDownLatch(1)
            var result = false
            service.swipe(x1, y1, x2, y2, duration) { success ->
                result = success
                latch.countDown()
            }
            latch.await(10, TimeUnit.SECONDS)
            return result
        }
        if (hasRoot()) {
            shell("input swipe $x1 $y1 $x2 $y2 $duration", true, 10000L)
            return true
        }
        throw UnsupportedOperationException("No accessibility service or root available")
    }

    private fun keyEvent(keycode: Int): Boolean {
        val service = McpAccessibilityService.instance
        // 仅 HOME(3)/BACK(4)/POWER(26)/RECENTS(187) 可通过无障碍服务处理
        val accessibilitySupported = listOf(3, 4, 26, 187).contains(keycode)
        if (service != null && accessibilitySupported) {
            return service.performGlobalActionByKeycode(keycode)
        }
        if (hasRoot()) {
            shell("input keyevent $keycode", true, 10000L)
            return true
        }
        if (service != null && !accessibilitySupported) {
            throw UnsupportedOperationException("Keycode $keycode is not supported by accessibility service. Supported: 3=HOME, 4=BACK, 26=POWER, 187=RECENTS. Use root for other keys.")
        }
        throw UnsupportedOperationException("No accessibility service or root available")
    }

    private fun inputText(text: String): Boolean {
        val service = McpAccessibilityService.instance
        if (service != null) {
            return service.setText(text)
        }
        if (hasRoot()) {
            // 使用 Android input text 命令的安全转义
            // input text 命令中空格需用 %s 表示，其他特殊字符需要转义
            val escaped = text
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("'", "\\'")
                .replace("`", "\\`")
                .replace("$", "\\$")
                .replace("(", "\\(")
                .replace(")", "\\)")
                .replace(";", "\\;")
                .replace("|", "\\|")
                .replace("&", "\\&")
                .replace("<", "\\<")
                .replace(">", "\\>")
                .replace("\n", "%n")
                .replace(" ", "%s")
            shell("input text \"$escaped\"", true, 10000L)
            return true
        }
        throw UnsupportedOperationException("No accessibility service or root available")
    }

    // ==================== Screenshot ====================

    private fun screenshot(): String {
        if (hasRoot()) {
            return screenshotViaRoot()
        }
        throw UnsupportedOperationException("Screenshot requires root. Non-root MediaProjection not yet implemented.")
    }

    private fun screenshotViaRoot(): String {
        val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "screencap -p"))
        val bytes = process.inputStream.readBytes()
        val stderr = BufferedReader(InputStreamReader(process.errorStream, Charsets.UTF_8)).readText()
        val exitCode = process.waitFor()
        if (exitCode != 0 || bytes.isEmpty()) {
            throw RuntimeException("screencap failed (exit=$exitCode): $stderr")
        }
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    // ==================== Shell ====================

    private fun shell(command: String, useSu: Boolean, timeoutMs: Long): Map<String, Any> {
        val fullCommand = if (useSu) arrayOf("su", "-c", command) else arrayOf("sh", "-c", command)
        val process = Runtime.getRuntime().exec(fullCommand)
        val stdout = BufferedReader(InputStreamReader(process.inputStream, Charsets.UTF_8)).readText()
        val stderr = BufferedReader(InputStreamReader(process.errorStream, Charsets.UTF_8)).readText()
        val completed = process.waitFor(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
        val exitCode = if (completed) process.exitValue() else -1

        // 超时后必须销毁进程，避免资源泄漏
        if (!completed) {
            process.destroyForcibly()
        }

        return mapOf(
            "success" to (completed && exitCode == 0),
            "command" to command,
            "useSu" to useSu,
            "timeoutMs" to timeoutMs,
            "timedOut" to !completed,
            "exitCode" to exitCode,
            "stdout" to stdout,
            "stderr" to stderr
        )
    }

    // ==================== Accessibility Settings ====================

    private fun openAccessibilitySettings(): Boolean {
        val intent = Intent("android.settings.ACCESSIBILITY_SETTINGS").apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context?.startActivity(intent)
        return true
    }

    /**
     * 打开 Shizuku 授权页面
     * Shizuku 官方提供了专用授权 Intent（moe.shizuku.privileged.api 的 ACTIVITY_PERMISSION）
     */
    private fun openShizukuSettings(): Boolean {
        return try {
            val activity = Class.forName("moe.shizuku.privileged.api.constant.Intent")
            val action = activity.getField("ACTIVITY_PERMISSION").get(null) as String
            val intent = Intent(action).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context?.startActivity(intent)
            true
        } catch (e: Exception) {
            // 反射失败时退回 Shizuku 应用主页
            try {
                val pm = context?.packageManager ?: return false
                val launch = pm.getLaunchIntentForPackage("moe.shizuku.privileged.api")
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context?.startActivity(launch)
                    true
                } else false
            } catch (e2: Exception) {
                false
            }
        }
    }

    /**
     * 请求 Shizuku 授权（标准 API）
     * 已授权返回 true；未授权时在应用内直接弹出 Shizuku 的系统授权弹窗，
     * 等待用户操作后返回授权结果（最长等待 90 秒）。
     * 使用标准 binder API 后，ProxyPin 会出现在 Shizuku 的应用管理列表中。
     */
    private fun requestShizukuAuthorization(): Boolean {
        return try {
            val ctx = context ?: return false
            if (!Shizuku.pingBinder()) return false

            // 已授权直接成功（含用户在 Shizuku 应用内手动授权后）
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                return true
            }

            // requestPermission 必须在主线程调用（Shizuku 内部依赖主线程 Handler）
            var granted = false
            val latch = CountDownLatch(1)
            val listener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
                if (requestCode == SHIZUKU_REQUEST_CODE) {
                    granted = grantResult == PackageManager.PERMISSION_GRANTED
                    latch.countDown()
                }
            }
            Shizuku.addRequestPermissionResultListener(listener)
            try {
                val mainThread = android.os.Looper.getMainLooper() == android.os.Looper.myLooper()
                val requestDone = CountDownLatch(1)
                val invoke = Runnable {
                    try {
                        Shizuku.requestPermission(SHIZUKU_REQUEST_CODE)
                    } catch (e: Throwable) {
                        granted = false
                    } finally {
                        requestDone.countDown()
                    }
                }
                if (mainThread) {
                    invoke.run()
                } else {
                    android.os.Handler(android.os.Looper.getMainLooper()).post(invoke)
                }
                // 等待弹窗请求真正发出（最长 5 秒），再等待用户操作结果（最长 60 秒）
                requestDone.await(5, TimeUnit.SECONDS)
                latch.await(60, TimeUnit.SECONDS)
            } finally {
                Shizuku.removeRequestPermissionResultListener(listener)
            }
            // 兜底：即使回调未触发，用户手动授权后实时权限检查也会成功
            if (!granted) {
                granted = Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            }
            granted
        } catch (e: Throwable) {
            // 标准流程不可用时回退：打开 Shizuku 的授权页面
            return try {
                openShizukuSettings()
            } catch (e2: Exception) {
                false
            }
        }
    }

    private fun requestDhizukuAuthorization(): Boolean {
        // 优先走 Dhizuku 标准 API（应用内弹出授权弹窗），失败回退到打开 Dhizuku 应用
        try {
            val context = context ?: return openDhizukuApp()
            val clazz = Class.forName("com.bmax.dhizuku.api.Dhizuku")
            // 初始化
            clazz.getMethod("init", android.content.Context::class.java).invoke(null, context)

            val isOwnerGranted = clazz.getMethod("isOwnerGranted").invoke(null) as Boolean
            if (isOwnerGranted) {
                return true
            }

            // requestPermission 触发 Dhizuku 的标准授权弹窗，等待用户操作
            var granted = false
            val latch = CountDownLatch(1)
            val listenerInterface = Class.forName("com.bmax.dhizuku.api.Dhizuku\$OnRequestPermissionResultListener")
            val handler = java.lang.reflect.InvocationHandler { _, method, args ->
                if (method.name == "onRequestPermissionResult" && args != null && args.size >= 2) {
                    granted = (args[1] as Int) == 0
                    latch.countDown()
                }
                null
            }
            val listener = java.lang.reflect.Proxy.newProxyInstance(
                listenerInterface.classLoader, arrayOf(listenerInterface), handler)

            clazz.getMethod("addRequestPermissionResultListener", listenerInterface).invoke(null, listener)
            try {
                val requestCodeField = clazz.getField("REQUEST_PERMISSION_ID")
                val requestCode = requestCodeField.get(null) as Int
                clazz.getMethod("requestPermission", Int::class.javaPrimitiveType).invoke(null, requestCode)
                latch.await(90, TimeUnit.SECONDS)
            } finally {
                clazz.getMethod("removeRequestPermissionResultListener", listenerInterface)
                    .invoke(null, listener)
            }
            return granted
        } catch (e: Throwable) {
            // API 不可用（未装 Dhizuku / 版本过旧），回退：打开 Dhizuku 应用
            return openDhizukuApp()
        }
    }

    /** 打开 Dhizuku 应用（回退路径） */
    private fun openDhizukuApp(): Boolean {
        return try {
            val pm = context?.packageManager ?: return false
            val dhizukuPkg = "me.bmax.dhizuku"

            val intent = pm.getLaunchIntentForPackage(dhizukuPkg)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context?.startActivity(intent)
                true
            } else {
                val dhizukuIntent = Intent("me.bmax.dhizuku.action.OPEN").apply {
                    setPackage(dhizukuPkg)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context?.startActivity(dhizukuIntent)
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 请求 Root 授权
     * 通过执行 su 命令触发 Magisk/KernelSU/SuperSU 等授权弹窗
     * 注意：需要应用有请求 Root 权限的意图
     */
    private fun requestRootAuthorization(): Boolean {
        return try {
            // 执行简单的 su 命令触发 Magisk/KernelSU/SuperSU 的标准授权弹窗
            // 用户同意 → 退出码 0；拒绝或超时 → 非 0 / 未完成
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val completed = process.waitFor(15, TimeUnit.SECONDS)
            if (!completed) {
                process.destroy()
                return false
            }
            process.exitValue() == 0
        } catch (e: Exception) {
            // su 不可用或执行失败
            false
        }
    }

    // ==================== Shizuku / Dhizuku ====================

    /**
     * 检测 Shizuku 是否可用：
     * 1. Shizuku 应用已安装
     * 2. binder 已连接（用户已在 Shizuku 中授权）
     */
    @Volatile
    private var shizukuStatus: Boolean? = null
    @Volatile
    private var shizukuCheckTime: Long = 0L

    private fun hasShizuku(): Boolean {
        // 5 秒缓存，授权返回后能重新检测
        val now = System.currentTimeMillis()
        if (shizukuStatus != null && now - shizukuCheckTime < 5000) return shizukuStatus!!
        val result = try {
            // 优先使用标准 API 检测 binder 是否存活
            if (Shizuku.pingBinder()) {
                true
            } else {
                // Shizuku 未运行时，检查应用是否已安装（提示用户先启动 Shizuku）
                val pm = context?.packageManager ?: return false
                pm.getPackageInfo("moe.shizuku.privileged.api", 0)
                false
            }
        } catch (e: Exception) {
            false
        }
        shizukuStatus = result
        shizukuCheckTime = now
        return result
    }

    /**
     * 检测 Dhizuku（Device Owner 扩展）是否可用：
     * 检查 me.bmax.dhizuku 是否被授予 Device Owner 权限
     */
    @Volatile
    private var dhizukuStatus: Boolean? = null

    private fun hasDhizuku(): Boolean {
        dhizukuStatus?.let { return it }
        val result = try {
            val pm = context?.packageManager ?: return false
            val dpm = context?.getSystemService(android.content.Context.DEVICE_POLICY_SERVICE)
                    as? android.app.admin.DevicePolicyManager
            val isOwner = dpm?.isDeviceOwnerApp("me.bmax.dhizuku") == true
            // Dhizuku 未作为 device owner 时，检查其是否已安装（部分系统用其它方式激活）
            val installed = try {
                pm.getPackageInfo("me.bmax.dhizuku", 0)
                true
            } catch (e: Exception) {
                false
            }
            isOwner || installed
        } catch (e: Exception) {
            false
        }
        dhizukuStatus = result
        return result
    }

    /**
     * 通过 Shizuku 执行 shell 命令（无需 root）
     * 注：Shizuku API 13 起官方移除直接 newProcess，需改为 User Service；
     * 此处保留运行时反射以兼容旧版 Shizuku，API 13+ 将走 root/su 路径。
     */
    private fun shellViaShizuku(command: String, timeoutMs: Long): Map<String, Any> {
        try {
            if (!Shizuku.pingBinder()) throw IllegalStateException("Shizuku binder not connected")
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                throw IllegalStateException("Shizuku permission not granted")
            }
            val process = try {
                // 兼容旧版 Shizuku（< API 13）：反射调用 newProcess
                val clazz = Class.forName("rikka.shizuku.Shizuku")
                val newProcess = clazz.getMethod(
                    "newProcess",
                    Array<String>::class.java,
                    Array<String>::class.java,
                    String::class.java
                )
                newProcess.invoke(null, arrayOf("sh", "-c", command), null, null) as java.lang.Process
            } catch (e: Exception) {
                throw IllegalStateException("Shizuku newProcess unavailable (API 13+), use root mode")
            }
            val stdout = process.inputStream.bufferedReader().readText()
            val stderr = process.getErrorStream().bufferedReader().readText()
            val completed = process.waitFor(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
            val exitCode = if (completed) process.exitValue() else -1
            if (!completed) process.destroyForcibly()
            return mapOf(
                "success" to (completed && exitCode == 0),
                "command" to command,
                "useSu" to false,
                "useShizuku" to true,
                "timeoutMs" to timeoutMs,
                "timedOut" to !completed,
                "exitCode" to exitCode,
                "stdout" to stdout,
                "stderr" to stderr
            )
        } catch (e: Exception) {
            return mapOf(
                "success" to false,
                "command" to command,
                "useSu" to false,
                "useShizuku" to true,
                "timedOut" to false,
                "exitCode" to -1,
                "stdout" to "",
                "stderr" to "Shizuku failed: ${e.message}"
            )
        }
    }

    /**
     * 通过 Dhizuku 执行 shell 命令（Device Owner 权限，无需 root）
     */
    private fun shellViaDhizuku(command: String, timeoutMs: Long): Map<String, Any> {
        try {
            val clazz = Class.forName("me.bmax.dhizuku.api.Dhizuku")
            val execMethod = clazz.getMethod("execCommand", String::class.java)
            val result = execMethod.invoke(null, command) as? String ?: ""
            // execCommand 返回 {status: 0, stdout: "...", stderr: "..."} JSON
            val json = org.json.JSONObject(result)
            val code = json.optInt("status", -1)
            return mapOf(
                "success" to (code == 0),
                "command" to command,
                "useSu" to false,
                "useDhizuku" to true,
                "timeoutMs" to timeoutMs,
                "timedOut" to false,
                "exitCode" to code,
                "stdout" to json.optString("stdout", ""),
                "stderr" to json.optString("stderr", "")
            )
        } catch (e: Exception) {
            return mapOf(
                "success" to false,
                "command" to command,
                "useSu" to false,
                "useDhizuku" to true,
                "timedOut" to false,
                "exitCode" to -1,
                "stdout" to "",
                "stderr" to "Dhizuku failed: ${e.message}"
            )
        }
    }

    /**
     * 统一 shell 执行：root > shizuku > dhizuku > 普通 shell
     * [mode] 指定模式: root / shizuku / dhizuku / auto
     */
    private fun shellWithMode(command: String, mode: String, timeoutMs: Long): Map<String, Any> {
        return when (mode) {
            "root" -> shell(command, true, timeoutMs)
            "shizuku" -> shellViaShizuku(command, timeoutMs)
            "dhizuku" -> shellViaDhizuku(command, timeoutMs)
            else -> { // auto
                when {
                    hasRoot() -> shell(command, true, timeoutMs)
                    hasShizuku() -> shellViaShizuku(command, timeoutMs)
                    hasDhizuku() -> shellViaDhizuku(command, timeoutMs)
                    else -> shell(command, false, timeoutMs)
                }
            }
        }
    }

    // ==================== Utilities ====================

    // Root 状态缓存，避免每次调用都 fork su 进程
    @Volatile
    private var rootStatus: Boolean? = null

    private fun hasRoot(): Boolean {
        rootStatus?.let { return it }
        val result = try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val output = BufferedReader(InputStreamReader(process.inputStream)).readText()
            process.waitFor()
            output.contains("uid=0")
        } catch (e: Exception) {
            false
        }
        rootStatus = result
        return result
    }

    private fun getWifiIpAddress(): String {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                val name = iface.name
                if (!name.contains("wlan") && !name.contains("eth")) continue

                val addresses = iface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val addr = addresses.nextElement()
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        return addr.hostAddress ?: ""
                    }
                }
            }
        } catch (e: Exception) {
        }
        return ""
    }

    private val resourceCache = mutableMapOf<String, android.content.res.Resources?>()

    private fun resolveResourceId(resourceId: String): String {
        if (resourceId.isEmpty()) return ""
        val ctx = context ?: return ""

        try {
            val colonIndex = resourceId.indexOf(':')
            if (colonIndex <= 0) return ""

            val packageName = resourceId.substring(0, colonIndex)
            val rest = resourceId.substring(colonIndex + 1)

            val slashIndex = rest.indexOf('/')
            if (slashIndex <= 0) return ""

            val type = rest.substring(0, slashIndex)
            val name = rest.substring(slashIndex + 1)

            val resources = resourceCache.getOrPut(packageName) {
                try {
                    ctx.packageManager.getResourcesForApplication(packageName)
                } catch (e: Exception) {
                    null
                }
            } ?: return ""

            val identifier = resources.getIdentifier(name, type, packageName)
            return if (identifier != 0) "0x${Integer.toHexString(identifier)}" else ""
        } catch (e: Exception) {
            return ""
        }
    }
}
