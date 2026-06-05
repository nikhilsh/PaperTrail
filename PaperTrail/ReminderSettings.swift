import Foundation
import Observation

/// Lead time before warranty expiry to fire the first reminder.
enum WarrantyLeadTime: String, CaseIterable, Identifiable, Codable {
    case oneWeek
    case twoWeeks
    case oneMonth

    var id: String { rawValue }

    /// Days before expiry for the lead reminder.
    var days: Int {
        switch self {
        case .oneWeek: 7
        case .twoWeeks: 14
        case .oneMonth: 30
        }
    }

    var label: String {
        switch self {
        case .oneWeek: "1 week before"
        case .twoWeeks: "2 weeks before"
        case .oneMonth: "1 month before"
        }
    }
}

/// User preferences for reminders + household sharing.
///
/// Backed by `UserDefaults` (not a parallel SwiftData store) so it survives the
/// CloudKit-backed `ModelContainer` and is trivially readable from any view. The
/// shared singleton is `@Observable` so SwiftUI re-renders on change and supports
/// `@Bindable` two-way toggles in Settings.
@Observable
final class ReminderSettings {
    static let shared = ReminderSettings()

    private enum Key {
        static let warrantyEnabled = "reminders.warrantyEnabled"
        static let warrantyLeadTime = "reminders.warrantyLeadTime"
        static let returnWindowEnabled = "reminders.returnWindowEnabled"
        static let suggestSupport = "reminders.suggestSupportContacts"
        static let shareWithHousehold = "reminders.shareWithHousehold"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Defaults: every toggle starts on; lead time at two weeks. Registering
        // makes "never set" read as the intended default instead of false/empty.
        defaults.register(defaults: [
            Key.warrantyEnabled: true,
            Key.returnWindowEnabled: true,
            Key.suggestSupport: true,
            Key.shareWithHousehold: true,
            Key.warrantyLeadTime: WarrantyLeadTime.twoWeeks.rawValue,
        ])
    }

    var warrantyRemindersEnabled: Bool {
        get { access(keyPath: \.warrantyRemindersEnabled); return defaults.bool(forKey: Key.warrantyEnabled) }
        set { withMutation(keyPath: \.warrantyRemindersEnabled) { defaults.set(newValue, forKey: Key.warrantyEnabled) } }
    }

    var warrantyLeadTime: WarrantyLeadTime {
        get {
            access(keyPath: \.warrantyLeadTime)
            let raw = defaults.string(forKey: Key.warrantyLeadTime) ?? WarrantyLeadTime.twoWeeks.rawValue
            return WarrantyLeadTime(rawValue: raw) ?? .twoWeeks
        }
        set { withMutation(keyPath: \.warrantyLeadTime) { defaults.set(newValue.rawValue, forKey: Key.warrantyLeadTime) } }
    }

    var returnWindowRemindersEnabled: Bool {
        get { access(keyPath: \.returnWindowRemindersEnabled); return defaults.bool(forKey: Key.returnWindowEnabled) }
        set { withMutation(keyPath: \.returnWindowRemindersEnabled) { defaults.set(newValue, forKey: Key.returnWindowEnabled) } }
    }

    var suggestSupportContacts: Bool {
        get { access(keyPath: \.suggestSupportContacts); return defaults.bool(forKey: Key.suggestSupport) }
        set { withMutation(keyPath: \.suggestSupportContacts) { defaults.set(newValue, forKey: Key.suggestSupport) } }
    }

    var shareRemindersWithHousehold: Bool {
        get { access(keyPath: \.shareRemindersWithHousehold); return defaults.bool(forKey: Key.shareWithHousehold) }
        set { withMutation(keyPath: \.shareRemindersWithHousehold) { defaults.set(newValue, forKey: Key.shareWithHousehold) } }
    }
}
