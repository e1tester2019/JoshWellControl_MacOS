//
//  HandoverNote.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-09.
//

import Foundation
import SwiftData

enum NoteCategory: String, Codable, CaseIterable {
    case general = "General"
    case safety = "Safety"
    case operations = "Operations"
    case equipment = "Equipment"
    case personnel = "Personnel"
    case handover = "Handover"
}

@Model
final class HandoverNote {
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var categoryRaw: String = NoteCategory.general.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var author: String = ""
    var isPinned: Bool = false

    @Relationship var well: Well?
    @Relationship var pad: Pad?  // Can be assigned to pad instead of well
    @Relationship var project: ProjectState?  // Optional: can be tied to specific project

    init(title: String = "",
         content: String = "",
         category: NoteCategory = .general,
         author: String = "",
         isPinned: Bool = false) {
        self.title = title
        self.content = content
        self.categoryRaw = category.rawValue
        self.author = author
        self.isPinned = isPinned
    }

    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .general }
        set {
            categoryRaw = newValue.rawValue
            updatedAt = Date.now
        }
    }

    func update(title: String? = nil, content: String? = nil) {
        if let t = title { self.title = t }
        if let c = content { self.content = c }
        updatedAt = Date.now
    }
}
