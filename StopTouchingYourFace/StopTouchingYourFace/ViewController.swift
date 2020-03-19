//
//  ViewController.swift
//  StopTouchingYourFace
//
//  Created by Matthew Spear on 18/03/2020.
//  Copyright © 2020 Matthew Spear. All rights reserved.
//

import AVFoundation
import Cocoa

private enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
}

class ViewController: NSViewController {
    @IBOutlet var previewView: NSView!
    var previewLayer: AVCaptureVideoPreviewLayer?

    // Session variables
    private let session = AVCaptureSession()

    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var setupResult: SessionSetupResult = .success

    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!

    var device: AVCaptureDevice?

    fileprivate func setupPermissions() {
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

            let videoDeviceInput = try AVCaptureDeviceInput(device: devices.devices.first!)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            }

            // Handle displaying preview

            previewLayer = AVCaptureVideoPreviewLayer(session: session)

            if previewLayer?.connection?.isVideoMirroringSupported ?? false {
                previewLayer?.connection?.automaticallyAdjustsVideoMirroring = false
                previewLayer?.connection?.isVideoMirrored = true
            }

            DispatchQueue.main.async {
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
