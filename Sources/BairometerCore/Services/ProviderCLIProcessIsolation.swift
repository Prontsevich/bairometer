import Foundation

enum ProviderCLIProcessIsolation {
    static func defaultWorkingDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("io.github.Prontsevich.Bairometer", isDirectory: true)
            .appendingPathComponent("ProviderCLI", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    static func prepareWorkingDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    static func isolatedEnvironment(
        from inheritedEnvironment: [String: String],
        workingDirectoryURL: URL
    ) -> [String: String] {
        var environment = inheritedEnvironment
        environment["PWD"] = workingDirectoryURL.path
        environment.removeValue(forKey: "OLDPWD")
        environment.removeValue(forKey: "INIT_CWD")
        return environment
    }
}
