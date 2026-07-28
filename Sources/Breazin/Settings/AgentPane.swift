import AppKit
import SwiftUI

struct AgentPane: View {
    @Bindable private var appState = AppState.shared
    @State private var provider = AgentProviderConfiguration.selectedProvider
    @State private var pairedMCPClients: [MCPPairedClient] = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
            SettingsSection(title: "AI Chat") {
                apiKeySection
            }
            SettingsSection(title: "Integrations") {
                mcpSection
            }
        }
        .onAppear {
            provider = AgentProviderConfiguration.selectedProvider
            refreshPairedMCPClients()
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            SettingsToggleRow(
                title: "Allow AI Chat edits",
                subtitle: "Allows reversible edits to the current project. Paid, upload, import, export, and high-impact actions still ask every time.",
                isOn: Binding(
                    get: { ToolCapabilityPolicy.inAppReversibleEditsEnabled },
                    set: { ToolCapabilityPolicy.inAppReversibleEditsEnabled = $0 }
                )
            )

            Divider()

            HStack {
                Text("Chat Provider")
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Spacer()
                Picker("Chat Provider", selection: providerBinding) {
                    ForEach(AgentChatProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            AgentAPIKeyField(
                title: "Anthropic API Key",
                getKeyLabel: "Get Anthropic API key",
                consoleURL: URL(string: "https://console.anthropic.com/settings/keys")!,
                emptyPlaceholder: "sk-ant-…",
                load: AnthropicKeychain.load,
                save: AnthropicKeychain.save,
                remove: AnthropicKeychain.delete,
                onSaved: { selectProvider(.anthropic) }
            )

            Divider()

            AgentAPIKeyField(
                title: "DeepSeek API Key",
                getKeyLabel: "Get DeepSeek API key",
                consoleURL: URL(string: "https://platform.deepseek.com/api_keys")!,
                emptyPlaceholder: "sk-…",
                load: DeepSeekKeychain.load,
                save: DeepSeekKeychain.save,
                remove: DeepSeekKeychain.delete,
                onSaved: { selectProvider(.deepSeek) }
            )
        }
    }

    private var providerBinding: Binding<AgentChatProvider> {
        Binding(
            get: { provider },
            set: { selectProvider($0) }
        )
    }

    private func selectProvider(_ selection: AgentChatProvider) {
        provider = selection
        AgentProviderConfiguration.selectedProvider = selection
    }

    // MARK: - MCP server

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            mcpHeader
            mcpStatusRow
            Divider()
            HStack {
                Text("Pairing creates a separate revocable Keychain-backed token for each MCP client.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                Spacer()
                Button("Copy pairing secret") {
                    Task {
                        let secret = await Task.detached { MCPAccessControl.pairingSecret() }.value
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(secret, forType: .string)
                    }
                }
                Button("Reset pairing") {
                    Task {
                        await appState.resetMCPPairing()
                        refreshPairedMCPClients()
                    }
                }
            }

            if pairedMCPClients.isEmpty {
                Text("No paired clients")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            } else {
                ForEach(pairedMCPClients) { client in
                    HStack {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                            Text(client.name)
                                .font(.system(size: AppTheme.FontSize.sm))
                                .foregroundStyle(AppTheme.Text.primaryColor)
                            Text(client.lastUsedAt.map { "Last used \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not used yet")
                                .font(.system(size: AppTheme.FontSize.xs))
                                .foregroundStyle(AppTheme.Text.tertiaryColor)
                        }
                        Spacer()
                        Toggle(
                            "Allow edits",
                            isOn: Binding(
                                get: { client.capabilities.contains(.editCurrentProject) },
                                set: { enabled in
                                    Task {
                                        await appState.setMCPClientCapability(
                                            .editCurrentProject,
                                            enabled: enabled,
                                            clientID: client.id
                                        )
                                        refreshPairedMCPClients()
                                    }
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .help("Allows reversible edits to the current project. Imports, exports, generation, and high-impact actions remain blocked.")
                        Button("Revoke") {
                            Task {
                                await appState.revokeMCPClient(clientID: client.id)
                                refreshPairedMCPClients()
                            }
                        }
                    }
                }
            }
        }
    }

    private var mcpHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("MCP Server")
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text("Lets external clients like Cursor, Claude Desktop, Claude Code, and Codex edit your timeline.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: openInstructions) {
                    HStack(spacing: AppTheme.Spacing.xxs) {
                        Text("Setup instructions")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                    }
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Accent.link)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .pointerStyle(.link)
            }
        }
    }

    private var mcpStatusRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Circle()
                    .fill((appState.mcpService?.isRunning ?? false) ? AppTheme.Status.successColor : AppTheme.Text.mutedColor)
                    .frame(width: AppTheme.Spacing.smMd, height: AppTheme.Spacing.smMd)

                if appState.mcpService?.isRunning ?? false {
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xxs) {
                        Text("Running on")
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                        Text("127.0.0.1:\(String(MCPService.port))")
                            .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                            .foregroundStyle(AppTheme.Text.primaryColor)
                    }
                } else {
                    Text("Stopped")
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }
            .font(.system(size: AppTheme.FontSize.sm))

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { (appState.mcpService?.isRunning ?? false) },
                    set: { appState.setMCPEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel("MCP Server")
        }
        .padding(.top, AppTheme.Spacing.xs)
    }

    private func openInstructions() {
        HelpWindowController.shared.show(tab: .mcp)
    }

    private func refreshPairedMCPClients() {
        Task {
            pairedMCPClients = await Task.detached { MCPAccessControl.pairedClients() }.value
        }
    }
}

private struct AgentAPIKeyField: View {
    let title: String
    let getKeyLabel: String
    let consoleURL: URL
    let emptyPlaceholder: String
    let load: @Sendable () -> String?
    let save: @Sendable (String) -> Void
    let remove: @Sendable () -> Void
    let onSaved: @MainActor () -> Void

    @State private var hasKey = false
    @State private var maskedKey = ""
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)

                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    Text("Use your own API key for AI chat. Stored in the macOS Keychain.")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: openConsole) {
                        HStack(spacing: AppTheme.Spacing.xxs) {
                            Text(getKeyLabel)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                        }
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Accent.link)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .pointerStyle(.link)
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                SecureField(hasKey ? maskedKey : emptyPlaceholder, text: $draft)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .onSubmit(saveDraft)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.smMd)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .fill(Color.black.opacity(AppTheme.Opacity.muted))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(
                                isFocused ? AppTheme.Border.primaryColor : AppTheme.Border.subtleColor,
                                lineWidth: AppTheme.BorderWidth.thin
                            )
                    )
                    .animation(.easeOut(duration: AppTheme.Anim.hover), value: isFocused)

                trailingControl
            }
        }
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
            Button("Save", action: saveDraft)
                .buttonStyle(.capsule(.prominent, size: .regular))
                .controlSize(.large)
        } else if hasKey {
            Button(action: removeKey) {
                Image(systemName: "trash")
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
            }
            .buttonStyle(.capsule(.secondary, size: .regular))
            .controlSize(.large)
            .help("Remove API key")
        }
    }

    private func refresh() {
        Task { @MainActor in
            let key = await Task.detached(priority: .utility) { load() ?? "" }.value
            applyKey(key)
        }
    }

    private func saveDraft() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        draft = ""
        isFocused = false
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) { save(key) }.value
            applyKey(key)
            onSaved()
        }
    }

    private func removeKey() {
        draft = ""
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) { remove() }.value
            applyKey("")
        }
    }

    private func applyKey(_ key: String) {
        hasKey = !key.isEmpty
        maskedKey = mask(key)
    }

    private func mask(_ key: String) -> String {
        guard key.count > 4 else { return String(repeating: "\u{2022}", count: 32) }
        return String(repeating: "\u{2022}", count: 36) + key.suffix(4)
    }

    private func openConsole() {
        NSWorkspace.shared.open(consoleURL, configuration: .init(), completionHandler: nil)
    }
}
