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
#H#   The AppImage files are downloaded from the official Cursor releases.
#H#   The list of download sources can be found at https://github.com/oslook/cursor-ai-downloads
#H#
#H# Options:
#H#   --list-local         Lists locally available versions
#H#   --list-remote        Lists versions available for download
#H#   --download <version> Downloads a version
#H#   --update             Downloads and selects the latest version
#H#   --use <version>      Selects a locally available version
#H#   --active             Shows the currently selected version
#H#   --remove <version...>  Removes one or more locally available versions
#H#   --install            Adds an alias `cursor` and downloads the latest version
#H#   --uninstall          Removes the Cursor version manager directory and alias
#H#   --update-script      Updates the (cvm.sh) script to the latest version
#H#   -v --version         Shows the current and latest versions for cvm.sh and Cursor
#H#   -h --help            Shows this message

#
# Constants
#
CURSOR_DIR="$HOME/.local/share/cvm"
DOWNLOADS_DIR="$CURSOR_DIR/app-images"
ASSETS_DIR="$CURSOR_DIR/assets"
DESKTOP_ENTRY_PATH="$HOME/.local/share/applications/cursor.desktop"
CVM_VERSION="1.0.0"
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
    aarch64|arm64)
      echo "linux-arm64"
      ;;
    *)
      echo "Error: Unsupported architecture: $architecture" >&2
      return 1
      ;;
  esac
}

# Set platform and fail fast if unsupported
if ! platform=$(getPlatform); then
  exit 1
fi

getRemoteVersions() {
  getVersionHistory | \
    jq -r ".versions[] | select(.platforms[\"$platform\"] != null) | .version" \
      | sort -V
}

getLatestRemoteVersion() {
  getVersionHistory | \
    jq -r ".versions[] | select(.platforms[\"$platform\"] != null) | .version" \
      | sort -V \
      | tail -n1
}

getLatestLocalVersion() {
  # shellcheck disable=SC2010
  ls -1 "$DOWNLOADS_DIR" 2>/dev/null \
    | grep -oP 'cursor-\K[0-9.]+(?=\.)' \
    | sort -V -r \
    | head -n 1 \
    || true
}

downloadVersion() {
  version=$1 # e.g. 2.1.0
  if [ -z "$version" ]; then
    echo "Error: Version number is required, use \`cvm --list-remote\` to see available versions" >&2
    return 1
  fi

  localFilename="cursor-$version.AppImage"
  url=$(
    getVersionHistory | \
      jq -r --arg v "$version" --arg platform "$platform" '.versions[] | select(.version == $v and .platforms[$platform] != null) | .platforms[$platform]'
  )

  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "Version $version is not available for platform $platform." >&2
    echo "Use \`cvm --list-remote\` to see available versions." >&2
    return 1
  fi

  echo "Downloading Cursor $version..."
  wget -O "$DOWNLOADS_DIR/$localFilename" "$url"
  chmod +x "$DOWNLOADS_DIR/$localFilename"
  echo "Cursor $version downloaded to $DOWNLOADS_DIR/$localFilename"
}

selectVersion() {
  version=$1 # e.g. 2.1.0
  filename="cursor-$version.AppImage"
  appimage_path="$DOWNLOADS_DIR/$filename"
  ln -sf "$appimage_path" "$CURSOR_DIR/active"
  echo "Symlink created: $CURSOR_DIR/active -> $appimage_path"
  echo "Close all instances of Cursor and reopen it to use the new version."
}

getActiveVersion() {
  if [ -L "$CURSOR_DIR/active" ]; then
    appimage_path=$(readlink -f "$CURSOR_DIR/active")
    filename=$(basename "$appimage_path")
    version=${filename#cursor-}
    version=${version%.AppImage}
    echo "$version"
  else
    echo "No active version. Use \`cvm --use <version>\` to select one."
    exit 1
  fi
}

exitIfVersionNotInstalled() {
  version=$1
  appimage_path="$DOWNLOADS_DIR/cursor-$version.AppImage"
  if [ ! -f "$appimage_path" ]; then
    echo "Version $version not found locally. Use \`cvm --list-local\` to list available versions."
    exit 1
  fi
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
  
  cat > "$DESKTOP_ENTRY_PATH" << EOF
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
  latestLocalVersion=$(getLatestLocalVersion)
  if [ "$latestRemoteVersion" != "$latestLocalVersion" ]; then
    downloadVersion "$latestRemoteVersion"
  fi
  selectVersion "$latestRemoteVersion"

  echo "Cursor $latestRemoteVersion installed and activated."
  
  # Setup assets and create desktop entry
  setupAssets
  createDesktopEntry
  
  echo "Adding alias to your shell config..."
  case "$(basename "$SHELL")" in
    sh|dash)
      if ! grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.profile"; then
        echo "alias cursor='$CURSOR_DIR/active'" >> "$HOME/.profile"
      fi
      ;;
    bash)
      if ! grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.bashrc"; then
        echo "alias cursor='$CURSOR_DIR/active'" >> "$HOME/.bashrc"
      fi
      ;;
    zsh)
      if ! grep -q "alias cursor='$CURSOR_DIR/active'" "$HOME/.zshrc"; then
        echo "alias cursor='$CURSOR_DIR/active'" >> "$HOME/.zshrc"
      fi
      ;;
    fish)
      if [ ! -f "$HOME/.config/fish/functions/cursor.fish" ] || ! grep -q "function cursor" "$HOME/.config/fish/functions/cursor.fish"; then
        mkdir -p "$HOME/.config/fish/functions"
        {
          echo "function cursor"
          echo "    nohup $CURSOR_DIR/active \$argv --no-sandbox </dev/null >/dev/null 2>&1 &"
          echo "    disown"
          echo "end"
        } > "$HOME/.config/fish/functions/cursor.fish"
      fi
      ;;
  esac
  echo "Alias added. You can now use 'cursor' to run Cursor."
  case "$(basename "$SHELL")" in
    sh|dash)
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

uninstallCVM() {
  rm -rf "$CURSOR_DIR"
  
  # Remove desktop entry
  if [ -f "$DESKTOP_ENTRY_PATH" ]; then
    rm "$DESKTOP_ENTRY_PATH"
    echo "Desktop entry removed from $DESKTOP_ENTRY_PATH"
  fi
  
  case "$(basename "$SHELL")" in
    sh|dash)
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
  for program in sed grep jq find wget; do
    if ! command -v "$program" >/dev/null 2>&1; then
      echo "Error: $program is not installed." >&2
      exit 1
    fi
  done
}

isShellSupported() {
  case "$(basename "$SHELL")" in
    sh|dash|bash|zsh|fish)
      return 0
      ;;
    *)
      return 1
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
    wget -O- "$GITHUB_API_URL" \
      | jq -r '.assets[] | select(.name == "cvm.sh") | .browser_download_url'
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
mkdir -p "$ASSETS_DIR"
cleanupAppImages

# Show ASCII art and help when no arguments are provided
if [ $# -eq 0 ]; then
  help
  exit 0
fi

case "$1" in
  --help|-h)
    help
    ;;
  --version|-v)
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
    latestRemoteVersion=$(getLatestRemoteVersion)
    if [ -d "$DOWNLOADS_DIR" ] && [ -n "$(ls -A "$DOWNLOADS_DIR" 2>/dev/null)" ]; then
      latestLocalVersion=$(getLatestLocalVersion)
      activeVersion=$(getActiveVersion 2>/dev/null || echo "None")
      echo "  - Latest remote version: $latestRemoteVersion"
      echo "  - Latest locally available: $latestLocalVersion"
      echo "  - Currently active: $activeVersion"

      if [ "$latestRemoteVersion" != "$latestLocalVersion" ]; then
        print_color "$ORANGE" "There is a newer Cursor version available for download!"
        print_color "$ORANGE" "You can download and activate it with \`cvm --update\`"
      elif [ "$latestRemoteVersion" != "$activeVersion" ]; then
        print_color "$ORANGE" "There is a newer Cursor version already installed!"
        print_color "$ORANGE" "You can activate it with \`cvm --use $latestRemoteVersion\`"
      else
        print_color "$GREEN" "You are running the latest Cursor version!"
      fi
    else
      echo "  - Latest remote version: $latestRemoteVersion"
      echo "  - No local Cursor installation found"
      print_color "$ORANGE" "To install Cursor, run: $0 --install"
    fi
    ;;
  --update)
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

    localFileForLatest="$DOWNLOADS_DIR/cursor-$latestRemoteVersion.AppImage"
    if [ -f "$localFileForLatest" ]; then
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
  --list-local)
    # shellcheck disable=SC2010
    local_versions_list=$(ls -1 "$DOWNLOADS_DIR" 2>/dev/null | grep -oP 'cursor-\K[0-9.]+(?=\.)' || true)
    if [ -n "$local_versions_list" ]; then
      echo "Locally available versions:"
      while IFS= read -r version; do
        echo "  - $version"
      done <<< "$local_versions_list"
    else
      echo "  No versions installed."
    fi
    ;;
  --list-remote)
    echo "Remote versions:"
    while IFS= read -r version; do
      echo "  - $version"
    done < <(getRemoteVersions)
    ;;
  --download)
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
    if [ -f "$DOWNLOADS_DIR/cursor-$version.AppImage" ]; then
      echo "Version $version already downloaded."
    else
      downloadVersion "$version"
    fi
    echo "To select the downloaded version, run \`cvm --use $version\`"
    ;;
  --active)
    getActiveVersion
    ;;
  --use)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 --use <version>"
      exit 1
    fi

    version=$2
    exitIfVersionNotInstalled "$version"
    selectVersion "$version"
    ;;
  --remove)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 --remove <version1> <version2> <version3>..."
      exit 1
    fi

    shift # Skip the --remove argument
    versions=("$@")
    
    for version in "${versions[@]}"; do
      # Check if version is installed
      if [ ! -f "$DOWNLOADS_DIR/cursor-$version.AppImage" ]; then
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

      # Remove the AppImage file
      echo "Removing AppImage for version $version..."
      if rm "$DOWNLOADS_DIR/cursor-$version.AppImage"; then
        print_color "$GREEN" "✓ Successfully removed version $version"
      else
        print_color "$ORANGE" "! Failed to remove version $version"
      fi
    done

    # Post-remove guidance
    if [ ! -L "$CURSOR_DIR/active" ]; then
      if [ -n "$(ls -A "$DOWNLOADS_DIR" 2>/dev/null)" ]; then
        echo "No active version selected. To activate one, run: $0 --use <version> (see \`$0 --list-local\`)."
      else
        echo "No Cursor versions installed."
      fi
    fi
    ;;
  --install)
    installCVM
    ;;
  --uninstall)
    uninstallCVM
    ;;
  --update-script)
    updateScript
    ;;
  *)
    echo "Unknown command: $1"
    help
    exit 1
    ;;
esac