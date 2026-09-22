import BairometerCore
import Foundation

struct AccountRefreshIssue: Equatable {
    let occurredAt: Date
    let warnings: [String]
}

struct AccountSnapshotRow: Identifiable {
    let account: ProviderAccount
    let providerDisplayName: String
    let snapshot: UsageSnapshot?
    let refreshStatus: ProviderRefreshStatus
    let refreshIssue: AccountRefreshIssue?

    var id: String { account.id }
}
