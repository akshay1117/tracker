#!/usr/bin/env bash
# ==============================================================================
# MacPulse Automated Terminal Installer
# https://github.com/akshay1117/tracker
#
# Install via Terminal (Public repo):
#   curl -fsSL https://raw.githubusercontent.com/akshay1117/tracker/main/install.sh | bash
#
# Install via Terminal (Private repo with token):
#   curl -fsSL -H "Authorization: token $GH_TOKEN" https://raw.githubusercontent.com/akshay1117/tracker/main/install.sh | GITHUB_TOKEN=$GH_TOKEN bash
# ==============================================================================

set -euo pipefail

# ANSI Colors
BOLD="\033[1m"
CYAN="\033[0;36m"
GREEN="\033[0;32m"
AMBER="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

echo -e "${CYAN}${BOLD}"
echo "  __  __            _____       _          "
echo " |  \/  |          |  __ \     | |         "
echo " | \  / | __ _  ___| |__) |   _| |___  ___ "
echo " | |\/| |/ _\` |/ __|  ___/ | | | / __|/ _ \\"
echo " | |  | | (_| | (__| |   | |_| | \__ \  __/"
echo " |_|  |_|\__,_|\___|_|    \__,_|_|___/\___|"
echo -e "${NC}"
echo -e "${BOLD}MacPulse — Native macOS Power & Wi-Fi Usage Tracker${NC}"
echo -e "Repository: ${CYAN}https://github.com/akshay1117/tracker${NC}\n"

# 1. Platform Verification
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${RED}Error: MacPulse is built exclusively for macOS.${NC}"
    exit 1
fi

ARCH="$(uname -m)"
echo -e "• Detected Architecture: ${GREEN}${ARCH}${NC}"

# Target installation directory
TARGET_DIR="/Applications"
if [[ ! -w "${TARGET_DIR}" ]]; then
    TARGET_DIR="${HOME}/Applications"
    mkdir -p "${TARGET_DIR}"
fi
DEST_APP="${TARGET_DIR}/MacPulse.app"

TMP_DIR="$(mktemp -d -t macpulse_installer_XXXXXX)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

REPO="akshay1117/tracker"
RELEASE_URL="https://github.com/${REPO}/releases/latest/download/MacPulse.zip"
ZIP_PATH="${TMP_DIR}/MacPulse.zip"

echo -e "• Fetching MacPulse release package..."

TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

DOWNLOAD_SUCCESS=false
if [[ -n "${TOKEN}" ]]; then
    if curl -H "Authorization: Bearer ${TOKEN}" -fsSL -o "${ZIP_PATH}" "${RELEASE_URL}" 2>/dev/null; then
        DOWNLOAD_SUCCESS=true
    fi
else
    if curl -fsSL -o "${ZIP_PATH}" "${RELEASE_URL}" 2>/dev/null; then
        DOWNLOAD_SUCCESS=true
    fi
fi

# Fallback: If no pre-built release asset found, try source clone & compile
if [[ "${DOWNLOAD_SUCCESS}" != "true" ]]; then
    echo -e "${AMBER}• Pre-built release archive not yet published. Building directly from source...${NC}"
    
    if ! command -v swift >/dev/null 2>&1; then
        echo -e "${RED}Error: Swift toolchain required to compile from source. Install via: xcode-select --install${NC}"
        exit 1
    fi
    
    CLONE_SUCCESS=false
    if [[ -n "${TOKEN}" ]]; then
        if git clone --depth 1 "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "${TMP_DIR}/tracker" 2>/dev/null; then
            CLONE_SUCCESS=true
        fi
    fi

    if [[ "${CLONE_SUCCESS}" != "true" ]]; then
        if git clone --depth 1 "https://github.com/${REPO}.git" "${TMP_DIR}/tracker" 2>/dev/null || \
           git clone --depth 1 "git@github.com:${REPO}.git" "${TMP_DIR}/tracker" 2>/dev/null; then
            CLONE_SUCCESS=true
        fi
    fi
    
    if [[ "${CLONE_SUCCESS}" == "true" ]]; then
        echo -e "• Compiling release binary with optimizations..."
        (cd "${TMP_DIR}/tracker" && ./build.sh >/dev/null)
        cp -R "${TMP_DIR}/tracker/MacPulse.app" "${TMP_DIR}/"
    else
        echo -e "${RED}Error: Could not download release or clone repository.${NC}"
        echo -e "Note: If your repository is set to 'Private' on GitHub, ensure you either:"
        echo -e "  1. Make the repository ${BOLD}Public${NC} on GitHub (Settings -> Danger Zone -> Change repository visibility -> Make public)"
        echo -e "  2. Or provide a token: ${CYAN}GITHUB_TOKEN=your_token curl -fsSL ... | bash${NC}"
        exit 1
    fi
else
    echo -e "• Download complete. Unpacking application bundle..."
    unzip -q "${ZIP_PATH}" -d "${TMP_DIR}"
fi

# 2. Deploy to Applications
echo -e "• Installing to ${GREEN}${DEST_APP}${NC}..."
pkill -9 -x MacPulse 2>/dev/null || true
rm -rf "${DEST_APP}"
cp -R "${TMP_DIR}/MacPulse.app" "${TARGET_DIR}/"

# 3. Gatekeeper Quarantine Removal (ensures clean launch on macOS 14/15)
echo -e "• Authorizing application with macOS Gatekeeper..."
xattr -dr com.apple.quarantine "${DEST_APP}" 2>/dev/null || true

# 4. Launch Application
echo -e "• Launching MacPulse..."
open "${DEST_APP}"

echo -e "\n${GREEN}${BOLD}✓ MacPulse installed and launched successfully!${NC}"
echo -e "Look for the ${BOLD}bolt icon${NC} in your macOS Menu Bar or in ${DEST_APP}."
echo -e "To update anytime, run:\n"
echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash${NC}\n"
