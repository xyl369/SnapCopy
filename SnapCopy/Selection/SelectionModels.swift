import Foundation

enum SnapCopyError: LocalizedError {
    case captureCancelled
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureCancelled: return "Cancelled"
        case .captureFailed(let r): return r
        }
    }
}
