#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/openssl_common.sh"

TRIPLE="${TRIPLE:?TRIPLE required (macos-universal or ios-xcframework)}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/native/out/${OPENSSL_VERSION}/${TRIPLE}}"
PREBUILT_DIR="${PREBUILT_DIR:-${PREBUILT_VERSION_ROOT}/${TRIPLE}}"

build_openssl() {
  local config="$1"
  local build_dir="$2"
  ensure_openssl_src
  rm -rf "${build_dir}"
  cp -R "${OPENSSL_SRC}" "${build_dir}"
  cd "${build_dir}"
  ./Configure "${config}" "${CONFIGURE_ARGS[@]}"
  make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
}

mkdir -p "${OUT_DIR}" "${PREBUILT_DIR}"

if [[ "${TRIPLE}" == "macos-universal" ]]; then
  ARM_DIR="${REPO_ROOT}/native/out/_build-macos-arm64"
  X64_DIR="${REPO_ROOT}/native/out/_build-macos-x64"
  build_openssl darwin64-arm64 "${ARM_DIR}"
  build_openssl darwin64-x86_64 "${X64_DIR}"
  lipo -create \
    "${ARM_DIR}/libcrypto.dylib" \
    "${X64_DIR}/libcrypto.dylib" \
    -output "${PREBUILT_DIR}/libcrypto.dylib"
  cp -v "${PREBUILT_DIR}/libcrypto.dylib" "${OUT_DIR}/"
  ls -la "${PREBUILT_DIR}"
  exit 0
fi

if [[ "${TRIPLE}" == "ios-xcframework" ]]; then
  IOS_DEVICE="${REPO_ROOT}/native/out/_build-ios-device"
  IOS_SIM="${REPO_ROOT}/native/out/_build-ios-sim"
  build_openssl ios64-xcrun "${IOS_DEVICE}"
  build_openssl iossimulator-arm64-xcrun "${IOS_SIM}"

  XCFW="${PREBUILT_DIR}/OpenSSL.xcframework"
  rm -rf "${XCFW}"
  xcodebuild -create-xcframework \
    -library "${IOS_DEVICE}/libcrypto.a" -headers "${IOS_DEVICE}/include" \
    -library "${IOS_SIM}/libcrypto.a" -headers "${IOS_SIM}/include" \
    -output "${XCFW}"
  cp -R "${XCFW}" "${OUT_DIR}/"
  ls -la "${PREBUILT_DIR}"
  exit 0
fi

echo "Unknown TRIPLE ${TRIPLE}"
exit 1
