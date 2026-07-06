#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Transcript Extractor"
DIST_DIR="dist"
APP_PATH="${DIST_DIR}/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.zip"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
VENV_PYTHON="${VENV_DIR}/bin/python"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Warning: ffmpeg was not found on PATH. Install it with: brew install ffmpeg"
fi

"${PYTHON_BIN}" -m venv "${VENV_DIR}"
"${VENV_PYTHON}" -m pip install --upgrade pip
"${VENV_PYTHON}" -m pip install -r requirements.txt
"${VENV_PYTHON}" -m PyInstaller --clean --noconfirm build.spec

rm -f "${ZIP_PATH}" "${DMG_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_PATH}" -ov -format UDZO "${DMG_PATH}"

echo "Built:"
echo "  ${APP_PATH}"
echo "  ${ZIP_PATH}"
echo "  ${DMG_PATH}"
