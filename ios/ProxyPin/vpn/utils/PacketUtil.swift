//
//  PacketUtil.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/17.
//

import Foundation
import os.log

class PacketUtil {
    private static var packetId: Int = 0

    static func getPacketId() -> Int {
        defer { packetId += 1 }
        return packetId
    }
    
    static var currentTime: Int {
        return Int(Date().timeIntervalSince1970)
    }
    
   static func writeIntToBytes(value: UInt32, buffer: inout Data, offset: Int) {
        guard buffer.count >= offset + 4 else { return }
        var intValue = value.bigEndian
        let intData = Data(bytes: &intValue, count: 4)
        buffer.replaceSubrange(offset..<offset+4, with: intData)
    }
    
    static func intToIPAddress(_ ip: UInt32) -> String {
        return String(format: "%d.%d.%d.%d", (ip >> 24) & 0xFF, (ip >> 16) & 0xFF, (ip >> 8) & 0xFF, ip & 0xFF)
    }
    
    static func calculateTCPHeaderChecksum(data: Data, offset: Int, tcpLength: Int, sourceIP: UInt32, destinationIP: UInt32) -> Data {
        var bufferSize = tcpLength + 12
        var isOdd = false
        if bufferSize % 2 != 0 {
            bufferSize += 1
            isOdd = true
        }

        var buffer = Data()

        // Add source IP
        buffer.append(contentsOf: sourceIP.bytes)
        // Add destination IP
        buffer.append(contentsOf: destinationIP.bytes)

        // Add reserved byte and protocol (6 for TCP)
        buffer.append(0)
        buffer.append(6)

        // Add TCP length
        buffer.append(contentsOf: UInt16(tcpLength).bytes)

        // Add TCP header and data
        buffer.append(contentsOf: data[offset..<offset + tcpLength])

        // Pad with zero if odd length
        if isOdd {
            buffer.append(0)
        }

        // Calculate checksum
        return calculateChecksum(data: buffer, offset: 0, length: bufferSize)
    }

    static func calculateChecksum(data: Data, offset: Int, length: Int) -> Data {
        var start = offset
        var sum = 0

        while start < length {
            sum += getNetworkInt(buffer: data, start: start, length: 2)
            start += 2
        }

        // Carry over one's complement
        while (sum >> 16) > 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }

        // Flip the bits to get one's complement
        sum = ~sum

        // Extract the last two bytes of the int
        let checksum = Data([UInt8(truncatingIfNeeded: (sum >> 8) & 0xFF), UInt8(truncatingIfNeeded: sum & 0xFF)])
        return checksum
    }
    
    static func getNetworkInt(buffer: Data, start: Int, length: Int) -> Int {
        var value = 0
        var end = start + min(length, 4)
        if end > buffer.count { end = buffer.count }
        for i in start..<end {
            value = value | (Int(buffer[i]) & 0xFF)
            if i < end - 1 { value = value << 8 }
        }
        return value
    }
    
    static func isPacketCorrupted(tcpHeader: TCPHeader) -> Bool {
        guard let options = tcpHeader.options else {
            return false
        }

        // options 直接来自客户端报文，可能是截断或伪造的：每一步都必须先校验边界。
        // 原实现有两个危险点：
        //   1. `options[i + 1]`：当 kind 5/15 恰好是最后一个字节时直接下标越界崩溃；
        //   2. `i += Int(options[i + 1]) - 2`：长度字节小于 2 时 i 会回退成负数（同样崩溃），
        //      或原地打转形成死循环，而本函数本身是"防御性校验"，不该由畸形选项把扩展搞崩。
        var i = 0
        while i < options.count {
            let kind = Int(options[i])
            switch kind {
            case 0: // End of Option List
                return false
            case 1: // No Operation
                i += 1
            case 2: // Maximum Segment Size
                i += 4
            case 3, 14: // Window Scale / Alternate Checksum Request
                i += 3
            case 4: // SACK Permitted
                i += 2
            case 5, 15: // SACK / Alternate Checksum Data
                guard i + 1 < options.count else {
                    os_log("Truncated TCP option: %d", log: OSLog.default, type: .error, kind)
                    return true
                }
                let length = Int(options[i + 1])
                guard length >= 2, i + length <= options.count else {
                    os_log("Invalid TCP option length: %d, option: %d", log: OSLog.default, type: .error, length, kind)
                    return true
                }
                i += length
            case 8: // Timestamps
                i += 10
            case 23:
                return true
            default:
                os_log("Unknown TCP option: %d", log: OSLog.default, type: .debug, kind)
                i += 1
            }
        }
        return false
    }
}


extension FixedWidthInteger {
    var bytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian) { Array($0) }
    }
}
