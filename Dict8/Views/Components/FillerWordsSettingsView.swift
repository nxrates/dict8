import SwiftUI

struct FillerWordChip: View {
    let word: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.caption)
                .foregroundColor(.primary)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
    }
}

struct FillerWordsSettingsView: View {
    @AppStorage("RemoveFillerWords") private var removeFillerWords = true
    @StateObject private var fillerWordManager = FillerWordManager.shared
    @State private var newWord = ""
    @State private var showDuplicateAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $removeFillerWords) {
                    Text("Remove filler words")
                }
                InfoTip("Automatically remove filler words like 'uh', 'um', 'hmm' from transcriptions.")
            }

            if removeFillerWords {
                HStack(spacing: 8) {
                    TextField("Add filler word", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWord() }
                    Button(action: addWord) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !fillerWordManager.fillerWords.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(fillerWordManager.fillerWords, id: \.self) { word in
                            FillerWordChip(word: word) {
                                withAnimation { fillerWordManager.removeWord(word) }
                            }
                        }
                    }
                }
            }
        }
        .alert("Duplicate Word", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This filler word is already in the list.")
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if fillerWordManager.addWord(trimmed) {
            newWord = ""
        } else {
            showDuplicateAlert = true
        }
    }
}
