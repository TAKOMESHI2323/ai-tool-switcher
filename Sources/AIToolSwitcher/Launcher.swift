import AppKit
import ApplicationServices
import CoreImage

struct AITool {
    let title: String
    let symbolName: String
    let bundleIdentifiers: [String]
    let windowKeywords: [String]
    let behavior: ActivationBehavior

    func firstMatchingApplication<Result>(using lookup: (String) -> Result?) -> Result? {
        for bundleIdentifier in bundleIdentifiers {
            if let match = lookup(bundleIdentifier) {
                return match
            }
        }
        return nil
    }
}

enum ActivationBehavior {
    case application
}

enum ToolStatus: String, CaseIterable {
    case idle
    case working
    case completed

    var menuTitle: String {
        switch self {
        case .idle:
            return "確認済みにする（バッジを消す）"
        case .working:
            return "作業中にする（手動）"
        case .completed:
            return "作業終了を知らせる（手動）"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle:
            return "待機中（バッジなし）"
        case .working:
            return "作業中"
        case .completed:
            return "作業終了・未確認"
        }
    }
}

enum ToolStatusBehavior {
    static func statusAfterLauncherClick(_ currentStatus: ToolStatus) -> ToolStatus {
        currentStatus == .completed ? .idle : currentStatus
    }
}

struct StatusMenuSelection {
    let toolTitle: String
    let status: ToolStatus
}

enum AIToolCatalog {
    static let tools: [AITool] = [
        AITool(
            title: "Antigravity",
            symbolName: "sparkles",
            bundleIdentifiers: ["com.google.antigravity"],
            windowKeywords: ["Antigravity"],
            behavior: .application
        ),
        AITool(
            title: "Antigravity IDE",
            symbolName: "hammer",
            bundleIdentifiers: ["com.google.antigravity-ide"],
            windowKeywords: ["Antigravity IDE"],
            behavior: .application
        ),
        AITool(
            title: "ClaudeCode",
            symbolName: "message",
            bundleIdentifiers: ["com.anthropic.claudefordesktop"],
            windowKeywords: ["Claude"],
            behavior: .application
        ),
        AITool(
            title: "Gemini",
            symbolName: "sparkles",
            bundleIdentifiers: ["com.google.GeminiMacOS"],
            windowKeywords: ["Gemini"],
            behavior: .application
        ),
        AITool(
            title: "Grok Bot",
            symbolName: "bolt.horizontal.circle",
            bundleIdentifiers: ["com.anysphere.sand"],
            windowKeywords: ["Grok Bot", "Grok"],
            behavior: .application
        ),
        AITool(
            title: "Codex",
            symbolName: "chevron.left.forwardslash.chevron.right",
            bundleIdentifiers: [
                "com.openai.codex",
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "dev.warp.Warp-Stable",
                "com.warp.Warp"
            ],
            windowKeywords: ["codex", "ChatGPT"],
            behavior: .application
        ),
        AITool(
            title: "Cursor",
            symbolName: "cursorarrow.rays",
            bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
            windowKeywords: ["Cursor"],
            behavior: .application
        )
    ]
}

@MainActor
final class WindowActivator {
    func activate(_ tool: AITool) {
        activateApplication(tool)
    }

    func candidateIdentifiers(for tool: AITool) -> [String] {
        let identifiers = tool.bundleIdentifiers
        guard identifiers.count > 1, let preferred = identifiers.first else {
            return identifiers
        }
        let preferredAvailable = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferred) != nil
            || !NSRunningApplication.runningApplications(withBundleIdentifier: preferred).isEmpty
        return ActivationRouting.candidates(identifiers, preferredAvailable: preferredAvailable)
    }

    private func activateApplication(_ tool: AITool) {
        let identifiers = candidateIdentifiers(for: tool)
        let runningApplications = identifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }

        if let matchingApplication = runningApplications.first(where: { application in
            raiseMatchingWindow(in: application, keywords: tool.windowKeywords)
        }) {
            matchingApplication.activate(options: [.activateAllWindows])
            return
        }

        if let application = runningApplications.first {
            application.activate(options: [.activateAllWindows])
            return
        }

        guard let url = identifiers.lazy.compactMap({
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }).first else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func raiseMatchingWindow(in application: NSRunningApplication, keywords: [String]) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let axApplication = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axApplication,
            kAXWindowsAttribute as CFString,
            &value
        )

        guard result == .success, let windows = value as? [AXUIElement] else {
            return false
        }

        for window in windows {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = (titleValue as? String) ?? ""

            if keywords.contains(where: { title.localizedCaseInsensitiveContains($0) }),
               AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success {
                return true
            }
        }

        return false
    }
}

@MainActor
final class ToolButton: NSButton {
    private static let imageContext = CIContext()

    private var activeIcon: NSImage?
    private var inactiveIcon: NSImage?
    private(set) var isToolRunning = false

    var status: ToolStatus = .idle {
        didSet {
            needsDisplay = true
        }
    }

    func configureIcon(_ icon: NSImage) {
        activeIcon = icon
        inactiveIcon = makeInactiveIcon(from: icon)
        refreshIcon()
    }

    func setToolRunning(_ isRunning: Bool) {
        guard isToolRunning != isRunning else { return }
        isToolRunning = isRunning
        refreshIcon()
    }

    private func refreshIcon() {
        image = isToolRunning ? activeIcon : inactiveIcon
        needsDisplay = true
    }

    private func makeInactiveIcon(from icon: NSImage) -> NSImage {
        var proposedRect = NSRect(origin: .zero, size: icon.size)
        guard let sourceImage = icon.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return fadedCopy(of: icon)
        }

        let inputImage = CIImage(cgImage: sourceImage)
        let outputImage = inputImage.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 0.82
            ]
        )

        guard let grayscaleImage = Self.imageContext.createCGImage(
            outputImage,
            from: outputImage.extent
        ) else {
            return fadedCopy(of: icon)
        }

        let grayscaleIcon = NSImage(cgImage: grayscaleImage, size: icon.size)
        return fadedCopy(of: grayscaleIcon)
    }

    private func fadedCopy(of icon: NSImage) -> NSImage {
        NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 0.42
            )
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard status != .idle else { return }

        let badgeRect = NSRect(
            x: bounds.maxX - 16,
            y: bounds.minY + 2,
            width: 14,
            height: 14
        )

        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let innerRect = badgeRect.insetBy(dx: 1.5, dy: 1.5)
        switch status {
        case .idle:
            break
        case .working:
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: innerRect).fill()
        case .completed:
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: innerRect).fill()

            let checkmark = NSBezierPath()
            checkmark.move(to: NSPoint(x: innerRect.minX + 2.2, y: innerRect.midY))
            checkmark.line(to: NSPoint(x: innerRect.minX + 4.2, y: innerRect.minY + 2.4))
            checkmark.line(to: NSPoint(x: innerRect.maxX - 2.0, y: innerRect.maxY - 2.4))
            checkmark.lineWidth = 1.5
            checkmark.lineCapStyle = .round
            checkmark.lineJoinStyle = .round
            NSColor.white.setStroke()
            checkmark.stroke()
        }
    }
}

@MainActor
final class LauncherPanel: NSPanel {
    private static let orientationKey = "AIToolSwitcher.isVertical"
    private static let statusKeyPrefix = "AIToolSwitcher.status."
    private static let hiddenToolsKey = "AIToolSwitcher.hiddenTools"
    private static let positionKey = "AIToolSwitcher.panelTopLeft"
    private static let orientationButtonWidth: CGFloat = 44
    private static let buttonHeight: CGFloat = 42
    private static let toolButtonWidth: CGFloat = 46

    private let activator = WindowActivator()
    private let tools: [AITool]
    private var isVertical: Bool
    private(set) var toolVisibility: ToolVisibility
    private var savedAnchor: CGPoint?
    private var isApplyingLayout = false
    private let visualEffectView = NSVisualEffectView()
    private let stackView = NSStackView()
    private let orientationButton = NSButton()
    private var toolButtons: [String: ToolButton] = [:]

    init(tools: [AITool]) {
        self.tools = tools
        self.isVertical = UserDefaults.standard.bool(forKey: Self.orientationKey)
        self.toolVisibility = ToolVisibility(
            catalog: tools.map(\.title),
            savedHidden: UserDefaults.standard.stringArray(forKey: Self.hiddenToolsKey) ?? []
        )
        if let position = UserDefaults.standard.string(forKey: Self.positionKey) {
            self.savedAnchor = NSPointFromString(position)
        }
        let initialSize = Self.panelSize(for: tools, isVertical: isVertical)
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        stackView.spacing = 8
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for (index, tool) in tools.enumerated() {
            let button = makeButton(for: tool, tag: index)
            toolButtons[tool.title] = button
            stackView.addArrangedSubview(button)
        }

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(workspaceApplicationStateChanged(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(workspaceApplicationStateChanged(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        orientationButton.target = self
        orientationButton.action = #selector(orientationButtonClicked)
        orientationButton.bezelStyle = .texturedRounded
        orientationButton.controlSize = .regular
        orientationButton.imagePosition = .imageOnly
        orientationButton.toolTip = "パネルを縦型・横型に切り替え"
        orientationButton.setAccessibilityLabel("パネルを縦型・横型に切り替え")
        orientationButton.translatesAutoresizingMaskIntoConstraints = false
        orientationButton.widthAnchor.constraint(equalToConstant: Self.orientationButtonWidth).isActive = true
        orientationButton.heightAnchor.constraint(equalToConstant: Self.buttonHeight).isActive = true
        stackView.addArrangedSubview(orientationButton)

        visualEffectView.addSubview(stackView)
        contentView?.addSubview(visualEffectView)

        if let contentView {
            NSLayoutConstraint.activate([
                visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
                visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                stackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 12),
                stackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -12),
                stackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 12),
                stackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -12)
            ])
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelMoved(_:)), name: NSWindow.didMoveNotification, object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        applyToolVisibility()
        updateRunningStates()
        updateLayout()
    }

    override var canBecomeKey: Bool { true }

    func toggleToolVisibility(_ title: String) {
        guard toolVisibility.toggle(title) else { return }
        UserDefaults.standard.set(toolVisibility.hidden.sorted(), forKey: Self.hiddenToolsKey)
        applyToolVisibility()
        updateLayout()
    }

    func resetPosition() {
        savedAnchor = nil
        UserDefaults.standard.removeObject(forKey: Self.positionKey)
        updateLayout()
    }

    private func applyToolVisibility() {
        for (title, button) in toolButtons {
            button.isHidden = toolVisibility.hidden.contains(title)
        }
    }

    @objc private func panelMoved(_ notification: Notification) {
        guard !isApplyingLayout else { return }
        let anchor = CGPoint(x: frame.minX, y: frame.maxY)
        savedAnchor = anchor
        UserDefaults.standard.set(NSStringFromPoint(anchor), forKey: Self.positionKey)
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        updateLayout()
    }

    private func makeButton(for tool: AITool, tag: Int) -> ToolButton {
        let button = ToolButton(title: "", target: self, action: #selector(toolButtonClicked(_:)))
        let status = loadStatus(for: tool)
        button.tag = tag
        button.bezelStyle = .texturedRounded
        button.controlSize = .regular
        if let icon = applicationIcon(for: tool)
            ?? NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title) {
            button.configureIcon(icon)
        }
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.status = status
        button.toolTip = toolTip(for: tool, status: status, isRunning: false)
        button.setAccessibilityLabel(tool.title)
        button.setAccessibilityValue(status.accessibilityLabel)
        button.menu = makeStatusMenu(for: tool, status: status)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Self.toolButtonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: Self.buttonHeight).isActive = true
        return button
    }

    private func applicationIcon(for tool: AITool) -> NSImage? {
        guard let applicationURL = tool.firstMatchingApplication(
            using: NSWorkspace.shared.urlForApplication(withBundleIdentifier:)
        ) else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: 28, height: 28)
        return icon
    }

    private static func buttonWidth(for tool: AITool) -> CGFloat {
        toolButtonWidth
    }

    private func loadStatus(for tool: AITool) -> ToolStatus {
        let key = Self.statusKeyPrefix + tool.title
        guard let rawValue = UserDefaults.standard.string(forKey: key) else {
            return .idle
        }
        if rawValue == ToolStatus.completed.rawValue {
            return .completed
        }

        // 旧バージョンが保存した作業中状態は、起動時に待機へ戻す。
        UserDefaults.standard.removeObject(forKey: key)
        return .idle
    }

    private func toolTip(for tool: AITool, status: ToolStatus, isRunning: Bool) -> String {
        let applicationState = isRunning ? "起動中" : "未起動"
        return "\(tool.title)を前面に表示\nアプリ: \(applicationState)\n作業: \(status.accessibilityLabel)\n右クリックで作業状態を変更"
    }

    private func makeStatusMenu(for tool: AITool, status: ToolStatus) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let heading = NSMenuItem(title: "\(tool.title)の状態", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())

        for candidate in ToolStatus.allCases {
            let item = NSMenuItem(
                title: candidate.menuTitle,
                action: #selector(statusMenuItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = candidate == status ? .on : .off
            item.representedObject = StatusMenuSelection(toolTitle: tool.title, status: candidate)
            menu.addItem(item)
        }

        return menu
    }

    private func setStatus(_ status: ToolStatus, for tool: AITool) {
        let key = Self.statusKeyPrefix + tool.title
        if status == .completed {
            UserDefaults.standard.set(status.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }

        guard let button = toolButtons[tool.title] else { return }
        button.status = status
        button.toolTip = toolTip(
            for: tool,
            status: status,
            isRunning: button.isToolRunning
        )
        button.setAccessibilityValue(status.accessibilityLabel)
        button.menu = makeStatusMenu(for: tool, status: status)
    }

    private func updateRunningStates() {
        for tool in tools {
            guard let button = toolButtons[tool.title] else { continue }
            let isRunning = isApplicationRunning(for: tool)
            button.setToolRunning(isRunning)
            button.toolTip = toolTip(
                for: tool,
                status: button.status,
                isRunning: isRunning
            )
        }
    }

    private func isApplicationRunning(for tool: AITool) -> Bool {
        activator.candidateIdentifiers(for: tool).contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
    }

    private static func panelSize(for tools: [AITool], isVertical: Bool) -> NSSize {
        let toolWidths = tools.map { buttonWidth(for: $0) }

        if isVertical {
            let contentWidth = max(toolWidths.max() ?? 0, orientationButtonWidth)
            let contentHeight = CGFloat(tools.count + 1) * buttonHeight
                + CGFloat(tools.count * 8)
            return NSSize(width: contentWidth + 24, height: contentHeight + 24)
        }

        let contentWidth = toolWidths.reduce(0, +)
            + orientationButtonWidth
            + CGFloat(tools.count * 8)
        return NSSize(width: contentWidth + 24, height: buttonHeight + 32)
    }

    @objc private func toolButtonClicked(_ sender: NSButton) {
        guard tools.indices.contains(sender.tag) else { return }
        let tool = tools[sender.tag]
        let currentStatus = toolButtons[tool.title]?.status ?? .idle
        let nextStatus = ToolStatusBehavior.statusAfterLauncherClick(currentStatus)
        activator.activate(tool)

        if nextStatus != currentStatus {
            setStatus(nextStatus, for: tool)
        }
    }

    @objc private func workspaceApplicationStateChanged(_ notification: Notification) {
        updateRunningStates()
    }

    @objc private func statusMenuItemClicked(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? StatusMenuSelection,
              let tool = tools.first(where: { $0.title == selection.toolTitle }) else {
            return
        }
        setStatus(selection.status, for: tool)
    }

    @objc private func orientationButtonClicked() {
        isVertical.toggle()
        UserDefaults.standard.set(isVertical, forKey: Self.orientationKey)
        updateLayout()
    }

    private func updateLayout() {
        stackView.orientation = isVertical ? .vertical : .horizontal
        stackView.alignment = isVertical ? .centerX : .centerY
        let orientationDescription = isVertical ? "横型にする" : "縦型にする"
        orientationButton.title = ""
        orientationButton.image = NSImage(
            systemSymbolName: isVertical ? "arrow.left.and.right" : "arrow.up.and.down",
            accessibilityDescription: orientationDescription
        )
        orientationButton.toolTip = orientationDescription
        orientationButton.setAccessibilityLabel(orientationDescription)

        let anchorScreen = savedAnchor.flatMap { anchor in
            NSScreen.screens.first {
                $0.frame.contains(CGPoint(x: anchor.x, y: anchor.y - 1))
            }
        }
        guard let targetScreen = anchorScreen ?? NSScreen.main else { return }
        let visibleTools = tools.filter { !toolVisibility.hidden.contains($0.title) }
        let size = Self.panelSize(for: visibleTools, isVertical: isVertical)
        let newFrame = PanelPlacement.frame(
            size: size, anchor: anchorScreen == nil ? nil : savedAnchor, in: targetScreen.visibleFrame
        )
        isApplyingLayout = true
        defer { isApplyingLayout = false }
        setFrame(newFrame, display: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: LauncherPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = LauncherPanel(tools: AIToolCatalog.tools)
        panel?.orderFrontRegardless()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: "AI Tool Switcher"
        )
        item.button?.toolTip = "AI Tool Switcher"
        let menu = NSMenu()
        menu.delegate = self
        menuNeedsUpdate(menu)
        item.menu = menu
        statusItem = item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel?.orderFrontRegardless()
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let panel else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false
        let visibilityTitle = panel.isVisible ? "パネルを隠す" : "パネルを再表示"
        menu.addItem(menuItem(visibilityTitle, action: #selector(togglePanel)))
        menu.addItem(menuItem("位置を戻す", action: #selector(resetPanelPosition)))
        menu.addItem(.separator())

        let toolsItem = NSMenuItem(title: "表示するAIツール", action: nil, keyEquivalent: "")
        let toolsMenu = NSMenu()
        toolsMenu.autoenablesItems = false
        for tool in AIToolCatalog.tools {
            let item = menuItem(tool.title, action: #selector(toggleTool(_:)))
            item.representedObject = tool.title
            item.state = panel.toolVisibility.hidden.contains(tool.title) ? .off : .on
            item.isEnabled = panel.toolVisibility.canToggle(tool.title)
            toolsMenu.addItem(item)
        }
        toolsItem.submenu = toolsMenu
        menu.addItem(toolsItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("AI Tool Switcherを終了", action: #selector(quit)))
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func resetPanelPosition() {
        panel?.resetPosition()
        panel?.orderFrontRegardless()
    }

    @objc private func toggleTool(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String else { return }
        panel?.toggleToolVisibility(title)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
@MainActor
struct AIToolSwitcherMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
