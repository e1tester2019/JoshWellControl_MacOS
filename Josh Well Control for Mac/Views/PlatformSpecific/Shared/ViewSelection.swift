//
//  ViewSelection.swift
//  Josh Well Control for Mac
//
//  Shared view selection enum for navigation across platforms
//

import SwiftUI

enum ViewSelection: String, CaseIterable, Identifiable {
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
    case swabbing
    case tripSimulation
    case rentals
    case transfers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .drillString: return "Drill String"
        case .annulus: return "Annulus"
        case .volumeSummary: return "Volume Summary"
        case .surveys: return "Surveys"
        case .mudCheck: return "Mud Check"
        case .mixingCalc: return "Mixing Calculator"
        case .pressureWindow: return "Pressure Window"
        case .mudPlacement: return "Mud Placement"
        case .pumpSchedule: return "Pump Schedule"
        case .swabbing: return "Swabbing"
        case .tripSimulation: return "Trip Simulation"
        case .rentals: return "Rentals"
        case .transfers: return "Material Transfers"
        }
    }

    var icon: String {
        switch self {
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
        case .swabbing: return "arrow.up.circle.fill"
        case .tripSimulation: return "play.circle.fill"
        case .rentals: return "bag.fill"
        case .transfers: return "arrow.left.arrow.right.circle.fill"
        }
    }

    #if os(macOS)
    var keyboardShortcut: KeyEquivalent? {
        switch self {
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
        case .swabbing: return nil
        case .tripSimulation: return nil
        case .rentals: return nil
        case .transfers: return nil
        }
    }
    #endif

    var description: String {
        switch self {
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
        case .swabbing:
            return "Swabbing analysis and charts"
        case .tripSimulation:
            return "Trip simulation and modeling"
        case .rentals:
            return "Equipment rental tracking"
        case .transfers:
            return "Material transfer management"
        }
    }
}
