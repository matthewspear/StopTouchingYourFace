//
//  Preferences.swift
//  StopTouchingYourFace
//
//  Created by Matthew Spear on 22/03/2020.
//  Copyright © 2020 Matthew Spear. All rights reserved.
//

import Foundation

struct Preferences {
    private let slowFrameRateKey = "StopTouchingYourFace.slowFrameRate"
    var slowFrameRate: Double {
        set { UserDefaults.standard.set(newValue, forKey: slowFrameRateKey) }
        get { return UserDefaults.standard.double(forKey: slowFrameRateKey) }
    }

    private let fastFrameRateKey = "StopTouchingYourFace.fastFrameRate"
    var fastFrameRate: Double {
        set { UserDefaults.standard.set(newValue, forKey: fastFrameRateKey) }
        get { return UserDefaults.standard.double(forKey: fastFrameRateKey) }
    }

    private let imageDistanceThresholdKey = "StopTouchingYourFace.imageDistanceThreshold"
    var imageDistanceThreshold: Float {
        set { UserDefaults.standard.set(newValue, forKey: imageDistanceThresholdKey) }
        get { return UserDefaults.standard.float(forKey: imageDistanceThresholdKey) }
    }

    private let handCoverageThresholdKey = "StopTouchingYourFace.handCoverageThresholdKey"
    var handCoverageThreshold: Double {
        set { UserDefaults.standard.set(newValue, forKey: handCoverageThresholdKey) }
        get { return UserDefaults.standard.double(forKey: handCoverageThresholdKey) }
    }

    private let movementCooloffKey = "StopTouchingYourFace.movementCooloff"
    var movementCooloff: Double {
        set { UserDefaults.standard.set(newValue, forKey: movementCooloffKey) }
        get { return UserDefaults.standard.double(forKey: movementCooloffKey) }
    }

    private let touchCooloffKey = "StopTouchingYourFace.touchCooloff"
    var touchCooloff: Double {
        set { UserDefaults.standard.set(newValue, forKey: touchCooloffKey) }
        get { return UserDefaults.standard.double(forKey: touchCooloffKey) }
    }

    func registerDefaults() {
        UserDefaults.standard.register(
            defaults: [
                slowFrameRateKey: 5.0, // per second
                fastFrameRateKey: 15.0, // per second
                movementCooloffKey: 3.0, // seconds
                touchCooloffKey: 5.0, // seconds
                imageDistanceThresholdKey: 7.5, // sensitivity (the lower the more sensitive)
                handCoverageThresholdKey: 0.04,
            ]
        )
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: slowFrameRateKey)
        UserDefaults.standard.removeObject(forKey: fastFrameRateKey)
        UserDefaults.standard.removeObject(forKey: imageDistanceThresholdKey)
        UserDefaults.standard.removeObject(forKey: handCoverageThresholdKey)
        UserDefaults.standard.removeObject(forKey: movementCooloffKey)
        UserDefaults.standard.removeObject(forKey: touchCooloffKey)
        registerDefaults()
        UserDefaults.standard.synchronize()
    }

    func sync() {
        UserDefaults.standard.synchronize()
    }
}
