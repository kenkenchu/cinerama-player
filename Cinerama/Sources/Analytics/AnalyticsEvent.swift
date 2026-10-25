import Foundation

/// The complete vocabulary Cinerama is allowed to report.
///
/// Adding an event means adding a case here. `AnalyticsEvent` cannot be built
/// from a free-form string, so the reported vocabulary is always exactly this
/// list — which is what keeps the privacy policy's description of it accurate.
///
/// Only the name and its properties go over the wire. What an event *means* is
/// documented here and in `docs/analytics.md`.
enum AnalyticsEventName: String, CaseIterable, Sendable {
    /// Cinerama was opened or brought to the foreground. Sent at most once per
    /// device per calendar day, so the daily count is an active-device count.
    case appOpened = "app_opened"

    var isPageview: Bool { true }
    var path: String { "/app" }

}

/// A property value on an event. Rybbit only accepts strings and numbers, with
/// no nesting and a 2 KB cap on the whole property bag — which doubles as a
/// useful limit, since it stops this from quietly becoming a place where
/// arbitrary user data ends up.
enum AnalyticsValue: Sendable, Encodable {
    case string(String)
    case int(Int)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }
}

/// One reportable event: a name from the fixed vocabulary plus flat properties.
struct AnalyticsEvent: Sendable {
    let name: AnalyticsEventName
    let properties: [String: AnalyticsValue]

    init(_ name: AnalyticsEventName, _ properties: [String: AnalyticsValue] = [:]) {
        self.name = name
        self.properties = properties
    }
}
