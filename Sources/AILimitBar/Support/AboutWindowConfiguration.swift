import SwiftUI

enum AboutWindowConfiguration {
    static let title = "About Bairometer"
    static let preferredSize = CGSize(width: 360, height: 410)

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
}
