/*
 * NetFilter SDK 原生桥（Windows）—— 实现。
 *
 * 工作方式：在 tcpConnectRequest 里，跳过本进程流量后，把目标地址改写为
 * 127.0.0.1:relayPort，并把 filteringFlag 设为 NF_ALLOW（数据不再经过用户态，
 * 由系统直接转发到本地中继）。原始目标记录到 NAT 表，供本地中继用 CONNECT 还原。
 *
 * 与 WinDivert 不同，这里**必须**由原生侧处理回调（Dart FFI 无法满足 NetFilter 的
 * 「native 线程同步回调 + 同步改写 connInfo」模型）。
 *
 * 注意：本文件需与 NetFilter SDK 的 nfapi.h / nfapi.lib 一起编译；
 * 本仓库**不包含**这些商业文件，请自备并放到 netfilter_bridge/sdk/ 下。
 */
#include "netfilter_bridge.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <atomic>

#include "nfapi.h" // 来自 NetFilter SDK（自备）

namespace {

std::atomic<bool> g_running(false);
unsigned short g_relayPort = 0;
unsigned int g_selfPid = 0;

std::mutex g_lock;
std::unordered_map<unsigned long long, std::pair<unsigned int, unsigned short>> g_nat;

std::atomic<unsigned long long> g_syn(0), g_connected(0), g_closed(0), g_skipped(0);

inline unsigned long long nat_key(unsigned int ip, unsigned short port) {
    return (static_cast<unsigned long long>(ip) << 16) | static_cast<unsigned long long>(port);
}

void NFAPI_CC onThreadStart() {}
void NFAPI_CC onThreadEnd() {}

void NFAPI_CC onTcpConnectRequest(ENDPOINT_ID id, PNF_TCP_CONN_INFO pInfo) {
    if (!g_running || pInfo == nullptr) return;
    if (pInfo->ip_family != AF_INET) return; // 暂只处理 IPv4

    if (pInfo->processId == g_selfPid) { // 自己（代理进程）的流量不劫持
        g_skipped++;
        return;
    }

    sockaddr_in* la = reinterpret_cast<sockaddr_in*>(pInfo->localAddress);
    sockaddr_in* ra = reinterpret_cast<sockaddr_in*>(pInfo->remoteAddress);
    if (la == nullptr || ra == nullptr) return;

    const unsigned int cliIp = ::ntohl(la->sin_addr.s_addr);
    const unsigned short cliPort = ::ntohs(la->sin_port);
    const unsigned int origIp = ::ntohl(ra->sin_addr.s_addr);
    const unsigned short origPort = ::ntohs(ra->sin_port);

    {
        std::lock_guard<std::mutex> lk(g_lock);
        g_nat[nat_key(cliIp, cliPort)] = std::make_pair(origIp, origPort);
        if (g_nat.size() > 8192) g_nat.erase(g_nat.begin());
    }
    g_syn++;

    // 改写目标 → 本地中继，并放行
    ra->sin_family = AF_INET;
    ra->sin_port = ::htons(g_relayPort);
    ra->sin_addr.s_addr = ::htonl(INADDR_LOOPBACK);
    pInfo->filteringFlag = NF_ALLOW;
}

void NFAPI_CC onTcpConnected(ENDPOINT_ID, PNF_TCP_CONN_INFO) { g_connected++; }
void NFAPI_CC onTcpClosed(ENDPOINT_ID, PNF_TCP_CONN_INFO) { g_closed++; }
void NFAPI_CC onTcpReceive(ENDPOINT_ID, const char*, int) {} // NF_ALLOW 下不会触发
void NFAPI_CC onTcpSend(ENDPOINT_ID, const char*, int) {}
void NFAPI_CC onTcpCanReceive(ENDPOINT_ID) {}
void NFAPI_CC onTcpCanSend(ENDPOINT_ID) {}
void NFAPI_CC onUdpCreated(ENDPOINT_ID, PNF_UDP_CONN_INFO) {}
void NFAPI_CC onUdpConnectRequest(ENDPOINT_ID, PNF_UDP_CONN_REQUEST) {}
void NFAPI_CC onUdpClosed(ENDPOINT_ID, PNF_UDP_CONN_INFO) {}
void NFAPI_CC onUdpReceive(ENDPOINT_ID, const unsigned char*, const char*, int, PNF_UDP_OPTIONS) {}
void NFAPI_CC onUdpSend(ENDPOINT_ID, const unsigned char*, const char*, int, PNF_UDP_OPTIONS) {}
void NFAPI_CC onUdpCanReceive(ENDPOINT_ID) {}
void NFAPI_CC onUdpCanSend(ENDPOINT_ID) {}

// 与 nfapi.h 中 NF_EventHandler（_C_API）字段顺序严格一致：
// threadStart/End、tcp*(ConnectRequest/Connected/Closed/Receive/Send/CanReceive/CanSend)、
// udp*(Created/ConnectRequest/Closed/Receive/Send/CanReceive/CanSend)
NF_EventHandler g_handler = {
    onThreadStart, onThreadEnd,
    onTcpConnectRequest, onTcpConnected, onTcpClosed, onTcpReceive, onTcpSend, onTcpCanReceive, onTcpCanSend,
    onUdpCreated, onUdpConnectRequest, onUdpClosed, onUdpReceive, onUdpSend, onUdpCanReceive, onUdpCanSend,
};

bool ensure_winsock() {
    static bool done = false;
    static WSADATA wsa;
    if (!done) {
        done = (WSAStartup(MAKEWORD(2, 2), &wsa) == 0);
    }
    return done;
}

} // namespace

extern "C" {

int nfb_start(const char* driverName, unsigned short relayPort, unsigned int selfPid) {
    if (g_running) return -1;
    if (!ensure_winsock()) return -2;
    g_relayPort = relayPort;
    g_selfPid = selfPid;
    const NF_STATUS st = nf_init(driverName ? driverName : "nfdriver", &g_handler);
    if (st != NF_STATUS_SUCCESS) return static_cast<int>(st);
    g_running = true;
    return 0;
}

int nfb_add_tcp_rule(unsigned short port) {
    if (!g_running) return -1;
    NF_RULE rule;
    ::memset(&rule, 0, sizeof(rule));
    rule.protocol = IPPROTO_TCP;
    rule.direction = NF_D_OUT;
    rule.remotePort = ::htons(port); // 规则里的端口须为网络序
    rule.filteringFlag = NF_FILTER | NF_INDICATE_CONNECT_REQUESTS | NF_DISABLE_REDIRECT_PROTECTION;
    const NF_STATUS st = nf_addRule(&rule, 0 /* 追加到表尾 */);
    return (st == NF_STATUS_SUCCESS) ? 0 : static_cast<int>(st);
}

void nfb_stop(void) {
    if (!g_running) return;
    g_running = false;
    nf_deleteRules();
    nf_free();
    std::lock_guard<std::mutex> lk(g_lock);
    g_nat.clear();
}

int nfb_lookup_original(unsigned int clientIp, unsigned short clientPort,
                        unsigned int* outIp, unsigned short* outPort) {
    std::lock_guard<std::mutex> lk(g_lock);
    const auto it = g_nat.find(nat_key(clientIp, clientPort));
    if (it == g_nat.end()) return 0;
    if (outIp) *outIp = it->second.first;
    if (outPort) *outPort = it->second.second;
    return 1;
}

unsigned long long nfb_get_counters(unsigned long long* syn, unsigned long long* connected,
                                    unsigned long long* closed, unsigned long long* skipped) {
    if (syn) *syn = g_syn.load();
    if (connected) *connected = g_connected.load();
    if (closed) *closed = g_closed.load();
    if (skipped) *skipped = g_skipped.load();
    return g_syn.load();
}

} // extern "C"
