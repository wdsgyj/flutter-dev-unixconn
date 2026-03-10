#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO_DIR="$ROOT/go"
INCLUDE_DIR="$GO_DIR/include"
APPLE_TMP="$ROOT/.cache/apple"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-}"
GOCACHE="${GOCACHE:-/tmp/gocache}"
# Shrink Android c-shared outputs without dropping the exported C ABI symbols.
GO_ANDROID_LDFLAGS='-s -w -buildid='

if [[ -z "$ANDROID_NDK_HOME" && -d "$HOME/Library/Android/sdk/ndk/29.0.14206865" ]]; then
  ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/29.0.14206865"
fi

mkdir -p "$APPLE_TMP"
mkdir -p "$GOCACHE"

build_macos_archive() {
  local arch="$1"
  local sdk_path
  local cc
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
  cc="$(xcrun --sdk macosx --find clang)"
  CGO_ENABLED=1 \
  GOCACHE="$GOCACHE" \
  GOOS=darwin \
  GOARCH="$arch" \
  CC="$cc" \
  CGO_CFLAGS="-isysroot $sdk_path -mmacosx-version-min=10.14" \
  CGO_LDFLAGS="-isysroot $sdk_path -mmacosx-version-min=10.14" \
  go build -C "$GO_DIR" -buildmode=c-archive -trimpath -o "$APPLE_TMP/libunixconn_proxy_macos_${arch}.a" .
}

build_ios_archive() {
  local sdk="$1"
  local arch="$2"
  local target="$3"
  local output_dir="$4"
  local sdk_path
  local cc
  mkdir -p "$output_dir"
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" --find clang)"
  CGO_ENABLED=1 \
  GOCACHE="$GOCACHE" \
  GOOS=ios \
  GOARCH="$arch" \
  CC="$cc" \
  CGO_CFLAGS="-isysroot $sdk_path -target $target" \
  CGO_LDFLAGS="-isysroot $sdk_path -target $target" \
  go build -C "$GO_DIR" -buildmode=c-archive -trimpath -o "$output_dir/libunixconn_proxy.a" .
}

build_android_shared() {
  local abi="$1"
  local goarch="$2"
  local compiler="$3"
  local output="$ROOT/android/src/main/jniLibs/$abi/libunixconn_proxy.so"
  local toolchain="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"
  mkdir -p "$ROOT/android/src/main/jniLibs/$abi"
  if [[ "$goarch" == "arm" ]]; then
    CGO_ENABLED=1 \
    GOCACHE="$GOCACHE" \
    GOOS=android \
    GOARCH="$goarch" \
    GOARM=7 \
    CC="$toolchain/$compiler" \
    go build -C "$GO_DIR" -buildmode=c-shared -trimpath \
      -ldflags "$GO_ANDROID_LDFLAGS" \
      -o "$output" .
    "$toolchain/llvm-strip" --strip-debug "$output"
    return
  fi
  CGO_ENABLED=1 \
  GOCACHE="$GOCACHE" \
  GOOS=android \
  GOARCH="$goarch" \
  CC="$toolchain/$compiler" \
  go build -C "$GO_DIR" -buildmode=c-shared -trimpath \
    -ldflags "$GO_ANDROID_LDFLAGS" \
    -o "$output" .
  "$toolchain/llvm-strip" --strip-debug "$output"
}

build_macos_archive arm64
build_macos_archive amd64
mkdir -p "$ROOT/macos/Libraries"
rm -f "$ROOT/macos/Libraries/libunixconn_proxy.a"
lipo -create \
  "$APPLE_TMP/libunixconn_proxy_macos_arm64.a" \
  "$APPLE_TMP/libunixconn_proxy_macos_amd64.a" \
  -output "$ROOT/macos/Libraries/libunixconn_proxy.a"

IOS_DEVICE_DIR="$APPLE_TMP/ios-device"
IOS_SIMULATOR_ARM64_DIR="$APPLE_TMP/ios-simulator-arm64"
IOS_SIMULATOR_AMD64_DIR="$APPLE_TMP/ios-simulator-amd64"
IOS_SIMULATOR_UNIVERSAL_DIR="$APPLE_TMP/ios-simulator-universal"
IOS_SIMULATOR_UNIVERSAL_LIB="$IOS_SIMULATOR_UNIVERSAL_DIR/libunixconn_proxy.a"
rm -rf \
  "$IOS_DEVICE_DIR" \
  "$IOS_SIMULATOR_ARM64_DIR" \
  "$IOS_SIMULATOR_AMD64_DIR" \
  "$IOS_SIMULATOR_UNIVERSAL_DIR"
build_ios_archive iphoneos arm64 arm64-apple-ios12.0 "$IOS_DEVICE_DIR"
build_ios_archive iphonesimulator arm64 arm64-apple-ios12.0-simulator "$IOS_SIMULATOR_ARM64_DIR"
build_ios_archive iphonesimulator amd64 x86_64-apple-ios12.0-simulator "$IOS_SIMULATOR_AMD64_DIR"
mkdir -p "$IOS_SIMULATOR_UNIVERSAL_DIR"
lipo -create \
  "$IOS_SIMULATOR_ARM64_DIR/libunixconn_proxy.a" \
  "$IOS_SIMULATOR_AMD64_DIR/libunixconn_proxy.a" \
  -output "$IOS_SIMULATOR_UNIVERSAL_LIB"
mkdir -p "$ROOT/ios/Frameworks"
rm -rf "$ROOT/ios/Frameworks/unixconn_proxy.xcframework"
xcodebuild -create-xcframework \
  -library "$IOS_DEVICE_DIR/libunixconn_proxy.a" -headers "$INCLUDE_DIR" \
  -library "$IOS_SIMULATOR_UNIVERSAL_LIB" -headers "$INCLUDE_DIR" \
  -output "$ROOT/ios/Frameworks/unixconn_proxy.xcframework"

if [[ -z "$ANDROID_NDK_HOME" ]]; then
  echo "ANDROID_NDK_HOME is not set and no default NDK was found." >&2
  exit 1
fi

build_android_shared armeabi-v7a arm armv7a-linux-androideabi21-clang
build_android_shared arm64-v8a arm64 aarch64-linux-android21-clang
build_android_shared x86_64 amd64 x86_64-linux-android21-clang
