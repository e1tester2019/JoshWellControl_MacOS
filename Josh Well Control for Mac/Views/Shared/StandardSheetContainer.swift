import SwiftUI

/// Standard sheet sizing tiers for consistent modal presentation.
enum SheetSize {
    /// 450 x 350 — simple forms, rename dialogs, confirmations
    case small
    /// 640 x 500 — single-entity editors, detail views
    case medium
    /// 900 x 650 — complex editors, reports
    case large
    /// 1100 x 700 — full simulation views, side-by-side panels
    case wide

    var minWidth: CGFloat {
        switch self {
        case .small:  return 450
        case .medium: return 640
        case .large:  return 900
        case .wide:   return 1100
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .small:  return 350
        case .medium: return 500
        case .large:  return 650
        case .wide:   return 700
        }
    }
}

extension View {
    /// Apply a standard sheet size.
    func standardSheetSize(_ size: SheetSize) -> some View {
        self.frame(minWidth: size.minWidth, minHeight: size.minHeight)
    }
}
