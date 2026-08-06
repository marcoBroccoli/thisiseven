import Foundation

public extension Toast {
    /// Maps a thrown error into an error-tone toast.
    ///
    /// Copy is passed in rather than baked in — the module has no idea what
    /// service the caller was talking to, and shouldn't name one.
    static func failure(
        from error: Error,
        offline: String,
        fallback: String,
        duration: Duration? = nil
    ) -> Toast {
        Toast(
            message: isOffline(error) ? offline : fallback,
            tone: .error,
            duration: duration
        )
    }

    /// Explicit error copy when the caller already has a message.
    static func failure(
        _ message: String,
        duration: Duration? = nil
    ) -> Toast {
        Toast(message: message, tone: .error, duration: duration)
    }

    /// True for the connectivity cases worth telling the user to retry on.
    static func isOffline(_ error: Error) -> Bool {
        let code: URLError.Code? =
            if let url = error as? URLError {
                url.code
            } else {
                {
                    let ns = error as NSError
                    return ns.domain == NSURLErrorDomain
                        ? URLError.Code(rawValue: ns.code)
                        : nil
                }()
            }

        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut:
            return true
        default:
            return false
        }
    }
}
