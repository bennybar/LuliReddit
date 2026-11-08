import Foundation

// Also built into the ShareSummarize extension (project.yml).

/// More right-to-left letters (Hebrew, Arabic…) than left-to-right ones.
func isMostlyRtl(_ text: String) -> Bool {
    var rtl = 0
    var ltr = 0
    for u in text.unicodeScalars {
        // iOS has no public bidi-class API: strong letters are close enough to Java's
        // getDirectionality (digits, punctuation and marks are neutral in both).
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            switch u.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF:
                rtl += 1
            default:
                ltr += 1
            }
        default:
            break
        }
    }
    return rtl > ltr
}
