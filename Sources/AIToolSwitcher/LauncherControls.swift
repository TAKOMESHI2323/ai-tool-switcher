import CoreGraphics

struct ToolVisibility {
    private let catalog: [String]
    private(set) var hidden: Set<String>

    init(catalog: [String], savedHidden: [String]) {
        self.catalog = catalog
        self.hidden = Set(savedHidden).intersection(catalog)
        if let first = catalog.first, hidden.count == catalog.count {
            hidden.remove(first)
        }
    }

    var visibleTitles: [String] {
        catalog.filter { !hidden.contains($0) }
    }

    func canToggle(_ title: String) -> Bool {
        catalog.contains(title) && (hidden.contains(title) || visibleTitles.count > 1)
    }

    @discardableResult
    mutating func toggle(_ title: String) -> Bool {
        guard canToggle(title) else { return false }
        if hidden.remove(title) == nil {
            hidden.insert(title)
        }
        return true
    }
}

enum PanelPlacement {
    static func frame(size: CGSize, anchor: CGPoint?, in visibleFrame: CGRect) -> CGRect {
        let x = anchor?.x ?? (visibleFrame.midX - size.width / 2)
        let top = anchor?.y ?? (visibleFrame.maxY - 12)
        let rightmost = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let highest = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return CGRect(
            x: min(max(x, visibleFrame.minX), rightmost),
            y: min(max(top - size.height, visibleFrame.minY), highest),
            width: size.width,
            height: size.height
        )
    }
}

enum ActivationRouting {
    static func candidates(_ identifiers: [String], preferredAvailable: Bool) -> [String] {
        preferredAvailable ? Array(identifiers.prefix(1)) : identifiers
    }
}
