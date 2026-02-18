//
//  DailyCycle.swift
//  BatteryTracker
//
//  Created by Dominic Docimo on 2/17/26.
//

import Foundation
import SwiftData

@Model
final class DailyCycle {
    @Attribute(.unique) var date: Date
    var cycles: Int
    var rawCycles: Double
    var totalMahUsed: Double
    var timeOnBattery: Double
    var timePluggedIn: Double

    init(date: Date,
         cycles: Int,
         rawCycles: Double = 0,
         totalMahUsed: Double = 0,
         timeOnBattery: Double = 0,
         timePluggedIn: Double = 0) {
        self.date = date
        self.cycles = cycles
        self.rawCycles = rawCycles
        self.totalMahUsed = totalMahUsed
        self.timeOnBattery = timeOnBattery
        self.timePluggedIn = timePluggedIn
    }
}
