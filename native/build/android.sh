#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/openssl_common.sh"

TRIPLE="${TRIPLE:?TRIPLE required (android-arm64-v8a or android-x86_64)}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/native/out/${OPENSSL_VERSION}/${TRIPLE}}"
PREBUILT_DIR="${PREBUILT_DIR:-${PREBUILT_VERSION_ROOT}/${TRIPLE}}"

case "${TRIPLE}" in
  android-arm64-v8a) CONFIG=android-arm64 ;;
  android-x86_64) CONFIG=android-x86_64 ;;
  *) echo "Unknown TRIPLE ${TRIPLE}"; exit 1 ;;
esac

: "${ANDROID_NDK_ROOT:?ANDROID_NDK_ROOT required}"
export ANDROID_NDK_HOME="${ANDROID_NDK_ROOT}"
HOST_TAG="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
TOOLCHAIN_BIN="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}/bin"
export PATH="${TOOLCHAIN_BIN}:${PATH}"

ensure_openssl_src
cd "${OPENSSL_SRC}"
./Configure "${CONFIG}" "${CONFIGURE_ARGS[@]}"
make -j"$(nproc 2>/dev/null || echo 4)"

mkdir -p "${OUT_DIR}" "${PREBUILT_DIR}"
copy_artifact "${OUT_DIR}" 'libcrypto.so*'
copy_artifact "${PREBUILT_DIR}" 'libcrypto.so*'
ls -la "${PREBUILT_DIR}"
