import BairometerCore

enum UsageDisplayOverrideSelection: CaseIterable, Hashable, Identifiable {
    case global
    case used
    case left

    var id: Self { self }

    var overrideMode: UsageDisplayMode? {
        switch self {
        case .global:
            nil
        case .used:
            .used
        case .left:
            .left
        }
    }

    init(mode: UsageDisplayMode?) {
        switch mode {
        case nil:
            self = .global
        case .used:
            self = .used
        case .left:
            self = .left
        }
    }
}
