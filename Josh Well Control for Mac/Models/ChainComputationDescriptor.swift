//
//  ChainComputationDescriptor.swift
//  Josh Well Control for Mac
//
//  Created by OpenAI.
//

import Foundation

struct ChainVariableDefinition: Identifiable, Hashable {
    let key: String
    let label: String
    let unit: String?
    let placeholder: String?
    let isShared: Bool
    let footnote: String?

    var id: String { key }
}

struct ChainComputationDescriptor {
    let type: ChainComputationType
    let title: String
    let subtitle: String
    let symbolName: String
    let inputs: [ChainVariableDefinition]
    let outputs: [ChainVariableDefinition]
    let compute: (_ inputs: [String: Double]) -> [String: Double]
}

enum ChainComputationType: String, CaseIterable, Identifiable {
    case hydrostaticPressure
    case annularFriction
    case bottomHolePressure
    case requiredSBP

    var id: String { rawValue }
}

enum ChainComputationLibrary {
    static func descriptor(for type: ChainComputationType) -> ChainComputationDescriptor {
        switch type {
        case .hydrostaticPressure:
            return ChainComputationDescriptor(
                type: type,
                title: "Hydrostatic Pressure",
                subtitle: "Gradient × TVD for a single fluid",
                symbolName: "gauge.medium",
                inputs: [
                    ChainVariableDefinition(
                        key: "tvd_m",
                        label: "True vertical depth",
                        unit: "m",
                        placeholder: "3200",
                        isShared: true,
                        footnote: "Used wherever depth is required"
                    ),
                    ChainVariableDefinition(
                        key: "fluidDensity_kgm3",
                        label: "Fluid density",
                        unit: "kg/m³",
                        placeholder: "1260",
                        isShared: true,
                        footnote: "Feeds other density-aware computations"
                    )
                ],
                outputs: [
                    ChainVariableDefinition(
                        key: "hydrostaticPressure_kPa",
                        label: "Hydrostatic pressure",
                        unit: "kPa",
                        placeholder: nil,
                        isShared: true,
                        footnote: "Feeds BHP & SBP computations"
                    ),
                    ChainVariableDefinition(
                        key: "hydrostaticGradient_kPa_per_m",
                        label: "Hydrostatic gradient",
                        unit: "kPa/m",
                        placeholder: nil,
                        isShared: true,
                        footnote: "Can be reused as a friction estimate"
                    )
                ]
            ) { values in
                guard
                    let tvd = values["tvd_m"],
                    let density = values["fluidDensity_kgm3"]
                else { return [:] }
                let grad = HydraulicsCalculator.grad_kPa_per_m(density_kg_per_m3: density)
                return [
                    "hydrostaticPressure_kPa": grad * tvd,
                    "hydrostaticGradient_kPa_per_m": grad
                ]
            }

        case .annularFriction:
            return ChainComputationDescriptor(
                type: type,
                title: "Annular Friction",
                subtitle: "Estimate kPa/m from flow and geometry",
                symbolName: "arrow.triangle.branch",
                inputs: [
                    ChainVariableDefinition(
                        key: "flowRate_m3_per_s",
                        label: "Flow rate",
                        unit: "m³/s",
                        placeholder: "0.028",
                        isShared: true,
                        footnote: "Shared with other hydraulics calculations"
                    ),
                    ChainVariableDefinition(
                        key: "fluidDensity_kgm3",
                        label: "Fluid density",
                        unit: "kg/m³",
                        placeholder: "1260",
                        isShared: true,
                        footnote: "Couples with hydrostatic computations"
                    ),
                    ChainVariableDefinition(
                        key: "viscosity_Pa_s",
                        label: "Viscosity",
                        unit: "Pa·s",
                        placeholder: "0.02",
                        isShared: true,
                        footnote: "Use apparent viscosity for rheology"
                    ),
                    ChainVariableDefinition(
                        key: "annulusID_m",
                        label: "Annulus ID",
                        unit: "m",
                        placeholder: "0.216",
                        isShared: true,
                        footnote: "Typically casing ID"
                    ),
                    ChainVariableDefinition(
                        key: "stringOD_m",
                        label: "String OD",
                        unit: "m",
                        placeholder: "0.127",
                        isShared: true,
                        footnote: "Typically drill string OD"
                    )
                ],
                outputs: [
                    ChainVariableDefinition(
                        key: "frictionGrad_kPa_per_m",
                        label: "Friction gradient",
                        unit: "kPa/m",
                        placeholder: nil,
                        isShared: true,
                        footnote: "Feeds BHP & SBP targets"
                    )
                ]
            ) { values in
                guard
                    let q = values["flowRate_m3_per_s"],
                    let density = values["fluidDensity_kgm3"],
                    let mu = values["viscosity_Pa_s"],
                    let id = values["annulusID_m"],
                    let od = values["stringOD_m"]
                else { return [:] }

                let grad = HydraulicsCalculator.annularFrictionGrad_kPa_per_m(
                    flowRate_m3_per_s: q,
                    density_kg_per_m3: density,
                    viscosity_Pa_s: mu,
                    ID_m: id,
                    OD_m: od,
                    roughness_m: 4.6e-5
                )
                return ["frictionGrad_kPa_per_m": max(grad, 0)]
            }

        case .bottomHolePressure:
            return ChainComputationDescriptor(
                type: type,
                title: "Bottom-hole Pressure",
                subtitle: "Combine SBP + hydrostatic + friction",
                symbolName: "target",
                inputs: [
                    ChainVariableDefinition(
                        key: "hydrostaticPressure_kPa",
                        label: "Hydrostatic pressure",
                        unit: "kPa",
                        placeholder: nil,
                        isShared: true,
                        footnote: "Output from hydrostatic node"
                    ),
                    ChainVariableDefinition(
                        key: "frictionGrad_kPa_per_m",
                        label: "Friction gradient",
                        unit: "kPa/m",
                        placeholder: "0.5",
                        isShared: true,
                        footnote: "Can come from annular friction"
                    ),
                    ChainVariableDefinition(
                        key: "tvd_m",
                        label: "True vertical depth",
                        unit: "m",
                        placeholder: "3200",
                        isShared: true,
                        footnote: nil
                    ),
                    ChainVariableDefinition(
                        key: "sbp_kPa",
                        label: "Surface back pressure",
                        unit: "kPa",
                        placeholder: "0",
                        isShared: true,
                        footnote: "Shared with SBP solver"
                    )
                ],
                outputs: [
                    ChainVariableDefinition(
                        key: "bhp_kPa",
                        label: "Bottom-hole pressure",
                        unit: "kPa",
                        placeholder: nil,
                        isShared: true,
                        footnote: "Feed target comparisons"
                    )
                ]
            ) { values in
                guard
                    let hydro = values["hydrostaticPressure_kPa"],
                    let grad = values["frictionGrad_kPa_per_m"],
                    let tvd = values["tvd_m"],
                    let sbp = values["sbp_kPa"]
                else { return [:] }
                let dynamic = max(grad, 0) * max(tvd, 0)
                return ["bhp_kPa": sbp + hydro + dynamic]
            }

        case .requiredSBP:
            return ChainComputationDescriptor(
                type: type,
                title: "Required SBP",
                subtitle: "What choke pressure hits the target BHP?",
                symbolName: "dial.max",
                inputs: [
                    ChainVariableDefinition(
                        key: "targetBHP_kPa",
                        label: "Target BHP",
                        unit: "kPa",
                        placeholder: "28000",
                        isShared: true,
                        footnote: "Can come from another chain"
                    ),
                    ChainVariableDefinition(
                        key: "hydrostaticPressure_kPa",
                        label: "Hydrostatic pressure",
                        unit: "kPa",
                        placeholder: nil,
                        isShared: true,
                        footnote: nil
                    ),
                    ChainVariableDefinition(
                        key: "frictionGrad_kPa_per_m",
                        label: "Friction gradient",
                        unit: "kPa/m",
                        placeholder: "0.5",
                        isShared: true,
                        footnote: nil
                    ),
                    ChainVariableDefinition(
                        key: "tvd_m",
                        label: "True vertical depth",
                        unit: "m",
                        placeholder: "3200",
                        isShared: true,
                        footnote: nil
                    )
                ],
                outputs: [
                    ChainVariableDefinition(
                        key: "sbp_kPa",
                        label: "Required SBP",
                        unit: "kPa",
                        placeholder: nil,
                        isShared: true,
                        footnote: "Feeds BHP nodes"
                    )
                ]
            ) { values in
                guard
                    let target = values["targetBHP_kPa"],
                    let hydro = values["hydrostaticPressure_kPa"],
                    let grad = values["frictionGrad_kPa_per_m"],
                    let tvd = values["tvd_m"]
                else { return [:] }
                let friction = max(grad, 0) * max(tvd, 0)
                return ["sbp_kPa": max(target - hydro - friction, 0)]
            }
        }
    }

    static func metadata(for key: String) -> ChainVariableDefinition? {
        for type in ChainComputationType.allCases {
            let desc = descriptor(for: type)
            if let match = (desc.inputs + desc.outputs).first(where: { $0.key == key }) {
                return match
            }
        }
        return nil
    }
}

extension ChainComputationType {
    var descriptor: ChainComputationDescriptor {
        ChainComputationLibrary.descriptor(for: self)
    }
}
