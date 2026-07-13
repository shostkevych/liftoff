import SwiftUI

/// Lightweight Markdown renderer for the summary popup.
/// Handles: bold lead lines, (nested) bullets, numbered lists,
/// headings, fenced code blocks, and inline `code`/**bold**/*italic*.
struct MarkdownText: View {
    let markdown: String
    /// Parsed once at init so re-renders don't re-scan the whole markdown string.
    private let blocks: [Block]

    init(markdown: String) {
        self.markdown = markdown
        self.blocks = Self.parse(markdown)
    }

    private enum Block {
        case paragraph(String)
        case heading(String)
        case bullet(level: Int, text: String, marker: String)
        case code(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 14.5))
                .lineSpacing(3)
        case .heading(let text):
            Text(inline(text))
                .font(.system(size: 15.5, weight: .bold))
                .padding(.top, 2)
        case .bullet(let level, let text, let marker):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(inline(text))
                    .font(.system(size: 14.5))
                    .lineSpacing(3)
            }
            .padding(.leading, CGFloat(level) * 16)
        case .code(let code):
            Text(code)
                .font(.system(size: 12.5, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private static func parse(_ markdown: String) -> [Block] {
        var result: [Block] = []
        var codeLines: [String]? = nil

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if let collected = codeLines {
                    result.append(.code(collected.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    codeLines = []
                }
                continue
            }
            if codeLines != nil {
                codeLines?.append(rawLine)
                continue
            }
            if line.isEmpty { continue }

            // 2- or 4-space indents both step one nesting level.
            let leadingSpaces = rawLine.prefix { $0 == " " }.count
            let level = min((leadingSpaces + 2) / 4, 3)

            if line.hasPrefix("#") {
                result.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(.bullet(level: level, text: String(line.dropFirst(2)), marker: "•"))
            } else if let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let number = line[..<match.upperBound].trimmingCharacters(in: .whitespaces)
                result.append(.bullet(level: level, text: String(line[match.upperBound...]), marker: number))
            } else {
                result.append(.paragraph(line))
            }
        }
        if let collected = codeLines, !collected.isEmpty {
            result.append(.code(collected.joined(separator: "\n")))
        }
        return result
    }
}
