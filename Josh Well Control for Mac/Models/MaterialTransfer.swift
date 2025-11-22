import Foundation
import SwiftData

@Model
final class MaterialTransfer {
    @Attribute(.unique) var id: UUID = UUID()
    var number: Int = 1                 // M.T.#
    var date: Date

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

    @Relationship(deleteRule: .cascade) var items: [MaterialTransferItem] = []

    // Back link to Well
    @Relationship(inverse: \Well.transfers) var well: Well?

    init(number: Int = 1, date: Date = Date()) {
        self.number = number
        self.date = date
    }
}

@Model
final class MaterialTransferItem {
    @Attribute(.unique) var id: UUID = UUID()

    var quantity: Double = 1
    var descriptionText: String = ""
    var accountCode: String? = nil
    var conditionCode: String? = nil    // e.g., A-New, B-Used
    var unitPrice: Double? = nil        // $ / Unit
    var vendorOrTo: String? = nil       // To Loc/AFE/Vendor (per line override)
    var transportedBy: String? = nil    // per line override

    var detailText: String? = nil       // Additional item details
    var receiverPhone: String? = nil    // Contact phone for receiver
    var receiverAddress: String? = nil  // Receiver address
    var estimatedWeight: Double? = nil  // Estimated weight in pounds

    // Derived
    var totalValue: Double { (unitPrice ?? 0) * quantity }

    // Back link to transfer
    @Relationship(inverse: \MaterialTransfer.items) var transfer: MaterialTransfer?

    init(quantity: Double = 1, descriptionText: String) {
        self.quantity = quantity
        self.descriptionText = descriptionText
    }
}
