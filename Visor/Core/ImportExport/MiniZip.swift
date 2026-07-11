import Foundation

/// 极简 ZIP 编解码器（STORE 方法，无压缩）
///
/// 产出标准 ZIP 文件，可用任何解压工具（macOS 访达 / iOS 文件 / unzip）打开。
/// 选择 STORE 而非 DEFLATE 的理由：
/// 1. Apple 的 Compression 框架只提供带 zlib 包装（RFC1950）的接口，
///    而 ZIP 标准要求原始 DEFLATE（RFC1951），直接复用会导致格式不兼容。
/// 2. STORE 同样是 ZIP 标准方法（method 0），产出文件完全合法。
/// 3. 会话产物多为 HTML/CSS/JS 文本，单会话总体积可控，无压缩也可接受。
/// 4. 零第三方依赖，符合项目硬约束。
///
/// 编码：`(name, data)` 列表 → ZIP Data
/// 解码：ZIP Data → `(name, data)` 列表（仅支持 STORE；遇 DEFLATE 抛错）
nonisolated enum MiniZip {

    // MARK: - 常量

    private static let sigLocalHeader: UInt32     = 0x04034b50   // PK\x03\x04
    private static let sigCentralDir: UInt32      = 0x02014b50   // PK\x01\x02
    private static let sigEndOfCentralDir: UInt32 = 0x06054b50   // PK\x05\x06

    private static let methodStored: UInt16 = 0
    private static let methodDeflate: UInt16 = 8

    enum ZipError: Error, LocalizedError {
        case truncated(String)
        case unsupportedMethod(UInt16)
        case badSignature(UInt32)
        case eocdNotFound
        case crcMismatch(expected: UInt32, actual: UInt32)

        var errorDescription: String? {
            switch self {
            case .truncated(let what):       return "ZIP 数据截断：\(what)"
            case .unsupportedMethod(let m):  return "不支持的压缩方法：\(m)（仅支持 STORE）"
            case .badSignature(let s):       return "ZIP 签名异常：0x\(String(s, radix: 16))"
            case .eocdNotFound:              return "未找到 ZIP End of Central Directory"
            case .crcMismatch(let e, let a): return "CRC 校验失败：期望 0x\(String(e, radix: 16))，实际 0x\(String(a, radix: 16))"
            }
        }
    }

    // MARK: - Encode

    /// 将条目列表打包为 ZIP Data
    static func encode(_ entries: [(name: String, data: Data)]) throws -> Data {
        var output = Data()
        var centralDirectory = Data()
        var records: [(name: String, offset: UInt32, crc: UInt32, size: UInt32)] = []
        records.reserveCapacity(entries.count)

        let now = Date()
        let (dosDate, dosTime) = dosDateTime(now)

        for entry in entries {
            // ZIP 规范要求路径使用正斜杠
            let name = entry.name.replacingOccurrences(of: "\\", with: "/")
            let nameBytes = Array(name.utf8)
            guard nameBytes.count <= UInt16.max else {
                throw ZipError.truncated("文件名过长")
            }
            let data = entry.data
            let crc = crc32(data)
            let offset = UInt32(output.count)
            let size = UInt32(data.count)

            // Local file header
            var lfh = Data()
            lfh.appendLE(sigLocalHeader)
            lfh.appendLE(UInt16(20))              // version needed: 2.0
            lfh.appendLE(UInt16(0))               // general purpose bit flag
            lfh.appendLE(methodStored)            // compression method: STORE
            lfh.appendLE(dosTime)
            lfh.appendLE(dosDate)
            lfh.appendLE(crc)                     // CRC-32
            lfh.appendLE(size)                    // compressed size (== uncompressed for STORE)
            lfh.appendLE(size)                    // uncompressed size
            lfh.appendLE(UInt16(nameBytes.count)) // file name length
            lfh.appendLE(UInt16(0))               // extra field length
            lfh.append(contentsOf: nameBytes)
            output.append(lfh)
            output.append(data)

            records.append((name: name, offset: offset, crc: crc, size: size))
        }

        // Central directory
        let cdOffset = UInt32(output.count)
        for rec in records {
            let nameBytes = Array(rec.name.utf8)
            var cd = Data()
            cd.appendLE(sigCentralDir)
            cd.appendLE(UInt16(20))               // version made by
            cd.appendLE(UInt16(20))               // version needed
            cd.appendLE(UInt16(0))                // general purpose bit flag
            cd.appendLE(methodStored)             // compression method
            cd.appendLE(dosTime)
            cd.appendLE(dosDate)
            cd.appendLE(rec.crc)                  // CRC-32
            cd.appendLE(rec.size)                 // compressed size
            cd.appendLE(rec.size)                 // uncompressed size
            cd.appendLE(UInt16(nameBytes.count))  // file name length
            cd.appendLE(UInt16(0))                // extra field length
            cd.appendLE(UInt16(0))                // file comment length
            cd.appendLE(UInt16(0))                // disk number start
            cd.appendLE(UInt16(0))                // internal file attributes
            cd.appendLE(UInt32(0))                // external file attributes
            cd.appendLE(rec.offset)               // relative offset of local header
            cd.append(contentsOf: nameBytes)
            centralDirectory.append(cd)
        }
        let cdSize = UInt32(centralDirectory.count)

        output.append(centralDirectory)

        // End of central directory record
        var eocd = Data()
        eocd.appendLE(sigEndOfCentralDir)
        eocd.appendLE(UInt16(0))                  // number of this disk
        eocd.appendLE(UInt16(0))                  // disk where central directory starts
        eocd.appendLE(UInt16(records.count))      // entries on this disk
        eocd.appendLE(UInt16(records.count))      // total entries
        eocd.appendLE(cdSize)                     // size of central directory
        eocd.appendLE(cdOffset)                   // offset of start of central directory
        eocd.appendLE(UInt16(0))                  // comment length
        output.append(eocd)

        return output
    }

    // MARK: - Decode

    /// 解析 ZIP Data 为条目列表
    static func decode(_ zip: Data) throws -> [(name: String, data: Data)] {
        guard zip.count >= 22 else { throw ZipError.eocdNotFound }

        // 1. 定位 EOCD（从尾部向前搜索签名）
        let eocdOffset = try findEOCD(in: zip)

        // 2. 读取中央目录信息
        let cdCount = zip.readLE16(at: eocdOffset + 10)
        let cdSize  = zip.readLE32(at: eocdOffset + 12)
        let cdStart = zip.readLE32(at: eocdOffset + 16)
        guard Int(cdStart) + Int(cdSize) <= zip.count else {
            throw ZipError.truncated("中央目录")
        }

        // 3. 遍历中央目录条目
        var entries: [(name: String, data: Data)] = []
        entries.reserveCapacity(Int(cdCount))

        var cursor = Int(cdStart)
        for _ in 0..<Int(cdCount) {
            guard cursor + 46 <= zip.count else { throw ZipError.truncated("中央目录条目") }
            let sig = zip.readLE32(at: cursor)
            guard sig == sigCentralDir else { throw ZipError.badSignature(sig) }

            let method       = zip.readLE16(at: cursor + 10)
            let crc          = zip.readLE32(at: cursor + 16)
            let compSize     = zip.readLE32(at: cursor + 20)
            let uncompSize   = zip.readLE32(at: cursor + 24)
            let nameLen      = Int(zip.readLE16(at: cursor + 28))
            let extraLen     = Int(zip.readLE16(at: cursor + 30))
            let commentLen   = Int(zip.readLE16(at: cursor + 32))
            let localOffset  = Int(zip.readLE32(at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLen <= zip.count else { throw ZipError.truncated("文件名") }
            let name = String(data: zip.subdata(in: nameStart..<(nameStart + nameLen)), encoding: .utf8) ?? ""

            // 移动到下一个中央目录条目
            cursor = nameStart + nameLen + extraLen + commentLen

            // 4. 读取本地文件头并提取数据
            let payload = try readLocalEntry(
                zip: zip, at: localOffset,
                method: method, crc: crc,
                compSize: compSize, uncompSize: uncompSize
            )
            entries.append((name: name, data: payload))
        }

        return entries
    }

    /// 从本地文件头读取文件数据
    private static func readLocalEntry(
        zip: Data, at offset: Int,
        method: UInt16, crc: UInt32,
        compSize: UInt32, uncompSize: UInt32
    ) throws -> Data {
        guard offset + 30 <= zip.count else { throw ZipError.truncated("本地文件头") }
        let sig = zip.readLE32(at: offset)
        guard sig == sigLocalHeader else { throw ZipError.badSignature(sig) }

        let nameLen  = Int(zip.readLE16(at: offset + 26))
        let extraLen = Int(zip.readLE16(at: offset + 28))
        let dataStart = offset + 30 + nameLen + extraLen

        switch method {
        case methodStored:
            // STORE：压缩大小 == 原始大小
            let len = Int(compSize)
            guard dataStart + len <= zip.count else { throw ZipError.truncated("文件数据") }
            let payload = zip.subdata(in: dataStart..<(dataStart + len))
            // 校验 CRC
            let actual = crc32(payload)
            guard actual == crc else { throw ZipError.crcMismatch(expected: crc, actual: actual) }
            return payload

        case methodDeflate:
            // 本编解码器仅支持 STORE，遇 DEFLATE 抛错
            throw ZipError.unsupportedMethod(method)

        default:
            throw ZipError.unsupportedMethod(method)
        }
    }

    /// 从尾部向前搜索 EOCD 签名
    private static func findEOCD(in zip: Data) throws -> Int {
        // EOCD 最小 22 字节，最大含 65535 字节注释
        let maxComment = 65535
        let lowerBound = max(0, zip.count - maxComment - 22)
        var pos = zip.count - 22
        while pos >= lowerBound {
            if zip.readLE32(at: pos) == sigEndOfCentralDir {
                return pos
            }
            pos -= 1
        }
        throw ZipError.eocdNotFound
    }

    // MARK: - CRC-32（IEEE 802.3 / ZIP 标准，多项式 0xEDB88320）

    /// 预计算 CRC32 表（懒加载，线程安全）
    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        return table
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[idx]
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - DOS 日期时间

    /// 将 Date 转换为 ZIP 使用的 DOS 日期/时间（2 字节各）
    private static func dosDateTime(_ date: Date) -> (date: UInt16, time: UInt16) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year  = max((comps.year ?? 1980), 1980)
        let month = (comps.month ?? 1) & 0x0F
        let day   = (comps.day ?? 1) & 0x1F
        let hour  = (comps.hour ?? 0) & 0x1F
        let min   = (comps.minute ?? 0) & 0x3F
        let sec   = ((comps.second ?? 0) / 2) & 0x1F

        let dosDate = UInt16(((year - 1980) << 9) | (Int(month) << 5) | day)
        let dosTime = UInt16((Int(hour) << 11) | (Int(min) << 5) | sec)
        return (dosDate, dosTime)
    }
}

// MARK: - Data 读写辅助（小端序）

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    func readLE16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func readLE32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
