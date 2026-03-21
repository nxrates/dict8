import SwiftUI
import SwiftData

enum SortMode: String { case originalAsc, originalDesc, replacementAsc, replacementDesc }
enum SortColumn { case original, replacement }
enum VocabularySortMode: String { case wordAsc, wordDesc }

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wordReplacements: [WordReplacement]
    @Query private var vocabularyWords: [VocabularyWord]
    @ObservedObject var whisperPrompt: WhisperPrompt

    @State private var selectedSection: DictionarySection = .replacements

    enum DictionarySection: String, CaseIterable {
        case replacements = "Word Replacements"
        case spellings = "Vocabulary"

        var description: String {
            switch self {
            case .spellings: return "Add words to help Dict8 recognize them properly"
            case .replacements: return "Automatically replace specific words/phrases with custom formatted text"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Section", selection: $selectedSection) {
                    ForEach(DictionarySection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button { DictionaryImportExportService.shared.importDictionary(into: modelContext) } label: {
                    Image(systemName: "square.and.arrow.down")
                }.buttonStyle(.bordered).help("Import vocabulary and word replacements")

                Button { DictionaryImportExportService.shared.exportDictionary(from: modelContext) } label: {
                    Image(systemName: "square.and.arrow.up")
                }.buttonStyle(.bordered).help("Export vocabulary and word replacements")
            }
            .padding()

            Divider()

            Text(selectedSection.description).font(.caption).foregroundStyle(.secondary).padding()

            switch selectedSection {
            case .spellings: vocabularyContent
            case .replacements: replacementsContent
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Vocabulary

    @State private var newWord = ""
    @State private var vocabShowAlert = false
    @State private var vocabAlertMessage = ""
    @State private var vocabSortMode: VocabularySortMode = .wordAsc

    private var sortedVocabulary: [VocabularyWord] {
        vocabularyWords.sorted { vocabSortMode == .wordAsc ? $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending : $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedDescending }
    }

    private var vocabularyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add words to help Dict8 recognize them properly. (Requires AI enhancement)", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Add word to vocabulary", text: $newWord).textFieldStyle(.roundedBorder).onSubmit { addWords() }
                if !newWord.isEmpty {
                    Button { addWords() } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.borderless).disabled(newWord.isEmpty)
                }
            }

            if !vocabularyWords.isEmpty {
                Button {
                    vocabSortMode = vocabSortMode == .wordAsc ? .wordDesc : .wordAsc
                    UserDefaults.standard.set(vocabSortMode.rawValue, forKey: "vocabularySortMode")
                } label: {
                    HStack(spacing: 4) {
                        Text("Vocabulary Words (\(vocabularyWords.count))").font(.caption).foregroundStyle(.secondary)
                        Image(systemName: vocabSortMode == .wordAsc ? "chevron.up" : "chevron.down").font(.caption).foregroundColor(.accentColor)
                    }
                }.buttonStyle(.plain)

                ScrollView {
                    FlowLayout(spacing: 8) {
                        ForEach(sortedVocabulary) { item in
                            HStack(spacing: 6) {
                                Text(item.word).font(.body).lineLimit(1)
                                HoverIconButton(icon: "xmark.circle.fill", hoverColor: .red, action: { removeVocab(item) }, help: "Remove word")
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .alert("Vocabulary", isPresented: $vocabShowAlert) { Button("OK", role: .cancel) {} } message: { Text(vocabAlertMessage) }
    }

    private func addWords() {
        let parts = newWord.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        if parts.count == 1, let word = parts.first {
            if vocabularyWords.contains(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) { vocabAlertMessage = "'\(word)' already exists"; vocabShowAlert = true; return }
            addVocab(word); newWord = ""; return
        }
        for word in parts where !vocabularyWords.contains(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) { addVocab(word) }
        newWord = ""
    }

    private func addVocab(_ word: String) {
        let item = VocabularyWord(word: word.trimmingCharacters(in: .whitespacesAndNewlines))
        modelContext.insert(item)
        do { try modelContext.save() } catch { modelContext.delete(item); vocabAlertMessage = "Failed: \(error.localizedDescription)"; vocabShowAlert = true }
    }

    private func removeVocab(_ word: VocabularyWord) {
        modelContext.delete(word)
        do { try modelContext.save() } catch { modelContext.rollback(); vocabAlertMessage = "Failed: \(error.localizedDescription)"; vocabShowAlert = true }
    }

    // MARK: - Word Replacements

    @State private var originalWord = ""
    @State private var replacementWord = ""
    @State private var replShowAlert = false
    @State private var replAlertMessage = ""
    @State private var sortMode: SortMode = .originalAsc
    @State private var editingReplacement: WordReplacement?
    @State private var showInfoPopover = false

    private var sortedReplacements: [WordReplacement] {
        wordReplacements.sorted {
            let (key, asc): (KeyPath<WordReplacement, String>, Bool) = {
                switch sortMode {
                case .originalAsc: return (\.originalText, true)
                case .originalDesc: return (\.originalText, false)
                case .replacementAsc: return (\.replacementText, true)
                case .replacementDesc: return (\.replacementText, false)
                }
            }()
            let cmp = $0[keyPath: key].localizedCaseInsensitiveCompare($1[keyPath: key])
            return asc ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }

    private func toggleSort(for col: SortColumn) {
        sortMode = col == .original ? (sortMode == .originalAsc ? .originalDesc : .originalAsc) : (sortMode == .replacementAsc ? .replacementDesc : .replacementAsc)
        UserDefaults.standard.set(sortMode.rawValue, forKey: "wordReplacementSortMode")
    }

    private var replacementsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { showInfoPopover.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.bordered).popover(isPresented: $showInfoPopover) { WordReplacementInfoPopover() }
                Text("Define word replacements to automatically replace specific words or phrases").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("Original text (use commas for multiple)", text: $originalWord).textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Replacement text", text: $replacementWord).textFieldStyle(.roundedBorder).onSubmit { addReplacement() }
                if !originalWord.isEmpty || !replacementWord.isEmpty {
                    Button { addReplacement() } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.borderless).disabled(originalWord.isEmpty || replacementWord.isEmpty)
                }
            }
            if !wordReplacements.isEmpty {
                HStack(spacing: 8) {
                    sortButton("Original", col: .original, active: sortMode == .originalAsc || sortMode == .originalDesc, asc: sortMode == .originalAsc)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    sortButton("Replacement", col: .replacement, active: sortMode == .replacementAsc || sortMode == .replacementDesc, asc: sortMode == .replacementAsc)
                }
                List {
                    ForEach(sortedReplacements) { r in
                        ReplacementRow(original: r.originalText, replacement: r.replacementText, onDelete: { removeReplacement(r) }, onEdit: { editingReplacement = r })
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .sheet(item: $editingReplacement) { EditReplacementSheet(replacement: $0, modelContext: modelContext) }
        .alert("Word Replacement", isPresented: $replShowAlert) { Button("OK", role: .cancel) {} } message: { Text(replAlertMessage) }
    }

    private func sortButton(_ title: String, col: SortColumn, active: Bool, asc: Bool) -> some View {
        Button { toggleSort(for: col) } label: {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if active { Image(systemName: asc ? "chevron.up" : "chevron.down").font(.caption).foregroundColor(.accentColor) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
    }

    private func addReplacement() {
        let orig = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let repl = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = orig.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !tokens.isEmpty, !repl.isEmpty else { return }
        for existing in wordReplacements {
            let existingTokens = existing.originalText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            for token in tokens where existingTokens.contains(token.lowercased()) {
                replAlertMessage = "'\(token)' already exists"; replShowAlert = true; return
            }
        }
        let item = WordReplacement(originalText: orig, replacementText: repl)
        modelContext.insert(item)
        do { try modelContext.save(); originalWord = ""; replacementWord = "" }
        catch { modelContext.delete(item); replAlertMessage = "Failed: \(error.localizedDescription)"; replShowAlert = true }
    }

    private func removeReplacement(_ r: WordReplacement) {
        modelContext.delete(r)
        do { try modelContext.save() }
        catch { modelContext.rollback(); replAlertMessage = "Failed: \(error.localizedDescription)"; replShowAlert = true }
    }
}

// MARK: - Info Popover

private struct WordReplacementInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to use Word Replacements").font(.headline)
            Text("Separate multiple originals with commas:").font(.caption).foregroundStyle(.secondary)
            Text("dictate, dikt8, dict-eight").font(.body).padding()
                .frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.1)).cornerRadius(8)
            Divider()
            Text("Examples").font(.caption).foregroundStyle(.secondary)
            exampleRow("my website link", "https://example.com")
            exampleRow("dictate, dikt8", "Dict8")
        }.padding().frame(width: 380)
    }

    private func exampleRow(_ from: String, _ to: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading) { Text("Original:").font(.caption).foregroundStyle(.secondary); Text(from) }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            VStack(alignment: .leading) { Text("Replacement:").font(.caption).foregroundStyle(.secondary); Text(to) }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.06)).cornerRadius(8)
    }
}

// MARK: - Row

struct ReplacementRow: View {
    let original: String, replacement: String, onDelete: () -> Void, onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(original).font(.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Text(replacement).font(.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                HoverIconButton(icon: "pencil.circle.fill", hoverColor: .accentColor, action: onEdit, help: "Edit")
                HoverIconButton(icon: "xmark.circle.fill", hoverColor: .red, action: onDelete, help: "Remove")
            }
        }.padding(.vertical, 8)
    }
}

// MARK: - Shared hover icon button

struct HoverIconButton: View {
    let icon: String, hoverColor: Color, action: () -> Void
    var help: String = ""
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHovered ? hoverColor : .secondary)
        }
        .buttonStyle(.borderless).help(help)
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { isHovered = h } }
    }
}

// MARK: - Edit Replacement Sheet

struct EditReplacementSheet: View {
    let replacement: WordReplacement
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var originalWord: String
    @State private var replacementWord: String
    @State private var showAlert = false
    @State private var alertMessage = ""

    init(replacement: WordReplacement, modelContext: ModelContext) {
        self.replacement = replacement; self.modelContext = modelContext
        _originalWord = State(initialValue: replacement.originalText)
        _replacementWord = State(initialValue: replacement.replacementText)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Text("Edit Word Replacement").font(.headline)
                Spacer()
                Button("Save") { saveChanges() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                    .keyboardShortcut(.return, modifiers: [])
            }.padding()

            Divider()

            Form {
                Section("Original Text") {
                    TextField("Enter word or phrase to replace (use commas for multiple)", text: $originalWord)
                        .textFieldStyle(.roundedBorder)
                }
                Section("Replacement Text") {
                    TextEditor(text: $replacementWord).font(.body).frame(height: 100)
                }
            }.formStyle(.grouped)
        }
        .frame(width: 460, height: 360)
        .alert("Word Replacement", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
    }

    private func saveChanges() {
        let newOriginal = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let newReplacement = replacementWord
        let tokens = newOriginal.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !tokens.isEmpty, !newReplacement.isEmpty else { return }

        let newTokensPairs = tokens.map { (original: $0, lowercased: $0.lowercased()) }
        let descriptor = FetchDescriptor<WordReplacement>()
        if let allReplacements = try? modelContext.fetch(descriptor) {
            for existing in allReplacements where existing.id != replacement.id {
                let existingTokens = existing.originalText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
                for tokenPair in newTokensPairs where existingTokens.contains(tokenPair.lowercased) {
                    alertMessage = "'\(tokenPair.original)' already exists in word replacements"; showAlert = true; return
                }
            }
        }

        replacement.originalText = newOriginal; replacement.replacementText = newReplacement
        do { try modelContext.save(); dismiss() }
        catch { alertMessage = "Failed to save changes: \(error.localizedDescription)"; showAlert = true }
    }
}
