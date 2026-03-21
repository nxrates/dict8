import SwiftUI
import SwiftData

struct TranscriptionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedTranscription: Transcription?
    @State private var showDeleteConfirmation = false
    @State private var transcriptionToDelete: Transcription?
    @State private var isViewCurrentlyVisible = false
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?

    private let pageSize = 20

    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]

    private static func createLatestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)])
        if let timestamp = timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { t in
                    (t.text.localizedStandardContains(searchText) || (t.enhancedText?.localizedStandardContains(searchText) ?? false)) && t.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { t in t.timestamp < timestamp }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { t in
                t.text.localizedStandardContains(searchText) || (t.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }
        descriptor.fetchLimit = pageSize
        return descriptor
    }

    var body: some View {
        Group {
            if let transcription = selectedTranscription {
                detailView(for: transcription)
            } else {
                listView
            }
        }
        .alert("Delete Transcription?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let t = transcriptionToDelete {
                    performDeletion(for: t)
                    Task { await saveAndReload() }
                }
            }
            Button("Cancel", role: .cancel) { transcriptionToDelete = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear { isViewCurrentlyVisible = true; Task { await loadInitialContent() } }
        .onDisappear { isViewCurrentlyVisible = false }
        .onChange(of: searchText) { _, _ in Task { await resetPagination(); await loadInitialContent() } }
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible, newId != oldId else { return }
            Task { await resetPagination(); await loadInitialContent() }
        }
    }

    // MARK: - List View

    private var listView: some View {
        Form {
            Section("Transcriptions") {
                ForEach(displayedTranscriptions) { transcription in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(transcription.enhancedText ?? transcription.text)
                            .font(.body)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text(transcription.timestamp.formatted(date: .abbreviated, time: .shortened))
                        if transcription.duration > 0 {
                            Text("·")
                            Text(transcription.duration.formatTiming())
                        }
                        if let model = transcription.transcriptionModelName {
                            Text("·")
                            Text(model)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .listRowBackground(selectedTranscription?.id == transcription.id ? Color.accentColor.opacity(0.15) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { selectedTranscription = transcription }
                .contextMenu {
                    Button { let _ = ClipboardManager.copyToClipboard(transcription.enhancedText ?? transcription.text) } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) { transcriptionToDelete = transcription; showDeleteConfirmation = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            if hasMoreContent {
                Button {
                    Task { await loadMoreContent() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Load More")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            }
        }
        .formStyle(.grouped)
        .searchable(text: $searchText, prompt: "Search transcriptions")
        .overlay {
            if displayedTranscriptions.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("No transcriptions")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Detail View

    private func detailView(for transcription: Transcription) -> some View {
        TranscriptionDetailView(transcription: transcription)
            .id(transcription.id)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        selectedTranscription = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
                ToolbarItem {
                    Button(role: .destructive) {
                        transcriptionToDelete = transcription
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete")
                }
            }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadInitialContent() async {
        isLoading = true; defer { isLoading = false }
        do {
            lastTimestamp = nil
            let items = try modelContext.fetch(cursorQueryDescriptor())
            displayedTranscriptions = items
            lastTimestamp = items.last?.timestamp
            hasMoreContent = items.count == pageSize
        } catch { print("Error loading transcriptions: \(error)") }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let lastTimestamp else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let newItems = try modelContext.fetch(cursorQueryDescriptor(after: lastTimestamp))
            displayedTranscriptions.append(contentsOf: newItems)
            self.lastTimestamp = newItems.last?.timestamp
            hasMoreContent = newItems.count == pageSize
        } catch { print("Error loading more transcriptions: \(error)") }
    }

    @MainActor
    private func resetPagination() {
        displayedTranscriptions = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    private func performDeletion(for transcription: Transcription) {
        if let urlString = transcription.audioFileURL, let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        if selectedTranscription == transcription { selectedTranscription = nil }
        modelContext.delete(transcription)
    }

    private func saveAndReload() async {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            await loadInitialContent()
        } catch {
            print("Error saving deletion: \(error.localizedDescription)")
            await loadInitialContent()
        }
    }
}
