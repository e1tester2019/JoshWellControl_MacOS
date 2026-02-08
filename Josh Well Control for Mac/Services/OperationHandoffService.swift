//
//  OperationHandoffService.swift
//  Josh Well Control for Mac
//
//  Singleton for passing wellbore state between Trip Out, Trip In, and Pump Schedule views.
//

import Foundation

@Observable
final class OperationHandoffService {
    static let shared = OperationHandoffService()
    private init() {}

    /// Pending wellbore state snapshot for Trip In to pick up
    var pendingTripInState: WellboreStateSnapshot?

    /// Pending wellbore state snapshot for Trip Out to pick up
    var pendingTripOutState: WellboreStateSnapshot?

    /// Pending wellbore state snapshot for Pump Schedule to pick up
    var pendingPumpScheduleState: WellboreStateSnapshot?
}
