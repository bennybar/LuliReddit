import Foundation

/// Sort options for post listings. Order matters: persisted by index (`defaultSort`).
enum PostSort: Int, CaseIterable, Sendable {
    case best, hot, newest, top, rising

    var path: String {
        switch self {
        case .best: return "best"
        case .hot: return "hot"
        case .newest: return "new"
        case .top: return "top"
        case .rising: return "rising"
        }
    }

    var label: String {
        switch self {
        case .best: return "Best"
        case .hot: return "Hot"
        case .newest: return "New"
        case .top: return "Top"
        case .rising: return "Rising"
        }
    }

    var needsTime: Bool { self == .top }
}

enum TopTime: Int, CaseIterable, Sendable {
    case hour, day, week, month, year, all

    var param: String {
        switch self {
        case .hour: return "hour"
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        case .all: return "all"
        }
    }

    var label: String {
        switch self {
        case .hour: return "Now"
        case .day: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        case .year: return "This year"
        case .all: return "All time"
        }
    }
}

/// Reddit comment sorts: id → label.
let COMMENT_SORTS: [(id: String, label: String)] = [
    ("confidence", "Best"),
    ("top", "Top"),
    ("new", "New"),
    ("controversial", "Controversial"),
    ("old", "Old"),
    ("qa", "Q&A"),
]
