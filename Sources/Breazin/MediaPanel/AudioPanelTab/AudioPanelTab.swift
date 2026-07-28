import SwiftUI

struct AudioPanelTab: View {
    var body: some View {
        ContentUnavailableView(
            "Audio Generation Unavailable",
            systemImage: "waveform.badge.exclamationmark",
            description: Text("Configure an audio generation provider after an adapter is installed.")
        )
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Background.surfaceColor)
    }
}
