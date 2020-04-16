//
//  TrackingPreferenceViewController.swift
//  StopTouchingYourFace
//
//  Created by Matthew Spear on 25/03/2020.
//  Copyright © 2020 Matthew Spear. All rights reserved.
//

import AppKit

class TrackingPreferenceViewController: NSViewController {
    @IBOutlet var slowFramerateTextView: NSTextField!
    @IBOutlet var slowFramerateStepper: NSStepper!

    @IBOutlet var fastFramerateTextView: NSTextField!
    @IBOutlet var fastFramerateStepper: NSStepper!

    @IBOutlet var movementCooloffTextView: NSTextField!
    @IBOutlet var movementCooloffStepper: NSStepper!

    @IBOutlet var touchCooloffTextView: NSTextField!
    @IBOutlet var touchCooloffStepper: NSStepper!

    @IBOutlet var imageDistanceSlider: NSSlider!
    @IBOutlet var imageDistanceTextView: NSTextField!
    @IBOutlet var imageDistanceStepper: NSStepper!

    @IBOutlet var thresholdSlider: NSSlider!
    @IBOutlet var thresholdTextView: NSTextField!
    @IBOutlet var thresholdStepper: NSStepper!

    var pref = Preferences()

    override func viewDidLoad() {
        setupControls()
        updateLabels()
        updateControls()
    }

    func setupControls() {
        slowFramerateStepper.minValue = 1.0
        slowFramerateStepper.maxValue = 60.0
        slowFramerateStepper.increment = 1.0

        fastFramerateStepper.minValue = 1.0
        fastFramerateStepper.maxValue = 60.0
        fastFramerateStepper.increment = 1.0

        movementCooloffStepper.minValue = 0.0
        movementCooloffStepper.maxValue = 60.0
        movementCooloffStepper.increment = 0.5

        touchCooloffStepper.minValue = 0.0
        touchCooloffStepper.maxValue = 60.0
        touchCooloffStepper.increment = 0.5

        imageDistanceStepper.minValue = 0.0
        imageDistanceStepper.maxValue = 50.0
        imageDistanceStepper.increment = 0.5
        imageDistanceSlider.minValue = 0.0
        imageDistanceSlider.maxValue = 50.0

        thresholdStepper.minValue = 0.0
        thresholdStepper.maxValue = 1.0
        thresholdStepper.increment = 0.01
        thresholdSlider.minValue = 0.0
        thresholdSlider.maxValue = 1.0

        // setup textView delegates
        slowFramerateTextView.delegate = self
        fastFramerateTextView.delegate = self
        movementCooloffTextView.delegate = self
        touchCooloffTextView.delegate = self
        imageDistanceTextView.delegate = self
    }

    func updateLabels() {
        slowFramerateTextView.stringValue = String(format: "%2.1f", pref.slowFrameRate)
        fastFramerateTextView.stringValue = String(format: "%2.1f", pref.fastFrameRate)
        movementCooloffTextView.stringValue = String(format: "%2.1f", pref.movementCooloff)
        touchCooloffTextView.stringValue = String(format: "%2.1f", pref.touchCooloff)
        imageDistanceTextView.stringValue = String(format: "%2.1f", pref.imageDistanceThreshold)
        thresholdTextView.stringValue = String(format: "%2.2f", pref.handCoverageThreshold)
    }

    func updateControls() {
        slowFramerateStepper.doubleValue = pref.slowFrameRate
        fastFramerateStepper.doubleValue = pref.fastFrameRate
        movementCooloffStepper.doubleValue = pref.movementCooloff
        touchCooloffStepper.doubleValue = pref.touchCooloff
        imageDistanceStepper.doubleValue = Double(pref.imageDistanceThreshold)
        thresholdStepper.doubleValue = pref.handCoverageThreshold

        imageDistanceSlider.doubleValue = Double(pref.imageDistanceThreshold)
        thresholdSlider.doubleValue = pref.handCoverageThreshold
    }

    @IBAction func stepperAction(_ sender: NSStepper) {
        switch sender {
        case slowFramerateStepper:
            pref.slowFrameRate = slowFramerateStepper.doubleValue
        case fastFramerateStepper:
            pref.fastFrameRate = fastFramerateStepper.doubleValue
        case movementCooloffStepper:
            pref.movementCooloff = movementCooloffStepper.doubleValue
        case touchCooloffStepper:
            pref.touchCooloff = touchCooloffStepper.doubleValue
        case imageDistanceStepper:
            pref.imageDistanceThreshold = Float(imageDistanceStepper.doubleValue)
        case thresholdStepper:
            pref.handCoverageThreshold = thresholdStepper.doubleValue
        default:
            break
        }
        updateLabels()
        updateControls()
    }

    @IBAction func sliderAction(_ sender: NSSlider) {
        switch sender {
        case imageDistanceSlider:
            let newValue = Float(imageDistanceSlider.doubleValue)
            pref.imageDistanceThreshold = newValue
            imageDistanceTextView.stringValue = String(format: "%2.1f", newValue)

        case thresholdSlider:
            let newValue = thresholdSlider.doubleValue
            pref.handCoverageThreshold = newValue
            thresholdTextView.stringValue = String(format: "%2.2f", newValue)
        default:
            break
        }
    }

    @IBAction func resetAction(_: NSButton) {
        pref.reset()
        updateLabels()
        updateControls()
    }
}

extension TrackingPreferenceViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        let textField = notification.object as! NSTextField

        switch textField {
        case slowFramerateTextView:
            if let newValue = Double(slowFramerateTextView.stringValue) {
                pref.slowFrameRate = newValue
                slowFramerateStepper.doubleValue = newValue
            }
        case fastFramerateTextView:
            if let newValue = Double(fastFramerateTextView.stringValue) {
                pref.fastFrameRate = newValue
                fastFramerateStepper.doubleValue = newValue
            }
        case movementCooloffTextView:
            if let newValue = Double(movementCooloffTextView.stringValue) {
                pref.movementCooloff = newValue
                movementCooloffStepper.doubleValue = newValue
            }

        case touchCooloffTextView:
            if let newValue = Double(touchCooloffTextView.stringValue) {
                pref.touchCooloff = newValue
                touchCooloffStepper.doubleValue = newValue
            }

        case imageDistanceTextView:
            if let newValue = Float(imageDistanceTextView.stringValue) {
                pref.imageDistanceThreshold = newValue
                imageDistanceStepper.doubleValue = Double(newValue)
            }

        case thresholdTextView:
            if let newValue = Double(thresholdTextView.stringValue) {
                pref.handCoverageThreshold = newValue
                thresholdStepper.doubleValue = newValue
            }
        default:
            break
        }
    }
}
