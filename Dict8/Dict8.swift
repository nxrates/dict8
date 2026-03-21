import SwiftUI
import SwiftData
#if !LOCAL_BUILD
import Sparkle
#endif
import AppKit
import OSLog
import AppIntents
import FluidAudio

@main
struct Dict8App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    let containerInitializationFailed: Bool
    
    @StateObject private var whisperState: WhisperState
    @StateObject private var hotkeyManager: HotkeyManager
    #if !LOCAL_BUILD
    @StateObject private var updaterViewModel: UpdaterViewModel
    #endif
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @State private var showMenuBarIcon = true

    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared

    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared

    // Model prewarm service for optimizing model on wake from sleep
    @StateObject private var prewarmService: ModelPrewarmService
    
    init() {
        AppDefaults.registerDefaults()

        if UserDefaults.standard.object(forKey: "powerModeUIFlag") == nil {
            let hasEnabledPowerModes = PowerModeManager.shared.configurations.contains { $0.isEnabled }
            UserDefaults.standard.set(hasEnabledPowerModes, forKey: "powerModeUIFlag")
        }

        let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "Initialization")
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self
        ])
        var initializationFailed = false
        
        // Attempt 1: Try persistent storage
        if let persistentContainer = Self.createContainer(schema: schema, logger: logger, inMemory: false) {
            container = persistentContainer
        }
        // Attempt 2: Try in-memory storage
        else if let memoryContainer = Self.createContainer(schema: schema, logger: logger, inMemory: true) {
            container = memoryContainer

            logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")

            // Show alert to user about storage issue
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Storage Warning"
                alert.informativeText = "Dict8 couldn't access its storage location. Your transcriptions will not be saved between sessions."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        // All attempts failed
        else {
            logger.critical("ModelContainer initialization failed")
            initializationFailed = true

            // Create minimal in-memory container to satisfy initialization
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: schema, configurations: [config])) ?? {
                preconditionFailure("Unable to create ModelContainer. SwiftData is unavailable.")
            }()
        }
        
        containerInitializationFailed = initializationFailed
        
        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)
        
        #if !LOCAL_BUILD
        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)
        #endif

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)
        
        let whisperState = WhisperState(modelContext: container.mainContext, enhancementService: enhancementService)
        _whisperState = StateObject(wrappedValue: whisperState)
        
        let hotkeyManager = HotkeyManager(whisperState: whisperState)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)

        let menuBarManager = MenuBarManager()
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        menuBarManager.configure(modelContainer: container, whisperState: whisperState)

        let activeWindowService = ActiveWindowService.shared
        activeWindowService.configure(with: enhancementService)
        activeWindowService.configureWhisperState(whisperState)
        _activeWindowService = StateObject(wrappedValue: activeWindowService)

        
        let prewarmService = ModelPrewarmService(whisperState: whisperState, modelContext: container.mainContext)
        _prewarmService = StateObject(wrappedValue: prewarmService)

        appDelegate.menuBarManager = menuBarManager

        // Ensure no lingering recording state from previous runs
        Task {
            await whisperState.resetOnLaunch()
        }

        AppShortcuts.updateAppShortcutParameters()

        // Start cleanup service for the app's lifetime, not tied to window lifecycle
        TranscriptionAutoCleanupService.shared.startMonitoring(modelContext: container.mainContext)
    }
    
    // MARK: - Container Creation Helpers

    private static func createContainer(schema: Schema, logger: Logger, inMemory: Bool) -> ModelContainer? {
        do {
            let transcriptSchema = Schema([Transcription.self])
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])

            let transcriptConfig: ModelConfiguration
            let dictionaryConfig: ModelConfiguration

            if inMemory {
                transcriptConfig = ModelConfiguration(
                    "default",
                    schema: transcriptSchema,
                    isStoredInMemoryOnly: true
                )
                dictionaryConfig = ModelConfiguration(
                    "dictionary",
                    schema: dictionarySchema,
                    isStoredInMemoryOnly: true
                )
            } else {
                let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.prakashjoshipax.Dict8", isDirectory: true)
                try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

                let defaultStoreURL = appSupportURL.appendingPathComponent("default.store")
                let dictionaryStoreURL = appSupportURL.appendingPathComponent("dictionary.store")

                transcriptConfig = ModelConfiguration(
                    "default",
                    schema: transcriptSchema,
                    url: defaultStoreURL,
                    cloudKitDatabase: .none
                )

                #if LOCAL_BUILD
                let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .none
                #else
                let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .private("iCloud.com.prakashjoshipax.Dict8")
                #endif
                dictionaryConfig = ModelConfiguration(
                    "dictionary",
                    schema: dictionarySchema,
                    url: dictionaryStoreURL,
                    cloudKitDatabase: dictionaryCloudKit
                )
            }

            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig)
        } catch {
            let mode = inMemory ? "in-memory" : "persistent"
            logger.error("Failed to create \(mode, privacy: .public) ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(whisperState)
                .environmentObject(hotkeyManager)
                #if !LOCAL_BUILD
                .environmentObject(updaterViewModel)
                #endif
                .environmentObject(menuBarManager)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
                .modelContainer(container)
                .onAppear {
                    // Check if container initialization failed
                    if containerInitializationFailed {
                        let alert = NSAlert()
                        alert.messageText = "Critical Storage Error"
                        alert.informativeText = "Dict8 cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: "Quit")
                        alert.runModal()

                        NSApplication.shared.terminate(nil)
                        return
                    }

                    // Migrate dictionary data from UserDefaults to SwiftData (one-time operation)
                    DictionaryMigrationService.shared.migrateIfNeeded(context: container.mainContext)

                    #if !LOCAL_BUILD
                    updaterViewModel.silentlyCheckForUpdates()
                    #endif

                    // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                    if !UserDefaults.standard.bool(forKey: "IsTranscriptionCleanupEnabled") {
                        audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                    }

                    // Process any pending open-file request now that the main ContentView is ready.
                    if let pendingURL = appDelegate.pendingOpenFileURL {
                        NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": pendingURL])
                        appDelegate.pendingOpenFileURL = nil
                    }
                }
                .background(WindowAccessor { window in
                    WindowManager.shared.configureWindow(window)
                })
                .onDisappear {
                    whisperState.unloadModel()

                    // Stop the automatic audio cleanup process
                    audioCleanupManager.stopAutomaticCleanup()
                }
        }
        .defaultSize(width: 740, height: 650)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }

            #if !LOCAL_BUILD
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
            #endif
        }
        
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(whisperState)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                #if !LOCAL_BUILD
                .environmentObject(updaterViewModel)
                #endif
                .environmentObject(aiService)
                .environmentObject(enhancementService)
        } label: {
            Image(nsImage: {
                $0.size = NSSize(width: 22, height: 22)
                $0.isTemplate = true
                return $0
            }(NSImage(named: "menuBarIcon")!))
        }
        .menuBarExtraStyle(.menu)
        
        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Menu Bar Only") {
                menuBarManager.isMenuBarOnly.toggle()
            }
        }
        #endif
    }
}

#if !LOCAL_BUILD
class UpdaterViewModel: ObservableObject {
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true

    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Enable automatic update checking
        updaterController.updater.automaticallyChecksForUpdates = autoUpdateCheck
        updaterController.updater.updateCheckInterval = 24 * 60 * 60

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func toggleAutoUpdates(_ value: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = value
    }

    func checkForUpdates() {
        // This is for manual checks - will show UI
        updaterController.checkForUpdates(nil)
    }

    func silentlyCheckForUpdates() {
        // This checks for updates in the background without showing UI unless an update is found
        updaterController.updater.checkForUpdatesInBackground()
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}
#endif

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
