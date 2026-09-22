//
//  MemoryMonitor.swift
//  ProxyPin
//
//  网络扩展的内存水位观测（上游 #903）。
//

import Foundation
import os.log
import Darwin

/// 观测 VPN 扩展进程的内存水位。
///
/// 为什么需要它：iOS 给网络扩展的内存上限是**独立**的（与 App 进程无关），
/// 超限时系统会直接杀掉扩展进程，表现为"网络突然全断 + 小窗消失 + 日志为空"。
/// 而 App 设置里的「内存清理」只作用于 App 进程内的请求列表，对扩展无效——
/// 所以扩展内部需要有一份自己的水位记录：
/// - 周期性写系统日志（Console.app 过滤 "extension memory" 即可看到 rss/peak/连接数/缓冲量）
/// - 通过 `handleAppMessage` 让 App 主动拉取快照（见 PacketTunnelProvider）
///
/// 本类只做观测，不改变任何转发行为。
final class MemoryMonitor {

    static let shared = MemoryMonitor()

    private let lock = NSLock()
    private var peakBytes: UInt64 = 0
    private var lastLogAt = Date.distantPast
    private let logInterval: TimeInterval = 10

    private var lastSampleAt = Date.distantPast
    private var lastBytes: UInt64 = 0
    /// 采样最小间隔：readPackets 回调可能每秒触发上百次，
    /// 不能让 task_info 这种系统调用跑在包处理热路径上
    private let sampleInterval: TimeInterval = 1

    /// 连接统计来源，由 ProxyVpnService 创建 ConnectionManager 时注入。
    /// 用 weak：ConnectionManager 的生命周期由 ProxyVpnService 持有，这里只借用。
    weak var statisticsSource: ConnectionManager?

    /// 内存压力线（上游 #903）。
    /// 超过就主动回收连接：iOS 给网络扩展的配额远小于 App 进程，
    /// “先断几条连接”永远比“扩展被系统直接杀掉（全断网）”好。
    private let pressureBytes: UInt64 = 45 * 1024 * 1024
    private let severePressureBytes: UInt64 = 60 * 1024 * 1024
    private var lastTrimAt = Date.distantPast
    private let trimInterval: TimeInterval = 5

    private init() {}

    /// 采样一次：更新峰值，并按 `logInterval` 节流写日志。返回当前占用字节数。
    ///
    /// 内部按 `sampleInterval` 做去重：热路径上高频调用时直接返回上一次的值，
    /// 避免把系统调用压进包处理循环。
    @discardableResult
    func sample(reason: String) -> UInt64 {
        lock.lock()
        let now = Date()
        if now.timeIntervalSince(lastSampleAt) < sampleInterval {
            let cached = lastBytes
            lock.unlock()
            return cached
        }
        lastSampleAt = now
        lock.unlock()

        let bytes = MemoryMonitor.currentResidentBytes()

        lock.lock()
        lastBytes = bytes
        if bytes > peakBytes {
            peakBytes = bytes
        }
        let peak = peakBytes
        let shouldLog = now.timeIntervalSince(lastLogAt) >= logInterval
        if shouldLog {
            lastLogAt = now
        }
        lock.unlock()

        if shouldLog {
            let stats = statistics()
            os_log("[extension memory] rss=%.1fMB peak=%.1fMB connections=%d buffered=%.2fMB reason=%{public}@",
                   log: OSLog.default,
                   type: .default,
                   Double(bytes) / 1048576.0,
                   Double(peak) / 1048576.0,
                   stats.connections,
                   Double(stats.bufferedBytes) / 1048576.0,
                   reason)
        }

        if bytes >= pressureBytes {
            trimConnectionsIfNeeded(bytes: bytes)
        }
        return bytes
    }

    /// 内存越线时按活跃度裁剪连接（上游 #903）。
    /// 每 trimInterval 秒最多做一次，避免在包处理热路径上反复扫表。
    private func trimConnectionsIfNeeded(bytes: UInt64) {
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastTrimAt) >= trimInterval else {
            lock.unlock()
            return
        }
        lastTrimAt = now
        lock.unlock()

        // 严重趋紧时留得更少；平时只把长尾切掉
        let target = bytes >= severePressureBytes ? 48 : 128
        let closed = statisticsSource?.trimToCount(target, reason: "extension memory \(bytes / 1048576)MB") ?? 0
        if closed > 0 {
            os_log("[extension memory] pressure rss=%.1fMB, trimmed %ld connections (target %ld)",
                   log: OSLog.default, type: .default,
                   Double(bytes) / 1048576.0, closed, target)
        }
    }

    /// 当前连接数 / 所有连接 sendBuffer 积压总量 / 单连接最大积压
    func statistics() -> (connections: Int, bufferedBytes: UInt64, maxBufferedBytes: UInt64) {
        return statisticsSource?.statistics() ?? (connections: 0, bufferedBytes: 0, maxBufferedBytes: 0)
    }

    /// 供 App 通过 sendProviderMessage 读取的快照（用户主动拉取，不做节流，取即时值）
    func snapshot() -> [String: Any] {
        let bytes = MemoryMonitor.currentResidentBytes()

        lock.lock()
        lastSampleAt = Date()
        lastBytes = bytes
        if bytes > peakBytes {
            peakBytes = bytes
        }
        let peak = peakBytes
        lock.unlock()

        let stats = statistics()

        return [
            "rssBytes": Int(bytes),
            "peakBytes": Int(peak),
            "connections": stats.connections,
            "bufferedBytes": Int(stats.bufferedBytes),
            "maxBufferedBytes": Int(stats.maxBufferedBytes),
        ]
    }

    func snapshotJson() -> Data? {
        return try? JSONSerialization.data(withJSONObject: snapshot())
    }

    /// 当前进程常驻内存（字节）。
    /// 优先 phys_footprint——它比 resident_size 更接近系统 jetsam 判定时用的值。
    static func currentResidentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        if result == KERN_SUCCESS {
            return info.phys_footprint
        }

        // 退化路径：部分系统上 TASK_VM_INFO 可能不可用
        var basic = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let basicResult = withUnsafeMutablePointer(to: &basic) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &basicCount)
            }
        }
        return basicResult == KERN_SUCCESS ? basic.resident_size : 0
    }
}
