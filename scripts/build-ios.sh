#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
GEN_DIR="$IOS_DIR/StreamTube/Generated"
HEADERS_STAGE="$ROOT_DIR/target/ios-headers"
XCFRAMEWORK_OUT="$IOS_DIR/Frameworks/StreamTubeCoreFFI.xcframework"

export IPHONEOS_DEPLOYMENT_TARGET="17.0"

echo "==> 1/5 Ensuring Rust iOS targets are installed..."
rustup target add aarch64-apple-ios aarch64-apple-ios-sim

echo "==> 2/5 Building streamtube-core for iPhone (aarch64-apple-ios) & Simulator (aarch64-apple-ios-sim)..."
cargo build --manifest-path "$ROOT_DIR/Cargo.toml" -p streamtube-core --release --target aarch64-apple-ios
cargo build --manifest-path "$ROOT_DIR/Cargo.toml" -p streamtube-core --release --target aarch64-apple-ios-sim

echo "==> 3/5 Generating Swift bindings via UniFFI..."
mkdir -p "$GEN_DIR"
(
  cd "$ROOT_DIR"
  cargo run -p streamtube-core --features cli --bin uniffi-bindgen -- \
    generate \
    --library "$ROOT_DIR/target/aarch64-apple-ios/release/libstreamtube_core.a" \
    --language swift \
    --out-dir "$GEN_DIR"
)

echo "==> 4/5 Packaging StreamTubeCoreFFI.xcframework..."
rm -rf "$HEADERS_STAGE" "$XCFRAMEWORK_OUT"
mkdir -p "$HEADERS_STAGE" "$IOS_DIR/Frameworks"
cp "$GEN_DIR/streamtube_coreFFI.h" "$HEADERS_STAGE/streamtube_coreFFI.h"
cp "$GEN_DIR/streamtube_coreFFI.modulemap" "$HEADERS_STAGE/module.modulemap"

xcodebuild -create-xcframework \
  -library "$ROOT_DIR/target/aarch64-apple-ios/release/libstreamtube_core.a" \
  -headers "$HEADERS_STAGE" \
  -library "$ROOT_DIR/target/aarch64-apple-ios-sim/release/libstreamtube_core.a" \
  -headers "$HEADERS_STAGE" \
  -output "$XCFRAMEWORK_OUT"

echo "==> 5/5 Generating Xcode project with XcodeGen (if installed)..."
if command -v xcodegen >/dev/null 2>&1; then
  (cd "$IOS_DIR" && xcodegen generate)
  echo "Done! Open $IOS_DIR/StreamTube.xcodeproj in Xcode to sign and install on your iPhone."
else
  echo "XCFramework ready at $XCFRAMEWORK_OUT. Install xcodegen ('brew install xcodegen') and run 'cd ios && xcodegen generate'."
fi
