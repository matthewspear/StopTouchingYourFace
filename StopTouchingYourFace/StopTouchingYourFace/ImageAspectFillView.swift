//
//  ImageAspectFillView.swift
//  StopTouchingYourFace
//
//  Created by Matthew Spear on 19/03/2020.
//  Copyright © 2020 Matthew Spear. All rights reserved.
//

import AppKit

class ImageAspectFillView: NSImageView {
    override var image: NSImage? {
        set {
            layer = CALayer()
            layer?.contentsGravity = .resizeAspectFill
            layer?.contents = newValue
            wantsLayer = true
            super.image = newValue
        }

        get {
            return super.image
        }
    }
}
