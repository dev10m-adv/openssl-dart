#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/openssl_common.sh"

TRIPLE="${TRIPLE:?TRIPLE required (linux-x64 or linux-arm64)}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/native/out/${OPENSSL_VERSION}/${TRIPLE}}"
PREBUILT_DIR="${PREBUILT_DIR:-${PREBUILT_VERSION_ROOT}/${TRIPLE}}"

CROSS_PREFIX=""
case "${TRIPLE}" in
  linux-x64) CONFIG=linux-x86_64 ;;
  linux-arm64)
    CONFIG=linux-aarch64
    if [[ "$(uname -m)" != "aarch64" ]]; then
      CROSS_PREFIX="aarch64-linux-gnu-"
      if ! command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1; then
        echo "Install cross compiler: sudo apt-get install -y gcc-aarch64-linux-gnu"
        exit 1
      fi
    fi
    ;;
  *) echo "Unknown TRIPLE ${TRIPLE}"; exit 1 ;;
esac

ensure_openssl_src
cd "${OPENSSL_SRC}"
if [[ -n "${CROSS_PREFIX}" ]]; then
  export CC="${CROSS_PREFIX}gcc"
  export CXX="${CROSS_PREFIX}g++"
  export AR="${CROSS_PREFIX}ar"
  export RANLIB="${CROSS_PREFIX}ranlib"
  ./Configure "${CONFIG}" --cross-compile-prefix="${CROSS_PREFIX}" "${CONFIGURE_ARGS[@]}"
else
  ./Configure "${CONFIG}" "${CONFIGURE_ARGS[@]}"
fi
make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "${OUT_DIR}" "${PREBUILT_DIR}"
copy_artifact "${OUT_DIR}" 'libcrypto.so*'
copy_artifact "${PREBUILT_DIR}" 'libcrypto.so*'
ls -la "${PREBUILT_DIR}"
