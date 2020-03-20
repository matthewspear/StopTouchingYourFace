//
//  Utillities.swift
//  StopTouchingYourFace
//
//  Created by Matthew Spear on 20/03/2020.
//  Copyright © 2020 Matthew Spear. All rights reserved.
//

import AppKit

extension NSView {
    var backgroundColor: NSColor? {
        get {
            if let colorRef = layer?.backgroundColor {
                return NSColor(cgColor: colorRef)
            } else {
                return nil
            }
        }

        set {
            wantsLayer = true
            layer?.backgroundColor = newValue?.cgColor
        }
    }
}
