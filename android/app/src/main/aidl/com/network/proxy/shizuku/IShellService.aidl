// Shizuku UserService 接口。
//
// 用途：在 Shizuku 提供的身份下执行命令 ——
//   * Shizuku 由 ADB 启动 => 进程 uid 2000 (shell)
//   * Shizuku 由 root 启动 => 进程 uid 0 (root)
// 相比已废弃的 Shizuku.newProcess()，UserService 是官方指定的替代方案
// （见 Shizuku changelog 13.1.3 "Prepare to remove Shizuku#newProcess"）。
//
// 重要：destroy() 的事务码 16777114 是 Shizuku 服务器保留的固定值，必须原样保留，
// 否则 UserService 的生命周期管理会失效。用户自定义方法从 1 开始编号。
// 参考官方 demo：demo/src/main/aidl/rikka/shizuku/demo/IUserService.aidl
package com.network.proxy.shizuku;

interface IShellService {
    /** Shizuku 服务器保留的销毁入口（事务码固定为 16777114，勿改）。 */
    void destroy() = 16777114;

    /** 用户自定义：主动退出。 */
    void exit() = 1;

    /**
     * 执行一条 shell 命令。
     * 返回 JSON 字符串：{"exitCode":int,"stdout":str,"stderr":str,"timedOut":bool,"elapsedMs":long,"uid":int}
     */
    String exec(String command, long timeoutMs) = 2;

    /** 执行 screencap，返回 PNG 原始字节；失败时返回长度为 0 的数组。 */
    byte[] screencap() = 3;
}
