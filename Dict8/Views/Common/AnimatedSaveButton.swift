import SwiftUI
import UniformTypeIdentifiers

struct AnimatedSaveButton: View {
    let textToSave: String
    @State private var isSaved = false

    var body: some View {
        Menu {
            Button("Save as TXT") { saveFile(as: .plainText, extension: "txt") }
            Button("Save as MD") { saveFile(as: .text, extension: "md") }
        } label: {
            Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "checkmark" : "square.and.arrow.down")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .opacity(isSaved ? 0.7 : 1)
        .animation(.easeInOut(duration: 0.2), value: isSaved)
    }

    private func saveFile(as contentType: UTType, extension ext: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "\(generateFileName()).\(ext)"
        panel.title = "Save Transcription"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = ext == "md" ? "# Transcription\n\n**Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n\n\(textToSave)" : textToSave
            try content.write(to: url, atomically: true, encoding: .utf8)
            withAnimation { isSaved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { isSaved = false } }
        } catch {
            print("Failed to save file: \(error.localizedDescription)")
        }
    }

    private func generateFileName() -> String {
        let words = textToSave.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let selected = Array(words.prefix(min(words.count, 8)))
        guard !selected.isEmpty else { return "transcription" }
        let name = selected.joined(separator: "-").lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return name.isEmpty ? "transcription" : String(name.prefix(50))
    }
}
