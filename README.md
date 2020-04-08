# StopTouchingYourFace

> macOS app to help you stop touching your face when remote working or watching Netflix!

StopTouchingYourFace is a native macOS application using the webcam to detect the user touching their face and play an alert. The app uses Vision for motion detection and a custom CoreML model to detect face touching.

## Files

`HandModel` contains all the code required to build the dataset, run the model and convert to CoreML.

`StopTouchingYourFace` contains the Xcode Project for building and running the macOS application.

## Installation / Setup

Open project found in the `StopTouchingYourFace` folder. 

The project was built using Xcode 11.3. No additional dependencies required to run.

## Releases

Keep an eye on the releases page for the first alpha release!

Distributed under the MIT license. See ``LICENSE`` for more information.