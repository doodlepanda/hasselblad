import SwiftUI
import AppKit

@main
struct ImgSlicerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    init() {
        if let command = DetectionOverlayCommand.parse(arguments: CommandLine.arguments) {
            command.run()
            Foundation.exit(0)
        }
        if let command = DetectionCountCommand.parse(arguments: CommandLine.arguments) {
            command.run()
            Foundation.exit(0)
        }
        if let command = SingleFileCropCommand.parse(arguments: CommandLine.arguments) {
            command.run()
            Foundation.exit(0)
        }
        if let command = TemplateDetectionCommand.parse(arguments: CommandLine.arguments) {
            command.run()
            Foundation.exit(0)
        }
        if let command = AlgorithmComparisonCommand.parse(arguments: CommandLine.arguments) {
            command.run()
            Foundation.exit(0)
        }
        AppIcon.install()
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入文件...") {
                    store.pickFiles()
                }
                .keyboardShortcut("o")

                Button("开始处理") {
                    store.startProcessing()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@MainActor
enum AppIcon {
    static func image() -> NSImage {
        let bundleCandidates = [
            Bundle.main,
            Bundle(path: Bundle.main.resourceURL?.appendingPathComponent("ImgSlicer_ImgSlicer.bundle").path ?? "")
        ].compactMap { $0 }

        for bundle in bundleCandidates {
            if let url = bundle.url(forResource: "AppIconSource", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
            if let url = bundle.url(forResource: "icon", withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return NSApplication.shared.applicationIconImage
    }

    static func install() {
        NSApplication.shared.applicationIconImage = image()
    }
}
