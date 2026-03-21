import Foundation
import CoreAudio
import AVFoundation
import os

enum AudioInputMode: String, CaseIterable {
    case systemDefault = "System Default"
    case custom = "Custom Device"
}

class AudioDeviceManager: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "AudioDeviceManager")
    @Published var availableDevices: [(id: AudioDeviceID, uid: String, name: String)] = []
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var inputMode: AudioInputMode = .custom

    var isRecordingActive: Bool = false

    static let shared = AudioDeviceManager()

    init() {
        if let savedMode = UserDefaults.standard.audioInputModeRawValue,
           let mode = AudioInputMode(rawValue: savedMode) {
            inputMode = mode
        } else {
            inputMode = .systemDefault
        }

        loadAvailableDevices { [weak self] in
            self?.initializeSelectedDevice()
        }

        setupDeviceChangeNotifications()
    }

    func getSystemDefaultDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &propertySize, &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            logger.error("Failed to get system default device: \(status, privacy: .public)")
            return nil
        }
        return deviceID
    }

    func getSystemDefaultDeviceName() -> String? {
        guard let deviceID = getSystemDefaultDevice() else { return nil }
        return getDeviceName(deviceID: deviceID)
    }

    private func initializeSelectedDevice() {
        switch inputMode {
        case .systemDefault:
            break
        case .custom:
            if let savedUID = UserDefaults.standard.selectedAudioDeviceUID {
                if let device = availableDevices.first(where: { $0.uid == savedUID }) {
                    selectedDeviceID = device.id
                } else {
                    UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.selectedAudioDeviceUID)
                    fallbackToDefaultDevice()
                }
            } else {
                fallbackToDefaultDevice()
            }
        }
    }

    private func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        return availableDevices.contains { $0.id == deviceID }
    }

    private func fallbackToDefaultDevice() {
        guard let newDeviceID = findBestAvailableDevice() else {
            logger.error("No input devices available!")
            selectedDeviceID = nil
            notifyDeviceChange()
            return
        }
        selectDevice(id: newDeviceID)
    }

    func findBestAvailableDevice() -> AudioDeviceID? {
        if let device = availableDevices.first(where: { isBuiltInDevice($0.id) }) {
            return device.id
        }
        return availableDevices.first?.id
    }

    private func isBuiltInDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard let uid = getDeviceUID(deviceID: deviceID) else { return false }
        return uid.contains("BuiltIn")
    }

    func loadAvailableDevices(completion: (() -> Void)? = nil) {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize
        )

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs
        )

        if result != noErr {
            logger.error("Error getting audio devices: \(result, privacy: .public)")
            return
        }

        let devices = deviceIDs.compactMap { deviceID -> (id: AudioDeviceID, uid: String, name: String)? in
            guard let name = getDeviceName(deviceID: deviceID),
                  let uid = getDeviceUID(deviceID: deviceID),
                  isValidInputDevice(deviceID: deviceID) else { return nil }
            return (id: deviceID, uid: uid, name: name)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.availableDevices = devices.map { ($0.id, $0.uid, $0.name) }
            if let currentID = self.selectedDeviceID, !devices.contains(where: { $0.id == currentID }) {
                if !self.isRecordingActive {
                    self.fallbackToDefaultDevice()
                }
            }
            completion?()
        }
    }

    func getDeviceName(deviceID: AudioDeviceID) -> String? {
        let name: CFString? = getDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
        return name as String?
    }

    private func isValidInputDevice(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        if result != noErr { return false }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferList.deallocate() }

        result = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferList)
        if result != noErr { return false }

        return Int(bufferList.pointee.mNumberBuffers) > 0
    }

    func selectDevice(id: AudioDeviceID) {
        if let deviceToSelect = availableDevices.first(where: { $0.id == id }) {
            let uid = deviceToSelect.uid
            DispatchQueue.main.async {
                self.selectedDeviceID = id
                UserDefaults.standard.selectedAudioDeviceUID = uid
                self.notifyDeviceChange()
            }
        } else {
            fallbackToDefaultDevice()
        }
    }

    func selectDeviceAndSwitchToCustomMode(id: AudioDeviceID) {
        if let deviceToSelect = availableDevices.first(where: { $0.id == id }) {
            let uid = deviceToSelect.uid
            DispatchQueue.main.async {
                self.inputMode = .custom
                self.selectedDeviceID = id
                UserDefaults.standard.audioInputModeRawValue = AudioInputMode.custom.rawValue
                UserDefaults.standard.selectedAudioDeviceUID = uid
                self.notifyDeviceChange()
            }
        } else {
            fallbackToDefaultDevice()
        }
    }

    func selectInputMode(_ mode: AudioInputMode) {
        inputMode = mode
        UserDefaults.standard.audioInputModeRawValue = mode.rawValue

        if mode == .custom && selectedDeviceID == nil {
            if let firstDevice = availableDevices.first {
                selectDevice(id: firstDevice.id)
            }
        }

        notifyDeviceChange()
    }

    func getCurrentDevice() -> AudioDeviceID {
        switch inputMode {
        case .systemDefault:
            return getSystemDefaultDevice() ?? findBestAvailableDevice() ?? 0
        case .custom:
            if let id = selectedDeviceID, isDeviceAvailable(id) {
                return id
            }
            return findBestAvailableDevice() ?? 0
        }
    }

    private func setupDeviceChangeNotifications() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        AudioObjectAddPropertyListener(
            systemObjectID, &address,
            { (_, _, _, userData) -> OSStatus in
                let manager = Unmanaged<AudioDeviceManager>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async { manager.handleDeviceListChange() }
                return noErr
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    private func handleDeviceListChange() {
        loadAvailableDevices { [weak self] in
            guard let self = self else { return }

            if self.inputMode == .systemDefault {
                self.notifyDeviceChange()
                return
            }

            if self.isRecordingActive {
                guard let currentID = self.selectedDeviceID else { return }
                if !self.isDeviceAvailable(currentID) {
                    let newDeviceID = self.findBestAvailableDevice()
                    if let deviceID = newDeviceID {
                        self.selectedDeviceID = deviceID
                        NotificationCenter.default.post(
                            name: .audioDeviceSwitchRequired,
                            object: nil,
                            userInfo: ["newDeviceID": deviceID]
                        )
                    } else {
                        NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
                    }
                }
                return
            }

            if self.inputMode == .custom,
               let currentID = self.selectedDeviceID,
               !self.isDeviceAvailable(currentID) {
                self.fallbackToDefaultDevice()
            }
        }
    }

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        let uid: CFString? = getDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
        return uid as String?
    }

    deinit {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &address,
            { (_, _, _, _) -> OSStatus in return noErr },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    private func createPropertyAddress(selector: AudioObjectPropertySelector,
                                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                       element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func getDeviceProperty<T>(deviceID: AudioDeviceID,
                                      selector: AudioObjectPropertySelector,
                                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        guard deviceID != 0 else { return nil }

        var address = createPropertyAddress(selector: selector, scope: scope)
        var propertySize = UInt32(MemoryLayout<T>.size)
        var property: T? = nil

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &property)
        if status != noErr { return nil }

        return property
    }

    private func notifyDeviceChange() {
        NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
    }
}
