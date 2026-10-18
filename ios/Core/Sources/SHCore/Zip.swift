import Foundation

/// 极简 ZIP 读写（无第三方依赖，纯 Foundation）。
///
/// 为什么自己写：备份必须跨端 —— 安卓导出的 zip 要能在 iOS 导入，反之亦然。
/// iOS 系统没有公开的 zip 打包 API，而我们的载荷已经是 JPEG/JSON，
/// 再压一遍收益接近 0，所以**写出用 store（不压缩）**；读取则同时支持
/// store 与 deflate（用户在「文件」里重新打包会变成 deflate）。
///
/// CRC32 是 ZIP 规范的强制项，写错一个位整包就废了，因此单独可测。
public enum Zip {

    public struct Entry: Equatable {
        public let name: String
        public let data: Data
        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    public enum ZipError: Error, Equatable {
        case badMagic
        case truncated
        case unsupportedMethod(UInt16)
    }

    // MARK: - 写

    public static func write(_ entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            var local = Data()
            local += le(0x04034b50)          // local file header 魔数
            local += le16(20)                // version needed
            local += le16(0)                 // flags
            local += le16(0)                 // method = store
            local += le16(0)                 // mod time
            local += le16(0x21)              // mod date（1980-01-01，够用即可，备份不靠它排序）
            local += le(crc)
            local += le(size)                // compressed size
            local += le(size)                // uncompressed size
            local += le16(UInt16(nameData.count))
            local += le16(0)                 // extra length
            local += nameData
            local += entry.data

            var record = Data()
            record += le(0x02014b50)         // central directory 魔数
            record += le16(20)               // version made by
            record += le16(20)               // version needed
            record += le16(0)
            record += le16(0)                // method = store
            record += le16(0)
            record += le16(0x21)
            record += le(crc)
            record += le(size)
            record += le(size)
            record += le16(UInt16(nameData.count))
            record += le16(0)                // extra
            record += le16(0)                // comment
            record += le16(0)                // disk number
            record += le16(0)                // internal attrs
            record += le(0)                  // external attrs
            record += le(offset)             // 本地头偏移
            record += nameData

            out += local
            central += record
            offset += UInt32(local.count)
        }

        let centralOffset = offset
        let centralSize = UInt32(central.count)
        var end = Data()
        end += le(0x06054b50)
        end += le16(0)
        end += le16(0)
        end += le16(UInt16(entries.count))
        end += le16(UInt16(entries.count))
        end += le(centralSize)
        end += le(centralOffset)
        end += le16(0)                       // comment length

        out += central
        out += end
        return out
    }

    // MARK: - 读

    /// 从 zip 里读出全部文件。容忍 store 与 deflate 两种方法。
    public static func read(_ data: Data) throws -> [Entry] {
        guard let endOffset = findEndOfCentral(in: data) else { throw ZipError.badMagic }
        let slice = data.subdata(in: endOffset..<data.count)
        guard slice.count >= 22 else { throw ZipError.truncated }
        let count = Int(read16(slice, 10))
        var centralOffset = UInt32(read32(slice, 16))
        var cursor = Int(centralOffset)

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            let header = data.subdata(in: cursor..<(cursor + 46))
            guard header.count == 46, read32(header, 0) == 0x02014b50 else { throw ZipError.truncated }
            let method = read16(header, 10)
            let compressedSize = Int(read32(header, 20))
            let nameLength = Int(read16(header, 28))
            let extraLength = Int(read16(header, 30))
            let commentLength = Int(read16(header, 32))
            let localHeaderOffset = Int(read32(header, 42))
            let nameRange = (cursor + 46)..<(cursor + 46 + nameLength)
            guard nameRange.upperBound <= data.count else { throw ZipError.truncated }
            let name = String(data: data.subdata(in: nameRange), encoding: .utf8) ?? ""

            // 真实数据在本地头之后，本地头长度要重新解析（extra 字段长度与中央目录里那份可能不同）
            let local = data.subdata(in: localHeaderOffset..<(localHeaderOffset + 30))
            guard local.count == 30, read32(local, 0) == 0x04034b50 else { throw ZipError.badMagic }
            let localNameLen = Int(read16(local, 26))
            let localExtraLen = Int(read16(local, 28))
            let payloadStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            guard payloadStart + compressedSize <= data.count else { throw ZipError.truncated }
            var payload = data.subdata(in: payloadStart..<(payloadStart + compressedSize))
            if method == 8 {
                // 本地头偏移 24 是 uncompressed size，拿它做输出缓冲的下界估计
                payload = try inflate(payload, expected: Int(read32(local, 24)))
            } else if method != 0 {
                throw ZipError.unsupportedMethod(method)
            }
            if !name.hasSuffix("/") {
                entries.append(Entry(name: name, data: payload))
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func findEndOfCentral(in data: Data) -> Int? {
        // EOCD 从尾部往前找，最多扫 64KB（zip 注释上限）
        let needle: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let lowerBound = max(0, data.count - 65_557)
        var i = data.count - 4
        while i >= lowerBound {
            if data[i] == needle[0], data[i + 1] == needle[1],
               data[i + 2] == needle[2], data[i + 3] == needle[3] {
                return i
            }
            i -= 1
        }
        return nil
    }

    /// raw deflate 解压：ZIP 存的是裸 deflate 流，Compression 的 ZLIB 算法正是裸流。
    static func inflate(_ input: Data, expected: Int) throws -> Data {
        #if canImport(Compression)
        return try RawDeflate.inflate(input, expected: expected)
        #else
        throw ZipError.unsupportedMethod(8)
        #endif
    }

    // MARK: - 小端读写

    static func le(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    static func le16(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }

    static func read32(_ data: Data, _ at: Int) -> UInt32 {
        guard at + 4 <= data.count else { return 0 }
        let b = [UInt8](data.subdata(in: at..<(at + 4)))
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    static func read16(_ data: Data, _ at: Int) -> UInt16 {
        guard at + 2 <= data.count else { return 0 }
        let b = [UInt8](data.subdata(in: at..<(at + 2)))
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }
}

/// ZIP 规范的 CRC-32（多项式 0xEDB88320）。安卓端 BackupManager 用的是 java.util.zip 的同一个表。
public enum Crc32 {

    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var c = UInt32(index)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Zip {
    /// 写侧统一走 Crc32，避免两处实现漂移。
    static func crc32(_ data: Data) -> UInt32 { Crc32.checksum(data) }
}
