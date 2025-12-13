//
//  ReceiptScannerViewIOS.swift
//  Josh Well Control for Mac
//
//  Vision framework receipt scanning and OCR for iOS
//

#if os(iOS)
import SwiftUI
import SwiftData
import VisionKit
import PhotosUI

// MARK: - Receipt Scanner View

struct ReceiptScannerViewIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var expense: Expense?
    let onScanComplete: (ReceiptOCRService.OCRResult, UIImage) -> Void

    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var selectedImage: UIImage?
    @State private var ocrResult: ReceiptOCRService.OCRResult?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = selectedImage {
                    // Show scanned image and OCR results
                    ScrollView {
                        VStack(spacing: 20) {
                            // Receipt Image
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 4)
                                .padding(.horizontal)

                            if isProcessing {
                                VStack(spacing: 12) {
                                    ProgressView()
                                    Text("Extracting receipt data...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                            } else if let result = ocrResult {
                                // OCR Results
                                OCRResultsView(result: result, expense: expense)
                            }

                            if let error = errorMessage {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .padding()
                            }
                        }
                        .padding(.vertical)
                    }
                } else {
                    // Capture options
                    Spacer()

                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)

                        Text("Scan a Receipt")
                            .font(.title2.bold())

                        Text("Take a photo or select from your library to extract receipt data")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        // Camera button
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Scan with Camera", systemImage: "camera.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!VNDocumentCameraViewController.isSupported)

                        // Photo picker button
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if selectedImage != nil && ocrResult != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if let result = ocrResult, let image = selectedImage {
                                onScanComplete(result, image)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                DocumentCameraView { image in
                    selectedImage = image
                    processImage(image)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                        processImage(image)
                    }
                }
            }
        }
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let result = try await ReceiptOCRService.shared.processReceipt(image: image)
                await MainActor.run {
                    ocrResult = result
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Document Camera View

struct DocumentCameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Get the first scanned page
            if scan.pageCount > 0 {
                let image = scan.imageOfPage(at: 0)
                onImageCaptured(image)
            }
            controller.dismiss(animated: true)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - OCR Results View

struct OCRResultsView: View {
    let result: ReceiptOCRService.OCRResult
    var expense: Expense?

    var body: some View {
        VStack(spacing: 16) {
            // Confidence indicator
            HStack {
                Text("Extraction Confidence")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                ConfidenceIndicator(confidence: result.confidence)
            }
            .padding(.horizontal)

            // Extracted fields
            VStack(spacing: 0) {
                if let vendor = result.vendor {
                    ExtractedFieldRow(
                        label: "Vendor",
                        value: vendor,
                        icon: "building.2"
                    )
                    Divider()
                }

                if let date = result.date {
                    ExtractedFieldRow(
                        label: "Date",
                        value: formatDate(date),
                        icon: "calendar"
                    )
                    Divider()
                }

                if let total = result.totalAmount {
                    ExtractedFieldRow(
                        label: "Total",
                        value: String(format: "$%.2f", total),
                        icon: "dollarsign.circle",
                        isHighlighted: true
                    )
                    Divider()
                }

                if let subtotal = result.subtotal {
                    ExtractedFieldRow(
                        label: "Subtotal",
                        value: String(format: "$%.2f", subtotal),
                        icon: "sum"
                    )
                    Divider()
                }

                if let gst = result.gstAmount {
                    ExtractedFieldRow(
                        label: "GST",
                        value: String(format: "$%.2f", gst),
                        icon: "percent"
                    )
                    Divider()
                }

                if let pst = result.pstAmount {
                    ExtractedFieldRow(
                        label: "PST",
                        value: String(format: "$%.2f", pst),
                        icon: "percent"
                    )
                    Divider()
                }

                if let category = result.suggestedCategory {
                    ExtractedFieldRow(
                        label: "Category",
                        value: category.rawValue,
                        icon: category.icon
                    )
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            // Raw text toggle
            DisclosureGroup("Show Raw Text") {
                Text(result.rawText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Extracted Field Row

struct ExtractedFieldRow: View {
    let label: String
    let value: String
    let icon: String
    var isHighlighted: Bool = false

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(isHighlighted ? .headline : .body)
                .foregroundStyle(isHighlighted ? .green : .primary)
        }
        .padding()
    }
}

// MARK: - Confidence Indicator

struct ConfidenceIndicator: View {
    let confidence: Double

    var color: Color {
        if confidence >= 0.7 {
            return .green
        } else if confidence >= 0.4 {
            return .yellow
        } else {
            return .red
        }
    }

    var label: String {
        if confidence >= 0.7 {
            return "High"
        } else if confidence >= 0.4 {
            return "Medium"
        } else {
            return "Low"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Receipt Scanner Button (for use in expense editor)

struct ReceiptScannerButton: View {
    @Bindable var expense: Expense
    @State private var showingScanner = false

    var body: some View {
        Button {
            showingScanner = true
        } label: {
            Label("Scan Receipt", systemImage: "doc.text.viewfinder")
        }
        .sheet(isPresented: $showingScanner) {
            ReceiptScannerViewIOS(expense: .constant(expense)) { result, image in
                applyOCRResult(result, image: image)
            }
        }
    }

    private func applyOCRResult(_ result: ReceiptOCRService.OCRResult, image: UIImage) {
        // Store OCR data for reference
        expense.ocrVendor = result.vendor
        expense.ocrDate = result.date
        expense.ocrTotalAmount = result.totalAmount
        expense.ocrSubtotal = result.subtotal
        expense.ocrGSTAmount = result.gstAmount
        expense.ocrPSTAmount = result.pstAmount
        expense.ocrSuggestedCategory = result.suggestedCategory
        expense.ocrConfidence = result.confidence
        expense.wasOCRProcessed = true

        // Always apply OCR values to expense fields (user can still manually edit after)
        if let vendor = result.vendor {
            expense.vendor = vendor
        }
        if let date = result.date {
            expense.date = date
        }
        if let total = result.totalAmount {
            expense.amount = total
            expense.taxIncludedInAmount = true // Receipt totals typically include tax
        }
        if let gst = result.gstAmount {
            expense.gstAmount = gst
        }
        if let pst = result.pstAmount {
            expense.pstAmount = pst
        }
        if let category = result.suggestedCategory {
            expense.category = category
        }

        // Store receipt image
        if let jpegData = image.jpegData(compressionQuality: 0.8) {
            expense.receiptImageData = jpegData

            // Create thumbnail
            if let thumbnail = createThumbnail(from: image, maxSize: 150) {
                expense.receiptThumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
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
}

// MARK: - Receipt Preview View

struct ReceiptPreviewView: View {
    let expense: Expense
    @State private var showingFullImage = false

    var body: some View {
        if let imageData = expense.receiptImageData,
           let image = UIImage(data: imageData) {
            Button {
                showingFullImage = true
            } label: {
                if let thumbnailData = expense.receiptThumbnailData,
                   let thumbnail = UIImage(data: thumbnailData) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .sheet(isPresented: $showingFullImage) {
                NavigationStack {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                    .navigationTitle("Receipt")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingFullImage = false
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - OCR Badge (shows if expense was OCR processed)

struct OCRBadge: View {
    let expense: Expense

    var body: some View {
        if expense.wasOCRProcessed {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.caption2)
                Text("OCR")
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor.opacity(0.2))
            .foregroundStyle(confidenceColor)
            .clipShape(Capsule())
        }
    }

    private var confidenceColor: Color {
        guard let confidence = expense.ocrConfidence else { return .gray }
        if confidence >= 0.7 {
            return .green
        } else if confidence >= 0.4 {
            return .yellow
        } else {
            return .red
        }
    }
}
#endif
