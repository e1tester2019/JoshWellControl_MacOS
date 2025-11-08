//
//  Well.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import Foundation
import SwiftData

@Model
final class Well {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = "New Well"
    var uwi: String? = nil
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade) var projects: [ProjectState] = []

    init(name: String = "New Well", uwi: String? = nil) {
        self.name = name
        self.uwi = uwi
    }
}
