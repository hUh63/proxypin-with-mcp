package com.network.proxy.vpn.util

import android.util.Log
import com.network.proxy.vpn.formatTag
import com.network.proxy.vpn.transport.protocol.IP4Header
import com.network.proxy.vpn.transport.protocol.TCPHeader
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Helper class to perform various useful task
 */
object PacketUtil {
    @get:Synchronized
    private var packetId = 0
    fun getPacketId() = packetId++

    val currentTime: Int
        get() = (System.currentTimeMillis() / 1000).toInt()

    /**
     * convert int to byte array
     * [...](https://docs.oracle.com/javase/tutorial/java/nutsandbolts/datatypes.html)
     *
     * @param value  int value 32 bits
     * @param buffer array of byte to write to
     * @param offset position to write to
     */
    fun writeIntToBytes(value: Int, buffer: ByteArray, offset: Int) {
        if (buffer.size - offset < 4) {
            return
        }
        buffer[offset] = (value ushr 24 and 0x000000FF).toByte()
        buffer[offset + 1] = (value shr 16 and 0x000000FF).toByte()
        buffer[offset + 2] = (value shr 8 and 0x000000FF).toByte()
        buffer[offset + 3] = (value and 0x000000FF).toByte()
    }

    /**
     * convert array of max 4 bytes to int
     *
     * @param buffer byte array
     * @param start  Starting point to be read in byte array
     * @param length Length to be read
     * @return value of int
     */
    fun getNetworkInt(buffer: ByteArray, start: Int, length: Int): Int {
        var value = 0
        var end = start + Math.min(length, 4)
        if (end > buffer.size) end = buffer.size
        for (i in start until end) {
            value = value or (buffer[i].toInt() and 0xFF)
            if (i < end - 1) value = value shl 8
        }
        return value
    }

    /**
     * validate TCP header checksum
     *
     * @param source      Source Port
     * @param destination Destination Port
     * @param data        Payload
     * @param tcpLength   TCP Header length
     * @return boolean
     */
    fun isValidTCPChecksum(
        source: Int, destination: Int,
        data: ByteArray, tcpLength: Short, tcpOffset: Int
    ): Boolean {
        var buffersize = tcpLength + 12
        var isodd = false
        if (buffersize % 2 != 0) {
            buffersize++
            isodd = true
        }
        val buffer = ByteBuffer.allocate(buffersize)
        buffer.putInt(source)
        buffer.putInt(destination)
        buffer.put(0.toByte()) //reserved => 0
        buffer.put(6.toByte()) //TCP protocol => 6
        buffer.putShort(tcpLength)
        buffer.put(data, tcpOffset, tcpLength.toInt())
        if (isodd) {
            buffer.put(0.toByte())
        }
        return isValidIPChecksum(buffer.array(), buffersize)
    }

    /**
     * validate IP Header checksum
     *
     * @param data byte stream
     * @return boolean
     */
    private fun isValidIPChecksum(data: ByteArray, length: Int): Boolean {
        var start = 0
        var sum = 0
        while (start < length) {
            sum += getNetworkInt(data, start, 2)
            start = start + 2
        }

        //carry over one's complement
        while (sum shr 16 > 0) sum = (sum and 0xffff) + (sum shr 16)

        //flip the bit to get one' complement
        sum = sum.inv()
        val buffer = ByteBuffer.allocate(4)
        buffer.putInt(sum)
        return buffer.getShort(2).toInt() == 0
    }

    fun calculateChecksum(data: ByteArray, offset: Int, length: Int): ByteArray {
        var start = offset
        var sum = 0
        while (start < length) {
            sum += getNetworkInt(data, start, 2)
            start = start + 2
        }
        //carry over one's complement
        while (sum shr 16 > 0) {
            sum = (sum and 0xffff) + (sum shr 16)
        }
        //flip the bit to get one' complement
        sum = sum.inv()

        //extract the last two byte of int
        val checksum = ByteArray(2)
        checksum[0] = (sum shr 8).toByte()
        checksum[1] = sum.toByte()
        return checksum
    }

    fun calculateTCPHeaderChecksum(
        data: ByteArray,
        offset: Int,
        tcplength: Int,
        destip: Int,
        sourceip: Int
    ): ByteArray {
        var buffersize = tcplength + 12
        var odd = false
        if (buffersize % 2 != 0) {
            buffersize++
            odd = true
        }
        val buffer = ByteBuffer.allocate(buffersize)
        buffer.order(ByteOrder.BIG_ENDIAN)

        //create virtual header
        buffer.putInt(sourceip)
        buffer.putInt(destip)
        buffer.put(0.toByte()) //reserved => 0
        buffer.put(6.toByte()) //tcp protocol => 6
        buffer.putShort(tcplength.toShort())

        //add actual header + data
        buffer.put(data, offset, tcplength)

        //padding last byte to zero
        if (odd) {
            buffer.put(0.toByte())
        }
        val tcparray = buffer.array()
        return calculateChecksum(tcparray, 0, buffersize)
    }

    fun intToIPAddress(addressInt: Int): String {
        return (addressInt ushr 24 and 0x000000FF).toString() + "." +
                (addressInt ushr 16 and 0x000000FF) + "." +
                (addressInt ushr 8 and 0x000000FF) + "." +
                (addressInt and 0x000000FF)
    }

    fun getOutput(
        ipHeader: IP4Header, tcpheader: TCPHeader,
        packetData: ByteArray
    ): String {
        val tcpLength = (packetData.size -
                ipHeader.getIPHeaderLength()).toShort()
        val isValidChecksum = isValidTCPChecksum(
            ipHeader.sourceIP, ipHeader.destinationIP,
            packetData, tcpLength, ipHeader.getIPHeaderLength()
        )
        val isValidIPChecksum = isValidIPChecksum(
            packetData,
            ipHeader.getIPHeaderLength()
        )
        val packetBodyLength = (packetData.size - ipHeader.getIPHeaderLength()
                - tcpheader.getTCPHeaderLength())
        val str = StringBuilder("\r\nIP Version: ")
            .append(ipHeader.ipVersion.toInt())
            .append("\r\nProtocol: ").append(ipHeader.protocol.toInt())
            .append("\r\nID# ").append(ipHeader.identification)
            .append("\r\nTotal Length: ").append(ipHeader.totalLength)
            .append("\r\nData Length: ").append(packetBodyLength)
            .append("\r\nDest: ").append(intToIPAddress(ipHeader.destinationIP))
            .append(":").append(tcpheader.getDestinationPort())
            .append("\r\nSrc: ").append(intToIPAddress(ipHeader.sourceIP))
            .append(":").append(tcpheader.getSourcePort())
            .append("\r\nACK: ").append(tcpheader.ackNumber)
            .append("\r\nSeq: ").append(tcpheader.sequenceNumber)
            .append("\r\nIP Header length: ").append(ipHeader.getIPHeaderLength())
            .append("\r\nTCP Header length: ").append(tcpheader.getTCPHeaderLength())
            .append("\r\nACK: ").append(tcpheader.isACK())
            .append("\r\nSYN: ").append(tcpheader.isSYN())
            .append("\r\nCWR: ").append(tcpheader.isCWR())
            .append("\r\nECE: ").append(tcpheader.isECE())
            .append("\r\nFIN: ").append(tcpheader.isFIN())
            .append("\r\nNS: ").append(tcpheader.isNS)
            .append("\r\nPSH: ").append(tcpheader.isPSH())
            .append("\r\nRST: ").append(tcpheader.isRST())
            .append("\r\nURG: ").append(tcpheader.isURG())
            .append("\r\nIP checksum: ").append(ipHeader.headerChecksum)
            .append("\r\nIs Valid IP Checksum: ").append(isValidIPChecksum)
            .append("\r\nTCP Checksum: ").append(tcpheader.checksum)
            .append("\r\nIs Valid TCP checksum: ").append(isValidChecksum)
            .append("\r\nFragment Offset: ").append(ipHeader.fragmentOffset.toInt())
            .append("\r\nWindow: ").append(tcpheader.windowSize)
            .append("\r\nData Offset: ").append(tcpheader.dataOffset)
        return str.toString()
    }

    /**
     * detect packet corruption flag in tcp options sent from client ACK
     *
     * @param tcpHeader TCPHeader
     * @return boolean
     */
    fun isPacketCorrupted(tcpHeader: TCPHeader): Boolean {
        val options = tcpHeader.options ?: return false

        // 防御：options 直接来自客户端报文，可能被截断或伪造。
        // 原实现 `i = i + options[++i] - 2` 有两个问题：
        //   1. options[++i]：kind 5/15 恰好是最后一个字节时直接数组越界（抛异常，中断该包的 ACK 处理）；
        //   2. options[++i] 是有符号 Byte，取值 >127 会变成负数，使 i 回退（重复解析甚至死循环）。
        // 本函数本身就是"防御性校验"，不该由畸形选项把它自己搞崩（iOS 侧同名函数已同样修复）。
        var i = 0
        while (i < options.size) {
            val kind = options[i].toInt() and 0xFF
            when (kind) {
                0 -> return false // End of Option List
                1 -> i += 1 // No Operation
                2 -> i += 4 // Maximum Segment Size
                3, 14 -> i += 3 // Window Scale / Alternate Checksum Request
                4 -> i += 2 // SACK Permitted
                5, 15 -> { // SACK / Alternate Checksum Data
                    if (i + 1 >= options.size) {
                        Log.e(formatTag(PacketUtil::class.java.name), "truncated tcp option: $kind")
                        return true
                    }
                    val length = options[i + 1].toInt() and 0xFF
                    if (length < 2 || i + length > options.size) {
                        Log.e(formatTag(PacketUtil::class.java.name), "invalid tcp option length: $length, option: $kind")
                        return true
                    }
                    i += length
                }
                8 -> i += 10 // Timestamps
                23 -> return true
                else -> {
                    Log.e(
                        formatTag(PacketUtil::class.java.name),
                        "unknown option: $kind"
                    )
                    i += 1
                }
            }
        }
        return false
    }
}

