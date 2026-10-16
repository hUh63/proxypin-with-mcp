package com.network.proxy.shizuku

import android.content.Context
import android.os.Process
import android.os.SystemClock
import androidx.annotation.Keep
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Shizuku UserService 的实现。
 *
 * ⚠️ 本类**不会**运行在 ProxyPin 自己的进程里，也**不是** android.app.Service：
 * Shizuku 服务端（以 shell/root 身份运行）通过 `Class.forName(类名)` 加载本类并实例化，
 * 然后把实例暴露给调用方。因此有三条硬性约束：
 *   1) 不能继承 Service，也**不需要**（也不能）在 AndroidManifest 里注册；
 *   2) 必须提供无参构造器，并额外提供带 Context 的构造器（Shizuku API 13+ 会优先使用后者）；
 *      带 Context 的构造器必须标注 @Keep，否则 R8 会把它删掉；
 *   3) 类名与构造器都必须保留（见 proguard-rules.pro 的 keep 规则）。
 *
 * 因为运行身份已经是 shell(uid 2000) 或 root(uid 0)，这里直接 fork 子进程即可，不需要 su。
 */
class ShizukuShellService : IShellService.Stub {

    /** 无参构造器（Shizuku 会优先尝试带 Context 的那个，失败时回退到这里）。 */
    constructor() : super()

    @Keep
    constructor(context: Context) : super()

    /** Shizuku 服务器保留的销毁入口。 */
    override fun destroy() {
        System.exit(0)
    }

    override fun exit() {
        destroy()
    }

    override fun exec(command: String, timeoutMs: Long): String {
        val json = JSONObject()
        try {
            val process = ProcessBuilder("sh", "-c", command).start()
            // 命令不读 stdin，立即关闭避免子进程等待
            runCatching { process.outputStream.close() }

            val stdout = StringBuilder()
            val stderr = StringBuilder()
            val tOut = Thread {
                runCatching { process.inputStream.bufferedReader().use { stdout.append(it.readText()) } }
            }
            val tErr = Thread {
                runCatching { process.errorStream.bufferedReader().use { stderr.append(it.readText()) } }
            }
            val start = SystemClock.elapsedRealtime()
            tOut.start()
            tErr.start()

            val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            if (!finished) process.destroyForcibly()
            runCatching { tOut.join(500) }
            runCatching { tErr.join(500) }

            json.put("exitCode", if (finished) process.exitValue() else -1)
            json.put("stdout", stdout.toString())
            json.put("stderr", stderr.toString())
            json.put("timedOut", !finished)
            json.put("elapsedMs", SystemClock.elapsedRealtime() - start)
            json.put("uid", Process.myUid())
        } catch (e: Throwable) {
            json.put("exitCode", -1)
            json.put("stdout", "")
            json.put("stderr", "exec failed: ${e.message}")
            json.put("timedOut", false)
            json.put("uid", Process.myUid())
        }
        return json.toString()
    }

    override fun screencap(): ByteArray {
        return try {
            val process = ProcessBuilder("sh", "-c", "screencap -p").start()
            val bytes = process.inputStream.readBytes()
            process.waitFor(10, TimeUnit.SECONDS)
            bytes
        } catch (e: Throwable) {
            ByteArray(0)
        }
    }
}
