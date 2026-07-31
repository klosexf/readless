//
//  Item.swift
//  readless
//
//  Created by 陈晓峰 on 2026/7/31.
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
