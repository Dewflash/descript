# -*- mode: python ; coding: utf-8 -*-

from PyInstaller.utils.hooks import collect_submodules


APP_NAME = "Transcript Extractor"
BUNDLE_IDENTIFIER = "com.example.transcript-extractor"

hiddenimports = []
for package in [
    "rumps",
    "pyperclip",
    "pydub",
    "youtube_transcript_api",
    "objc",
    "Foundation",
    "Cocoa",
    "AppKit",
    "Speech",
]:
    hiddenimports += collect_submodules(package)


a = Analysis(
    ["app.py"],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "Tkinter", "_tkinter"],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name=APP_NAME,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name=APP_NAME,
)

app = BUNDLE(
    coll,
    name=f"{APP_NAME}.app",
    icon=None,
    bundle_identifier=BUNDLE_IDENTIFIER,
    info_plist={
        "CFBundleDisplayName": APP_NAME,
        "CFBundleName": APP_NAME,
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1.0.0",
        "LSUIElement": True,
        "NSHumanReadableCopyright": "Copyright © 2026",
        "NSSpeechRecognitionUsageDescription": "This app transcribes selected MP4 files using Apple's on-device speech recognition.",
        "NSMicrophoneUsageDescription": "This app does not record microphone audio, but macOS may require microphone permission for speech recognition services.",
    },
)
