//
//  AppFlags.swift
//  Habit Tracker
//
//  Created by John Fuller on 5/1/26.
//


import Foundation

enum AppFlags {
    #if DEBUG
    static let showDevTools = false
    #else
    static let showDevTools = false
    #endif
}