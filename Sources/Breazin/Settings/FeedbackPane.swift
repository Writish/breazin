import AppKit
import SwiftUI

struct FeedbackPane: View {
    private enum Activity: Equatable {
        case idle
        case submitting
        case deleting
        case success(String)
        case failure(String)
    }

    @State private var category: FeedbackSubmission.Category = .bug
    @State private var summary = ""
    @State private var details = ""
    @State private var diagnosticsConsent = true
    @State private var followUpConsent = false
    @State private var clientEventID = UUID().uuidString.lowercased()
    @State private var preview: String?
    @State private var previewReviewed = false
    @State private var activity: Activity = .idle
    @State private var hasToken = false
    @State private var maskedToken = ""
    @State private var tokenDraft = ""
    @State private var deviceID = ""
    @State private var showDeletionConfirmation = false
    @FocusState private var tokenFocused: Bool

    private var normalizedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDetails: String {
        details.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftIsValid: Bool {
        (1...160).contains(normalizedSummary.count)
            && (1...4_000).contains(normalizedDetails.count)
    }

    private var canSubmit: Bool {
        hasToken && draftIsValid && preview != nil && previewReviewed && activity != .submitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
            SettingsSection(title: "Device access") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text("Feedback credential")
                                .font(.system(
                                    size: AppTheme.FontSize.md,
                                    weight: AppTheme.FontWeight.medium
                                ))
                                .foregroundStyle(AppTheme.Text.primaryColor)
                            Text("This credential can submit feedback and delete data for this pseudonymous installation. It cannot upload media, access providers, open the operator console, or write GitHub.")
                                .font(.system(size: AppTheme.FontSize.sm))
                                .foregroundStyle(AppTheme.Text.tertiaryColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text(hasToken ? "Connected" : "Token required")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(
                                hasToken
                                    ? AppTheme.Status.successColor
                                    : AppTheme.Text.tertiaryColor
                            )
                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        SecureField(
                            hasToken ? maskedToken : "Paste feedback device token",
                            text: $tokenDraft
                        )
                        .textFieldStyle(.plain)
                        .focused($tokenFocused)
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.smMd)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .fill(Color.black.opacity(AppTheme.Opacity.muted))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .strokeBorder(
                                    AppTheme.Border.subtleColor,
                                    lineWidth: AppTheme.BorderWidth.thin
                                )
                        )
                        .onSubmit(saveToken)

                        if !tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Save", action: saveToken)
                                .buttonStyle(.capsule(.prominent, size: .regular))
                        } else if hasToken {
                            Button(action: removeToken) {
                                Image(systemName: "trash")
                                    .foregroundStyle(AppTheme.Text.secondaryColor)
                            }
                            .buttonStyle(.capsule(.secondary, size: .regular))
                            .help("Remove feedback credential")
                        }
                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text("Device ID")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                        Text(deviceID.isEmpty ? "Loading…" : deviceID)
                            .font(.system(size: AppTheme.FontSize.xs, design: .monospaced))
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(deviceID, forType: .string)
                        }
                        .disabled(deviceID.isEmpty)
                    }

                    Text("Service: \(AppConfiguration.current.feedbackBaseURL.absoluteString)")
                        .font(.system(size: AppTheme.FontSize.xs, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .textSelection(.enabled)
                }
            }

            SettingsSection(title: "Send feedback") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Picker("Category", selection: $category) {
                        ForEach(FeedbackSubmission.Category.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .onChange(of: category) { _, _ in invalidatePreview() }

                    TextField("Short summary", text: $summary)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: summary) { _, _ in invalidatePreview() }

                    TextEditor(text: $details)
                        .font(.system(size: AppTheme.FontSize.sm))
                        .scrollContentBackground(.hidden)
                        .padding(AppTheme.Spacing.sm)
                        .frame(minHeight: AppTheme.Settings.feedbackDescriptionMinHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .fill(Color.black.opacity(AppTheme.Opacity.muted))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .strokeBorder(
                                    AppTheme.Border.subtleColor,
                                    lineWidth: AppTheme.BorderWidth.thin
                                )
                        )
                        .onChange(of: details) { _, _ in invalidatePreview() }

                    SettingsToggleRow(
                        title: "Include diagnostics",
                        subtitle: "Allows only the fields shown in the preview. Raw prompts, project content, paths, media, provider keys, and authorization headers are excluded.",
                        isOn: $diagnosticsConsent
                    )
                    .onChange(of: diagnosticsConsent) { _, _ in invalidatePreview() }

                    SettingsToggleRow(
                        title: "Allow follow-up",
                        subtitle: "Records permission to contact you through a separately configured support channel. No email address is included here.",
                        isOn: $followUpConsent
                    )
                    .onChange(of: followUpConsent) { _, _ in invalidatePreview() }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        Button("Preview data", action: generatePreview)
                            .buttonStyle(.capsule(.secondary, size: .regular))
                            .disabled(!draftIsValid)
                        Button("Submit", action: submit)
                            .buttonStyle(.capsule(.prominent, size: .regular))
                            .disabled(!canSubmit)
                    }

                    if let preview {
                        Text(preview)
                            .font(.system(size: AppTheme.FontSize.xs, design: .monospaced))
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: AppTheme.Settings.feedbackPreviewMinHeight,
                                alignment: .topLeading
                            )
                            .padding(AppTheme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                    .fill(Color.black.opacity(AppTheme.Opacity.muted))
                            )

                        Toggle(
                            "I reviewed this exact payload",
                            isOn: $previewReviewed
                        )
                    }

                    activityMessage
                }
            }

            SettingsSection(title: "Your data") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    Text("Delete feedback, traces, and subject-linked evidence for this pseudonymous installation. A minimal audit tombstone retains only a subject hash, deletion counts, reason, and time.")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Delete my feedback data") {
                        showDeletionConfirmation = true
                    }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .disabled(!hasToken || activity == .deleting)
                }
            }
        }
        .onAppear(perform: refreshCredential)
        .alert(
            "Delete feedback data?",
            isPresented: $showDeletionConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: deleteMyData)
        } message: {
            Text("This removes subject-linked feedback and evidence from the current environment. The audit tombstone cannot reconstruct the deleted content.")
        }
    }

    @ViewBuilder
    private var activityMessage: some View {
        switch activity {
        case .idle:
            EmptyView()
        case .submitting:
            ProgressView("Submitting…")
        case .deleting:
            ProgressView("Deleting…")
        case .success(let message):
            Text(message)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Status.successColor)
        case .failure(let message):
            Text(message)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Status.errorColor)
        }
    }

    private func submission() -> FeedbackSubmission {
        FeedbackSubmission.current(
            clientEventID: clientEventID,
            category: category,
            summary: normalizedSummary,
            description: normalizedDetails,
            consent: .init(
                diagnostics: diagnosticsConsent,
                followUp: followUpConsent
            )
        )
    }

    private func generatePreview() {
        guard draftIsValid else { return }
        let submission = submission()
        Task { @MainActor in
            do {
                preview = try await Task.detached(priority: .userInitiated) {
                    try submission.privacyPreview()
                }.value
                previewReviewed = false
                activity = .idle
            } catch {
                activity = .failure("Could not build the privacy preview.")
            }
        }
    }

    private func invalidatePreview() {
        preview = nil
        previewReviewed = false
        if case .success = activity {
            activity = .idle
        }
    }

    private func submit() {
        guard canSubmit else { return }
        let submission = submission()
        activity = .submitting
        Task { @MainActor in
            do {
                let credentials = await loadCredential()
                let client = try FeedbackClient(
                    token: credentials.token,
                    deviceID: credentials.deviceID
                )
                let receipt = try await client.submit(submission)
                summary = ""
                details = ""
                clientEventID = UUID().uuidString.lowercased()
                preview = nil
                previewReviewed = false
                activity = .success("Submitted as \(receipt.feedbackID).")
            } catch {
                activity = .failure(
                    (error as? LocalizedError)?.errorDescription
                        ?? "Feedback submission failed."
                )
            }
        }
    }

    private func deleteMyData() {
        activity = .deleting
        Task { @MainActor in
            do {
                let credentials = await loadCredential()
                let client = try FeedbackClient(
                    token: credentials.token,
                    deviceID: credentials.deviceID
                )
                let receipt = try await client.deleteMyData(
                    rationale: "User confirmed deletion in Breazin Settings."
                )
                activity = .success(
                    "Deleted \(receipt.deletedFeedback) feedback item(s) and \(receipt.deletedEvidence) evidence item(s)."
                )
            } catch {
                activity = .failure(
                    (error as? LocalizedError)?.errorDescription
                        ?? "Feedback data deletion failed."
                )
            }
        }
    }

    private func refreshCredential() {
        Task { @MainActor in
            let credentials = await loadCredential()
            deviceID = credentials.deviceID
            applyToken(credentials.token ?? "")
        }
    }

    private func saveToken() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        tokenDraft = ""
        tokenFocused = false
        Task { @MainActor in
            let saved = await Task.detached(priority: .userInitiated) {
                FeedbackCredentialStore.saveToken(token)
            }.value
            if saved {
                applyToken(token)
                activity = .success("Feedback credential saved in Keychain.")
            } else {
                activity = .failure("Feedback credential must contain 16–512 characters.")
            }
        }
    }

    private func removeToken() {
        tokenDraft = ""
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) {
                FeedbackCredentialStore.deleteToken()
            }.value
            applyToken("")
            activity = .success("Feedback credential removed from this Mac.")
        }
    }

    private func applyToken(_ token: String) {
        hasToken = !token.isEmpty
        maskedToken = token.isEmpty
            ? ""
            : String(repeating: "•", count: 24) + token.suffix(4)
    }

    private func loadCredential() async -> (token: String?, deviceID: String) {
        await Task.detached(priority: .utility) {
            (
                FeedbackCredentialStore.loadToken(),
                FeedbackCredentialStore.deviceID()
            )
        }.value
    }
}

private extension FeedbackSubmission.Category {
    var label: String {
        switch self {
        case .bug: "Bug"
        case .feature: "Feature request"
        case .usability: "Usability"
        case .quality: "Quality"
        case .other: "Other"
        }
    }
}
