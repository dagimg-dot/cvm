#!/bin/bash

set -euo pipefail
trap 'printf "\nScript interrupted by user. Please remove any unfinished downloads (if any) using --remove option.\n"; exit 130' INT TERM

#H#
#H# cvm.sh — Cursor version manager
#H#
#H#  ██████╗██╗   ██╗███╗   ███╗
#H# ██╔════╝██║   ██║████╗ ████║
#H# ██║     ██║   ██║██╔████╔██║
#H# ██║     ╚██╗ ██╔╝██║╚██╔╝██║
#H# ╚██████╗ ╚████╔╝ ██║ ╚═╝ ██║
#H# ╚═════╝  ╚═══╝  ╚═╝     ╚═╝
#H#
#H#
#H# Examples:
#H#   cvm --version
#H#   cvm --list-local
#H#   cvm --use 1.4.4
#H#
#H# Notice*:
#H#   Packages are downloaded from the official Cursor releases.
#H#   Package type is auto-detected (deb/rpm/appimage) or can be set with CVM_PACKAGE_TYPE.
#H#   The list of download sources can be found at https://github.com/oslook/cursor-ai-downloads
#H#
#H# Options:
#H#   -l --list-local      Lists locally available versions
#H#   -L --list-remote     Lists versions available for download
#H#   -d --download <version> Downloads a version
#H#   -u --update          Downloads and selects the latest version
#H#   -U --use <version>   Selects a locally available version
#H#   -a --active          Shows the currently selected version
#H#   -r --remove <version...>  Removes one or more locally available versions
#H#   -i --install [<version>] Adds an alias `cursor` and installs the latest version or specified version
#H#   -I --uninstall       Removes the Cursor version manager directory and alias
#H#   -s --update-script   Updates the (cvm.sh) script to the latest version
#H#   -v --version         Shows the current and latest versions for cvm.sh and Cursor
#H#   -h --help            Shows this message

#
# Constants
#
CURSOR_DIR="$HOME/.local/share/cvm"
DOWNLOADS_DIR="$CURSOR_DIR/app-images"
RPM_DIR="$CURSOR_DIR/rpms"
DEB_DIR="$CURSOR_DIR/debs"
ASSETS_DIR="$CURSOR_DIR/assets"
DESKTOP_ENTRY_PATH="$HOME/.local/share/applications/cursor.desktop"
CVM_VERSION="1.2.1"
_CACHE_FILE="/tmp/cursor_versions.json"
VERSION_HISTORY_URL="https://raw.githubusercontent.com/oslook/cursor-ai-downloads/refs/heads/main/version-history.json"
GITHUB_API_URL="https://api.github.com/repos/dagimg-dot/cvm/releases/latest"
CURSOR_ICON_URL="https://raw.githubusercontent.com/dagimg-dot/cvm/main/assets/cursor.png"

# Color definitions
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

#
# Functions
#
help() {
  sed -rn 's/^#H# ?//;T;p' "$0"
}

print_color() {
  color=$1
  text=$2
  printf "%b%s%b\n" "$color" "$text" "$NC"
}

getLatestScriptVersion() {
  # Fetch latest release version from GitHub API
  latest_version=$(wget -qO- "$GITHUB_API_URL" | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
  if [ -n "$latest_version" ]; then
    echo "$latest_version"
    return 0
  else
    return 1
  fi
}

getVersionHistory() {
  # Check if cache file exists and is less than 15 min old
  if [ -f "$_CACHE_FILE" ] && [ -n "$(find "$_CACHE_FILE" -mmin -15 2>/dev/null)" ]; then
    cat "$_CACHE_FILE"
    return 0
  fi

  # Fetch JSON directly from remote and cache it
  # echo "Fetching version history..." >&2
  if wget -qO "$_CACHE_FILE.tmp" "$VERSION_HISTORY_URL"; then
    mv "$_CACHE_FILE.tmp" "$_CACHE_FILE"
    cat "$_CACHE_FILE"
    return 0
  else
    rm -f "$_CACHE_FILE.tmp"
    echo "Error: Failed to fetch version history" >&2
    return 1
  fi
}

getPlatform() {
  architecture=$(uname -m)
  case "$architecture" in
  x86_64)
    echo "linux-x64"
    ;;
  aarch64 | arm64)
    echo "linux-arm64"
    ;;
  *)
    echo "Error: Unsupported architecture: $architecture" >&2
    return 1
    ;;
  esac
}

detectPackageManager() {
  # Check for dnf/yum/rpm (RPM based) first - more specific to RPM-based distros
  if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1 || command -v rpm >/dev/null 2>&1; then
    echo "rpm"
    return 0
  fi

  # Check for apt/dpkg (Debian/Ubuntu based)
  if command -v apt >/dev/null 2>&1 || command -v dpkg >/dev/null 2>&1; then
    echo "deb"
    return 0
  fi

  # Default to appimage if neither is detected
  echo "appimage"
  return 0
}

getPackageType() {
  # Allow override via environment variable
  if [ -n "${CVM_PACKAGE_TYPE:-}" ]; then
    case "${CVM_PACKAGE_TYPE,,}" in
    deb | rpm | appimage)
      echo "${CVM_PACKAGE_TYPE,,}"
      return 0
      ;;
    *)
      echo "Warning: Invalid CVM_PACKAGE_TYPE '$CVM_PACKAGE_TYPE', ignoring" >&2
      ;;
    esac
  fi

  detectPackageManager
}

# Set platform and fail fast if unsupported
if ! platform=$(getPlatform); then
  exit 1
fi

# Set package type for the session
package_type=$(getPackageType)

# URL construction functions for different package types
constructAppImageUrl() {
  local appimage_url="$1"
  echo "$appimage_url"
}

constructRpmUrl() {
  local appimage_url="$1"
  local version="$2"

  # Extract base URL up to the platform part
  # From: https://downloads.cursor.com/production/.../linux/x64/Cursor-X.Y.Z-x86_64.AppImage
  # To:   https://downloads.cursor.com/production/.../linux/x64/rpm/x86_64/cursor-X.Y.Z.el8.x86_64.rpm

  local base_url
  base_url=${appimage_url%/Cursor-*-x86_64.AppImage}
  echo "${base_url}/rpm/x86_64/cursor-${version}.el8.x86_64.rpm"
}

constructDebUrl() {
  local appimage_url="$1"
  local version="$2"

  # Extract base URL up to the platform part
  # From: https://downloads.cursor.com/production/.../linux/x64/Cursor-X.Y.Z-x86_64.AppImage
  # To:   https://downloads.cursor.com/production/.../linux/x64/deb/amd64/cursor_X.Y.Z_amd64.deb

  local base_url
  base_url=${appimage_url%/Cursor-*-x86_64.AppImage}

  # Convert version format: 1.7.39 -> 1.7.39 (underscore instead of dots for deb)
  local deb_version
  deb_version=$(echo "$version" | tr '.' '_')
  echo "${base_url}/deb/amd64/cursor_${deb_version}_amd64.deb"
}

constructPackageUrl() {
  local appimage_url="$1"
  local version="$2"
  local package_type="$3"

  case "$package_type" in
  appimage)
    constructAppImageUrl "$appimage_url"
    ;;
  rpm)
    constructRpmUrl "$appimage_url" "$version"
    ;;
  deb)
    constructDebUrl "$appimage_url" "$version"
    ;;
  *)
    echo "Error: Unknown package type: $package_type" >&2
    return 1
    ;;
  esac
}

# Strategy pattern: Package-specific implementations

# AppImage strategy
getAppImageDownloadUrl() {
  local version="$1"
  getVersionHistory |
    jq -r --arg v "$version" --arg platform "$platform" '.versions[] | select(.version == $v and .platforms[$platform] != null) | .platforms[$platform]'
}

downloadAppImage() {
  local version="$1"
  local url
  url=$(getAppImageDownloadUrl "$version")

  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "Version $version is not available for platform $platform." >&2
    return 1
  fi

  mkdir -p "$DOWNLOADS_DIR"
  local localFilename="cursor-$version.AppImage"
  echo "Downloading Cursor $version (AppImage)..."
  # Capture server response to check HTTP status, but show progress
  if wget --server-response -O "$DOWNLOADS_DIR/$localFilename" "$url" 2>&1 | tee /dev/stderr | grep -q "HTTP/.* 200"; then
    chmod +x "$DOWNLOADS_DIR/$localFilename"
    echo "Cursor $version downloaded to $DOWNLOADS_DIR/$localFilename"
  else
    echo "Error: Failed to download Cursor $version (HTTP error or file not found)" >&2
    rm -f "$DOWNLOADS_DIR/$localFilename" # Clean up partial download
    return 1
  fi
}

selectAppImage() {
  local version="$1"
  local filename="cursor-$version.AppImage"
  local appimage_path="$DOWNLOADS_DIR/$filename"
  ln -sf "$appimage_path" "$CURSOR_DIR/active"
  echo "Symlink created: $CURSOR_DIR/active -> $appimage_path"
  echo "Close all instances of Cursor and reopen it to use the new version."
}

# RPM strategy
getRpmDownloadUrl() {
  local version="$1"
  local appimage_url
  appimage_url=$(getAppImageDownloadUrl "$version")

  if [ -z "$appimage_url" ] || [ "$appimage_url" = "null" ]; then
    echo "Version $version is not available for platform $platform." >&2
    return 1
  fi

  constructRpmUrl "$appimage_url" "$version"
}

downloadRpm() {
  local version="$1"
  local url
  url=$(getRpmDownloadUrl "$version")

  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "Version $version is not available for platform $platform." >&2
    return 1
  fi

  mkdir -p "$RPM_DIR"
  local localFilename="cursor-$version.rpm"
  echo "Downloading Cursor $version (RPM)..."
  # Capture server response to check HTTP status, but show progress
  if wget --server-response -O "$RPM_DIR/$localFilename" "$url" 2>&1 | tee /dev/stderr | grep -q "HTTP/.* 200"; then
    echo "Cursor $version downloaded to $RPM_DIR/$localFilename"
  else
    echo "Error: Failed to download Cursor $version (HTTP error or file not found)" >&2
    rm -f "$RPM_DIR/$localFilename" # Clean up partial download
    return 1
  fi
}

extractRpm() {
  local version="$1"
  local rpm_file="$RPM_DIR/cursor-$version.rpm"
  local extract_dir="$RPM_DIR/cursor-$version"

  if [ ! -f "$rpm_file" ]; then
    echo "Error: RPM file not found: $rpm_file" >&2
    return 1
  fi

  echo "Extracting RPM package..."
  mkdir -p "$extract_dir"
  cd "$extract_dir" || return 1

  # Extract RPM using rpm2cpio and cpio
  if rpm2cpio "$rpm_file" | cpio -idmv 2>/dev/null; then
    echo "RPM extracted successfully to $extract_dir"
    # Find the cursor binary/executable
    local cursor_binary
    cursor_binary=$(find . -name "cursor" -type f -executable 2>/dev/null | head -n1)
    if [ -n "$cursor_binary" ]; then
      echo "Found Cursor binary: $cursor_binary"
      return 0
    else
      echo "Warning: Could not find cursor executable in extracted RPM" >&2
      return 1
    fi
  else
    echo "Error: Failed to extract RPM package" >&2
    return 1
  fi
}

selectRpm() {
  local version="$1"
  local extract_dir="$RPM_DIR/cursor-$version"
  local cursor_binary="$extract_dir/usr/bin/cursor" # RPM extraction path

  # If not found in expected location, try alternative locations
  if [ ! -f "$cursor_binary" ]; then
    cursor_binary="$extract_dir/usr/share/cursor/bin/cursor" # Alternative RPM path
  fi
  if [ ! -f "$cursor_binary" ]; then
    cursor_binary="$extract_dir/opt/cursor/cursor" # Fallback RPM path
  fi
  if [ ! -f "$cursor_binary" ]; then
    cursor_binary=$(find "$extract_dir" -name "cursor" -type f -executable 2>/dev/null | head -n1)
  fi

  if [ -z "$cursor_binary" ]; then
    echo "Error: Could not find cursor executable for version $version" >&2
    return 1
  fi

  ln -sf "$cursor_binary" "$CURSOR_DIR/active"
  echo "Symlink created: $CURSOR_DIR/active -> $cursor_binary"
  echo "Close all instances of Cursor and reopen it to use the new version."
}

# DEB strategy
getDebDownloadUrl() {
  local version="$1"
  local appimage_url
  appimage_url=$(getAppImageDownloadUrl "$version")

  if [ -z "$appimage_url" ] || [ "$appimage_url" = "null" ]; then
    echo "Version $version is not available for platform $platform." >&2
    return 1
  fi

  constructDebUrl "$appimage_url" "$version"
}

downloadDeb() {
  local version="$1"
  local url
  url=$(getDebDownloadUrl "$version")

  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "Version $version is not available for platform $platform." >&2
    return 1
  fi

  mkdir -p "$DEB_DIR"
  local localFilename="cursor-$version.deb"
  echo "Downloading Cursor $version (DEB)..."
  # Capture server response to check HTTP status, but show progress
  if wget --server-response -O "$DEB_DIR/$localFilename" "$url" 2>&1 | tee /dev/stderr | grep -q "HTTP/.* 200"; then
    echo "Cursor $version downloaded to $DEB_DIR/$localFilename"
  else
    echo "Error: Failed to download Cursor $version (HTTP error or file not found)" >&2
    rm -f "$DEB_DIR/$localFilename" # Clean up partial download
    return 1
  fi
}

extractDeb() {
  local version="$1"
  local deb_file="$DEB_DIR/cursor-$version.deb"
  local extract_dir="$DEB_DIR/cursor-$version"

  if [ ! -f "$deb_file" ]; then
    echo "Error: DEB file not found: $deb_file" >&2
    return 1
  fi

  echo "Extracting DEB package..."
  mkdir -p "$extract_dir"
  cd "$extract_dir" || return 1

  # Extract DEB using dpkg-deb
  if dpkg-deb -x "$deb_file" . 2>/dev/null; then
    echo "DEB extracted successfully to $extract_dir"
    # Find the cursor binary/executable
    local cursor_binary
    cursor_binary=$(find . -name "cursor" -type f -executable 2>/dev/null | head -n1)
    if [ -n "$cursor_binary" ]; then
      echo "Found Cursor binary: $cursor_binary"
      return 0
    else
      echo "Warning: Could not find cursor executable in extracted DEB" >&2
      return 1
    fi
  else
    echo "Error: Failed to extract DEB package" >&2
    return 1
  fi
}

selectDeb() {
  local version="$1"
  local extract_dir="$DEB_DIR/cursor-$version"
  local cursor_binary="$extract_dir/usr/bin/cursor" # DEB extraction path

  # If not found in expected location, try alternative locations
  if [ ! -f "$cursor_binary" ]; then
    cursor_binary="$extract_dir/usr/share/cursor/bin/cursor" # Alternative DEB path
  fi
  if [ ! -f "$cursor_binary" ]; then
    cursor_binary="$extract_dir/opt/cursor/cursor" # Fallback DEB path
  fi
  if [ ! -f "$cursor_binary" ]; then
    cursor_binary=$(find "$extract_dir" -name "cursor" -type f -executable 2>/dev/null | head -n1)
  fi

  if [ -z "$cursor_binary" ]; then
    echo "Error: Could not find cursor executable for version $version" >&2
    return 1
  fi

  ln -sf "$cursor_binary" "$CURSOR_DIR/active"
  echo "Symlink created: $CURSOR_DIR/active -> $cursor_binary"
  echo "Close all instances of Cursor and reopen it to use the new version."
}

# Generic functions that dispatch to the appropriate strategy

downloadVersion() {
  local version="$1"
  case "$package_type" in
  appimage)
    downloadAppImage "$version"
    ;;
  rpm)
    downloadRpm "$version"
    ;;
  deb)
    downloadDeb "$version"
    ;;
  *)
    echo "Error: Unsupported package type: $package_type" >&2
    return 1
    ;;
  esac
}

extractPackage() {
  local version="$1"
  case "$package_type" in
  appimage)
    # AppImage doesn't need extraction
    return 0
    ;;
  rpm)
    extractRpm "$version"
    ;;
  deb)
    extractDeb "$version"
    ;;
  *)
    echo "Error: Unsupported package type: $package_type" >&2
    return 1
    ;;
  esac
}

selectVersion() {
  local version="$1"
  case "$package_type" in
  appimage)
    selectAppImage "$version"
    ;;
  rpm)
    # For RPM, we need to extract first if not already extracted
    local extract_dir="$RPM_DIR/cursor-$version"
    if [ ! -d "$extract_dir" ]; then
      extractRpm "$version" || return 1
    fi
    selectRpm "$version"
    ;;
  deb)
    # For DEB, we need to extract first if not already extracted
    local extract_dir="$DEB_DIR/cursor-$version"
    if [ ! -d "$extract_dir" ]; then
      extractDeb "$version" || return 1
    fi
    selectDeb "$version"
    ;;
  *)
    echo "Error: Unsupported package type: $package_type" >&2
    return 1
    ;;
  esac
}

getPackageExtension() {
  case "$package_type" in
  appimage)
    echo "AppImage"
    ;;
  rpm)
    echo "rpm"
    ;;
  deb)
    echo "deb"
    ;;
  *)
    echo "unknown"
    ;;
  esac
}

isPackageDownloaded() {
  local version="$1"
  local extension
  extension=$(getPackageExtension)

  case "$package_type" in
  appimage)
    [ -f "$DOWNLOADS_DIR/cursor-$version.$extension" ]
    ;;
  rpm)
    [ -f "$RPM_DIR/cursor-$version.$extension" ] || [ -d "$RPM_DIR/cursor-$version" ]
    ;;
  deb)
    [ -f "$DEB_DIR/cursor-$version.$extension" ] || [ -d "$DEB_DIR/cursor-$version" ]
    ;;
  *)
    false
    ;;
  esac
}

getRemoteVersions() {
  getVersionHistory |
    jq -r ".versions[] | select(.platforms[\"$platform\"] != null) | .version" |
    sort -V
}

getLatestRemoteVersion() {
  getVersionHistory |
    jq -r ".versions[] | select(.platforms[\"$platform\"] != null) | .version" |
    sort -V |
    tail -n1
}

getLatestLocalVersion() {
  # Find versions across different package types
  local versions=""

  case "$package_type" in
  appimage)
    versions=""
    for file in "$DOWNLOADS_DIR"/cursor-*.AppImage; do
      [[ -f "$file" ]] || continue
      [[ "$file" =~ cursor-([0-9.]+)\.AppImage$ ]] && versions="${versions:+$versions$'\n'}${BASH_REMATCH[1]}"
    done
    ;;
  rpm)
    versions=""
    for file in "$RPM_DIR"/cursor-*.rpm; do
      [[ -f "$file" ]] || continue
      [[ "$file" =~ cursor-([0-9.]+)\.rpm$ ]] && versions="${versions:+$versions$'\n'}${BASH_REMATCH[1]}"
    done
    # Also check for extracted directories
    local extracted_versions=""
    for dir in "$RPM_DIR"/cursor-*; do
      [[ -d "$dir" ]] || continue
      [[ "$dir" =~ cursor-([0-9.]+)$ ]] && extracted_versions="${extracted_versions:+$extracted_versions$'\n'}${BASH_REMATCH[1]}"
    done
    versions=$(echo -e "$versions\n$extracted_versions" | sort -V | uniq)
    ;;
  deb)
    versions=""
    for file in "$DEB_DIR"/cursor-*.deb; do
      [[ -f "$file" ]] || continue
      [[ "$file" =~ cursor-([0-9.]+)\.deb$ ]] && versions="${versions:+$versions$'\n'}${BASH_REMATCH[1]}"
    done
    # Also check for extracted directories
    local extracted_versions=""
    for dir in "$DEB_DIR"/cursor-*; do
      [[ -d "$dir" ]] || continue
      [[ "$dir" =~ cursor-([0-9.]+)$ ]] && extracted_versions="${extracted_versions:+$extracted_versions$'\n'}${BASH_REMATCH[1]}"
    done
    versions=$(echo -e "$versions\n$extracted_versions" | sort -V | uniq)
    ;;
  esac

  local latest_version
  latest_version=$(echo "$versions" | sort -V -r | head -n 1 || true)

  if [ -z "$latest_version" ]; then
    echo "not found for $package_type"
  else
    echo "$latest_version"
  fi
}

getActiveVersion() {
  if [ -L "$CURSOR_DIR/active" ]; then
    active_path=$(readlink "$CURSOR_DIR/active")
    filename=$(basename "$active_path")

    # Determine the package type of the active version
    local active_package_type="unknown"
    local version=""

    # Check if it's an AppImage
    if [[ "$filename" =~ cursor-([0-9.]+)\.AppImage$ ]]; then
      version="${BASH_REMATCH[1]}"
      active_package_type="appimage"
    # Check if it's from an extracted RPM/DEB directory
    elif [[ "$active_path" =~ /cursor-([0-9.]+)/ ]]; then
      version="${BASH_REMATCH[1]}"
      # Determine if it's RPM or DEB by checking which directory it came from
      if [[ "$active_path" =~ ^$RPM_DIR/ ]]; then
        active_package_type="rpm"
      elif [[ "$active_path" =~ ^$DEB_DIR/ ]]; then
        active_package_type="deb"
      else
        active_package_type="extracted"
      fi
    fi

    if [ -n "$version" ]; then
      echo "$version ($active_package_type)"
    else
      # Fallback: try to extract from any cursor- prefix
      if [[ "$filename" =~ cursor-([0-9.]+) ]]; then
        version="${BASH_REMATCH[1]}"
        # Remove any file extension
        version=${version%.*}
        echo "$version (unknown)"
      else
        echo "Error: Could not determine version from active symlink: $active_path" >&2
        exit 1
      fi
    fi
  else
    echo "None"
  fi
}

exitIfVersionNotInstalled() {
  local version=$1

  case "$package_type" in
  appimage)
    local appimage_path
    appimage_path="$DOWNLOADS_DIR/cursor-$version.AppImage"
    if [ ! -f "$appimage_path" ]; then
      echo "Version $version not found locally. Use \`cvm --list-local\` to list available versions."
      exit 1
    fi
    ;;
  rpm)
    local package_file
    package_file="$RPM_DIR/cursor-$version.$(getPackageExtension)"
    local extract_dir
    extract_dir="$RPM_DIR/cursor-$version"
    if [ ! -f "$package_file" ] && [ ! -d "$extract_dir" ]; then
      echo "Version $version not found locally. Use \`cvm --list-local\` to list available versions."
      exit 1
    fi
    ;;
  deb)
    local package_file
    package_file="$DEB_DIR/cursor-$version.$(getPackageExtension)"
    local extract_dir
    extract_dir="$DEB_DIR/cursor-$version"
    if [ ! -f "$package_file" ] && [ ! -d "$extract_dir" ]; then
      echo "Version $version not found locally. Use \`cvm --list-local\` to list available versions."
      exit 1
    fi
    ;;
  esac
}

setupAssets() {
  echo "Setting up assets..."
  mkdir -p "$ASSETS_DIR"

  local icon_path="$ASSETS_DIR/cursor.png"
  if [ ! -f "$icon_path" ]; then
    echo "Downloading Cursor icon..."
    if wget -qO "$icon_path" "$CURSOR_ICON_URL"; then
      echo "Icon downloaded successfully."
    else
      echo "Warning: Failed to download icon. Desktop entry will be created without icon."
      return 1
    fi
  else
    echo "Icon already exists."
  fi
  return 0
}

createDesktopEntry() {
  echo "Creating desktop entry..."
  mkdir -p "$(dirname "$DESKTOP_ENTRY_PATH")"

  local icon_path="$ASSETS_DIR/cursor.png"
  # Use icon path only if file exists, otherwise omit the Icon line
  local icon_line=""
  if [ -f "$icon_path" ]; then
    icon_line="Icon=$icon_path"
  fi

  cat >"$DESKTOP_ENTRY_PATH" <<EOF
[Desktop Entry]
Name=Cursor
Comment=The AI Code Editor.
GenericName=Text Editor
Exec=$CURSOR_DIR/active
${icon_line}
Type=Application
StartupNotify=false
StartupWMClass=Cursor
Categories=TextEditor;Development;IDE;
MimeType=application/x-cursor-workspace;
Actions=new-empty-window;
Keywords=cursor;

[Desktop Action new-empty-window]
Name=New Empty Window
Name[de]=Neues leeres Fenster
Name[es]=Nueva ventana vacía
Name[fr]=Nouvelle fenêtre vide
Name[it]=Nuova finestra vuota
Name[ja]=新しい空のウィンドウ
Name[ko]=새 빈 창
Name[ru]=Новое пустое окно
Name[zh_CN]=新建空窗口
Name[zh_TW]=開新空視窗
Exec=$CURSOR_DIR/active --new-window %F
${icon_line}
EOF

  echo "Desktop entry created at $DESKTOP_ENTRY_PATH"
}

installCVM() {
  latestRemoteVersion=$(getLatestRemoteVersion)

  if [ -z "$latestRemoteVersion" ]; then
    echo "Error: Could not determine the latest Cursor version available for download" >&2
    return 1
  fi

  latestLocalVersion=$(getLatestLocalVersion)
  if [ "$latestRemoteVersion" != "$latestLocalVersion" ]; then
    if ! downloadVersion "$latestRemoteVersion"; then
      echo "Error: Failed to download Cursor $latestRemoteVersion" >&2
      return 1
    fi
  fi

  if ! selectVersion "$latestRemoteVersion"; then
    echo "Error: Failed to select Cursor $latestRemoteVersion" >&2
    return 1
  fi

  echo "Cursor $latestRemoteVersion installed and activated."

  # Setup assets and create desktop entry
  if ! setupAssets; then
    echo "Warning: Failed to setup assets, but continuing with installation" >&2
  fi
  if ! createDesktopEntry; then
    echo "Warning: Failed to create desktop entry, but continuing with installation" >&2
  fi

  setupAlias
}

uninstallCVM() {
  rm -rf "$CURSOR_DIR"
  rm -rf "$RPM_DIR"
  rm -rf "$DEB_DIR"

  # Remove desktop entry
  if [ -f "$DESKTOP_ENTRY_PATH" ]; then
    rm "$DESKTOP_ENTRY_PATH"
    echo "Desktop entry removed from $DESKTOP_ENTRY_PATH"
  fi

  case "$(basename "$SHELL")" in
  sh | dash)
    if grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.profile"; then
      sed -i "\#alias cursor='$CURSOR_DIR/active'#d" "$HOME/.profile"
      echo "Alias removed from ~/.profile"
      echo "Run '. ~/.profile' to apply the changes or restart your shell."
    fi
    ;;
  bash)
    if grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.bashrc"; then
      sed -i "\#alias cursor='$CURSOR_DIR/active'#d" "$HOME/.bashrc"
      echo "Alias removed from ~/.bashrc"
      echo "Run 'source ~/.bashrc' to apply the changes or restart your shell."
    fi
    ;;
  zsh)
    if grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.zshrc"; then
      sed -i "\#alias cursor='$CURSOR_DIR/active'#d" "$HOME/.zshrc"
      echo "Alias removed from ~/.zshrc"
      echo "Run 'source ~/.zshrc' to apply the changes or restart your shell."
    fi
    ;;
  fish)
    if [ -f "$HOME/.config/fish/functions/cursor.fish" ]; then
      rm "$HOME/.config/fish/functions/cursor.fish"
      echo "Cursor function removed from ~/.config/fish/functions/cursor.fish"
    fi
    ;;
  esac
  echo "Cursor version manager uninstalled."
}

checkDependencies() {
  local base_deps=("sed" "grep" "jq" "find" "wget")
  local package_deps=()

  # Add package-specific dependencies
  case "$package_type" in
  rpm)
    package_deps=("rpm2cpio" "cpio")
    ;;
  deb)
    package_deps=("dpkg-deb")
    ;;
  esac

  # Check all dependencies
  for program in "${base_deps[@]}" "${package_deps[@]}"; do
    if ! command -v "$program" >/dev/null 2>&1; then
      echo "Error: $program is not installed (required for $package_type packages)." >&2
      exit 1
    fi
  done
}

isShellSupported() {
  case "$(basename "$SHELL")" in
  sh | dash | bash | zsh | fish)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

setupAlias() {
  echo "Adding alias to your shell config..."
  case "$(basename "$SHELL")" in
  sh | dash)
    if ! grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.profile"; then
      echo "alias cursor='$CURSOR_DIR/active'" >>"$HOME/.profile"
    fi
    ;;
  bash)
    if ! grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.bashrc"; then
      echo "alias cursor='$CURSOR_DIR/active'" >>"$HOME/.bashrc"
    fi
    ;;
  zsh)
    if ! grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.zshrc"; then
      echo "alias cursor='$CURSOR_DIR/active'" >>"$HOME/.zshrc"
    fi
    ;;
  fish)
    if [ "$package_type" = "appimage" ]; then
      # AppImage needs --no-sandbox flag for proper functioning
      if [ ! -f "$HOME/.config/fish/functions/cursor.fish" ] || ! grep -q "function cursor" "$HOME/.config/fish/functions/cursor.fish"; then
        mkdir -p "$HOME/.config/fish/functions"
        {
          echo "function cursor"
          echo "    nohup $CURSOR_DIR/active \$argv --no-sandbox </dev/null >/dev/null 2>&1 &"
          echo "    disown"
          echo "end"
        } >"$HOME/.config/fish/functions/cursor.fish"
      fi
    else
      # RPM/DEB packages don't need special flags
      if [ ! -f "$HOME/.config/fish/functions/cursor.fish" ] || ! grep -q "alias cursor" "$HOME/.config/fish/functions/cursor.fish"; then
        mkdir -p "$HOME/.config/fish/functions"
        echo "alias cursor='$CURSOR_DIR/active'" >"$HOME/.config/fish/functions/cursor.fish"
      fi
    fi
    ;;
  esac
  echo "Alias added. You can now use 'cursor' to run Cursor."
  case "$(basename "$SHELL")" in
  sh | dash)
    echo "Run '. ~/.profile' to apply the changes or restart your shell."
    ;;
  bash)
    echo "Run 'source ~/.bashrc' to apply the changes or restart your shell."
    ;;
  zsh)
    echo "Run 'source ~/.zshrc' to apply the changes or restart your shell."
    ;;
  fish)
    echo "The cursor function has been added in ~/.config/fish/functions/cursor.fish. You can use it immediately."
    ;;
  esac
}

cleanupAppImages() {
  for build_file in "$DOWNLOADS_DIR"/cursor-*-build-*-x86_64.AppImage; do
    # Skip if no files match the pattern
    [ -e "$build_file" ] || continue

    # Extract version number from build file
    version=$(basename "$build_file" | sed -E 's/cursor-([0-9.]+)-build.*/\1/')
    regular_file="$DOWNLOADS_DIR/cursor-$version.AppImage"

    if [ -f "$regular_file" ]; then
      # If regular version exists, remove build version
      rm "$build_file"
      # echo "Removed build version for $version (regular version exists)"
    else
      # If only build version exists, rename it to regular format
      mv "$build_file" "$regular_file"
      # echo "Renamed build version to regular format for $version"
    fi
  done
}

updateScript() {
  version=$(getLatestScriptVersion)

  if [ -z "$version" ]; then
    echo "Error: Failed to determine version to download" >&2
    return 1
  fi

  # Get the download URL from the release assets
  download_url=$(
    wget -O- "$GITHUB_API_URL" |
      jq -r '.assets[] | select(.name == "cvm.sh") | .browser_download_url'
  )

  if [ -z "$download_url" ]; then
    echo "Error: Failed to find download URL for cvm.sh" >&2
    return 1
  fi

  echo "Downloading CVM version ${version}..."

  # Download to a temporary file in the same directory
  script_dir=$(dirname "$0")
  temp_file="${script_dir}/cvm.sh.new"

  if wget -qO "$temp_file" "$download_url"; then
    chmod +x "$temp_file"
    mv "$temp_file" "$0"
    echo "Successfully updated to version ${version}"
    echo "Please run the script again to use the new version"
    return 0
  else
    rm -f "$temp_file"
    echo "Error: Failed to download version ${version}" >&2
    return 1
  fi
}

#
# Execution
#
if ! isShellSupported; then
  echo "Error: Unsupported shell. Please use bash, zsh, fish, or sh."
  echo "Currently using: $(basename "$SHELL")"
  echo "Open a github issue if you want to add support for your shell:"
  echo "https://github.com/dagimg-dot/cvm/issues"
  exit 1
fi

checkDependencies
mkdir -p "$DOWNLOADS_DIR"
mkdir -p "$RPM_DIR"
mkdir -p "$DEB_DIR"
mkdir -p "$ASSETS_DIR"
cleanupAppImages

# Show ASCII art and help when no arguments are provided
if [ $# -eq 0 ]; then
  help
  exit 0
fi

case "$1" in
--help | -h)
  help
  ;;
--version | -v)
  echo "Cursor Version Manager (cvm.sh):"
  echo "  - Current version: $CVM_VERSION"
  if latest_version=$(getLatestScriptVersion); then
    if [ "$latest_version" != "$CVM_VERSION" ]; then
      echo "  - Latest version: $latest_version"
      print_color "$ORANGE" "There is a newer cvm.sh version available for download!"
      print_color "$ORANGE" "You can update the script with: $0 --update-script"
    else
      print_color "$GREEN" "You are running the latest cvm.sh version!"
    fi
  else
    echo "Failed to check for latest cvm.sh version"
  fi

  echo ""
  echo "Cursor App Information:"
  echo "  - Package type: $package_type"
  latestRemoteVersion=$(getLatestRemoteVersion)
  has_local_installations=false
  [ -d "$DOWNLOADS_DIR" ] && [ -n "$(ls -A "$DOWNLOADS_DIR" 2>/dev/null)" ] && has_local_installations=true
  [ -d "$RPM_DIR" ] && [ -n "$(ls -A "$RPM_DIR" 2>/dev/null)" ] && has_local_installations=true
  [ -d "$DEB_DIR" ] && [ -n "$(ls -A "$DEB_DIR" 2>/dev/null)" ] && has_local_installations=true

  if [ "$has_local_installations" = true ]; then
    latestLocalVersion=$(getLatestLocalVersion)
    activeVersionFull=$(getActiveVersion 2>/dev/null || echo "None")

    # Extract version number from active version (remove package type)
    if [[ "$activeVersionFull" =~ ([0-9.]+) ]]; then
      activeVersion="${BASH_REMATCH[1]}"
    else
      activeVersion="$activeVersionFull"
    fi

    echo "  - Latest remote version: $latestRemoteVersion"
    echo "  - Latest locally available: $latestLocalVersion"
    echo "  - Currently active: $activeVersionFull"

    # Only show update messages if we have valid versions to compare
    if [[ "$latestLocalVersion" != "not found for "* ]] && [[ "$activeVersion" != "None" ]]; then
      if [ "$latestRemoteVersion" != "$latestLocalVersion" ]; then
        print_color "$ORANGE" "There is a newer Cursor version available for download!"
        print_color "$ORANGE" "You can download and activate it with \`cvm --update\`"
      elif [ "$latestRemoteVersion" != "$activeVersion" ]; then
        print_color "$ORANGE" "There is a newer Cursor version already installed!"
        print_color "$ORANGE" "You can activate it with \`cvm --use $latestRemoteVersion\`"
      else
        print_color "$GREEN" "You are running the latest Cursor version!"
      fi
    fi
  else
    echo "  - Latest remote version: $latestRemoteVersion"
    echo "  - No local Cursor installation found"
    print_color "$ORANGE" "To install Cursor, run: $0 --install"
  fi
  ;;
--update | -u)
  latestRemoteVersion=$(getLatestRemoteVersion)

  if [ ! -d "$DOWNLOADS_DIR" ] || [ -z "$(ls -A "$DOWNLOADS_DIR" 2>/dev/null)" ]; then
    echo "No Cursor versions found locally."
    echo "Downloading latest version $latestRemoteVersion..."
    downloadVersion "$latestRemoteVersion"
    selectVersion "$latestRemoteVersion"
    print_color "$GREEN" "Downloaded and switched to version $latestRemoteVersion."
    exit 0
  fi

  activeVersion=$(getActiveVersion 2>/dev/null || echo "None")

  if [ "$latestRemoteVersion" = "$activeVersion" ]; then
    print_color "$GREEN" "You are already running the latest version: $activeVersion"
    exit 0
  fi

  if isPackageDownloaded "$latestRemoteVersion"; then
    echo "Latest version $latestRemoteVersion is already downloaded."
    selectVersion "$latestRemoteVersion"
    print_color "$GREEN" "Switched to version $latestRemoteVersion."
  else
    echo "Downloading latest version $latestRemoteVersion..."
    downloadVersion "$latestRemoteVersion"
    selectVersion "$latestRemoteVersion"
    print_color "$GREEN" "Downloaded and switched to version $latestRemoteVersion."
  fi
  ;;
--list-local | -l)
  local_versions_list=""

  case "$package_type" in
  appimage)
    local_versions_list=""
    for file in "$DOWNLOADS_DIR"/cursor-*.AppImage; do
      [[ -f "$file" ]] || continue
      [[ "$file" =~ cursor-([0-9.]+)\.AppImage$ ]] && local_versions_list="${local_versions_list:+$local_versions_list$'\n'}${BASH_REMATCH[1]}"
    done
    ;;
  rpm)
    package_versions=""
    for file in "$RPM_DIR"/cursor-*.rpm; do
      [[ -f "$file" ]] || continue
      [[ "$file" =~ cursor-([0-9.]+)\.rpm$ ]] && package_versions="${package_versions:+$package_versions$'\n'}${BASH_REMATCH[1]}"
    done
    extracted_versions=""
    for dir in "$RPM_DIR"/cursor-*; do
      [[ -d "$dir" ]] || continue
      [[ "$dir" =~ cursor-([0-9.]+)$ ]] && extracted_versions="${extracted_versions:+$extracted_versions$'\n'}${BASH_REMATCH[1]}"
    done
    local_versions_list=$(echo -e "$package_versions\n$extracted_versions" | sort -V | uniq)
    ;;
  deb)
    package_versions=""
    for file in "$DEB_DIR"/cursor-*.deb; do
      [[ -f "$file" ]] || continue
      [[ "$file" =~ cursor-([0-9.]+)\.deb$ ]] && package_versions="${package_versions:+$package_versions$'\n'}${BASH_REMATCH[1]}"
    done
    extracted_versions=""
    for dir in "$DEB_DIR"/cursor-*; do
      [[ -d "$dir" ]] || continue
      [[ "$dir" =~ cursor-([0-9.]+)$ ]] && extracted_versions="${extracted_versions:+$extracted_versions$'\n'}${BASH_REMATCH[1]}"
    done
    local_versions_list=$(echo -e "$package_versions\n$extracted_versions" | sort -V | uniq)
    ;;
  esac

  if [ -n "$local_versions_list" ]; then
    echo "Locally available versions (using $package_type packages):"
    while IFS= read -r version; do
      [ -n "$version" ] && echo "  - $version"
    done <<<"$local_versions_list"
  else
    echo "  No versions installed."
  fi
  ;;
--list-remote | -L)
  echo "Remote versions:"
  while IFS= read -r version; do
    echo "  - $version"
  done < <(getRemoteVersions)
  ;;
--download | -d)
  if [ -z "${2:-}" ]; then
    echo "Usage: $0 --download <version>"
    exit 1
  fi

  version=$2
  # check if version is available for download
  if ! getRemoteVersions | grep -q "^$version\$"; then
    echo "Version $version not found for download."
    exit 1
  fi

  # check if version is already downloaded
  if isPackageDownloaded "$version"; then
    echo "Version $version already downloaded."
  else
    downloadVersion "$version"
  fi
  echo "To select the downloaded version, run \`cvm --use $version\`"
  ;;
--active | -a)
  getActiveVersion
  ;;
--use | -U)
  if [ -z "${2:-}" ]; then
    echo "Usage: $0 --use <version>"
    exit 1
  fi

  version=$2
  exitIfVersionNotInstalled "$version"
  selectVersion "$version"
  ;;
--remove | -r)
  if [ -z "${2:-}" ]; then
    echo "Usage: $0 --remove <version1> <version2> <version3>..."
    exit 1
  fi

  shift # Skip the --remove argument
  versions=("$@")

  for version in "${versions[@]}"; do
    # Check if version is installed
    if ! isPackageDownloaded "$version"; then
      print_color "$ORANGE" "! Version $version not found locally. Skipping..."
      continue
    fi

    # Check if this version is currently active
    if [ -L "$CURSOR_DIR/active" ]; then
      activeVersion=$(getActiveVersion)
      if [ "$activeVersion" = "$version" ]; then
        echo "Removing active version $version..."
        rm "$CURSOR_DIR/active"
        print_color "$GREEN" "✓ Removed active symlink"
      fi
    fi

    # Remove the package files based on type
    case "$package_type" in
    appimage)
      appimage_file="$DOWNLOADS_DIR/cursor-$version.AppImage"
      echo "Removing AppImage for version $version..."
      if rm "$appimage_file"; then
        print_color "$GREEN" "✓ Successfully removed version $version"
      else
        print_color "$ORANGE" "! Failed to remove version $version"
      fi
      ;;
    rpm)
      package_file="$RPM_DIR/cursor-$version.$(getPackageExtension)"
      extract_dir="$RPM_DIR/cursor-$version"

      echo "Removing $(getPackageExtension | tr '[:lower:]' '[:upper:]') package and extracted files for version $version..."

      # Remove package file
      [ -f "$package_file" ] && rm "$package_file"

      # Remove extracted directory
      [ -d "$extract_dir" ] && rm -rf "$extract_dir"

      print_color "$GREEN" "✓ Successfully removed version $version"
      ;;
    deb)
      package_file="$DEB_DIR/cursor-$version.$(getPackageExtension)"
      extract_dir="$DEB_DIR/cursor-$version"

      echo "Removing $(getPackageExtension | tr '[:lower:]' '[:upper:]') package and extracted files for version $version..."

      # Remove package file
      [ -f "$package_file" ] && rm "$package_file"

      # Remove extracted directory
      [ -d "$extract_dir" ] && rm -rf "$extract_dir"

      print_color "$GREEN" "✓ Successfully removed version $version"
      ;;
    esac
  done

  # Post-remove guidance
  if [ ! -L "$CURSOR_DIR/active" ]; then
    has_any_versions=false
    [ -n "$(ls -A "$DOWNLOADS_DIR" 2>/dev/null)" ] && has_any_versions=true
    [ -n "$(ls -A "$RPM_DIR" 2>/dev/null)" ] && has_any_versions=true
    [ -n "$(ls -A "$DEB_DIR" 2>/dev/null)" ] && has_any_versions=true

    if [ "$has_any_versions" = true ]; then
      echo "No active version selected. To activate one, run: $0 --use <version> (see \`$0 --list-local\`)."
    else
      echo "No Cursor versions installed."
    fi
  fi
  ;;
--install | -i)
  if [ -n "${2:-}" ]; then
    # Install specific version if provided
    version="$2"
    if ! isPackageDownloaded "$version"; then
      # Check if version is available for download
      if ! getRemoteVersions | grep -q "^$version\$"; then
        echo "Error: Version $version not found for download." >&2
        exit 1
      fi

      # Ask for confirmation to download
      echo "Version $version is not downloaded locally."
      echo -n "Would you like to download it now? (y/N): "
      read -r response
      # Trim whitespace and convert to lowercase for more reliable matching
      response=$(echo "$response" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
      case "$response" in
      y | yes)
        echo "Downloading Cursor $version..."
        if ! downloadVersion "$version"; then
          echo "Error: Failed to download Cursor $version" >&2
          exit 1
        fi
        ;;
      *)
        echo "Installation cancelled. Please download the version first with 'cvm --download $version'"
        exit 1
        ;;
      esac
    fi
    selectVersion "$version"
    echo "Cursor $version installed and activated."
    # Setup assets and create desktop entry
    setupAssets >/dev/null 2>&1
    createDesktopEntry >/dev/null 2>&1
    echo "Setting up shell alias..."
    setupAlias
  else
    # Install latest version (original behavior)
    installCVM
  fi
  ;;
--uninstall | -I)
  uninstallCVM
  ;;
--update-script | -s)
  updateScript
  ;;
*)
  echo "Unknown command: $1"
  help
  exit 1
  ;;
esac
