//
//  Well.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import Foundation
import SwiftData

#if os(macOS)
import AppKit
#endif

@Model
final class Well {
    var id: UUID = UUID()
    var name: String = "New Well"
    var uwi: String? = nil
    var afeNumber: String? = nil
    var requisitioner: String? = nil
    var rigName: String? = nil
    var costCode: String? = nil
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \ProjectState.well) var projects: [ProjectState]?
    @Relationship(deleteRule: .nullify, inverse: \MaterialTransfer.well) var transfers: [MaterialTransfer]?
    @Relationship(deleteRule: .nullify, inverse: \RentalItem.well) var rentals: [RentalItem]?
    @Relationship(deleteRule: .nullify, inverse: \WorkDay.well) var workDays: [WorkDay]?
    @Relationship(deleteRule: .nullify, inverse: \InvoiceLineItem.well) var invoiceLineItems: [InvoiceLineItem]?
    @Relationship(deleteRule: .nullify, inverse: \Expense.well) var expenses: [Expense]?
    @Relationship(deleteRule: .nullify, inverse: \MileageLog.well) var mileageLogs: [MileageLog]?

    init(name: String = "New Well", uwi: String? = nil, afeNumber: String? = nil, requisitioner: String? = nil) {
        self.name = name
        self.uwi = uwi
        self.afeNumber = afeNumber
        self.requisitioner = requisitioner
    }
}

extension Well {
    func createTransfer(number: Int? = nil, context: ModelContext) -> MaterialTransfer {
        let transferNumber = number ?? (((transfers ?? []).map { $0.number }.max() ?? 0) + 1)
        let transfer = MaterialTransfer(number: transferNumber)
        transfer.well = self
        if transfers == nil { transfers = [] }
        transfers?.append(transfer)
        context.insert(transfer)
        return transfer
    }

    /// Generate PDF for a material transfer using the cross-platform PDF generator
    func generateTransferPDF(_ transfer: MaterialTransfer, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        return MaterialTransferPDFGenerator.shared.generatePDF(for: transfer, well: self, pageSize: pageSize)
    }
}

