import SwiftUI

struct SettingsWindowPlacementGeometry: Equatable {
    let position: CGPoint
    let size: CGSize
}

enum SettingsWindowConfiguration {
    static let id = "settings"
    static let title = "Bairometer Settings"
    static let preferredSize = CGSize(width: 840, height: 560)

    static func defaultSize(contentSize: CGSize, visibleRect: CGRect) -> CGSize {
        let requestedSize = CGSize(
            width: max(preferredSize.width, contentSize.width),
            height: max(preferredSize.height, contentSize.height)
        )
        let availableSize = visibleRect.size

        return CGSize(
            width: min(requestedSize.width, max(0, availableSize.width)),
            height: min(requestedSize.height, max(0, availableSize.height))
        )
    }

    static func defaultPlacement(contentSize: CGSize, visibleRect: CGRect) -> SettingsWindowPlacementGeometry {
        let size = defaultSize(contentSize: contentSize, visibleRect: visibleRect)
        return SettingsWindowPlacementGeometry(
            position: CGPoint(
                x: visibleRect.midX - (size.width / 2),
                y: visibleRect.midY - (size.height / 2)
            ),
            size: size
        )
    }

    static func centeredWindowFrame(_ windowFrame: CGRect, in visibleRect: CGRect) -> CGRect {
        let size = CGSize(
            width: min(windowFrame.width, visibleRect.width),
            height: min(windowFrame.height, visibleRect.height)
        )
        return CGRect(
            x: visibleRect.midX - (size.width / 2),
            y: visibleRect.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    static func matchesTitle(_ value: String) -> Bool {
        value == title || value == AppStrings.Window.settingsTitle.localized(locale: Locale(identifier: "ru"))
    }
}

enum OllamaConnectionWindowConfiguration {
    static let id = "ollama-connection"
    static let title = "Connect Ollama"
    static let preferredSize = CGSize(width: 1_080, height: 840)

    static func defaultSize(contentSize: CGSize, visibleRect: CGRect) -> CGSize {
        CGSize(
            width: min(max(preferredSize.width, contentSize.width), visibleRect.width),
            height: min(max(preferredSize.height, contentSize.height), visibleRect.height)
        )
    }

    static func matchesTitle(_ value: String) -> Bool {
        value == title || value == AppStrings.Window.ollamaTitle.localized(locale: Locale(identifier: "ru"))
    }
}
