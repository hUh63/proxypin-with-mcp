package com.network.proxy.plugin

import android.util.Log
import java.util.concurrent.TimeUnit

/**
 * root 模式抓包（上游 #839 Feature Request 2）。
 *
 * 思路：不启用 VPN，而是用 root 权限往 nat 表加一条 OUTPUT 重定向规则，
 * 把本机出站的 TCP 连接转到 ProxyPin 的代理端口。这样能绕开
 * 「应用检测到 VPN/系统代理就拒绝联网」这类规避手段——正是 issue 里被点名想要的能力。
 * 用户不开启时，本类不会执行任何特权命令（连 su 都不会唤起）。
 *
 * 安全约定（写错会让设备断网，务必遵守）：
 *  1. 所有规则都挂在我们自己的链 [CHAIN] 下，绝不直接改系统既有规则；
 *  2. 链内先排除回环地址与**本 App 自身的 uid**，避免代理自己的出站流量被再次
 *     重定向回去形成死循环；
 *  3. 关闭时先摘掉 OUTPUT 里的引用（-D），再 flush / delete 链；顺序反了会留下
 *     引用着空链的规则；
 *  4. 只处理 IPv4。不碰 ip6tables——我们的代理端口只监听 IPv4，把 IPv6 流量引过去
 *     只会让 IPv6 站点全部连不上；
 *  5. start() 失败一律回滚（调 stop()），绝不把设备留在半开状态。
 */
object RootProxyManager {

    private const val TAG = "RootProxyManager"

    /** 自建链名，避免与系统/其它工具的规则混淆 */
    private const val CHAIN = "PROXYPIN"

    private const val TIMEOUT_SECONDS = 15L

    /** 执行一条（或分号分隔的多条）shell 命令，返回 exitCode 与合并后的输出。 */
    private fun run(command: String): Pair<Int, String> = try {
        val process = ProcessBuilder("su", "-c", command)
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        if (!process.waitFor(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            process.destroy()
            -1 to "timeout: $output"
        } else {
            process.exitValue() to output
        }
    } catch (e: Throwable) {
        Log.w(TAG, "run failed: $command", e)
        -1 to (e.message ?: "exec failed")
    }

    /** 设备是否已 root 且用户已授权 su。首次调用会弹出授权框。 */
    fun isRootAvailable(): Boolean {
        val (code, output) = run("id")
        return code == 0 && output.contains("uid=0")
    }

    /** 重定向是否正在生效（OUTPUT 链里还有我们的跳转） */
    fun isRootProxyRunning(): Boolean {
        val (code, output) = run("iptables -t nat -S OUTPUT")
        if (code != 0) return false
        return output.lineSequence().any { it.contains("-j $CHAIN") }
    }

    /**
     * 开启重定向。
     *
     * @param port 代理监听端口
     * @param appUid 本 App 的 uid，用于把自身流量排除在外
     * @return Pair(是否成功, 失败原因)
     */
    fun start(port: Int, appUid: Int): Pair<Boolean, String> {
        if (port !in 1..65535) {
            return false to "invalid port: $port"
        }
        // 幂等：先清掉可能残留的旧链，避免叠加出重复规则
        stop()

        val script = buildString {
            append("iptables -t nat -N $CHAIN; ")
            append("iptables -t nat -A $CHAIN -d 127.0.0.0/8 -j RETURN; ")
            if (appUid > 0) {
                append("iptables -t nat -A $CHAIN -m owner --uid-owner $appUid -j RETURN; ")
            }
            append("iptables -t nat -A $CHAIN -p tcp -j REDIRECT --to-ports $port; ")
            append("iptables -t nat -A OUTPUT -p tcp -j $CHAIN")
        }

        val (code, output) = run(script)
        if (code != 0 || !isRootProxyRunning()) {
            // 失败立刻回滚，绝不把设备留在"规则半装"的状态
            stop()
            val reason = output.trim().ifBlank { "exit=$code" }
            Log.w(TAG, "start root proxy failed: $reason")
            return false to reason
        }

        Log.i(TAG, "root proxy started on port $port (uid=$appUid)")
        return true to ""
    }

    /** 关闭重定向并清理自建链。 */
    fun stop(): Boolean {
        // 先摘引用，再清链（顺序不可颠倒）
        run("iptables -t nat -D OUTPUT -p tcp -j $CHAIN")
        run("iptables -t nat -F $CHAIN")
        val (code, _) = run("iptables -t nat -X $CHAIN")
        Log.i(TAG, "root proxy stopped (exit=$code)")
        return code == 0
    }

    /**
     * 启动时清理残留规则。
     *
     * 上一次异常退出（进程被杀、断电）可能把重定向规则留在内核里，此时设备表现为
     * "能连 WiFi 但所有 App 上不了网"。这里只在链确实存在时才动手，避免无缘无故
     * 唤起 su 授权框。
     */
    fun cleanupStale(): Boolean {
        val (code, output) = run("iptables -t nat -L $CHAIN -n")
        if (code != 0 || output.isBlank()) {
            return true
        }
        Log.w(TAG, "stale root proxy chain found, cleaning up")
        return stop()
    }
}
