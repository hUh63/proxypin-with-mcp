//
//  ProxyPin-Bridging-Header.h
//  Runner
//
//  Created by wanghongen on 2025/5/28.
//

// 原先这里 #import "GBPing.h" 引入 ObjC 版 ping 实现。
// 该实现（vpn/ping/GBPing*、ICMPHeader.h，合计约 40KB）在扩展里从未被调用——
// ConnectionHandler.isReachable 写死返回 true（ping 不走它），GBPingHelper 也无任何引用，
// 已随本次清理删除。ICMP echo 回包由 vpn/transport/protocol/ICMPPacket.swift 处理。
// 若将来要做真实可达性探测，再重新引入并接上调用点。

