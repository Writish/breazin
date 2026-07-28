import SwiftUI

/// Scrollable list of AI generations for the current project.
struct ProjectActivityView: View {
    let entries: [GenerationLogEntry]

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Project Activity")
                    .font(.system(size: AppTheme.FontSize.sm, weight: .medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Spacer()
                if !entries.isEmpty {
                    Text("\(entries.count) generation\(entries.count == 1 ? "" : "s")")
                        .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }

            if entries.isEmpty {
                Text("No generations yet")
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppTheme.Spacing.sm)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(width: 340)
    }

    private func row(_ entry: GenerationLogEntry) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: entry.sfSymbolName)
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.IconSize.xs)
            Text(entry.modelDisplayName)
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: AppTheme.Spacing.xs)
            Text(relativeTime(entry.createdAt))
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.mutedColor)
                .lineLimit(1)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .padding(.horizontal, AppTheme.Spacing.xxs)
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ProjectActivityButton: View {
    @Environment(EditorViewModel.self) var editor
    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented.toggle() }) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
        .help("Project Activity · \(editor.generationLogEntries.count) generations")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ProjectActivityView(entries: editor.generationLogEntries)
        }
    }
}
