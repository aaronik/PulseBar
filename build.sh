#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/PulseBar.app/Contents/MacOS build/PulseBar.app/Contents/Resources
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx13.0" -O -o build/PulseBar.app/Contents/MacOS/PulseBar Sources/PulseBar/*.swift
cp Info.plist build/PulseBar.app/Contents/Info.plist
cp Resources/PulseBar.icns build/PulseBar.app/Contents/Resources/PulseBar.icns
codesign --force --sign - build/PulseBar.app
printf 'Built %s/build/PulseBar.app\n' "$PWD"
