import Foundation

/// Quarantined launch-arg switches for UITests / demos (DEBUG only).
public enum EvenLaunchArguments {
    public static var skipGooglePrompt: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--skip-google-prompt")
        #else
            false
        #endif
    }

    public static var resetSession: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--reset-session")
        #else
            false
        #endif
    }
}
