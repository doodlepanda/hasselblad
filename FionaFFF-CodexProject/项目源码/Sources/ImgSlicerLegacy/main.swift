import AppKit
import CoreGraphics
import Foundation
import ImageIO

enum LegacyExportFormat: String {
    case tif = "tif"
    case jpg = "jpg"
}

struct LegacyCrop: Equatable {
    var rect: CGRect
    var angle: CGFloat = 0
}

struct LegacyImageAdjustments: Equatable {
    var levelsEnabled = false
    var curvesEnabled = false
    var inputBlack: Double = 0
    var inputWhite: Double = 1
    var gamma: Double = 1
    var outputBlack: Double = 0
    var outputWhite: Double = 1
    var curveShadows: Double = 0
    var curveMidtones: Double = 0
    var curveHighlights: Double = 0

    var isActive: Bool { levelsEnabled || curvesEnabled }
}

struct LegacyPhoto {
    var url: URL
    var crops: [LegacyCrop]
    var previewRotationDegrees: Int = 0
    var isInverted: Bool = false
    var adjustments = LegacyImageAdjustments()

    var name: String { url.lastPathComponent }
}

struct LegacyTask {
    var name: String
    var rootURL: URL
    var photos: [LegacyPhoto]
    var isStopped: Bool = false

    var cropCount: Int { photos.reduce(0) { $0 + $1.crops.count } }
}

struct LegacyDetectionCandidate {
    var title: String
    var detail: String
    var rects: [CGRect]
    var score: Double

    var crops: [LegacyCrop] {
        rects.sortedForReadingOrder().enumerated().map { _, rect in
            LegacyCrop(rect: rect.normalized)
        }
    }
}

struct LegacyDetectionResult {
    var crops: [LegacyCrop]
    var candidates: [LegacyDetectionCandidate]

    var reportText: String {
        guard !candidates.isEmpty else { return "算法候选：无稳定结果" }
        let lines = candidates.prefix(4).map { candidate in
            "\(candidate.title)：\(candidate.rects.count) 张 · \(Int(candidate.score * 100))%"
        }
        return "算法候选：\n" + lines.joined(separator: "\n")
    }
}

enum LegacyFolderScanner {
    private static let rasterExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif"]

    static func scan(urls: [URL], includeFFFParsing: Bool = true) -> [URL] {
        var result: [URL] = []
        for url in urls {
            result.append(contentsOf: scan(url: url.standardizedFileURL, includeFFFParsing: includeFFFParsing))
        }
        var seen = Set<String>()
        return result
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func scan(url: URL, includeFFFParsing: Bool) -> [URL] {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDirectory {
            return isSupported(url, includeFFFParsing: includeFFFParsing) ? [url] : []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            if isSupported(fileURL, includeFFFParsing: includeFFFParsing) {
                files.append(fileURL)
            }
        }
        return files
    }

    private static func isSupported(_ url: URL, includeFFFParsing: Bool) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if rasterExtensions.contains(fileExtension) { return true }
        return includeFFFParsing && FFFParsingRuntime.fileExtensions.contains(fileExtension)
    }
}

enum LegacyLaunchLog {
    static let url: URL = {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        return (desktop ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("fionafff-mojave.log")
    }()

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

final class LegacyAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var controller: LegacyWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyLaunchLog.write("applicationDidFinishLaunching")
        installMainMenu()
        controller = LegacyWindowController()
        window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.title = "FionaFFF"
        window.setContentSize(NSSize(width: 1280, height: 780))
        window.minSize = NSSize(width: 1040, height: 640)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        LegacyLaunchLog.write("window shown")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.hasRunningTasks else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "仍有任务正在运行，确定退出 FionaFFF？"
        alert.informativeText = "退出会中断当前任务状态，但不会删除原始图片文件。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "FionaFFF")
        let themeItem = NSMenuItem(title: "切换浅色/深色界面", action: #selector(LegacyWindowController.toggleThemeFromMenu(_:)), keyEquivalent: "l")
        themeItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(themeItem)
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 FionaFFF", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }
}

final class LegacyDropRootView: NSView {
    var onFileDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFileDropped?(urls)
        return true
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        if let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            return urls
        }
        if let items = sender.draggingPasteboard.propertyList(forType: .fileURL) as? [String],
           !items.isEmpty {
            return items.compactMap { URL(string: $0) }
        }
        if let item = sender.draggingPasteboard.string(forType: .fileURL) {
            return URL(string: item).map { [$0] } ?? []
        }
        return []
    }
}

final class LegacyTopBarView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            super.mouseUp(with: event)
        }
    }
}

final class LegacyRepeatingButton: NSButton {
    private var repeatTimer: Timer?

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sendAction(self.action, to: self.target)
        }
        RunLoop.current.add(repeatTimer!, forMode: .eventTracking)
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp { break }
        }
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

final class LegacyFilmstripTileView: NSView {
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let background = isSelected
            ? NSColor(calibratedRed: 0.24, green: 0.28, blue: 0.34, alpha: 1)
            : NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.19, alpha: 1)
        background.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        let stroke = isSelected
            ? NSColor(calibratedRed: 0.45, green: 0.62, blue: 0.92, alpha: 1)
            : NSColor.black.withAlphaComponent(0.35)
        stroke.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
        path.lineWidth = isSelected ? 2 : 1
        path.stroke()
    }
}

final class LegacyFlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class LegacyTaskRowView: NSView {
    var isSelected = false {
        didSet { needsDisplay = true }
    }
    var isStopped = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        if isSelected {
            color = NSColor(calibratedRed: 0.24, green: 0.29, blue: 0.37, alpha: 1)
        } else if isStopped {
            color = NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.17, alpha: 1)
        } else {
            color = NSColor(calibratedWhite: 0.18, alpha: 1)
        }
        color.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        let border = isSelected
            ? NSColor(calibratedRed: 0.42, green: 0.60, blue: 0.88, alpha: 1)
            : NSColor.white.withAlphaComponent(0.08)
        border.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
        path.lineWidth = isSelected ? 1.5 : 1
        path.stroke()
    }
}

final class LegacyWindowController: NSViewController {
    private let canvas = LegacyCanvasView()
    private let statusLabel = NSTextField(labelWithString: "拖入或导入 TIFF/JPG 文件开始。")
    private let fileNameLabel = NSTextField(labelWithString: "未导入文件")
    private let outputLabel = NSTextField(labelWithString: "默认导出到原文件夹")
    private let cropCountLabel = NSTextField(labelWithString: "红框 0 个")
    private let detectionReportLabel = NSTextField(labelWithString: "算法候选：等待识别")
    private let algorithmListStack = NSStackView()
    private let taskListScroll = NSScrollView()
    private let taskListStack = LegacyFlippedStackView()
    private let photoPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fffParsingCheckbox = NSButton(checkboxWithTitle: "解析 FFF/3F 文件", target: nil, action: nil)
    private let dustRemovalCheckbox = NSButton(checkboxWithTitle: "除尘导出", target: nil, action: nil)
    private let dustStrengthSlider = NSSlider(value: 35, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let dustStrengthLabel = NSTextField(labelWithString: "强度 35")
    private let filmstripScroll = NSScrollView()
    private let filmstripStack = NSStackView()
    private var tasks: [LegacyTask] = []
    private var selectedTaskIndex = 0
    private var selectedPhotoIndex = 0
    private var exportDirectory: URL?
    private var templateRect: CGRect?
    private var templateImageAspect: Double?
    private var exportFormat: LegacyExportFormat = .tif
    private var dustRemovalEnabled = false
    private var dustRemovalStrength = 35.0
    private var imageAspectCache: [String: Double] = [:]
    private var detectionCandidatesByPhotoPath: [String: [LegacyDetectionCandidate]] = [:]
    private var selectedAlgorithmIndexByPhotoPath: [String: Int] = [:]
    private var usesLightTheme = false
    private weak var topBarView: NSView?
    private weak var leftPanelView: NSView?
    private weak var rightPanelView: NSView?
    private weak var bottomPanelView: NSView?
    private var arrowKeyMonitor: Any?

    private var selectedTask: LegacyTask? {
        tasks.indices.contains(selectedTaskIndex) ? tasks[selectedTaskIndex] : nil
    }

    private var selectedPhoto: LegacyPhoto? {
        guard tasks.indices.contains(selectedTaskIndex),
              tasks[selectedTaskIndex].photos.indices.contains(selectedPhotoIndex) else { return nil }
        return tasks[selectedTaskIndex].photos[selectedPhotoIndex]
    }

    var hasRunningTasks: Bool {
        tasks.contains { !$0.isStopped && !$0.photos.isEmpty }
    }

    override func loadView() {
        LegacyLaunchLog.write("loadView")
        let rootView = LegacyDropRootView(frame: NSRect(x: 0, y: 0, width: 1280, height: 760))
        rootView.onFileDropped = { [weak self] urls in
            self?.importItems(urls)
        }
        view = rootView
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.112, alpha: 1).cgColor

        let topBar = makeTopBar()
        let leftPanel = makeLeftPanel()
        let rightPanel = makeRightPanel()
        let bottomPanel = makeBottomPanel()
        topBarView = topBar
        leftPanelView = leftPanel
        rightPanelView = rightPanel
        bottomPanelView = bottomPanel

        formatPopup.addItems(withTitles: ["TIF 16-bit", "JPG"])
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        fffParsingCheckbox.state = .off
        fffParsingCheckbox.target = self
        fffParsingCheckbox.action = #selector(fffParsingChanged)
        FFFParsingRuntime.isEnabled = false
        dustRemovalCheckbox.target = self
        dustRemovalCheckbox.action = #selector(dustRemovalChanged)
        dustStrengthSlider.target = self
        dustStrengthSlider.action = #selector(dustStrengthChanged)
        photoPopup.target = self
        photoPopup.action = #selector(photoSelectionChanged)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = 8
        canvas.layer?.masksToBounds = true
        canvas.onCropChanged = { [weak self] rect in
            guard let self else { return }
            self.templateRect = rect
            self.templateImageAspect = self.selectedPhoto.flatMap { self.cachedImageAspect(url: $0.url) }
            self.saveCurrentCrops(updateTemplateAspect: false)
            self.refreshSummary()
        }
        canvas.onCropsChanged = { [weak self] in
            self?.saveCurrentCrops()
            self?.refreshSummary()
        }
        canvas.onMagnifierToggled = { [weak self] enabled in
            self?.statusLabel.stringValue = enabled ? "已开启拖动放大镜。" : "已关闭拖动放大镜。"
        }
        canvas.onNudgeAll = { [weak self] dx, dy in
            self?.nudgeAllCrops(dx: dx, dy: dy)
        }
        canvas.onFileDropped = { [weak self] urls in
            self?.importItems(urls)
        }

        view.addSubview(topBar)
        view.addSubview(leftPanel)
        view.addSubview(rightPanel)
        view.addSubview(canvas)
        view.addSubview(bottomPanel)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 54),

            leftPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            leftPanel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            leftPanel.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: -10),
            leftPanel.widthAnchor.constraint(equalToConstant: 222),

            rightPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            rightPanel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            rightPanel.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: -10),
            rightPanel.widthAnchor.constraint(equalToConstant: 238),

            canvas.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: 10),
            canvas.trailingAnchor.constraint(equalTo: rightPanel.leadingAnchor, constant: -10),
            canvas.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            canvas.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: -10),

            bottomPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            bottomPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            bottomPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            bottomPanel.heightAnchor.constraint(equalToConstant: 112)
        ])
        applyTheme()
        LegacyLaunchLog.write("loadView finished")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard arrowKeyMonitor == nil else { return }
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.view.window,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                return event
            }
            switch event.keyCode {
            case 123:
                self.nudgeAllCrops(dx: -0.001, dy: 0)
            case 124:
                self.nudgeAllCrops(dx: 0.001, dy: 0)
            case 125:
                self.nudgeAllCrops(dx: 0, dy: -0.001)
            case 126:
                self.nudgeAllCrops(dx: 0, dy: 0.001)
            default:
                return event
            }
            return nil
        }
    }

    deinit {
        if let arrowKeyMonitor {
            NSEvent.removeMonitor(arrowKeyMonitor)
        }
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        prepareStableButton(button)
        return button
    }

    private func prepareStableButton(_ button: NSButton, role: String = "standard") {
        button.identifier = NSUserInterfaceItemIdentifier("stableButton.\(role)")
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.borderWidth = 1
        applyStableButtonColors(button)
    }

    private func applyStableButtonColors(_ button: NSButton) {
        let isPrimary = button.identifier?.rawValue.hasSuffix(".primary") == true
        let background: NSColor
        let border: NSColor
        let foreground: NSColor
        if usesLightTheme {
            background = isPrimary
                ? NSColor(calibratedRed: 0.78, green: 0.86, blue: 0.96, alpha: 1)
                : NSColor(calibratedWhite: 0.90, alpha: 1)
            border = isPrimary
                ? NSColor(calibratedRed: 0.38, green: 0.55, blue: 0.76, alpha: 1)
                : NSColor(calibratedWhite: 0.68, alpha: 1)
            foreground = NSColor(calibratedWhite: 0.12, alpha: 1)
        } else {
            background = isPrimary
                ? NSColor(calibratedRed: 0.22, green: 0.31, blue: 0.43, alpha: 1)
                : NSColor(calibratedWhite: 0.23, alpha: 1)
            border = isPrimary
                ? NSColor(calibratedRed: 0.39, green: 0.56, blue: 0.78, alpha: 1)
                : NSColor(calibratedWhite: 0.34, alpha: 1)
            foreground = NSColor(calibratedWhite: 0.94, alpha: 1)
        }
        button.layer?.backgroundColor = background.cgColor
        button.layer?.borderColor = border.cgColor
        button.contentTintColor = foreground
        if !button.title.isEmpty {
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [
                    .foregroundColor: foreground,
                    .font: button.font ?? NSFont.systemFont(ofSize: 12)
                ]
            )
        }
    }

    private func iconImage(_ name: String) -> NSImage? {
        let image = NSImage(named: NSImage.Name(name))
        image?.isTemplate = true
        return image
    }

    private func stackedRectanglesIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18))
        image.lockFocus()
        NSColor.black.setStroke()
        let lineWidth: CGFloat = 1.6
        let rects = [
            NSRect(x: 2, y: 8, width: 11, height: 7),
            NSRect(x: 6, y: 5, width: 11, height: 7),
            NSRect(x: 10, y: 2, width: 11, height: 7)
        ]
        for rect in rects {
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
            path.lineWidth = lineWidth
            path.stroke()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func magicWandIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let wand = NSBezierPath()
        wand.lineWidth = 2
        wand.move(to: NSPoint(x: 5, y: 5))
        wand.line(to: NSPoint(x: 17, y: 17))
        wand.stroke()
        for point in [NSPoint(x: 5, y: 17), NSPoint(x: 14, y: 5), NSPoint(x: 18, y: 10)] {
            let sparkle = NSBezierPath()
            sparkle.lineWidth = 1.3
            sparkle.move(to: NSPoint(x: point.x - 3, y: point.y))
            sparkle.line(to: NSPoint(x: point.x + 3, y: point.y))
            sparkle.move(to: NSPoint(x: point.x, y: point.y - 3))
            sparkle.line(to: NSPoint(x: point.x, y: point.y + 3))
            sparkle.stroke()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func importIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        NSColor.black.setStroke()
        let box = NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: 16, height: 12), xRadius: 2, yRadius: 2)
        box.lineWidth = 1.5
        box.stroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 1.8
        arrow.move(to: NSPoint(x: 11, y: 18))
        arrow.line(to: NSPoint(x: 11, y: 8))
        arrow.move(to: NSPoint(x: 7, y: 12))
        arrow.line(to: NSPoint(x: 11, y: 8))
        arrow.line(to: NSPoint(x: 15, y: 12))
        arrow.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func revealIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        NSColor.black.setStroke()
        let window = NSBezierPath(roundedRect: NSRect(x: 3, y: 5, width: 16, height: 12), xRadius: 2, yRadius: 2)
        window.lineWidth = 1.5
        window.stroke()
        let line = NSBezierPath()
        line.lineWidth = 1.3
        line.move(to: NSPoint(x: 6, y: 14))
        line.line(to: NSPoint(x: 16, y: 14))
        line.move(to: NSPoint(x: 7, y: 10))
        line.line(to: NSPoint(x: 13, y: 10))
        line.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func outputFolderIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        NSColor.black.setStroke()
        let tray = NSBezierPath()
        tray.lineWidth = 1.6
        tray.move(to: NSPoint(x: 4, y: 8))
        tray.line(to: NSPoint(x: 4, y: 5))
        tray.line(to: NSPoint(x: 18, y: 5))
        tray.line(to: NSPoint(x: 18, y: 8))
        tray.stroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 1.8
        arrow.move(to: NSPoint(x: 11, y: 18))
        arrow.line(to: NSPoint(x: 11, y: 9))
        arrow.move(to: NSPoint(x: 7, y: 13))
        arrow.line(to: NSPoint(x: 11, y: 9))
        arrow.line(to: NSPoint(x: 15, y: 13))
        arrow.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func loupeIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        NSColor.black.setStroke()
        let lens = NSBezierPath(ovalIn: NSRect(x: 4, y: 7, width: 10, height: 10))
        lens.lineWidth = 1.8
        lens.stroke()
        let handle = NSBezierPath()
        handle.lineWidth = 2
        handle.move(to: NSPoint(x: 12, y: 8))
        handle.line(to: NSPoint(x: 18, y: 3))
        handle.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func invertIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        let rect = NSRect(x: 3, y: 3, width: 16, height: 16)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)).fill()
        NSColor.black.setStroke()
        let outline = NSBezierPath(ovalIn: rect)
        outline.lineWidth = 1.3
        outline.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func iconButton(_ iconName: String, title: String = "", action: Selector, help: String) -> NSButton {
        imageButton(iconImage(iconName), title: title, action: action, help: help)
    }

    private func imageButton(_ image: NSImage?, title: String = "", action: Selector, help: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        prepareStableButton(button)
        button.image = image
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button.toolTip = help
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        if title.isEmpty {
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        return button
    }

    private func iconWideButton(_ title: String, iconName: String, action: Selector, help: String) -> NSButton {
        let button = iconButton(iconName, title: title, action: action, help: help)
        button.alignment = .center
        return button
    }

    private func applyAllButton(title: String = "", compact: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(applyCropsToCurrentTask))
        prepareStableButton(button)
        button.image = stackedRectanglesIcon()
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button.toolTip = "以左上第一帧黑边为基准，将当前红框应用到全部图片"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: compact ? 26 : 28).isActive = true
        if title.isEmpty {
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        return button
    }

    private func makeTopBar() -> NSView {
        let bar = LegacyTopBarView()
        bar.onDoubleClick = { [weak self] in self?.toggleWindowZoom() }
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1).cgColor

        let title = label("FionaFFF", size: 15, weight: .semibold, color: NSColor(calibratedWhite: 0.92, alpha: 1))
        let subtitle = label("Mojave build 0.35.2-73", size: 10, weight: .regular, color: NSColor(calibratedWhite: 0.62, alpha: 1))
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        let importButton = imageButton(importIcon(), title: "导入文件", action: #selector(importFile), help: "导入图片文件或文件夹")
        let exportButton = iconWideButton("导出", iconName: "NSShareTemplate", action: #selector(exportCrops), help: "按当前红框导出")
        let actions = NSStackView(views: [importButton, exportButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        actions.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        bar.addSubview(actions)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 18),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -18),
            actions.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        return bar
    }

    @objc private func toggleWindowZoom() {
        view.window?.zoom(nil)
    }

    private func makeLeftPanel() -> NSView {
        let box = panel()
        let importButton = imageButton(importIcon(), action: #selector(importFile), help: "导入图片文件或文件夹")
        let openFolderButton = imageButton(revealIcon(), action: #selector(openCurrentImageFolder), help: "打开当前图片所在文件夹")
        let fileActions = NSStackView(views: [importButton, openFolderButton])
        fileActions.orientation = .horizontal
        fileActions.alignment = .centerY
        fileActions.spacing = 6

        let identifyButton = NSButton(title: "自动识别", target: self, action: #selector(autoIdentify))
        prepareStableButton(identifyButton, role: "primary")
        identifyButton.image = magicWandIcon()
        identifyButton.imagePosition = .imageLeft
        identifyButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        identifyButton.toolTip = "自动识别当前任务画面"
        identifyButton.translatesAutoresizingMaskIntoConstraints = false
        identifyButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let applyButton = applyAllButton()
        let rotateLeftButton = arrowButton("↶", action: #selector(rotateSelectedCropLeft), help: "当前选中红框向左旋转 0.5 度")
        let rotateRightButton = arrowButton("↷", action: #selector(rotateSelectedCropRight), help: "当前选中红框向右旋转 0.5 度")
        let rotateImageLeftButton = arrowButton("⟲", action: #selector(rotateImageLeft), help: "整张图片向左旋转 90 度，导出方向与预览一致")
        let rotateImageRightButton = arrowButton("⟳", action: #selector(rotateImageRight), help: "整张图片向右旋转 90 度，导出方向与预览一致")
        let zoomOutButton = iconButton("NSExitFullScreenTemplate", action: #selector(zoomOut), help: "缩小预览")
        let resetZoomButton = smallButton("100%", action: #selector(resetZoom))
        resetZoomButton.toolTip = "恢复 100% 预览"
        let zoomInButton = iconButton("NSEnterFullScreenTemplate", action: #selector(zoomIn), help: "放大预览")
        let invertButton = imageButton(invertIcon(), action: #selector(toggleInvertImage), help: "一键反相当前图片，导出保持反相效果")
        let loupeButton = imageButton(loupeIcon(), action: #selector(toggleMagnifier), help: "开启或关闭拖动红框时的放大镜，快捷键 D")

        let rotateActions = NSStackView(views: [
            rotateImageLeftButton,
            rotateImageRightButton,
            rotateLeftButton,
            rotateRightButton
        ])
        rotateActions.orientation = .horizontal
        rotateActions.alignment = .centerY
        rotateActions.spacing = 6
        let zoomActions = NSStackView(views: [zoomOutButton, resetZoomButton, zoomInButton])
        zoomActions.orientation = .horizontal
        zoomActions.alignment = .centerY
        zoomActions.spacing = 6
        let viewActions = NSStackView(views: [applyButton, loupeButton, invertButton])
        viewActions.orientation = .horizontal
        viewActions.alignment = .centerY
        viewActions.spacing = 6

        let fileSection = sectionCard(title: "文件操作", views: [fileActions], tone: 0)
        let toolsContent = NSStackView(views: [
            identifyButton,
            rotateActions,
            zoomActions,
            viewActions
        ])
        toolsContent.orientation = .vertical
        toolsContent.alignment = .leading
        toolsContent.spacing = 8
        let toolsSection = sectionCard(title: "画面与选框", views: [toolsContent], tone: 1)

        let title = label("任务列表", size: 13, weight: .semibold)
        let taskCount = label("0", size: 10, weight: .medium, color: NSColor(calibratedWhite: 0.62, alpha: 1))
        taskCount.identifier = NSUserInterfaceItemIdentifier("taskCountLabel")
        let titleRow = NSStackView(views: [title, taskCount])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.distribution = .fill
        titleRow.spacing = 8

        taskListStack.orientation = .vertical
        taskListStack.alignment = .leading
        taskListStack.spacing = 6
        taskListStack.translatesAutoresizingMaskIntoConstraints = false
        taskListScroll.documentView = taskListStack
        taskListScroll.hasVerticalScroller = true
        taskListScroll.hasHorizontalScroller = false
        taskListScroll.autohidesScrollers = true
        taskListScroll.drawsBackground = false
        taskListScroll.translatesAutoresizingMaskIntoConstraints = false
        let taskSection = sectionCard(title: "", views: [titleRow, taskListScroll], tone: 2)

        for item in [fileSection, toolsSection, taskSection] {
            item.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(item)
        }
        NSLayoutConstraint.activate([
            fileSection.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            fileSection.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            fileSection.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),

            toolsSection.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            toolsSection.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            toolsSection.topAnchor.constraint(equalTo: fileSection.bottomAnchor, constant: 8),
            identifyButton.widthAnchor.constraint(equalTo: toolsSection.widthAnchor, constant: -16),

            taskSection.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            taskSection.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            taskSection.topAnchor.constraint(equalTo: toolsSection.bottomAnchor, constant: 8),
            taskSection.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            taskListScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            taskListStack.widthAnchor.constraint(equalTo: taskListScroll.contentView.widthAnchor),
            titleRow.widthAnchor.constraint(equalTo: taskSection.widthAnchor, constant: -16),
            taskListScroll.widthAnchor.constraint(equalTo: taskSection.widthAnchor, constant: -16)
        ])
        rebuildTaskList()
        return box
    }

    private func makeRightPanel() -> NSView {
        let box = panel()
        let title = label("参数设置", size: 15, weight: .bold)
        let add = iconButton("NSAddTemplate", action: #selector(addBox), help: "新增红框")
        let deleteCrop = iconButton("NSTrashFull", action: #selector(deleteCurrentCrop), help: "删除当前选中的红框")
        let toolRow = NSStackView(views: [add, deleteCrop])
        toolRow.orientation = .horizontal
        toolRow.alignment = .centerY
        toolRow.spacing = 9
        let nudgeUp = repeatingArrowButton("↑", action: #selector(nudgeCropsUp), help: "所有红框向上微调，按住可持续移动")
        let nudgeDown = repeatingArrowButton("↓", action: #selector(nudgeCropsDown), help: "所有红框向下微调，按住可持续移动")
        let nudgeLeft = repeatingArrowButton("←", action: #selector(nudgeCropsLeft), help: "所有红框向左微调，按住可持续移动")
        let nudgeRight = repeatingArrowButton("→", action: #selector(nudgeCropsRight), help: "所有红框向右微调，按住可持续移动")
        let nudgeRow = NSStackView(views: [nudgeLeft, nudgeUp, nudgeDown, nudgeRight])
        nudgeRow.orientation = .horizontal
        nudgeRow.alignment = .centerY
        nudgeRow.spacing = 6
        let choose = imageButton(outputFolderIcon(), action: #selector(chooseOutput), help: "选择导出文件夹")
        let export = iconButton("NSShareTemplate", action: #selector(exportCrops), help: "导出当前任务")
        let exportRow = NSStackView(views: [choose, export])
        exportRow.orientation = .horizontal
        exportRow.alignment = .centerY
        exportRow.spacing = 6
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        algorithmListStack.orientation = .vertical
        algorithmListStack.alignment = .leading
        algorithmListStack.spacing = 5
        algorithmListStack.translatesAutoresizingMaskIntoConstraints = false
        algorithmListStack.setHuggingPriority(.required, for: .vertical)
        algorithmListStack.setContentCompressionResistancePriority(.required, for: .vertical)
        fffParsingCheckbox.font = NSFont.systemFont(ofSize: 12)
        fffParsingCheckbox.contentTintColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        dustRemovalCheckbox.font = NSFont.systemFont(ofSize: 12)
        dustRemovalCheckbox.contentTintColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        dustStrengthSlider.translatesAutoresizingMaskIntoConstraints = false
        dustStrengthLabel.textColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        dustStrengthLabel.font = NSFont.systemFont(ofSize: 11)
        let dustRow = NSStackView(views: [dustRemovalCheckbox, dustStrengthLabel])
        dustRow.orientation = .horizontal
        dustRow.alignment = .centerY
        dustRow.spacing = 8
        outputLabel.textColor = NSColor(calibratedWhite: 0.6, alpha: 1)
        outputLabel.font = NSFont.systemFont(ofSize: 11)
        outputLabel.lineBreakMode = .byTruncatingMiddle
        detectionReportLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        detectionReportLabel.font = NSFont(name: "Menlo", size: 10) ?? NSFont.systemFont(ofSize: 10)
        detectionReportLabel.maximumNumberOfLines = 6
        detectionReportLabel.lineBreakMode = .byWordWrapping
        let shortcutLabel = label("快捷键：方向键移动全部红框 · A 新增 · S/Delete 删除 · D 放大镜 · 滚轮缩放", size: 10, color: NSColor(calibratedWhite: 0.58, alpha: 1))
        shortcutLabel.maximumNumberOfLines = 4
        shortcutLabel.lineBreakMode = .byWordWrapping

        let cropSection = sectionCard(
            title: "裁切框",
            views: [toolRow],
            tone: 0
        )
        let nudgeSection = sectionCard(
            title: "统一微调",
            views: [nudgeRow],
            tone: 1
        )
        let algorithmSection = sectionCard(
            title: "算法结果",
            views: [algorithmListStack],
            tone: 2
        )
        let exportSection = sectionCard(
            title: "导出设置",
            views: [
                fffParsingCheckbox,
                formatPopup,
                dustRow,
                dustStrengthSlider,
                exportRow,
                outputLabel
            ],
            tone: 1
        )

        let stack = NSStackView(views: [
            title,
            separator(),
            cropSection,
            nudgeSection,
            algorithmSection,
            exportSection,
            shortcutLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor, constant: -8),
            cropSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            nudgeSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            algorithmSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            exportSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            algorithmListStack.widthAnchor.constraint(equalTo: algorithmSection.widthAnchor, constant: -16),
            algorithmListStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 183),
            formatPopup.widthAnchor.constraint(equalTo: exportSection.widthAnchor, constant: -16),
            dustStrengthSlider.widthAnchor.constraint(equalTo: exportSection.widthAnchor, constant: -16),
            exportRow.widthAnchor.constraint(lessThanOrEqualTo: exportSection.widthAnchor, constant: -16),
            shortcutLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return box
    }

    private func sectionCard(title: String, views: [NSView], tone: Int) -> NSView {
        let card = NSView()
        card.identifier = NSUserInterfaceItemIdentifier("sectionTone\(tone)")
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 5
        card.layer?.borderWidth = 1

        let content = NSStackView(views: views)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(content)
        if title.isEmpty {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
                content.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
            ])
        } else {
            let heading = label(title, size: 11, weight: .semibold)
            card.addSubview(heading)
            NSLayoutConstraint.activate([
                heading.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                heading.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -8),
                heading.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
                content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
                content.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
                content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
            ])
        }
        applySectionTone(card, tone: tone)
        return card
    }

    private func applySectionTone(_ view: NSView, tone: Int) {
        let darkColors = [
            NSColor(calibratedWhite: 0.115, alpha: 0.72),
            NSColor(calibratedWhite: 0.185, alpha: 0.72),
            NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.21, alpha: 0.82)
        ]
        let lightColors = [
            NSColor(calibratedWhite: 0.91, alpha: 1),
            NSColor(calibratedWhite: 0.965, alpha: 1),
            NSColor(calibratedRed: 0.88, green: 0.92, blue: 0.97, alpha: 1)
        ]
        let colors = usesLightTheme ? lightColors : darkColors
        view.layer?.backgroundColor = colors[min(max(tone, 0), colors.count - 1)].cgColor
        view.layer?.borderColor = (usesLightTheme
            ? NSColor.black.withAlphaComponent(0.12)
            : NSColor.white.withAlphaComponent(0.09)).cgColor
    }

    private func makeBottomPanel() -> NSView {
        let box = panel()
        statusLabel.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        cropCountLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        cropCountLabel.font = NSFont.systemFont(ofSize: 11)
        filmstripStack.orientation = .horizontal
        filmstripStack.alignment = .top
        filmstripStack.spacing = 8
        filmstripStack.translatesAutoresizingMaskIntoConstraints = false
        filmstripScroll.documentView = filmstripStack
        filmstripScroll.hasHorizontalScroller = true
        filmstripScroll.hasVerticalScroller = false
        filmstripScroll.drawsBackground = false
        filmstripScroll.translatesAutoresizingMaskIntoConstraints = false

        let feedback = NSStackView(views: [
            statusLabel,
            cropCountLabel
        ])
        feedback.orientation = .vertical
        feedback.alignment = .leading
        feedback.spacing = 6
        feedback.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [feedback, filmstripScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
            filmstripScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            filmstripScroll.heightAnchor.constraint(equalToConstant: 54)
        ])
        return box
    }

    private func panel() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.145, green: 0.145, blue: 0.155, alpha: 1).cgColor
        view.layer?.cornerRadius = 4
        view.layer?.borderColor = NSColor.black.withAlphaComponent(0.45).cgColor
        view.layer?.borderWidth = 1
        return view
    }

    private func separator() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    @objc func toggleThemeFromMenu(_ sender: Any?) {
        usesLightTheme.toggle()
        applyTheme()
        statusLabel.stringValue = usesLightTheme ? "已切换为浅色界面。" : "已切换为深色界面。"
    }

    private func applyTheme() {
        let rootColor = usesLightTheme ? NSColor(calibratedWhite: 0.84, alpha: 1) : NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.112, alpha: 1)
        let topColor = usesLightTheme ? NSColor(calibratedWhite: 0.92, alpha: 1) : NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
        let panelColor = usesLightTheme ? NSColor(calibratedWhite: 0.96, alpha: 1) : NSColor(calibratedRed: 0.145, green: 0.145, blue: 0.155, alpha: 1)
        let borderColor = usesLightTheme ? NSColor(calibratedWhite: 0.66, alpha: 1) : NSColor.black.withAlphaComponent(0.45)
        let textColor = usesLightTheme ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.88, alpha: 1)
        let mutedColor = usesLightTheme ? NSColor(calibratedWhite: 0.36, alpha: 1) : NSColor(calibratedWhite: 0.62, alpha: 1)

        view.layer?.backgroundColor = rootColor.cgColor
        topBarView?.layer?.backgroundColor = topColor.cgColor
        for panel in [leftPanelView, rightPanelView, bottomPanelView].compactMap({ $0 }) {
            panel.layer?.backgroundColor = panelColor.cgColor
            panel.layer?.borderColor = borderColor.cgColor
        }
        updateSectionTones(in: view)
        updateStableButtonColors(in: view)
        canvas.backgroundColor = usesLightTheme ? NSColor(calibratedWhite: 0.78, alpha: 1) : NSColor(calibratedWhite: 0.12, alpha: 1)
        setTextColors(in: view, textColor: textColor, mutedColor: mutedColor)
    }

    private func updateSectionTones(in root: NSView) {
        for subview in root.subviews {
            if let raw = subview.identifier?.rawValue,
               raw.hasPrefix("sectionTone"),
               let tone = Int(raw.dropFirst("sectionTone".count)) {
                applySectionTone(subview, tone: tone)
            }
            updateSectionTones(in: subview)
        }
    }

    private func updateStableButtonColors(in root: NSView) {
        for subview in root.subviews {
            if let button = subview as? NSButton,
               button.identifier?.rawValue.hasPrefix("stableButton.") == true {
                applyStableButtonColors(button)
            }
            updateStableButtonColors(in: subview)
        }
    }

    private func setTextColors(in root: NSView, textColor: NSColor, mutedColor: NSColor) {
        for subview in root.subviews {
            if let field = subview as? NSTextField {
                field.textColor = field.font?.pointSize ?? 12 <= 10.5 ? mutedColor : textColor
            }
            setTextColors(in: subview, textColor: textColor, mutedColor: mutedColor)
        }
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = NSColor(calibratedWhite: 0.88, alpha: 1)) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func wideButton(_ title: String, action: Selector) -> NSButton {
        let button = button(title, action: action)
        button.controlSize = .regular
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func smallButton(_ title: String, action: Selector) -> NSButton {
        let button = button(title, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: title == "100%" ? 54 : 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private func repeatingArrowButton(_ title: String, action: Selector, help: String) -> NSButton {
        let button = LegacyRepeatingButton(title: title, target: self, action: action)
        prepareStableButton(button)
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        button.toolTip = help
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private func arrowButton(_ title: String, action: Selector, help: String) -> NSButton {
        let button = button(title, action: action)
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        button.toolTip = help
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    @objc private func importFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        var fileTypes = ["tif", "tiff", "jpg", "jpeg", "png", "bmp"]
        if fffParsingCheckbox.state == .on {
            fileTypes.append(contentsOf: FFFParsingRuntime.fileExtensions)
        }
        panel.allowedFileTypes = fileTypes
        if panel.runModal() == .OK {
            importItems(panel.urls)
        }
    }

    private func importItems(_ urls: [URL]) {
        let includeFFFParsing = fffParsingCheckbox.state == .on
        FFFParsingRuntime.isEnabled = includeFFFParsing
        let found = LegacyFolderScanner.scan(urls: urls, includeFFFParsing: includeFFFParsing)
        guard !found.isEmpty else {
            statusLabel.stringValue = includeFFFParsing
                ? "没有找到可处理图片。"
                : "没有找到可处理图片；FFF/3F 解析已关闭。"
            return
        }
        for url in found {
            detectionCandidatesByPhotoPath.removeValue(forKey: photoKey(url))
        }
        let template = templateCompatible(with: found.first) ? templateRect : nil
        let photos = found.map { url in
            let crop = template ?? CGRect(x: 0.05, y: 0.08, width: 0.18, height: 0.72)
            return LegacyPhoto(url: url, crops: [LegacyCrop(rect: crop)])
        }
        let root = taskRootURL(from: urls, fallback: found[0].deletingLastPathComponent())
        let task = LegacyTask(name: taskName(from: urls, fallback: root), rootURL: root, photos: photos)
        tasks.append(task)
        selectedTaskIndex = tasks.count - 1
        selectedPhotoIndex = 0
        exportDirectory = found.first?.deletingLastPathComponent()
        templateRect = photos.first?.crops.first?.rect ?? template
        templateImageAspect = found.first.flatMap { cachedImageAspect(url: $0) }
        rebuildTaskList()
        rebuildPhotoPopup()
        rebuildFilmstrip()
        loadSelectedPhoto()
        statusLabel.stringValue = "已导入 \(photos.count) 张图片。"
        refreshSummary()
    }

    private func loadSelectedPhoto() {
        guard let task = selectedTask, task.photos.indices.contains(selectedPhotoIndex) else {
            canvas.setImage(NSImage(size: NSSize(width: 1, height: 1)), crops: [], rotationDegrees: 0, inverted: false)
            fileNameLabel.stringValue = "未导入文件"
            rebuildAlgorithmPopup(for: nil)
            refreshSummary()
            return
        }
        let photo = task.photos[selectedPhotoIndex]
        guard let image = LegacyImageIO.thumbnail(url: photo.url, maxPixelSize: 6200) else {
            statusLabel.stringValue = "无法打开图片。"
            return
        }
        canvas.setImage(image, crops: photo.crops, rotationDegrees: photo.previewRotationDegrees, inverted: photo.isInverted)
        fileNameLabel.stringValue = "\(task.name)：\(selectedPhotoIndex + 1) / \(task.photos.count)  \(photo.name)"
        outputLabel.stringValue = "输出：\(exportDirectory?.path ?? photo.url.deletingLastPathComponent().path)"
        photoPopup.selectItem(at: selectedPhotoIndex)
        rebuildAlgorithmPopup(for: photo)
        updateFilmstripSelection()
        refreshSummary()
    }

    private func photoKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func rebuildAlgorithmPopup(for photo: LegacyPhoto?) {
        for subview in algorithmListStack.arrangedSubviews {
            algorithmListStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        guard let photo,
              let candidates = detectionCandidatesByPhotoPath[photoKey(photo.url)],
              !candidates.isEmpty else {
            let empty = label("等待自动识别", size: 10, color: NSColor(calibratedWhite: 0.55, alpha: 1))
            empty.alignment = .center
            algorithmListStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: algorithmListStack.widthAnchor).isActive = true
            empty.heightAnchor.constraint(equalToConstant: 46).isActive = true
            detectionReportLabel.stringValue = "算法候选：等待识别"
            return
        }
        let key = photoKey(photo.url)
        let selectedIndex = min(selectedAlgorithmIndexByPhotoPath[key] ?? 0, candidates.count - 1)
        selectedAlgorithmIndexByPhotoPath[key] = selectedIndex
        for (index, candidate) in candidates.enumerated() {
            let button = NSButton(
                title: "\(candidate.title)\n\(candidate.rects.count) 张 · 可信度 \(Int(candidate.score * 100))%",
                target: self,
                action: #selector(algorithmCandidateSelected(_:))
            )
            button.tag = index
            button.setButtonType(.radio)
            button.state = index == selectedIndex ? .on : .off
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 10, weight: index == selectedIndex ? .semibold : .regular)
            button.toolTip = candidate.detail
            button.translatesAutoresizingMaskIntoConstraints = false
            algorithmListStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: algorithmListStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        }
        detectionReportLabel.stringValue = LegacyDetectionResult(crops: [], candidates: candidates).reportText
    }

    @objc private func algorithmCandidateSelected(_ sender: NSButton) {
        guard tasks.indices.contains(selectedTaskIndex),
              tasks[selectedTaskIndex].photos.indices.contains(selectedPhotoIndex) else { return }
        let photo = tasks[selectedTaskIndex].photos[selectedPhotoIndex]
        guard let candidates = detectionCandidatesByPhotoPath[photoKey(photo.url)],
              candidates.indices.contains(sender.tag) else { return }
        selectedAlgorithmIndexByPhotoPath[photoKey(photo.url)] = sender.tag
        let candidate = candidates[sender.tag]
        guard let template = Self.currentFixedTemplate(from: canvas.crops, fallback: templateRect ?? canvas.currentTemplateRect) else {
            statusLabel.stringValue = "需要先有一个参考红框尺寸。"
            return
        }
        let crops = Self.templateSizedCrops(from: candidate.rects, template: template)
        guard !crops.isEmpty else { return }
        tasks[selectedTaskIndex].photos[selectedPhotoIndex].crops = crops
        canvas.crops = crops
        canvas.selectedIndex = crops.isEmpty ? nil : 0
        canvas.needsDisplay = true
        templateRect = crops.sortedForReadingOrder().first?.rect ?? template
        detectionReportLabel.stringValue = LegacyDetectionResult(crops: crops, candidates: candidates).reportText
        statusLabel.stringValue = "已应用算法结果：\(candidate.title) · \(crops.count) 张 · 可信度 \(Int(candidate.score * 100))%。红框尺寸沿用第一框。"
        rebuildAlgorithmPopup(for: tasks[selectedTaskIndex].photos[selectedPhotoIndex])
        refreshSummary()
    }

    private static func currentFixedTemplate(from crops: [LegacyCrop], fallback: CGRect?) -> CGRect? {
        if let first = crops.sortedForReadingOrder().first?.rect.normalized {
            return first
        }
        return fallback?.normalized
    }

    private static func templateSizedCrops(from rects: [CGRect], template: CGRect) -> [LegacyCrop] {
        let fixed = template.normalized
        let width = min(max(fixed.width, 0.001), 1)
        let height = min(max(fixed.height, 0.001), 1)
        let ordered = rects.sortedForReadingOrder()
        return ordered.map { rect in
            let normalized = rect.normalized
            let x = min(max(normalized.midX - width / 2, 0), max(0, 1 - width))
            let y = min(max(normalized.midY - height / 2, 0), max(0, 1 - height))
            return LegacyCrop(rect: CGRect(x: x, y: y, width: width, height: height).normalized)
        }
    }

    private func saveCurrentCrops(updateTemplateAspect: Bool = true) {
        guard tasks.indices.contains(selectedTaskIndex),
              tasks[selectedTaskIndex].photos.indices.contains(selectedPhotoIndex) else { return }
        tasks[selectedTaskIndex].photos[selectedPhotoIndex].crops = canvas.crops
        tasks[selectedTaskIndex].photos[selectedPhotoIndex].previewRotationDegrees = canvas.previewRotationDegrees
        tasks[selectedTaskIndex].photos[selectedPhotoIndex].isInverted = canvas.isInverted
        if let selected = canvas.currentTemplateRect {
            templateRect = selected
            if updateTemplateAspect {
                templateImageAspect = selectedPhoto.flatMap { cachedImageAspect(url: $0.url) }
            }
        }
    }

    private func templateCompatible(with url: URL?) -> Bool {
        guard let templateImageAspect,
              let url,
              let currentAspect = cachedImageAspect(url: url) else {
            return true
        }
        let diff = abs(currentAspect - templateImageAspect) / max(max(currentAspect, templateImageAspect), 0.0001)
        return diff < 0.18
    }

    private func cachedImageAspect(url: URL) -> Double? {
        let key = url.standardizedFileURL.path
        if let cached = imageAspectCache[key] {
            return cached
        }
        guard let aspect = Self.imageAspect(url: url) else {
            return nil
        }
        imageAspectCache[key] = aspect
        return aspect
    }

    private static func imageAspect(url: URL) -> Double? {
        if let decoder = FFFParsingRuntime.decoder(for: url) {
            return Double(decoder.info.width) / Double(max(decoder.info.height, 1))
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
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              height > 0 else {
            return nil
        }
        return Double(width) / Double(height)
    }

    private func rebuildTaskList() {
        for subview in taskListStack.arrangedSubviews {
            taskListStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        updateTaskCountLabel(in: view)
        guard !tasks.isEmpty else {
            let empty = label("暂无任务\n拖入文件夹或点击导入", size: 10, color: NSColor(calibratedWhite: 0.55, alpha: 1))
            empty.alignment = .center
            empty.maximumNumberOfLines = 3
            empty.translatesAutoresizingMaskIntoConstraints = false
            taskListStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: taskListStack.widthAnchor).isActive = true
            empty.heightAnchor.constraint(equalToConstant: 70).isActive = true
            return
        }
        for (index, task) in tasks.enumerated() {
            let row = LegacyTaskRowView()
            row.isSelected = index == selectedTaskIndex
            row.isStopped = task.isStopped
            row.translatesAutoresizingMaskIntoConstraints = false

            let select = NSButton(title: "", target: self, action: #selector(taskListSelectionChanged(_:)))
            select.tag = index
            select.isBordered = false
            select.translatesAutoresizingMaskIntoConstraints = false

            let name = NSTextField(labelWithString: task.name)
            name.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            name.textColor = NSColor(calibratedWhite: 0.9, alpha: 1)
            name.lineBreakMode = .byTruncatingMiddle
            name.translatesAutoresizingMaskIntoConstraints = false

            let stateText = task.isStopped ? "已终止" : "运行中"
            let detail = NSTextField(labelWithString: "\(task.photos.count) 张 · \(stateText)")
            detail.font = NSFont.systemFont(ofSize: 9)
            detail.textColor = task.isStopped
                ? NSColor(calibratedRed: 0.86, green: 0.48, blue: 0.48, alpha: 1)
                : NSColor(calibratedWhite: 0.58, alpha: 1)
            detail.translatesAutoresizingMaskIntoConstraints = false

            let stop = iconButton("NSStopProgressTemplate", action: #selector(stopTaskFromList(_:)), help: "终止这个任务")
            stop.tag = index
            stop.isEnabled = !task.isStopped
            let remove = iconButton("NSTrashFull", action: #selector(deleteTaskFromList(_:)), help: "删除这个任务")
            remove.tag = index

            for item in [select, name, detail, stop, remove] {
                row.addSubview(item)
            }
            taskListStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: taskListStack.widthAnchor),
                row.heightAnchor.constraint(equalToConstant: 58),
                select.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                select.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                select.topAnchor.constraint(equalTo: row.topAnchor),
                select.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                name.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 9),
                name.trailingAnchor.constraint(equalTo: stop.leadingAnchor, constant: -6),
                name.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
                detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
                detail.trailingAnchor.constraint(equalTo: name.trailingAnchor),
                detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 3),
                stop.widthAnchor.constraint(equalToConstant: 26),
                stop.heightAnchor.constraint(equalToConstant: 24),
                stop.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                stop.trailingAnchor.constraint(equalTo: remove.leadingAnchor, constant: -4),
                remove.widthAnchor.constraint(equalToConstant: 26),
                remove.heightAnchor.constraint(equalToConstant: 24),
                remove.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                remove.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -7)
            ])
            row.addSubview(stop, positioned: .above, relativeTo: select)
            row.addSubview(remove, positioned: .above, relativeTo: select)
        }
    }

    private func updateTaskCountLabel(in root: NSView) {
        for subview in root.subviews {
            if let field = subview as? NSTextField,
               field.identifier == NSUserInterfaceItemIdentifier("taskCountLabel") {
                field.stringValue = "\(tasks.count)"
                return
            }
            updateTaskCountLabel(in: subview)
        }
    }

    private func rebuildPhotoPopup() {
        photoPopup.removeAllItems()
        guard let task = selectedTask, !task.photos.isEmpty else {
            photoPopup.addItem(withTitle: "未导入图片")
            return
        }
        photoPopup.addItems(withTitles: task.photos.enumerated().map { "\($0.offset + 1). \($0.element.name)" })
    }

    private func rebuildFilmstrip() {
        for subview in filmstripStack.arrangedSubviews {
            filmstripStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        guard let task = selectedTask else { return }
        for (index, photo) in task.photos.enumerated() {
            let imageView = NSImageView()
            imageView.image = NSWorkspace.shared.icon(forFile: photo.url.path)
            imageView.imageScaling = .scaleProportionallyDown
            imageView.imageAlignment = .alignCenter
            imageView.translatesAutoresizingMaskIntoConstraints = false

            let titleLabel = NSTextField(labelWithString: photo.name)
            titleLabel.alignment = .left
            titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            titleLabel.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
            titleLabel.lineBreakMode = .byTruncatingMiddle
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let button = NSButton(title: "", target: self, action: #selector(filmstripPhotoSelected(_:)))
            button.tag = index
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.setButtonType(.momentaryPushIn)
            button.translatesAutoresizingMaskIntoConstraints = false

            let deleteButton = NSButton(title: "×", target: self, action: #selector(deleteFilmstripPhoto(_:)))
            deleteButton.tag = index
            deleteButton.bezelStyle = .circular
            deleteButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            deleteButton.toolTip = "从当前任务移除这个文件"
            deleteButton.translatesAutoresizingMaskIntoConstraints = false
            let tile = LegacyFilmstripTileView()
            tile.translatesAutoresizingMaskIntoConstraints = false
            tile.addSubview(imageView)
            tile.addSubview(titleLabel)
            tile.addSubview(button)
            tile.addSubview(deleteButton)
            NSLayoutConstraint.activate([
                tile.widthAnchor.constraint(equalToConstant: 206),
                tile.heightAnchor.constraint(equalToConstant: 44),
                imageView.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 8),
                imageView.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 28),
                imageView.heightAnchor.constraint(equalToConstant: 28),
                titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
                titleLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),
                titleLabel.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
                button.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 4),
                button.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -34),
                button.topAnchor.constraint(equalTo: tile.topAnchor, constant: 4),
                button.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -4),
                deleteButton.widthAnchor.constraint(equalToConstant: 22),
                deleteButton.heightAnchor.constraint(equalToConstant: 22),
                deleteButton.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
                deleteButton.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -6)
            ])
            tile.addSubview(deleteButton, positioned: .above, relativeTo: button)
            filmstripStack.addArrangedSubview(tile)
        }
        updateFilmstripSelection()
    }

    private func updateFilmstripSelection() {
        for view in filmstripStack.arrangedSubviews {
            if let tile = view as? LegacyFilmstripTileView {
                tile.isSelected = filmstripButtons(in: tile).contains { button in
                    button.action == #selector(filmstripPhotoSelected(_:)) && button.tag == selectedPhotoIndex
                }
            }
            let buttons = filmstripButtons(in: view)
            for button in buttons where button.action == #selector(filmstripPhotoSelected(_:)) {
                button.state = button.tag == selectedPhotoIndex ? .on : .off
            }
        }
    }

    private func filmstripButtons(in view: NSView) -> [NSButton] {
        var result: [NSButton] = []
        if let button = view as? NSButton {
            result.append(button)
        }
        for subview in view.subviews {
            result.append(contentsOf: filmstripButtons(in: subview))
        }
        return result
    }

    @objc private func taskListSelectionChanged(_ sender: NSButton) {
        selectTask(at: sender.tag)
    }

    private func selectTask(at index: Int) {
        guard tasks.indices.contains(index) else { return }
        saveCurrentCrops()
        selectedTaskIndex = index
        selectedPhotoIndex = 0
        exportDirectory = selectedTask?.rootURL
        rebuildTaskList()
        rebuildPhotoPopup()
        rebuildFilmstrip()
        loadSelectedPhoto()
    }

    @objc private func photoSelectionChanged() {
        saveCurrentCrops()
        selectedPhotoIndex = max(0, photoPopup.indexOfSelectedItem)
        loadSelectedPhoto()
    }

    @objc private func filmstripPhotoSelected(_ sender: NSButton) {
        saveCurrentCrops()
        selectedPhotoIndex = sender.tag
        loadSelectedPhoto()
    }

    @objc private func deleteFilmstripPhoto(_ sender: NSButton) {
        guard tasks.indices.contains(selectedTaskIndex),
              tasks[selectedTaskIndex].photos.indices.contains(sender.tag) else { return }
        let removedPhoto = tasks[selectedTaskIndex].photos[sender.tag]
        let name = removedPhoto.name
        detectionCandidatesByPhotoPath.removeValue(forKey: photoKey(removedPhoto.url))
        if sender.tag != selectedPhotoIndex {
            saveCurrentCrops()
        }
        let previousSelection = selectedPhotoIndex
        let removedCurrentPhoto = sender.tag == previousSelection
        tasks[selectedTaskIndex].photos.remove(at: sender.tag)
        if tasks[selectedTaskIndex].photos.isEmpty {
            let taskName = tasks[selectedTaskIndex].name
            tasks.remove(at: selectedTaskIndex)
            selectedTaskIndex = min(selectedTaskIndex, max(0, tasks.count - 1))
            selectedPhotoIndex = 0
            statusLabel.stringValue = "已移除文件 \(name)，任务 \(taskName) 已为空并删除。"
        } else {
            if sender.tag == previousSelection {
                selectedPhotoIndex = min(previousSelection, tasks[selectedTaskIndex].photos.count - 1)
            } else if sender.tag < previousSelection {
                selectedPhotoIndex = max(0, previousSelection - 1)
            } else {
                selectedPhotoIndex = min(previousSelection, tasks[selectedTaskIndex].photos.count - 1)
            }
            statusLabel.stringValue = "已从当前任务移除文件：\(name)"
        }
        rebuildTaskList()
        rebuildPhotoPopup()
        rebuildFilmstrip()
        if removedCurrentPhoto || tasks.isEmpty {
            loadSelectedPhoto()
        } else {
            photoPopup.selectItem(at: selectedPhotoIndex)
            updateFilmstripSelection()
            refreshSummary()
        }
    }

    @objc private func stopSelectedTask() {
        stopTask(at: selectedTaskIndex)
    }

    @objc private func stopTaskFromList(_ sender: NSButton) {
        stopTask(at: sender.tag)
    }

    private func stopTask(at index: Int) {
        guard tasks.indices.contains(index) else { return }
        tasks[index].isStopped = true
        statusLabel.stringValue = "已终止任务：\(tasks[index].name)"
        rebuildTaskList()
        refreshSummary()
    }

    @objc private func openCurrentImageFolder() {
        guard let photo = selectedPhoto else {
            statusLabel.stringValue = "当前没有选中的图片。"
            return
        }
        let folder = photo.url.deletingLastPathComponent()
        NSWorkspace.shared.selectFile(photo.url.path, inFileViewerRootedAtPath: folder.path)
        statusLabel.stringValue = "已打开当前图片所在文件夹。"
    }

    @objc private func deleteSelectedTask() {
        deleteTask(at: selectedTaskIndex)
    }

    @objc private func deleteTaskFromList(_ sender: NSButton) {
        deleteTask(at: sender.tag)
    }

    private func deleteTask(at index: Int) {
        guard tasks.indices.contains(index) else { return }
        let name = tasks[index].name
        tasks.remove(at: index)
        selectedTaskIndex = min(selectedTaskIndex, max(0, tasks.count - 1))
        selectedPhotoIndex = 0
        rebuildTaskList()
        rebuildPhotoPopup()
        rebuildFilmstrip()
        loadSelectedPhoto()
        statusLabel.stringValue = "已删除任务：\(name)"
    }

    @objc private func applyCropsToCurrentTask() {
        saveCurrentCrops()
        guard tasks.indices.contains(selectedTaskIndex), !canvas.crops.isEmpty else { return }
        guard !tasks[selectedTaskIndex].isStopped else {
            statusLabel.stringValue = "当前任务已终止，无法应用到全部。"
            return
        }
        let taskIndex = selectedTaskIndex
        let sourceCrops = canvas.crops.sortedForReadingOrder()
        let anchor = sourceCrops[0].rect.normalized
        let photos = tasks[taskIndex].photos
        let selectedIndex = selectedPhotoIndex
        statusLabel.stringValue = "正在以左上第一帧黑边为基准应用到其他图片..."
        DispatchQueue.global(qos: .userInitiated).async {
            let results = photos.enumerated().map { index, photo in
                if index == selectedIndex {
                    return sourceCrops
                }
                return LegacyFrameDetector.anchorAlignedCrops(url: photo.url, sourceCrops: sourceCrops, anchor: anchor)
            }
            DispatchQueue.main.async {
                guard self.tasks.indices.contains(taskIndex) else { return }
                for index in self.tasks[taskIndex].photos.indices {
                    self.tasks[taskIndex].photos[index].crops = results[index]
                }
                self.loadSelectedPhoto()
                self.statusLabel.stringValue = "已保留当前图片微调结果，并按左上第一帧黑边基准应用到其他图片。"
                self.refreshSummary()
            }
        }
    }

    @objc private func addBox() {
        let rect = templateRect ?? canvas.currentTemplateRect ?? CGRect(x: 0.05, y: 0.08, width: 0.18, height: 0.72)
        canvas.crops.append(LegacyCrop(rect: rect))
        canvas.selectedIndex = canvas.crops.count - 1
        templateRect = rect
        canvas.needsDisplay = true
        saveCurrentCrops()
        refreshSummary()
    }

    @objc private func deleteCurrentCrop() {
        canvas.deleteSelectedCrop()
        saveCurrentCrops()
        statusLabel.stringValue = "已删除当前选中的红框。"
        refreshSummary()
    }

    @objc private func clearCurrentCrops() {
        canvas.crops.removeAll()
        canvas.selectedIndex = nil
        saveCurrentCrops()
        statusLabel.stringValue = "已清除当前图片所有红框。"
        refreshSummary()
    }

    @objc private func nudgeCropsUp() { nudgeAllCrops(dx: 0, dy: 0.001) }
    @objc private func nudgeCropsDown() { nudgeAllCrops(dx: 0, dy: -0.001) }
    @objc private func nudgeCropsLeft() { nudgeAllCrops(dx: -0.001, dy: 0) }
    @objc private func nudgeCropsRight() { nudgeAllCrops(dx: 0.001, dy: 0) }

    @objc private func rotateSelectedCropLeft() {
        canvas.rotateSelectedCrop(byDegrees: -0.5)
        statusLabel.stringValue = "已将当前选中红框向左旋转 0.5°。"
    }

    @objc private func rotateSelectedCropRight() {
        canvas.rotateSelectedCrop(byDegrees: 0.5)
        statusLabel.stringValue = "已将当前选中红框向右旋转 0.5°。"
    }

    @objc private func rotateImageLeft() {
        guard tasks.indices.contains(selectedTaskIndex),
              tasks[selectedTaskIndex].photos.indices.contains(selectedPhotoIndex) else { return }
        canvas.rotatePreviewImage(byDegrees: -90)
        saveCurrentCrops(updateTemplateAspect: false)
        statusLabel.stringValue = "已将当前图片向左旋转 90°，导出会保持预览方向。"
    }

    @objc private func rotateImageRight() {
        guard tasks.indices.contains(selectedTaskIndex),
              tasks[selectedTaskIndex].photos.indices.contains(selectedPhotoIndex) else { return }
        canvas.rotatePreviewImage(byDegrees: 90)
        saveCurrentCrops(updateTemplateAspect: false)
        statusLabel.stringValue = "已将当前图片向右旋转 90°，导出会保持预览方向。"
    }

    @objc private func toggleInvertImage() {
        guard tasks.indices.contains(selectedTaskIndex),
              tasks[selectedTaskIndex].photos.indices.contains(selectedPhotoIndex) else { return }
        canvas.isInverted.toggle()
        saveCurrentCrops(updateTemplateAspect: false)
        statusLabel.stringValue = canvas.isInverted ? "已反相当前图片，导出会保持反相效果。" : "已取消当前图片反相。"
    }

    @objc private func toggleMagnifier() {
        canvas.isMagnifierEnabled.toggle()
        statusLabel.stringValue = canvas.isMagnifierEnabled ? "已开启拖动放大镜。" : "已关闭拖动放大镜。"
    }

    private func nudgeAllCrops(dx: CGFloat, dy: CGFloat) {
        guard !canvas.crops.isEmpty else { return }
        canvas.crops = canvas.crops.map { LegacyCrop(rect: $0.rect.offsetBy(dx: dx, dy: dy).normalized, angle: $0.angle) }
        saveCurrentCrops()
        statusLabel.stringValue = "已统一微调当前图片全部红框。"
        refreshSummary()
    }

    @objc private func autoIdentify() {
        saveCurrentCrops()
        guard tasks.indices.contains(selectedTaskIndex), !tasks[selectedTaskIndex].photos.isEmpty else { return }
        guard !tasks[selectedTaskIndex].isStopped else {
            statusLabel.stringValue = "当前任务已终止，无法自动识别。"
            return
        }
        let template = templateRect ?? canvas.currentTemplateRect
        guard let template else { return }
        let taskIndex = selectedTaskIndex
        let photos = tasks[taskIndex].photos
        let selectedIndex = selectedPhotoIndex
        statusLabel.stringValue = "正在批量按参考红框和黑色片距识别..."
        DispatchQueue.global(qos: .userInitiated).async {
            let detections = photos.map { photo -> LegacyDetectionResult in
                let result = LegacyFrameDetector.detectBestTemplateCropsWithReport(url: photo.url, template: template)
                if result.crops.isEmpty {
                    return LegacyDetectionResult(crops: LegacyFrameDetector.tiledCrops(template: template), candidates: result.candidates)
                }
                let candidate = result.candidates.first
                let fixed = Self.templateSizedCrops(from: candidate?.rects ?? result.crops.map(\.rect), template: template)
                return LegacyDetectionResult(crops: fixed, candidates: result.candidates)
            }
            DispatchQueue.main.async {
                guard self.tasks.indices.contains(taskIndex) else { return }
                for index in self.tasks[taskIndex].photos.indices {
                    self.tasks[taskIndex].photos[index].crops = detections[index].crops
                    self.detectionCandidatesByPhotoPath[self.photoKey(photos[index].url)] = detections[index].candidates
                }
                self.loadSelectedPhoto()
                let count = detections.reduce(0) { $0 + $1.crops.count }
                if detections.indices.contains(selectedIndex) {
                    self.detectionReportLabel.stringValue = detections[selectedIndex].reportText
                }
                self.statusLabel.stringValue = "已识别 \(photos.count) 张图片，共 \(count) 个红框。"
                self.refreshSummary()
            }
        }
    }

    @objc private func exportCrops() {
        saveCurrentCrops()
        guard let task = selectedTask, !task.photos.isEmpty else { return }
        guard !task.isStopped else {
            statusLabel.stringValue = "当前任务已终止，无法导出。"
            return
        }
        let directory = exportDirectory ?? task.rootURL
        let format = exportFormat
        let dustEnabled = dustRemovalEnabled
        let dustStrength = dustRemovalStrength
        let photos = task.photos
        statusLabel.stringValue = dustEnabled ? "正在批量导出并除尘..." : "正在批量导出..."
        DispatchQueue.global(qos: .userInitiated).async {
            var outputs: [URL] = []
            for photo in photos {
                outputs.append(contentsOf: LegacyExporter.export(url: photo.url, crops: photo.crops, directory: directory, format: format, dustEnabled: dustEnabled, dustStrength: dustStrength, rotationDegrees: photo.previewRotationDegrees, inverted: photo.isInverted, adjustments: photo.adjustments))
            }
            DispatchQueue.main.async {
                self.statusLabel.stringValue = "已导出 \(outputs.count) 个文件到 \(directory.path)"
            }
        }
    }

    @objc private func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = exportDirectory
        if panel.runModal() == .OK, let url = panel.url {
            exportDirectory = url
            outputLabel.stringValue = "输出：\(url.path)"
            statusLabel.stringValue = "已选择导出文件夹。"
        }
    }

    @objc private func formatChanged() {
        exportFormat = formatPopup.indexOfSelectedItem == 0 ? .tif : .jpg
    }

    @objc private func fffParsingChanged() {
        FFFParsingRuntime.isEnabled = fffParsingCheckbox.state == .on
        statusLabel.stringValue = FFFParsingRuntime.isEnabled
            ? "已开启 FFF/3F 文件解析。"
            : "已关闭 FFF/3F 文件解析；再次导入时会跳过这些文件。"
    }

    @objc private func dustRemovalChanged() {
        dustRemovalEnabled = dustRemovalCheckbox.state == .on
    }

    @objc private func dustStrengthChanged() {
        dustRemovalStrength = dustStrengthSlider.doubleValue.rounded()
        dustStrengthLabel.stringValue = "强度 \(Int(dustRemovalStrength))"
    }

    @objc private func zoomIn() { canvas.adjustZoom(by: 1.2) }
    @objc private func zoomOut() { canvas.adjustZoom(by: 1 / 1.2) }
    @objc private func resetZoom() { canvas.resetViewTransform() }

    private func refreshSummary() {
        let totalPhotos = tasks.reduce(0) { $0 + $1.photos.count }
        let totalCrops = tasks.reduce(0) { $0 + $1.cropCount }
        let taskText = selectedTask.map { "\($0.name) · \($0.photos.count) 张" } ?? "未导入任务"
        cropCountLabel.stringValue = "\(tasks.count) 个任务 · \(totalPhotos) 张图片 · 当前任务 \(taskText) · 当前红框 \(canvas.crops.count) 个 · 全部红框 \(totalCrops) 个 · A 新增，S/Delete 删除，D 放大镜，滚轮缩放"
    }

    private func taskRootURL(from urls: [URL], fallback: URL) -> URL {
        if urls.count == 1 {
            let url = urls[0].standardizedFileURL
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory ? url : url.deletingLastPathComponent()
        }
        return fallback
    }

    private func taskName(from urls: [URL], fallback: URL) -> String {
        if urls.count == 1 {
            let url = urls[0].standardizedFileURL
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory ? url.lastPathComponent : url.deletingLastPathComponent().lastPathComponent
        }
        return fallback.lastPathComponent.isEmpty ? "导入任务 \(tasks.count + 1)" : fallback.lastPathComponent
    }
}

final class LegacyCanvasView: NSView {
    var crops: [LegacyCrop] = [] {
        didSet {
            if !isUpdatingCropInteractively {
                needsDisplay = true
            }
        }
    }
    var selectedIndex: Int?
    var previewRotationDegrees: Int = 0 { didSet { needsDisplay = true } }
    var isInverted: Bool = false {
        didSet {
            if isInverted, invertedImage == nil {
                invertedImage = Self.invertedPreview(from: image)
            }
            displayInvertedPreviewImage = nil
            wheelInvertedPreviewImage = nil
            needsDisplay = true
        }
    }
    var backgroundColor: NSColor = NSColor(calibratedWhite: 0.12, alpha: 1) { didSet { needsDisplay = true } }
    var onCropChanged: ((CGRect) -> Void)?
    var onCropsChanged: (() -> Void)?
    var onFileDropped: (([URL]) -> Void)?
    var onMagnifierToggled: ((Bool) -> Void)?
    var onNudgeAll: ((CGFloat, CGFloat) -> Void)?
    var zoom: CGFloat = 1 {
        didSet {
            if !suppressZoomRedraw {
                needsDisplay = true
            }
        }
    }
    var isMagnifierEnabled = false {
        didSet {
            if !isMagnifierEnabled { magnifierPoint = nil }
            needsDisplay = true
        }
    }

    private var image: NSImage?
    private var invertedImage: NSImage?
    private var displayPreviewImage: NSImage?
    private var displayInvertedPreviewImage: NSImage?
    private var wheelPreviewImage: NSImage?
    private var wheelInvertedPreviewImage: NSImage?
    private var activeHandle: CropHandle?
    private var activeIndex: Int?
    private var magnifierPoint: CGPoint?
    private var lastMagnifierFrame = CGRect.null
    private var lastMagnifierUpdateTime: TimeInterval = 0
    private var isUpdatingCropInteractively = false
    private var startCrop = CGRect.zero
    private var startAngle: CGFloat = 0
    private var startPoint = CGPoint.zero
    private var panOffset = CGPoint.zero
    private var startPanOffset = CGPoint.zero
    private var isPanning = false
    private var isWheelZooming = false
    private var suppressZoomRedraw = false
    private var lastWheelZoomDisplayTime: TimeInterval = 0
    private var lastPanDisplayTime: TimeInterval = 0
    private var lastCropDisplayTime: TimeInterval = 0
    private var pendingCropDirtyRect = CGRect.null
    private var interactionSnapshot: NSImage?
    private var snapshotZoom: CGFloat = 1
    private var snapshotPanOffset = CGPoint.zero
    private let usesMojaveRenderingPath: Bool = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion == 10 && version.minorVersion <= 14
    }()

    var currentTemplateRect: CGRect? {
        selectedIndex.flatMap { crops.indices.contains($0) ? crops[$0].rect : nil } ?? crops.first?.rect
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    func setImage(_ image: NSImage, crops: [LegacyCrop], rotationDegrees: Int, inverted: Bool) {
        self.image = image
        invertedImage = nil
        displayPreviewImage = usesMojaveRenderingPath
            ? Self.downsampledPreview(from: image, maxPixelSize: 2800)
            : nil
        displayInvertedPreviewImage = nil
        wheelPreviewImage = Self.downsampledPreview(
            from: image,
            maxPixelSize: usesMojaveRenderingPath ? 1200 : 1800
        )
        wheelInvertedPreviewImage = nil
        self.crops = crops
        previewRotationDegrees = normalizedRotation(rotationDegrees)
        isInverted = inverted
        selectedIndex = crops.isEmpty ? nil : 0
        panOffset = .zero
        magnifierPoint = nil
        lastMagnifierFrame = .null
        pendingCropDirtyRect = .null
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
        if usesMojaveRenderingPath,
           let interactionSnapshot,
           isWheelZooming || isPanning {
            let scale = max(0.01, zoom / max(snapshotZoom, 0.01))
            let center = CGPoint(
                x: bounds.midX + snapshotPanOffset.x,
                y: bounds.midY + snapshotPanOffset.y
            )
            let translatedCenter = CGPoint(
                x: center.x + panOffset.x - snapshotPanOffset.x,
                y: center.y + panOffset.y - snapshotPanOffset.y
            )
            let destination = CGRect(
                x: translatedCenter.x - (center.x - bounds.minX) * scale,
                y: translatedCenter.y - (center.y - bounds.minY) * scale,
                width: bounds.width * scale,
                height: bounds.height * scale
            )
            NSGraphicsContext.current?.imageInterpolation = .low
            interactionSnapshot.draw(in: destination, from: .zero, operation: .copy, fraction: 1)
            return
        }
        guard let image else { return }
        let displayImage = isInverted ? (invertedImage ?? image) : image
        let usesFastInteractionPreview = isWheelZooming || isPanning
        let drawnImage: NSImage
        if usesFastInteractionPreview {
            drawnImage = wheelPreview(for: displayImage, inverted: isInverted)
        } else if usesMojaveRenderingPath {
            drawnImage = settledPreview(for: displayImage, inverted: isInverted)
        } else {
            drawnImage = displayImage
        }
        let rect = imageContentRect()
        NSGraphicsContext.current?.imageInterpolation = usesFastInteractionPreview ? .low : .high
        NSGraphicsContext.current?.saveGraphicsState()
        imageTransform(for: rect).concat()
        drawnImage.draw(in: rect)
        NSColor.red.setStroke()
        for (index, crop) in crops.enumerated() {
            let r = viewRect(from: crop.rect, imageRect: rect)
            let path = rotatedRectPath(rect: r, angle: crop.angle)
            path.lineWidth = index == selectedIndex ? 0.9 : 0.6
            path.stroke()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
        if isMagnifierEnabled, let magnifierPoint, let activeIndex, crops.indices.contains(activeIndex) {
            drawMagnifier(sourcePoint: magnifierPoint, imageRect: rect, displayImage: displayImage, activeCrop: crops[activeIndex])
        }
    }

    private func wheelPreview(for image: NSImage, inverted: Bool) -> NSImage {
        if inverted, let wheelInvertedPreviewImage {
            return wheelInvertedPreviewImage
        }
        if !inverted, let wheelPreviewImage {
            return wheelPreviewImage
        }
        let preview = Self.downsampledPreview(
            from: image,
            maxPixelSize: usesMojaveRenderingPath ? 1200 : 1800
        ) ?? image
        if inverted {
            wheelInvertedPreviewImage = preview
        } else {
            wheelPreviewImage = preview
        }
        return preview
    }

    private func settledPreview(for image: NSImage, inverted: Bool) -> NSImage {
        if inverted, let displayInvertedPreviewImage {
            return displayInvertedPreviewImage
        }
        if !inverted, let displayPreviewImage {
            return displayPreviewImage
        }
        let preview = Self.downsampledPreview(from: image, maxPixelSize: 2800) ?? image
        if inverted {
            displayInvertedPreviewImage = preview
        } else {
            displayPreviewImage = preview
        }
        return preview
    }

    private func beginMojaveInteractionSnapshotIfNeeded() {
        guard usesMojaveRenderingPath,
              interactionSnapshot == nil,
              bounds.width > 1,
              bounds.height > 1 else { return }
        let width = max(1, Int(bounds.width.rounded(.up)))
        let height = max(1, Int(bounds.height.rounded(.up)))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return }
        bitmap.size = bounds.size
        cacheDisplay(in: bounds, to: bitmap)
        let snapshot = NSImage(size: bounds.size)
        snapshot.addRepresentation(bitmap)
        interactionSnapshot = snapshot
        snapshotZoom = zoom
        snapshotPanOffset = panOffset
    }

    private func endMojaveInteractionSnapshot() {
        interactionSnapshot = nil
        snapshotZoom = zoom
        snapshotPanOffset = panOffset
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let rawPoint = convert(event.locationInWindow, from: nil)
        let imgRect = imageContentRect()
        let point = inverseRotated(point: rawPoint, around: CGPoint(x: imgRect.midX, y: imgRect.midY), angle: rotationRadians)
        for index in crops.indices.reversed() {
            let rect = viewRect(from: crops[index].rect, imageRect: imgRect)
            if let handle = hitHandle(point: point, rect: rect, angle: crops[index].angle) {
                selectedIndex = index
                activeIndex = index
                activeHandle = handle
                startCrop = crops[index].rect
                startAngle = crops[index].angle
                startPoint = point
                needsDisplay = true
                return
            }
        }
        selectedIndex = nil
        if image != nil, imageDisplayRect().contains(rawPoint) {
            beginMojaveInteractionSnapshotIfNeeded()
            isPanning = true
            startPoint = rawPoint
            startPanOffset = panOffset
            lastPanDisplayTime = 0
            NSCursor.closedHand.set()
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            let point = convert(event.locationInWindow, from: nil)
            panOffset = CGPoint(
                x: startPanOffset.x + point.x - startPoint.x,
                y: startPanOffset.y + point.y - startPoint.y
            )
            let frameInterval = usesMojaveRenderingPath ? 1.0 / 40.0 : 1.0 / 60.0
            if event.timestamp - lastPanDisplayTime >= frameInterval {
                lastPanDisplayTime = event.timestamp
                needsDisplay = true
            }
            return
        }
        guard let activeIndex, crops.indices.contains(activeIndex), let activeHandle else { return }
        let rawPoint = convert(event.locationInWindow, from: nil)
        let imgRect = imageContentRect()
        let point = inverseRotated(point: rawPoint, around: CGPoint(x: imgRect.midX, y: imgRect.midY), angle: rotationRadians)
        let dx = (point.x - startPoint.x) / max(1, imgRect.width)
        let dy = (point.y - startPoint.y) / max(1, imgRect.height)
        let oldDirty = cropDirtyRect(crops[activeIndex], imageRect: imgRect).union(lastMagnifierFrame)
        isUpdatingCropInteractively = true
        crops[activeIndex].rect = activeHandle.adjust(rect: startCrop, dx: dx, dy: dy).normalized
        isUpdatingCropInteractively = false
        var newLens = CGRect.null
        if isMagnifierEnabled, event.timestamp - lastMagnifierUpdateTime > 0.04 {
            magnifierPoint = point
            lastMagnifierUpdateTime = event.timestamp
            newLens = magnifierFrame(for: point)
            lastMagnifierFrame = newLens
        } else if !isMagnifierEnabled {
            magnifierPoint = nil
            lastMagnifierFrame = .null
        }
        let newDirty = cropDirtyRect(crops[activeIndex], imageRect: imgRect).union(newLens)
        let dirty = oldDirty.union(newDirty).insetBy(dx: -8, dy: -8)
        pendingCropDirtyRect = pendingCropDirtyRect.isNull ? dirty : pendingCropDirtyRect.union(dirty)
        let frameInterval = usesMojaveRenderingPath ? 1.0 / 40.0 : 1.0 / 60.0
        if event.timestamp - lastCropDisplayTime >= frameInterval {
            lastCropDisplayTime = event.timestamp
            setNeedsDisplay(pendingCropDirtyRect)
            pendingCropDirtyRect = .null
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let activeIndex, crops.indices.contains(activeIndex) {
            onCropChanged?(crops[activeIndex].rect)
            onCropsChanged?()
        }
        activeIndex = nil
        activeHandle = nil
        magnifierPoint = nil
        lastMagnifierUpdateTime = 0
        if !lastMagnifierFrame.isNull {
            setNeedsDisplay(lastMagnifierFrame.insetBy(dx: -8, dy: -8))
        }
        lastMagnifierFrame = .null
        isPanning = false
        endMojaveInteractionSnapshot()
        lastPanDisplayTime = 0
        lastCropDisplayTime = 0
        if !pendingCropDirtyRect.isNull {
            setNeedsDisplay(pendingCropDirtyRect)
            pendingCropDirtyRect = .null
        }
        needsDisplay = true
        NSCursor.arrow.set()
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch event.keyCode {
        case 123:
            onNudgeAll?(-0.001, 0)
            return
        case 124:
            onNudgeAll?(0.001, 0)
            return
        case 125:
            onNudgeAll?(0, -0.001)
            return
        case 126:
            onNudgeAll?(0, 0.001)
            return
        default:
            break
        }
        if key == "d" {
            isMagnifierEnabled.toggle()
            onMagnifierToggled?(isMagnifierEnabled)
        } else if key == "a" {
            let rect = currentTemplateRect ?? CGRect(x: 0.05, y: 0.08, width: 0.18, height: 0.72)
            crops.append(LegacyCrop(rect: rect))
            selectedIndex = crops.count - 1
            onCropChanged?(rect)
            onCropsChanged?()
        } else if key == "s" || event.keyCode == 51 {
            deleteSelectedCrop()
        } else {
            super.keyDown(with: event)
        }
    }

    func deleteSelectedCrop() {
        guard let selectedIndex, crops.indices.contains(selectedIndex) else { return }
        crops.remove(at: selectedIndex)
        self.selectedIndex = crops.isEmpty ? nil : (crops.indices.contains(selectedIndex) ? selectedIndex : crops.indices.last)
        onCropsChanged?()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else { return }
        beginMojaveInteractionSnapshotIfNeeded()
        isWheelZooming = true
        let factor = pow(CGFloat(1.0018), delta)
        suppressZoomRedraw = true
        zoom = min(8, max(0.25, zoom * factor))
        suppressZoomRedraw = false
        let frameInterval = usesMojaveRenderingPath ? 1.0 / 40.0 : 1.0 / 60.0
        if event.timestamp - lastWheelZoomDisplayTime >= frameInterval {
            lastWheelZoomDisplayTime = event.timestamp
            needsDisplay = true
        }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(finishWheelZoom), object: nil)
        perform(#selector(finishWheelZoom), with: nil, afterDelay: 0.12)
    }

    @objc private func finishWheelZoom() {
        isWheelZooming = false
        endMojaveInteractionSnapshot()
        lastWheelZoomDisplayTime = 0
        needsDisplay = true
    }

    func adjustZoom(by factor: CGFloat) {
        guard factor > 0 else { return }
        beginMojaveInteractionSnapshotIfNeeded()
        isWheelZooming = true
        suppressZoomRedraw = true
        zoom = min(8, max(0.25, zoom * factor))
        suppressZoomRedraw = false
        needsDisplay = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(finishWheelZoom), object: nil)
        perform(#selector(finishWheelZoom), with: nil, afterDelay: 0.10)
    }

    func resetViewTransform() {
        endMojaveInteractionSnapshot()
        zoom = 1
        panOffset = .zero
        needsDisplay = true
    }

    func rotateSelectedCrop(byDegrees degrees: CGFloat) {
        guard let selectedIndex, crops.indices.contains(selectedIndex) else { return }
        crops[selectedIndex].angle += degrees * .pi / 180
        onCropChanged?(crops[selectedIndex].rect)
        onCropsChanged?()
        needsDisplay = true
    }

    func rotatePreviewImage(byDegrees degrees: Int) {
        previewRotationDegrees = normalizedRotation(previewRotationDegrees + degrees)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFileDropped?(urls)
        return true
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        if let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            return urls
        }
        if let items = sender.draggingPasteboard.propertyList(forType: .fileURL) as? [String],
           !items.isEmpty {
            return items.compactMap { URL(string: $0) }
        }
        if let item = sender.draggingPasteboard.string(forType: .fileURL) {
            return URL(string: item).map { [$0] } ?? []
        }
        return []
    }

    private func imageDisplayRect() -> CGRect {
        guard let image else { return bounds }
        let inset = bounds.insetBy(dx: 24, dy: 24)
        let displayWidth = isQuarterTurn ? image.size.height : image.size.width
        let displayHeight = isQuarterTurn ? image.size.width : image.size.height
        let scale = min(inset.width / max(1, displayWidth), inset.height / max(1, displayHeight)) * zoom
        let size = CGSize(width: displayWidth * scale, height: displayHeight * scale)
        return CGRect(
            x: bounds.midX - size.width / 2 + panOffset.x,
            y: bounds.midY - size.height / 2 + panOffset.y,
            width: size.width,
            height: size.height
        )
    }

    private func imageContentRect() -> CGRect {
        guard image != nil else { return bounds }
        let display = imageDisplayRect()
        let size = isQuarterTurn ? CGSize(width: display.height, height: display.width) : display.size
        return CGRect(
            x: display.midX - size.width / 2,
            y: display.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private var isQuarterTurn: Bool {
        previewRotationDegrees == 90 || previewRotationDegrees == 270
    }

    private var rotationRadians: CGFloat {
        CGFloat(previewRotationDegrees) * .pi / 180
    }

    private func normalizedRotation(_ degrees: Int) -> Int {
        let value = degrees % 360
        return value < 0 ? value + 360 : value
    }

    private func imageTransform(for rect: CGRect) -> NSAffineTransform {
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byRadians: rotationRadians)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        return transform
    }

    private func inverseRotated(point: CGPoint, around center: CGPoint, angle: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(-angle) - dy * sin(-angle),
            y: center.y + dx * sin(-angle) + dy * cos(-angle)
        )
    }

    private func viewRect(from normalized: CGRect, imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalized.minX * imageRect.width,
            y: imageRect.minY + normalized.minY * imageRect.height,
            width: normalized.width * imageRect.width,
            height: normalized.height * imageRect.height
        )
    }

    private func rotatedRectPath(rect: CGRect, angle: CGFloat) -> NSBezierPath {
        var transform = AffineTransform()
        transform.translate(x: rect.midX, y: rect.midY)
        transform.rotate(byRadians: angle)
        transform.translate(x: -rect.midX, y: -rect.midY)
        let path = NSBezierPath(rect: rect)
        path.transform(using: transform)
        return path
    }

    private func hitHandle(point: CGPoint, rect: CGRect, angle: CGFloat) -> CropHandle? {
        let corner: CGFloat = 42
        let edge: CGFloat = 24
        let corners: [(CropHandle, CGRect)] = [
            (.topLeft, CGRect(x: rect.minX - corner / 2, y: rect.minY - corner / 2, width: corner, height: corner)),
            (.topRight, CGRect(x: rect.maxX - corner / 2, y: rect.minY - corner / 2, width: corner, height: corner)),
            (.bottomRight, CGRect(x: rect.maxX - corner / 2, y: rect.maxY - corner / 2, width: corner, height: corner)),
            (.bottomLeft, CGRect(x: rect.minX - corner / 2, y: rect.maxY - corner / 2, width: corner, height: corner))
        ]
        for item in corners where item.1.contains(point) { return item.0 }
        if CGRect(x: rect.minX, y: rect.minY - edge / 2, width: rect.width, height: edge).contains(point) { return .top }
        if CGRect(x: rect.maxX - edge / 2, y: rect.minY, width: edge, height: rect.height).contains(point) { return .right }
        if CGRect(x: rect.minX, y: rect.maxY - edge / 2, width: rect.width, height: edge).contains(point) { return .bottom }
        if CGRect(x: rect.minX - edge / 2, y: rect.minY, width: edge, height: rect.height).contains(point) { return .left }
        if rect.contains(point) { return .move }
        return nil
    }

    private func cropDirtyRect(_ crop: LegacyCrop, imageRect: CGRect) -> CGRect {
        rotatedRectPath(rect: viewRect(from: crop.rect, imageRect: imageRect), angle: crop.angle).bounds.insetBy(dx: -28, dy: -28)
    }

    private func magnifierFrame(for sourcePoint: CGPoint) -> CGRect {
        let lensWidth: CGFloat = min(560, max(420, bounds.width * 0.34))
        let lensHeight: CGFloat = min(360, max(280, bounds.height * 0.34))
        let margin: CGFloat = 14
        let rightX = sourcePoint.x + margin
        let leftX = sourcePoint.x - lensWidth - margin
        let lensOriginX: CGFloat
        if rightX + lensWidth <= bounds.maxX - margin {
            lensOriginX = rightX
        } else if leftX >= bounds.minX + margin {
            lensOriginX = leftX
        } else {
            lensOriginX = min(bounds.maxX - lensWidth - margin, max(bounds.minX + margin, sourcePoint.x - lensWidth * 0.5))
        }
        let lensOriginY = min(bounds.maxY - lensHeight - margin, max(bounds.minY + margin, sourcePoint.y - lensHeight * 0.5))
        return CGRect(x: lensOriginX, y: lensOriginY, width: lensWidth, height: lensHeight)
    }

    private func drawMagnifier(sourcePoint: CGPoint, imageRect: CGRect, displayImage: NSImage, activeCrop: LegacyCrop) {
        guard imageRect.width > 0, imageRect.height > 0 else { return }
        let lensRect = magnifierFrame(for: sourcePoint)

        NSGraphicsContext.current?.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: lensRect, xRadius: 8, yRadius: 8)
        clipPath.addClip()
        NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
        lensRect.fill()

        let crop = activeCrop.rect.normalized
        let edgePaddingX = max(0.004, crop.width * 0.055)
        let edgePaddingY = max(0.004, crop.height * 0.055)
        let expanded = CGRect(
            x: max(0, crop.minX - edgePaddingX),
            y: max(0, crop.minY - edgePaddingY),
            width: min(1, crop.maxX + edgePaddingX) - max(0, crop.minX - edgePaddingX),
            height: min(1, crop.maxY + edgePaddingY) - max(0, crop.minY - edgePaddingY)
        )
        let sourceRect = CGRect(
            x: expanded.minX * displayImage.size.width,
            y: expanded.minY * displayImage.size.height,
            width: max(1, expanded.width * displayImage.size.width),
            height: max(1, expanded.height * displayImage.size.height)
        )
        let fittedLens = aspectFitRect(sourceSize: sourceRect.size, in: lensRect.insetBy(dx: 8, dy: 8))
        NSGraphicsContext.current?.imageInterpolation = .none
        displayImage.draw(in: fittedLens, from: sourceRect, operation: .copy, fraction: 1)

        let cropViewRect = viewRect(from: activeCrop.rect, imageRect: imageRect)
        let scaleX = fittedLens.width / max(1, sourceRect.width)
        let scaleY = fittedLens.height / max(1, sourceRect.height)
        let cropLensRect = CGRect(
            x: fittedLens.minX + ((cropViewRect.minX - imageRect.minX) / imageRect.width * displayImage.size.width - sourceRect.minX) * scaleX,
            y: fittedLens.minY + ((cropViewRect.minY - imageRect.minY) / imageRect.height * displayImage.size.height - sourceRect.minY) * scaleY,
            width: cropViewRect.width / imageRect.width * displayImage.size.width * scaleX,
            height: cropViewRect.height / imageRect.height * displayImage.size.height * scaleY
        )
        NSColor.red.setStroke()
        let cropPath = rotatedRectPath(rect: cropLensRect, angle: activeCrop.angle)
        cropPath.lineWidth = 1.0
        cropPath.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.92).setStroke()
        clipPath.lineWidth = 2
        clipPath.stroke()
        NSColor.black.withAlphaComponent(0.55).setStroke()
        let crosshair = NSBezierPath()
        crosshair.lineWidth = 1
        crosshair.move(to: CGPoint(x: lensRect.midX - 8, y: lensRect.midY))
        crosshair.line(to: CGPoint(x: lensRect.midX + 8, y: lensRect.midY))
        crosshair.move(to: CGPoint(x: lensRect.midX, y: lensRect.midY - 8))
        crosshair.line(to: CGPoint(x: lensRect.midX, y: lensRect.midY + 8))
        crosshair.stroke()
    }

    private func aspectFitRect(sourceSize: CGSize, in destination: CGRect) -> CGRect {
        let scale = min(destination.width / max(1, sourceSize.width), destination.height / max(1, sourceSize.height))
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(x: destination.midX - size.width / 2, y: destination.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func invertedPreview(from image: NSImage?) -> NSImage? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            pixels[index] = 255 &- pixels[index]
            pixels[index + 1] = 255 &- pixels[index + 1]
            pixels[index + 2] = 255 &- pixels[index + 2]
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let output = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return nil
        }
        return NSImage(cgImage: output, size: image.size)
    }

    private static func downsampledPreview(from image: NSImage, maxPixelSize: Int) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        let longestSide = max(sourceWidth, sourceHeight)
        guard longestSide > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(longestSide)
        let width = max(1, Int(round(Double(sourceWidth) * scale)))
        let height = max(1, Int(round(Double(sourceHeight) * scale)))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew,
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let output = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }
        return NSImage(cgImage: output, size: image.size)
    }
}

enum CropHandle {
    case move, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func adjust(rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        var next = rect
        switch self {
        case .move:
            next.origin.x += dx; next.origin.y += dy
        case .topLeft:
            next.origin.x += dx; next.origin.y += dy; next.size.width -= dx; next.size.height -= dy
        case .top:
            next.origin.y += dy; next.size.height -= dy
        case .topRight:
            next.origin.y += dy; next.size.width += dx; next.size.height -= dy
        case .right:
            next.size.width += dx
        case .bottomRight:
            next.size.width += dx; next.size.height += dy
        case .bottom:
            next.size.height += dy
        case .bottomLeft:
            next.origin.x += dx; next.size.width -= dx; next.size.height += dy
        case .left:
            next.origin.x += dx; next.size.width -= dx
        }
        return next
    }
}

enum LegacyToneMapper {
    static func adjustedImage(_ image: CGImage, adjustments: LegacyImageAdjustments) -> CGImage? {
        guard adjustments.isActive else { return image }
        if image.bitsPerComponent == 16, image.bitsPerPixel >= 48 {
            return adjusted16BitRGBImage(image, adjustments: adjustments)
        }
        return adjusted8BitImage(image, adjustments: adjustments)
    }

    static func adjusted8BitImage(_ image: CGImage, adjustments: LegacyImageAdjustments) -> CGImage? {
        guard adjustments.isActive else { return image }
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        let lut = makeLUT8(adjustments: adjustments)
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            pixels[index] = lut[Int(pixels[index])]
            pixels[index + 1] = lut[Int(pixels[index + 1])]
            pixels[index + 2] = lut[Int(pixels[index + 2])]
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func adjusted16BitRGBImage(_ image: CGImage, adjustments: LegacyImageAdjustments) -> CGImage? {
        guard var pixels = compact16BitRGBPixels(from: image) else { return nil }
        let littleEndian = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrder16Little.rawValue != 0
        let lut = makeLUT16(adjustments: adjustments)
        for offset in stride(from: 0, to: pixels.count, by: 2) {
            let value = Int(readUInt16(pixels, offset: offset, littleEndian: littleEndian))
            writeUInt16(lut[value], pixels: &pixels, offset: offset, littleEndian: littleEndian)
        }
        return make16BitRGBImage(width: image.width, height: image.height, pixels: pixels, colorSpace: image.colorSpace, bitmapInfo: image.bitmapInfo)
    }

    private static func makeLUT8(adjustments: LegacyImageAdjustments) -> [UInt8] {
        (0...255).map { value in
            UInt8(clamping: Int(round(mappedValue(Double(value) / 255, adjustments: adjustments) * 255)))
        }
    }

    private static func makeLUT16(adjustments: LegacyImageAdjustments) -> [UInt16] {
        (0...65535).map { value in
            UInt16(clamping: Int(round(mappedValue(Double(value) / 65535, adjustments: adjustments) * 65535)))
        }
    }

    private static func mappedValue(_ input: Double, adjustments: LegacyImageAdjustments) -> Double {
        var x = min(1, max(0, input))
        if adjustments.levelsEnabled {
            let inputBlack = min(max(adjustments.inputBlack, 0), 0.99)
            let inputWhite = max(min(adjustments.inputWhite, 1), inputBlack + 0.001)
            let gamma = max(0.1, min(9.99, adjustments.gamma))
            x = min(1, max(0, (x - inputBlack) / (inputWhite - inputBlack)))
            x = pow(x, 1 / gamma)
            let outputBlack = min(max(adjustments.outputBlack, 0), 0.99)
            let outputWhite = max(min(adjustments.outputWhite, 1), outputBlack + 0.001)
            x = outputBlack + x * (outputWhite - outputBlack)
        }
        if adjustments.curvesEnabled {
            x = curveValue(x, adjustments: adjustments)
        }
        return min(1, max(0, x))
    }

    private static func curveValue(_ x: Double, adjustments: LegacyImageAdjustments) -> Double {
        let xs = [0.0, 0.25, 0.5, 0.75, 1.0]
        var ys = [
            0.0,
            min(1, max(0, 0.25 + adjustments.curveShadows)),
            min(1, max(0, 0.5 + adjustments.curveMidtones)),
            min(1, max(0, 0.75 + adjustments.curveHighlights)),
            1.0
        ]
        for index in 1..<ys.count {
            ys[index] = max(ys[index], ys[index - 1])
        }
        for index in stride(from: ys.count - 2, through: 0, by: -1) {
            ys[index] = min(ys[index], ys[index + 1])
        }
        let slopes = monotoneSlopes(xs: xs, ys: ys)
        let segment = max(0, min(xs.count - 2, xs.lastIndex(where: { $0 <= x }) ?? 0))
        let x0 = xs[segment]
        let x1 = xs[segment + 1]
        let y0 = ys[segment]
        let y1 = ys[segment + 1]
        let h = x1 - x0
        let t = h > 0 ? (x - x0) / h : 0
        let h00 = (2 * t * t * t) - (3 * t * t) + 1
        let h10 = (t * t * t) - (2 * t * t) + t
        let h01 = (-2 * t * t * t) + (3 * t * t)
        let h11 = (t * t * t) - (t * t)
        return h00 * y0 + h10 * h * slopes[segment] + h01 * y1 + h11 * h * slopes[segment + 1]
    }

    private static func monotoneSlopes(xs: [Double], ys: [Double]) -> [Double] {
        let count = xs.count
        var delta = [Double]()
        for index in 0..<(count - 1) {
            delta.append((ys[index + 1] - ys[index]) / (xs[index + 1] - xs[index]))
        }
        var slopes = [Double](repeating: 0, count: count)
        slopes[0] = delta[0]
        slopes[count - 1] = delta[count - 2]
        for index in 1..<(count - 1) {
            slopes[index] = delta[index - 1] * delta[index] <= 0 ? 0 : (delta[index - 1] + delta[index]) / 2
        }
        for index in 0..<(count - 1) where delta[index] != 0 {
            let a = slopes[index] / delta[index]
            let b = slopes[index + 1] / delta[index]
            let sum = a * a + b * b
            if sum > 9 {
                let scale = 3 / sqrt(sum)
                slopes[index] = scale * a * delta[index]
                slopes[index + 1] = scale * b * delta[index]
            }
        }
        return slopes
    }

    private static func compact16BitRGBPixels(from image: CGImage) -> [UInt8]? {
        guard image.bitsPerComponent == 16,
              image.bitsPerPixel >= 48,
              let data = image.dataProvider?.data else {
            return nil
        }
        let width = image.width
        let height = image.height
        let sourceBytesPerRow = image.bytesPerRow
        let compactBytesPerRow = width * 6
        let sourceData = data as Data
        guard sourceBytesPerRow >= compactBytesPerRow,
              sourceData.count >= sourceBytesPerRow * height else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: compactBytesPerRow * height)
        sourceData.withUnsafeBytes { sourceRaw in
            guard let source = sourceRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            pixels.withUnsafeMutableBytes { destinationRaw in
                guard let destination = destinationRaw.bindMemory(to: UInt8.self).baseAddress else { return }
                for y in 0..<height {
                    destination.advanced(by: y * compactBytesPerRow).update(from: source.advanced(by: y * sourceBytesPerRow), count: compactBytesPerRow)
                }
            }
        }
        return pixels
    }

    private static func make16BitRGBImage(width: Int, height: Int, pixels: [UInt8], colorSpace: CGColorSpace?, bitmapInfo sourceBitmapInfo: CGBitmapInfo) -> CGImage? {
        let bytesPerRow = width * 6
        guard pixels.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        let littleEndian = sourceBitmapInfo.rawValue & CGBitmapInfo.byteOrder16Little.rawValue != 0
        let bitmapInfo = CGBitmapInfo(rawValue: (littleEndian ? CGBitmapInfo.byteOrder16Little.rawValue : CGBitmapInfo.byteOrder16Big.rawValue) | CGImageAlphaInfo.none.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48, bytesPerRow: bytesPerRow, space: colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func readUInt16(_ pixels: [UInt8], offset: Int, littleEndian: Bool) -> UInt16 {
        if littleEndian {
            return UInt16(pixels[offset]) | (UInt16(pixels[offset + 1]) << 8)
        }
        return (UInt16(pixels[offset]) << 8) | UInt16(pixels[offset + 1])
    }

    private static func writeUInt16(_ value: UInt16, pixels: inout [UInt8], offset: Int, littleEndian: Bool) {
        if littleEndian {
            pixels[offset] = UInt8(value & 0xff)
            pixels[offset + 1] = UInt8(value >> 8)
        } else {
            pixels[offset] = UInt8(value >> 8)
            pixels[offset + 1] = UInt8(value & 0xff)
        }
    }
}

enum LegacyImageIO {
    static func thumbnail(url: URL, maxPixelSize: Int) -> NSImage? {
        if let decoder = FFFParsingRuntime.decoder(for: url),
           let cgImage = decoder.makePreviewCGImage(maxPixelSize: maxPixelSize) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func grayThumbnail(url: URL, maxPixelSize: Int) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let image = thumbnail(url: url, maxPixelSize: maxPixelSize)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? (bytes, width, height) : nil
    }
}

enum LegacyFrameDetector {
    static func anchorAlignedCrops(url: URL, sourceCrops: [LegacyCrop], anchor: CGRect) -> [LegacyCrop] {
        guard !sourceCrops.isEmpty else { return [] }
        let detected = detectBestTemplateCrops(url: url, template: anchor)
        guard let roughAnchor = detected.map(\.rect).sortedForReadingOrder().first else {
            return sourceCrops
        }
        let detectedAnchor = refinedContentAnchor(url: url, roughAnchor: roughAnchor, template: anchor) ?? roughAnchor
        let dx = detectedAnchor.minX - anchor.minX
        let dy = detectedAnchor.minY - anchor.minY
        return sourceCrops.map { crop in
            LegacyCrop(rect: crop.rect.offsetBy(dx: dx, dy: dy).normalized, angle: crop.angle)
        }
    }

    static func detectBestTemplateCrops(url: URL, template: CGRect) -> [LegacyCrop] {
        detectBestTemplateCropsWithReport(url: url, template: template).crops
    }

    static func detectBestTemplateCropsWithReport(url: URL, template: CGRect) -> LegacyDetectionResult {
        var candidates: [LegacyDetectionCandidate] = []
        if let gray = LegacyImageIO.grayThumbnail(url: url, maxPixelSize: 4096) {
            let luminances = gray.bytes.map { Double($0) / 255.0 }
            let strictRects = detectTwoRowSixFrameRects(luminances: luminances, width: gray.width, height: gray.height)
            if strictRects.count == 12 {
                candidates.append(LegacyDetectionCandidate(
                    title: "2x6固定胶片",
                    detail: "两行六张强约束",
                    rects: strictRects,
                    score: scoreCandidate(strictRects, expectedCount: 12) + 0.18
                ))
            }
        }

        let negativeRects = detectNegativeFilmRects(url: url)
        if negativeRects.count > 1 {
            candidates.append(LegacyDetectionCandidate(
                title: "浅色/黑色片距",
                detail: "负片胶片片距检测",
                rects: negativeRects,
                score: scoreCandidate(negativeRects, expectedCount: 12)
            ))
        }
        let templateCrops = detectTemplatePositionCrops(url: url, template: template)
        if !templateCrops.isEmpty {
            candidates.append(LegacyDetectionCandidate(
                title: "模板定位",
                detail: "按当前红框尺寸定位",
                rects: templateCrops.map(\.rect),
                score: scoreCandidate(templateCrops.map(\.rect), expectedCount: nil) - 0.04
            ))
        }
        let centerCrops = detectFrameCenters(url: url).map { crop(center: $0, size: template.size) }
        if !centerCrops.isEmpty {
            candidates.append(LegacyDetectionCandidate(
                title: "中心投影",
                detail: "旧版中心点估计",
                rects: centerCrops.map(\.rect),
                score: scoreCandidate(centerCrops.map(\.rect), expectedCount: nil) + 0.30
            ))
        }

        let ranked = candidates
            .map { candidate -> LegacyDetectionCandidate in
                let rects = nonOverlappingRects(candidate.rects)
                return LegacyDetectionCandidate(title: candidate.title, detail: candidate.detail, rects: rects, score: max(0, min(1, candidate.score)))
            }
            .filter { !$0.rects.isEmpty }
            .sorted {
                if $0.title == "中心投影", $1.title != "中心投影" { return true }
                if $1.title == "中心投影", $0.title != "中心投影" { return false }
                if abs($0.score - $1.score) > 0.001 { return $0.score > $1.score }
                return $0.rects.count > $1.rects.count
            }
        let crops = ranked.first.map { sameSizeTemplateCrops(from: $0.rects, template: template) } ?? []
        return LegacyDetectionResult(crops: crops, candidates: ranked)
    }

    private static func detectNegativeFilmRects(url: URL) -> [CGRect] {
        guard let gray = LegacyImageIO.grayThumbnail(url: url, maxPixelSize: 4096) else { return [] }
        let width = gray.width
        let height = gray.height
        guard width > 80, height > 120 else { return [] }
        let luminances = gray.bytes.map { Double($0) / 255.0 }

        let horizontalRects = detectHorizontalNegativeFilmRects(luminances: luminances, width: width, height: height)
        if horizontalRects.count >= 4 {
            return horizontalRects.sortedForReadingOrder()
        }

        var columnActivity = [Double](repeating: 0, count: width)
        for x in 0..<width {
            var filmLike = 0
            var black = 0
            for y in 0..<height {
                let value = luminances[y * width + x]
                if value > 0.10 && value < 0.92 { filmLike += 1 }
                if value <= 0.07 { black += 1 }
            }
            columnActivity[x] = max(0, Double(filmLike) / Double(height) - Double(black) / Double(height) * 0.65)
        }

        let smoothedColumns = movingAverage(columnActivity, window: max(3, width / 160))
        let columnThreshold = max(0.08, min(0.34, median(smoothedColumns) + standardDeviation(smoothedColumns) * 0.36))
        let rawColumns = thresholdSegments(
            values: smoothedColumns,
            threshold: columnThreshold,
            minimumSize: max(16, width / 18),
            lessThan: false
        )
        let columns = mergeCloseSegments(rawColumns, maxGap: max(3, width / 90))
            .compactMap { trimActiveColumn($0, activity: smoothedColumns, width: width) }
            .filter { segment in
                let ratio = Double(segment.size) / Double(width)
                return ratio >= 0.06 && ratio <= 0.62
            }

        let usableColumns = columns.isEmpty ? [IntSegment(start: 0, end: width)] : columns
        var rects: [CGRect] = []
        for column in usableColumns {
            rects.append(contentsOf: negativeFilmFrames(in: column, luminances: luminances, width: width, height: height))
        }

        let filtered = mergeNormalizedRects(rects, overlapThreshold: 0.45).filter { rect in
            let aspect = rect.width / max(rect.height, 0.001)
            return rect.area > 0.006
                && rect.width > 0.045
                && rect.height > 0.055
                && aspect >= 0.28
                && aspect <= 2.2
                && !(rect.width > 0.92 && rect.height > 0.92)
        }
        guard filtered.count > 1 else { return [] }
        return filtered.sortedForReadingOrder()
    }

    private static func detectTwoRowSixFrameRects(luminances: [Double], width: Int, height: Int) -> [CGRect] {
        guard width > height, width > 300, height > 160 else { return [] }
        var rowActivity = [Double](repeating: 0, count: height)
        for y in 0..<height {
            var nonWhite = 0
            for x in 0..<width {
                let value = luminances[y * width + x]
                if value > 0.06 && value < 0.985 {
                    nonWhite += 1
                }
            }
            rowActivity[y] = Double(nonWhite) / Double(width)
        }

        let smoothedRows = movingAverage(rowActivity, window: max(3, height / 160))
        let rowThreshold = max(0.05, min(0.35, median(smoothedRows) + standardDeviation(smoothedRows) * 0.20))
        let rows = mergeCloseSegments(
            thresholdSegments(values: smoothedRows, threshold: rowThreshold, minimumSize: max(12, height / 20), lessThan: false),
            maxGap: max(4, height / 110)
        )
            .filter { segment in
                let ratio = Double(segment.size) / Double(height)
                return ratio >= 0.12 && ratio <= 0.55
            }
            .sorted { lhs, rhs in
                let lhsScore = segmentMean(rowActivity, lhs) * Double(lhs.size)
                let rhsScore = segmentMean(rowActivity, rhs) * Double(rhs.size)
                return lhsScore > rhsScore
            }
            .prefix(2)
            .sorted { $0.start < $1.start }
        guard rows.count == 2 else { return [] }

        var rects: [CGRect] = []
        for row in rows {
            let yRange = horizontalFrameYRange(row, luminances: luminances, width: width, height: height)
            let xRange = horizontalFrameContentXRange(yStart: yRange.start, yEnd: yRange.end, luminances: luminances, width: width)
                ?? horizontalFilmXRange(yStart: yRange.start, yEnd: yRange.end, luminances: luminances, width: width)
                ?? IntSegment(start: 0, end: width)
            rects.append(contentsOf: horizontalRegularFrames(
                count: 6,
                xStart: xRange.start,
                xEnd: xRange.end,
                yStart: yRange.start,
                yEnd: yRange.end,
                separators: [],
                luminances: luminances,
                width: width,
                height: height
            ))
        }
        guard rects.count == 12 else { return [] }
        return rects.sortedForReadingOrder()
    }

    private static func detectHorizontalNegativeFilmRects(luminances: [Double], width: Int, height: Int) -> [CGRect] {
        guard width > height, width > 220, height > 120 else { return [] }

        var rowActivity = [Double](repeating: 0, count: height)
        for y in 0..<height {
            var body = 0
            for x in 0..<width {
                let value = luminances[y * width + x]
                if value > 0.08 && value < 0.96 {
                    body += 1
                }
            }
            rowActivity[y] = Double(body) / Double(width)
        }

        let smoothedRows = movingAverage(rowActivity, window: max(3, height / 160))
        let rowThreshold = max(0.05, min(0.35, median(smoothedRows) + standardDeviation(smoothedRows) * 0.25))
        let filmRows = mergeCloseSegments(
            thresholdSegments(values: smoothedRows, threshold: rowThreshold, minimumSize: max(12, height / 18), lessThan: false),
            maxGap: max(4, height / 120)
        ).filter { segment in
            let ratio = Double(segment.size) / Double(height)
            return ratio >= 0.12 && ratio <= 0.55
        }

        guard !filmRows.isEmpty else { return [] }
        var rects: [CGRect] = []
        for row in filmRows {
            rects.append(contentsOf: horizontalFrames(in: row, luminances: luminances, width: width, height: height))
        }
        if filmRows.count == 2, rects.count == 12 {
            return rects.sortedForReadingOrder()
        }

        let filtered = mergeNormalizedRects(rects, overlapThreshold: 0.42).filter { rect in
            let aspect = rect.width / max(rect.height, 0.001)
            return rect.area > 0.006
                && rect.width > 0.055
                && rect.height > 0.10
                && aspect >= 0.32
                && aspect <= 3.8
                && !(rect.width > 0.92 && rect.height > 0.70)
        }
        return keepConsistentNegativeFrames(filtered).sortedForReadingOrder()
    }

    private static func horizontalFrames(in row: IntSegment, luminances: [Double], width: Int, height: Int) -> [CGRect] {
        let yStart = max(0, min(height - 1, row.start))
        let yEnd = max(yStart + 1, min(height, row.end))
        let rowHeight = yEnd - yStart
        guard rowHeight > 20 else { return [] }

        var separatorScore = [Double](repeating: 0, count: width)
        var bodyScore = [Double](repeating: 0, count: width)
        for x in 0..<width {
            var dark = 0
            var light = 0
            var body = 0
            for y in yStart..<yEnd {
                let value = luminances[y * width + x]
                if value <= 0.12 { dark += 1 }
                if value >= 0.94 { light += 1 }
                if value > 0.12 && value < 0.95 { body += 1 }
            }
            let count = Double(rowHeight)
            let darkRatio = Double(dark) / count
            let lightRatio = Double(light) / count
            let bodyRatio = Double(body) / count
            separatorScore[x] = min(1, darkRatio * 1.05 + lightRatio * 0.45 - bodyRatio * 0.16)
            bodyScore[x] = bodyRatio
        }

        let smoothedSeparators = movingAverage(separatorScore, window: max(3, width / 500))
        let separatorThreshold = max(0.46, min(0.68, median(smoothedSeparators) + standardDeviation(smoothedSeparators) * 0.95))
        var separators = thresholdSegments(
            values: smoothedSeparators,
            threshold: separatorThreshold,
            minimumSize: max(2, width / 700),
            lessThan: false
        )

        if separators.count < 3 {
            let darkOnly = movingAverage((0..<width).map { x in
                var dark = 0
                for y in yStart..<yEnd where luminances[y * width + x] <= 0.12 {
                    dark += 1
                }
                return Double(dark) / Double(rowHeight)
            }, window: max(3, width / 520))
            separators = thresholdSegments(
                values: darkOnly,
                threshold: 0.58,
                minimumSize: max(2, width / 760),
                lessThan: false
            )
        }

        separators = mergeCloseSegments(separators, maxGap: max(2, width / 500))
            .filter { separator in
                separator.size <= max(12, width / 14)
            }
            .sorted { $0.start < $1.start }

        let estimatedCount = max(1, Int(round(Double(width) / (Double(max(1, rowHeight)) * 1.55))))
        let yRange = horizontalFrameYRange(IntSegment(start: yStart, end: yEnd), luminances: luminances, width: width, height: height)
        let activeRange = horizontalFrameContentXRange(yStart: yRange.start, yEnd: yRange.end, luminances: luminances, width: width)
            ?? horizontalFilmXRange(yStart: yRange.start, yEnd: yRange.end, luminances: luminances, width: width)
            ?? IntSegment(start: 0, end: width)
        if estimatedCount >= 5 && estimatedCount <= 7 {
            return keepConsistentNegativeFrames(horizontalRegularFrames(
                count: 6,
                xStart: activeRange.start,
                xEnd: activeRange.end,
                yStart: yRange.start,
                yEnd: yRange.end,
                separators: separators,
                luminances: luminances,
                width: width,
                height: height
            ))
        }

        var boundaries: [IntSegment] = []
        if let first = separators.first, first.start > max(8, width / 24) {
            boundaries.append(IntSegment(start: 0, end: 0))
        }
        boundaries.append(contentsOf: separators)
        if let last = separators.last, width - last.end > max(8, width / 24) {
            boundaries.append(IntSegment(start: width, end: width))
        }

        var frames: [CGRect] = []
        for pair in zip(boundaries, boundaries.dropFirst()) {
            let left = pair.0.end
            let right = pair.1.start
            guard right - left >= max(32, width / 18) else { continue }
            let meanBody = segmentMean(bodyScore, IntSegment(start: left, end: right))
            guard meanBody > 0.18 else { continue }
            frames.append(refineNegativeFrameRect(xStart: left, xEnd: right, yStart: yStart, yEnd: yEnd, luminances: luminances, width: width, height: height))
        }

        guard estimatedCount >= 3 && estimatedCount <= 12 else {
            return keepConsistentNegativeFrames(frames)
        }

        let regularFrames = horizontalRegularFrames(
            count: estimatedCount,
            xStart: activeRange.start,
            xEnd: activeRange.end,
            yStart: yRange.start,
            yEnd: yRange.end,
            separators: separators,
            luminances: luminances,
            width: width,
            height: height
        )
        if regularFrames.count > frames.count || (estimatedCount >= 5 && frames.count != estimatedCount) {
            return keepConsistentNegativeFrames(regularFrames)
        }
        return keepConsistentNegativeFrames(frames)
    }

    private static func horizontalRegularFrames(count: Int, xStart: Int, xEnd: Int, yStart: Int, yEnd: Int, separators: [IntSegment], luminances: [Double], width: Int, height: Int) -> [CGRect] {
        let boundedXStart = max(0, min(width - 1, xStart))
        let boundedXEnd = max(boundedXStart + 1, min(width, xEnd))
        let spanWidth = boundedXEnd - boundedXStart
        let step = Double(spanWidth) / Double(count)
        let rowHeight = max(1, yEnd - yStart)
        let medianGap = median(
            separators
                .filter { $0.start > boundedXStart + spanWidth / 80 && $0.end < boundedXEnd - spanWidth / 80 }
                .map { Double($0.size) }
        )
        let slotInsetFromGap = Int(round(max(3, min(step * 0.12, medianGap * 0.78))))
        let slotInsetX = max(5, slotInsetFromGap, Int(round(step * 0.024)))
        let edgeInsetX = max(4, Int(round(Double(slotInsetX) * 0.70)))
        let topInset = max(5, Int(round(Double(rowHeight) * 0.055)))
        let bottomInset = max(4, Int(round(Double(rowHeight) * 0.035)))
        return (0..<count).compactMap { index in
            let slotLeft = boundedXStart + Int(round(Double(index) * step))
            let slotRight = min(boundedXEnd, boundedXStart + Int(round(Double(index + 1) * step)))
            let leftInset = index == 0 ? edgeInsetX : slotInsetX
            let rightInset = index == count - 1 ? edgeInsetX : slotInsetX
            let left = min(slotRight - 1, slotLeft + leftInset)
            let right = max(left + 1, slotRight - rightInset)
            let top = min(yEnd - 1, yStart + topInset)
            let bottom = max(top + 1, yEnd - bottomInset)
            guard right - left >= max(32, width / 18) else { return nil }
            return CGRect(
                x: Double(left) / Double(width),
                y: Double(top) / Double(height),
                width: Double(right - left) / Double(width),
                height: Double(bottom - top) / Double(height)
            ).normalized
        }
    }

    private static func horizontalFrameYRange(_ row: IntSegment, luminances: [Double], width: Int, height: Int) -> IntSegment {
        let start = max(0, min(height - 1, row.start))
        let end = max(start + 1, min(height, row.end))
        let rowHeight = end - start
        guard rowHeight > 24 else { return IntSegment(start: start, end: end) }

        var scores = [Double](repeating: 0, count: rowHeight)
        for localY in 0..<rowHeight {
            let y = start + localY
            var imageLike = 0
            var dark = 0
            var white = 0
            for x in 0..<width {
                let value = luminances[y * width + x]
                if value > 0.12 && value < 0.94 { imageLike += 1 }
                if value <= 0.08 { dark += 1 }
                if value >= 0.985 { white += 1 }
            }
            let total = Double(width)
            let imageRatio = Double(imageLike) / total
            let darkRatio = Double(dark) / total
            let whiteRatio = Double(white) / total
            scores[localY] = imageRatio - darkRatio * 0.34 - whiteRatio * 0.42
        }

        let smoothed = movingAverage(scores, window: max(3, rowHeight / 60))
        let threshold = max(0.035, min(0.22, median(smoothed) + standardDeviation(smoothed) * 0.08))
        let segments = mergeCloseSegments(
            thresholdSegments(values: smoothed, threshold: threshold, minimumSize: max(8, rowHeight / 5), lessThan: false),
            maxGap: max(2, rowHeight / 35)
        )
        guard let strongest = segments.max(by: { segmentMean(smoothed, $0) * Double($0.size) < segmentMean(smoothed, $1) * Double($1.size) }) else {
            let top = min(end - 1, start + max(5, rowHeight / 18))
            let bottom = max(top + 1, end - max(3, rowHeight / 26))
            return IntSegment(start: top, end: bottom)
        }
        let topPad = max(2, rowHeight / 42)
        let bottomPad = max(2, rowHeight / 55)
        let top = min(end - 1, start + strongest.start + topPad)
        let bottom = max(top + 1, start + strongest.end - bottomPad)
        return IntSegment(start: top, end: bottom)
    }

    private static func horizontalFrameContentXRange(yStart: Int, yEnd: Int, luminances: [Double], width: Int) -> IntSegment? {
        let boundedYStart = max(0, yStart)
        let boundedYEnd = max(boundedYStart + 1, yEnd)
        let rowHeight = boundedYEnd - boundedYStart
        var scores = [Double](repeating: 0, count: width)
        for x in 0..<width {
            var imageLike = 0
            var dark = 0
            var white = 0
            for y in boundedYStart..<boundedYEnd {
                let value = luminances[y * width + x]
                if value > 0.13 && value < 0.94 { imageLike += 1 }
                if value <= 0.08 { dark += 1 }
                if value >= 0.985 { white += 1 }
            }
            let total = Double(rowHeight)
            let imageRatio = Double(imageLike) / total
            let darkRatio = Double(dark) / total
            let whiteRatio = Double(white) / total
            scores[x] = imageRatio - darkRatio * 0.48 - whiteRatio * 0.35
        }
        let smoothed = movingAverage(scores, window: max(3, width / 560))
        let threshold = max(0.035, min(0.24, median(smoothed) + standardDeviation(smoothed) * 0.10))
        let segments = mergeCloseSegments(
            thresholdSegments(values: smoothed, threshold: threshold, minimumSize: max(12, width / 80), lessThan: false),
            maxGap: max(4, width / 180)
        ).filter { segment in
            segment.size >= max(24, width / 28)
        }
        guard !segments.isEmpty else { return nil }
        let start = segments.map(\.start).min() ?? 0
        let end = segments.map(\.end).max() ?? width
        guard end - start >= width / 2 else { return nil }
        let inset = max(2, (end - start) / 140)
        return IntSegment(start: min(end - 1, start + inset), end: max(start + 1, end - inset))
    }

    private static func horizontalFilmXRange(yStart: Int, yEnd: Int, luminances: [Double], width: Int) -> IntSegment? {
        let height = max(1, yEnd - yStart)
        var occupancy = [Double](repeating: 0, count: width)
        for x in 0..<width {
            var nonWhite = 0
            for y in yStart..<yEnd {
                let value = luminances[y * width + x]
                if value < 0.985 {
                    nonWhite += 1
                }
            }
            occupancy[x] = Double(nonWhite) / Double(height)
        }
        let smoothed = movingAverage(occupancy, window: max(3, width / 520))
        let threshold = max(0.08, min(0.32, median(smoothed) + standardDeviation(smoothed) * 0.08))
        let segments = mergeCloseSegments(
            thresholdSegments(values: smoothed, threshold: threshold, minimumSize: max(16, width / 60), lessThan: false),
            maxGap: max(4, width / 220)
        ).filter { segment in
            segment.size >= max(24, width / 40)
        }
        guard !segments.isEmpty else { return nil }
        let start = segments.map(\.start).min() ?? 0
        let end = segments.map(\.end).max() ?? width
        guard end - start >= width / 2 else { return nil }
        let inset = max(1, (end - start) / 180)
        return IntSegment(start: min(end - 1, start + inset), end: max(start + 1, end - inset))
    }

    private static func trimActiveColumn(_ segment: IntSegment, activity: [Double], width: Int) -> IntSegment? {
        guard !activity.isEmpty else { return segment }
        var start = max(0, min(width - 1, segment.start))
        var end = max(start + 1, min(width, segment.end))
        let local = Array(activity[start..<end])
        let threshold = max(0.045, median(local) * 0.55)
        let maxInset = max(2, (end - start) / 5)

        while start + 1 < end, start - segment.start < maxInset, activity[start] < threshold {
            start += 1
        }
        while start + 1 < end, segment.end - end < maxInset, activity[end - 1] < threshold {
            end -= 1
        }
        return end - start >= max(12, width / 24) ? IntSegment(start: start, end: end) : nil
    }

    private static func negativeFilmFrames(in column: IntSegment, luminances: [Double], width: Int, height: Int) -> [CGRect] {
        let xStart = max(0, min(width - 1, column.start))
        let xEnd = max(xStart + 1, min(width, column.end))
        let columnWidth = xEnd - xStart
        guard columnWidth > 8 else { return [] }

        var rowActivity = [Double](repeating: 0, count: height)
        var rowLight = [Double](repeating: 0, count: height)
        var rowTexture = [Double](repeating: 0, count: height)

        for y in 0..<height {
            var active = 0
            var light = 0
            var edge = 0.0
            for x in xStart..<xEnd {
                let value = luminances[y * width + x]
                if value > 0.10 && value < 0.94 { active += 1 }
                if value >= 0.48 && value < 0.94 { light += 1 }
                if y > 0 {
                    edge += abs(value - luminances[(y - 1) * width + x])
                }
            }
            rowActivity[y] = Double(active) / Double(columnWidth)
            rowLight[y] = Double(light) / Double(columnWidth)
            rowTexture[y] = edge / Double(columnWidth)
        }

        let activeSmoothed = movingAverage(rowActivity, window: max(3, height / 180))
        let activeThreshold = max(0.10, min(0.38, median(activeSmoothed) + standardDeviation(activeSmoothed) * 0.20))
        let filmRows = mergeCloseSegments(
            thresholdSegments(values: activeSmoothed, threshold: activeThreshold, minimumSize: max(24, height / 18), lessThan: false),
            maxGap: max(6, height / 100)
        )
        guard let strip = filmRows.max(by: { $0.size < $1.size }), strip.size > max(40, height / 6) else { return [] }

        let lightSmoothed = movingAverage(rowLight, window: max(3, height / 220))
        let textureSmoothed = movingAverage(rowTexture, window: max(3, height / 220))
        let maxTexture = max(textureSmoothed.max() ?? 0, 0.001)
        var gapScore = [Double](repeating: 0, count: height)
        for y in strip.start..<strip.end {
            gapScore[y] = lightSmoothed[y] * 0.92 + activeSmoothed[y] * 0.22 - (textureSmoothed[y] / maxTexture) * 0.20
        }

        let stripScores = Array(gapScore[strip.start..<strip.end])
        let gapThreshold = max(0.30, min(0.72, median(stripScores) + standardDeviation(stripScores) * 0.62))
        var gaps = thresholdSegments(
            values: stripScores,
            threshold: gapThreshold,
            minimumSize: max(2, height / 260),
            lessThan: false
        ).map { IntSegment(start: strip.start + $0.start, end: strip.start + $0.end) }

        let maxGapSize = max(6, strip.size / 7)
        gaps = mergeCloseSegments(gaps, maxGap: max(2, height / 260)).filter { gap in
            gap.size <= maxGapSize
        }

        if gaps.count < 2 {
            return framesByRegularLightSpacing(strip: strip, xStart: xStart, xEnd: xEnd, luminances: luminances, width: width, height: height)
        }

        var boundaries: [IntSegment] = [IntSegment(start: strip.start, end: strip.start)]
        boundaries.append(contentsOf: gaps)
        boundaries.append(IntSegment(start: strip.end, end: strip.end))

        var frames: [CGRect] = []
        for pair in zip(boundaries, boundaries.dropFirst()) {
            let top = pair.0.end
            let bottom = pair.1.start
            guard bottom - top >= max(22, strip.size / 14) else { continue }
            frames.append(refineNegativeFrameRect(xStart: xStart, xEnd: xEnd, yStart: top, yEnd: bottom, luminances: luminances, width: width, height: height))
        }

        return keepConsistentNegativeFrames(frames)
    }

    private static func framesByRegularLightSpacing(strip: IntSegment, xStart: Int, xEnd: Int, luminances: [Double], width: Int, height: Int) -> [CGRect] {
        let frameWidth = xEnd - xStart
        guard frameWidth > 0 else { return [] }
        let expectedHeight = Int(Double(frameWidth) * 1.45)
        let estimatedCount = max(1, Int(round(Double(strip.size) / Double(max(1, expectedHeight)))))
        guard estimatedCount > 1 && estimatedCount <= 24 else { return [] }
        let step = Double(strip.size) / Double(estimatedCount)
        var frames: [CGRect] = []
        for index in 0..<estimatedCount {
            let top = strip.start + Int(round(Double(index) * step))
            let bottom = strip.start + Int(round(Double(index + 1) * step))
            guard bottom - top >= max(22, strip.size / 18) else { continue }
            frames.append(refineNegativeFrameRect(xStart: xStart, xEnd: xEnd, yStart: top, yEnd: bottom, luminances: luminances, width: width, height: height))
        }
        return keepConsistentNegativeFrames(frames)
    }

    private static func refineNegativeFrameRect(xStart: Int, xEnd: Int, yStart: Int, yEnd: Int, luminances: [Double], width: Int, height: Int) -> CGRect {
        var left = xStart
        var right = xEnd
        var top = max(0, yStart)
        var bottom = min(height, yEnd)
        let maxXInset = max(1, (right - left) / 8)
        let maxYInset = max(1, (bottom - top) / 12)

        func columnBodyRatio(_ x: Int) -> Double {
            var body = 0
            for y in top..<bottom {
                let value = luminances[y * width + x]
                if value > 0.10 && value < 0.90 { body += 1 }
            }
            return Double(body) / Double(max(1, bottom - top))
        }

        func rowBodyRatio(_ y: Int) -> Double {
            var body = 0
            for x in left..<right {
                let value = luminances[y * width + x]
                if value > 0.10 && value < 0.90 { body += 1 }
            }
            return Double(body) / Double(max(1, right - left))
        }

        while left + 4 < right, left - xStart < maxXInset, columnBodyRatio(left) < 0.18 { left += 1 }
        while left + 4 < right, xEnd - right < maxXInset, columnBodyRatio(right - 1) < 0.18 { right -= 1 }
        while top + 4 < bottom, top - yStart < maxYInset, rowBodyRatio(top) < 0.18 { top += 1 }
        while top + 4 < bottom, yEnd - bottom < maxYInset, rowBodyRatio(bottom - 1) < 0.18 { bottom -= 1 }

        return CGRect(
            x: Double(left) / Double(width),
            y: Double(top) / Double(height),
            width: Double(right - left) / Double(width),
            height: Double(bottom - top) / Double(height)
        ).normalized
    }

    private static func keepConsistentNegativeFrames(_ rects: [CGRect]) -> [CGRect] {
        guard rects.count > 2 else { return rects }
        let areas = rects.map(\.area)
        let medianArea = median(areas)
        guard medianArea > 0 else { return rects }
        return rects.filter { rect in
            let areaRatio = rect.area / medianArea
            return areaRatio >= 0.42 && areaRatio <= 2.35
        }
    }

    private static func scoreCandidate(_ rects: [CGRect], expectedCount: Int?) -> Double {
        let normalized = nonOverlappingRects(rects).map { $0.normalized }
        guard !normalized.isEmpty else { return 0 }
        let countScore: Double
        if let expectedCount {
            countScore = max(0, 0.34 - abs(Double(normalized.count - expectedCount)) * 0.055)
        } else {
            countScore = normalized.count > 1 ? 0.20 : 0.07
        }
        let areas = normalized.map(\.area)
        let medianArea = median(areas)
        let consistency: Double
        if medianArea > 0, normalized.count > 1 {
            let deviations = areas.map { abs($0 - medianArea) / medianArea }
            consistency = max(0, 0.24 - min(0.24, deviations.reduce(0, +) / Double(deviations.count) * 0.20))
        } else {
            consistency = 0.04
        }
        let rowScore = rowAlignmentScore(normalized)
        let coverage = min(0.18, normalized.map(\.area).reduce(0, +) * 0.28)
        let overlapPenalty = rects.count - normalized.count > 0 ? min(0.22, Double(rects.count - normalized.count) * 0.035) : 0
        let tinyPenalty = normalized.contains { $0.width < 0.045 || $0.height < 0.045 } ? 0.12 : 0
        return max(0, min(1, countScore + consistency + rowScore + coverage - overlapPenalty - tinyPenalty))
    }

    private static func rowAlignmentScore(_ rects: [CGRect]) -> Double {
        guard rects.count > 1 else { return 0.04 }
        var rows: [[CGRect]] = []
        let tolerance = CGFloat(max(0.025, min(0.16, median(rects.map { Double($0.height) }) * 0.35)))
        for rect in rects.sorted(by: { $0.midY < $1.midY }) {
            if let index = rows.firstIndex(where: { row in
                let rowMid = row.reduce(CGFloat(0)) { $0 + $1.midY } / CGFloat(max(1, row.count))
                return abs(rect.midY - rowMid) <= tolerance
            }) {
                rows[index].append(rect)
            } else {
                rows.append([rect])
            }
        }
        let twoRowsSix = rows.count == 2 && rows.allSatisfy { $0.count == 6 }
        if twoRowsSix { return 0.22 }
        return min(0.16, Double(rows.filter { $0.count > 1 }.count) * 0.05 + (rows.contains { $0.count >= 4 } ? 0.06 : 0))
    }

    static func detectTemplatePositionCrops(url: URL, template: CGRect) -> [LegacyCrop] {
        guard let gray = LegacyImageIO.grayThumbnail(url: url, maxPixelSize: 4096) else { return [] }
        let bytes = gray.bytes
        let width = gray.width
        let height = gray.height
        guard width > 80, height > 80 else { return [] }

        let brightThreshold: UInt8 = 42
        let rows = projectionSegments(
            count: height,
            minSize: max(18, Int(Double(height) * max(0.045, template.height * 0.45))),
            mergeGap: max(8, height / 70),
            minimumThreshold: 0.030
        ) { y in
            var content = 0
            var edge = 0
            let row = y * width
            for x in 0..<width {
                let value = bytes[row + x]
                if value > brightThreshold && value < 248 { content += 1 }
                if y > 0 {
                    edge += abs(Int(bytes[row + x]) - Int(bytes[(y - 1) * width + x]))
                }
            }
            let contentRatio = Double(content) / Double(width)
            let edgeRatio = Double(edge) / Double(width * 255)
            return contentRatio * 0.95 + edgeRatio * 1.10
        }

        let filteredRows = rows.filter { segment in
            let normalizedHeight = Double(segment.size) / Double(height)
            return normalizedHeight > template.height * 0.35 && normalizedHeight < min(0.68, template.height * 2.35)
        }

        var rects: [CGRect] = []
        for row in filteredRows {
            let columnScores = (0..<width).map { x in
                var content = 0
                var edge = 0
                for y in row.start..<row.end {
                    let index = y * width + x
                    let value = bytes[index]
                    if value > brightThreshold && value < 248 { content += 1 }
                    if x > 0 {
                        edge += abs(Int(bytes[index]) - Int(bytes[y * width + x - 1]))
                    }
                }
                let count = max(1, row.size)
                let contentRatio = Double(content) / Double(count)
                let edgeRatio = Double(edge) / Double(count * 255)
                return contentRatio * 0.95 + edgeRatio * 0.95
            }

            let templatePixels = max(18, Int(Double(width) * template.width))
            let gapColumns = frameColumnsByDarkGaps(scores: columnScores, templatePixels: templatePixels, imageWidth: width)
            let projectionColumns = projectionSegments(
                values: columnScores,
                minSize: max(18, Int(Double(width) * template.width * 0.36)),
                mergeGap: max(5, Int(Double(width) * min(0.018, max(0.006, template.width * 0.16)))),
                minimumThreshold: 0.055
            )
            let columns = gapColumns.count >= projectionColumns.count ? gapColumns : projectionColumns
            let splitColumns = splitSegmentsByExpectedSize(columns, expectedSize: templatePixels)
            let filteredColumns = splitColumns.filter { segment in
                let normalizedWidth = Double(segment.size) / Double(width)
                return normalizedWidth > template.width * 0.28 && normalizedWidth < min(0.55, template.width * 2.65)
            }

            for column in filteredColumns {
                let yBias = min(0.018, max(0.004, template.height * 0.026))
                let center = CGPoint(
                    x: Double(column.start + column.end) / 2 / Double(width),
                    y: min(0.995, Double(row.start + row.end) / 2 / Double(height) + yBias)
                )
                rects.append(templateRect(center: center, size: template.size))
            }
        }

        return mergeNormalizedRects(rects, overlapThreshold: 0.72)
            .sorted {
                if abs($0.minY - $1.minY) > 0.045 { return $0.minY < $1.minY }
                return $0.minX < $1.minX
            }
            .enumerated()
            .map { LegacyCrop(rect: $0.element.normalized) }
    }

    private static func sameSizeTemplateCrops(from rects: [CGRect], template: CGRect) -> [LegacyCrop] {
        let template = template.normalized
        guard !rects.isEmpty else { return [] }
        return rects
            .map { $0.normalized }
            .sorted {
                if abs($0.minY - $1.minY) > 0.045 { return $0.minY < $1.minY }
                return $0.minX < $1.minX
            }
            .enumerated()
            .map { _, rect in
                LegacyCrop(rect: templateRect(center: CGPoint(x: rect.midX, y: rect.midY), size: template.size))
            }
    }

    private static func nonOverlappingCrops(_ crops: [LegacyCrop]) -> [LegacyCrop] {
        var accepted: [LegacyCrop] = []
        for crop in crops.sortedForReadingOrder() {
            let rect = crop.rect.normalized
            let overlapsExisting = accepted.contains { existing in
                intersectionRatio(existing.rect.normalized, rect) > 0.18
            }
            if !overlapsExisting {
                accepted.append(LegacyCrop(rect: rect))
            }
        }
        return accepted
    }

    private static func nonOverlappingRects(_ rects: [CGRect]) -> [CGRect] {
        var accepted: [CGRect] = []
        for rect in rects.map({ $0.normalized }).sortedForReadingOrder() {
            let overlapsExisting = accepted.contains { existing in
                intersectionRatio(existing.normalized, rect) > 0.12
            }
            if !overlapsExisting {
                accepted.append(rect)
            }
        }
        return accepted
    }

    private static func refinedContentAnchor(url: URL, roughAnchor: CGRect, template: CGRect) -> CGRect? {
        guard let gray = LegacyImageIO.grayThumbnail(url: url, maxPixelSize: 4096) else { return nil }
        let bytes = gray.bytes
        let width = gray.width
        let height = gray.height
        let rough = roughAnchor.normalized
        let x0 = min(max(Int(rough.minX * CGFloat(width)), 0), width - 1)
        let y0 = min(max(Int(rough.minY * CGFloat(height)), 0), height - 1)
        let x1 = min(max(Int(rough.maxX * CGFloat(width)), x0 + 1), width)
        let y1 = min(max(Int(rough.maxY * CGFloat(height)), y0 + 1), height)
        let boxWidth = max(1, x1 - x0)
        let boxHeight = max(1, y1 - y0)

        let verticalRange = max(y0, y0 + boxHeight / 8)..<min(y1, y1 - boxHeight / 8)
        let horizontalRange = max(x0, x0 + boxWidth / 8)..<min(x1, x1 - boxWidth / 8)
        let leftLimit = min(x1 - 1, x0 + max(8, Int(Double(boxWidth) * 0.24)))
        let topLimit = min(y1 - 1, y0 + max(8, Int(Double(boxHeight) * 0.24)))

        let refinedX = firstContentColumn(
            bytes: bytes,
            width: width,
            xRange: x0...leftLimit,
            yRange: verticalRange
        ) ?? x0
        let refinedY = firstContentRow(
            bytes: bytes,
            width: width,
            yRange: y0...topLimit,
            xRange: horizontalRange
        ) ?? y0

        let nx = CGFloat(refinedX) / CGFloat(width)
        let ny = CGFloat(refinedY) / CGFloat(height)
        return CGRect(x: nx, y: ny, width: template.normalized.width, height: template.normalized.height).normalized
    }

    private static func firstContentColumn(bytes: [UInt8], width: Int, xRange: ClosedRange<Int>, yRange: Range<Int>) -> Int? {
        var runStart: Int?
        for x in xRange {
            let stats = columnBorderStats(bytes: bytes, width: width, x: x, yRange: yRange)
            let isContent = stats.darkRatio < 0.50 && !(stats.whiteRatio > 0.90 && stats.edgeRatio < 0.018)
            if isContent {
                if runStart == nil { runStart = x }
                if let start = runStart, x - start >= 2 { return start }
            } else {
                runStart = nil
            }
        }
        return nil
    }

    private static func firstContentRow(bytes: [UInt8], width: Int, yRange: ClosedRange<Int>, xRange: Range<Int>) -> Int? {
        var runStart: Int?
        for y in yRange {
            let stats = rowBorderStats(bytes: bytes, width: width, y: y, xRange: xRange)
            let isContent = stats.darkRatio < 0.50 && !(stats.whiteRatio > 0.88 && stats.edgeRatio < 0.018)
            if isContent {
                if runStart == nil { runStart = y }
                if let start = runStart, y - start >= 2 { return start }
            } else {
                runStart = nil
            }
        }
        return nil
    }

    private static func columnBorderStats(bytes: [UInt8], width: Int, x: Int, yRange: Range<Int>) -> (darkRatio: Double, whiteRatio: Double, edgeRatio: Double) {
        var dark = 0
        var white = 0
        var edge = 0
        var previous: UInt8?
        for y in yRange {
            let value = bytes[y * width + x]
            if value <= 42 { dark += 1 }
            if value >= 242 { white += 1 }
            if let previous { edge += abs(Int(value) - Int(previous)) }
            previous = value
        }
        let count = max(1, yRange.count)
        return (Double(dark) / Double(count), Double(white) / Double(count), Double(edge) / Double(max(1, count - 1) * 255))
    }

    private static func rowBorderStats(bytes: [UInt8], width: Int, y: Int, xRange: Range<Int>) -> (darkRatio: Double, whiteRatio: Double, edgeRatio: Double) {
        var dark = 0
        var white = 0
        var edge = 0
        var previous: UInt8?
        let row = y * width
        for x in xRange {
            let value = bytes[row + x]
            if value <= 42 { dark += 1 }
            if value >= 242 { white += 1 }
            if let previous { edge += abs(Int(value) - Int(previous)) }
            previous = value
        }
        let count = max(1, xRange.count)
        return (Double(dark) / Double(count), Double(white) / Double(count), Double(edge) / Double(max(1, count - 1) * 255))
    }

    private static func templateRect(center: CGPoint, size: CGSize) -> CGRect {
        let width = min(max(size.width, 0.01), 0.98)
        let height = min(max(size.height, 0.01), 0.98)
        let x = min(max(center.x - width / 2, 0), 1 - width)
        let y = min(max(center.y - height / 2, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height).normalized
    }

    private static func projectionSegments(count: Int, minSize: Int, mergeGap: Int, minimumThreshold: Double, score: (Int) -> Double) -> [IntSegment] {
        projectionSegments(values: (0..<count).map(score), minSize: minSize, mergeGap: mergeGap, minimumThreshold: minimumThreshold)
    }

    private static func projectionSegments(values raw: [Double], minSize: Int, mergeGap: Int, minimumThreshold: Double) -> [IntSegment] {
        let count = raw.count
        guard count > 0 else { return [] }
        let smoothed = movingAverage(raw, window: max(3, count / 260))
        let sorted = smoothed.sorted()
        let low = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.20))]
        let high = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.86))]
        let threshold = max(minimumThreshold, low + (high - low) * 0.36)
        let initial = mergeCloseSegments(thresholdSegments(values: smoothed, threshold: threshold, minimumSize: minSize, lessThan: false), maxGap: mergeGap)
        return splitOverwideSegments(initial, values: smoothed, idealSize: max(minSize, count / 8), gapThreshold: max(minimumThreshold * 0.75, threshold * 0.64))
    }

    private static func frameColumnsByDarkGaps(scores rawScores: [Double], templatePixels: Int, imageWidth: Int) -> [IntSegment] {
        guard rawScores.count > 8, templatePixels > 8 else { return [] }
        let scores = movingAverage(rawScores, window: max(3, rawScores.count / 360))
        let sorted = scores.sorted()
        let low = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.18))]
        let median = sorted[sorted.count / 2]
        let gapThreshold = min(0.16, max(0.018, low + (median - low) * 0.34))
        let minGap = max(3, min(templatePixels / 14, imageWidth / 500))
        let rawGaps = thresholdSegments(values: scores, threshold: gapThreshold, minimumSize: minGap, lessThan: true)
        let maxGap = max(minGap * 2, templatePixels / 3)
        let gaps = mergeCloseSegments(rawGaps, maxGap: max(2, minGap / 2))
            .filter { gap in
                gap.size <= maxGap || gap.start <= imageWidth / 80 || gap.end >= imageWidth - imageWidth / 80
            }
            .sorted { $0.start < $1.start }
        guard gaps.count >= 2 else { return [] }

        var boundaries: [IntSegment] = []
        if let first = gaps.first, first.start > max(4, templatePixels / 6) {
            boundaries.append(IntSegment(start: 0, end: 0))
        }
        boundaries.append(contentsOf: gaps)
        if let last = gaps.last, imageWidth - last.end > max(4, templatePixels / 6) {
            boundaries.append(IntSegment(start: imageWidth, end: imageWidth))
        }

        var frames: [IntSegment] = []
        for pair in zip(boundaries, boundaries.dropFirst()) {
            let left = pair.0.end
            let right = pair.1.start
            let size = right - left
            guard size >= max(12, templatePixels / 3) else { continue }
            if size > Int(Double(templatePixels) * 1.75) {
                frames.append(contentsOf: splitSegmentsByExpectedSize([IntSegment(start: left, end: right)], expectedSize: templatePixels))
            } else {
                frames.append(IntSegment(start: left, end: right))
            }
        }

        return frames.filter { segment in
            let ratio = Double(segment.size) / Double(templatePixels)
            return ratio >= 0.42 && ratio <= 1.85
        }
    }

    private static func splitOverwideSegments(_ segments: [IntSegment], values: [Double], idealSize: Int, gapThreshold: Double) -> [IntSegment] {
        var result: [IntSegment] = []
        for segment in segments {
            if segment.size <= idealSize * 2 {
                result.append(segment)
                continue
            }
            let inner = thresholdSegments(
                values: Array(values[segment.start..<segment.end]),
                threshold: gapThreshold,
                minimumSize: max(4, idealSize / 12),
                lessThan: true
            )
            var cursor = segment.start
            var didSplit = false
            for gap in inner {
                let gapStart = segment.start + gap.start
                let gapEnd = segment.start + gap.end
                if gapStart - cursor >= max(8, idealSize / 3) {
                    result.append(IntSegment(start: cursor, end: gapStart))
                    didSplit = true
                }
                cursor = gapEnd
            }
            if segment.end - cursor >= max(8, idealSize / 3) {
                result.append(IntSegment(start: cursor, end: segment.end))
                didSplit = true
            }
            if !didSplit { result.append(segment) }
        }
        return result
    }

    private static func splitSegmentsByExpectedSize(_ segments: [IntSegment], expectedSize: Int) -> [IntSegment] {
        guard expectedSize > 0 else { return segments }
        var result: [IntSegment] = []
        for segment in segments {
            let estimatedCount = Int(round(Double(segment.size) / Double(expectedSize)))
            guard estimatedCount >= 2, segment.size > Int(Double(expectedSize) * 1.45) else {
                result.append(segment)
                continue
            }
            let partSize = Double(segment.size) / Double(estimatedCount)
            for part in 0..<estimatedCount {
                let start = segment.start + Int(round(Double(part) * partSize))
                let end = segment.start + Int(round(Double(part + 1) * partSize))
                if end - start >= max(8, expectedSize / 3) {
                    result.append(IntSegment(start: start, end: end))
                }
            }
        }
        return result
    }

    private static func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard values.count > 1, window > 1 else { return values }
        let radius = max(1, window / 2)
        var result = [Double](repeating: 0, count: values.count)
        var sum = 0.0
        var left = 0
        for index in values.indices {
            let right = min(values.count - 1, index + radius)
            while left < max(0, index - radius) {
                sum -= values[left]
                left += 1
            }
            if index == 0 {
                sum = values[0...right].reduce(0, +)
            } else if index + radius < values.count {
                sum += values[index + radius]
            }
            result[index] = sum / Double(right - left + 1)
        }
        return result
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let average = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
        return sqrt(variance)
    }

    private static func segmentMean(_ values: [Double], _ segment: IntSegment) -> Double {
        let start = max(0, min(values.count, segment.start))
        let end = max(start, min(values.count, segment.end))
        guard start < end else { return 0 }
        return values[start..<end].reduce(0, +) / Double(end - start)
    }

    private static func thresholdSegments(values: [Double], threshold: Double, minimumSize: Int, lessThan: Bool) -> [IntSegment] {
        var segments: [IntSegment] = []
        var start: Int?
        for (index, value) in values.enumerated() {
            let active = lessThan ? value < threshold : value > threshold
            if active {
                if start == nil { start = index }
            } else if let s = start {
                if index - s >= minimumSize { segments.append(IntSegment(start: s, end: index)) }
                start = nil
            }
        }
        if let s = start, values.count - s >= minimumSize {
            segments.append(IntSegment(start: s, end: values.count))
        }
        return segments
    }

    private static func mergeCloseSegments(_ segments: [IntSegment], maxGap: Int) -> [IntSegment] {
        guard var current = segments.sorted(by: { $0.start < $1.start }).first else { return [] }
        var result: [IntSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }).dropFirst() {
            if segment.start - current.end <= maxGap {
                current.end = max(current.end, segment.end)
            } else {
                result.append(current)
                current = segment
            }
        }
        result.append(current)
        return result
    }

    private static func mergeNormalizedRects(_ rects: [CGRect], overlapThreshold: CGFloat) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rects.map({ $0.normalized }) {
            if let index = result.firstIndex(where: { intersectionRatio($0, rect) > overlapThreshold }) {
                result[index] = average(result[index], rect).normalized
            } else {
                result.append(rect)
            }
        }
        return result
    }

    private static func intersectionRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let minArea = max(0.0001, min(a.width * a.height, b.width * b.height))
        return intersection.width * intersection.height / minArea
    }

    private static func average(_ a: CGRect, _ b: CGRect) -> CGRect {
        CGRect(
            x: (a.minX + b.minX) / 2,
            y: (a.minY + b.minY) / 2,
            width: (a.width + b.width) / 2,
            height: (a.height + b.height) / 2
        )
    }

    static func detectFrameCenters(url: URL) -> [CGPoint] {
        guard let gray = LegacyImageIO.grayThumbnail(url: url, maxPixelSize: 4096) else { return [] }
        let rows = contentSegments(axisCount: gray.height) { y in
            var count = 0
            let row = y * gray.width
            for x in 0..<gray.width where gray.bytes[row + x] > 42 && gray.bytes[row + x] < 248 { count += 1 }
            return Double(count) / Double(gray.width)
        }.filter { $0.size > max(24, gray.height / 18) && $0.size < max(48, gray.height * 7 / 10) }
        var centers: [CGPoint] = []
        for row in rows {
            let columns = contentSegments(axisCount: gray.width) { x in
                var count = 0
                for y in row.start..<row.end where gray.bytes[y * gray.width + x] > 42 && gray.bytes[y * gray.width + x] < 248 { count += 1 }
                return Double(count) / Double(max(1, row.size))
            }.filter { $0.size > max(24, gray.width / 40) && $0.size < max(48, gray.width * 8 / 10) }
            for column in columns {
                centers.append(CGPoint(x: Double(column.mid) / Double(gray.width), y: Double(row.mid) / Double(gray.height)))
            }
        }
        return centers.sorted {
            abs($0.y - $1.y) > 0.04 ? $0.y < $1.y : $0.x < $1.x
        }
    }

    static func crop(center: CGPoint, size: CGSize) -> LegacyCrop {
        let x = min(max(center.x - size.width / 2, 0), 1 - size.width)
        let y = min(max(center.y - size.height / 2, 0), 1 - size.height)
        return LegacyCrop(rect: CGRect(x: x, y: y, width: size.width, height: size.height).normalized)
    }

    static func tiledCrops(template: CGRect) -> [LegacyCrop] {
        [LegacyCrop(rect: template.normalized)]
    }

    private static func contentSegments(axisCount: Int, value: (Int) -> Double) -> [IntSegment] {
        var segments: [IntSegment] = []
        var start: Int?
        for index in 0..<axisCount {
            let active = value(index) > 0.045
            if active {
                if start == nil { start = index }
            } else if let s = start {
                if index - s > 4 { segments.append(IntSegment(start: s, end: index)) }
                start = nil
            }
        }
        if let s = start, axisCount - s > 4 { segments.append(IntSegment(start: s, end: axisCount)) }
        return merge(segments, gap: max(4, axisCount / 180))
    }

    private static func merge(_ segments: [IntSegment], gap: Int) -> [IntSegment] {
        guard var current = segments.first else { return [] }
        var result: [IntSegment] = []
        for segment in segments.dropFirst() {
            if segment.start - current.end <= gap {
                current.end = segment.end
            } else {
                result.append(current)
                current = segment
            }
        }
        result.append(current)
        return result
    }
}

struct IntSegment {
    var start: Int
    var end: Int
    var size: Int { end - start }
    var mid: Int { (start + end) / 2 }
}

enum LegacyExporter {
    static func export(url: URL, crops: [LegacyCrop], directory: URL, format: LegacyExportFormat, dustEnabled: Bool, dustStrength: Double, rotationDegrees: Int, inverted: Bool, adjustments: LegacyImageAdjustments) -> [URL] {
        if let fffOutputs = exportFFF(url: url, crops: crops, directory: directory, format: format, dustEnabled: dustEnabled, dustStrength: dustStrength, rotationDegrees: rotationDegrees, inverted: inverted, adjustments: adjustments) {
            return fffOutputs
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return [] }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var next = nextIndex(directory: directory, ext: format.rawValue)
        var outputs: [URL] = []
        for crop in crops.sortedForReadingOrder() {
            let rect = pixelCropRect(from: crop, imageWidth: image.width, imageHeight: image.height)
            guard let cropped = image.cropping(to: rect) else { continue }
            let out = directory.appendingPathComponent(String(format: "%02d.%@", next, format.rawValue))
            next += 1
            let rotated = rotatedImage(cropped, degrees: rotationDegrees) ?? cropped
            let adjusted = inverted ? (invertedImage(rotated) ?? rotated) : rotated
            let cleaned = dustEnabled ? (dustCleanedImage(adjusted, strength: dustStrength) ?? adjusted) : adjusted
            let outputImage = LegacyToneMapper.adjustedImage(cleaned, adjustments: adjustments) ?? cleaned
            let ok = format == .tif ? writeTIFF(outputImage, url: out, props: props) : writeJPEG(outputImage, url: out)
            if ok { outputs.append(out) }
        }
        return outputs
    }

    private static func exportFFF(url: URL, crops: [LegacyCrop], directory: URL, format: LegacyExportFormat, dustEnabled: Bool, dustStrength: Double, rotationDegrees: Int, inverted: Bool, adjustments: LegacyImageAdjustments) -> [URL]? {
        guard let decoder = FFFParsingRuntime.decoder(for: url) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var next = nextIndex(directory: directory, ext: format.rawValue)
        var outputs: [URL] = []
        for crop in crops.sortedForReadingOrder() {
            let rect = sourceCropRect(for: crop.angle == 0 ? crop.rect.normalized : rotatedBoundingRect(crop).normalized, imageWidth: decoder.info.width, imageHeight: decoder.info.height)
            guard let cropped = decoder.makeCropCGImage(rect: rect) else { continue }
            let rotated = rotatedImage(cropped, degrees: rotationDegrees) ?? cropped
            let adjusted = inverted ? (invertedImage(rotated) ?? rotated) : rotated
            let cleaned = dustEnabled ? (dustCleanedImage(adjusted, strength: dustStrength) ?? adjusted) : adjusted
            let outputImage = LegacyToneMapper.adjustedImage(cleaned, adjustments: adjustments) ?? cleaned
            let out = directory.appendingPathComponent(String(format: "%02d.%@", next, format.rawValue))
            next += 1
            let ok = format == .tif ? writeTIFF(outputImage, url: out, props: nil) : writeJPEG(outputImage, url: out)
            if ok { outputs.append(out) }
        }
        return outputs
    }

    private static func pixelCropRect(from crop: LegacyCrop, imageWidth: Int, imageHeight: Int) -> CGRect {
        let raw = crop.angle == 0 ? crop.rect.normalized : rotatedBoundingRect(crop).normalized
        let normalized = sourceCropRect(for: raw, imageWidth: imageWidth, imageHeight: imageHeight)
        let imageWidth = CGFloat(imageWidth)
        let imageHeight = CGFloat(imageHeight)
        let x = floor(normalized.minX * imageWidth)
        let y = floor((1 - normalized.maxY) * imageHeight)
        let width = ceil(normalized.width * imageWidth)
        let height = ceil(normalized.height * imageHeight)
        return CGRect(
            x: min(max(x, 0), imageWidth - 1),
            y: min(max(y, 0), imageHeight - 1),
            width: min(max(width, 1), imageWidth - min(max(x, 0), imageWidth - 1)),
            height: min(max(height, 1), imageHeight - min(max(y, 0), imageHeight - 1))
        ).integral
    }

    private static func sourceCropRect(for rect: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        let crop = rect.normalized
        let sourceAspect = CGFloat(imageHeight) / max(CGFloat(imageWidth), 1)
        let cropAspect = crop.height / max(crop.width, 0.0001)

        if sourceAspect > 2.5,
           cropAspect > 2.5,
           crop.width < 0.35,
           crop.height > 0.55 {
            return CGRect(
                x: 1 - crop.maxY,
                y: crop.minX,
                width: crop.height,
                height: crop.width
            ).normalized
        }

        return crop
    }

    private static func rotatedBoundingRect(_ crop: LegacyCrop) -> CGRect {
        let rect = crop.rect.normalized
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ].map { point -> CGPoint in
            let dx = point.x - center.x
            let dy = point.y - center.y
            return CGPoint(
                x: center.x + dx * cos(crop.angle) - dy * sin(crop.angle),
                y: center.y + dx * sin(crop.angle) + dy * cos(crop.angle)
            )
        }
        let minX = corners.map(\.x).min() ?? rect.minX
        let maxX = corners.map(\.x).max() ?? rect.maxX
        let minY = corners.map(\.y).min() ?? rect.minY
        let maxY = corners.map(\.y).max() ?? rect.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func nextIndex(directory: URL, ext: String) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return (files.compactMap { $0.pathExtension.lowercased() == ext ? Int($0.deletingPathExtension().lastPathComponent) : nil }.max() ?? 0) + 1
    }

    private static func rotatedImage(_ image: CGImage, degrees: Int) -> CGImage? {
        let normalized = ((degrees % 360) + 360) % 360
        guard normalized != 0 else { return image }
        if image.bitsPerComponent == 16, image.bitsPerPixel >= 48,
           let rotated = rotated16BitRGBImage(image, degrees: normalized) {
            return rotated
        }
        let outputWidth = normalized == 90 || normalized == 270 ? image.height : image.width
        let outputHeight = normalized == 90 || normalized == 270 ? image.width : image.height
        let bitsPerComponent = image.bitsPerComponent
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let bytesPerRow = outputWidth * bytesPerPixel
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        var bitmapInfo = image.bitmapInfo
        if image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast {
            bitmapInfo = CGBitmapInfo(rawValue: (bitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue) | CGImageAlphaInfo.none.rawValue)
        }
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        switch normalized {
        case 90:
            context.translateBy(x: CGFloat(outputWidth), y: 0)
            context.rotate(by: .pi / 2)
        case 180:
            context.translateBy(x: CGFloat(outputWidth), y: CGFloat(outputHeight))
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: 0, y: CGFloat(outputHeight))
            context.rotate(by: -.pi / 2)
        default:
            break
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func rotated16BitRGBImage(_ image: CGImage, degrees: Int) -> CGImage? {
        guard let sourcePixels = compact16BitRGBPixels(from: image) else { return nil }
        let width = image.width
        let height = image.height
        let outputWidth = degrees == 90 || degrees == 270 ? height : width
        let outputHeight = degrees == 90 || degrees == 270 ? width : height
        let bytesPerPixel = 6
        let sourceRow = width * bytesPerPixel
        let outputRow = outputWidth * bytesPerPixel
        var outputPixels = [UInt8](repeating: 0, count: outputRow * outputHeight)

        sourcePixels.withUnsafeBytes { sourceRaw in
            guard let source = sourceRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            outputPixels.withUnsafeMutableBytes { outputRaw in
                guard let destination = outputRaw.bindMemory(to: UInt8.self).baseAddress else { return }
                for y in 0..<height {
                    for x in 0..<width {
                        let destinationX: Int
                        let destinationY: Int
                        switch degrees {
                        case 90:
                            destinationX = height - 1 - y
                            destinationY = x
                        case 180:
                            destinationX = width - 1 - x
                            destinationY = height - 1 - y
                        case 270:
                            destinationX = y
                            destinationY = width - 1 - x
                        default:
                            destinationX = x
                            destinationY = y
                        }
                        let sourceOffset = y * sourceRow + x * bytesPerPixel
                        let destinationOffset = destinationY * outputRow + destinationX * bytesPerPixel
                        destination.advanced(by: destinationOffset).update(from: source.advanced(by: sourceOffset), count: bytesPerPixel)
                    }
                }
            }
        }
        return make16BitRGBImage(width: outputWidth, height: outputHeight, pixels: outputPixels, colorSpace: image.colorSpace, bitmapInfo: image.bitmapInfo)
    }

    private static func invertedImage(_ image: CGImage) -> CGImage? {
        if image.bitsPerComponent == 16, image.bitsPerPixel >= 48,
           var pixels = compact16BitRGBPixels(from: image) {
            for index in pixels.indices {
                pixels[index] = 255 &- pixels[index]
            }
            return make16BitRGBImage(width: image.width, height: image.height, pixels: pixels, colorSpace: image.colorSpace, bitmapInfo: image.bitmapInfo)
        }

        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            pixels[index] = 255 &- pixels[index]
            pixels[index + 1] = 255 &- pixels[index + 1]
            pixels[index + 2] = 255 &- pixels[index + 2]
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func dustCleanedImage(_ image: CGImage, strength: Double) -> CGImage? {
        guard strength > 0 else { return image }
        if image.bitsPerComponent == 16, image.bitsPerPixel >= 48 {
            return dustCleaned16BitRGBImage(image, strength: strength)
        }
        return dustCleaned8BitImage(image, strength: strength)
    }

    private static func dustCleaned8BitImage(_ image: CGImage, strength: Double) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 8, height > 8 else { return image }

        let pixelCount = width * height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: pixelCount * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        let params = dustParameters(strength: strength)
        let softBrightFloor = Int(max(118, 156 - max(0, min(100, strength)) * 0.28))
        let softContrastThreshold = Int(max(8, 21 - max(0, min(100, strength)) * 0.20))
        var luma = [UInt8](repeating: 0, count: pixelCount)
        for index in 0..<pixelCount {
            let offset = index * bytesPerPixel
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            luma[index] = UInt8(min(255, (54 * red + 183 * green + 19 * blue) >> 8))
        }
        let integral = integralImage(values: luma.map(UInt32.init), width: width, height: height)
        var candidates = [Bool](repeating: false, count: pixelCount)
        var subtleCandidates = [Bool](repeating: false, count: pixelCount)
        var smoothBackgroundCandidates = [Bool](repeating: false, count: pixelCount)
        var ridgeCandidates = [Bool](repeating: false, count: pixelCount)
        var texturedCurveCandidates = [Bool](repeating: false, count: pixelCount)
        if width > 2, height > 2 {
            for y in 1..<(height - 1) {
                let row = y * width
                for x in 1..<(width - 1) {
                    let index = row + x
                    let value = Int(luma[index])
                    guard value >= softBrightFloor else { continue }
                    let background = localRingAverage(integral: integral, width: width, height: height, x: x, y: y, outerRadius: 5, innerRadius: 1)
                    let contrast = value - Int(background)
                    guard contrast >= softContrastThreshold else { continue }
                    let offset = index * bytesPerPixel
                    let red = Int(pixels[offset])
                    let green = Int(pixels[offset + 1])
                    let blue = Int(pixels[offset + 2])
                    let channelMax = max(red, max(green, blue))
                    let channelMin = min(red, min(green, blue))
                    let isNeutralBright = channelMax - channelMin <= params.chromaLimit8 || channelMin >= 242
                    let texture = localTexture(luma: luma, width: width, height: height, x: x, y: y)
                    if value >= Int(params.brightFloor8), contrast >= params.contrastThreshold8, isNeutralBright {
                        let isHardWhiteDefect = channelMin >= 248 && contrast >= params.contrastThreshold8 + 8
                        let isStrongNeutralDefect = channelMin >= 180
                            && channelMax - channelMin <= params.chromaLimit8
                            && contrast >= params.contrastThreshold8 + 28
                        if texture <= params.textureLimit8
                            || (isHardWhiteDefect && texture <= max(params.textureLimit8 + 34, 58))
                            || (isStrongNeutralDefect && texture <= max(params.textureLimit8 + 80, 112)) {
                            candidates[index] = true
                        }
                    }
                    if let lift = localAdditiveRGBLift8(pixels: pixels, width: width, height: height, x: x, y: y),
                       lift.minimum >= softContrastThreshold,
                       lift.spread <= max(10, lift.minimum / 2 + 5) {
                        let isStrongAdditiveWhite = lift.minimum >= softContrastThreshold + 20 && lift.spread <= 8
                        if texture <= max(46, params.textureLimit8 + 14) || (isStrongAdditiveWhite && texture <= 120) {
                            subtleCandidates[index] = true
                        }
                    }
                    let backgroundTexture = localBackgroundTexture(luma: luma, width: width, height: height, x: x, y: y)
                    let wideBackground = localRingAverage(integral: integral, width: width, height: height, x: x, y: y, outerRadius: 9, innerRadius: 3)
                    let wideContrast = value - Int(wideBackground)
                    if backgroundTexture <= 28,
                       wideContrast >= 3,
                       value >= 100 {
                        smoothBackgroundCandidates[index] = true
                    }
                    if x >= 3, y >= 3, x < width - 3, y < height - 3,
                       directionalBrightRidge(luma: luma, width: width, height: height, x: x, y: y) >= 5 {
                        let ridge = directionalBrightRidge(luma: luma, width: width, height: height, x: x, y: y)
                        if backgroundTexture <= 40 {
                            ridgeCandidates[index] = true
                        }
                        if ridge >= 12,
                           let lift = localAdditiveRGBLift8(pixels: pixels, width: width, height: height, x: x, y: y),
                           lift.minimum >= 8,
                           lift.spread <= 15 {
                            texturedCurveCandidates[index] = true
                        }
                    }
                }
            }
        }

        var mask = filteredDustMask(candidates: candidates, width: width, height: height, maxSpotArea: params.maxSpotArea, maxLineLength: params.maxLineLength, slenderLimit: params.slenderLimit)
        let subtleMask = filteredDustMask(candidates: subtleCandidates, width: width, height: height, maxSpotArea: min(params.maxSpotArea, 10), maxLineLength: min(params.maxLineLength, 110), slenderLimit: min(params.slenderLimit, 2))
        for index in mask.indices where subtleMask[index] {
            mask[index] = true
        }
        let smoothMask = filteredDustMask(candidates: bridgedDustCandidates(smoothBackgroundCandidates, width: width, height: height), width: width, height: height, maxSpotArea: 0, maxLineLength: min(params.maxLineLength, 220), slenderLimit: 4, minimumScratchLength: 5, allowSparseCurves: true)
        for index in mask.indices where smoothMask[index] {
            mask[index] = true
        }
        let ridgeMask = filteredDustMask(candidates: bridgedDustCandidates(ridgeCandidates, width: width, height: height), width: width, height: height, maxSpotArea: 12, maxLineLength: min(params.maxLineLength, 300), slenderLimit: 5, minimumScratchLength: 4, allowSparseCurves: true)
        for index in mask.indices where ridgeMask[index] {
            mask[index] = true
        }
        let texturedCurveMask = filteredDustMask(candidates: bridgedDustCandidates(texturedCurveCandidates, width: width, height: height), width: width, height: height, maxSpotArea: 0, maxLineLength: min(params.maxLineLength, 260), slenderLimit: 0, minimumScratchLength: 8, allowSparseCurves: true)
        for index in mask.indices where texturedCurveMask[index] {
            mask[index] = true
        }
        if params.shouldDilate {
            mask = dilatedDustMask(mask, width: width, height: height)
        }
        guard mask.contains(true) else { return image }
        repairDustPixels(pixels: &pixels, mask: mask, width: width, height: height, radius: params.repairRadius)

        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return nil
            }
            return context.makeImage()
        }
    }

    private static func dustCleaned16BitRGBImage(_ image: CGImage, strength: Double) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 8, height > 8 else { return image }

        let pixelCount = width * height
        let bytesPerPixel = 6
        guard var pixels = compact16BitRGBPixels(from: image) else { return nil }
        let littleEndian = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrder16Little.rawValue != 0
        let params = dustParameters(strength: strength)
        let clampedStrength = max(0, min(100, strength))
        let softBrightFloor = UInt16(max(118, 156 - clampedStrength * 0.28) * 257)
        let softContrastThreshold = UInt16(max(8, 21 - clampedStrength * 0.20) * 257)

        var luma = [UInt16](repeating: 0, count: pixelCount)
        for index in 0..<pixelCount {
            let offset = index * bytesPerPixel
            let red = Int(readUInt16(pixels, offset: offset, littleEndian: littleEndian))
            let green = Int(readUInt16(pixels, offset: offset + 2, littleEndian: littleEndian))
            let blue = Int(readUInt16(pixels, offset: offset + 4, littleEndian: littleEndian))
            luma[index] = UInt16(min(65535, (54 * red + 183 * green + 19 * blue) >> 8))
        }
        let integral = integralImage(values: luma.map(UInt32.init), width: width, height: height)
        var candidates = [Bool](repeating: false, count: pixelCount)
        var subtleCandidates = [Bool](repeating: false, count: pixelCount)
        var smoothBackgroundCandidates = [Bool](repeating: false, count: pixelCount)
        var ridgeCandidates = [Bool](repeating: false, count: pixelCount)
        var texturedCurveCandidates = [Bool](repeating: false, count: pixelCount)
        if width > 2, height > 2 {
            for y in 1..<(height - 1) {
                let row = y * width
                for x in 1..<(width - 1) {
                    let index = row + x
                    let value = luma[index]
                    guard value >= softBrightFloor else { continue }
                    let background = UInt16(min(65535, localRingAverage(integral: integral, width: width, height: height, x: x, y: y, outerRadius: 5, innerRadius: 1)))
                    guard value > background else { continue }
                    let contrast = value - background
                    guard contrast >= softContrastThreshold else { continue }
                    let offset = index * bytesPerPixel
                    let red = readUInt16(pixels, offset: offset, littleEndian: littleEndian)
                    let green = readUInt16(pixels, offset: offset + 2, littleEndian: littleEndian)
                    let blue = readUInt16(pixels, offset: offset + 4, littleEndian: littleEndian)
                    let channelMax = max(red, max(green, blue))
                    let channelMin = min(red, min(green, blue))
                    let isNeutralBright = channelMax - channelMin <= params.chromaLimit16 || channelMin >= 62194
                    let texture = localTexture(luma: luma, width: width, height: height, x: x, y: y)
                    if value >= params.brightFloor16, contrast >= params.contrastThreshold16, isNeutralBright {
                        let isHardWhiteDefect = channelMin >= 63736 && contrast >= params.contrastThreshold16 + 2056
                        let isStrongNeutralDefect = channelMin >= 46260
                            && channelMax - channelMin <= params.chromaLimit16
                            && contrast >= params.contrastThreshold16 + 7196
                        if texture <= params.textureLimit16
                            || (isHardWhiteDefect && texture <= max(params.textureLimit16 + 8738, 14906))
                            || (isStrongNeutralDefect && texture <= max(params.textureLimit16 + 20560, 28784)) {
                            candidates[index] = true
                        }
                    }
                    if let lift = localAdditiveRGBLift16(pixels: pixels, width: width, height: height, x: x, y: y, littleEndian: littleEndian),
                       lift.minimum >= softContrastThreshold,
                       lift.spread <= max(2570, lift.minimum / 2 + 1285) {
                        let isStrongAdditiveWhite = lift.minimum >= softContrastThreshold + 5140 && lift.spread <= 2056
                        if texture <= max(11822, params.textureLimit16 + 3598) || (isStrongAdditiveWhite && texture <= 30840) {
                            subtleCandidates[index] = true
                        }
                    }
                    let backgroundTexture = localBackgroundTexture(luma: luma, width: width, height: height, x: x, y: y)
                    let wideBackground = UInt16(min(65535, localRingAverage(integral: integral, width: width, height: height, x: x, y: y, outerRadius: 9, innerRadius: 3)))
                    let wideContrast = value > wideBackground ? value - wideBackground : 0
                    if backgroundTexture <= 7196,
                       wideContrast >= 771,
                       value >= 25700 {
                        smoothBackgroundCandidates[index] = true
                    }
                    if x >= 3, y >= 3, x < width - 3, y < height - 3,
                       directionalBrightRidge(luma: luma, width: width, height: height, x: x, y: y) >= 1285 {
                        let ridge = directionalBrightRidge(luma: luma, width: width, height: height, x: x, y: y)
                        if backgroundTexture <= 10280 {
                            ridgeCandidates[index] = true
                        }
                        if ridge >= 3084,
                           let lift = localAdditiveRGBLift16(pixels: pixels, width: width, height: height, x: x, y: y, littleEndian: littleEndian),
                           lift.minimum >= 2056,
                           lift.spread <= 3855 {
                            texturedCurveCandidates[index] = true
                        }
                    }
                }
            }
        }

        var mask = filteredDustMask(candidates: candidates, width: width, height: height, maxSpotArea: params.maxSpotArea, maxLineLength: params.maxLineLength, slenderLimit: params.slenderLimit)
        let subtleMask = filteredDustMask(candidates: subtleCandidates, width: width, height: height, maxSpotArea: min(params.maxSpotArea, 10), maxLineLength: min(params.maxLineLength, 110), slenderLimit: min(params.slenderLimit, 2))
        for index in mask.indices where subtleMask[index] {
            mask[index] = true
        }
        let smoothMask = filteredDustMask(candidates: bridgedDustCandidates(smoothBackgroundCandidates, width: width, height: height), width: width, height: height, maxSpotArea: 0, maxLineLength: min(params.maxLineLength, 220), slenderLimit: 4, minimumScratchLength: 5, allowSparseCurves: true)
        for index in mask.indices where smoothMask[index] {
            mask[index] = true
        }
        let ridgeMask = filteredDustMask(candidates: bridgedDustCandidates(ridgeCandidates, width: width, height: height), width: width, height: height, maxSpotArea: 12, maxLineLength: min(params.maxLineLength, 300), slenderLimit: 5, minimumScratchLength: 4, allowSparseCurves: true)
        for index in mask.indices where ridgeMask[index] {
            mask[index] = true
        }
        let texturedCurveMask = filteredDustMask(candidates: bridgedDustCandidates(texturedCurveCandidates, width: width, height: height), width: width, height: height, maxSpotArea: 0, maxLineLength: min(params.maxLineLength, 260), slenderLimit: 0, minimumScratchLength: 8, allowSparseCurves: true)
        for index in mask.indices where texturedCurveMask[index] {
            mask[index] = true
        }
        if params.shouldDilate {
            mask = dilatedDustMask(mask, width: width, height: height)
        }
        guard mask.contains(true) else { return image }
        repair16BitDustPixels(pixels: &pixels, mask: mask, width: width, height: height, radius: params.repairRadius, littleEndian: littleEndian)

        return make16BitRGBImage(width: width, height: height, pixels: pixels, colorSpace: image.colorSpace, bitmapInfo: image.bitmapInfo)
    }

    private static func dustParameters(strength rawStrength: Double) -> (brightFloor8: UInt8, brightFloor16: UInt16, contrastThreshold8: Int, contrastThreshold16: UInt16, chromaLimit8: Int, chromaLimit16: UInt16, textureLimit8: Int, textureLimit16: UInt16, maxSpotArea: Int, maxLineLength: Int, slenderLimit: Int, repairRadius: Int, shouldDilate: Bool) {
        let strength = max(0, min(100, rawStrength))
        let brightFloor = max(145, 192 - strength * 0.42)
        let contrastThreshold = max(14, 42 - strength * 0.30)
        let chromaLimit = max(18, 34 - strength * 0.12)
        let textureLimit = max(18, 36 - strength * 0.10)
        return (
            UInt8(brightFloor),
            UInt16(brightFloor * 257),
            Int(contrastThreshold),
            UInt16(contrastThreshold * 257),
            Int(chromaLimit),
            UInt16(chromaLimit * 257),
            Int(textureLimit),
            UInt16(textureLimit * 257),
            Int(max(4, 8 + strength * 0.45)),
            Int(max(48, 70 + strength * 3.0)),
            Int(max(2, 2 + strength / 24)),
            strength >= 85 ? 2 : 1,
            strength >= 95
        )
    }

    private static func compact16BitRGBPixels(from image: CGImage) -> [UInt8]? {
        guard image.bitsPerComponent == 16,
              image.bitsPerPixel >= 48,
              let data = image.dataProvider?.data else {
            return nil
        }
        let width = image.width
        let height = image.height
        let sourceBytesPerRow = image.bytesPerRow
        let compactBytesPerRow = width * 6
        let sourceData = data as Data
        guard sourceBytesPerRow >= compactBytesPerRow,
              sourceData.count >= sourceBytesPerRow * height else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: compactBytesPerRow * height)
        sourceData.withUnsafeBytes { sourceRaw in
            guard let source = sourceRaw.bindMemory(to: UInt8.self).baseAddress else { return }
            pixels.withUnsafeMutableBytes { destinationRaw in
                guard let destination = destinationRaw.bindMemory(to: UInt8.self).baseAddress else { return }
                for y in 0..<height {
                    destination.advanced(by: y * compactBytesPerRow).update(from: source.advanced(by: y * sourceBytesPerRow), count: compactBytesPerRow)
                }
            }
        }
        return pixels
    }

    private static func make16BitRGBImage(width: Int, height: Int, pixels: [UInt8], colorSpace: CGColorSpace?, bitmapInfo sourceBitmapInfo: CGBitmapInfo) -> CGImage? {
        let bytesPerRow = width * 6
        guard pixels.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        let littleEndian = sourceBitmapInfo.rawValue & CGBitmapInfo.byteOrder16Little.rawValue != 0
        let bitmapInfo = CGBitmapInfo(rawValue: (littleEndian ? CGBitmapInfo.byteOrder16Little.rawValue : CGBitmapInfo.byteOrder16Big.rawValue) | CGImageAlphaInfo.none.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48, bytesPerRow: bytesPerRow, space: colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func filteredDustMask(candidates: [Bool], width: Int, height: Int, maxSpotArea: Int, maxLineLength: Int, slenderLimit: Int, minimumScratchLength: Int = 1, allowSparseCurves: Bool = false) -> [Bool] {
        var visited = [Bool](repeating: false, count: candidates.count)
        var mask = [Bool](repeating: false, count: candidates.count)
        var queue: [Int] = []
        var component: [Int] = []

        for start in candidates.indices where candidates[start] && !visited[start] {
            queue.removeAll(keepingCapacity: true)
            component.removeAll(keepingCapacity: true)
            queue.append(start)
            visited[start] = true
            var head = 0
            var minX = start % width
            var maxX = minX
            var minY = start / width
            var maxY = minY

            while head < queue.count {
                let index = queue[head]
                head += 1
                component.append(index)
                let x = index % width
                let y = index / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)

                for yy in max(0, y - 1)...min(height - 1, y + 1) {
                    for xx in max(0, x - 1)...min(width - 1, x + 1) {
                        let next = yy * width + xx
                        if candidates[next], !visited[next] {
                            visited[next] = true
                            queue.append(next)
                        }
                    }
                }
            }

            let componentWidth = maxX - minX + 1
            let componentHeight = maxY - minY + 1
            let longest = max(componentWidth, componentHeight)
            let shortest = min(componentWidth, componentHeight)
            let isSmallSpot = component.count <= maxSpotArea
            let linePixelLimit = maxSpotArea * 3 + longest * max(2, slenderLimit + 1)
            let isFineScratch = shortest <= slenderLimit
                && longest >= minimumScratchLength
                && longest <= maxLineLength
                && component.count <= linePixelLimit
            let boxArea = componentWidth * componentHeight
            let isSparseCurve = allowSparseCurves
                && longest >= minimumScratchLength
                && longest <= maxLineLength
                && component.count <= max(12, longest * 5)
                && component.count * 4 <= boxArea
            guard isSmallSpot || isFineScratch || isSparseCurve else { continue }
            for index in component {
                mask[index] = true
            }
        }
        return mask
    }

    private static func integralImage(values: [UInt32], width: Int, height: Int) -> [UInt64] {
        var integral = [UInt64](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var rowSum: UInt64 = 0
            for x in 0..<width {
                rowSum += UInt64(values[y * width + x])
                let index = (y + 1) * (width + 1) + x + 1
                integral[index] = integral[y * (width + 1) + x + 1] + rowSum
            }
        }
        return integral
    }

    private static func localRingAverage(integral: [UInt64], width: Int, height: Int, x: Int, y: Int, outerRadius: Int, innerRadius: Int) -> UInt32 {
        let outerLeft = max(0, x - outerRadius)
        let outerTop = max(0, y - outerRadius)
        let outerRight = min(width, x + outerRadius + 1)
        let outerBottom = min(height, y + outerRadius + 1)
        let innerLeft = max(0, x - innerRadius)
        let innerTop = max(0, y - innerRadius)
        let innerRight = min(width, x + innerRadius + 1)
        let innerBottom = min(height, y + innerRadius + 1)
        let outerSum = rectSum(integral: integral, stride: width + 1, left: outerLeft, top: outerTop, right: outerRight, bottom: outerBottom)
        let innerSum = rectSum(integral: integral, stride: width + 1, left: innerLeft, top: innerTop, right: innerRight, bottom: innerBottom)
        let outerArea = UInt64((outerRight - outerLeft) * (outerBottom - outerTop))
        let innerArea = UInt64((innerRight - innerLeft) * (innerBottom - innerTop))
        return UInt32((outerSum - innerSum) / max(1, outerArea - innerArea))
    }

    private static func localAdditiveRGBLift8(pixels: [UInt8], width: Int, height: Int, x: Int, y: Int) -> (minimum: Int, spread: Int)? {
        var redSum = 0
        var greenSum = 0
        var blueSum = 0
        var count = 0
        for yy in max(0, y - 3)...min(height - 1, y + 3) {
            for xx in max(0, x - 3)...min(width - 1, x + 3) {
                guard abs(xx - x) > 1 || abs(yy - y) > 1 else { continue }
                let offset = (yy * width + xx) * 4
                redSum += Int(pixels[offset])
                greenSum += Int(pixels[offset + 1])
                blueSum += Int(pixels[offset + 2])
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let offset = (y * width + x) * 4
        let lifts = [
            Int(pixels[offset]) - redSum / count,
            Int(pixels[offset + 1]) - greenSum / count,
            Int(pixels[offset + 2]) - blueSum / count
        ]
        guard let minimum = lifts.min(), let maximum = lifts.max(), minimum > 0 else { return nil }
        return (minimum, maximum - minimum)
    }

    private static func localAdditiveRGBLift16(pixels: [UInt8], width: Int, height: Int, x: Int, y: Int, littleEndian: Bool) -> (minimum: UInt16, spread: UInt16)? {
        var redSum = 0
        var greenSum = 0
        var blueSum = 0
        var count = 0
        for yy in max(0, y - 3)...min(height - 1, y + 3) {
            for xx in max(0, x - 3)...min(width - 1, x + 3) {
                guard abs(xx - x) > 1 || abs(yy - y) > 1 else { continue }
                let offset = (yy * width + xx) * 6
                redSum += Int(readUInt16(pixels, offset: offset, littleEndian: littleEndian))
                greenSum += Int(readUInt16(pixels, offset: offset + 2, littleEndian: littleEndian))
                blueSum += Int(readUInt16(pixels, offset: offset + 4, littleEndian: littleEndian))
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let offset = (y * width + x) * 6
        let lifts = [
            Int(readUInt16(pixels, offset: offset, littleEndian: littleEndian)) - redSum / count,
            Int(readUInt16(pixels, offset: offset + 2, littleEndian: littleEndian)) - greenSum / count,
            Int(readUInt16(pixels, offset: offset + 4, littleEndian: littleEndian)) - blueSum / count
        ]
        guard let minimum = lifts.min(), let maximum = lifts.max(), minimum > 0 else { return nil }
        return (UInt16(min(65535, minimum)), UInt16(min(65535, maximum - minimum)))
    }

    private static func localTexture(luma: [UInt8], width: Int, height: Int, x: Int, y: Int) -> Int {
        var low = 255
        var high = 0
        let radius = 2
        for yy in max(0, y - radius)...min(height - 1, y + radius) {
            for xx in max(0, x - radius)...min(width - 1, x + radius) {
                guard xx != x || yy != y else { continue }
                let value = Int(luma[yy * width + xx])
                low = min(low, value)
                high = max(high, value)
            }
        }
        return high - low
    }

    private static func localTexture(luma: [UInt16], width: Int, height: Int, x: Int, y: Int) -> UInt16 {
        var low = 65535
        var high = 0
        let radius = 2
        for yy in max(0, y - radius)...min(height - 1, y + radius) {
            for xx in max(0, x - radius)...min(width - 1, x + radius) {
                guard xx != x || yy != y else { continue }
                let value = Int(luma[yy * width + xx])
                low = min(low, value)
                high = max(high, value)
            }
        }
        return UInt16(min(65535, high - low))
    }

    private static func localBackgroundTexture(luma: [UInt8], width: Int, height: Int, x: Int, y: Int) -> Int {
        var low = 255
        var high = 0
        for yy in max(0, y - 4)...min(height - 1, y + 4) {
            for xx in max(0, x - 4)...min(width - 1, x + 4) {
                guard abs(xx - x) > 2 || abs(yy - y) > 2 else { continue }
                let value = Int(luma[yy * width + xx])
                low = min(low, value)
                high = max(high, value)
            }
        }
        return high - low
    }

    private static func localBackgroundTexture(luma: [UInt16], width: Int, height: Int, x: Int, y: Int) -> UInt16 {
        var low = 65535
        var high = 0
        for yy in max(0, y - 4)...min(height - 1, y + 4) {
            for xx in max(0, x - 4)...min(width - 1, x + 4) {
                guard abs(xx - x) > 2 || abs(yy - y) > 2 else { continue }
                let value = Int(luma[yy * width + xx])
                low = min(low, value)
                high = max(high, value)
            }
        }
        return UInt16(min(65535, high - low))
    }

    private static func directionalBrightRidge(luma: [UInt8], width: Int, height: Int, x: Int, y: Int) -> Int {
        let center = Int(luma[y * width + x])
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        var best = 0
        for (dx, dy) in directions {
            let negative = (Int(luma[(y - dy * 2) * width + x - dx * 2]) + Int(luma[(y - dy * 3) * width + x - dx * 3])) / 2
            let positive = (Int(luma[(y + dy * 2) * width + x + dx * 2]) + Int(luma[(y + dy * 3) * width + x + dx * 3])) / 2
            guard abs(negative - positive) <= 18 else { continue }
            best = max(best, center - max(negative, positive))
        }
        return best
    }

    private static func directionalBrightRidge(luma: [UInt16], width: Int, height: Int, x: Int, y: Int) -> UInt16 {
        let center = Int(luma[y * width + x])
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        var best = 0
        for (dx, dy) in directions {
            let negative = (Int(luma[(y - dy * 2) * width + x - dx * 2]) + Int(luma[(y - dy * 3) * width + x - dx * 3])) / 2
            let positive = (Int(luma[(y + dy * 2) * width + x + dx * 2]) + Int(luma[(y + dy * 3) * width + x + dx * 3])) / 2
            guard abs(negative - positive) <= 4626 else { continue }
            best = max(best, center - max(negative, positive))
        }
        return UInt16(min(65535, max(0, best)))
    }

    private static func bridgedDustCandidates(_ candidates: [Bool], width: Int, height: Int) -> [Bool] {
        var result = candidates
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        guard width > 8, height > 8 else { return result }
        for y in 4..<(height - 4) {
            for x in 4..<(width - 4) {
                let index = y * width + x
                guard !candidates[index] else { continue }
                for (dx, dy) in directions {
                    let hasNegative = (1...3).contains { distance in
                        candidates[(y - dy * distance) * width + x - dx * distance]
                    }
                    let hasPositive = (1...3).contains { distance in
                        candidates[(y + dy * distance) * width + x + dx * distance]
                    }
                    if hasNegative, hasPositive {
                        result[index] = true
                        break
                    }
                }
            }
        }
        return result
    }

    private static func rectSum(integral: [UInt64], stride: Int, left: Int, top: Int, right: Int, bottom: Int) -> UInt64 {
        let bottomRight = integral[bottom * stride + right]
        let topLeft = integral[top * stride + left]
        let topRight = integral[top * stride + right]
        let bottomLeft = integral[bottom * stride + left]
        return bottomRight + topLeft - topRight - bottomLeft
    }

    private static func dilatedDustMask(_ mask: [Bool], width: Int, height: Int) -> [Bool] {
        var result = mask
        for index in mask.indices where mask[index] {
            let x = index % width
            let y = index / width
            for yy in max(0, y - 1)...min(height - 1, y + 1) {
                for xx in max(0, x - 1)...min(width - 1, x + 1) {
                    result[yy * width + xx] = true
                }
            }
        }
        return result
    }

    private static func repairDustPixels(pixels: inout [UInt8], mask: [Bool], width: Int, height: Int, radius: Int) {
        let source = pixels
        let bytesPerPixel = 4
        for index in mask.indices where mask[index] {
            let x = index % width
            let y = index / width
            var redSum = 0
            var greenSum = 0
            var blueSum = 0
            var sampleCount = 0
            for yy in max(0, y - radius)...min(height - 1, y + radius) {
                for xx in max(0, x - radius)...min(width - 1, x + radius) {
                    let sampleIndex = yy * width + xx
                    guard !mask[sampleIndex] else { continue }
                    let offset = sampleIndex * bytesPerPixel
                    redSum += Int(source[offset])
                    greenSum += Int(source[offset + 1])
                    blueSum += Int(source[offset + 2])
                    sampleCount += 1
                }
            }
            guard sampleCount > 0 else { continue }
            let offset = index * bytesPerPixel
            if let directional = directionalRGB8Repair(source: source, mask: mask, width: width, height: height, x: x, y: y, radius: radius + 1) {
                pixels[offset] = directional.0
                pixels[offset + 1] = directional.1
                pixels[offset + 2] = directional.2
            } else {
                pixels[offset] = UInt8(redSum / sampleCount)
                pixels[offset + 1] = UInt8(greenSum / sampleCount)
                pixels[offset + 2] = UInt8(blueSum / sampleCount)
            }
        }
    }

    private static func repair16BitDustPixels(pixels: inout [UInt8], mask: [Bool], width: Int, height: Int, radius: Int, littleEndian: Bool) {
        let source = pixels
        let bytesPerPixel = 6
        for index in mask.indices where mask[index] {
            let x = index % width
            let y = index / width
            var redSum = 0
            var greenSum = 0
            var blueSum = 0
            var sampleCount = 0
            for yy in max(0, y - radius)...min(height - 1, y + radius) {
                for xx in max(0, x - radius)...min(width - 1, x + radius) {
                    let sampleIndex = yy * width + xx
                    guard !mask[sampleIndex] else { continue }
                    let offset = sampleIndex * bytesPerPixel
                    redSum += Int(readUInt16(source, offset: offset, littleEndian: littleEndian))
                    greenSum += Int(readUInt16(source, offset: offset + 2, littleEndian: littleEndian))
                    blueSum += Int(readUInt16(source, offset: offset + 4, littleEndian: littleEndian))
                    sampleCount += 1
                }
            }
            guard sampleCount > 0 else { continue }
            let offset = index * bytesPerPixel
            if let directional = directionalRGB16Repair(source: source, mask: mask, width: width, height: height, x: x, y: y, radius: radius + 1, littleEndian: littleEndian) {
                writeUInt16(directional.0, to: &pixels, offset: offset, littleEndian: littleEndian)
                writeUInt16(directional.1, to: &pixels, offset: offset + 2, littleEndian: littleEndian)
                writeUInt16(directional.2, to: &pixels, offset: offset + 4, littleEndian: littleEndian)
            } else {
                writeUInt16(UInt16(redSum / sampleCount), to: &pixels, offset: offset, littleEndian: littleEndian)
                writeUInt16(UInt16(greenSum / sampleCount), to: &pixels, offset: offset + 2, littleEndian: littleEndian)
                writeUInt16(UInt16(blueSum / sampleCount), to: &pixels, offset: offset + 4, littleEndian: littleEndian)
            }
        }
    }

    private static func directionalRGB8Repair(source: [UInt8], mask: [Bool], width: Int, height: Int, x: Int, y: Int, radius: Int) -> (UInt8, UInt8, UInt8)? {
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        var best: (score: Int, red: Int, green: Int, blue: Int)?
        for direction in directions {
            guard let negative = nearestRGB8Sample(source: source, mask: mask, width: width, height: height, x: x, y: y, dx: -direction.0, dy: -direction.1, radius: radius),
                  let positive = nearestRGB8Sample(source: source, mask: mask, width: width, height: height, x: x, y: y, dx: direction.0, dy: direction.1, radius: radius) else {
                continue
            }
            let score = abs(negative.red - positive.red) + abs(negative.green - positive.green) + abs(negative.blue - positive.blue)
            let candidate = (score: score, red: (negative.red + positive.red) / 2, green: (negative.green + positive.green) / 2, blue: (negative.blue + positive.blue) / 2)
            if best == nil || candidate.score < best!.score {
                best = candidate
            }
        }
        guard let best else { return nil }
        return (UInt8(best.red), UInt8(best.green), UInt8(best.blue))
    }

    private static func nearestRGB8Sample(source: [UInt8], mask: [Bool], width: Int, height: Int, x: Int, y: Int, dx: Int, dy: Int, radius: Int) -> (red: Int, green: Int, blue: Int)? {
        for step in 1...max(1, radius) {
            let xx = x + dx * step
            let yy = y + dy * step
            guard xx >= 0, xx < width, yy >= 0, yy < height else { break }
            let index = yy * width + xx
            guard !mask[index] else { continue }
            let offset = index * 4
            return (Int(source[offset]), Int(source[offset + 1]), Int(source[offset + 2]))
        }
        return nil
    }

    private static func directionalRGB16Repair(source: [UInt8], mask: [Bool], width: Int, height: Int, x: Int, y: Int, radius: Int, littleEndian: Bool) -> (UInt16, UInt16, UInt16)? {
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        var best: (score: Int, red: Int, green: Int, blue: Int)?
        for direction in directions {
            guard let negative = nearestRGB16Sample(source: source, mask: mask, width: width, height: height, x: x, y: y, dx: -direction.0, dy: -direction.1, radius: radius, littleEndian: littleEndian),
                  let positive = nearestRGB16Sample(source: source, mask: mask, width: width, height: height, x: x, y: y, dx: direction.0, dy: direction.1, radius: radius, littleEndian: littleEndian) else {
                continue
            }
            let score = abs(negative.red - positive.red) + abs(negative.green - positive.green) + abs(negative.blue - positive.blue)
            let candidate = (score: score, red: (negative.red + positive.red) / 2, green: (negative.green + positive.green) / 2, blue: (negative.blue + positive.blue) / 2)
            if best == nil || candidate.score < best!.score {
                best = candidate
            }
        }
        guard let best else { return nil }
        return (UInt16(best.red), UInt16(best.green), UInt16(best.blue))
    }

    private static func nearestRGB16Sample(source: [UInt8], mask: [Bool], width: Int, height: Int, x: Int, y: Int, dx: Int, dy: Int, radius: Int, littleEndian: Bool) -> (red: Int, green: Int, blue: Int)? {
        for step in 1...max(1, radius) {
            let xx = x + dx * step
            let yy = y + dy * step
            guard xx >= 0, xx < width, yy >= 0, yy < height else { break }
            let index = yy * width + xx
            guard !mask[index] else { continue }
            let offset = index * 6
            return (
                Int(readUInt16(source, offset: offset, littleEndian: littleEndian)),
                Int(readUInt16(source, offset: offset + 2, littleEndian: littleEndian)),
                Int(readUInt16(source, offset: offset + 4, littleEndian: littleEndian))
            )
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], offset: Int, littleEndian: Bool) -> UInt16 {
        if littleEndian {
            return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func writeUInt16(_ value: UInt16, to bytes: inout [UInt8], offset: Int, littleEndian: Bool) {
        if littleEndian {
            bytes[offset] = UInt8(value & 0xff)
            bytes[offset + 1] = UInt8((value >> 8) & 0xff)
        } else {
            bytes[offset] = UInt8((value >> 8) & 0xff)
            bytes[offset + 1] = UInt8(value & 0xff)
        }
    }

    private static func writeTIFF(_ image: CGImage, url: URL, props: [CFString: Any]?) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else { return false }
        var outProps: [CFString: Any] = [kCGImagePropertyDepth: image.bitsPerComponent]
        if let props {
            for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyTIFFDictionary, kCGImagePropertyExifDictionary] {
                if let value = props[key] { outProps[key] = value }
            }
        }
        CGImageDestinationAddImage(dest, image, outProps as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    private static func writeJPEG(_ image: CGImage, url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}

private extension CGRect {
    var area: Double {
        Double(max(0, width) * max(0, height))
    }

    var normalized: CGRect {
        let width = min(max(size.width, 0.01), 0.98)
        let height = min(max(size.height, 0.01), 0.98)
        let x = min(max(origin.x, 0), 1 - width)
        let y = min(max(origin.y, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private func readingOrderMedian(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

private extension Array where Element == LegacyCrop {
    func sortedForReadingOrder() -> [LegacyCrop] {
        let heights = map { Double($0.rect.height) }
        let rowTolerance = CGFloat(Swift.max(0.025, Swift.min(0.18, readingOrderMedian(heights) * 0.42)))
        var rows: [[LegacyCrop]] = []
        for crop in sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                let rowMid = row.reduce(CGFloat(0)) { $0 + $1.rect.midY } / CGFloat(row.count)
                return abs(crop.rect.midY - rowMid) <= Swift.max(rowTolerance, first.rect.height * 0.28)
            }) {
                rows[index].append(crop)
            } else {
                rows.append([crop])
            }
        }
        return rows
            .sorted { lhs, rhs in
                let leftY = lhs.reduce(CGFloat(0)) { $0 + $1.rect.midY } / CGFloat(Swift.max(1, lhs.count))
                let rightY = rhs.reduce(CGFloat(0)) { $0 + $1.rect.midY } / CGFloat(Swift.max(1, rhs.count))
                return leftY < rightY
            }
            .flatMap { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }
}

private extension Array where Element == CGRect {
    func sortedForReadingOrder() -> [CGRect] {
        let heights = map { Double($0.height) }
        let rowTolerance = CGFloat(Swift.max(0.025, Swift.min(0.18, readingOrderMedian(heights) * 0.42)))
        var rows: [[CGRect]] = []
        for rect in sorted(by: { $0.midY < $1.midY }) {
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                let rowMid = row.reduce(CGFloat(0)) { $0 + $1.midY } / CGFloat(row.count)
                return abs(rect.midY - rowMid) <= Swift.max(rowTolerance, first.height * 0.28)
            }) {
                rows[index].append(rect)
            } else {
                rows.append([rect])
            }
        }
        return rows
            .sorted { lhs, rhs in
                let leftY = lhs.reduce(CGFloat(0)) { $0 + $1.midY } / CGFloat(Swift.max(1, lhs.count))
                let rightY = rhs.reduce(CGFloat(0)) { $0 + $1.midY } / CGFloat(Swift.max(1, rhs.count))
                return leftY < rightY
            }
            .flatMap { $0.sorted { $0.minX < $1.minX } }
    }
}

LegacyLaunchLog.write("process started")
let app = NSApplication.shared
let delegate = LegacyAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
LegacyLaunchLog.write("before app.run")
app.run()
LegacyLaunchLog.write("app.run returned")
