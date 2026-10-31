#!/usr/bin/env bash
# AES encrypt/decrypt a value with the CRYPT_KEY passphrase.
# Usage: crypt.sh <encrypt|decrypt> <value>
set -e
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR"
node src/crypt/crypt.js "$@"
