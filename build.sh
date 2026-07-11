#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
export COPYFILE_DISABLE=1

APP_NAME="Descript"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
BUILD_DIR="build"
RELEASE_DIR="release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
ZIP_PATH="${RELEASE_DIR}/${APP_NAME}-${VERSION}.zip"
DMG_PATH="${RELEASE_DIR}/${APP_NAME}-${VERSION}.dmg"

rm -rf "${BUILD_DIR}"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources" "${RELEASE_DIR}"

swiftc \
  -O \
  -parse-as-library \
  -o "${EXECUTABLE_PATH}" \
  Sources/DescriptApp.swift \
  Sources/DescriptModel.swift \
  Sources/TranscriptServices.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework Speech \
  -framework UniformTypeIdentifiers

cp Info.plist "${APP_PATH}/Contents/Info.plist"
cp Resources/DescriptIcon.icns "${APP_PATH}/Contents/Resources/DescriptIcon.icns"
chmod +x "${EXECUTABLE_PATH}"

codesign --force --sign - --identifier com.dewflash.descript "${APP_PATH}"
codesign --verify --strict "${APP_PATH}"

rm -f "${ZIP_PATH}" "${DMG_PATH}"
ditto -c -k --norsrc --noextattr --keepParent "${APP_PATH}" "${ZIP_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_PATH}" -ov -format UDZO "${DMG_PATH}"

echo "Built:"
echo "  ${APP_PATH}"
echo "  ${ZIP_PATH}"
echo "  ${DMG_PATH}"
