/*
 * NetFilter SDK 原生桥（Windows）—— 头文件。
 *
 * 目的：把 NetFilter SDK 的 NF_EventHandler 回调与 NF_TCP_CONN_INFO 改写都留在
 * **原生侧（C++）**，只把「控制 + 查询」通过这组 C ABI 暴露给 Dart。
 *
 * 为什么必须原生：NetFilter 会从它自己的线程**同步**回调，并要求在
 * tcpConnectRequest 里同步改写传入的 connInfo（改 remoteAddress / filteringFlag），
 * 指针在回调返回后即失效。Dart FFI 只有「同线程同步」或「跨线程异步」两种回调，
 * 都无法满足，故数据面只能留在原生。
 *
 * 编译产物：netfilter_bridge.dll（放到 proxypin 的 exe 同目录）。
 * 依赖：NetFilter SDK 的 nfapi.h / nfapi.lib（**需你自备，本仓库不包含**）。
 */
#ifndef NETFILTER_BRIDGE_H
#define NETFILTER_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define NFB_API __declspec(dllexport)
#else
#define NFB_API
#endif

/// 初始化：driverName 传 "nfdriver"（SDK 默认驱动名）；relayPort 是本地中继端口；
/// selfPid 用于跳过本进程自身的流量（避免回环）。成功返回 0，否则返回 NF_STATUS。
NFB_API int nfb_start(const char* driverName, unsigned short relayPort, unsigned int selfPid);

/// 为某个 TCP 目的端口添加「出站 + 指示连接请求」规则。成功返回 0。
NFB_API int nfb_add_tcp_rule(unsigned short port);

/// 停止并清理（删除规则、关闭驱动、清空 NAT 表）。
NFB_API void nfb_stop(void);

/// 查询某条连接的原始目的地址（由 tcpConnectRequest 记录）。
/// 找到返回 1 并写出 outIp / outPort；否则返回 0。
NFB_API int nfb_lookup_original(unsigned int clientIp, unsigned short clientPort,
                                unsigned int* outIp, unsigned short* outPort);

/// 读取累计计数（任一出参可为 NULL）。返回已重定向的连接数。
NFB_API unsigned long long nfb_get_counters(unsigned long long* syn, unsigned long long* connected,
                                            unsigned long long* closed, unsigned long long* skipped);

#ifdef __cplusplus
}
#endif
#endif /* NETFILTER_BRIDGE_H */
