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

            // Expenses Section
            Section("Expenses") {
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
                    Image(systemName: "plus")
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
    @Bindable var expense: Expense
    @State private var showingImagePicker = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section("Details") {
                Picker("Category", selection: $expense.category) {
                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }

                TextField("Vendor", text: $expense.vendor)

                DatePicker("Date", selection: $expense.date, displayedComponents: .date)

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", value: $expense.amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            Section("Description") {
                TextEditor(text: $expense.expenseDescription)
                    .frame(minHeight: 80)
            }

            Section("Tax") {
                Picker("Province", selection: $expense.province) {
                    ForEach(Province.allCases, id: \.self) { province in
                        Text(province.rawValue).tag(province)
                    }
                }

                Toggle("Tax Included", isOn: $expense.taxIncludedInAmount)

                HStack {
                    Text("GST")
                    Spacer()
                    Text(expense.calculatedGST, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("PST")
                    Spacer()
                    Text(expense.calculatedPST, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Reimbursement") {
                Toggle("Reimbursable", isOn: $expense.isReimbursable)

                if expense.isReimbursable {
                    Toggle("Reimbursed", isOn: $expense.isReimbursed)
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
                        }
                    }
                }
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
    @Binding var isPresented: Bool

    @State private var category: ExpenseCategory = .other
    @State private var vendor = ""
    @State private var amount: Double = 0
    @State private var date = Date()
    @State private var isReimbursable = false
    @State private var gstAmount: Double = 0
    @State private var pstAmount: Double = 0
    @State private var receiptImageData: Data?
    @State private var receiptThumbnailData: Data?
    @State private var showingScanner = false
    @State private var wasOCRProcessed = false
    @State private var ocrConfidence: Double?

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
                    }
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }

                    TextField("Vendor", text: $vendor)

                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Tax (if extracted)") {
                    HStack {
                        Text("GST")
                        Spacer()
                        Text(gstAmount, format: .currency(code: "CAD"))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("PST")
                        Spacer()
                        Text(pstAmount, format: .currency(code: "CAD"))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Reimbursable", isOn: $isReimbursable)
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
        expense.isReimbursable = isReimbursable
        expense.taxIncludedInAmount = true

        // Set tax amounts from OCR or calculate
        if gstAmount > 0 || pstAmount > 0 {
            expense.gstAmount = gstAmount
            expense.pstAmount = pstAmount
        } else {
            expense.calculateTaxes()
        }

        // Attach receipt if scanned
        expense.receiptImageData = receiptImageData
        expense.receiptThumbnailData = receiptThumbnailData
        expense.wasOCRProcessed = wasOCRProcessed
        expense.ocrConfidence = ocrConfidence

        modelContext.insert(expense)
        try? modelContext.save()
    }
}

// Note: MileageLogViewIOS is now in MileageTrackingViewIOS.swift with full GPS support

#endif
