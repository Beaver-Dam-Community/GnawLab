#!/usr/bin/env bash
# build_exiftool_layer.sh
# Packages ExifTool 12.23 (vulnerable to CVE-2021-22204) as a Lambda layer zip.
#
# Requirements:
#   - curl or wget
#   - zip
#   - Perl 5.x (to verify the script is intact; NOT needed at Lambda build time)
#
# Output:
#   ../terraform/exiftool-layer.zip
#
# Layer structure (maps to /opt/ inside Lambda):
#   bin/exiftool     — ExifTool Perl script
#   lib/             — ExifTool Perl library modules (Image::ExifTool::*)
#
# The Lambda Python 3.11 runtime (Amazon Linux 2023) includes system Perl.
# The handler sets PERL5LIB=/opt/lib before invoking perl /opt/bin/exiftool.

set -euo pipefail

VERSION="12.23"
ARCHIVE="exiftool-${VERSION}.tar.gz"
EXTRACT_DIR="exiftool-${VERSION}"
LAYER_DIR="layer"
OUTPUT="../terraform/exiftool-layer.zip"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[*] Building ExifTool ${VERSION} Lambda layer..."

# Clean up any previous build artifacts
rm -rf "$LAYER_DIR" "$ARCHIVE" "$EXTRACT_DIR"

# Download ExifTool 12.23 source
echo "[*] Downloading ExifTool ${VERSION}..."
if command -v curl &>/dev/null; then
    curl -sL "https://github.com/exiftool/exiftool/archive/refs/tags/${VERSION}.tar.gz" -o "$ARCHIVE"
elif command -v wget &>/dev/null; then
    wget -q "https://github.com/exiftool/exiftool/archive/refs/tags/${VERSION}.tar.gz" -O "$ARCHIVE"
else
    echo "[!] Error: curl or wget is required." >&2
    exit 1
fi

# Extract
echo "[*] Extracting..."
tar xzf "$ARCHIVE"

# Package into layer structure
echo "[*] Building layer directory..."
mkdir -p "${LAYER_DIR}/bin" "${LAYER_DIR}/lib"

cp "${EXTRACT_DIR}/exiftool" "${LAYER_DIR}/bin/exiftool"
chmod +x "${LAYER_DIR}/bin/exiftool"
cp -r "${EXTRACT_DIR}/lib/"* "${LAYER_DIR}/lib/"

# Create the zip
echo "[*] Creating ${OUTPUT}..."
(cd "$LAYER_DIR" && zip -r9 "${SCRIPT_DIR}/${OUTPUT}" .)

# Cleanup
rm -rf "$LAYER_DIR" "$ARCHIVE" "$EXTRACT_DIR"

echo "[+] Done: ${SCRIPT_DIR}/${OUTPUT}"
echo "[+] Layer size: $(du -sh "${SCRIPT_DIR}/${OUTPUT}" | cut -f1)"
echo ""
echo "[!] This layer contains ExifTool 12.23, which is VULNERABLE to CVE-2021-22204."
echo "    Do NOT use in production environments."
