//
//  FixtureEmitter.swift
//
//  In-xcodeproj fixture emitter for Tier C SuperSim regression tests.
//
//  Lives as an XCTest unit-test bundle hosted by the Mac app so it can
//  `@testable import` the real @Model SwiftData classes without stubs.
//
//  Each fixture-emit method writes one JSON file to the SuperSim Fixtures
//  directory in the canonical envelope:
//      { "service": "...", "case": "...", "input": {...}, "output": {...} }
//
//  Run all:
//      xcodebuild test \
//        -project "Josh Well Control for Mac.xcodeproj" \
//        -scheme  "FixtureEmitter" \
//        -destination "platform=macOS"
//
//  Run a subset:
//      ... -only-testing:FixtureEmitter/NumericalTripModelFixtures
//

import Foundation
import XCTest

@testable import Josh_Well_Control_for_Mac

/// Writes a fixture JSON to <root>/<service>/<case>.json with sorted keys
/// for diff stability. Mirrors `FixtureWriter.write` from SwiftFixtureCLI.
enum FixtureWriter {
    /// Default output directory matches the SwiftFixtureCLI default so both
    /// emitters land in the same Fixtures/ tree consumed by the C# tests.
    static let defaultRoot = URL(fileURLWithPath:
        "/Users/joshsallows/RiderProjects/supersim/tests/SuperSim.Core.Tests/Fixtures")

    static func write(service: String,
                      caseName: String,
                      input: Any,
                      output: Any,
                      root: URL = defaultRoot) throws {
        let payload: [String: Any] = [
            "service": service,
            "case": caseName,
            "input": input,
            "output": output,
        ]
        let dir = root.appendingPathComponent(service, isDirectory: true)
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(caseName).json")
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
    }
}

/// Smoke test — verifies the target compiles, the @testable import resolves,
/// and FixtureWriter can write into the fixture directory. Each Tier C
/// service gets its own XCTestCase subclass alongside this one.
final class FixtureEmitterSmokeTests: XCTestCase {
    func testTargetCompilesAndImportsAppModule() throws {
        // Touching a real internal type proves @testable import works at
        // both compile and link time.
        let g = HydraulicsDefaults.gravity_mps2
        XCTAssertEqual(g, 9.81, accuracy: 1e-9)
    }

    func testFixtureWriterRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fixture-emitter-smoke-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try FixtureWriter.write(
            service: "_smoke",
            caseName: "roundtrip",
            input: ["x": 1.0],
            output: ["y": 2.0],
            root: tmp)

        let file = tmp.appendingPathComponent("_smoke/roundtrip.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        let data = try Data(contentsOf: file)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["service"] as? String, "_smoke")
        XCTAssertEqual(obj?["case"] as? String, "roundtrip")
    }
}
