#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${NATIVE_DIR}/.." && pwd)"

OPENSSL_VERSION="$(tr -d '\r\n' < "${NATIVE_DIR}/src/VERSION")"
PREBUILT_VERSION_ROOT="${REPO_ROOT}/native/prebuilt/${OPENSSL_VERSION}"
OPENSSL_SRC="${REPO_ROOT}/native/third_party/openssl"
OPENSSL_TARBALL="openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/${OPENSSL_TARBALL}"

CONFIGURE_ARGS=(no-unit-test no-makedepend no-ssl no-apps -Wl,-headerpad_max_install_names)

ensure_openssl_src() {
  if [[ -f "${OPENSSL_SRC}/Configure" ]]; then
    return 0
  fi
  local tarball_dir="${REPO_ROOT}/native/out/_src"
  local work="${tarball_dir}/${TRIPLE}"
  local extracted="${work}/openssl-${OPENSSL_VERSION}"
  mkdir -p "${work}" "${tarball_dir}"
  if [[ ! -f "${tarball_dir}/${OPENSSL_TARBALL}" ]]; then
    curl -L "${OPENSSL_URL}" -o "${tarball_dir}/${OPENSSL_TARBALL}"
  fi
  if [[ -f "${extracted}/Configure" ]]; then
    OPENSSL_SRC="${extracted}"
    export OPENSSL_SRC
    return 0
  fi
  tar -xzf "${tarball_dir}/${OPENSSL_TARBALL}" -C "${work}"
  OPENSSL_SRC="${extracted}"
  export OPENSSL_SRC
}

copy_artifact() {
  local dest_dir="${1}"
  local pattern="${2}"
  mkdir -p "${dest_dir}"
  local file
  file="$(find "${OPENSSL_SRC}" -maxdepth 1 -type f -name "${pattern}" | head -1)"
  if [[ -z "${file}" ]]; then
    echo "Artifact matching ${pattern} not found in ${OPENSSL_SRC}"
    exit 1
  fi
  cp -v "${file}" "${dest_dir}/"
}
