#!/usr/bin/env bash
# One-time / refresh setup for openssl git dependency (LFS prebuilts).
set -euo pipefail
cd "$(dirname "$0")/.."
export GIT_LFS_SKIP_SMUDGE=1
echo "==> flutter pub get"
flutter pub get
echo "==> dart run openssl:setup_prebuilts"
dart run openssl:setup_prebuilts
