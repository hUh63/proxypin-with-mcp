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
import com.network.proxy.shizuku.IShellService
import com.network.proxy.shizuku.ShizukuShellService
import com.rosan.dhizuku.api.Dhizuku
import com.rosan.dhizuku.api.DhizukuRequestPermissionListener
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import android.content.ComponentName
import android.content.ServiceConnection
import android.os.IBinder

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

        /** Dhizuku 应用包名（官方包名是 com.rosan.dhizuku，不存在 me.bmax / com.bmax）。 */
        private const val DHIZUKU_PACKAGE = "com.rosan.dhizuku"

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
                    call.argument<Boolean>("autoDock")?.let { intent.putExtra("autoDock", it) }
                    // 仅在调用方显式提供颜色/透明度时才下发，避免「只切开关」把球重置为默认样式。
                    // 注意：Dart int 超出 Int 范围时（如 ARGB 颜色值）会解码为 Long，必须按 Number 取值再转 Int
                    (call.argument<Any?>("color") as? Number)?.let { intent.putExtra("color", it.toInt()) }
                    (call.argument<Any?>("alpha") as? Number)?.let { intent.putExtra("alpha", it.toInt()) }
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
        // Dhizuku 是否已安装：用于区分「未安装」与「已安装但未授权」两种状态，界面文案更精确
        val dhizukuInstalled = isDhizukuInstalled()

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
            "dhizukuInstalled" to dhizukuInstalled,
            "accessibilityEnabled" to accessibilityEnabled,
            "mode" to mode
        )
    }

    private fun getCurrentActivity(): String {
        if (McpAccessibilityService.isRunning() && McpAccessibilityService.currentPackage.isNotEmpty()) {
            return "${McpAccessibilityService.currentPackage}/${McpAccessibilityService.currentClassName}"
        }
        // 无无障碍服务：走特权 shell（root > Shizuku > Dhizuku）读 dumpsys
        if (hasRoot() || hasShizuku() || hasDhizuku()) {
            val out = shellWithMode(
                "dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity'",
                "auto", 5000L
            )["stdout"].toString()
            if (out.isNotBlank()) return out
        }
        return "unknown (no accessibility / Shizuku / Dhizuku / root)"
    }

    // ==================== UI Dump ====================

    private fun dumpUi(clickableOnly: Boolean, packageFilter: String?): String {
        val service = McpAccessibilityService.instance
        if (service != null) {
            return service.dumpUi(clickableOnly, packageFilter)
        }
        // 无无障碍服务：走特权 shell（root > Shizuku > Dhizuku）执行 uiautomator dump
        if (hasRoot() || hasShizuku() || hasDhizuku()) {
            return dumpUiViaShell(clickableOnly, packageFilter)
        }
        throw UnsupportedOperationException("No accessibility service, Shizuku, Dhizuku or root available. Enable accessibility in settings.")
    }

    /**
     * Dump UI hierarchy via 特权 shell（root / Shizuku / Dhizuku）执行 uiautomator dump。
     * 输出解析与无障碍路径保持一致（parseUiautomatorXml）。
     */
    private fun dumpUiViaShell(clickableOnly: Boolean, packageFilter: String?): String {
        val result = shellWithMode("uiautomator dump /dev/fd/1", "auto", 20_000L)
        var xml = result["stdout"].toString()
        val exitCode = (result["exitCode"] as? Number)?.toInt() ?: -1

        if (exitCode != 0 || xml.isBlank()) {
            // 部分 ROM 不支持 /dev/fd/1，退回写临时文件再 cat
            val fallback = shellWithMode(
                "uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1; cat /sdcard/window_dump.xml",
                "auto", 20_000L
            )
            xml = fallback["stdout"].toString()
            if (xml.isBlank()) {
                throw RuntimeException("uiautomator dump failed (exit=$exitCode): ${result["stderr"]}")
            }
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

    /**
     * 通过「特权 shell」执行命令：自动在 root > Shizuku > Dhizuku 中选择可用通道。
     *
     * 用途：在**未开启无障碍服务**时，为 tap / click / swipe / keyEvent / inputText / dumpUi
     * 提供等价能力 —— Shizuku 的 shell 身份（uid 2000）本来就可以执行 input / uiautomator，
     * 截图甚至只有 Shizuku/root 能做到（无障碍服务做不到）。
     */
    private fun runPrivilegedShell(command: String, timeoutMs: Long = 10_000L): Boolean {
        if (!hasRoot() && !hasShizuku() && !hasDhizuku()) return false
        val result = shellWithMode(command, "auto", timeoutMs)
        return result["success"] == true
    }

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
        return runPrivilegedShell("input tap $x $y")
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
        return runPrivilegedShell("input swipe $x $y $x $y $duration")
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
        return runPrivilegedShell("input swipe $x1 $y1 $x2 $y2 $duration")
    }

    private fun keyEvent(keycode: Int): Boolean {
        val service = McpAccessibilityService.instance
        // 仅 HOME(3)/BACK(4)/POWER(26)/RECENTS(187) 可通过无障碍服务处理
        val accessibilitySupported = listOf(3, 4, 26, 187).contains(keycode)
        if (service != null && accessibilitySupported) {
            return service.performGlobalActionByKeycode(keycode)
        }
        // 其它键码 / 无无障碍服务：走特权 shell（root > Shizuku > Dhizuku）
        if (runPrivilegedShell("input keyevent $keycode")) return true
        if (service != null && !accessibilitySupported) {
            throw UnsupportedOperationException("Keycode $keycode is not supported by accessibility service. Supported: 3=HOME, 4=BACK, 26=POWER, 187=RECENTS. Use root/Shizuku for other keys.")
        }
        throw UnsupportedOperationException("No accessibility service, Shizuku, Dhizuku or root available")
    }

    private fun inputText(text: String): Boolean {
        val service = McpAccessibilityService.instance
        if (service != null) {
            return service.setText(text)
        }
        // 无无障碍服务：走特权 shell（root > Shizuku > Dhizuku）执行 input text。
        // 注意 input text 的空格要写成 %s、换行写成 %n，其余特殊字符需要转义
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
        return runPrivilegedShell("input text \"$escaped\"")
    }

    // ==================== Screenshot ====================

    /**
     * 截图。
     *
     * 通道优先级：root（su + screencap）> Shizuku（UserService 内直接 screencap）。
     * 无障碍服务**无法**截图，所以对非 root 用户来说 Shizuku 是唯一可用的自动化截图途径；
     * 两者都不可用时才报错（MediaProjection 方案尚未实现）。
     */
    private fun screenshot(): String {
        if (hasRoot()) {
            return screenshotViaRoot()
        }
        if (hasShizuku()) {
            try {
                val svc = ensureShizukuUserService()
                if (svc != null) {
                    val bytes = svc.screencap()
                    if (bytes.isNotEmpty()) return Base64.encodeToString(bytes, Base64.NO_WRAP)
                }
            } catch (e: Throwable) {
                Log.w("ProxyPin", "screenshot via shizuku failed", e)
            }
        }
        throw UnsupportedOperationException("Screenshot requires root or Shizuku. Non-root MediaProjection not yet implemented.")
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

    /**
     * 请求 Dhizuku 授权（官方 API）。
     *
     * 说明：Dhizuku 的 DhizukuRequestPermissionListener 是 abstract class（继承自 AIDL Stub），
     * **不是 interface**，因此 java.lang.reflect.Proxy 无法构造它 —— 这是必须引入官方依赖
     * io.github.iamr0s:Dhizuku-API 的原因（此前用反射调用一个并不存在的包名
     * com.bmax.dhizuku.api，导致授权永远静默失败）。
     *
     * 流程：init() 连接 Dhizuku 服务 -> isPermissionGranted() 已授权直接返回 true ->
     * 否则 requestPermission(listener) 拉起 Dhizuku 授权界面，用户允许后回调返回结果。
     */
    private fun requestDhizukuAuthorization(): Boolean {
        return try {
            val ctx = context ?: return openDhizukuApp()
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return openDhizukuApp()
            // init() 返回 false => 未安装 Dhizuku 或其服务不可用
            if (!Dhizuku.init(ctx)) return openDhizukuApp()
            if (Dhizuku.isPermissionGranted()) return true

            val granted = AtomicBoolean(false)
            val latch = CountDownLatch(1)
            Dhizuku.requestPermission(object : DhizukuRequestPermissionListener() {
                override fun onRequestPermission(grantResult: Int) {
                    granted.set(grantResult == PackageManager.PERMISSION_GRANTED)
                    latch.countDown()
                }
            })
            latch.await(90, TimeUnit.SECONDS)
            // 兜底：即使回调未触发，用户在 Dhizuku 里手动授权后实时检查也会成功
            granted.get() || Dhizuku.isPermissionGranted()
        } catch (e: Throwable) {
            // API 不可用（未装 Dhizuku / 版本过旧），回退：打开 Dhizuku 应用让用户手动处理
            Log.w("ProxyPin", "requestDhizukuAuthorization failed", e)
            openDhizukuApp()
        }
    }

    /** 打开 Dhizuku 应用（回退路径）。包名固定为 com.rosan.dhizuku。 */
    private fun openDhizukuApp(): Boolean {
        return try {
            val pm = context?.packageManager ?: return false
            val dhizukuPkg = DHIZUKU_PACKAGE

            val intent = pm.getLaunchIntentForPackage(dhizukuPkg)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context?.startActivity(intent)
                true
            } else {
                val dhizukuIntent = Intent("$dhizukuPkg.action.OPEN").apply {
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
     * 检测 Dhizuku 是否「已授权可用」。
     *
     * 语义 = Dhizuku 服务可连接（已安装且已激活为 Device Owner）**且**本应用已被其授权。
     * 不再使用「仅安装即算可用」的旧逻辑：那会让 UI 显示可用、但 shell 实际执行必然失败。
     */
    @Volatile
    private var dhizukuStatus: Boolean? = null

    private fun hasDhizuku(): Boolean {
        dhizukuStatus?.let { return it }
        val result = try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                false
            } else {
                val ctx = context
                ctx != null && Dhizuku.init(ctx) && Dhizuku.isPermissionGranted()
            }
        } catch (e: Throwable) {
            false
        }
        dhizukuStatus = result
        return result
    }

    /**
     * Dhizuku 是否**已安装**（不要求已激活为 Device Owner、也不要求已授权给本应用）。
     * 只用于界面区分「未安装 Dhizuku」与「已安装但未授权」，不参与权限判定。
     */
    private fun isDhizukuInstalled(): Boolean {
        return try {
            val pm = context?.packageManager ?: return false
            pm.getPackageInfo(DHIZUKU_PACKAGE, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ---------------- Shizuku UserService（官方推荐的 shell 通道）----------------

    @Volatile
    private var shizukuShellService: IShellService? = null
    @Volatile
    private var shizukuShellBinding = false
    @Volatile
    private var shizukuShellError: String? = null
    private val shizukuShellLock = java.lang.Object()

    private val shizukuUserServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            synchronized(shizukuShellLock) {
                shizukuShellService =
                    if (binder != null && binder.pingBinder()) IShellService.Stub.asInterface(binder) else null
                shizukuShellBinding = false
                if (shizukuShellService == null) shizukuShellError = "user service binder is null"
                shizukuShellLock.notifyAll()
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            synchronized(shizukuShellLock) {
                shizukuShellService = null
                shizukuShellError = "user service disconnected"
            }
        }
    }

    /**
     * 确保 Shizuku UserService 已绑定，返回其接口（最长等待 10 秒）。
     * 绑定结果会缓存；断开后下次调用会重新绑定。
     */
    private fun ensureShizukuUserService(): IShellService? {
        shizukuShellService?.let { return it }
        if (!Shizuku.pingBinder()) return null
        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
            shizukuShellError = "permission not granted"
            return null
        }
        if (Shizuku.getVersion() < 10) {
            shizukuShellError = "requires Shizuku API 10+"
            return null
        }
        val ctx = context ?: return null
        synchronized(shizukuShellLock) {
            shizukuShellService?.let { return it }
            if (shizukuShellBinding) {
                shizukuShellLock.wait(10_000)
                return shizukuShellService
            }
            shizukuShellBinding = true
            shizukuShellError = null
            try {
                val args = Shizuku.UserServiceArgs(
                    ComponentName(ctx.packageName, ShizukuShellService::class.java.name))
                    .daemon(false)
                    .processNameSuffix("shizuku_shell")
                    .debuggable(false)
                    .version(1)
                Shizuku.bindUserService(args, shizukuUserServiceConnection)
                shizukuShellLock.wait(10_000)
            } catch (e: Throwable) {
                shizukuShellError = e.message
                shizukuShellBinding = false
            }
            return shizukuShellService
        }
    }

    /**
     * 通过 Shizuku 执行 shell 命令（无需 root）。
     *
     * 通道优先级：
     *   1) UserService —— 官方推荐（Shizuku 13.1.3 起 newProcess 已被标记 "prepare to remove"）；
     *   2) newProcess —— 旧版 Shizuku 兜底（13.x 仍可用，但已 deprecated）。
     *
     * 此前用 `Class.forName("rikka.shizuku.Shizuku")` 反射调用 newProcess，在 release 构建
     * （minifyEnabled true）下随时可能因 R8 重命名而失效，现改为编译期直接调用。
     */
    private fun shellViaShizuku(command: String, timeoutMs: Long): Map<String, Any> {
        if (!Shizuku.pingBinder()) {
            return shizukuFail(command, timeoutMs, "Shizuku binder not connected")
        }
        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
            return shizukuFail(command, timeoutMs, "Shizuku permission not granted")
        }

        // 1) UserService（官方推荐路径）
        try {
            val svc = ensureShizukuUserService()
            if (svc != null) {
                val json = JSONObject(svc.exec(command, timeoutMs))
                return mapOf(
                    "success" to (json.optInt("exitCode", -1) == 0),
                    "command" to command,
                    "useSu" to false,
                    "useShizuku" to true,
                    "shizukuChannel" to "user_service",
                    "timeoutMs" to timeoutMs,
                    "timedOut" to json.optBoolean("timedOut", false),
                    "exitCode" to json.optInt("exitCode", -1),
                    "stdout" to json.optString("stdout"),
                    "stderr" to json.optString("stderr")
                )
            }
        } catch (e: Throwable) {
            shizukuShellError = e.message
        }

        // 2) newProcess 兜底（仅旧版 Shizuku）
        //    注意：Shizuku 13.1.5 起 newProcess 已变成 private，编译期不可直接调用
        //    （旧代码用 getMethod 反射同样拿不到），因此这里用 getDeclaredMethod + setAccessible。
        try {
            val newProcess = Shizuku::class.java.getDeclaredMethod(
                "newProcess",
                Array<String>::class.java,
                Array<String>::class.java,
                String::class.java
            )
            newProcess.isAccessible = true
            val process = newProcess.invoke(null, arrayOf("sh", "-c", command), null, null) as? java.lang.Process
                ?: throw IllegalStateException("Shizuku newProcess returned null")
            val stdout = process.inputStream.bufferedReader().readText()
            val stderr = process.errorStream.bufferedReader().readText()
            val completed = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            val exitCode = if (completed) process.exitValue() else -1
            if (!completed) process.destroyForcibly()
            return mapOf(
                "success" to (completed && exitCode == 0),
                "command" to command,
                "useSu" to false,
                "useShizuku" to true,
                "shizukuChannel" to "new_process",
                "timeoutMs" to timeoutMs,
                "timedOut" to !completed,
                "exitCode" to exitCode,
                "stdout" to stdout,
                "stderr" to stderr
            )
        } catch (e: Throwable) {
            val reason = shizukuShellError ?: e.message ?: "unknown"
            return shizukuFail(command, timeoutMs, "Shizuku exec unavailable: $reason")
        }
    }

    private fun shizukuFail(command: String, timeoutMs: Long, message: String): Map<String, Any> = mapOf(
        "success" to false,
        "command" to command,
        "useSu" to false,
        "useShizuku" to true,
        "timeoutMs" to timeoutMs,
        "timedOut" to false,
        "exitCode" to -1,
        "stdout" to "",
        "stderr" to "Shizuku failed: $message"
    )

    /**
     * 通过 Dhizuku 执行 shell 命令（以 Dhizuku 的 Device Owner 身份运行，无需 root）。
     *
     * 使用官方 API `Dhizuku.newProcess(String[] cmd, String[] env, File dir)`，它返回的
     * DhizukuRemoteProcess 继承 java.lang.Process。此前调用的 "execCommand" 方法在官方
     * API 里根本不存在（且包名也写错了），因此这条路径从来没能成功过。
     */
    private fun shellViaDhizuku(command: String, timeoutMs: Long): Map<String, Any> {
        return try {
            val ctx = context ?: throw IllegalStateException("no context")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                throw IllegalStateException("Dhizuku requires Android 8.0+")
            }
            if (!Dhizuku.init(ctx)) throw IllegalStateException("Dhizuku service unavailable")
            if (!Dhizuku.isPermissionGranted()) throw IllegalStateException("Dhizuku permission not granted")

            val process = Dhizuku.newProcess(arrayOf("sh", "-c", command), null, null)
            val stdout = process.inputStream.bufferedReader().readText()
            val stderr = process.errorStream.bufferedReader().readText()
            val completed = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            val exitCode = if (completed) process.exitValue() else -1
            if (!completed) process.destroyForcibly()
            mapOf(
                "success" to (completed && exitCode == 0),
                "command" to command,
                "useSu" to false,
                "useDhizuku" to true,
                "timeoutMs" to timeoutMs,
                "timedOut" to !completed,
                "exitCode" to exitCode,
                "stdout" to stdout,
                "stderr" to stderr
            )
        } catch (e: Throwable) {
            mapOf(
                "success" to false,
                "command" to command,
                "useSu" to false,
                "useDhizuku" to true,
                "timeoutMs" to timeoutMs,
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
