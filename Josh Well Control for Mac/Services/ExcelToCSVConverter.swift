//
//  ExcelToCSVConverter.swift
//  Josh Well Control for Mac
//
//  Converts Excel (.xlsx) files to CSV using Python for import.
//

import Foundation

#if os(macOS)

enum ExcelToCSVConverter {

    enum ConversionError: LocalizedError {
        case pythonNotAvailable
        case conversionFailed(String)
        case noDataSheet

        var errorDescription: String? {
            switch self {
            case .pythonNotAvailable:
                return "Python 3 is required to import Excel files. Please install Python 3 or export the file as CSV."
            case .conversionFailed(let message):
                return "Excel conversion failed: \(message)"
            case .noDataSheet:
                return "No suitable data sheet found in the Excel file."
            }
        }
    }

    /// Convert an Excel file to CSV text
    /// - Parameter url: URL to the .xlsx file
    /// - Returns: CSV text content
    static func convert(url: URL) throws -> String {
        // Python script to convert xlsx to CSV
        // Looks for sheets with directional data (MD, Inc, Azi columns)
        // Also extracts VS Azimuth from metadata rows
        let script = """
        import sys
        import re

        def extract_vs_azimuth(rows):
            '''Extract Vertical Section Azimuth from metadata rows'''
            for row in rows[:30]:  # Check first 30 rows for metadata
                row_str = ' '.join(str(v) if v else '' for v in row)
                # Look for patterns like "Vertical Section Azimuth: 285.761"
                patterns = [
                    r'Vertical Section Azimuth[:\\s]+([\\d.]+)',
                    r'VS Azimuth[:\\s]+([\\d.]+)',
                    r'VSD[:\\s]+([\\d.]+)',
                ]
                for pattern in patterns:
                    match = re.search(pattern, row_str, re.IGNORECASE)
                    if match:
                        return match.group(1)
            return None

        try:
            import openpyxl
        except ImportError:
            # Try with pandas as fallback
            try:
                import pandas as pd
                xlsx = pd.ExcelFile(sys.argv[1])

                best_sheet = None
                best_header_row = None
                vs_azimuth = None

                for sheet in xlsx.sheet_names:
                    df = pd.read_excel(xlsx, sheet_name=sheet, header=None)
                    # Find header row containing MD
                    for i in range(min(30, len(df))):
                        row_str = ' '.join(str(v) for v in df.iloc[i].values)
                        if 'MD' in row_str and ('Inc' in row_str or 'Incl' in row_str):
                            best_sheet = sheet
                            best_header_row = i
                            # Extract VS azimuth from rows above header
                            for j in range(i):
                                meta_str = ' '.join(str(v) for v in df.iloc[j].values)
                                match = re.search(r'Vertical Section Azimuth[:\\s]+([\\d.]+)', meta_str, re.IGNORECASE)
                                if match:
                                    vs_azimuth = match.group(1)
                                    break
                            break
                    if best_sheet:
                        break

                if not best_sheet:
                    print("ERROR: No sheet with MD/Inc columns found", file=sys.stderr)
                    sys.exit(1)

                # Read with proper header
                df = pd.read_excel(xlsx, sheet_name=best_sheet, header=best_header_row)

                # Clean column names (remove newlines)
                df.columns = [str(c).replace('\\n', ' ').replace('\\r', ' ').strip() for c in df.columns]

                # Output metadata comment if VS azimuth found
                if vs_azimuth:
                    print(f'# Vertical Section Azimuth: {vs_azimuth}')

                # Output as TSV
                print(df.to_csv(sep='\\t', index=False))
                sys.exit(0)
            except ImportError:
                print("ERROR: Neither openpyxl nor pandas is available", file=sys.stderr)
                sys.exit(1)

        # Use openpyxl directly
        wb = openpyxl.load_workbook(sys.argv[1], read_only=True, data_only=True)

        best_sheet = None
        best_header_row = None
        vs_azimuth = None

        for sheet_name in wb.sheetnames:
            sheet = wb[sheet_name]
            all_rows = list(sheet.iter_rows(max_row=50, values_only=True))
            for row_idx, row in enumerate(all_rows, 1):
                row_str = ' '.join(str(v) if v else '' for v in row)
                if 'MD' in row_str and ('Inc' in row_str or 'Incl' in row_str):
                    best_sheet = sheet_name
                    best_header_row = row_idx
                    # Extract VS azimuth from earlier rows
                    vs_azimuth = extract_vs_azimuth(all_rows[:row_idx])
                    break
            if best_sheet:
                break

        if not best_sheet:
            print("ERROR: No sheet with MD/Inc columns found", file=sys.stderr)
            sys.exit(1)

        sheet = wb[best_sheet]
        rows = list(sheet.iter_rows(min_row=best_header_row, values_only=True))

        if not rows:
            print("ERROR: No data rows found", file=sys.stderr)
            sys.exit(1)

        # Output metadata comment if VS azimuth found
        if vs_azimuth:
            print(f'# Vertical Section Azimuth: {vs_azimuth}')

        # Get headers and clean them
        headers = [str(h).replace('\\n', ' ').replace('\\r', ' ').strip() if h else '' for h in rows[0]]

        # Output as TSV
        print('\\t'.join(headers))
        for row in rows[1:]:
            if row and any(v is not None for v in row):
                values = [str(v) if v is not None else '' for v in row]
                print('\\t'.join(values))

        wb.close()
        """

        // Write script to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("xlsx_convert_\(UUID().uuidString).py")

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        // Run Python
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path, url.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ConversionError.pythonNotAvailable
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            if errorMessage.contains("openpyxl") || errorMessage.contains("pandas") {
                throw ConversionError.conversionFailed("Python packages openpyxl or pandas are required. Run: pip3 install openpyxl")
            }
            throw ConversionError.conversionFailed(errorMessage)
        }

        guard let csvText = String(data: outputData, encoding: .utf8), !csvText.isEmpty else {
            throw ConversionError.noDataSheet
        }

        return csvText
    }

    /// Check if Python 3 is available
    static var isPythonAvailable: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["--version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

#endif
