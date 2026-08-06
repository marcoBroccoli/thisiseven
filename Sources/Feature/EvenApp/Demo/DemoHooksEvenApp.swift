import EvenCore
import Foundation

#if DEBUG
    /// Thin re-export so app-shell code can say `EvenDemoHooks` without reaching
    /// past Core. Source of truth: `EvenLaunchArguments`.
    public enum EvenDemoHooks {
        public static var skipGooglePrompt: Bool {
            EvenLaunchArguments.skipGooglePrompt
        }

        public static var resetSession: Bool {
            EvenLaunchArguments.resetSession
        }
    }
#endif
