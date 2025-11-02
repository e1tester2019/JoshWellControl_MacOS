//
//  Binding+NilReplace.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

import Foundation
import SwiftUI

extension Binding where Value == String? {
    init(_ source: Binding<String?>, replacingNilWith placeholder: String) {
        self.init(
            get: { source.wrappedValue ?? placeholder },
            set: { newValue in
                if let text = newValue, !text.isEmpty {
                    source.wrappedValue = text
                } else {
                    source.wrappedValue = nil
                }
            }
        )
    }
}

extension Binding where Value == Double? {
    init(_ source: Binding<Double?>, default def: Double) {
        self.init(get: { source.wrappedValue ?? def },
                  set: { source.wrappedValue = $0 })
    }
}
