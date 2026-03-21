import Foundation
import AppKit
import os

struct BrowserInfo {
    let scriptName: String
    let bundleIdentifier: String
    let displayName: String
}

private let browsers: [BrowserInfo] = [
    BrowserInfo(scriptName: "safariURL", bundleIdentifier: "com.apple.Safari", displayName: "Safari"),
    BrowserInfo(scriptName: "arcURL", bundleIdentifier: "company.thebrowser.Browser", displayName: "Arc"),
    BrowserInfo(scriptName: "chromeURL", bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome"),
    BrowserInfo(scriptName: "edgeURL", bundleIdentifier: "com.microsoft.edgemac", displayName: "Microsoft Edge"),
    BrowserInfo(scriptName: "firefoxURL", bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox"),
    BrowserInfo(scriptName: "braveURL", bundleIdentifier: "com.brave.Browser", displayName: "Brave"),
    BrowserInfo(scriptName: "operaURL", bundleIdentifier: "com.operasoftware.Opera", displayName: "Opera"),
    BrowserInfo(scriptName: "vivaldiURL", bundleIdentifier: "com.vivaldi.Vivaldi", displayName: "Vivaldi"),
    BrowserInfo(scriptName: "orionURL", bundleIdentifier: "com.kagi.kagimacOS", displayName: "Orion"),
    BrowserInfo(scriptName: "zenURL", bundleIdentifier: "app.zen-browser.zen", displayName: "Zen Browser"),
    BrowserInfo(scriptName: "yandexURL", bundleIdentifier: "ru.yandex.desktop.yandex-browser", displayName: "Yandex Browser"),
]

enum BrowserType: CaseIterable {
    case safari, arc, chrome, edge, firefox, brave, opera, vivaldi, orion, zen, yandex

    private static let infoMap: [BrowserType: BrowserInfo] = {
        let types: [BrowserType] = [.safari, .arc, .chrome, .edge, .firefox, .brave, .opera, .vivaldi, .orion, .zen, .yandex]
        return Dictionary(uniqueKeysWithValues: zip(types, browsers))
    }()

    var info: BrowserInfo { Self.infoMap[self]! }
    var scriptName: String { info.scriptName }
    var bundleIdentifier: String { info.bundleIdentifier }
    var displayName: String { info.displayName }

    static var allCases: [BrowserType] { [.safari, .arc, .chrome, .edge, .brave, .opera, .vivaldi, .orion, .yandex] }
    static var installedBrowsers: [BrowserType] {
        allCases.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil }
    }
}

enum BrowserURLError: Error {
    case scriptNotFound, executionFailed, browserNotRunning, noActiveWindow, noActiveTab
}

class BrowserURLService {
    static let shared = BrowserURLService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.dict8", category: "browser.applescript")
    private init() {}

    func getCurrentURL(from browser: BrowserType) async throws -> String {
        guard let scriptURL = Bundle.main.url(forResource: browser.scriptName, withExtension: "scpt") else {
            throw BrowserURLError.scriptNotFound
        }
        guard isRunning(browser) else { throw BrowserURLError.browserNotRunning }

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [scriptURL.path]
        let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = pipe

        do {
            try task.run(); task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else { throw BrowserURLError.noActiveTab }
            if output.lowercased().contains("error") { throw BrowserURLError.executionFailed }
            return output
        } catch { throw BrowserURLError.executionFailed }
    }

    func isRunning(_ browser: BrowserType) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == browser.bundleIdentifier }
    }
}
