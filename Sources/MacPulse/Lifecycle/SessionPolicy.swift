import Foundation

/// User configuration policy determining what triggers the boundary of a session.
public enum SessionPolicy: String, Codable, CaseIterable, Sendable {
    /// A session ends ONLY when the MacBook lid physically closes (even if external display keeps Mac awake).
    /// Sleep while lid remains open simply pauses duration tracking without splitting the session.
    case clamshellOnly = "ClamshellOnly"
    
    /// Any sleep event (manual sleep, idle sleep) or lid-close ends the current session.
    case sleepOrClamshell = "SleepOrClamshell"
    
    public var displayTitle: String {
        switch self {
        case .clamshellOnly:
            return "Lid Close Only (Default)"
        case .sleepOrClamshell:
            return "Lid Close or System Sleep"
        }
    }
    
    public var description: String {
        switch self {
        case .clamshellOnly:
            return "Session tracks continuous use across sleep until you physically close the lid."
        case .sleepOrClamshell:
            return "Each sleep or lid close finalizes a session and starts a new one on wake."
        }
    }
}
