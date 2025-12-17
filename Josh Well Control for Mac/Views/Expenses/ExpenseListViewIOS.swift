//
//  ExpenseListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized expense tracking views
//

#if os(iOS)
import SwiftUI
import SwiftData
import PhotosUI

struct ExpenseListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showingAddSheet = false
    @State private var filterCategory: ExpenseCategory?
    @State private var showReimbursableOnly = false

    private var filteredExpenses: [Expense] {
        var result = expenses

        if let category = filterCategory {
            result = result.filter { $0.category == category }
        }

        if showReimbursableOnly {
            result = result.filter { $0.isReimbursable && !$0.isReimbursed }
        }

        return result
    }

    private var totalAmount: Double {
        filteredExpenses.reduce(0) { $0 + $1.totalAmount }
    }

    var body: some View {
        List {
            // Summary Section
            Section {
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text(totalAmount, format: .currency(code: "CAD"))
                        .font(.headline)
                        .monospacedDigit()
                }

                if showReimbursableOnly {
                    HStack {
                        Text("Unreimbursed")
                        Spacer()
                        Text("\(filteredExpenses.count)")
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Filter Section
            Section("Filters") {
                Picker("Category", selection: $filterCategory) {
                    Text("All Categories").tag(nil as ExpenseCategory?)
                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category as ExpenseCategory?)
                    }
                }

                Toggle("Show Unreimbursed Only", isOn: $showReimbursableOnly)
            }

            // Add Button Section
            Section {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add New Expense", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Expenses Section
            Section("Expenses") {
                if filteredExpenses.isEmpty {
                    ContentUnavailableView {
                        Label("No Expenses", systemImage: "creditcard")
                    } description: {
                        Text("Track your business expenses and receipts")
                    }
                }

                ForEach(filteredExpenses) { expense in
                    NavigationLink {
                        ExpenseDetailViewIOS(expense: expense)
                    } label: {
                        ExpenseRowIOS(expense: expense)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(expense)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if expense.isReimbursable && !expense.isReimbursed {
                            Button {
                                expense.isReimbursed = true
                                expense.reimbursedDate = Date.now
                                try? modelContext.save()
                            } label: {
                                Label("Mark Reimbursed", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                    }
                    .contextMenu {
                        Button {
                            // Navigation handled by NavigationLink
                        } label: {
                            Label("View/Edit", systemImage: "pencil")
                        }

                        if expense.isReimbursable && !expense.isReimbursed {
                            Button {
                                expense.isReimbursed = true
                                expense.reimbursedDate = Date.now
                                try? modelContext.save()
                            } label: {
                                Label("Mark Reimbursed", systemImage: "checkmark.circle")
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            modelContext.delete(expense)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Expense", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddExpenseSheetIOS(isPresented: $showingAddSheet)
        }
    }
}

// MARK: - Expense Row

private struct ExpenseRowIOS: View {
    let expense: Expense

    var body: some View {
        HStack {
            // Category icon
            Image(systemName: expense.category.icon)
                .foregroundStyle(categoryColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(expense.vendor.isEmpty ? expense.category.rawValue : expense.vendor)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if expense.isReimbursable && !expense.isReimbursed {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if expense.isReimbursed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                HStack {
                    Text(expense.date, style: .date)
                    if !expense.expenseDescription.isEmpty {
                        Text("•")
                        Text(expense.expenseDescription)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(expense.totalAmount, format: .currency(code: "CAD"))
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private var categoryColor: Color {
        switch expense.category {
        case .fuel: return .orange
        case .meals: return .green
        case .lodging: return .purple
        case .vehicleMaintenance: return .gray
        case .toolsEquipment: return .blue
        case .officeSupplies: return .cyan
        case .phone: return .pink
        case .professionalServices: return .indigo
        case .insurance: return .teal
        case .travel: return .mint
        case .clothing: return .brown
        case .training: return .yellow
        case .subscriptions: return .red
        case .other: return .secondary
        }
    }
}

// MARK: - Expense Detail

struct ExpenseDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(sort: \Well.name) private var wells: [Well]
    @Bindable var expense: Expense
    @State private var showingImagePicker = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section("Basic Info") {
                DatePicker("Date", selection: $expense.date, displayedComponents: .date)

                TextField("Vendor/Merchant", text: $expense.vendor)

                Picker("Category", selection: $expense.category) {
                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        Label(category.rawValue, systemImage: category.icon).tag(category)
                    }
                }

                TextField("Description", text: $expense.expenseDescription)
            }

            Section("Amount & Tax") {
                Picker("Province", selection: $expense.province) {
                    ForEach(Province.allCases, id: \.self) { province in
                        Text(province.rawValue).tag(province)
                    }
                }

                Toggle("Amount includes tax", isOn: $expense.taxIncludedInAmount)

                HStack {
                    Text(expense.taxIncludedInAmount ? "Total Amount" : "Pre-tax Amount")
                    Spacer()
                    TextField("Amount", value: $expense.amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                HStack {
                    Text("GST (5%)")
                    Spacer()
                    if expense.taxIncludedInAmount {
                        Text(expense.calculatedGST, format: .currency(code: "CAD"))
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("GST", value: $expense.gstAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                if expense.province == .bc {
                    HStack {
                        Text("PST (7%)")
                        Spacer()
                        if expense.taxIncludedInAmount {
                            Text(expense.calculatedPST, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("PST", value: $expense.pstAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                HStack {
                    Text(expense.taxIncludedInAmount ? "Pre-tax Amount" : "Total")
                        .fontWeight(.medium)
                    Spacer()
                    Text(expense.taxIncludedInAmount ? expense.preTaxAmount : expense.totalAmount, format: .currency(code: "CAD"))
                        .fontWeight(.semibold)
                }
            }

            Section("Payment") {
                Picker("Payment Method", selection: $expense.paymentMethod) {
                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
            }

            Section("Reimbursement") {
                Toggle("Reimbursable expense", isOn: $expense.isReimbursable)

                if expense.isReimbursable {
                    Toggle("Has been reimbursed", isOn: $expense.isReimbursed)

                    if expense.isReimbursed, let reimbursedDate = expense.reimbursedDate {
                        HStack {
                            Text("Reimbursed on")
                            Spacer()
                            Text(reimbursedDate, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Link to Job") {
                Picker("Client", selection: Binding(
                    get: { expense.client },
                    set: { expense.client = $0 }
                )) {
                    Text("None").tag(nil as Client?)
                    ForEach(clients) { client in
                        Text(client.companyName).tag(client as Client?)
                    }
                }

                Picker("Well", selection: Binding(
                    get: { expense.well },
                    set: { expense.well = $0 }
                )) {
                    Text("None").tag(nil as Well?)
                    ForEach(wells) { well in
                        Text(well.name).tag(well as Well?)
                    }
                }
            }

            Section("Receipt") {
                if let receiptData = expense.receiptImageData,
                   let uiImage = UIImage(data: receiptData) {
                    HStack {
                        Spacer()
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                        Spacer()
                    }

                    if expense.wasOCRProcessed {
                        OCRBadge(expense: expense)
                    }

                    Button(role: .destructive) {
                        expense.receiptImageData = nil
                        expense.receiptThumbnailData = nil
                        expense.hasReceiptAttached = false
                    } label: {
                        Label("Remove Receipt", systemImage: "trash")
                    }
                }

                ReceiptScannerButton(expense: expense)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(expense.receiptImageData == nil ? "Choose from Library" : "Replace from Library", systemImage: "photo.on.rectangle")
                }
                .onChange(of: selectedItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            expense.receiptImageData = data
                            expense.hasReceiptAttached = true
                        }
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $expense.notes)
                    .frame(minHeight: 80)
            }
        }
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Expense Sheet

private struct AddExpenseSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(sort: \Well.name) private var wells: [Well]
    @Binding var isPresented: Bool

    // Basic info
    @State private var category: ExpenseCategory = .other
    @State private var vendor = ""
    @State private var expenseDescription = ""
    @State private var amount: Double = 0
    @State private var date = Date()

    // Tax settings
    @State private var province: Province = .alberta
    @State private var taxIncludedInAmount = true
    @State private var gstAmount: Double = 0
    @State private var pstAmount: Double = 0

    // Payment & reimbursement
    @State private var paymentMethod: PaymentMethod = .creditCard
    @State private var isReimbursable = false

    // Link to job
    @State private var selectedClient: Client?
    @State private var selectedWell: Well?

    // Notes
    @State private var notes = ""

    // Receipt
    @State private var receiptImageData: Data?
    @State private var receiptThumbnailData: Data?
    @State private var showingScanner = false
    @State private var wasOCRProcessed = false
    @State private var ocrConfidence: Double?
    @State private var selectedPhotoItem: PhotosPickerItem?

    private var preTaxAmount: Double {
        if taxIncludedInAmount {
            return amount / (1 + province.totalTaxRate)
        }
        return amount
    }

    private var calculatedGST: Double {
        preTaxAmount * province.gstRate
    }

    private var calculatedPST: Double {
        preTaxAmount * province.pstRate
    }

    private var totalAmount: Double {
        if taxIncludedInAmount {
            return amount
        }
        return amount + gstAmount + pstAmount
    }

    var body: some View {
        NavigationStack {
            Form {
                // Receipt scanning section at top for easy access
                Section("Receipt") {
                    Button {
                        showingScanner = true
                    } label: {
                        HStack {
                            Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                            Spacer()
                            if wasOCRProcessed {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Scanned")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: selectedPhotoItem) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self) {
                                receiptImageData = data
                                if let image = UIImage(data: data),
                                   let thumbnail = createThumbnail(from: image, maxSize: 150) {
                                    receiptThumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
                                }
                            }
                        }
                    }

                    if let imageData = receiptImageData,
                       let image = UIImage(data: imageData) {
                        HStack {
                            Spacer()
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 150)
                                .cornerRadius(8)
                            Spacer()
                        }

                        Button(role: .destructive) {
                            receiptImageData = nil
                            receiptThumbnailData = nil
                            wasOCRProcessed = false
                        } label: {
                            Label("Remove Receipt", systemImage: "trash")
                        }
                    }
                }

                Section("Basic Info") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    TextField("Vendor/Merchant", text: $vendor)

                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    TextField("Description", text: $expenseDescription)
                }

                Section("Amount & Tax") {
                    Picker("Province", selection: $province) {
                        ForEach(Province.allCases, id: \.self) { prov in
                            Text(prov.rawValue).tag(prov)
                        }
                    }
                    .onChange(of: province) { _, _ in
                        recalculateTaxes()
                    }

                    Toggle("Amount includes tax", isOn: $taxIncludedInAmount)
                        .onChange(of: taxIncludedInAmount) { _, _ in
                            recalculateTaxes()
                        }

                    HStack {
                        Text(taxIncludedInAmount ? "Total Amount" : "Pre-tax Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    .onChange(of: amount) { _, _ in
                        recalculateTaxes()
                    }

                    HStack {
                        Text("GST (5%)")
                        Spacer()
                        if taxIncludedInAmount {
                            Text(calculatedGST, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("GST", value: $gstAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }

                    if province == .bc {
                        HStack {
                            Text("PST (7%)")
                            Spacer()
                            if taxIncludedInAmount {
                                Text(calculatedPST, format: .currency(code: "CAD"))
                                    .foregroundStyle(.secondary)
                            } else {
                                TextField("PST", value: $pstAmount, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                        }
                    }

                    HStack {
                        Text(taxIncludedInAmount ? "Pre-tax Amount" : "Total")
                            .fontWeight(.medium)
                        Spacer()
                        Text(taxIncludedInAmount ? preTaxAmount : totalAmount, format: .currency(code: "CAD"))
                            .fontWeight(.semibold)
                    }
                }

                Section("Payment") {
                    Picker("Payment Method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                }

                Section("Reimbursement") {
                    Toggle("Reimbursable expense", isOn: $isReimbursable)
                }

                Section("Link to Job (Optional)") {
                    Picker("Client", selection: $selectedClient) {
                        Text("None").tag(nil as Client?)
                        ForEach(clients) { client in
                            Text(client.companyName).tag(client as Client?)
                        }
                    }

                    Picker("Well", selection: $selectedWell) {
                        Text("None").tag(nil as Well?)
                        ForEach(wells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addExpense()
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
            .sheet(isPresented: $showingScanner) {
                ReceiptScannerViewIOS(expense: .constant(nil)) { result, image in
                    applyOCRResult(result, image: image)
                }
            }
        }
    }

    private func recalculateTaxes() {
        if taxIncludedInAmount {
            gstAmount = calculatedGST
            pstAmount = calculatedPST
        } else {
            gstAmount = preTaxAmount * province.gstRate
            pstAmount = preTaxAmount * province.pstRate
        }
    }

    private func applyOCRResult(_ result: ReceiptOCRService.OCRResult, image: UIImage) {
        // Apply OCR values to form fields
        if let extractedVendor = result.vendor {
            vendor = extractedVendor
        }
        if let extractedDate = result.date {
            date = extractedDate
        }
        if let extractedTotal = result.totalAmount {
            amount = extractedTotal
        }
        if let extractedGST = result.gstAmount {
            gstAmount = extractedGST
        }
        if let extractedPST = result.pstAmount {
            pstAmount = extractedPST
        }
        if let extractedCategory = result.suggestedCategory {
            category = extractedCategory
        }

        wasOCRProcessed = true
        ocrConfidence = result.confidence

        // Store receipt image
        if let jpegData = image.jpegData(compressionQuality: 0.8) {
            receiptImageData = jpegData

            // Create thumbnail
            if let thumbnail = createThumbnail(from: image, maxSize: 150) {
                receiptThumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
            }
        }
    }

    private func createThumbnail(from image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func addExpense() {
        let expense = Expense(date: date, amount: amount, category: category)
        expense.vendor = vendor
        expense.expenseDescription = expenseDescription
        expense.province = province
        expense.paymentMethod = paymentMethod
        expense.taxIncludedInAmount = taxIncludedInAmount
        expense.isReimbursable = isReimbursable
        expense.client = selectedClient
        expense.well = selectedWell
        expense.notes = notes

        // Set tax amounts
        if taxIncludedInAmount {
            expense.gstAmount = calculatedGST
            expense.pstAmount = calculatedPST
        } else {
            expense.gstAmount = gstAmount
            expense.pstAmount = pstAmount
        }

        // Attach receipt if present
        expense.receiptImageData = receiptImageData
        expense.receiptThumbnailData = receiptThumbnailData
        expense.hasReceiptAttached = receiptImageData != nil
        expense.wasOCRProcessed = wasOCRProcessed
        expense.ocrConfidence = ocrConfidence

        modelContext.insert(expense)
        try? modelContext.save()
    }
}

// Note: MileageLogViewIOS is now in MileageTrackingViewIOS.swift with full GPS support

#endif
