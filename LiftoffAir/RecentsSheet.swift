import SwiftUI

/// Bottom sheet of the desktop's recent projects that aren't open yet.
/// Tapping one opens it on the Mac and navigates into its terminal.
struct RecentsSheet: View {
    let client: CompanionClient
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    if client.recents.isEmpty {
                        Text("No recent projects.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    ForEach(client.recents) { recent in
                        Button {
                            client.openRecent(recent.path)
                        } label: {
                            row(recent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Recent Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done", action: dismiss)
            }
        }
        .tint(.brand)
        .preferredColorScheme(.dark)
        .onAppear { client.loadRecents() }
    }

    private func row(_ recent: CompanionClient.Recent) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(recent.color.flatMap { Color(hex: $0) } ?? .secondary)
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(recent.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(recent.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.35)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
