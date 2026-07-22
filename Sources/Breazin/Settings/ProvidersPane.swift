import AppKit
import SwiftUI

struct ProvidersPane: View {
    @State private var hasVolcengineKey = false
    @State private var maskedKey = ""
    @State private var draft = ""
    @State private var hasBrokerToken = false
    @State private var maskedBrokerToken = ""
    @State private var brokerDraft = ""
    @FocusState private var keyFocused: Bool
    @FocusState private var brokerTokenFocused: Bool

    private let volcengineConsole = URL(string: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey")!

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
            SettingsSection(title: "Active") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    providerHeader(
                        title: "Volcengine Ark",
                        detail: "Doubao Seedream 5.0 Pro and Doubao Seedance 2.0. Usage is billed directly by Volcengine."
                    )
                    HStack(spacing: AppTheme.Spacing.sm) {
                        SecureField(hasVolcengineKey ? maskedKey : "Paste Volcengine API key", text: $draft)
                            .textFieldStyle(.plain)
                            .focused($keyFocused)
                            .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.vertical, AppTheme.Spacing.smMd)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .fill(Color.black.opacity(AppTheme.Opacity.muted))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
                            )
                            .onSubmit(save)

                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            Button("Save", action: save)
                                .buttonStyle(.capsule(.prominent, size: .regular))
                        } else if hasVolcengineKey {
                            Button(action: remove) {
                                Image(systemName: "trash")
                                    .foregroundStyle(AppTheme.Text.secondaryColor)
                            }
                            .buttonStyle(.capsule(.secondary, size: .regular))
                            .help("Remove API key")
                        }
                    }

                    Button(action: { NSWorkspace.shared.open(volcengineConsole) }) {
                        Label("Open Volcengine API key console", systemImage: "arrow.up.right")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Accent.link)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)

                    Text("The key is stored in the macOS Keychain and is sent only to ark.cn-beijing.volces.com.")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }

            SettingsSection(title: "Temporary media") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Breazin upload Broker")
                                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                                .foregroundStyle(AppTheme.Text.primaryColor)
                            Text("Uploads standardized reference media directly to temporary R2 storage. The Broker never receives provider API keys or generation requests.")
                                .font(.system(size: AppTheme.FontSize.sm))
                                .foregroundStyle(AppTheme.Text.tertiaryColor)
                        }
                        Spacer()
                        Text(hasBrokerToken ? "Connected" : "Token required")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(hasBrokerToken ? AppTheme.Status.successColor : AppTheme.Text.tertiaryColor)
                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        SecureField(hasBrokerToken ? maskedBrokerToken : "Paste upload Broker token", text: $brokerDraft)
                            .textFieldStyle(.plain)
                            .focused($brokerTokenFocused)
                            .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.vertical, AppTheme.Spacing.smMd)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .fill(Color.black.opacity(AppTheme.Opacity.muted))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
                            )
                            .onSubmit(saveBrokerToken)

                        if !brokerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Save", action: saveBrokerToken)
                                .buttonStyle(.capsule(.prominent, size: .regular))
                        } else if hasBrokerToken {
                            Button(action: removeBrokerToken) {
                                Image(systemName: "trash")
                                    .foregroundStyle(AppTheme.Text.secondaryColor)
                            }
                            .buttonStyle(.capsule(.secondary, size: .regular))
                            .help("Remove Broker token")
                        }
                    }

                    Text("The token is stored in the macOS Keychain. R2 Access Key and Secret stay in Cloudflare Worker secrets.")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }

            SettingsSection(title: "Planned") {
                plannedProvider(
                    title: "OpenAI GPT Image 2",
                    auth: "OAuth",
                    detail: "Reserved behind the same provider contract. The delegated authorization flow will be confirmed before implementation."
                )
                Divider().overlay(AppTheme.Border.subtleColor)
                plannedProvider(
                    title: "Midjourney",
                    auth: "Discord bot",
                    detail: "Reserved as an asynchronous bot adapter with external job polling and result ingestion."
                )
            }
        }
        .onAppear(perform: refresh)
    }

    private func providerHeader(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(detail)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            Spacer()
            Text(hasVolcengineKey ? "Connected" : "API key required")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(hasVolcengineKey ? AppTheme.Status.successColor : AppTheme.Text.tertiaryColor)
        }
    }

    private func plannedProvider(title: String, auth: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(detail)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            Spacer()
            Text(auth)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            Text("Planned")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func refresh() {
        Task { @MainActor in
            let credentials = await Task.detached(priority: .utility) {
                (
                    ProviderCredentialStore.loadAPIKey(for: ProviderModelCatalog.volcengineArk) ?? "",
                    ProviderCredentialStore.loadUploadBrokerToken() ?? ""
                )
            }.value
            apply(credentials.0)
            applyBrokerToken(credentials.1)
        }
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        draft = ""
        keyFocused = false
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) {
                ProviderCredentialStore.saveAPIKey(key, for: ProviderModelCatalog.volcengineArk)
            }.value
            apply(key)
        }
    }

    private func remove() {
        draft = ""
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) {
                ProviderCredentialStore.deleteAPIKey(for: ProviderModelCatalog.volcengineArk)
            }.value
            apply("")
        }
    }

    private func apply(_ key: String) {
        hasVolcengineKey = !key.isEmpty
        maskedKey = key.isEmpty ? "" : String(repeating: "•", count: 32) + key.suffix(4)
    }

    private func saveBrokerToken() {
        let token = brokerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        brokerDraft = ""
        brokerTokenFocused = false
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) {
                ProviderCredentialStore.saveUploadBrokerToken(token)
            }.value
            applyBrokerToken(token)
        }
    }

    private func removeBrokerToken() {
        brokerDraft = ""
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) {
                ProviderCredentialStore.deleteUploadBrokerToken()
            }.value
            applyBrokerToken("")
        }
    }

    private func applyBrokerToken(_ token: String) {
        hasBrokerToken = !token.isEmpty
        maskedBrokerToken = token.isEmpty ? "" : String(repeating: "•", count: 24) + token.suffix(4)
    }
}
