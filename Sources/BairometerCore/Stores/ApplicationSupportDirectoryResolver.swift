import Foundation

public struct ApplicationSupportDirectoryResolver: Sendable {
    public let appDirectoryName: String

    public init(appDirectoryName: String = "Bairometer") {
        self.appDirectoryName = appDirectoryName
    }

    public func resolve() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent(appDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
