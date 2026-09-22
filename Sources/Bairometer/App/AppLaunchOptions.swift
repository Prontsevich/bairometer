import Foundation

struct AppLaunchOptions {
    static let storageDirectoryArgument = "--bairometer-storage-directory"

    let storageDirectory: URL?
#if DEBUG
    let uiTestHostConfiguration: UITestHostConfiguration?
#endif

    init(
        arguments: [String] = CommandLine.arguments,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        guard let argumentIndex = arguments.firstIndex(of: Self.storageDirectoryArgument) else {
            storageDirectory = nil
#if DEBUG
            uiTestHostConfiguration = Self.uiTestHostConfiguration(
                arguments: arguments,
                bundleIdentifier: bundleIdentifier
            )
#endif
            return
        }

        let valueIndex = arguments.index(after: argumentIndex)
        guard valueIndex < arguments.endIndex else {
            fatalError("Missing value for \(Self.storageDirectoryArgument)")
        }

        let path = arguments[valueIndex]
        guard path.hasPrefix("/") else {
            fatalError("The value for \(Self.storageDirectoryArgument) must be an absolute path")
        }

        storageDirectory = URL(fileURLWithPath: path, isDirectory: true)
#if DEBUG
        uiTestHostConfiguration = Self.uiTestHostConfiguration(
            arguments: arguments,
            bundleIdentifier: bundleIdentifier
        )
#endif
    }

#if DEBUG
    private static func uiTestHostConfiguration(
        arguments: [String],
        bundleIdentifier: String?
    ) -> UITestHostConfiguration? {
        do {
            return try UITestHostConfiguration.parse(
                arguments: arguments,
                bundleIdentifier: bundleIdentifier
            )
        } catch {
            fatalError("Invalid UI test host configuration: \(error)")
        }
    }
#endif
}
