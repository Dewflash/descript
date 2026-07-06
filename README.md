# Descript Native

This is the first native macOS wiring pass for the approved compact popup UI.

It builds a real clickable `Descript.app` menu bar application using SwiftUI `MenuBarExtra`.

Implemented:

- Scroll emoji menu bar item
- Compact popup UI matching the preview direction
- Separate YouTube and MP4 source modes
- Separate persisted accent color settings for YouTube and MP4
- Settings button color follows the active source accent
- Clipboard paste/copy
- Save transcript dialog
- YouTube transcript fetch via caption tracks
- Native MP4 picker
- MP4 audio export to temporary M4A
- Asynchronous on-device `SFSpeechURLRecognitionRequest`

Build:

```bash
./build.sh
```

Outputs:

- `build/Descript.app`
- `release/Descript-0.1.0.zip`
- `release/Descript-0.1.0.dmg`
