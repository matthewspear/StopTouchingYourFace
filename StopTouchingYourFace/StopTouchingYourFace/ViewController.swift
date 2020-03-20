//
//  ViewController.swift
//  StopTouchingYourFace
//
//  Created by Matthew Spear on 18/03/2020.
//  Copyright © 2020 Matthew Spear. All rights reserved.
//

import AVFoundation
import Cocoa
import Vision

private enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
}

class ViewController: NSViewController {
    @IBOutlet var previewView: NSView!
    @IBOutlet var maskImageView: ImageAspectFillView!
    @IBOutlet var movementIndicator: NSView!

    // AVCapture Session variables
    var session = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?

    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!

    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?

    var captureDevice: AVCaptureDevice?
    var captureDeviceResolution: CGSize = CGSize()

    // Layer UI for drawing Vision results
    var rootLayer: CALayer?
    var detectionOverlayLayer: CALayer?
    var detectedFaceRectangleShapeLayer: CAShapeLayer?
    var detectedFaceLandmarksShapeLayer: CAShapeLayer?

    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var setupResult: SessionSetupResult = .success

    var lastFeaturePrint: VNFeaturePrintObservation?

    var lastMovement = Date.timeIntervalSinceReferenceDate
    var lastFrame = Date.timeIntervalSinceReferenceDate

    var audioPlayer: AVAudioPlayer?

    // parameters
    var displayPreview = true

    var frameRate = 2.0 // per second

    let slowFrameRate = 5.0 // per second
    let fastFrameRate = 15.0 // per second

    let imageDistanceThreshold: Float = 7.5 // sensitivity (the lower the more sensitive)

    let movementCoolOff = 3.0 // seconds
    let touchCoolOff = 5.0 // seconds

    override func viewDidLoad() {
        super.viewDidLoad()

        setupPermissions()
        setupAudioPlayer()

        movementIndicator.backgroundColor = #colorLiteral(red: 0.8549019694, green: 0.250980407, blue: 0.4784313738, alpha: 1)
        movementIndicator.layer?.cornerRadius = movementIndicator.frame.width / 2.0
        movementIndicator.alphaValue = 0.8
        maskImageView.alphaValue = 0.8

        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.

         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()

            if self.displayPreview {
                DispatchQueue.main.async {
                    self.setupVisionDrawingLayers()
                }
            }
            self.session.startRunning()
        }
    }

    private func setupPermissions() {
        /*
         Check the video authorization status. Video access is required and audio
         access is optional. If the user denies audio access, AVCam won't
         record audio during movie recording.
         */

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break

        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.

             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(
                for: .video,
                completionHandler: { granted in
                    if !granted {
                        self.setupResult = .notAuthorized
                    }
                    self.sessionQueue.resume()
                }
            )

        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
    }

    private func setupAudioPlayer() {
        let fileURL = URL(fileReferenceLiteralResourceName: "buzzer.wav")
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.prepareToPlay()
        } catch let error as NSError {
            print(error.localizedDescription)
        }
    }

    // MARK: Session

    private func configureSession() {
        if setupResult != .success {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .low

        // Add video input.
        do {
            // select main wide angle webcam as input
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)

            let device = devices.devices.first!

//            try device.lockForConfiguration()
//            device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 1)
//            device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 1)
//            device.unlockForConfiguration()

            let videoDeviceInput = try AVCaptureDeviceInput(device: device)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            }

            // add output

            let videoDataOutput = AVCaptureVideoDataOutput()

            // Create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured.
            // A serial dispatch queue must be used to guarantee that video frames will be delivered in order.
            let videoDataOutputQueue = DispatchQueue(label: "uk.co.matthewspear.VisionFaceTrack")
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            videoDataOutput.alwaysDiscardsLateVideoFrames = true

            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }

            videoDataOutput.connection(with: .video)?.isEnabled = true

            self.videoDataOutput = videoDataOutput
            self.videoDataOutputQueue = videoDataOutputQueue

            captureDevice = device

            let dimensions = device.activeFormat.formatDescription.dimensions

            print(device.activeFormat.videoSupportedFrameRateRanges)

            captureDeviceResolution = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))

            print(captureDeviceResolution)

            // Handle displaying preview

            if displayPreview {
                previewLayer = AVCaptureVideoPreviewLayer(session: session)

                previewLayer?.name = "CameraPreview"
                previewLayer?.backgroundColor = NSColor.black.cgColor
                previewLayer?.videoGravity = .resizeAspectFill

                if previewLayer?.connection?.isVideoMirroringSupported ?? false {
                    previewLayer?.connection?.automaticallyAdjustsVideoMirroring = false
                    previewLayer?.connection?.isVideoMirrored = true
                }

                DispatchQueue.main.async {
                    self.rootLayer = self.previewView.layer
                    self.previewView.layer?.addSublayer(self.previewLayer!)
                    self.previewLayer?.frame = self.previewView.frame
                }
            }

        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
    }

    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: Drawing Vision Observations

    private func setupVisionDrawingLayers() {
        let captureDeviceResolution = self.captureDeviceResolution

        let captureDeviceBounds = CGRect(
            x: 0,
            y: 0,
            width: captureDeviceResolution.width,
            height: captureDeviceResolution.height
        )

        let captureDeviceBoundsCenterPoint = CGPoint(
            x: captureDeviceBounds.midX,
            y: captureDeviceBounds.midY
        )

        let normalizedCenterPoint = CGPoint(x: 0.5, y: 0.5)

        guard let rootLayer = self.rootLayer else {
            print("View was not properly initialised")
//                presentErrorAlert(message: "view was not property initialized")
            return
        }

        let overlayLayer = CALayer()
        overlayLayer.name = "DetectionOverlay"
        overlayLayer.masksToBounds = true
        overlayLayer.anchorPoint = normalizedCenterPoint
        overlayLayer.bounds = captureDeviceBounds
        overlayLayer.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)

        let faceRectangleShapeLayer = CAShapeLayer()
        faceRectangleShapeLayer.name = "RectangleOutlineLayer"
        faceRectangleShapeLayer.bounds = captureDeviceBounds
        faceRectangleShapeLayer.anchorPoint = normalizedCenterPoint
        faceRectangleShapeLayer.position = captureDeviceBoundsCenterPoint
        faceRectangleShapeLayer.fillColor = nil
        faceRectangleShapeLayer.strokeColor = NSColor.green.withAlphaComponent(0.7).cgColor
        faceRectangleShapeLayer.lineWidth = 5
        faceRectangleShapeLayer.shadowOpacity = 0.7
        faceRectangleShapeLayer.shadowRadius = 5

        let faceLandmarksShapeLayer = CAShapeLayer()
        faceLandmarksShapeLayer.name = "FaceLandmarksLayer"
        faceLandmarksShapeLayer.bounds = captureDeviceBounds
        faceLandmarksShapeLayer.anchorPoint = normalizedCenterPoint
        faceLandmarksShapeLayer.position = captureDeviceBoundsCenterPoint
        faceLandmarksShapeLayer.fillColor = nil
        faceLandmarksShapeLayer.strokeColor = NSColor.yellow.withAlphaComponent(0.7).cgColor
        faceLandmarksShapeLayer.lineWidth = 3
        faceLandmarksShapeLayer.shadowOpacity = 0.7
        faceLandmarksShapeLayer.shadowRadius = 5

        overlayLayer.addSublayer(faceRectangleShapeLayer)
        faceRectangleShapeLayer.addSublayer(faceLandmarksShapeLayer)
        rootLayer.addSublayer(overlayLayer)

        detectionOverlayLayer = overlayLayer
        detectedFaceRectangleShapeLayer = faceRectangleShapeLayer
        detectedFaceLandmarksShapeLayer = faceLandmarksShapeLayer

        updateLayerGeometry()
    }

    private func updateLayerGeometry() {
        guard let overlayLayer = detectionOverlayLayer,
            let rootLayer = self.rootLayer,
            let previewLayer = self.previewLayer
        else {
            return
        }

        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)

        let videoPreviewRect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))

        let rotation: CGFloat = 0.0
        let scaleX = videoPreviewRect.width / captureDeviceResolution.width
        let scaleY = videoPreviewRect.height / captureDeviceResolution.height

        // Scale and mirror the image to ensure upright presentation.
        let affineTransform = CGAffineTransform(rotationAngle: radiansForDegrees(rotation))
            .scaledBy(x: scaleX, y: -scaleY)
        overlayLayer.setAffineTransform(affineTransform)

        // Cover entire screen UI.
        let rootLayerBounds = rootLayer.bounds
        overlayLayer.position = CGPoint(x: rootLayerBounds.midX, y: rootLayerBounds.midY)
    }

    private func addPoints(in landmarkRegion: VNFaceLandmarkRegion2D, to path: CGMutablePath, applying affineTransform: CGAffineTransform, closingWhenComplete closePath: Bool) {
        let pointCount = landmarkRegion.pointCount
        if pointCount > 1 {
            let points: [CGPoint] = landmarkRegion.normalizedPoints
            path.move(to: points[0], transform: affineTransform)
            path.addLines(between: points, transform: affineTransform)
            if closePath {
                path.addLine(to: points[0], transform: affineTransform)
                path.closeSubpath()
            }
        }
    }

    private func radiansForDegrees(_ degrees: CGFloat) -> CGFloat {
        return CGFloat(Double(degrees) * Double.pi / 180.0)
    }

    private func addIndicators(to faceRectanglePath: CGMutablePath, faceLandmarksPath: CGMutablePath, for faceObservation: VNFaceObservation) {
        let displaySize = captureDeviceResolution

        let faceBounds = VNImageRectForNormalizedRect(faceObservation.boundingBox, Int(displaySize.width), Int(displaySize.height))
        faceRectanglePath.addRect(faceBounds)

        if let landmarks = faceObservation.landmarks {
            // Landmarks are relative to -- and normalized within --- face bounds
            let affineTransform = CGAffineTransform(translationX: faceBounds.origin.x, y: faceBounds.origin.y)
                .scaledBy(x: faceBounds.size.width, y: faceBounds.size.height)

            // Treat eyebrows and lines as open-ended regions when drawing paths.
            let openLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
                landmarks.leftEyebrow,
                landmarks.rightEyebrow,
                landmarks.faceContour,
                landmarks.noseCrest,
                landmarks.medianLine,
            ]
            for openLandmarkRegion in openLandmarkRegions where openLandmarkRegion != nil {
                self.addPoints(in: openLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: false)
            }

            // Draw eyes, lips, and nose as closed regions.
            let closedLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
                landmarks.leftEye,
                landmarks.rightEye,
                landmarks.outerLips,
                landmarks.innerLips,
                landmarks.nose,
            ]
            for closedLandmarkRegion in closedLandmarkRegions where closedLandmarkRegion != nil {
                self.addPoints(in: closedLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: true)
            }
        }
    }

    /// - Tag: DrawPaths
    private func drawFaceObservations(_ faceObservations: [VNFaceObservation]) {
        guard let faceRectangleShapeLayer = detectedFaceRectangleShapeLayer,
            let faceLandmarksShapeLayer = detectedFaceLandmarksShapeLayer
        else {
            return
        }

        CATransaction.begin()

        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)

        let faceRectanglePath = CGMutablePath()
        let faceLandmarksPath = CGMutablePath()

        for faceObservation in faceObservations {
            addIndicators(
                to: faceRectanglePath,
                faceLandmarksPath: faceLandmarksPath,
                for: faceObservation
            )
        }

        faceRectangleShapeLayer.path = faceRectanglePath
        faceLandmarksShapeLayer.path = faceLandmarksPath

        updateLayerGeometry()

        CATransaction.commit()
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    /// - Tag: PerformRequests
    // Handle delegate method callback on receiving a sample buffer.
    public func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
//        print(1.0 / (Date.timeIntervalSinceReferenceDate - lastFrame))
        if (Date.timeIntervalSinceReferenceDate - lastFrame) < (1 / frameRate) { return }

        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]

        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to obtain a CVPixelBuffer for the current output frame.")
            return
        }

        // feature printing
        print(abs(lastMovement - Date.timeIntervalSinceReferenceDate))

        if Date.timeIntervalSinceReferenceDate > lastMovement {
            let startFeature = Date.timeIntervalSinceReferenceDate

            let imageRequestHandler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .down,
                options: requestHandlerOptions
            )

            var distance = Float(0)

            let request = VNGenerateImageFeaturePrintRequest()
            do {
                try imageRequestHandler.perform([request])
                let result = request.results?.first as? VNFeaturePrintObservation

                if let lastFeaturePrint = lastFeaturePrint {
                    try result?.computeDistance(&distance, to: lastFeaturePrint)
                }
                lastFeaturePrint = result
            } catch let error as NSError {
                NSLog("Failed to perform FaceLandmarkRequest: %@", error)
            }

//            print("Distance = \(distance)")

            if distance < imageDistanceThreshold {
                // Ensure this is in the correct position for frame rate to work
                lastFrame = Date.timeIntervalSinceReferenceDate
                frameRate = slowFrameRate
                DispatchQueue.main.async {
                    self.movementIndicator.backgroundColor = #colorLiteral(red: 0.8549019694, green: 0.250980407, blue: 0.4784313738, alpha: 1)
                }
                return
            }

            print("Movement!")
//            audioPlayer?.prepareToPlay()
            lastMovement = Date.timeIntervalSinceReferenceDate + movementCoolOff
            frameRate = fastFrameRate
            lastFeaturePrint = nil

            DispatchQueue.main.async {
                self.movementIndicator.backgroundColor = #colorLiteral(red: 0.5843137503, green: 0.8235294223, blue: 0.4196078479, alpha: 1)
            }
        }

        // CoreML Vision

        let startCoreML = Date.timeIntervalSinceReferenceDate

        let visionRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .upMirrored,
            options: requestHandlerOptions
        )

        var predictionRequest: VNCoreMLRequest?

        do {
            let model = try VNCoreMLModel(for: HandModel().model)
            predictionRequest = VNCoreMLRequest(model: model)
            predictionRequest!.imageCropAndScaleOption = .centerCrop

            try visionRequestHandler.perform([predictionRequest!])

            guard let observation = predictionRequest!.results?.first as? VNPixelBufferObservation else {
                fatalError("Unexpected result type from VNCoreMLRequest")
            }

            func pixelFrom(x: Int, y: Int, movieFrame: CVPixelBuffer) -> Int {
                let baseAddress = CVPixelBufferGetBaseAddress(movieFrame)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(movieFrame)
                let buffer = baseAddress!.assumingMemoryBound(to: UInt8.self)
                let index = x * 4 + y * bytesPerRow
                return Int(buffer[index])
            }

            CVPixelBufferLockBaseAddress(observation.pixelBuffer, [])
            var sum: Int = 0
            let threshold = Int(112 * 112 * 10)
            var faceTouched = false

            // work bottom up
            for row in 0 ..< 112 {
                for col in 0 ..< 112 {
                    sum += pixelFrom(x: 112 - row, y: col, movieFrame: observation.pixelBuffer)

                    if sum >= threshold {
                        faceTouched = true
                        break
                    }
                }
            }

            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            if faceTouched {
                print("Face!")
                AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert)
//                audioPlayer?.play()
                lastMovement = Date.timeIntervalSinceReferenceDate + touchCoolOff
            } else {
                audioPlayer?.stop()
            }

            if displayPreview {
                let ciImage = CIImage(cvImageBuffer: observation.pixelBuffer)
                let context = CIContext(options: nil)
                if let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(observation.pixelBuffer), height: CVPixelBufferGetHeight(observation.pixelBuffer))) {
                    DispatchQueue.main.async {
                        self.maskImageView.image = NSImage(cgImage: cgImage, size: NSSize(width: 112.0, height: 112.0))
                    }
//                    print(1.0 / (Date.timeIntervalSinceReferenceDate - startCoreML))
                }
            }

        } catch let error as NSError {
            NSLog("Failed to perform FaceLandmarkRequest: %@", error)
        }

        // Ensure this is in the correct position for frame rate to work
        lastFrame = Date.timeIntervalSinceReferenceDate
    }
}
