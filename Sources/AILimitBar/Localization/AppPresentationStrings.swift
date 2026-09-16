import Foundation

struct MiniMaxLocalizedString {
    let english: String
    let russian: String

    func localized(locale: Locale) -> String {
        let language = locale.identifier
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_", maxSplits: 1)
            .first
            .map(String.init)
        return language == "ru" ? russian : english
    }

    func formatted(locale: Locale, _ arguments: CVarArg...) -> String {
        String(
            format: localized(locale: locale),
            locale: locale,
            arguments: arguments
        )
    }
}

extension AppStrings {
    enum Common {
        static let cancel = AppString("common.action.cancel", defaultValue: "Cancel", comment: "Cancel button")
        static let save = AppString("common.action.save", defaultValue: "Save", comment: "Save button")
        static let create = AppString("common.action.create", defaultValue: "Create", comment: "Create button")
        static let delete = AppString("common.action.delete", defaultValue: "Remove", comment: "Remove locally configured item button")
        static let ok = AppString("common.action.ok", defaultValue: "OK", comment: "Confirmation button")
        static let refresh = AppString("common.action.refresh", defaultValue: "Refresh", comment: "Refresh action")
        static let refreshing = AppString("common.status.refreshing", defaultValue: "Refreshing", comment: "Refresh progress status")
        static let ready = AppString("common.status.ready", defaultValue: "Ready", comment: "Idle status")
        static let enabled = AppString("common.field.enabled", defaultValue: "Enabled", comment: "Enabled account setting")
        static let selected = AppString("common.selection.selected", defaultValue: "Selected", comment: "Selected segmented control option")
        static let notSelected = AppString("common.selection.not_selected", defaultValue: "Not selected", comment: "Unselected segmented control option")
        static let on = AppString("common.toggle.on", defaultValue: "ON", comment: "Toggle on label")
        static let off = AppString("common.toggle.off", defaultValue: "OFF", comment: "Toggle off label")
        static let onAccessibility = AppString("common.toggle.on_accessibility", defaultValue: "On", comment: "Toggle accessibility value when enabled")
        static let offAccessibility = AppString("common.toggle.off_accessibility", defaultValue: "Off", comment: "Toggle accessibility value when disabled")
        static let noUsageData = AppString("common.usage.no_data", defaultValue: "No usage data", comment: "Fallback when no usage snapshot exists")
        static let usageUnavailable = AppString("common.usage.unavailable", defaultValue: "Usage unavailable", comment: "Fallback when usage cannot be read")
        static let manual = AppString("common.source.manual", defaultValue: "Manual", comment: "Manual source label")
        static let live = AppString("common.source.live", defaultValue: "Live", comment: "Live source label")
        static let delayed = AppString("common.source.delayed", defaultValue: "Delayed", comment: "Delayed source label")
        static let localEstimate = AppString("common.source.local_estimate", defaultValue: "Local estimate", comment: "Local estimate confidence label")
        static let unknown = AppString("common.source.unknown", defaultValue: "Unknown", comment: "Unknown confidence label")
        static let unavailable = AppString("common.status.unavailable", defaultValue: "Unavailable", comment: "Unavailable status")
        static let unlimited = AppString("common.status.unlimited", defaultValue: "Unlimited", comment: "Unlimited capacity status")
        static let warning = AppString("common.status.warning", defaultValue: "Warning", comment: "Warning status")
        static let error = AppString("common.status.error", defaultValue: "Error", comment: "Error status")
        static let failed = AppString("common.status.failed", defaultValue: "Failed", comment: "Failed status")
        static let stale = AppString("common.status.stale", defaultValue: "Stale", comment: "Stale status")
        static let supported = AppString("common.status.supported", defaultValue: "Supported", comment: "Supported source status")
        static let selectedAccount = AppString("common.account.selected", defaultValue: "the selected account", comment: "Fallback account name in a destructive confirmation")
        static let idle = AppString("common.status.idle", defaultValue: "Idle", comment: "Idle refresh status")
        static let updated = AppString("common.status.updated", defaultValue: "Updated", comment: "Updated refresh status")
        static let managedStatusLine = AppString("common.source.managed_status_line", defaultValue: "Managed statusLine", comment: "Managed Claude statusLine source mode")
        static let usageCLIExperimental = AppString("common.source.usage_cli_experimental", defaultValue: "/usage CLI (Experimental)", comment: "Experimental Claude usage CLI source mode")
        static let webPageExperimental = AppString("common.source.web_page_experimental", defaultValue: "Experimental web page", comment: "Experimental web page source mode")
        static let appServerExperimental = AppString("common.source.app_server_experimental", defaultValue: "Experimental app-server", comment: "Experimental app-server source mode")
        static let localSnapshot = AppString("common.source.local_snapshot", defaultValue: "Local snapshot", comment: "Local snapshot source kind")
        static let intervalManual = AppString("common.interval.manual", defaultValue: "Manual", comment: "Manual refresh interval")
        static let intervalOneMinute = AppString("common.interval.one_minute", defaultValue: "1 min", comment: "One minute refresh interval")
        static let intervalFiveMinutes = AppString("common.interval.five_minutes", defaultValue: "5 min", comment: "Five minute refresh interval")
        static let intervalTenMinutes = AppString("common.interval.ten_minutes", defaultValue: "10 min", comment: "Ten minute refresh interval")
        static let intervalFifteenMinutes = AppString("common.interval.fifteen_minutes", defaultValue: "15 min", comment: "Fifteen minute refresh interval")
        static let intervalThirtyMinutes = AppString("common.interval.thirty_minutes", defaultValue: "30 min", comment: "Thirty minute refresh interval")
        static let intervalOneHour = AppString("common.interval.one_hour", defaultValue: "1 hr", comment: "One hour refresh interval")
        static let heightCompact = AppString("common.height.compact", defaultValue: "Compact", comment: "Compact dashboard height option")
        static let heightStandard = AppString("common.height.standard", defaultValue: "Standard", comment: "Standard dashboard height option")
        static let heightTall = AppString("common.height.tall", defaultValue: "Tall", comment: "Tall dashboard height option")
    }

    enum Dashboard {
        static let used = AppString("dashboard.usage.used", defaultValue: "%@ used", comment: "Used percentage beside a dashboard meter")
        static let left = AppString("dashboard.usage.left", defaultValue: "%@ left", comment: "Left percentage beside a dashboard meter")
        static let windowUsage = AppString("dashboard.usage.accessibility", defaultValue: "%@ usage", comment: "Accessibility label for a provider limit window")
        static let meterToggleHelp = AppString("dashboard.usage.toggle_help", defaultValue: "%@ is %@. Activate to show %@.", comment: "Help text for toggling a dashboard meter display mode")
        static let meterToggleHint = AppString("dashboard.usage.toggle_hint", defaultValue: "Toggles between used and left.", comment: "Accessibility hint for toggling a dashboard meter display mode")
        static let resets = AppString("dashboard.reset.future", defaultValue: "resets %@", comment: "Relative future reset label")
        static let reset = AppString("dashboard.reset.past", defaultValue: "reset %@", comment: "Relative past reset label")
        static let refreshAccount = AppString("dashboard.action.refresh_account", defaultValue: "Refresh %@", comment: "Refresh account accessibility label")
        static let accountDisabled = AppString("dashboard.refresh_help.account_disabled", defaultValue: "%@ is disabled.", comment: "Disabled account refresh help")
        static let refreshingAccount = AppString("dashboard.refresh_help.refreshing_account", defaultValue: "Refreshing %@.", comment: "Account refresh in progress help")
        static let showDetails = AppString("dashboard.action.show_details", defaultValue: "Show account details", comment: "Open account details tooltip")
        static let showDetailsForAccount = AppString("dashboard.action.show_details_for_account", defaultValue: "Show details for %@", comment: "Open account details accessibility label")
        static let refreshFailed = AppString("dashboard.status.refresh_failed", defaultValue: "Refresh failed", comment: "Refresh failure dashboard status")
        static let manualSource = AppString("dashboard.body.manual_source", defaultValue: "Manual source — open provider usage", comment: "Manual source dashboard message")
        static let noData = AppString("dashboard.body.no_data", defaultValue: "No usage data", comment: "No usage dashboard message")
        static let refreshFailedFallback = AppString("dashboard.body.refresh_failed", defaultValue: "Refresh failed", comment: "Refresh failure dashboard fallback")
        static let session = AppString("dashboard.window.session", defaultValue: "Session", comment: "Known normalized session usage window")
        static let weekly = AppString("dashboard.window.weekly", defaultValue: "Weekly", comment: "Known normalized weekly usage window")
        static let fiveHour = AppString("dashboard.window.five_hour", defaultValue: "5-hour", comment: "Known normalized five hour usage window")
        static let sevenDay = AppString("dashboard.window.seven_day", defaultValue: "7-day", comment: "Known normalized seven day usage window")
        static let highestUsage = AppString("dashboard.accessibility.highest_usage", defaultValue: "Highest usage is %@", comment: "Menu bar accessibility summary of highest usage")
        static let noUsageAvailable = AppString("dashboard.accessibility.no_usage_available", defaultValue: "No usage data available", comment: "Menu bar accessibility summary with no usage")
        static let noEnabledAccounts = AppString("dashboard.accessibility.no_enabled_accounts", defaultValue: "No enabled accounts", comment: "Menu bar accessibility summary with no enabled accounts")
        static let warningSummary = AppString("dashboard.accessibility.warning_summary", defaultValue: "Warning: one or more enabled accounts need attention. %@", comment: "Menu bar accessibility warning summary")
        static let errorSummary = AppString("dashboard.accessibility.error_summary", defaultValue: "Error: one or more enabled accounts need attention. %@", comment: "Menu bar accessibility error summary")
        static let sourceUnsupported = AppString("dashboard.diagnostics.source_unsupported", defaultValue: "This source mode is not supported by the provider adapter.", comment: "Unsupported source diagnostic summary")
        static let lastRefreshFailed = AppString("dashboard.diagnostics.last_refresh_failed", defaultValue: "The last refresh failed.", comment: "Failed refresh diagnostic summary")
        static let connectBeforeRefresh = AppString("dashboard.diagnostics.connect_before_refresh", defaultValue: "Connect this account through Bairometer before refreshing.", comment: "Connect before refreshing diagnostic summary")
        static let sourceSupported = AppString("dashboard.diagnostics.source_supported", defaultValue: "The configured source is supported.", comment: "Supported source diagnostic summary")
        static let ollamaSourceSummary = AppString("dashboard.diagnostics.ollama_source_summary", defaultValue: "Read usage from the authenticated Ollama settings page in Bairometer.", comment: "Ollama source summary")
        static let claudeStatusLineSummary = AppString("dashboard.diagnostics.claude_status_line_summary", defaultValue: "Read rate-limit data from Claude Code's managed statusLine snapshot.", comment: "Claude statusLine source summary")
        static let claudeUsageSummary = AppString("dashboard.diagnostics.claude_usage_summary", defaultValue: "Read plan limits from the local Claude Code /usage command.", comment: "Claude usage CLI source summary")
        static let codexSourceSummary = AppString("dashboard.diagnostics.codex_source_summary", defaultValue: "Read current rate-limit windows from the local Codex app-server.", comment: "Codex app-server source summary")
    }

    enum Storage {
        static let providerSettingsSave = AppString("storage.provider_settings_save", defaultValue: "Provider settings could not be saved.", comment: "Provider settings persistence warning")
        static let refreshSettingsSave = AppString("storage.refresh_settings_save", defaultValue: "Refresh settings could not be saved.", comment: "Refresh settings persistence warning")
        static let usageDisplayPreferencesLoad = AppString("storage.usage_display_preferences_load", defaultValue: "Usage display preferences could not be loaded.", comment: "Usage display preferences load warning")
        static let usageDisplayPreferencesSave = AppString("storage.usage_display_preferences_save", defaultValue: "Usage display preferences could not be saved.", comment: "Usage display preferences save warning")
        static let snapshotsSave = AppString("storage.snapshots_save", defaultValue: "Snapshots could not be saved.", comment: "Snapshots persistence warning")
        static let diagnosticsSave = AppString("storage.diagnostics_save", defaultValue: "Provider diagnostics could not be saved.", comment: "Provider diagnostics persistence warning")
        static let refreshStateSave = AppString("storage.refresh_state_save", defaultValue: "Provider refresh state could not be saved.", comment: "Provider refresh state persistence warning")
        static let legacyMigration = AppString("storage.legacy_migration", defaultValue: "Legacy JSON data could not be migrated. Existing database data remains available.", comment: "Legacy migration warning")
        static let temporaryStorage = AppString("storage.temporary_storage", defaultValue: "Application Support is unavailable. Temporary storage is active.", comment: "Temporary storage warning")
        static let storageUnavailable = AppString("storage.unavailable", defaultValue: "Bairometer storage is unavailable. Changes cannot be saved.", comment: "Storage unavailable warning")
        static let openRouterCredentials = AppString("storage.openrouter_credentials", defaultValue: "OpenRouter key metadata could not be loaded.", comment: "OpenRouter key metadata storage warning")
    }

    enum DisplayMode {
        static let used = AppString("display_mode.used", defaultValue: "Used", comment: "Usage display mode option")
        static let left = AppString("display_mode.left", defaultValue: "Left", comment: "Usage display mode option")
        static let useGlobal = AppString("display_mode.use_global", defaultValue: "Use global", comment: "Usage display override option that inherits the global setting")
    }

}

extension AppStrings.Settings {
        enum Navigation {
            static let label = AppString("settings.navigation.label", defaultValue: "Settings Section", comment: "Settings section selector accessibility label")
            static let general = AppString("settings.navigation.general", defaultValue: "General", comment: "General settings navigation item")
            static let accounts = AppString("settings.navigation.accounts", defaultValue: "Accounts", comment: "Accounts settings navigation item")
            static let providerSetup = AppString("settings.navigation.provider_setup", defaultValue: "Providers", comment: "Providers settings navigation item")
        }

        enum General {
            static let title = AppString("settings.general.title", defaultValue: "GENERAL", comment: "General settings page title")
            static let description = AppString("settings.general.description", defaultValue: "Configure preferences that apply across Bairometer accounts.", comment: "General settings page description")
            static let scheduleTitle = AppString("settings.schedule.title", defaultValue: "SCHEDULE", comment: "Refresh schedule section title")
            static let interval = AppString("settings.schedule.interval", defaultValue: "Interval", comment: "Refresh interval field label")
            static let refreshInterval = AppString("settings.schedule.accessibility", defaultValue: "Refresh interval", comment: "Refresh interval selector accessibility label")
            static let manualRefreshHelp = AppString("settings.schedule.manual_refresh_help", defaultValue: "Manual refresh stays available from the menu bar panel.", comment: "Refresh schedule help text")
            static let dashboardTitle = AppString("settings.dashboard.title", defaultValue: "DASHBOARD", comment: "Dashboard settings section title")
            static let height = AppString("settings.dashboard.height", defaultValue: "Height", comment: "Dashboard height field label")
            static let heightAccessibility = AppString("settings.dashboard.height_accessibility", defaultValue: "Dashboard height", comment: "Dashboard height selector accessibility label")
            static let heightHelp = AppString("settings.dashboard.height_help", defaultValue: "Controls the maximum visible height of the menu-bar dashboard. Longer account lists scroll.", comment: "Dashboard height help text")
            static let displayLimits = AppString("settings.dashboard.display_limits", defaultValue: "Limits", comment: "Usage display mode field label")
            static let displayLimitsAccessibility = AppString("settings.dashboard.display_limits_accessibility", defaultValue: "Limit display", comment: "Usage display mode selector accessibility label")
            static let displayLimitsHelp = AppString("settings.dashboard.display_limits_help", defaultValue: "Sets the default for windows that use the global display mode.", comment: "Usage display mode setting help text")
        }

        enum Accounts {
            static let title = AppString("settings.accounts.title", defaultValue: "ACCOUNTS", comment: "Accounts page title")
            static let deleteTitle = AppString("settings.accounts.delete_title", defaultValue: "Remove Account?", comment: "Remove locally configured account alert title")
            static let deleteMessage = AppString("settings.accounts.delete_message", defaultValue: "This removes %@ and its stored snapshot from Bairometer.", comment: "Delete account alert message")
            static let deleteOpenRouterMessage = AppString("settings.accounts.delete_openrouter_message", defaultValue: "This securely removes %@, every stored OpenRouter key for it, and its capacity data from Bairometer.", comment: "Remove locally configured OpenRouter account alert message")
            static let moveUp = AppString("settings.accounts.move_up", defaultValue: "Move Up", comment: "Move account up action")
            static let moveDown = AppString("settings.accounts.move_down", defaultValue: "Move Down", comment: "Move account down action")
            static let addAccount = AppString("settings.accounts.add", defaultValue: "Add account", comment: "Add account tooltip and accessibility label")
            static let deleteSelectedAccount = AppString("settings.accounts.delete_selected", defaultValue: "Remove selected account", comment: "Remove selected locally configured account tooltip and accessibility label")
            static let selectOrAdd = AppString("settings.accounts.select_or_add", defaultValue: "Select an account or add a new one to configure it.", comment: "Accounts empty state description")
            static let noAccountSelected = AppString("settings.accounts.no_account_selected", defaultValue: "No Account Selected", comment: "Accounts empty state title")
            static let discardTitle = AppString("settings.accounts.discard_title", defaultValue: "Discard Changes?", comment: "Discard account changes alert title")
            static let discard = AppString("settings.accounts.discard", defaultValue: "Discard Changes", comment: "Discard account changes action")
            static let keepEditing = AppString("settings.accounts.keep_editing", defaultValue: "Keep Editing", comment: "Keep editing action")
            static let discardMessage = AppString("settings.accounts.discard_message", defaultValue: "Your account changes have not been saved.", comment: "Discard account changes alert message")
        }

        enum ProviderSetup {
            static let title = AppString("settings.provider_setup.title", defaultValue: "PROVIDERS", comment: "Providers page title")
            static let description = AppString("settings.provider_setup.description", defaultValue: "Open the limits page for a provider.", comment: "Providers page description")
            static let providers = AppString("settings.provider_setup.providers", defaultValue: "AVAILABLE PROVIDERS", comment: "Provider list section title")
            static let openUsage = AppString("settings.provider_setup.open_usage", defaultValue: "Open Limits", comment: "Open provider limits action")
            static let noConfiguredSource = AppString("settings.provider_setup.no_configured_source", defaultValue: "Limits page unavailable", comment: "Provider without a limits page")
        }

        enum Detail {
            static let status = AppString("settings.detail.status", defaultValue: "STATUS", comment: "Account status section title")
            static let source = AppString("settings.detail.source", defaultValue: "Source", comment: "Source field label")
            static let refresh = AppString("settings.detail.refresh", defaultValue: "Refresh", comment: "Refresh field label")
            static let lastUpdated = AppString("settings.detail.last_updated", defaultValue: "Last updated", comment: "Last updated field label")
            static let configuration = AppString("settings.detail.configuration", defaultValue: "CONFIGURATION", comment: "Account configuration section title")
            static let provider = AppString("settings.detail.provider", defaultValue: "Provider", comment: "Provider field label")
            static let accountStatus = AppString("settings.detail.account_status", defaultValue: "Account status", comment: "Accessibility label for an account-level exception")
            static let migration = AppString("settings.detail.migration", defaultValue: "MIGRATION", comment: "Migration diagnostics section title")
            static let codexExecutable = AppString("settings.detail.codex_executable", defaultValue: "Codex executable", comment: "Codex executable field label")
            static let claudeExecutable = AppString("settings.detail.claude_executable", defaultValue: "Claude executable", comment: "Claude executable field label")
            static let editAccount = AppString("settings.detail.edit_account", defaultValue: "Edit account", comment: "Edit account tooltip")
            static let connectOllama = AppString("settings.detail.connect_ollama", defaultValue: "Connect Ollama", comment: "Connect Ollama action")
            static let reconnectOllama = AppString("settings.detail.reconnect_ollama", defaultValue: "Reconnect Ollama", comment: "Reconnect Ollama action")
            static let refreshing = AppString("settings.detail.refreshing", defaultValue: "Refreshing…", comment: "Refresh tooltip during an account refresh")
        }

        enum Editor {
            static let newAccount = AppString("settings.editor.new_account", defaultValue: "New Account", comment: "New account editor title")
            static let editAccount = AppString("settings.editor.edit_account", defaultValue: "Edit Account", comment: "Edit account editor title")
            static let newDescription = AppString("settings.editor.new_description", defaultValue: "Add a provider account to track its usage.", comment: "New account editor description")
            static let editDescription = AppString("settings.editor.edit_description", defaultValue: "Save to apply account configuration changes.", comment: "Edit account editor description")
            static let account = AppString("settings.editor.account", defaultValue: "ACCOUNT", comment: "Account editor section title")
            static let accountName = AppString("settings.editor.account_name", defaultValue: "Account Name", comment: "Account name field label")
            static let source = AppString("settings.editor.source", defaultValue: "SOURCE", comment: "Source editor section title")
            static let mode = AppString("settings.editor.mode", defaultValue: "Mode", comment: "Source mode field label")
            static let provider = AppString("settings.editor.provider", defaultValue: "Provider", comment: "Provider field label")
            static let manualSourceDescription = AppString("settings.editor.manual_source_description", defaultValue: "Manual source: open the Claude usage page when you need to check plan limits. Bairometer does not start Claude Code or retain provider output in this mode.", comment: "Manual Claude source description")
            static let statusLineTitle = AppString("settings.editor.status_line_title", defaultValue: "Claude Code statusLine helper", comment: "Claude statusLine helper title")
            static let statusLineDescription = AppString("settings.editor.status_line_description", defaultValue: "The helper reads Claude Code's official statusLine JSON and writes local-estimate rate-limit data to Bairometer's managed database. No JSON path is configured or retained.", comment: "Claude statusLine helper description")
            static let installHelper = AppString("settings.editor.install_helper", defaultValue: "Install or Repair Helper", comment: "Install Claude statusLine helper action")
            static let saveFirst = AppString("settings.editor.save_first", defaultValue: "Save this account first, then install its helper configuration.", comment: "Save account before helper installation message")
            static let usageCLI = AppString("settings.editor.usage_cli_description", defaultValue: "Experimental source: Bairometer runs the authenticated local Claude Code CLI in safe non-interactive mode and retains only normalized plan-limit windows. Raw output, activity attribution, stderr, and session metadata are discarded.", comment: "Claude usage CLI source description")
            static let ollamaSource = AppString("settings.editor.ollama_source_description", defaultValue: "Experimental source: Bairometer opens an isolated WebKit session for https://ollama.com/settings. The session is never copied from another browser, and raw page content is not stored.", comment: "Ollama source description")
            static let codexSource = AppString("settings.editor.codex_source_description", defaultValue: "Experimental source: Bairometer starts a short-lived local Codex app-server to read current rate-limit windows. It never reads Codex credentials, session files, browser data, or terminal output.", comment: "Codex app-server source description")
            static let leaveBlankForClaude = AppString("settings.editor.leave_blank_claude", defaultValue: "Leave blank to locate Claude automatically.", comment: "Claude executable path help")
            static let leaveBlankForCodex = AppString("settings.editor.leave_blank_codex", defaultValue: "Leave blank to locate Codex automatically.", comment: "Codex executable path help")
            static let browse = AppString("settings.editor.browse", defaultValue: "Browse…", comment: "Browse executable action")
            static let moreActions = AppString("settings.editor.more_actions", defaultValue: "More account actions", comment: "More account actions tooltip and accessibility label")
            static let providerAccessibility = AppString("settings.editor.provider_accessibility", defaultValue: "Provider", comment: "Provider picker accessibility label")
            static let selectProvider = AppString("settings.editor.select_provider", defaultValue: "Select provider", comment: "Provider picker empty selection")
            static let providerHint = AppString("settings.editor.provider_hint", defaultValue: "Press Space or Return to open the provider list. Use arrow keys to move through the list, then press Space or Return to select a provider.", comment: "Provider picker accessibility hint")
            static let claudePath = AppString("settings.editor.claude_path", defaultValue: "Claude Path", comment: "Claude executable path field label")
            static let codexPath = AppString("settings.editor.codex_path", defaultValue: "Codex Path", comment: "Codex executable path field label")
            static let claudeExecutablePlaceholder = AppString("settings.editor.claude_executable_placeholder", defaultValue: "Claude executable path", comment: "Claude executable path placeholder")
            static let codexExecutablePlaceholder = AppString("settings.editor.codex_executable_placeholder", defaultValue: "Codex executable path", comment: "Codex executable path placeholder")
            static let claudeSourceAccessibility = AppString("settings.editor.claude_source_accessibility", defaultValue: "Claude Code source", comment: "Claude source selector accessibility label")
            static let appServerConflict = AppString("settings.editor.app_server_conflict", defaultValue: "Only one OpenAI Codex account can use the local app-server source because it reads the active local Codex CLI session.", comment: "Codex app-server source conflict")
            static let usageCLIConflict = AppString("settings.editor.usage_cli_conflict", defaultValue: "Only one Claude Code account can use /usage CLI because it reads the active local Claude CLI identity, including when the other account is disabled.", comment: "Claude usage CLI source conflict")
            static let displayNameConflict = AppString("settings.editor.display_name_conflict", defaultValue: "Account names must be globally unique, including disabled accounts.", comment: "Account display name conflict")
            static let saveBeforeHelper = AppString("settings.editor.save_before_helper", defaultValue: "Save the account before installing its statusLine helper.", comment: "Save account before helper install error")
            static let helperInstalled = AppString("settings.editor.helper_installed", defaultValue: "Installed at %@. Add this object to ~/.claude/settings.json:\n\n%@", comment: "Claude helper installation success message")
        }
    }

extension AppStrings {
    enum Ollama {
        static let connectionTitle = AppString("ollama.connection.title", defaultValue: "Ollama Connection", comment: "Ollama connection alert title")
        static let unavailable = AppString("ollama.connection.unavailable", defaultValue: "Ollama connection is unavailable.", comment: "Ollama connection fallback")
        static let saveBeforeConnecting = AppString("ollama.connection.save_before_connecting", defaultValue: "Save the account before connecting Ollama through Bairometer.", comment: "Save account before connecting Ollama")
        static let connect = AppString("ollama.connection.connect", defaultValue: "Connect Ollama", comment: "Ollama connection window title")
        static let reconnect = AppString("ollama.connection.reconnect", defaultValue: "Reconnect Ollama", comment: "Ollama reconnect window title")
        static let description = AppString("ollama.connection.description", defaultValue: "Sign in directly with Ollama in this isolated Bairometer window. Cookies, tokens, passwords, and raw page content stay inside WebKit and are never exported to Bairometer storage.", comment: "Ollama connection privacy description")
        static let profileUnavailable = AppString("ollama.connection.profile_unavailable", defaultValue: "Connection Profile Unavailable", comment: "Unavailable Ollama connection profile title")
        static let saveBeforeOpening = AppString("ollama.connection.save_before_opening", defaultValue: "Save this account before opening the Ollama connection flow.", comment: "Save account before opening Ollama connection")
        static let tryAgain = AppString("ollama.connection.try_again", defaultValue: "Try Again", comment: "Retry Ollama connection action")
        static let loading = AppString("ollama.connection.loading", defaultValue: "Loading Ollama settings…", comment: "Ollama connection loading message")
        static let cancelled = AppString("ollama.connection.cancelled", defaultValue: "Connection cancelled.", comment: "Ollama connection cancelled message")
        static let failed = AppString("ollama.connection.failed", defaultValue: "Ollama connection failed. Reconnect and try again.", comment: "Ollama connection generic failure")
        static let windowUnavailable = AppString("ollama.connection.window_unavailable", defaultValue: "Ollama Connection Unavailable", comment: "Unavailable Ollama window title")
        static let chooseFromAccount = AppString("ollama.connection.choose_from_account", defaultValue: "Choose Connect Ollama or Reconnect from an Ollama account first.", comment: "Unavailable Ollama window description")
    }

    enum About {
        static let buildInformation = AppString("about.build_information", defaultValue: "Build information", comment: "Build information accessibility label")
        static let openGitHub = AppString("about.open_github", defaultValue: "Open GitHub", comment: "Open GitHub action")
        static let openGitHubAccessibility = AppString("about.open_github_accessibility", defaultValue: "Open Bairometer on GitHub", comment: "Open GitHub accessibility label")
        static let feedback = AppString("about.feedback", defaultValue: "Feedback", comment: "Feedback section title")
        static let reportIssue = AppString("about.report_issue", defaultValue: "Report an issue", comment: "Report issue action")
        static let reportIssueAccessibility = AppString("about.report_issue_accessibility", defaultValue: "Report a Bairometer issue on GitHub", comment: "Report issue accessibility label")
        static let email = AppString("about.email", defaultValue: "Email", comment: "Email feedback action")
        static let emailAccessibility = AppString("about.email_accessibility", defaultValue: "Email the Bairometer developer", comment: "Email feedback accessibility label")
        static let telegram = AppString("about.telegram", defaultValue: "Telegram", comment: "Telegram feedback action")
        static let telegramAccessibility = AppString("about.telegram_accessibility", defaultValue: "Message the Bairometer developer on Telegram", comment: "Telegram feedback accessibility label")
        static let supportText = AppString("about.support_text", defaultValue: "If Bairometer is useful, thank you for supporting its development.", comment: "Support message")
        static let supportBoosty = AppString("about.support_boosty", defaultValue: "Support on Boosty", comment: "Boosty support action")
        static let supportBoostyAccessibility = AppString("about.support_boosty_accessibility", defaultValue: "Support Bairometer on Boosty", comment: "Boosty support accessibility label")
        static let accessibilityLabel = AppString("about.accessibility", defaultValue: "About Bairometer", comment: "About window accessibility label")
        static let developmentBuild = AppString("about.development_build", defaultValue: "Development build", comment: "Development build fallback")
        static let version = AppString("about.version", defaultValue: "Version %@ (build %@)", comment: "App version and build text")
    }

    enum AccountDetails {
        static let title = AppString("account_details.title", defaultValue: "%@ details", comment: "Account details fieldset title")
        static let refresh = AppString("account_details.refresh", defaultValue: "REFRESH", comment: "Refresh inspector label")
        static let sourceState = AppString("account_details.source_state", defaultValue: "SOURCE STATE", comment: "Source state inspector label")
        static let lastSuccess = AppString("account_details.last_success", defaultValue: "LAST SUCCESS", comment: "Last successful refresh inspector label")
        static let source = AppString("account_details.source", defaultValue: "SOURCE", comment: "Source inspector label")
        static let confidence = AppString("account_details.confidence", defaultValue: "CONFIDENCE", comment: "Confidence inspector label")
        static let plan = AppString("account_details.plan", defaultValue: "PLAN", comment: "Plan inspector label")
        static let usage = AppString("account_details.usage", defaultValue: "USAGE", comment: "Usage inspector label")
        static let displayMode = AppString("account_details.display_mode", defaultValue: "%@ DISPLAY", comment: "Account-details display mode label for a provider limit window")
        static let displayModeAccessibility = AppString("account_details.display_mode_accessibility", defaultValue: "Display mode for %@", comment: "Account-details display mode selector accessibility label")
        static let reset = AppString("account_details.reset", defaultValue: "%@ RESET", comment: "Limit window reset inspector label")
        static let diagnostics = AppString("account_details.diagnostics", defaultValue: "Diagnostics", comment: "Diagnostics section title")
        static let lastRefreshFailed = AppString("account_details.last_refresh_failed", defaultValue: "Last refresh failed", comment: "Refresh diagnostics title")
        static let noErrorDetails = AppString("account_details.no_error_details", defaultValue: "No additional error details were provided.", comment: "Fallback refresh diagnostics detail")
        static let staleData = AppString("account_details.stale_data", defaultValue: "Stale data", comment: "Stale diagnostics title")
        static let staleDetail = AppString("account_details.stale_detail", defaultValue: "Snapshot is older than the configured freshness window.", comment: "Stale diagnostics detail")
        static let warnings = AppString("account_details.warnings", defaultValue: "Warnings", comment: "Warnings diagnostics title")
        static let testConnection = AppString("account_details.test_connection", defaultValue: "Test Connection", comment: "Test provider connection action")
        static let openUsage = AppString("account_details.open_usage", defaultValue: "Open Usage", comment: "Open provider usage action")
        static let connect = AppString("account_details.connect", defaultValue: "Connect", comment: "Connect provider action")
        static let reconnect = AppString("account_details.reconnect", defaultValue: "Reconnect", comment: "Reconnect provider action")
        static let ollamaConnectFirst = AppString("account_details.ollama_connect_first", defaultValue: "Connect Ollama to load the experimental settings-page source.", comment: "Ollama no data instruction")
        static let codexRefreshFirst = AppString("account_details.codex_refresh_first", defaultValue: "Refresh this account to read the experimental local Codex app-server source.", comment: "Codex no data instruction")
        static let claudeUsageRefreshFirst = AppString("account_details.claude_usage_refresh_first", defaultValue: "Refresh this account to read the experimental local Claude /usage source.", comment: "Claude usage CLI no data instruction")
        static let refreshOrTestFirst = AppString("account_details.refresh_or_test_first", defaultValue: "Refresh or test this account to load a snapshot.", comment: "Generic no data instruction")
        static let succeededAt = AppString("account_details.succeeded_at", defaultValue: "Succeeded at %@", comment: "Refresh success timestamp")
        static let failedAt = AppString("account_details.failed_at", defaultValue: "Failed at %@", comment: "Refresh failure timestamp")
    }

    enum OpenRouter {
        static let sharedCredits = AppString("openrouter.shared_credits", defaultValue: "SHARED CREDITS", comment: "OpenRouter shared credits fieldset title")
        static let apiKeys = AppString("openrouter.api_keys", defaultValue: "API KEYS", comment: "OpenRouter ordinary API keys fieldset title")
        static let accountCredits = AppString("openrouter.metric.account_credits", defaultValue: "Account credits", comment: "OpenRouter account credits metric")
        static let keyCreditLimit = AppString("openrouter.metric.key_credit_limit", defaultValue: "Key credit limit", comment: "OpenRouter API key credit limit metric")
        static let totalUsage = AppString("openrouter.metric.total_usage", defaultValue: "Total usage", comment: "OpenRouter total usage metric")
        static let dailyUsage = AppString("openrouter.metric.daily_usage", defaultValue: "Daily usage", comment: "OpenRouter daily usage metric")
        static let weeklyUsage = AppString("openrouter.metric.weekly_usage", defaultValue: "Weekly usage", comment: "OpenRouter weekly usage metric")
        static let monthlyUsage = AppString("openrouter.metric.monthly_usage", defaultValue: "Monthly usage", comment: "OpenRouter monthly usage metric")
        static let totalBYOKUsage = AppString("openrouter.metric.total_byok_usage", defaultValue: "Total BYOK usage", comment: "OpenRouter total BYOK usage metric")
        static let dailyBYOKUsage = AppString("openrouter.metric.daily_byok_usage", defaultValue: "Daily BYOK usage", comment: "OpenRouter daily BYOK usage metric")
        static let weeklyBYOKUsage = AppString("openrouter.metric.weekly_byok_usage", defaultValue: "Weekly BYOK usage", comment: "OpenRouter weekly BYOK usage metric")
        static let monthlyBYOKUsage = AppString("openrouter.metric.monthly_byok_usage", defaultValue: "Monthly BYOK usage", comment: "OpenRouter monthly BYOK usage metric")
        static let remainingOf = AppString("openrouter.value.remaining_of", defaultValue: "%@ %@ of %@ left", comment: "Compact OpenRouter currency-code, left, and limit value")
        static let remaining = AppString("openrouter.value.remaining", defaultValue: "%@ left", comment: "OpenRouter left value")
        static let available = AppString("openrouter.value.available", defaultValue: "Available", comment: "OpenRouter key capacity available label")
        static let availableOf = AppString("openrouter.value.available_of", defaultValue: "%@ available of %@", comment: "OpenRouter key available capacity accessibility value")
        static let limit = AppString("openrouter.value.limit", defaultValue: "%@ limit", comment: "OpenRouter limit value")
        static let used = AppString("openrouter.value.used", defaultValue: "%@ used", comment: "OpenRouter consumed value")
        static let total = AppString("openrouter.value.total", defaultValue: "%@ total", comment: "OpenRouter total credits value")
        static let creditSummary = AppString("openrouter.value.credit_summary", defaultValue: "%@ left · %@ used", comment: "OpenRouter account credits accessibility summary")
        static let leftColumn = AppString("openrouter.table.left", defaultValue: "Left", comment: "OpenRouter account credits left column")
        static let usedColumn = AppString("openrouter.table.used", defaultValue: "Used", comment: "OpenRouter account credits used column")
        static let scopeColumn = AppString("openrouter.table.scope", defaultValue: "Scope", comment: "OpenRouter reset schedule scope column")
        static let resetColumn = AppString("openrouter.table.reset", defaultValue: "Reset", comment: "OpenRouter reset schedule value column")
        static let usageColumn = AppString("openrouter.table.usage", defaultValue: "Usage", comment: "OpenRouter standard usage column")
        static let byokColumn = AppString("openrouter.table.byok", defaultValue: "BYOK", comment: "OpenRouter BYOK usage column")
        static let dayScope = AppString("openrouter.scope.day", defaultValue: "Day", comment: "OpenRouter daily table scope")
        static let weekScope = AppString("openrouter.scope.week", defaultValue: "Week", comment: "OpenRouter weekly table scope")
        static let monthScope = AppString("openrouter.scope.month", defaultValue: "Month", comment: "OpenRouter monthly table scope")
        static let totalScope = AppString("openrouter.scope.total", defaultValue: "Total", comment: "OpenRouter lifetime table scope")
        static let limitScope = AppString("openrouter.scope.limit", defaultValue: "Limit", comment: "OpenRouter key limit reset scope")
        static let keyLimitSection = AppString("openrouter.section.key_limit", defaultValue: "KEY LIMIT", comment: "OpenRouter expanded key limit section")
        static let usageSection = AppString("openrouter.section.usage", defaultValue: "USAGE", comment: "OpenRouter expanded usage section")
        static let resetScheduleSection = AppString("openrouter.section.reset_schedule", defaultValue: "RESET SCHEDULE", comment: "OpenRouter expanded reset schedule section")
        static let noReset = AppString("openrouter.reset.none", defaultValue: "No reset", comment: "OpenRouter lifetime limit reset")
        static let resetUnknown = AppString("openrouter.reset.unknown", defaultValue: "Reset unknown", comment: "OpenRouter unknown reset time")
        static let resets = AppString("openrouter.reset.future", defaultValue: "Resets %@", comment: "OpenRouter future reset")
        static let reset = AppString("openrouter.reset.past", defaultValue: "Reset %@", comment: "OpenRouter past reset")
        static let updated = AppString("openrouter.freshness.updated", defaultValue: "Updated %@", comment: "OpenRouter observation freshness")
        static let staleUpdated = AppString("openrouter.freshness.stale_updated", defaultValue: "Stale · updated %@", comment: "OpenRouter stale observation freshness")
        static let partial = AppString("openrouter.status.partial", defaultValue: "Partial", comment: "OpenRouter partial account status")
        static let current = AppString("openrouter.status.current", defaultValue: "Current", comment: "OpenRouter current metric status")
        static let disabled = AppString("openrouter.status.disabled", defaultValue: "Disabled", comment: "OpenRouter disabled credential status")
        static let recoveryRequired = AppString("openrouter.status.recovery_required", defaultValue: "Recovery required", comment: "OpenRouter pending credential creation status")
        static let deletionPending = AppString("openrouter.status.deletion_pending", defaultValue: "Secure deletion pending", comment: "OpenRouter pending credential deletion status")
        static let authenticationFailed = AppString("openrouter.status.authentication_failed", defaultValue: "Key authentication failed", comment: "OpenRouter authentication diagnostic")
        static let privilegeInsufficient = AppString("openrouter.status.privilege_insufficient", defaultValue: "Key privileges are insufficient", comment: "OpenRouter insufficient privilege diagnostic")
        static let throttled = AppString("openrouter.status.throttled", defaultValue: "Refresh throttled", comment: "OpenRouter throttled diagnostic")
        static let temporaryFailure = AppString("openrouter.status.temporary_failure", defaultValue: "Refresh failed temporarily", comment: "OpenRouter transient diagnostic")
        static let credentialUnavailable = AppString("openrouter.status.credential_unavailable", defaultValue: "Key unavailable", comment: "OpenRouter unavailable key diagnostic")
        static let noOrdinaryKeys = AppString("openrouter.no_ordinary_keys", defaultValue: "Add at least one key to load per-key capacity.", comment: "OpenRouter no configured keys message")
        static let managementUnavailable = AppString("openrouter.management_unavailable", defaultValue: "Shared credits are unavailable until an optional management key is configured and refreshed.", comment: "OpenRouter unavailable shared credits message")
        static let unnamedKey = AppString("openrouter.unnamed_key", defaultValue: "Unnamed API key", comment: "OpenRouter credential name fallback")
        static let metricsAccessibility = AppString("openrouter.metrics_accessibility", defaultValue: "%@, %@, %@", comment: "OpenRouter metric accessibility value")
        static let credentialsTitle = AppString("openrouter.settings.credentials_title", defaultValue: "KEYS", comment: "OpenRouter key inventory Settings fieldset title")
        static let managementTitle = AppString("openrouter.settings.management_title", defaultValue: "SHARED CREDITS ACCESS", comment: "OpenRouter management credential Settings fieldset title")
        static let addKey = AppString("openrouter.settings.add_key", defaultValue: "Add key", comment: "Add OpenRouter key action")
        static let addManagement = AppString("openrouter.settings.add_management", defaultValue: "Add Management Key", comment: "Add OpenRouter management key action")
        static let credentialActions = AppString("openrouter.settings.credential_actions", defaultValue: "More actions for %@", comment: "OpenRouter credential overflow menu accessibility label")
        static let enableCredential = AppString("openrouter.settings.enable", defaultValue: "Enable", comment: "Enable OpenRouter credential action")
        static let disableCredential = AppString("openrouter.settings.disable", defaultValue: "Disable", comment: "Disable OpenRouter credential action")
        static let notConfigured = AppString("openrouter.settings.not_configured", defaultValue: "Not configured", comment: "OpenRouter optional management credential absence")
        static let noKeyLimit = AppString("openrouter.value.no_key_limit", defaultValue: "No key limit", comment: "OpenRouter ordinary key has no configured key-level limit")
        static let rename = AppString("openrouter.settings.rename", defaultValue: "Rename", comment: "Rename OpenRouter key action")
        static let replace = AppString("openrouter.settings.replace", defaultValue: "Replace Key", comment: "Replace OpenRouter key action")
        static let recover = AppString("openrouter.settings.recover", defaultValue: "Recover Key", comment: "Recover OpenRouter key action")
        static let removeCredential = AppString("openrouter.settings.remove", defaultValue: "Remove", comment: "Remove OpenRouter credential action")
        static let managementCredential = AppString("openrouter.settings.management_credential", defaultValue: "Management key", comment: "OpenRouter management key local label")
        static let storedSecurely = AppString("openrouter.settings.stored_securely", defaultValue: "Stored keys stay in the macOS Data Protection Keychain and are never shown again.", comment: "OpenRouter key storage disclosure")
        static let managementDisclosure = AppString("openrouter.settings.management_disclosure", defaultValue: "Optional elevated key. Bairometer uses it only to read shared account credits through /api/v1/credits. It is never used to refresh per-key capacity.", comment: "OpenRouter elevated key disclosure")
        static let ordinaryDisclosure = AppString("openrouter.settings.ordinary_disclosure", defaultValue: "This locally named key is refreshed independently through /api/v1/key.", comment: "OpenRouter per-key refresh disclosure")
        static let deleteCredentialTitle = AppString("openrouter.settings.delete_title", defaultValue: "Remove Key?", comment: "OpenRouter key delete confirmation title")
        static let deleteCredentialMessage = AppString("openrouter.settings.delete_message", defaultValue: "This securely removes %@ from Keychain and removes its local capacity context.", comment: "OpenRouter key removal confirmation message")
        static let addKeyTitle = AppString("openrouter.editor.add_key_title", defaultValue: "Add key", comment: "OpenRouter key editor title")
        static let keyDetails = AppString("openrouter.editor.key_details", defaultValue: "KEY DETAILS", comment: "OpenRouter key editor fieldset title")
        static let addManagementTitle = AppString("openrouter.editor.add_management_title", defaultValue: "Add Management Key", comment: "OpenRouter management key editor title")
        static let renameKeyTitle = AppString("openrouter.editor.rename_title", defaultValue: "Rename API Key", comment: "OpenRouter credential rename editor title")
        static let replaceCredentialTitle = AppString("openrouter.editor.replace_title", defaultValue: "Replace Key", comment: "OpenRouter key replacement editor title")
        static let recoverCredentialTitle = AppString("openrouter.editor.recover_title", defaultValue: "Recover Key", comment: "OpenRouter key recovery editor title")
        static let keyName = AppString("openrouter.editor.key_name", defaultValue: "Name", comment: "OpenRouter local key name field")
        static let credential = AppString("openrouter.editor.credential", defaultValue: "Key", comment: "OpenRouter key secure field")
        static let credentialPlaceholder = AppString("openrouter.editor.credential_placeholder", defaultValue: "Paste key", comment: "OpenRouter key secure field placeholder")
        static let saveWithoutReadback = AppString("openrouter.editor.no_readback", defaultValue: "The entered key is written directly to Keychain. Bairometer will not display the stored key after this sheet closes.", comment: "OpenRouter no key read-back notice")
        static let errorTitle = AppString("openrouter.error.title", defaultValue: "OpenRouter Key Error", comment: "OpenRouter key error alert title")
        static let invalidAccountError = AppString("openrouter.error.invalid_account", defaultValue: "The OpenRouter account is unavailable.", comment: "OpenRouter invalid account error")
        static let invalidNameError = AppString("openrouter.error.invalid_name", defaultValue: "Enter a local name for this API key.", comment: "OpenRouter invalid local name error")
        static let duplicateNameError = AppString("openrouter.error.duplicate_name", defaultValue: "API key names must be unique within this account.", comment: "OpenRouter duplicate local name error")
        static let emptyCredentialError = AppString("openrouter.error.empty_credential", defaultValue: "Enter a key value.", comment: "OpenRouter empty key error")
        static let managementExistsError = AppString("openrouter.error.management_exists", defaultValue: "This account already has a management key.", comment: "OpenRouter duplicate management key error")
        static let pendingDeletionError = AppString("openrouter.error.pending_deletion", defaultValue: "Secure deletion is pending. Retry removal before replacing this key.", comment: "OpenRouter pending key deletion error")
        static let unavailableCredentialError = AppString("openrouter.error.credential_unavailable", defaultValue: "The selected key is unavailable. Reload Settings and try again.", comment: "OpenRouter missing key error")
        static let keychainError = AppString("openrouter.error.keychain", defaultValue: "Keychain access failed. No stored key was displayed.", comment: "OpenRouter Keychain error")
        static let storageError = AppString("openrouter.error.storage", defaultValue: "OpenRouter key settings could not be saved.", comment: "OpenRouter storage error")
        static let sourceDescription = AppString("openrouter.settings.source_description", defaultValue: "Save the account, then add one or more keys. Shared credits require a separate optional management key.", comment: "OpenRouter account editor source description")
        static let detailsExpanded = AppString("openrouter.details.expanded", defaultValue: "Expanded", comment: "OpenRouter key details disclosure state")
        static let detailsCollapsed = AppString("openrouter.details.collapsed", defaultValue: "Collapsed", comment: "OpenRouter key details disclosure state")
        static let showKeyDetails = AppString("openrouter.details.show", defaultValue: "Show key details.", comment: "OpenRouter key details disclosure hint")
        static let hideKeyDetails = AppString("openrouter.details.hide", defaultValue: "Hide key details.", comment: "OpenRouter key details disclosure hint")
    }

    enum MiniMax {
        static let quotaCategoryAShort = MiniMaxLocalizedString(
            english: "Text & multimedia",
            russian: "Текст и мультимедиа"
        )
        static let quotaCategoryAFull = MiniMaxLocalizedString(
            english: "Shared text & multimodal Token Plan quota",
            russian: "Общая квота Token Plan для текста и мультимодальных задач"
        )
        static let quotaCategoryBShort = MiniMaxLocalizedString(
            english: "Video generation",
            russian: "Генерация видео"
        )
        static let quotaCategoryBFull = MiniMaxLocalizedString(
            english: "Video generation Token Plan quota",
            russian: "Квота Token Plan на генерацию видео"
        )
        static let currentWindow = MiniMaxLocalizedString(
            english: "Current window",
            russian: "Текущее окно"
        )
        static let weeklyWindow = MiniMaxLocalizedString(
            english: "Weekly window",
            russian: "Недельное окно"
        )
        static let capacitySummary = MiniMaxLocalizedString(
            english: "Used %@ · Remaining %@ · Total %@",
            russian: "Использовано %@ · Осталось %@ · Всего %@"
        )
        static let quotaWindowAccessibility = MiniMaxLocalizedString(
            english: "%@, %@",
            russian: "%@, %@"
        )
        static let credentialsTitle = MiniMaxLocalizedString(
            english: "SUBSCRIPTION KEY",
            russian: "КЛЮЧ ПОДПИСКИ"
        )
        static let boundaryLabel = MiniMaxLocalizedString(
            english: "Account boundary",
            russian: "Граница аккаунта"
        )
        static let boundaryDescription = MiniMaxLocalizedString(
            english: "Global · personal Default Team · locally configured. Bairometer does not verify this boundary upstream.",
            russian: "Global · личная Default Team · настроено локально. Биирометр не проверяет эту границу на стороне MiniMax."
        )
        static let keyLabel = MiniMaxLocalizedString(
            english: "Subscription Key",
            russian: "Ключ подписки"
        )
        static let notAdded = MiniMaxLocalizedString(
            english: "Not added",
            russian: "Не добавлен"
        )
        static let storedEnabled = MiniMaxLocalizedString(
            english: "Stored securely · Enabled",
            russian: "Безопасно сохранён · Включён"
        )
        static let storedDisabled = MiniMaxLocalizedString(
            english: "Stored securely · Disabled",
            russian: "Безопасно сохранён · Отключён"
        )
        static let recoveryRequired = MiniMaxLocalizedString(
            english: "Recovery required",
            russian: "Требуется восстановление"
        )
        static let deletionPending = MiniMaxLocalizedString(
            english: "Secure removal pending",
            russian: "Ожидается безопасное удаление"
        )
        static let authenticationFailed = MiniMaxLocalizedString(
            english: "Stored securely · Authentication failed",
            russian: "Безопасно сохранён · Ошибка аутентификации"
        )
        static let subscriptionUnavailable = MiniMaxLocalizedString(
            english: "MiniMax Token Plan subscription is unavailable or expired",
            russian: "Подписка MiniMax Token Plan недоступна или истекла"
        )
        static let subscriptionUnavailableCredential = MiniMaxLocalizedString(
            english: "Stored securely · Subscription unavailable or expired",
            russian: "Безопасно сохранён · Подписка недоступна или истекла"
        )
        static let throttled = MiniMaxLocalizedString(
            english: "Stored securely · Refresh throttled",
            russian: "Безопасно сохранён · Обновление ограничено"
        )
        static let temporaryFailure = MiniMaxLocalizedString(
            english: "Stored securely · Refresh failed temporarily",
            russian: "Безопасно сохранён · Временная ошибка обновления"
        )
        static let unavailable = MiniMaxLocalizedString(
            english: "Stored key unavailable",
            russian: "Сохранённый ключ недоступен"
        )
        static let addKey = MiniMaxLocalizedString(
            english: "Add Key",
            russian: "Добавить ключ"
        )
        static let replaceKey = MiniMaxLocalizedString(
            english: "Replace Key",
            russian: "Заменить ключ"
        )
        static let recoverKey = MiniMaxLocalizedString(
            english: "Recover Key",
            russian: "Восстановить ключ"
        )
        static let enableKey = MiniMaxLocalizedString(
            english: "Enable",
            russian: "Включить"
        )
        static let disableKey = MiniMaxLocalizedString(
            english: "Disable",
            russian: "Отключить"
        )
        static let removeKey = MiniMaxLocalizedString(
            english: "Remove",
            russian: "Удалить"
        )
        static let removeTitle = MiniMaxLocalizedString(
            english: "Remove Subscription Key?",
            russian: "Удалить ключ подписки?"
        )
        static let removeMessage = MiniMaxLocalizedString(
            english: "This securely removes the locally stored MiniMax Subscription Key from Keychain. The MiniMax account remains configured.",
            russian: "Ключ подписки MiniMax будет безопасно удалён из Keychain. Аккаунт MiniMax останется настроенным."
        )
        static let addTitle = MiniMaxLocalizedString(
            english: "Add MiniMax Subscription Key",
            russian: "Добавить ключ подписки MiniMax"
        )
        static let replaceTitle = MiniMaxLocalizedString(
            english: "Replace MiniMax Subscription Key",
            russian: "Заменить ключ подписки MiniMax"
        )
        static let recoverTitle = MiniMaxLocalizedString(
            english: "Recover MiniMax Subscription Key",
            russian: "Восстановить ключ подписки MiniMax"
        )
        static let keyDetails = MiniMaxLocalizedString(
            english: "KEY DETAILS",
            russian: "ДАННЫЕ КЛЮЧА"
        )
        static let keyPlaceholder = MiniMaxLocalizedString(
            english: "Paste Subscription Key",
            russian: "Вставьте ключ подписки"
        )
        static let storageDisclosure = MiniMaxLocalizedString(
            english: "The entered key is written directly to Keychain. Bairometer never reads it back into Settings or exposes it to accessibility.",
            russian: "Введённый ключ записывается напрямую в Keychain. Биирометр не возвращает его в Settings и не передаёт через accessibility."
        )
        static let errorTitle = MiniMaxLocalizedString(
            english: "MiniMax Key Error",
            russian: "Ошибка ключа MiniMax"
        )
        static let invalidAccountError = MiniMaxLocalizedString(
            english: "The MiniMax account is unavailable.",
            russian: "Аккаунт MiniMax недоступен."
        )
        static let credentialExistsError = MiniMaxLocalizedString(
            english: "This MiniMax account already has a Subscription Key.",
            russian: "Для этого аккаунта MiniMax уже сохранён ключ подписки."
        )
        static let emptyCredentialError = MiniMaxLocalizedString(
            english: "Enter a Subscription Key.",
            russian: "Введите ключ подписки."
        )
        static let pendingDeletionError = MiniMaxLocalizedString(
            english: "Secure removal is pending. Retry removal before replacing this key.",
            russian: "Ожидается безопасное удаление. Повторите удаление перед заменой ключа."
        )
        static let unavailableCredentialError = MiniMaxLocalizedString(
            english: "The Subscription Key is unavailable. Reload Settings and try again.",
            russian: "Ключ подписки недоступен. Перезагрузите Settings и повторите попытку."
        )
        static let keychainError = MiniMaxLocalizedString(
            english: "Keychain access failed. No stored key was displayed.",
            russian: "Не удалось обратиться к Keychain. Сохранённый ключ не отображался."
        )
        static let storageError = MiniMaxLocalizedString(
            english: "MiniMax key settings could not be saved.",
            russian: "Не удалось сохранить настройки ключа MiniMax."
        )
    }

    enum Window {
        static let settingsTitle = AppString("window.settings.title", defaultValue: "Bairometer Settings", comment: "Settings window title")
        static let ollamaTitle = AppString("window.ollama.title", defaultValue: "Connect Ollama", comment: "Ollama connection window title")
        static let aboutTitle = AppString("window.about.title", defaultValue: "About Bairometer", comment: "About window title")
    }
}
