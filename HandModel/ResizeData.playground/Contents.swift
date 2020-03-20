
import PlaygroundSupport
import UIKit
import Vision

func processImage(for name: String) {
    
    // Load image

    let imageURL = Bundle.main.url(forResource: "images_original_size/\(name)", withExtension: "jpg")!

    let imageData = try! Data(contentsOf: imageURL)
    let image = UIImage(data: imageData)!
    let imageView = UIImageView(image: image)

    // Get face bounding box

    let faceRectangleRequest = VNDetectFaceRectanglesRequest { request, error in
        if error != nil {
            print("Face Recognition error: \(String(describing: error)).")
        }

        guard let rectangleRequest = request as? VNDetectFaceRectanglesRequest,
            let results = rectangleRequest.results as? [VNFaceObservation] else {
            print("NO RESULT")
            return
        }

        var boundingBoxRect: CGRect

        let originalWidth = image.size.width
        let originalHeight = image.size.height

        if let faceBoundingBox = results.first?.boundingBox {
            boundingBoxRect = CGRect(
                x: faceBoundingBox.minX * originalWidth,
                y: faceBoundingBox.minY * originalHeight,
                width: faceBoundingBox.width * originalWidth,
                height: faceBoundingBox.height * originalHeight
            )

        } else {
            boundingBoxRect = CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight)
        }

        let path = CGPath(rect: boundingBoxRect, transform: nil)
        let boundingBox = CAShapeLayer()
        boundingBox.path = path
        boundingBox.fillColor = UIColor.clear.cgColor
        boundingBox.strokeColor = UIColor.green.cgColor
        boundingBox.lineWidth = 3.0

        imageView.layer.addSublayer(boundingBox)
        imageView

        print(results)

        let landscape = originalWidth > originalHeight

        let squareSize = landscape ? originalHeight : originalWidth
        // Crop

        let cropRect = CGRect(
            x: boundingBoxRect.midX - squareSize / 2.0,
            y: 0.0,
            width: squareSize,
            height: squareSize
        )

        UIGraphicsBeginImageContextWithOptions(cropRect.size, false, image.scale)
        let origin = CGPoint(x: cropRect.origin.x * CGFloat(-1), y: cropRect.origin.y * CGFloat(-1))
        image.draw(at: origin)
        let cropped = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Resize image

        let newSize = CGSize(width: 224.0, height: 224.0)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, UIScreen.main.scale)
        cropped!.draw(in: rect)
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        resized

        let outputImage = resized?.jpegData(compressionQuality: 1.0)
        let outputFolder = playgroundSharedDataDirectory.appendingPathComponent("images")
        try! outputImage?.write(to: outputFolder.appendingPathComponent("\(name).jpg"))

        // Process masks form XML annotations

        let maskURL = Bundle.main.url(forResource: "annotations/\(name)", withExtension: "xml")!
        let parser = XMLParser(contentsOf: maskURL)

        class AnnotationParser: NSObject, XMLParserDelegate {
            var polygons: [[CGPoint]] = []
            var currentPolygon: [CGPoint]?
            var currentPoint: CGPoint?
            var readX = false
            var readY = false

            func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes _: [String: String] = [:]) {
                switch elementName {
                case "polygon":
                    currentPolygon = []
                    readX = false
                    readY = false
                case "pt":
                    currentPoint = CGPoint()
                    readX = false
                    readY = false

                case "x":
                    readX = true
                    readY = false

                case "y":
                    readX = false
                    readY = true
                default:
                    break
                }
            }

            func parser(_: XMLParser, foundCharacters string: String) {
                if readX {
                    currentPoint?.x = CGFloat(Int(string)!)
                }

                if readY {
                    currentPoint?.y = CGFloat(Int(string)!)
                }
            }

            func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
                if elementName == "polygon", let polygon = currentPolygon {
                    polygons.append(polygon)
                    currentPolygon = nil
                }

                if elementName == "pt", let point = currentPoint {
                    currentPolygon?.append(point)
                    currentPoint = nil
                }
            }
        }

        let annotationDelegate = AnnotationParser()
        parser?.delegate = annotationDelegate
        parser?.parse()

        let renderer = UIGraphicsImageRenderer(size: image.size)
        let maskImage = renderer.image { context in

            // Fill background
            let background = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.addRect(background)
            context.cgContext.drawPath(using: .fillStroke)

            for points in annotationDelegate.polygons {
                context.cgContext.move(to: points[0])

                for point in points[1...] {
                    context.cgContext.addLine(to: CGPoint(x: point.x, y: point.y))
                }

                context.cgContext.setStrokeColor(UIColor.white.cgColor)
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.setLineWidth(0)
                context.cgContext.drawPath(using: .fillStroke)
            }
        }

        let maskOriginalWidth = maskImage.size.width
        let maskOriginalHeight = maskImage.size.height
        let squareMaskSize = landscape ? maskOriginalHeight : maskOriginalWidth

        let cropMaskRect = CGRect(
            x: (cropRect.minX / originalWidth) * maskOriginalWidth,
            y: 0.0,
            width: squareMaskSize,
            height: squareMaskSize
        )

        UIGraphicsBeginImageContextWithOptions(cropMaskRect.size, false, image.scale)
        let maskOrigin = CGPoint(x: cropMaskRect.origin.x * CGFloat(-1), y: cropMaskRect.origin.y * CGFloat(-1))
        maskImage.draw(at: maskOrigin)
        let croppedMask = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        cropped
        
        croppedMask

        // Resize mask image

        UIGraphicsBeginImageContextWithOptions(newSize, false, UIScreen.main.scale)
        croppedMask!.draw(in: rect)

        let resizedMask = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        resizedMask

        let outputMaskImage = resizedMask?.jpegData(compressionQuality: 1.0)
        let maskFolder = playgroundSharedDataDirectory.appendingPathComponent("masks")

        try! outputMaskImage?.write(to: maskFolder.appendingPathComponent("\(name).jpg"))
    }

    let imageRequestHandler = VNImageRequestHandler(url: imageURL, orientation: .downMirrored, options: [:])

    do {
        try imageRequestHandler.perform([faceRectangleRequest])
    } catch let error as NSError {
        NSLog("Failed to perform FaceLandmarkRequest: %@", error)
    }
}

// Create folders

let outputFolder = playgroundSharedDataDirectory.appendingPathComponent("images")
let maskFolder = playgroundSharedDataDirectory.appendingPathComponent("masks")

if !FileManager.default.fileExists(atPath: outputFolder.path) {
    try! FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true, attributes: nil)
}

if !FileManager.default.fileExists(atPath: maskFolder.path) {
    try! FileManager.default.createDirectory(at: maskFolder, withIntermediateDirectories: true, attributes: nil)
}

// processImage(for: "1")

for index in 1 ... 302 {
    if index == 133 || index == 166 { continue }
    print(index)
    processImage(for: "\(index)")
}

print("Writing to \(outputFolder.path)")
