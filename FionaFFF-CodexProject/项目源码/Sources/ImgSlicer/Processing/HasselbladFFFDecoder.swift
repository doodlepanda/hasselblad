import CoreGraphics
import Foundation

struct HasselbladFFFInfo: Sendable {
    var width: Int
    var height: Int
    var bitsPerSample: Int
    var samplesPerPixel: Int
}

enum FFFParsingRuntime {
    nonisolated(unsafe) static var isEnabled = true
    static let fileExtensions: Set<String> = ["fff", "3f"]

    static func isFFFLikeURL(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    static func decoder(for url: URL) -> HasselbladFFFDecoder? {
        guard isEnabled else { return nil }
        return HasselbladFFFDecoder(url: url)
    }
}

final class HasselbladFFFDecoder {
    private enum Endian {
        case little
        case big
    }

    private struct IFDEntry {
        var tag: UInt16
        var type: UInt16
        var count: UInt32
        var valueOffset: UInt32
        var inlineValue: Data
    }

    let url: URL
    let info: HasselbladFFFInfo
    private let endian: Endian
    private let stripOffsets: [UInt64]
    private let stripByteCounts: [UInt64]
    private let rowsPerStrip: Int

    init?(url: URL) {
        guard FFFParsingRuntime.fileExtensions.contains(url.pathExtension.lowercased()),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { handle.closeFile() }

        let header = handle.readData(ofLength: 8)
        guard header.count == 8 else { return nil }
        let bytes = [UInt8](header)
        if bytes[0] == 0x4D && bytes[1] == 0x4D {
            endian = .big
        } else if bytes[0] == 0x49 && bytes[1] == 0x49 {
            endian = .little
        } else {
            return nil
        }
        guard Self.uint16(bytes[2...3], endian: endian) == 42 else { return nil }

        var ifdOffset = UInt64(Self.uint32(bytes[4...7], endian: endian))
        var best: (info: HasselbladFFFInfo, offsets: [UInt64], counts: [UInt64], rowsPerStrip: Int)?

        while ifdOffset > 0 {
            guard let entries = Self.readIFD(handle: handle, offset: ifdOffset, endian: endian) else { break }
            let table = Dictionary(uniqueKeysWithValues: entries.map { ($0.tag, $0) })

            let width = Self.firstInt(tag: 256, table: table, handle: handle, endian: endian)
            let height = Self.firstInt(tag: 257, table: table, handle: handle, endian: endian)
            let bits = Self.intArray(tag: 258, table: table, handle: handle, endian: endian)
            let compression = Self.firstInt(tag: 259, table: table, handle: handle, endian: endian) ?? 1
            let photometric = Self.firstInt(tag: 262, table: table, handle: handle, endian: endian) ?? 2
            let offsets = Self.intArray(tag: 273, table: table, handle: handle, endian: endian).map(UInt64.init)
            let samples = Self.firstInt(tag: 277, table: table, handle: handle, endian: endian) ?? 3
            let rows = Self.firstInt(tag: 278, table: table, handle: handle, endian: endian) ?? 1
            let counts = Self.intArray(tag: 279, table: table, handle: handle, endian: endian).map(UInt64.init)
            let planar = Self.firstInt(tag: 284, table: table, handle: handle, endian: endian) ?? 1

            if let width, let height,
               compression == 1,
               photometric == 2,
               samples == 3,
               planar == 1,
               bits.allSatisfy({ $0 == 16 }),
               !offsets.isEmpty,
               offsets.count == counts.count {
                let candidate = (
                    info: HasselbladFFFInfo(width: width, height: height, bitsPerSample: 16, samplesPerPixel: samples),
                    offsets: offsets,
                    counts: counts,
                    rowsPerStrip: rows
                )
                if best == nil || width * height > best!.info.width * best!.info.height {
                    best = candidate
                }
            }

            guard let next = Self.nextIFDOffset(handle: handle, offset: ifdOffset, endian: endian) else { break }
            ifdOffset = next
        }

        guard let best else { return nil }
        self.url = url
        self.info = best.info
        self.stripOffsets = best.offsets
        self.stripByteCounts = best.counts
        self.rowsPerStrip = best.rowsPerStrip
    }

    func makePreviewCGImage(maxPixelSize: Int) -> CGImage? {
        let scale = max(1, Int(ceil(Double(max(info.width, info.height)) / Double(max(maxPixelSize, 1)))))
        let outputWidth = max(1, info.width / scale)
        let outputHeight = max(1, info.height / scale)
        var rgba = Data(count: outputWidth * outputHeight * 4)

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        let sourceStride = info.width * 6
        rgba.withUnsafeMutableBytes { outRaw in
            guard let out = outRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<outputHeight {
                let sourceY = min(info.height - 1, y * scale)
                guard let row = readRow(sourceY, handle: handle, expectedBytes: sourceStride) else { continue }
                row.withUnsafeBytes { rowRaw in
                    guard let src = rowRaw.bindMemory(to: UInt8.self).baseAddress else { return }
                    for x in 0..<outputWidth {
                        let sourceX = min(info.width - 1, x * scale)
                        let si = sourceX * 6
                        let di = (y * outputWidth + x) * 4
                        out[di] = src[si]
                        out[di + 1] = src[si + 2]
                        out[di + 2] = src[si + 4]
                        out[di + 3] = 255
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: rgba as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: outputWidth * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    func makeCropCGImage(rect: CGRect) -> CGImage? {
        let crop = rect.normalizedFFFRect
        let x = min(max(Int(floor(crop.minX * Double(info.width))), 0), info.width - 1)
        let y = min(max(Int(floor(crop.minY * Double(info.height))), 0), info.height - 1)
        let maxX = min(max(Int(ceil(crop.maxX * Double(info.width))), x + 1), info.width)
        let maxY = min(max(Int(ceil(crop.maxY * Double(info.height))), y + 1), info.height)
        let width = maxX - x
        let height = maxY - y
        let bytesPerRow = width * 6
        var data = Data(count: bytesPerRow * height)

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        let sourceStride = info.width * 6
        data.withUnsafeMutableBytes { outRaw in
            guard let out = outRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            for rowIndex in 0..<height {
                guard let row = readRow(y + rowIndex, handle: handle, expectedBytes: sourceStride) else { continue }
                row.withUnsafeBytes { rowRaw in
                    guard let src = rowRaw.bindMemory(to: UInt8.self).baseAddress else { return }
                    out.advanced(by: rowIndex * bytesPerRow).update(from: src.advanced(by: x * 6), count: bytesPerRow)
                }
            }
        }

        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 48,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder16Big.rawValue | CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func readRow(_ row: Int, handle: FileHandle, expectedBytes: Int) -> Data? {
        let strip = row / max(rowsPerStrip, 1)
        guard stripOffsets.indices.contains(strip), stripByteCounts.indices.contains(strip) else { return nil }
        let rowInStrip = row % max(rowsPerStrip, 1)
        let rowOffset = stripOffsets[strip] + UInt64(rowInStrip * expectedBytes)
        let remainingInStrip = Int(stripByteCounts[strip]) - rowInStrip * expectedBytes
        guard remainingInStrip >= expectedBytes else { return nil }
        handle.seek(toFileOffset: rowOffset)
        let data = handle.readData(ofLength: expectedBytes)
        return data.count == expectedBytes ? data : nil
    }

    private static func readIFD(handle: FileHandle, offset: UInt64, endian: Endian) -> [IFDEntry]? {
        handle.seek(toFileOffset: offset)
        let countData = handle.readData(ofLength: 2)
        guard countData.count == 2 else { return nil }
        let count = Int(uint16(countData, endian: endian))
        let entryData = handle.readData(ofLength: count * 12)
        guard entryData.count == count * 12 else { return nil }
        var entries: [IFDEntry] = []
        let bytes = [UInt8](entryData)
        for index in 0..<count {
            let start = index * 12
            let tag = uint16(bytes[start..<(start + 2)], endian: endian)
            let type = uint16(bytes[(start + 2)..<(start + 4)], endian: endian)
            let valueCount = uint32(bytes[(start + 4)..<(start + 8)], endian: endian)
            let valueOffset = uint32(bytes[(start + 8)..<(start + 12)], endian: endian)
            let inlineValue = Data(bytes[(start + 8)..<(start + 12)])
            entries.append(IFDEntry(tag: tag, type: type, count: valueCount, valueOffset: valueOffset, inlineValue: inlineValue))
        }
        return entries
    }

    private static func nextIFDOffset(handle: FileHandle, offset: UInt64, endian: Endian) -> UInt64? {
        handle.seek(toFileOffset: offset)
        let countData = handle.readData(ofLength: 2)
        guard countData.count == 2 else { return nil }
        let count = UInt64(uint16(countData, endian: endian))
        handle.seek(toFileOffset: offset + 2 + count * 12)
        let nextData = handle.readData(ofLength: 4)
        guard nextData.count == 4 else { return nil }
        return UInt64(uint32(nextData, endian: endian))
    }

    private static func firstInt(tag: UInt16, table: [UInt16: IFDEntry], handle: FileHandle, endian: Endian) -> Int? {
        intArray(tag: tag, table: table, handle: handle, endian: endian).first
    }

    private static func intArray(tag: UInt16, table: [UInt16: IFDEntry], handle: FileHandle, endian: Endian) -> [Int] {
        guard let entry = table[tag],
              let data = valueData(entry: entry, handle: handle) else { return [] }
        let bytes = [UInt8](data)
        let count = Int(entry.count)
        switch entry.type {
        case 3:
            return (0..<min(count, bytes.count / 2)).map { index in
                Int(uint16(bytes[(index * 2)..<(index * 2 + 2)], endian: endian))
            }
        case 4:
            return (0..<min(count, bytes.count / 4)).map { index in
                Int(uint32(bytes[(index * 4)..<(index * 4 + 4)], endian: endian))
            }
        default:
            return []
        }
    }

    private static func valueData(entry: IFDEntry, handle: FileHandle) -> Data? {
        let byteCount = Int(entry.count) * typeSize(entry.type)
        guard byteCount > 0 else { return nil }
        if byteCount <= 4 {
            return entry.inlineValue.prefix(byteCount)
        }
        handle.seek(toFileOffset: UInt64(entry.valueOffset))
        let data = handle.readData(ofLength: byteCount)
        return data.count == byteCount ? data : nil
    }

    private static func typeSize(_ type: UInt16) -> Int {
        switch type {
        case 1, 2, 6, 7: 1
        case 3, 8: 2
        case 4, 9, 11: 4
        case 5, 10, 12: 8
        default: 0
        }
    }

    private static func uint16<C: Collection>(_ bytes: C, endian: Endian) -> UInt16 where C.Element == UInt8 {
        let b = Array(bytes)
        guard b.count >= 2 else { return 0 }
        switch endian {
        case .big:
            return UInt16(b[0]) << 8 | UInt16(b[1])
        case .little:
            return UInt16(b[1]) << 8 | UInt16(b[0])
        }
    }

    private static func uint32<C: Collection>(_ bytes: C, endian: Endian) -> UInt32 where C.Element == UInt8 {
        let b = Array(bytes)
        guard b.count >= 4 else { return 0 }
        switch endian {
        case .big:
            return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        case .little:
            return UInt32(b[3]) << 24 | UInt32(b[2]) << 16 | UInt32(b[1]) << 8 | UInt32(b[0])
        }
    }
}

private extension CGRect {
    var normalizedFFFRect: CGRect {
        let x = min(max(origin.x, 0), 0.95)
        let y = min(max(origin.y, 0), 0.95)
        let width = min(max(size.width, 0.001), 1 - x)
        let height = min(max(size.height, 0.001), 1 - y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
