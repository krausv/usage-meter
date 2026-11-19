import Foundation

/// The polling intervals offered in Preferences.
public enum RefreshInterval: TimeInterval, CaseIterable {
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300

    public static let defaultValue: Self = .oneMinute

    public init(preferenceValue: TimeInterval) {
        self = Self(rawValue: preferenceValue) ?? Self.defaultValue
    }
}
