import AppKit
import SwiftUI

struct MCPInstructionsPane: View {
    private var mcpEndpoint: String { "http://127.0.0.1:\(MCPService.port)/mcp" }
    private var pairingEndpoint: String { "http://127.0.0.1:\(MCPService.port)/pair" }
    private var pairingCommand: String {
        """
        read -s BREAZIN_MCP_PAIRING_SECRET
        curl --fail-with-body \(pairingEndpoint) \\
          -H 'Content-Type: application/json' \\
          -H "Authorization: Bearer ${BREAZIN_MCP_PAIRING_SECRET}" \\
          --data '{"clientName":"My MCP client"}'
        unset BREAZIN_MCP_PAIRING_SECRET
        """
    }
    private var mcpServiceName: String { AppConfiguration.current.mcpServiceName }

    private var claudeCodeCommand: String {
        "claude mcp add --transport http -H \"Authorization: Bearer <paired-client-token>\" \(mcpServiceName) \(mcpEndpoint)"
    }

    private var cursorJSONConfig: String {
        """
        {
          "mcpServers": {
            "\(mcpServiceName)": {
              "type": "http",
              "url": "\(mcpEndpoint)",
              "headers": {
                "Authorization": "Bearer <paired-client-token>"
              }
            }
          }
        }
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                Text("Connect an external agent to inspect and edit the open Breazin project.")
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsGroup(title: "Server URL") {
                    endpointRow
                }

                SettingsGroup(title: "Pair this client") {
                    CodeBlockView(
                        content: pairingCommand,
                        fontSize: AppTheme.FontSize.sm,
                        foreground: AppTheme.Text.primaryColor,
                        verticalPadding: AppTheme.Spacing.smMd
                    )
                    Text("Run once while the local MCP server is enabled. Copy accessToken from the response into only that client. Breazin stores only its digest; revoke the client from Settings > Agent.")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }

                SettingsGroup(title: "Connect an agent") {
                    agentList
                }
            }
            .frame(maxWidth: AppTheme.Settings.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, AppTheme.Spacing.xlXxl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var endpointRow: some View {
        CodeBlockView(
            content: mcpEndpoint,
            fontSize: AppTheme.FontSize.sm,
            foreground: AppTheme.Text.primaryColor,
            verticalPadding: AppTheme.Spacing.smMd
        )
    }

    private var agentList: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            claudeDesktopSection
            agentDivider
            claudeCodeSection
            agentDivider
            codexSection
            agentDivider
            cursorSection
        }
    }

    private var cursorSection: some View {
        agentSection(
            .cursor,
            name: "Cursor",
            description: "Add the paired client token to Cursor's MCP configuration."
        ) {
            ManualFallback(
                intro: "Add this configuration to ~/.cursor/mcp.json.",
                code: cursorJSONConfig
            )
        }
    }

    private var claudeDesktopSection: some View {
        agentSection(
            .claude,
            name: "Claude Desktop",
            description: "Configure the local HTTP endpoint and paired client Authorization header."
        ) {
            Text("Use the same URL and Authorization header shown above; do not reuse another client's token.")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
    }

    private var claudeCodeSection: some View {
        agentSection(
            .claude,
            name: "Claude Code",
            description: "Run this command once in Terminal."
        ) {
            CodeBlockView(content: claudeCodeCommand)
        }
    }

    private var codexSection: some View {
        agentSection(
            .codex,
            name: "Codex",
            description: "The installed Codex CLI only accepts local stdio servers through `codex mcp add`."
        ) {
            Text("Do not use an unauthenticated bridge. Connect Breazin only after Codex supports authenticated HTTP MCP configuration.")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var agentDivider: some View {
        Divider().overlay(AppTheme.Border.subtleColor)
    }

    private func agentSection<Details: View>(
        _ agent: SkillExternalAgent,
        name: String,
        description: String,
        @ViewBuilder details: () -> Details
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                agentIdentity(agent: agent, name: name, description: description)
            }
            details()
        }
        .padding(.vertical, AppTheme.Spacing.mdLg)
    }

    private func agentIdentity(agent: SkillExternalAgent, name: String, description: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ExternalAgentLogo(agent: agent, size: AppTheme.IconSize.lgXl)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(name)
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(description)
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

private struct CodeBlockView: View {
    let content: String
    var fontSize = AppTheme.FontSize.xs
    var foreground = AppTheme.Text.secondaryColor
    var verticalPadding = AppTheme.Spacing.md

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            Text(content)
                .font(.system(size: fontSize, weight: AppTheme.FontWeight.regular, design: .monospaced))
                .foregroundStyle(foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            CopyButton(value: content)
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.vertical, verticalPadding)
        .themedSurface(AppTheme.Background.raisedColor, cornerRadius: AppTheme.Radius.sm)
    }
}

private struct ManualFallback: View {
    let intro: String
    let code: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Button(action: toggle) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.regular))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Manual setup")
                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                }
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(intro)
                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                    CodeBlockView(content: code)
                }
            }
        }
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: AppTheme.Anim.hover)) {
            expanded.toggle()
        }
    }
}

private struct CopyButton: View {
    private static let feedbackDuration: Duration = .seconds(1.4)

    let value: String
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(copied ? AppTheme.Text.primaryColor : AppTheme.Text.secondaryColor)
                .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy")
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: Self.feedbackDuration)
            copied = false
        }
    }
}

#Preview {
    MCPInstructionsPane()
        .frame(width: AppTheme.Settings.contentMaxWidth, height: AppTheme.Settings.skillDetailMinHeight)
        .background(AppTheme.Background.surfaceColor)
}
