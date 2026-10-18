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
        // 解压炸弹兜底：允许比声明的大小多出 1MB，超了直接判定损坏
        let capacity = max(expected, 0) + 1_048_576
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
        guard written > 0 else { throw Failure.corrupted }
        return Data(bytes: buffer, count: written)
    }
}
#endif
