import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ModelManagementView: View {
    @ObservedObject var whisperState: WhisperState
    @State private var customModelToEdit: CustomCloudModel?
    @StateObject private var customModelManager = CustomModelManager.shared
    @StateObject private var whisperPrompt = WhisperPrompt()
    @State private var isShowingDeleteAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var deleteActionClosure: () -> Void = {}
    @State private var isAdvancedSettingsExpanded = false

    var body: some View {
        Form {
            Section("Default Model") {
                LabeledContent("Current") {
                    Text(whisperState.currentTranscriptionModel?.displayName ?? "No model selected")
                        .fontWeight(.semibold)
                }
            }

            Section {
                LanguageSelectionView(whisperState: whisperState, displayMode: .full, whisperPrompt: whisperPrompt)
            }

            Section {
                DisclosureGroup(isExpanded: $isAdvancedSettingsExpanded) {
                    ModelSettingsView(whisperPrompt: whisperPrompt)
                } label: {
                    Text("Advanced Settings").font(.headline)
                }
            }

            Section("Available Models") {
                ForEach(whisperState.allAvailableModels, id: \.id) { model in
                    ModelCardView(
                        model: model,
                        whisperState: whisperState,
                        deleteAction: { confirmDelete(model) },
                        setDefaultAction: { Task { await whisperState.setDefaultTranscriptionModel(model) } },
                        downloadAction: downloadAction(for: model),
                        editAction: model.provider == .custom ? { customModelToEdit = $0 } : nil
                    )
                }

                AddCustomModelCardView(
                    customModelManager: customModelManager,
                    editingModel: customModelToEdit,
                    whisperState: whisperState
                ) {
                    whisperState.refreshAllAvailableModels()
                    customModelToEdit = nil
                }
            }
        }
        .formStyle(.grouped)
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Delete"), action: deleteActionClosure),
                secondaryButton: .cancel()
            )
        }
    }

    private func downloadAction(for model: any TranscriptionModel) -> (() -> Void)? {
        switch model.provider {
        case .local: return { Task { await whisperState.downloadModel(model) } }
        case .parakeet: return { Task { await whisperState.downloadParakeetModel(model) } }
        default: return nil
        }
    }

    private func confirmDelete(_ model: any TranscriptionModel) {
        alertTitle = "Delete Model"
        alertMessage = "Are you sure you want to delete '\(model.displayName)'?"
        if model.provider == .custom, let customModel = model as? CustomCloudModel {
            deleteActionClosure = {
                customModelManager.removeCustomModel(withId: customModel.id)
                whisperState.refreshAllAvailableModels()
            }
        } else if model.provider == .parakeet {
            deleteActionClosure = { whisperState.deleteParakeetModel(model) }
        } else if let downloaded = whisperState.availableModels.first(where: { $0.name == model.name }) {
            deleteActionClosure = { Task { await whisperState.deleteModel(downloaded) } }
        } else {
            return
        }
        isShowingDeleteAlert = true
    }

}
