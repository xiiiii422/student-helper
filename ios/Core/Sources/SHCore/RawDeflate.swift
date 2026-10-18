import Foundation

#if canImport(Compression)
import Compression

/// ZIP 里 deflate 条目的解压。
///
/// 只在 Apple 平台编译：Windows 侧只跑单测，测试数据一律用 store（不压缩），
/// 这样 Core 在两端都能编译，而 iOS 仍然读得懂用户在「文件」App 里重新压缩过的备份包。
enum RawDeflate {

    enum Failure: Swift.Error {
        case corrupted
    }

    /// raw deflate（无 zlib/gzip 头），正是 ZIP method=8 的格式。
    /// COMPRESSION_ZLIB 在 Apple 的 Compression 里就是裸 deflate 流。
    static func inflate(_ input: Data, expected: Int) throws -> Data {
        guard !input.isEmpty else { return Data() }
        // 声明大小来自不可信的 zip 头：直接拿去 allocate 可能一次要 4GB 直接崩。
        // 已知大小时按「声明 + 1MB 余量」分配，未知大小（data descriptor 写法）给 16MB。
        let declared = max(expected, 0)
        let capacity = declared > 0
            ? min(declared + 1_048_576, 64 * 1024 * 1024)
            : 16 * 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        let written: Int = input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                buffer, capacity,
                base, input.count,
                nil, COMPRESSION_ZLIB
            )
        }
        // 缓冲区被填满说明真实内容比声明的大，按损坏处理，避免把截断数据当成功
        guard written > 0, written < capacity else { throw Failure.corrupted }
        return Data(bytes: buffer, count: written)
    }
}
#endif
