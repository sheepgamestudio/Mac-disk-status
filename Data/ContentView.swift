//  Created by Sheep Game Studio on 16–19 August 2026
//
//
//
//
//
import SwiftUI
import AppKit
import Combine

@main
struct DiskStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var monitor: DiskMonitor!
    var cancellable: AnyCancellable?
    var menu: NSMenu!
    
    private let fontSizeKey = "com.data.statusBarFontSize"
    private let roundValuesKey = "com.data.roundDiskValues"

    var currentFontSize: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: fontSizeKey)
            return saved >= 11 ? CGFloat(saved) : 11
        }
        set {
            let clamped = min(max(newValue, 11), 15)
            UserDefaults.standard.set(Double(clamped), forKey: fontSizeKey)
            updateFont()
            rebuildMenu(disks: monitor.disks)
        }
    }

    var isRounded: Bool {
        get {
            if UserDefaults.standard.object(forKey: roundValuesKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: roundValuesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: roundValuesKey)
            updateStatusBar(disks: monitor.disks)
            rebuildMenu(disks: monitor.disks)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        LoginItemManager.refreshCacheFromSystem()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateFont()

        monitor = DiskMonitor()
        menu = NSMenu()
        statusItem.menu = menu

        cancellable = monitor.$disks.sink { [weak self] disks in
            self?.updateStatusBar(disks: disks)
            self?.rebuildMenu(disks: disks)
        }
    }

    func updateFont() {
        statusItem.button?.font = NSFont.systemFont(ofSize: currentFontSize, weight: .regular)
    }

    func updateStatusBar(disks: [DiskInfo]) {
        if disks.isEmpty {
            statusItem.button?.title = NSLocalizedString("loading", comment: "Loading text")
            return
        }
        
        statusItem.button?.title = disks.map { disk in
            if isRounded {
                return formatCutDecimal(fullString: disk.freeSpace)
            } else {
                return disk.freeSpace
            }
        }.joined(separator: " | ")
    }

    func formatCutDecimal(fullString: String) -> String {
        if let commaIndex = fullString.firstIndex(of: ",") ?? fullString.firstIndex(of: ".") {
            let integerPart = fullString[..<commaIndex]
            let suffix = fullString.contains("GB") ? "GB" : "ГБ"
            return "\(integerPart) \(suffix)"
        }
        return fullString
    }

    func rebuildMenu(disks: [DiskInfo]) {
        menu.removeAllItems()

        // --- Блок 1: Управление размером шрифта ---
        let fontSizeView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
        
        let fontSizeTitle = NSLocalizedString("font_size_label", comment: "Font size label")
        let label = NSTextField(frame: NSRect(x: 12, y: 8, width: 150, height: 20))
        label.stringValue = "\(fontSizeTitle): \(Int(currentFontSize))"
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: 13)
        fontSizeView.addSubview(label)

        let minusButton = NSButton(frame: NSRect(x: 175, y: 6, width: 32, height: 24))
        minusButton.title = "-"
        minusButton.bezelStyle = .rounded
        minusButton.target = self
        minusButton.action = #selector(decreaseFontSize)
        minusButton.isEnabled = currentFontSize > 11
        fontSizeView.addSubview(minusButton)

        let plusButton = NSButton(frame: NSRect(x: 215, y: 6, width: 32, height: 24))
        plusButton.title = "+"
        plusButton.bezelStyle = .rounded
        plusButton.target = self
        plusButton.action = #selector(increaseFontSize)
        plusButton.isEnabled = currentFontSize < 15
        fontSizeView.addSubview(plusButton)

        let fontMenuItem = NSMenuItem()
        fontMenuItem.view = fontSizeView
        menu.addItem(fontMenuItem)
        
        // --- Блок 2: Переключатель «Округлить значение» ---
        let roundTitle = NSLocalizedString("round_values_label", comment: "Round values toggle")
        let roundItem = NSMenuItem(
            title: roundTitle,
            action: #selector(toggleRoundValues),
            keyEquivalent: ""
        )
        roundItem.target = self
        roundItem.state = isRounded ? .on : .off
        
        let attributedRound = NSAttributedString(string: roundTitle, attributes: [
            .foregroundColor: NSColor.controlTextColor
        ])
        roundItem.attributedTitle = attributedRound
        menu.addItem(roundItem)
        
        menu.addItem(NSMenuItem.separator())

        // --- Список дисков с защитой от длинных слов ---
        for disk in disks {
            let format = NSLocalizedString("disk_free_of_total", comment: "Disk format")
            let itemText = String(format: format, disk.name, disk.freeSpace, disk.totalSpace)
            
            let diskView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
            
            let diskTextField = NSTextField(frame: NSRect(x: 12, y: 4, width: 316, height: 20))
            diskTextField.stringValue = itemText
            diskTextField.isEditable = false
            diskTextField.isBordered = false
            diskTextField.drawsBackground = false
            diskTextField.font = NSFont.systemFont(ofSize: 13)
            diskTextField.textColor = NSColor.labelColor
            
            diskTextField.cell?.usesSingleLineMode = true
            diskTextField.cell?.truncatesLastVisibleLine = true
            
            if let cell = diskTextField.cell as? NSTextFieldCell {
                cell.allowsUndo = false
            }
            diskTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            
            diskView.addSubview(diskTextField)
            
            let diskMenuItem = NSMenuItem()
            diskMenuItem.view = diskView
            menu.addItem(diskMenuItem)
        }

        menu.addItem(NSMenuItem.separator())

        // --- Автозапуск ---
        let loginTitle = NSLocalizedString("launch_at_login", comment: "Launch at login")
        let loginItem = NSMenuItem(
            title: loginTitle,
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LoginItemManager.cachedIsEnabled ? .on : .off
        
        let attributedLogin = NSAttributedString(string: loginTitle, attributes: [
            .foregroundColor: NSColor.controlTextColor
        ])
        loginItem.attributedTitle = attributedLogin
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())
        
        // --- Поддержать проект ---
        let supportTitle = NSLocalizedString("Support Project", comment: "Support project button")
        let supportItem = NSMenuItem(
            title: supportTitle,
            action: #selector(supportApp),
            keyEquivalent: "s"
        )
        supportItem.target = self
        let attributedSupport = NSAttributedString(string: supportTitle, attributes: [
            .foregroundColor: NSColor.controlTextColor
        ])
        supportItem.attributedTitle = attributedSupport
        menu.addItem(supportItem)

        menu.addItem(NSMenuItem.separator())

        // --- Выход ---
        let quitTitle = NSLocalizedString("quit", comment: "Quit")
        let quitItem = NSMenuItem(
            title: quitTitle,
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        let attributedQuit = NSAttributedString(string: quitTitle, attributes: [
            .foregroundColor: NSColor.controlTextColor
        ])
        quitItem.attributedTitle = attributedQuit
        menu.addItem(quitItem)
    }

    @objc func decreaseFontSize() {
        if currentFontSize > 11 {
            currentFontSize -= 1
        }
    }

    @objc func increaseFontSize() {
        if currentFontSize < 15 {
            currentFontSize += 1
        }
    }

    @objc func toggleRoundValues(_ sender: NSMenuItem) {
        isRounded.toggle()
        sender.state = isRounded ? .on : .off
    }

    @objc func toggleLoginItem(_ sender: NSMenuItem) {
        let newState = !LoginItemManager.cachedIsEnabled
        LoginItemManager.setEnabled(newState)
        sender.state = newState ? .on : .off
    }

    @objc func supportApp() {
        if let url = URL(string: "https://macdiskstatus.app") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// Менеджер автозапуска
enum LoginItemManager {
    private static let defaultsKey = "com.data.launchAtLoginEnabled"

    private static var appPath: String {
        Bundle.main.bundlePath
    }

    private static var appName: String {
        (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "DATA"
    }

    static var cachedIsEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func refreshCacheFromSystem() {
        let script = """
        tell application "System Events"
            return exists login item "\(appName)"
        end tell
        """
        guard let result = runAppleScript(script) else { return }
        UserDefaults.standard.set(result.booleanValue, forKey: defaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        let script: String
        if enabled {
            script = """
            tell application "System Events"
                if not (exists login item "\(appName)") then
                    make login item at end with properties {path:"\(appPath)", hidden:false}
                end if
            end tell
            """
        } else {
            script = """
            tell application "System Events"
                if exists login item "\(appName)" then
                    delete login item "\(appName)"
                end if
            end tell
            """
        }
        _ = runAppleScript(script)
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error = error {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Ошибка автозапуска"
                alert.informativeText = "\(error)"
                alert.alertStyle = .warning
                alert.runModal()
            }
            return nil
        }
        return result
    }
}

struct DiskInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let freeSpace: String
    let totalSpace: String
}

class DiskMonitor: ObservableObject {
    @Published var disks: [DiskInfo] = []
    private var timer: AnyCancellable?

    init() {
        updateDisks()
        timer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDisks()
            }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDisks()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDisks()
        }
    }
    
    func updateDisks() {
        let fileManager = FileManager.default
        guard let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsInternalKey,
                .volumeIsRemovableKey
            ],
            options: [.skipHiddenVolumes]
        ) else {
            return
        }

        var externalDisks: [DiskInfo] = []
        var macDisk: DiskInfo? = nil

        for url in urls {
            do {
                let values = try url.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey,
                    .volumeIsInternalKey,
                    .volumeIsRemovableKey
                ])
                let name = values.volumeName ?? url.lastPathComponent
                let total = Int64(values.volumeTotalCapacity ?? 0)
                let free = Int64(values.volumeAvailableCapacity ?? 0)
                let isInternal = values.volumeIsInternal ?? false

                guard total > 0 else { continue }

                if name.hasPrefix("com.apple.os.update-") { continue }

                let freeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)

                let disk = DiskInfo(id: url.path, name: name, freeSpace: freeStr, totalSpace: totalStr)

                if isInternal {
                    if macDisk == nil {
                        macDisk = disk
                    }
                } else {
                    externalDisks.append(disk)
                }
            } catch {
                continue
            }
        }

        let sortedExternal = externalDisks.sorted { $0.name < $1.name }

        var combined = sortedExternal
        if let mainHD = macDisk {
            combined.append(mainHD)
        }

        if combined != self.disks {
            self.disks = combined
        }
    }
}
