import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct AppShell: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            HStack(spacing: 16) {
                QueuePanel()
                    .frame(width: 292)
                PreviewWorkspace()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ParameterPanel()
                    .frame(width: 336)
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            Filmstrip()
                .frame(height: 132)
        }
        .background(AppTheme.background)
        .overlay(DropZoneOverlay())
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left:
                store.selectPreviousPhoto()
            case .right:
                store.selectNextPhoto()
            default:
                break
            }
        }
        .onDeleteCommand {
            store.deleteSelectedCropRegion()
        }
        .onKeyPress("a") {
            store.addCropRegionToSelectedPhoto()
            return .handled
        }
        .onDrop(of: [.fileURL], isTargeted: $store.isDropTargeted) { providers in
            loadDroppedURLs(providers)
        }
    }

    private func loadDroppedURLs(_ providers: [NSItemProvider]) -> Bool {
        let collector = URLCollector()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let foundURL: URL?
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    foundURL = url
                } else if let url = item as? URL {
                    foundURL = url
                } else {
                    foundURL = nil
                }
                if let foundURL {
                    collector.append(foundURL)
                }
            }
        }
        group.notify(queue: .main) {
            store.importItems(collector.values)
        }
        return true
    }
}

final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

final class ImagePreviewCache: @unchecked Sendable {
    static let shared = ImagePreviewCache()

    private let cache = NSCache<NSString, NSImage>()
    private let loadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "local.fiona.fff.preview-loader"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    func key(for url: URL, maxPixelSize: Int) -> String {
        "\(url.path)#\(maxPixelSize)"
    }

    func cachedImage(for url: URL, maxPixelSize: Int) -> NSImage? {
        cache.object(forKey: key(for: url, maxPixelSize: maxPixelSize) as NSString)
    }

    func image(for url: URL, maxPixelSize: Int) -> NSImage? {
        let key = key(for: url, maxPixelSize: maxPixelSize) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let decoder = HasselbladFFFDecoder(url: url),
           let cgImage = decoder.makePreviewCGImage(maxPixelSize: maxPixelSize) {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            cache.setObject(image, forKey: key)
            return image
        }

        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ] as CFDictionary
        ) else {
            return NSImage(contentsOf: url)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }

    func loadImage(for url: URL, maxPixelSize: Int, completion: @escaping (NSImage?) -> Void) {
        loadQueue.addOperation { [weak self] in
            guard let self else { return }
            let loaded = self.image(for: url, maxPixelSize: maxPixelSize)
            OperationQueue.main.addOperation {
                completion(loaded)
            }
        }
    }
}

struct AsyncCachedImage<Content: View, Placeholder: View>: View {
    let url: URL
    let maxPixelSize: Int
    let content: (NSImage) -> Content
    let placeholder: () -> Placeholder
    @State private var image: NSImage?
    @State private var loadKey = ""

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder()
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: url) { _, _ in resetAndLoad() }
        .onChange(of: maxPixelSize) { _, _ in resetAndLoad() }
    }

    private func resetAndLoad() {
        image = nil
        loadIfNeeded()
    }

    private func loadIfNeeded() {
        let key = ImagePreviewCache.shared.key(for: url, maxPixelSize: maxPixelSize)
        guard image == nil || loadKey != key else { return }
        loadKey = key
        if let cached = ImagePreviewCache.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            image = cached
            return
        }
        let targetKey = key
        let targetURL = url
        let targetSize = maxPixelSize
        ImagePreviewCache.shared.loadImage(for: targetURL, maxPixelSize: targetSize) { loaded in
            guard loadKey == targetKey else { return }
            image = loaded
        }
    }
}

struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> ScrollWheelMonitorView {
        let view = ScrollWheelMonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelMonitorView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: ScrollWheelMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class ScrollWheelMonitorView: NSView {
    var onScroll: ((Double) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isPointerInside(event) else { return event }
            self.onScroll?(event.scrollingDeltaY)
            return nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func isPointerInside(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }
}

struct TopBar: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack {
            BrandLockup()
            Spacer()
            HStack(spacing: 10) {
                Button("导入文件") { store.pickFiles() }
                    .buttonStyle(TopBarButtonStyle())
                    .help("导入图片文件或包含图片的文件夹")
                Button { store.startProcessing() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .bold))
                        Text("导出")
                    }
                }
                    .buttonStyle(StartProcessButtonStyle())
                    .help("按当前裁切框导出")
            }
        }
        .padding(.leading, 84)
        .padding(.trailing, 18)
        .padding(.top, 17)
        .frame(height: 72, alignment: .topLeading)
        .background(Color(red: 0.095, green: 0.105, blue: 0.125).opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.line).frame(height: 1)
        }
    }
}

struct BrandLockup: View {
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            LogoMark()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("FionaFFF")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                Text("film frame spotting and export")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            .padding(.top, 1)
        }
        .frame(width: 252, height: 38, alignment: .leading)
    }
}

struct QueuePanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("任务列表")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    store.clearFinishedAndIdle()
                } label: {
                    Image(systemName: "eraser")
                }
                .buttonStyle(IconButtonStyle())
                .help("清理已完成与未开始任务")
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.tasks.isEmpty {
                        EmptyQueueView()
                    } else {
                        ForEach(store.tasks) { task in
                            FolderTaskRow(task: task, active: task.id == store.selectedTask?.id)
                                .onTapGesture { store.selectTask(task.id) }
                        }
                    }
                }
                .padding(12)
            }
        }
        .panelStyle()
    }
}

struct FolderTaskRow: View {
    @EnvironmentObject private var store: AppStore

    let task: FolderTask
    let active: Bool

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(task.status == .done ? AppTheme.green.opacity(0.18) : Color(red: 0.09, green: 0.1, blue: 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14)))
                    if task.status == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.green)
                    }
                }
                .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(task.imageCount) 张图片 · \(task.detail)\n已处理 \(task.processedCount) / \(task.imageCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    StatusLabel(status: task.status)
                    Button {
                        store.openFolder(for: task.id)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("打开当前图片所在文件夹")
                }
            }

            ProgressView(value: task.progress)
                .tint(AppTheme.blue)
                .controlSize(.small)
        }
        .padding(12)
        .background(active ? Color(red: 0.125, green: 0.145, blue: 0.176) : Color(red: 0.115, green: 0.13, blue: 0.155))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(active ? AppTheme.blue.opacity(0.32) : Color.white.opacity(0.05))
        }
    }
}

struct StatusLabel: View {
    let status: TaskStatus

    var color: Color {
        switch status {
        case .waiting: Color(red: 0.82, green: 0.68, blue: 0.47)
        case .running: Color(red: 0.72, green: 0.79, blue: 0.86)
        case .needsReview: Color(red: 0.86, green: 0.68, blue: 0.43)
        case .done: AppTheme.green
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(status.rawValue)
                .font(.system(size: 11))
        }
        .foregroundStyle(color)
        .fixedSize()
    }
}

struct PreviewWorkspace: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GridBackground()
                if let photo = store.selectedPhoto {
                    AsyncCachedImage(url: photo.url, maxPixelSize: 2400) { image in
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            PhotoCanvas(
                                image: image,
                                rotationDegrees: store.previewRotationDegrees,
                                regions: photo.cropRegions,
                                selectedRegionID: store.selectedCropRegionID,
                                onDelete: { regionID in
                                    store.deleteSelectedCrop(regionID: regionID)
                                },
                                onSelect: { regionID in
                                    store.selectCropRegion(regionID)
                                }
                            ) { regionID, rect, angle in
                                store.updateSelectedCrop(regionID: regionID, rect: rect, angle: angle)
                            }
                            .id(photo.id)
                            .frame(width: max(proxy.size.width - 136, 1) * store.previewZoom, height: max(proxy.size.height - 164, 1) * store.previewZoom)
                            .padding(.horizontal, 68)
                            .padding(.vertical, 82)
                        }
                        .overlay(ScrollWheelCatcher { delta in
                            store.adjustPreviewZoom(delta: delta)
                        })
                    } placeholder: {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在加载预览")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 42))
                            .foregroundStyle(AppTheme.muted)
                        Text("拖入文件夹或点击导入开始")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.text)
                    }
                }

                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前图片：\(store.selectedPhoto?.name ?? "未选择")")
                                .font(.system(size: 14, weight: .bold))
                            if let folder = store.selectedTask?.displayName {
                                Text("当前文件夹：\(folder)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        Spacer()
                        Text(store.selectedPhoto?.status.rawValue ?? "等待导入")
                            .font(.system(size: 11))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button { store.rotatePreviewImageLeft() } label: {
                            Image(systemName: "rotate.left")
                        }
                        .buttonStyle(IconButtonStyle())
                        .help("左旋预览图 90 度")

                        Button { store.resetPreviewZoom() } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(IconButtonStyle())
                        .help("重置预览缩放")

                        Button { store.rotatePreviewImageRight() } label: {
                            Image(systemName: "rotate.right")
                        }
                        .buttonStyle(IconButtonStyle())
                        .help("右旋预览图 90 度")
                    }
                    ViewerLog()
                }
                .padding(18)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(AppTheme.viewer)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.05)))
    }
}

struct PhotoCanvas: View {
    let image: NSImage
    let rotationDegrees: Double
    let regions: [CropRegion]
    let selectedRegionID: CropRegion.ID?
    let onDelete: (CropRegion.ID) -> Void
    let onSelect: (CropRegion.ID) -> Void
    let onCropChange: (CropRegion.ID, CGRect, Double) -> Void
    @State private var panOffset: CGSize = .zero
    @State private var panStartOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let rotated = isQuarterTurn(rotationDegrees)
            let displaySize = rotated ? CGSize(width: image.size.height, height: image.size.width) : image.size
            let imageRect = aspectFitRect(imageSize: displaySize, bounds: proxy.size)
            let contentSize = rotated ? CGSize(width: imageRect.height, height: imageRect.width) : imageRect.size
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(canvasPanGesture)

                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipped()
                        .frame(width: contentSize.width, height: contentSize.height)

                    CropOverlayView(
                        regions: regions,
                        selectedRegionID: selectedRegionID,
                        onSelect: onSelect,
                        onChange: onCropChange
                    )
                    .frame(width: contentSize.width, height: contentSize.height)
                }
                .frame(width: contentSize.width, height: contentSize.height)
                .rotationEffect(.degrees(rotationDegrees), anchor: .center)
                .position(x: imageRect.midX, y: imageRect.midY)
                .offset(panOffset)
            }
        }
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                panOffset = CGSize(
                    width: panStartOffset.width + value.translation.width,
                    height: panStartOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                panStartOffset = panOffset
            }
    }

    private func aspectFitRect(imageSize: CGSize, bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }

    private func isQuarterTurn(_ degrees: Double) -> Bool {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        return abs(normalized - 90) < 0.001 || abs(normalized - 270) < 0.001 || abs(normalized + 90) < 0.001
    }
}

struct MultiCropOverlay: View {
    let regions: [CropRegion]
    let selectedRegionID: CropRegion.ID?
    let onDelete: (CropRegion.ID) -> Void
    let onSelect: (CropRegion.ID) -> Void
    let onChange: (CropRegion.ID, CGRect, Double) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(regions) { region in
                CropOverlay(region: region, isSelected: region.id == selectedRegionID, onDelete: {
                    onDelete(region.id)
                }, onSelect: {
                    onSelect(region.id)
                }) { rect, angle in
                    onChange(region.id, rect, angle)
                }
            }
        }
    }
}

struct CropOverlayView: NSViewRepresentable {
    let regions: [CropRegion]
    let selectedRegionID: CropRegion.ID?
    let onSelect: (CropRegion.ID) -> Void
    let onChange: (CropRegion.ID, CGRect, Double) -> Void

    func makeNSView(context: Context) -> CropOverlayNSView {
        let view = CropOverlayNSView()
        view.onSelect = onSelect
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: CropOverlayNSView, context: Context) {
        nsView.onSelect = onSelect
        nsView.onChange = onChange
        nsView.set(regions: regions, selectedID: selectedRegionID)
    }
}

final class CropOverlayNSView: NSView {
    var onSelect: ((CropRegion.ID) -> Void)?
    var onChange: ((CropRegion.ID, CGRect, Double) -> Void)?

    private var regions: [CropRegion] = []
    private var selectedID: CropRegion.ID?
    private var activeID: CropRegion.ID?
    private var activeHandle: CropHandle?
    private var dragStartRect = CGRect.zero
    private var dragStartPoint = CGPoint.zero
    private var isDragging = false
    private let cropRed = NSColor(calibratedRed: 1, green: 0.02, blue: 0, alpha: 1)

    override var isFlipped: Bool { true }

    func set(regions: [CropRegion], selectedID: CropRegion.ID?) {
        guard !isDragging else { return }
        self.regions = regions
        self.selectedID = selectedID
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        cropRed.setStroke()
        for region in regions {
            let rect = viewRect(from: region.rect)
            let path = rotatedRectPath(rect: rect, angle: region.angle)
            path.lineWidth = region.id == selectedID ? 2 : 1.5
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hitTestCrop(at: point) else { return }
        selectedID = hit.id
        activeID = hit.id
        activeHandle = hit.handle
        dragStartRect = hit.rect
        dragStartPoint = point
        isDragging = true
        onSelect?(hit.id)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging,
              let activeID,
              let index = regions.firstIndex(where: { $0.id == activeID }) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = (point.x - dragStartPoint.x) / max(1, bounds.width)
        let dy = (point.y - dragStartPoint.y) / max(1, bounds.height)
        var next = dragStartRect
        if let activeHandle {
            next = activeHandle.resize(rect: dragStartRect, dx: dx, dy: dy)
        } else {
            next.origin.x += dx
            next.origin.y += dy
        }
        regions[index].rect = next.normalizedCropRect
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            activeID = nil
            activeHandle = nil
            isDragging = false
        }
        guard let selectedID,
              let region = regions.first(where: { $0.id == selectedID }) else { return }
        onChange?(selectedID, region.rect.normalizedCropRect, region.angle)
    }

    private func hitTestCrop(at point: CGPoint) -> (id: CropRegion.ID, handle: CropHandle?, rect: CGRect)? {
        for region in regions.reversed() {
            let rect = viewRect(from: region.rect)
            if let handle = hitHandle(point: point, rect: rect, angle: region.angle) {
                return (region.id, handle, region.rect)
            }
            if rotatedRectPath(rect: rect, angle: region.angle).contains(point) {
                return (region.id, nil, region.rect)
            }
        }
        return nil
    }

    private func hitHandle(point: CGPoint, rect: CGRect, angle: Double) -> CropHandle? {
        for handle in CropHandle.allCases {
            let center = rotated(point: handle.point(in: rect), around: CGPoint(x: rect.midX, y: rect.midY), angle: angle)
            let size = handle.hitSize(in: rect)
            let hitRect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
            if hitRect.contains(point) {
                return handle
            }
        }
        return nil
    }

    private func viewRect(from normalized: CGRect) -> CGRect {
        CGRect(
            x: normalized.minX * bounds.width,
            y: normalized.minY * bounds.height,
            width: normalized.width * bounds.width,
            height: normalized.height * bounds.height
        )
    }

    private func rotatedRectPath(rect: CGRect, angle: Double) -> NSBezierPath {
        var transform = AffineTransform()
        transform.translate(x: rect.midX, y: rect.midY)
        transform.rotate(byRadians: angle)
        transform.translate(x: -rect.midX, y: -rect.midY)
        let path = NSBezierPath(rect: rect)
        path.transform(using: transform)
        return path
    }

    private func rotated(point: CGPoint, around center: CGPoint, angle: Double) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(angle) - dy * sin(angle),
            y: center.y + dx * sin(angle) + dy * cos(angle)
        )
    }
}

struct CropOverlay: View {
    let region: CropRegion
    let isSelected: Bool
    let onDelete: () -> Void
    let onSelect: () -> Void
    let onChange: (CGRect, Double) -> Void
    @State private var workingRect: CGRect?
    @State private var workingAngle: Double?
    @State private var dragStartRect: CGRect?
    @State private var isDraggingCrop = false
    private let cropRed = Color(red: 1, green: 0.02, blue: 0)

    var body: some View {
        GeometryReader { proxy in
            let current = workingRect ?? region.rect
            let angle = workingAngle ?? region.angle
            let draw = CGRect(
                x: current.minX * proxy.size.width,
                y: current.minY * proxy.size.height,
                width: current.width * proxy.size.width,
                height: current.height * proxy.size.height
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                Rectangle()
                    .fill(cropRed.opacity(0.001))
                    .overlay(
                        Rectangle()
                            .stroke(cropRed.opacity(isSelected ? 1 : 0.9), lineWidth: isSelected ? 2 : 1.5)
                    )
                    .contentShape(Rectangle())
                    .frame(width: draw.width, height: draw.height)
                    .offset(x: draw.minX, y: draw.minY)
                    .rotationEffect(.radians(angle), anchor: .center)
                    .highPriorityGesture(dragGesture(in: proxy.size, handle: nil))
                    .onTapGesture { onSelect() }

                ForEach(CropHandle.edgeHandles) { handle in
                    Rectangle()
                        .fill(cropRed.opacity(0.001))
                        .contentShape(Rectangle())
                        .frame(width: handle.hitSize(in: draw).width, height: handle.hitSize(in: draw).height)
                        .position(rotated(point: handle.point(in: draw), around: CGPoint(x: draw.midX, y: draw.midY), angle: angle))
                        .highPriorityGesture(dragGesture(in: proxy.size, handle: handle))
                }

                ForEach(CropHandle.cornerHandles) { handle in
                    Rectangle()
                        .fill(cropRed.opacity(0.001))
                        .contentShape(Rectangle())
                        .frame(width: handle.hitSize(in: draw).width, height: handle.hitSize(in: draw).height)
                        .position(rotated(point: handle.point(in: draw), around: CGPoint(x: draw.midX, y: draw.midY), angle: angle))
                        .highPriorityGesture(dragGesture(in: proxy.size, handle: handle))
                }
            }
            .onChange(of: region.rect) { _, newValue in
                if !isDraggingCrop {
                    workingRect = newValue
                }
            }
            .onChange(of: region.angle) { _, newValue in
                if !isDraggingCrop {
                    workingAngle = newValue
                }
            }
        }
    }

    private func dragGesture(in size: CGSize, handle: CropHandle?) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = workingRect ?? region.rect
                    isDraggingCrop = true
                    onSelect()
                }
                let startRect = dragStartRect ?? region.rect
                let dx = value.translation.width / max(1, size.width)
                let dy = value.translation.height / max(1, size.height)
                var next = startRect
                if let handle {
                    next = handle.resize(rect: startRect, dx: dx, dy: dy)
                } else {
                    next.origin.x += dx
                    next.origin.y += dy
                }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    workingRect = next.normalizedCropRect
                }
            }
            .onEnded { _ in
                onSelect()
                if let workingRect {
                    onChange(workingRect.normalizedCropRect, workingAngle ?? region.angle)
                }
                dragStartRect = nil
                isDraggingCrop = false
            }
    }

    private func rotated(point: CGPoint, around center: CGPoint, angle: Double) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(angle) - dy * sin(angle),
            y: center.y + dx * sin(angle) + dy * cos(angle)
        )
    }
}

enum CropHandle: CaseIterable, Identifiable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    var id: String { String(describing: self) }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func resize(rect: CGRect, dx: Double, dy: Double) -> CGRect {
        let minSize = 0.05
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
            min(max(value, lower), upper)
        }

        switch self {
        case .topLeft:
            minX = clamp(rect.minX + dx, 0, rect.maxX - minSize)
            minY = clamp(rect.minY + dy, 0, rect.maxY - minSize)
        case .top:
            minY = clamp(rect.minY + dy, 0, rect.maxY - minSize)
        case .topRight:
            maxX = clamp(rect.maxX + dx, rect.minX + minSize, 1)
            minY = clamp(rect.minY + dy, 0, rect.maxY - minSize)
        case .right:
            maxX = clamp(rect.maxX + dx, rect.minX + minSize, 1)
        case .bottomRight:
            maxX = clamp(rect.maxX + dx, rect.minX + minSize, 1)
            maxY = clamp(rect.maxY + dy, rect.minY + minSize, 1)
        case .bottom:
            maxY = clamp(rect.maxY + dy, rect.minY + minSize, 1)
        case .bottomLeft:
            minX = clamp(rect.minX + dx, 0, rect.maxX - minSize)
            maxY = clamp(rect.maxY + dy, rect.minY + minSize, 1)
        case .left:
            minX = clamp(rect.minX + dx, 0, rect.maxX - minSize)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: true
        case .top, .right, .bottom, .left: false
        }
    }

    static var edgeHandles: [CropHandle] {
        [.top, .right, .bottom, .left]
    }

    static var cornerHandles: [CropHandle] {
        [.topLeft, .topRight, .bottomRight]
    }

    private var isHorizontalEdge: Bool {
        self == .top || self == .bottom
    }

    func hitSize(in rect: CGRect) -> CGSize {
        if isCorner {
            CGSize(width: 30, height: 30)
        } else if isHorizontalEdge {
            CGSize(width: max(44, rect.width), height: 18)
        } else {
            CGSize(width: 18, height: max(44, rect.height))
        }
    }
}

struct ViewerLog: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(AppTheme.green).frame(width: 6, height: 6)
                    Text("当前操作反馈")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.79, green: 0.83, blue: 0.88))
                }
                Text(store.logMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.text)
                Text(store.logSubMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(14)
            .frame(maxWidth: 430, alignment: .leading)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer()
            if let summary = store.lastImportSummary {
                VStack(alignment: .leading, spacing: 6) {
                    Text("导入统计")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(summary.folderCount) 个文件夹 · \(summary.subfolderCount) 个子文件夹\n\(summary.imageCount) 张图片")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(12)
                .frame(width: 220, alignment: .leading)
                .background(Color.black.opacity(0.34))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct ParameterPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("参数设置")
                    .font(.system(size: 15, weight: .bold))
                HStack(spacing: 7) {
                    Button {
                        store.addCropRegionToSelectedPhoto()
                    } label: {
                        Image(systemName: "plus.viewfinder")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.orange))
                    .disabled(store.selectedPhoto == nil)
                    .help("添加一个新的裁切框，可在预览区拖动和调整四角")

                    Button {
                        store.smartRedetectSelectedPhoto()
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.blue))
                    .disabled(store.selectedPhoto == nil)
                    .help("自动识别当前页面")

                    Button {
                        store.applyCurrentCropToSelectedFolder()
                    } label: {
                        Image(systemName: "rectangle.stack")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.green))
                    .disabled(!store.canApplyCurrentCropToFolder)
                    .help("将当前图片的裁切框应用到当前文件夹内未手动调整的图片")
                }
                HStack(spacing: 7) {
                    Button { store.nudgeAllCropRegions(dx: -0.001, dy: 0) } label: {
                        Image(systemName: "arrow.left")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.blue))
                    .disabled(store.selectedPhoto == nil)
                    .help("所有红框向左微调")

                    Button { store.nudgeAllCropRegions(dx: 0, dy: -0.001) } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.blue))
                    .disabled(store.selectedPhoto == nil)
                    .help("所有红框向上微调")

                    Button { store.nudgeAllCropRegions(dx: 0, dy: 0.001) } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.blue))
                    .disabled(store.selectedPhoto == nil)
                    .help("所有红框向下微调")

                    Button { store.nudgeAllCropRegions(dx: 0.001, dy: 0) } label: {
                        Image(systemName: "arrow.right")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.blue))
                    .disabled(store.selectedPhoto == nil)
                    .help("所有红框向右微调")

                    Button { store.rotateSelectedCropRegion(degrees: -0.5) } label: {
                        Image(systemName: "rotate.left")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.orange))
                    .disabled(store.selectedCropRegionID == nil)
                    .help("当前选中红框向左旋转 0.5 度")

                    Button { store.rotateSelectedCropRegion(degrees: 0.5) } label: {
                        Image(systemName: "rotate.right")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.orange))
                    .disabled(store.selectedCropRegionID == nil)
                    .help("当前选中红框向右旋转 0.5 度")

                    Button { store.keepOnlySelectedCropRegion() } label: {
                        Image(systemName: "rectangle.stack.badge.minus")
                    }
                    .buttonStyle(AccentIconButtonStyle(color: AppTheme.red))
                    .disabled((store.selectedPhoto?.cropRegions.count ?? 0) <= 1)
                    .help("清除当前画面其他红框，只保留当前选中的 1 个")
                }
                Button {
                    store.addCropRegionToSelectedPhoto()
                } label: {
                    ParameterActionLabel(icon: "plus.rectangle.on.rectangle", title: "新增红框")
                }
                .buttonStyle(ParameterActionButtonStyle(color: AppTheme.orange))
                .disabled(store.selectedPhoto == nil)
            }
            .padding(16)
            .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 1) }

            ScrollView {
                VStack(spacing: 12) {
                    SettingsGroup("识别模式") {
                        AutoModeSummary()
                    }
                    SettingsGroup("自动效果") {
                        VStack(spacing: 10) {
                            AutoCandidatePicker()
                        }
                    }
                    SettingsGroup("边距设置") {
                        VStack(spacing: 10) {
                            if let reference = store.recognitionMarginReference {
                                RecognitionMarginReferenceView(reference: reference)
                            }
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                MarginField(title: "上边距", value: $store.settings.top)
                                MarginField(title: "下边距", value: $store.settings.bottom)
                                MarginField(title: "左边距", value: $store.settings.left)
                                MarginField(title: "右边距", value: $store.settings.right)
                            }
                        }
                    }
                    SettingsGroup("导出设置") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $store.settings.exportFormat) {
                                ForEach(ExportFormat.allCases) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $store.settings.dustRemovalEnabled) {
                                    HStack(spacing: 7) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(AppTheme.orange)
                                        Text("除尘导出")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(AppTheme.text)
                                    }
                                }
                                .toggleStyle(.switch)

                                HStack(spacing: 10) {
                                    Text("强度")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppTheme.muted)
                                    Slider(value: $store.settings.dustRemovalStrength, in: 0...100)
                                        .disabled(!store.settings.dustRemovalEnabled)
                                    Text("\(Int(store.settings.dustRemovalStrength))")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppTheme.muted)
                                        .frame(width: 28, alignment: .trailing)
                                }
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.blue)
                                Text(store.settings.exportDirectory?.path ?? "默认原文件夹")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    store.chooseExportDirectory()
                                } label: {
                                    Image(systemName: "ellipsis")
                                }
                                .buttonStyle(IconButtonStyle())
                                .help("选择导出文件夹")
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(14)
            }
        }
        .panelStyle()
        .onChange(of: store.settings.top) { _, _ in store.reapplySelectedCandidateMargins() }
        .onChange(of: store.settings.bottom) { _, _ in store.reapplySelectedCandidateMargins() }
        .onChange(of: store.settings.left) { _, _ in store.reapplySelectedCandidateMargins() }
        .onChange(of: store.settings.right) { _, _ in store.reapplySelectedCandidateMargins() }
        .onChange(of: store.settings.businessProfile) { _, _ in store.redetectSelectedPhoto() }
        .onChange(of: store.settings.preprocessMode) { _, _ in store.redetectSelectedPhoto() }
        .onChange(of: store.settings.algorithmMode) { _, _ in store.redetectSelectedPhoto() }
        .onChange(of: store.settings.orientation) { _, _ in store.redetectSelectedPhoto() }
    }
}

struct AutoCandidatePicker: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("候选效果")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
            }

            if let photo = store.selectedPhoto {
                if !photo.cropCandidates.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(photo.cropCandidates) { candidate in
                            Button {
                                store.applySelectedCandidate(candidate.id)
                            } label: {
                                CandidateRow(
                                    icon: photo.selectedCandidateID == candidate.id ? "checkmark.circle.fill" : "circle",
                                    title: candidate.title,
                                    detail: "\(candidate.detail) · 可信度 \(Int(candidate.score * 100))%"
                                )
                            }
                            .buttonStyle(CandidateButtonStyle(active: photo.selectedCandidateID == candidate.id))
                        }
                    }
                } else if !photo.cropRegions.isEmpty {
                    CandidateRow(
                        icon: "checkmark.circle.fill",
                        title: "当前裁切框",
                        detail: "已保留当前结果，可重新生成自动效果"
                    )
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppTheme.blue.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.blue.opacity(0.42))
                    }
                }
            } else {
                Text("选择图片后生成自动效果")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.black.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct AutoModeSummary: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 26, height: 26)
                .background(AppTheme.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text("自动最佳")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                Text("自动组合胶片框、分隔线与主体检测")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct CandidateRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
        }
    }
}

struct Filmstrip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("图片胶片栏")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(AppTheme.green).frame(width: 6, height: 6)
                    Text("\(store.tasks.filter { $0.status == .running }.count) 个运行中 · \(store.tasks.filter { $0.status == .waiting }.count) 个等待")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            HStack(spacing: 10) {
                Button {
                    store.selectPreviousPhoto()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(FilmstripNavButtonStyle())
                .disabled(!canMovePrevious)
                .help("上一张")

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.selectedTask?.photos ?? []) { photo in
                                FilmFrame(photo: photo, active: photo.id == store.selectedPhoto?.id)
                                    .id(photo.id)
                                    .onTapGesture { store.selectPhoto(photo.id) }
                            }
                        }
                    }
                    .onChange(of: store.selectedPhoto?.id) { _, photoID in
                        guard let photoID else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(photoID, anchor: .center)
                        }
                    }
                }

                Button {
                    store.selectNextPhoto()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(FilmstripNavButtonStyle())
                .disabled(!canMoveNext)
                .help("下一张")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.line).frame(height: 1) }
    }

    private var selectedPhotoIndex: Int? {
        guard let selectedID = store.selectedPhoto?.id else { return nil }
        return store.selectedTask?.photos.firstIndex { $0.id == selectedID }
    }

    private var canMovePrevious: Bool {
        (selectedPhotoIndex ?? 0) > 0
    }

    private var canMoveNext: Bool {
        guard let photos = store.selectedTask?.photos, let index = selectedPhotoIndex else { return false }
        return index < photos.count - 1
    }
}

struct FilmFrame: View {
    let photo: PhotoItem
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                AsyncCachedImage(url: photo.url, maxPixelSize: 360) { image in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color(red: 0.22, green: 0.18, blue: 0.14)
                }
                Circle().fill(statusColor).frame(width: 8, height: 8).padding(5)
            }
            .frame(width: 112, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(photo.name)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
            Text(photo.status.rawValue)
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.5, green: 0.54, blue: 0.6))
                .lineLimit(1)
        }
        .padding(6)
        .frame(width: 124, height: 78)
        .background(Color(red: 0.115, green: 0.13, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? AppTheme.blue.opacity(0.45) : Color.white.opacity(0.05)))
    }

    private var statusColor: Color {
        switch photo.status {
        case .autoDone, .located: AppTheme.green
        case .manual, .failed: Color(red: 0.87, green: 0.69, blue: 0.43)
        case .running, .locating: AppTheme.blue
        case .pending: Color(red: 0.4, green: 0.44, blue: 0.5)
        }
    }
}

struct DropZoneOverlay: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.isDropTargeted {
            ZStack {
                Color.black.opacity(0.38)
                RoundedRectangle(cornerRadius: 22)
                    .stroke(AppTheme.blue, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .padding(34)
                Text("松开后导入文件夹并递归识别图片")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
            }
        }
    }
}

struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34))
            Text("暂无任务")
                .font(.system(size: 13, weight: .semibold))
            Text("导入文件夹后会按来源建立队列")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.muted)
        }
        .foregroundStyle(AppTheme.muted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.86, green: 0.89, blue: 0.93))
            content
        }
        .padding(14)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05)))
    }
}

struct LabeledPicker<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    let content: Content

    init(title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 48, alignment: .leading)
            Picker("", selection: $selection) {
                content
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(10)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct RecognitionMarginReferenceView: View {
    let reference: CropMarginReference

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "ruler")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.blue)
                Text("\(reference.source)基准")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                Spacer()
                Text("用于对照微调")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.muted)
            }
            HStack(spacing: 6) {
                ReferenceValue(label: "上", value: reference.top)
                ReferenceValue(label: "下", value: reference.bottom)
                ReferenceValue(label: "左", value: reference.left)
                ReferenceValue(label: "右", value: reference.right)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.blue.opacity(0.16)))
    }
}

struct ReferenceValue: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.muted)
            Text("\(Int(round(value)))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct MarginField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.muted)
            Stepper(value: $value, in: 0...80, step: 1) {
                Text("\(Int(value)) px")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct LogoMark: View {
    var body: some View {
        Image(nsImage: AppIcon.image())
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ParameterActionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let color = Color.white.opacity(0.035)
            for x in stride(from: 0, through: size.width, by: 40) {
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }, with: .color(color), lineWidth: 1)
            }
            for y in stride(from: 0, through: size.height, by: 40) {
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }, with: .color(color), lineWidth: 1)
            }
        }
    }
}

enum AppTheme {
    static let text = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let muted = Color(red: 0.59, green: 0.63, blue: 0.69)
    static let blue = Color(red: 0.37, green: 0.53, blue: 0.72)
    static let green = Color(red: 0.31, green: 0.65, blue: 0.55)
    static let orange = Color(red: 0.9, green: 0.55, blue: 0.26)
    static let red = Color(red: 0.95, green: 0.12, blue: 0.1)
    static let line = Color.white.opacity(0.08)
    static let background = LinearGradient(colors: [Color(red: 0.125, green: 0.14, blue: 0.17), Color(red: 0.055, green: 0.063, blue: 0.075)], startPoint: .top, endPoint: .bottom)
    static let viewer = RadialGradient(colors: [Color(red: 0.105, green: 0.12, blue: 0.15), Color(red: 0.05, green: 0.055, blue: 0.07)], center: .top, startRadius: 0, endRadius: 760)
}

struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LinearGradient(colors: [Color(red: 0.102, green: 0.115, blue: 0.138), Color(red: 0.078, green: 0.087, blue: 0.105)], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.05)))
    }
}

extension View {
    func panelStyle() -> some View {
        modifier(PanelStyle())
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.muted)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? Color.white.opacity(0.08) : Color.white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct AccentIconButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 31, height: 31)
            .background(color.opacity(configuration.isPressed ? 0.24 : 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(color.opacity(configuration.isPressed ? 0.58 : 0.36), lineWidth: 1)
            }
            .shadow(color: color.opacity(0.18), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

struct ParameterActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(color.opacity(configuration.isPressed ? 0.18 : 0.075))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(configuration.isPressed ? 0.46 : 0.22), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

struct TopBarButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primary ? AppTheme.text : Color(red: 0.78, green: 0.83, blue: 0.89))
            .frame(width: 94, height: 34)
            .background(primary ? AppTheme.blue : Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(primary ? Color.white.opacity(0.08) : Color.white.opacity(0.06))
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct StartProcessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppTheme.text)
            .frame(width: 82, height: 34)
            .background(AppTheme.green.opacity(configuration.isPressed ? 0.78 : 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.18 : 0.12))
            }
            .shadow(color: AppTheme.green.opacity(0.22), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct FilmstripNavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(AppTheme.muted)
            .frame(width: 30, height: 78)
            .background(configuration.isPressed ? Color.white.opacity(0.075) : Color.white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.white.opacity(0.05))
            }
    }
}

struct PanelButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primary ? AppTheme.text : Color(red: 0.8, green: 0.84, blue: 0.88))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(primary ? AppTheme.blue : Color(red: 0.14, green: 0.155, blue: 0.185))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct CandidateButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? AppTheme.text : Color(red: 0.78, green: 0.83, blue: 0.89))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(active ? AppTheme.blue.opacity(0.18) : Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? AppTheme.blue.opacity(0.42) : Color.white.opacity(0.05))
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct TemplateRetileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(red: 0.78, green: 0.83, blue: 0.89))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Color.white.opacity(configuration.isPressed ? 0.075 : 0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08))
            }
    }
}

struct CropToolButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(destructive ? Color(red: 0.76, green: 0.25, blue: 0.25) : AppTheme.blue)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.78 : 1)
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
