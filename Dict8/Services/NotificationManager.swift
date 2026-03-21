import SwiftUI

// MARK: - Notification Types

extension AppNotificationView {
    enum NotificationType {
        case error, warning, info, success

        var iconName: String {
            switch self {
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .error: return .red
            case .warning: return .yellow
            case .info: return .blue
            case .success: return .green
            }
        }
    }
}

// Keep AppNotificationView as a minimal namespace for the NotificationType enum
enum AppNotificationView {}

// MARK: - Notification Manager

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var activeNotification: String? = nil
    @Published var activeNotificationType: AppNotificationView.NotificationType = .info
    @Published var notificationProgress: Double = 1.0

    private var dismissTimer: Timer?
    private var progressTimer: Timer?
    private var duration: TimeInterval = 3.0
    private var startTime: Date?
    private init() {}

    @MainActor
    func showNotification(title: String, type: AppNotificationView.NotificationType, duration: TimeInterval = 3.0, onTap: (() -> Void)? = nil) {
        dismissTimer?.invalidate()
        progressTimer?.invalidate()

        if type == .error { SoundManager.shared.playEscSound() }

        activeNotification = title
        activeNotificationType = type
        notificationProgress = 1.0
        self.duration = duration
        startTime = Date()

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let start = self.startTime else { return }
            let remaining = max(0, 1.0 - Date().timeIntervalSince(start) / self.duration)
            Task { @MainActor in self.notificationProgress = remaining }
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.progressTimer?.invalidate()
                self?.activeNotification = nil
            }
        }
    }

    @MainActor
    func dismissNotification() {
        dismissTimer?.invalidate()
        progressTimer?.invalidate()
        activeNotification = nil
    }
}
