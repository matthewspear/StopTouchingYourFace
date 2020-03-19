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

    // Vision requests
    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var trackingRequests: [VNTrackObjectRequest]?

    lazy var sequenceRequestHandler = VNSequenceRequestHandler()

    override func viewDidLoad() {
        super.viewDidLoad()

        setupPermissions()

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
//            self.prepareVisionRequest()
            DispatchQueue.main.async {
                self.setupVisionDrawingLayers()
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

            let videoDeviceInput = try AVCaptureDeviceInput(device: device)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            }

            // add output

            let videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.alwaysDiscardsLateVideoFrames = true

            // Create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured.
            // A serial dispatch queue must be used to guarantee that video frames will be delivered in order.
            let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VisionFaceTrack")
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)

            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }

            videoDataOutput.connection(with: .video)?.isEnabled = true

            self.videoDataOutput = videoDataOutput
            self.videoDataOutputQueue = videoDataOutputQueue

            captureDevice = device

            let dimensions = device.activeFormat.formatDescription.dimensions

            captureDeviceResolution = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))

            print(captureDeviceResolution)

            // Handle displaying preview

            previewLayer = AVCaptureVideoPreviewLayer(session: session)

            previewLayer?.name = "CameraPreview"
            previewLayer?.backgroundColor = NSColor.black.cgColor
            previewLayer?.videoGravity = .resizeAspectFill

            if previewLayer?.connection?.isVideoMirroringSupported ?? false {
                previewLayer?.connection?.automaticallyAdjustsVideoMirroring = false
                previewLayer?.connection?.isVideoMirrored = true
            }

            DispatchQueue.main.async {
//                if let previewRootLayer = self.previewView?.layer {
//                    self.rootLayer = previewRootLayer
//
//                    previewRootLayer.masksToBounds = true
//                    self.previewLayer?.frame = previewRootLayer.bounds
//                    previewRootLayer.addSublayer(self.previewLayer!)
//                }

                self.rootLayer = self.previewView.layer
                self.previewView.layer?.addSublayer(self.previewLayer!)
                self.previewLayer?.frame = self.previewView.frame
                self.session.startRunning()
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
//    func captureOutput(_: AVCaptureOutput, didOutput _: CMSampleBuffer, from _: AVCaptureConnection) {
//        print("Frame")
//    }
//
//    func captureOutput(_: AVCaptureOutput, didDrop _: CMSampleBuffer, from _: AVCaptureConnection) {
//        print("Dropped a frame...")
//    }

    // MARK: Performing Vision Requests

    /// - Tag: WriteCompletionHandler
    private func prepareVisionRequest() {
//        trackingRequests = []
        var requests = [VNTrackObjectRequest]()

        let faceDetectionRequest = VNDetectFaceRectanglesRequest(
            completionHandler: { request, error in

                if error != nil {
                    print("FaceDetection error: \(String(describing: error)).")
                }

                guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
                    let results = faceDetectionRequest.results as? [VNFaceObservation] else {
                    return
                }
                DispatchQueue.main.async {
                    // Add the observations to the tracking list
                    for observation in results {
                        let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                        requests.append(faceTrackingRequest)
                    }
                    self.trackingRequests = requests
                }
            }
        )

        // Start with detection.  Find face, then track it.
        detectionRequests = [faceDetectionRequest]

        sequenceRequestHandler = VNSequenceRequestHandler()

        DispatchQueue.main.async {
            self.setupVisionDrawingLayers()
        }
    }

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

        var rotation: CGFloat
        var scaleX: CGFloat
        var scaleY: CGFloat

        // Rotate the layer into screen orientation.
        //        switch UIDevice.current.orientation {
        //        case .portraitUpsideDown:
        //            rotation = 180
        //            scaleX = videoPreviewRect.width / captureDeviceResolution.width
        //            scaleY = videoPreviewRect.height / captureDeviceResolution.height
        //
        //        case .landscapeLeft:
        //            rotation = 90
        //            scaleX = videoPreviewRect.height / captureDeviceResolution.width
        //            scaleY = scaleX
        //
        //        case .landscapeRight:
        //            rotation = -90
        //            scaleX = videoPreviewRect.height / captureDeviceResolution.width
        //            scaleY = scaleX
        //
        //        default:
        rotation = 0
        scaleX = videoPreviewRect.width / captureDeviceResolution.width
        scaleY = videoPreviewRect.height / captureDeviceResolution.height
        //        }

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
        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]

        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to obtain a CVPixelBuffer for the current output frame.")
            return
        }

        let exifOrientation = CGImagePropertyOrientation.down

        // Perform face landmark tracking on detected faces.
        var faceRectangleRequests = [VNDetectFaceRectanglesRequest]()

        let faceRectangleRequest = VNDetectFaceRectanglesRequest { request, error in
            if error != nil {
                print("FaceLandmarks error: \(String(describing: error)).")
            }

            guard let rectangleRequest = request as? VNDetectFaceRectanglesRequest,
                let results = rectangleRequest.results as? [VNFaceObservation] else {
                return
            }

            print(results)

            DispatchQueue.main.async {
                self.drawFaceObservations(results)
            }
        }

        faceRectangleRequests.append(faceRectangleRequest)

        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: exifOrientation,
            options: requestHandlerOptions
        )

        do {
            try imageRequestHandler.perform(faceRectangleRequests)
        } catch let error as NSError {
            NSLog("Failed to perform FaceLandmarkRequest: %@", error)
        }
    }
}
