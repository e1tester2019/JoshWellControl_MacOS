//
//  ViewSelection.swift
//  Josh Well Control for Mac
//
//  Shared view selection enum for navigation across platforms
//

import SwiftUI

enum ViewSelection: String, CaseIterable, Identifiable {
    // Dashboards
    case handover
    case padDashboard
    case wellDashboard
    case dashboard

    // Well Geometry
    case drillString
    case annulus
    case volumeSummary
    case surveys

    // Fluids & Mud
    case mudCheck
    case mixingCalc
    case mudPlacement

    // Analysis & Simulation
    case pressureWindow
    case pumpSchedule
    case cementJob
    case swabbing
    case surgeSwab
    case tripSimulation
    case tripInSimulation
    case tripTracker
    case tripRecord
    case mpdTracking
    case superSimulation
    case directionalPlanning

    // Operations - Look Ahead
    case lookAheadScheduler
    case vendors
    case jobCodes

    // Operations - Other
    case rentals
    case transfers
    case equipmentRegistry

    // Business - Income
    case shiftCalendar
    case workDays
    case invoices
    case clients

    // Business - Expenses
    case expenses
    case mileage

    // Business - Payroll
    case payroll
    case employees

    // Business - Dividends
    case dividends
    case shareholders

    // Business - Reports
    case companyStatement
    case expenseReport
    case payrollReport

    var id: String { rawValue }

    /// Whether this view requires PIN unlock to access
    var requiresBusinessUnlock: Bool {
        switch self {
        case .shiftCalendar, .workDays, .invoices, .clients, .expenses, .mileage,
             .payroll, .employees, .dividends, .shareholders, .companyStatement,
             .expenseReport, .payrollReport:
            return true
        default:
            return false
        }
    }

    // MARK: - Categories for Tab Organization

    enum Category: String, CaseIterable {
        case technical = "Technical"
        case operations = "Operations"
        case simulation = "Simulation"
        case income = "Income"
        case expensesCat = "Expenses"
        case payrollCat = "Payroll"
        case dividendsCat = "Dividends"
        case reports = "Reports"
        case more = "More"

        var icon: String {
            switch self {
            case .technical: return "gauge.with.dots.needle.67percent"
            case .operations: return "drop.fill"
            case .simulation: return "play.circle.fill"
            case .income: return "dollarsign.circle.fill"
            case .expensesCat: return "creditcard.fill"
            case .payrollCat: return "banknote.fill"
            case .dividendsCat: return "chart.line.uptrend.xyaxis"
            case .reports: return "chart.bar.doc.horizontal"
            case .more: return "ellipsis.circle.fill"
            }
        }
    }

    var category: Category {
        switch self {
        case .handover, .padDashboard, .wellDashboard, .dashboard, .drillString, .annulus, .volumeSummary, .surveys, .directionalPlanning:
            return .technical
        case .mudCheck, .mixingCalc, .pressureWindow, .mudPlacement, .swabbing, .surgeSwab:
            return .operations
        case .pumpSchedule, .cementJob, .tripSimulation, .tripInSimulation, .tripTracker, .tripRecord, .mpdTracking, .superSimulation:
            return .simulation
        case .lookAheadScheduler, .vendors, .jobCodes:
            return .operations
        case .shiftCalendar, .workDays, .invoices, .clients:
            return .income
        case .expenses, .mileage:
            return .expensesCat
        case .payroll, .employees:
            return .payrollCat
        case .dividends, .shareholders:
            return .dividendsCat
        case .companyStatement, .expenseReport, .payrollReport:
            return .reports
        case .rentals, .transfers, .equipmentRegistry:
            return .more
        }
    }

    static func viewsForCategory(_ category: Category) -> [ViewSelection] {
        allCases.filter { $0.category == category }
    }

    var title: String {
        switch self {
        case .handover: return "Handover"
        case .padDashboard: return "Pad Dashboard"
        case .wellDashboard: return "Well Dashboard"
        case .dashboard: return "Project Dashboard"
        case .drillString: return "Drill String"
        case .annulus: return "Annulus"
        case .volumeSummary: return "Volume Summary"
        case .surveys: return "Surveys"
        case .mudCheck: return "Mud Check"
        case .mixingCalc: return "Mixing Calculator"
        case .pressureWindow: return "Pressure Window"
        case .mudPlacement: return "Mud Placement"
        case .pumpSchedule: return "Pump Schedule"
        case .cementJob: return "Cement Job"
        case .swabbing: return "Swabbing"
        case .surgeSwab: return "Surge/Swab"
        case .tripSimulation: return "Trip Simulation"
        case .tripInSimulation: return "Trip In"
        case .superSimulation: return "Super Simulation"
        case .tripTracker: return "Trip Tracker"
        case .tripRecord: return "Trip Recording"
        case .mpdTracking: return "MPD Tracking"
        case .directionalPlanning: return "Directional Planning"
        case .lookAheadScheduler: return "Look Ahead"
        case .vendors: return "Vendors"
        case .jobCodes: return "Job Codes"
        case .rentals: return "Rentals"
        case .transfers: return "Material Transfers"
        case .equipmentRegistry: return "Equipment Registry"
        case .shiftCalendar: return "Shift Calendar"
        case .workDays: return "Work Days"
        case .invoices: return "Invoices"
        case .clients: return "Clients"
        case .expenses: return "Expenses"
        case .mileage: return "Mileage"
        case .payroll: return "Payroll"
        case .employees: return "Employees"
        case .dividends: return "Dividends"
        case .shareholders: return "Shareholders"
        case .companyStatement: return "Company Statement"
        case .expenseReport: return "Expense Report"
        case .payrollReport: return "Payroll Report"
        }
    }

    var icon: String {
        switch self {
        case .handover: return "list.clipboard"
        case .padDashboard: return "map"
        case .wellDashboard: return "building.2"
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .drillString: return "cylinder.split.1x2"
        case .annulus: return "circle.hexagonpath"
        case .volumeSummary: return "chart.bar.fill"
        case .surveys: return "location.north.circle.fill"
        case .mudCheck: return "drop.fill"
        case .mixingCalc: return "function"
        case .pressureWindow: return "waveform.path.ecg"
        case .mudPlacement: return "square.stack.3d.up.fill"
        case .pumpSchedule: return "timer"
        case .cementJob: return "cylinder.split.1x2.fill"
        case .swabbing: return "arrow.up.circle.fill"
        case .surgeSwab: return "arrow.up.arrow.down"
        case .tripSimulation: return "play.circle.fill"
        case .tripInSimulation: return "arrow.down.circle.fill"
        case .superSimulation: return "bolt.circle.fill"
        case .tripTracker: return "figure.walk.circle.fill"
        case .tripRecord: return "list.bullet.clipboard"
        case .mpdTracking: return "gauge.with.needle.fill"
        case .directionalPlanning: return "arrow.triangle.turn.up.right.diamond"
        case .lookAheadScheduler: return "calendar.badge.clock"
        case .vendors: return "person.2.badge.gearshape"
        case .jobCodes: return "list.bullet.rectangle"
        case .rentals: return "bag.fill"
        case .transfers: return "arrow.left.arrow.right.circle.fill"
        case .equipmentRegistry: return "shippingbox.fill"
        case .shiftCalendar: return "calendar.badge.clock"
        case .workDays: return "calendar"
        case .invoices: return "doc.text"
        case .clients: return "person.2"
        case .expenses: return "dollarsign.circle"
        case .mileage: return "car.fill"
        case .payroll: return "banknote"
        case .employees: return "person.3"
        case .dividends: return "chart.line.uptrend.xyaxis"
        case .shareholders: return "person.2.circle"
        case .companyStatement: return "building.columns"
        case .expenseReport: return "chart.bar"
        case .payrollReport: return "chart.pie"
        }
    }

    #if os(macOS)
    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .handover: return nil
        case .padDashboard: return nil
        case .wellDashboard: return "0"
        case .dashboard: return "1"
        case .drillString: return "2"
        case .annulus: return "3"
        case .volumeSummary: return "4"
        case .surveys: return "5"
        case .mudCheck: return "6"
        case .mixingCalc: return "7"
        case .pressureWindow: return "8"
        case .mudPlacement: return "9"
        default: return nil
        }
    }
    #endif

    var description: String {
        switch self {
        case .handover:
            return "Notes, tasks, and pad management across all wells"
        case .padDashboard:
            return "Pad overview, wells list, and handover items"
        case .wellDashboard:
            return "Well overview, projects, rentals, transfers, and handover items"
        case .dashboard:
            return "Project overview and configuration"
        case .drillString:
            return "Define drill string sections and geometry"
        case .annulus:
            return "Define annular sections and casing"
        case .volumeSummary:
            return "Well geometry volume analytics"
        case .surveys:
            return "Survey station data and trajectory"
        case .mudCheck:
            return "Mud properties and rheology"
        case .mixingCalc:
            return "Mud mixing and weight-up calculations"
        case .pressureWindow:
            return "Pore pressure and fracture gradient"
        case .mudPlacement:
            return "Mud placement and final layers"
        case .pumpSchedule:
            return "Pump program and hydraulics"
        case .cementJob:
            return "Cement job planning and calculations"
        case .swabbing:
            return "Swabbing analysis and charts"
        case .surgeSwab:
            return "Surge/swab pressure calculator with closed-end displacement"
        case .tripSimulation:
            return "Trip simulation and modeling"
        case .tripInSimulation:
            return "Simulate running pipe into well with floated casing support"
        case .superSimulation:
            return "Chain trip and circulation operations with continuous wellbore state tracking"
        case .tripTracker:
            return "Process-based step-by-step trip tracking"
        case .tripRecord:
            return "Record actual trip observations vs simulation predictions"
        case .mpdTracking:
            return "Managed Pressure Drilling ECD/ESD tracking"
        case .directionalPlanning:
            return "Compare actual wellbore trajectory against planned path with variance analysis"
        case .lookAheadScheduler:
            return "Drilling operations scheduler with vendor call tracking"
        case .vendors:
            return "Manage service providers and contacts"
        case .jobCodes:
            return "Task categories with learned duration estimates"
        case .rentals:
            return "Equipment rental tracking"
        case .transfers:
            return "Material transfer management"
        case .equipmentRegistry:
            return "Track rental equipment across wells with issue logging"
        case .shiftCalendar:
            return "Shift rotation tracking with auto work day creation and end-of-shift reminders"
        case .workDays:
            return "Track work days for clients"
        case .invoices:
            return "Generate and manage invoices"
        case .clients:
            return "Manage client information"
        case .expenses:
            return "Track business expenses"
        case .mileage:
            return "Log mileage for CRA deductions"
        case .payroll:
            return "Manage pay runs and stubs"
        case .employees:
            return "Employee information"
        case .dividends:
            return "Dividend declarations and payments"
        case .shareholders:
            return "Manage shareholder information"
        case .companyStatement:
            return "Annual and quarterly financial statements"
        case .expenseReport:
            return "Expense summaries and analysis"
        case .payrollReport:
            return "Payroll summaries and T4 prep"
        }
    }
}
