import CoreGraphics
import Foundation
import ImageIO

struct CropEditStore: Sendable {
    private let fileName = ".imgslicer-edits.json"

    func restoredTask(_ task: FolderTask) -> FolderTask {
        let edits = loadEdits(rootURL: task.rootURL)
        guard !edits.photos.isEmpty else { return task }

        var restored = task
        for photoIndex in restored.photos.indices {
            let photo = restored.photos[photoIndex]
            let relativePath = photo.relativePath
            guard let edit = edits.photos[relativePath], !edit.regions.isEmpty else { continue }
            guard let savedSignature = edit.imageSignature,
                  let currentSignature = ImageSignature(url: photo.url),
                  savedSignature.matches(currentSignature) else {
                continue
            }
            let isManual = edit.isManual ?? true
            restored.photos[photoIndex].cropRegions = edit.regions.enumerated().map { offset, rect in
                CropRegion(index: offset + 1, rect: rect.cgRect, angle: rect.angle ?? 0, isManual: isManual)
            }
            restored.photos[photoIndex].isManual = isManual
            restored.photos[photoIndex].status = isManual ? .manual : .located
        }
        return restored
    }

    func save(photo: PhotoItem, in task: FolderTask) {
        var edits = loadEdits(rootURL: task.rootURL)
        edits.photos[photo.relativePath] = SavedPhotoEdit(
            updatedAt: Date(),
            isManual: photo.isManual,
            imageSignature: ImageSignature(url: photo.url),
            regions: photo.cropRegions.map { SavedRect(rect: $0.rect, angle: $0.angle) }
        )
        write(edits: edits, rootURL: task.rootURL)
    }

    func save(photos: [PhotoItem], in task: FolderTask) {
        var edits = loadEdits(rootURL: task.rootURL)
        let now = Date()
        for photo in photos {
            edits.photos[photo.relativePath] = SavedPhotoEdit(
                updatedAt: now,
                isManual: photo.isManual,
                imageSignature: ImageSignature(url: photo.url),
                regions: photo.cropRegions.map { SavedRect(rect: $0.rect, angle: $0.angle) }
            )
        }
        write(edits: edits, rootURL: task.rootURL)
    }

    private func loadEdits(rootURL: URL) -> SavedCropEdits {
        let url = editsURL(rootURL: rootURL)
        guard let data = try? Data(contentsOf: url) else {
            return SavedCropEdits()
        }
        return (try? JSONDecoder().decode(SavedCropEdits.self, from: data)) ?? SavedCropEdits()
    }

    private func write(edits: SavedCropEdits, rootURL: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let url = editsURL(rootURL: rootURL)
            let data = try encoder.encode(edits)
            try data.write(to: url, options: .atomic)
        } catch {
            // Manual edits are still kept in memory; persistence is a convenience layer.
        }
    }

    private func editsURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(fileName, isDirectory: false)
    }
}

private struct SavedCropEdits: Codable {
    var version: Int = 1
    var photos: [String: SavedPhotoEdit] = [:]
}

private struct SavedPhotoEdit: Codable {
    var updatedAt: Date
    var isManual: Bool?
    var imageSignature: ImageSignature?
    var regions: [SavedRect]
}

private struct ImageSignature: Codable, Equatable {
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSize: Int64?
    var modificationTime: Date?

    init?(url: URL) {
        if let decoder = FFFParsingRuntime.decoder(for: url) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            pixelWidth = decoder.info.width
            pixelHeight = decoder.info.height
            fileSize = values?.fileSize.map(Int64.init)
            modificationTime = values?.contentModificationDate
            return
        }

        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ] as CFDictionary
        ),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        pixelWidth = width
        pixelHeight = height
        fileSize = values?.fileSize.map(Int64.init)
        modificationTime = values?.contentModificationDate
    }

    func matches(_ other: ImageSignature) -> Bool {
        guard pixelWidth == other.pixelWidth, pixelHeight == other.pixelHeight else { return false }
        if let fileSize, let otherFileSize = other.fileSize, fileSize != otherFileSize { return false }
        if let modificationTime, let otherModificationTime = other.modificationTime,
           abs(modificationTime.timeIntervalSince(otherModificationTime)) > 1 {
            return false
        }
        return true
    }
}

private struct SavedRect: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var angle: Double?

    init(rect: CGRect, angle: Double = 0) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
        self.angle = angle
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height).normalizedCropRect
    }
}

private extension CGRect {
    var normalizedCropRect: CGRect {
        let x = min(max(origin.x, 0), 0.95)
        let y = min(max(origin.y, 0), 0.95)
        let width = min(max(size.width, 0.05), 1 - x)
        let height = min(max(size.height, 0.05), 1 - y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
