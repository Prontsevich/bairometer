import BairometerCore
import Foundation

struct ClaudeCodeStatusLineInstaller {
    func install() throws -> URL {
        let sourceURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(ClaudeCodeStatusLinePaths.helperFileName)

        guard FileManager.default.isExecutableFile(atPath: sourceURL.path) else {
            throw InstallerError.helperMissing
        }

        let destinationURL = try ClaudeCodeStatusLinePaths.helperURL()
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let helperData = try Data(contentsOf: sourceURL)
        try helperData.write(to: destinationURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destinationURL.path
        )
        return destinationURL
    }

    func settingsSnippet(helperURL: URL, accountID: String) -> String {
        let command = "\(shellQuote(helperURL.path)) --account-id \(shellQuote(accountID))"
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "statusLine": {
            "type": "command",
            "command": "\(escapedCommand)"
          }
        }
        """
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    enum InstallerError: Error, LocalizedError {
        case helperMissing

        var errorDescription: String? {
            switch self {
            case .helperMissing:
                return "The Claude Code helper is unavailable in this app bundle. Rebuild the staged app bundle first."
            }
        }
    }
}
