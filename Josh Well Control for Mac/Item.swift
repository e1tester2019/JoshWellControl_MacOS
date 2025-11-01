//
//  Item.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-01.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
