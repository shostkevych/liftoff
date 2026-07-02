import SwiftUI

/// Reads the bundled CHANGELOG.md and pulls out one version's section.
enum Changelog {
    /// The notes under `## <version>`, up to the next `## ` heading.
    /// Nil when the changelog is missing or has no section for that version.
    static func notes(for version: String) -> String? {
        guard let path = Bundle.main.path(forResource: "CHANGELOG", ofType: "md"),
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }

        var lines: [String] = []
        var inSection = false
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if inSection { break }
                inSection = line.dropFirst(3).trimmingCharacters(in: .whitespaces) == version
                continue
            }
            if inSection { lines.append(line) }
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}

/// Post-update release-notes popup, shown once after the app launches as a
/// newer version than the last run (see AppStore.showWhatsNewIfNeeded).
struct WhatsNewPopup: View {
    let notes: String
    let dismiss: () -> Void

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let path = Bundle.main.path(forResource: "icon", ofType: "png"),
                   let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's New in Liftoff")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Version \(version)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 16)

            ScrollView {
                MarkdownText(markdown: notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)

            HStack {
                Spacer()
                Button("Continue", action: dismiss)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 440)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
    }
}
