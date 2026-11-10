#!/bin/bash
# ClamshellDischarge.app 빌드
#   ./build.sh            → build/ClamshellDischarge.app + build/ClamshellDischarge-<버전>.zip
#   ./build.sh --install  → 위 + /Applications 에 설치
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(cat VERSION)
BUILD_NUMBER=${BUILD_NUMBER:-1}
APP=build/ClamshellDischarge.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macos13 Sources/*.swift -o "$APP/Contents/MacOS/ClamshellDischarge" \
	-framework Cocoa -framework ServiceManagement -framework SwiftUI -framework Charts

install -m 755 scripts/clamshell-discharge "$APP/Contents/Resources/clamshell-discharge"
install -m 755 scripts/clamshell-charge-limit "$APP/Contents/Resources/clamshell-charge-limit"
install -m 644 icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>ClamshellDischarge</string>
	<key>CFBundleDisplayName</key><string>Clamshell Discharge</string>
	<key>CFBundleIdentifier</key><string>io.github.waps2k.clamshell-discharge</string>
	<key>CFBundleExecutable</key><string>ClamshellDischarge</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"

ZIP="build/ClamshellDischarge-${VERSION}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "built: $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
	if pgrep -x ClamshellDischarge >/dev/null; then
		osascript -e 'quit app "ClamshellDischarge"' 2>/dev/null || pkill -x ClamshellDischarge || true
		sleep 1
	fi
	rm -rf /Applications/ClamshellDischarge.app
	ditto "$APP" /Applications/ClamshellDischarge.app
	# 로컬 설치본은 개발자 인증서로 서명: 다시 빌드해도 macOS 가 같은 앱으로 알아봐서
	# 입력 모니터링 같은 권한이 유지됨 (ad-hoc 서명은 빌드마다 바뀌어 권한이 풀림).
	# 배포 zip 은 개인 정보(인증서 이름)가 들어가지 않도록 ad-hoc 그대로.
	SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}
	if [[ -n "$SIGN_ID" ]]; then
		codesign --force --deep -s "$SIGN_ID" /Applications/ClamshellDischarge.app && echo "signed for local install: $SIGN_ID"
	fi
	echo "installed: /Applications/ClamshellDischarge.app"
fi
