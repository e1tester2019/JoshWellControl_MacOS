import Foundation
import SwiftData

@Model
final class MaterialTransfer {
    var id: UUID = UUID()
    var number: Int = 1                 // M.T.#
    var date: Date = Date()

    // Header fields
    var destinationName: String? = nil  // To Loc/AFE/Vendor
    var destinationAddress: String? = nil
    var activity: String? = nil         // e.g., Drilling, Completions
    var province: String? = nil
    var country: String? = nil
    var surfaceLocation: String? = nil
    var transportedBy: String? = nil    // Truck #
    var shippingCompany: String? = nil
    var accountCode: String? = nil      // Default for lines when not set
    var operatorName: String? = nil     // Company/Operator string
    var notes: String? = nil

    // Workflow flags
    var isShippingOut: Bool = false     // This transfer ships items out of location
    var isShippedBack: Bool = false     // Items have been shipped back to vendor

    @Relationship(deleteRule: .cascade, inverse: \MaterialTransferItem.transfer) var items: [MaterialTransferItem]?

    // Back link to Well
    @Relationship var well: Well?

    init(number: Int = 1, date: Date = Date()) {
        self.number = number
        self.date = date
    }
}

@Model
final class MaterialTransferItem {
    var id: UUID = UUID()

    var quantity: Double = 1
    var descriptionText: String = ""
    var accountCode: String? = nil
    var conditionCode: String? = nil    // e.g., New, Used, Damaged
    var unitPrice: Double? = nil        // $ / Unit
    var vendorOrTo: String? = nil       // To Loc/AFE/Vendor (per line override)
    var transportedBy: String? = nil    // per line override

    var detailText: String? = nil       // Additional item details
    var serialNumber: String? = nil     // Equipment serial number
    var receiverPhone: String? = nil    // Contact phone for receiver
    var receiverAddress: String? = nil  // Receiver address
    var estimatedWeight: Double? = nil  // Estimated weight in pounds

    // Derived
    var totalValue: Double { (unitPrice ?? 0) * quantity }

    // Back link to transfer
    @Relationship var transfer: MaterialTransfer?

    init(quantity: Double = 1, descriptionText: String) {
        self.quantity = quantity
        self.descriptionText = descriptionText
    }
}

