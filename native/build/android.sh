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

ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
: "${ANDROID_NDK_ROOT:?ANDROID_NDK_ROOT or ANDROID_NDK_HOME required}"
export ANDROID_NDK_HOME="${ANDROID_NDK_ROOT}"

if [[ -n "${OPENSSL_NDK_HOST_TAG:-}" ]]; then
  HOST_TAG="${OPENSSL_NDK_HOST_TAG}"
else
  HOST_TAG="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
  case "${HOST_TAG}" in
    mingw*|msys*|cygwin*|windows*)
      HOST_TAG="windows-x86_64"
      ;;
  esac
fi
TOOLCHAIN_BIN="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}/bin"
if [[ -z "${OPENSSL_ANDROID_SKIP_PATH:-}" ]]; then
  export PATH="${TOOLCHAIN_BIN}:${PATH}"
fi

API_LEVEL="${ANDROID_API:-21}"
case "${TRIPLE}" in
  android-arm64-v8a) ARCH_PREFIX=aarch64 ;;
  android-x86_64) ARCH_PREFIX=x86_64 ;;
esac

if [[ -z "${CC:-}" || -z "${CXX:-}" ]]; then
  resolve_ndk_tool() {
    local name="${1}"
    local base="${TOOLCHAIN_BIN}/${name}"
    if [[ -x "${base}" ]]; then
      echo "${base}"
    elif [[ -f "${base}.cmd" ]]; then
      echo "${base}.cmd"
    elif [[ -f "${base}.exe" ]]; then
      echo "${base}.exe"
    else
      return 1
    fi
  }

  CC_BIN="$(resolve_ndk_tool "${ARCH_PREFIX}-linux-android${API_LEVEL}-clang")" || {
    echo "NDK clang not found for ${ARCH_PREFIX} API ${API_LEVEL} under ${TOOLCHAIN_BIN}"
    exit 1
  }
  CXX_BIN="$(resolve_ndk_tool "${ARCH_PREFIX}-linux-android${API_LEVEL}-clang++")" || {
    echo "NDK clang++ not found for ${ARCH_PREFIX} API ${API_LEVEL} under ${TOOLCHAIN_BIN}"
    exit 1
  }
  export CC="${CC_BIN}"
  export CXX="${CXX_BIN}"
  if [[ -z "${AR:-}" ]]; then
    export AR="$(resolve_ndk_tool llvm-ar)"
  fi
  if [[ -z "${RANLIB:-}" ]]; then
    export RANLIB="$(resolve_ndk_tool llvm-ranlib)"
  fi
fi

# OpenSSL Configure still probes for *-linux-android-gcc; NDK r23+ ships clang only.
if [[ "${HOST_TAG}" != windows-* ]]; then
  WRAPPER_DIR="${REPO_ROOT}/native/out/_ndk-wrap/${TRIPLE}"
  mkdir -p "${WRAPPER_DIR}"
  write_ndk_shim() {
    local name="${1}"
    local target="${2}"
    local file="${WRAPPER_DIR}/${name}"
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "${target}" > "${file}"
    chmod +x "${file}"
  }
  write_ndk_shim "${ARCH_PREFIX}-linux-android-gcc" "${CC}"
  write_ndk_shim "${ARCH_PREFIX}-linux-android-g++" "${CXX}"
  export PATH="${WRAPPER_DIR}:${PATH}"
fi

if [[ -n "${PERL:-}" ]]; then
  export PATH="$(dirname "${PERL}"):${PATH}"
fi

ensure_openssl_src
cd "${OPENSSL_SRC}"
if [[ -n "${PERL:-}" ]]; then
  "${PERL}" ./Configure "${CONFIG}" "${CONFIGURE_ARGS[@]}"
else
  ./Configure "${CONFIG}" "${CONFIGURE_ARGS[@]}"
fi
make -j"$(nproc 2>/dev/null || echo 4)"

mkdir -p "${OUT_DIR}" "${PREBUILT_DIR}"
copy_artifact "${OUT_DIR}" 'libcrypto.so*'
copy_artifact "${PREBUILT_DIR}" 'libcrypto.so*'
ls -la "${PREBUILT_DIR}"
