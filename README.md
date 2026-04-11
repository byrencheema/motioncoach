# MotionCoach

Native iOS MVP for camera-based basketball shooting drills.

## What is built

- Start screen with Free Shoot, Make N, and Timed drill choices.
- Live drill screen with rear-camera preview, makes, attempts, FG%, progress text, make sound, and End Drill.
- Session summary screen with final stats and a shareable summary image.
- History screen with locally saved sessions and an FG% trend chart.
- On-device detector boundary wired for a bundled `best` Core ML model.
- Swift port of the SwishAI cooldown scoring rules:
  - player-shooting detection registers an attempt with a 1.5s cooldown
  - ball-in-basket detection registers a make with a 2.0s cooldown
  - make without a recent shot auto-adds an attempt

## Model setup

The referenced SwishAI repository does not currently include `basketball_training/weights/best.pt`, so this repo does not include a model artifact.

When you have the weights, convert them from the SwishAI `BE` folder:

```bash
pip install ultralytics
python -c "from ultralytics import YOLO; model = YOLO('basketball_training/weights/best.pt'); model.export(format='coreml', nms=True)"
```

Then add the generated `best.mlpackage` to the `MotionCoach` target in Xcode. The app looks for `best.mlmodelc` or `best.mlpackage` in the app bundle and keeps the UI usable with a "model missing" message until the model is present.

## Build

```bash
xcodebuild -project MotionCoach.xcodeproj -scheme MotionCoach -destination 'generic/platform=iOS Simulator' build
```

Run on a physical iPhone for real camera testing.
