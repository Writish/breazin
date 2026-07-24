import AppKit
import SwiftUI

struct AgentMessageView: View {
    let message: AgentMessage
    let toolResults: [String: ToolRunResult]
    @State private var isHovering = false

    var body: some View {
        switch message.role {
        case .user:   userBody
        case .assistant: assistantBody
        case .system: systemBody
        }
    }

    @ViewBuilder
    private var systemBody: some View {
        let texts = message.blocks.compactMap { block -> String? in
            if case let .text(s) = block { return s }
            return nil
        }
        if !texts.isEmpty {
            HStack {
                Spacer(minLength: 0)
                Text(texts.joined(separator: "\n"))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
    }

    private var copyableText: String {
        message.blocks
            .compactMap { if case let .text(s) = $0 { return s } else { return nil } }
            .joined(separator: "\n\n")
    }

    @ViewBuilder
    private var userBody: some View {
        let texts = message.blocks.compactMap { block -> String? in
            if case let .text(s) = block { return s }
            return nil
        }
        if !texts.isEmpty {
            HStack {
                Spacer(minLength: 48)
                Text(texts.joined(separator: "\n"))
                    .font(.body)
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .lineSpacing(3)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.smMd)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .fill(Color.white.opacity(AppTheme.Opacity.faint))
                    )
                    .textSelection(.enabled)
            }
        }
        // Tool-result user messages render merged into the preceding assistant row.
    }

    @ViewBuilder
    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    MarkdownText(text: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .toolUse(let id, let name, let inputJSON):
                    ToolRunRow(name: name, inputJSON: inputJSON, result: toolResults[id])
                case .toolResult:
                    EmptyView()
                }
            }
            if !copyableText.isEmpty {
                CopyMessageButton(text: copyableText)
                    .opacity(isHovering ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: AppTheme.Anim.hover), value: isHovering)
    }
}

private struct CopyMessageButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "Copied" : "Copy")
            }
            .font(.system(size: AppTheme.FontSize.xs))
            .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
        .buttonStyle(.plain)
        .help("Copy message")
    }
}

struct ToolRunResult {
    let content: [ToolResult.Block]
    let isError: Bool
}

private struct ToolRunRow: View {
    let name: String
    let inputJSON: String
    let result: ToolRunResult?
    @State private var expanded = false

    private var isRunning: Bool { result == nil }
    private var generationJobID: String? {
        result?.content.compactMap {
            if case .generationJob(let id) = $0 { return id }
            return nil
        }.first
    }
    private var statusIcon: String {
        guard let result else { return "circle.dotted" }
        return result.isError ? "xmark.circle.fill" : "checkmark.circle.fill"
    }
    private var statusTint: Color {
        guard let result else { return AppTheme.Text.mutedColor }
        return result.isError ? .red.opacity(AppTheme.Opacity.prominent) : AppTheme.Text.tertiaryColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if let generationJobID {
                        GenerationJobInlineStatus(jobID: generationJobID)
                    } else if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: AppTheme.Spacing.md, height: AppTheme.Spacing.md)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: AppTheme.FontSize.xs))
                            .foregroundStyle(statusTint)
                    }
                    Text(name)
                        .font(.system(size: AppTheme.FontSize.sm, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .opacity(isRunning ? 0.7 : 1.0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: AppTheme.FontSize.micro, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    argsSection
                    if let result { resultSection(result) }
                }
                .font(.system(size: AppTheme.FontSize.xs, design: .monospaced))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(Color.white.opacity(AppTheme.Opacity.subtle))
                )
                .textSelection(.enabled)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var argsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("args").font(.system(size: AppTheme.FontSize.xxs)).foregroundStyle(AppTheme.Text.mutedColor)
            Text(prettyPrinted(inputJSON))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func resultSection(_ r: ToolRunResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(r.isError ? "error" : "result")
                .font(.system(size: AppTheme.FontSize.xxs))
                .foregroundStyle(r.isError ? .red.opacity(AppTheme.Opacity.prominent) : AppTheme.Text.mutedColor)
            ForEach(Array(r.content.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let s):
                    Text(s).frame(maxWidth: .infinity, alignment: .leading)
                case .image(let base64, _):
                    ToolResultImageView(base64: base64)
                case .generationJob(let id):
                    GenerationJobDetailView(jobID: id)
                }
            }
        }
    }

    private func prettyPrinted(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let s = String(data: pretty, encoding: .utf8),
              !s.isEmpty, s != "{}" else {
            return "(no args)"
        }
        return s
    }
}

private struct GenerationJobInlineStatus: View {
    let jobID: String
    @State private var job: GenerationJobRecord?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if job?.state.isActivelyProcessing == true {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }
            Text(statusLabel)
                .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                .foregroundStyle(statusColor)
        }
        .task(id: jobID) { await observeJob() }
    }

    private var statusLabel: String {
        guard let job else { return "Preparing" }
        return switch job.state {
        case .preparing: "Preparing"
        case .submitting: job.kind == .image ? "Waiting for provider" : "Submitting"
        case .queued: "Queued"
        case .running: "Running"
        case .downloading: "Downloading"
        case .finalizing: "Finalizing"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .needsAttention: "Needs attention"
        }
    }

    private var statusIcon: String {
        switch job?.state {
        case .succeeded: "checkmark.circle.fill"
        case .failed, .cancelled, .needsAttention: "xmark.circle.fill"
        default: "circle.dotted"
        }
    }

    private var statusColor: Color {
        switch job?.state {
        case .succeeded: .green.opacity(AppTheme.Opacity.prominent)
        case .failed, .cancelled, .needsAttention: .red.opacity(AppTheme.Opacity.prominent)
        default: AppTheme.Text.tertiaryColor
        }
    }

    private func observeJob() async {
        while !Task.isCancelled {
            job = try? await GenerationJobStore.shared.job(id: jobID)
            guard job?.state.isActivelyProcessing == true else { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

private struct GenerationJobDetailView: View {
    let jobID: String
    @State private var job: GenerationJobRecord?

    var body: some View {
        Group {
            if let job {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    detail("Provider", value: job.providerID)
                    if let providerJobID = job.providerJobID {
                        detail("Task", value: providerJobID)
                    }
                    detail("Status", value: job.state.rawValue)
                    if let providerUpdatedAt = job.providerDetails?.providerUpdatedAt {
                        detail("Provider updated", value: providerUpdatedAt.formatted())
                    }
                    if let usage = job.providerDetails?.usage {
                        if let generatedImages = usage.generatedImages {
                            detail("Generated images", value: String(generatedImages))
                        }
                        if let tokens = usage.completionTokens ?? usage.outputTokens {
                            detail("Output tokens", value: String(tokens))
                        }
                        if let totalTokens = usage.totalTokens {
                            detail("Total tokens", value: String(totalTokens))
                        }
                    }
                    if let output = job.providerDetails?.output {
                        let summary = [
                            output.resolution,
                            output.ratio,
                            output.durationSeconds.map { "\($0.formatted())s" },
                            output.framesPerSecond.map { "\($0) fps" },
                        ].compactMap { $0 }.joined(separator: " · ")
                        if !summary.isEmpty { detail("Output", value: summary) }
                    }
                    if let code = job.errorCode {
                        detail("Error", value: code)
                    }
                    if let message = job.errorMessage ?? job.providerDetails?.errorMessage {
                        Text(message).foregroundStyle(.red.opacity(AppTheme.Opacity.prominent))
                    }
                    if let result = job.resultURLs.first.flatMap(URL.init(string:)) {
                        Link("Open provider result URL", destination: result)
                    }
                }
            } else {
                Text("Generation job metadata unavailable.")
            }
        }
        .task(id: jobID) { await observeJob() }
    }

    @ViewBuilder
    private func detail(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
            Text("\(label):").foregroundStyle(AppTheme.Text.mutedColor)
            Text(value).textSelection(.enabled)
        }
    }

    private func observeJob() async {
        while !Task.isCancelled {
            job = try? await GenerationJobStore.shared.job(id: jobID)
            guard job?.state.isActivelyProcessing == true else { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

private struct ToolResultImageView: View {
    let base64: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: AppTheme.ComponentSize.toolImagePreviewMaxHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            } else {
                Text("(image payload)").foregroundStyle(AppTheme.Text.mutedColor)
            }
        }
        .task(id: base64) {
            guard image == nil else { return }
            let data = await Task.detached { Data(base64Encoded: base64) }.value
            if let data { image = NSImage(data: data) }
        }
    }
}
