//
//  ViewSelection.swift
//  Josh Well Control for Mac
//
//  Shared view selection enum for navigation across platforms
//

import SwiftUI

enum ViewSelection: String, CaseIterable, Identifiable {
    case wellsDashboard
    case dashboard
    case drillString
    case annulus
    case volumeSummary
    case surveys
    case mudCheck
    case mixingCalc
    case pressureWindow
    case mudPlacement
    case pumpSchedule
    case cementJob
    case swabbing
    case tripSimulation
    case rentals
    case transfers
    case workTracking

    var id: String { rawValue }

    // MARK: - Categories for Tab Organization

    enum Category: String, CaseIterable {
        case technical = "Technical"
        case operations = "Operations"
        case simulation = "Simulation"
        case business = "Business"
        case more = "More"

        var icon: String {
            switch self {
            case .technical: return "gauge.with.dots.needle.67percent"
            case .operations: return "drop.fill"
            case .simulation: return "play.circle.fill"
            case .business: return "dollarsign.circle.fill"
            case .more: return "ellipsis.circle.fill"
            }
        }
    }

    var category: Category {
        switch self {
        case .dashboard, .drillString, .annulus, .volumeSummary, .surveys:
            return .technical
        case .mudCheck, .mixingCalc, .pressureWindow, .mudPlacement, .swabbing:
            return .operations
        case .pumpSchedule, .cementJob, .tripSimulation:
            return .simulation
        case .workTracking:
            return .business
        case .rentals, .transfers:
            return .more
        }
    }

    static func viewsForCategory(_ category: Category) -> [ViewSelection] {
        allCases.filter { $0.category == category }
    }

    var title: String {
        switch self {
        case .wellsDashboard: return "Wells Dashboard"
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
        case .tripSimulation: return "Trip Simulation"
        case .rentals: return "Rentals"
        case .transfers: return "Material Transfers"
        case .workTracking: return "Work Tracking"
        }
    }

    var icon: String {
        switch self {
        case .wellsDashboard: return "list.clipboard"
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
        case .tripSimulation: return "play.circle.fill"
        case .rentals: return "bag.fill"
        case .transfers: return "arrow.left.arrow.right.circle.fill"
        case .workTracking: return "dollarsign.circle.fill"
        }
    }

    #if os(macOS)
    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .wellsDashboard: return "0"
        case .dashboard: return "1"
        case .drillString: return "2"
        case .annulus: return "3"
        case .volumeSummary: return "4"
        case .surveys: return "5"
        case .mudCheck: return "6"
        case .mixingCalc: return "7"
        case .pressureWindow: return "8"
        case .mudPlacement: return "9"
        case .pumpSchedule: return nil
        case .cementJob: return nil
        case .swabbing: return nil
        case .tripSimulation: return nil
        case .rentals: return nil
        case .transfers: return nil
        case .workTracking: return nil
        }
    }
    #endif

    var description: String {
        switch self {
        case .wellsDashboard:
            return "Tasks and handover notes across all wells"
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
        case .tripSimulation:
            return "Trip simulation and modeling"
        case .rentals:
            return "Equipment rental tracking"
        case .transfers:
            return "Material transfer management"
        case .workTracking:
            return "Track work days and generate invoices"
        }
    }
}
