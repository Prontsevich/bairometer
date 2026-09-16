import AILimitBarCore
import Darwin
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, arguments[1] == "--account-id", !arguments[2].isEmpty else {
    fputs("Usage: AILimitBarClaudeStatusLine --account-id <account-id>\n", stderr)
    exit(EXIT_FAILURE)
}

let data = FileHandle.standardInput.readDataToEndOfFile()
let accountID = arguments[2]

do {
    let directory = try ApplicationSupportDirectoryResolver().resolve()
    let snapshot = try ClaudeCodeStatusLineDatabaseWriter(directory: directory)
        .writeSnapshot(from: data, accountID: accountID)
    let values = snapshot.limitWindows.compactMap { window -> String? in
        guard let usedPercent = window.usedPercent else { return nil }
        let shortName = window.id == "rolling-5-hour" ? "5h" : "7d"
        return "\(shortName) \(Int(usedPercent.rounded()))%"
    }
    print(values.isEmpty ? "AI Limits unavailable" : "AI Limits · \(values.joined(separator: " · "))")
} catch {
    fputs("Bairometer: \(error.localizedDescription)\n", stderr)
    print("AI Limits unavailable")
    exit(EXIT_FAILURE)
}
