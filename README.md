# CVM (Cursor Version Manager) 🚀

A powerful, single-file Bash utility for managing and switching between multiple [Cursor](https://www.cursor.com/) versions with ease. Supports **AppImage**, **RPM**, and **DEB** packages with automatic system detection.

<div align="center">
  <img src="assets/cursor.png" width="200" height="200">
</div>

## ✨ Features

- 🔄 **Multi-Package Support**: AppImage, RPM, and DEB packages
- 🔍 **Smart System Detection**: Automatically chooses the best package type for your system
- 📁 **Organized Storage**: Separate directories for each package type
- ⚡ **Live Package Switching**: Switch between AppImage ↔ RPM ↔ DEB seamlessly
- 🖥️ **Desktop Integration**: Automatic .desktop file creation and management
- 🐚 **Shell Integration**: Package-type specific aliases for optimal performance
- 📊 **Rich Version Info**: Detailed version and package type information
- 🌍 **Cross-Distribution**: Works on Ubuntu, Fedora, CentOS, Debian, and more

## 📦 Package Type Support

| Package Type | Best For           | Special Features                         |
| ------------ | ------------------ | ---------------------------------------- |
| **AppImage** | Universal          | Sandbox mode, portable, works everywhere |
| **RPM**      | Fedora/RHEL/CentOS | Native system integration, auto-updates  |
| **DEB**      | Ubuntu/Debian      | Native system integration, repositories  |

## 🚀 Installation

### Option 1: Install with [eget](https://github.com/zyedidia/eget) (Recommended)

```bash
eget dagimg-dot/cvm --to $HOME/.local/bin
```

### Option 2: Direct Download

```bash
# Download and install to local bin
curl -L -o $HOME/.local/bin/cvm https://github.com/dagimg-dot/cvm/releases/download/v1.2.2/cvm.sh
chmod +x $HOME/.local/bin/cvm

# Ensure ~/.local/bin is in your PATH
```

### Option 3: Use as Local Script

```bash
curl -L -o cvm.sh https://github.com/dagimg-dot/cvm/releases/download/v1.2.2/cvm.sh
chmod +x cvm.sh

./cvm.sh --help
```

## 📖 Usage

```
cvm.sh — Cursor version manager

 ██████╗██╗   ██╗███╗   ███╗
██╔════╝██║   ██║████╗ ████║
██║     ██║   ██║██╔████╔██║
██║     ╚██╗ ██╔╝██║╚██╔╝██║
╚██████╗ ╚████╔╝ ██║ ╚═╝ ██║
 ╚═════╝  ╚═══╝  ╚═╝     ╚═╝

Examples:
  cvm --version
  cvm --list-local
  cvm --use 1.4.4
  cvm --remove 1.2.3 1.3.0 1.4.0

Notice*:
  Packages are downloaded from the official Cursor releases.
  Package type is auto-detected (deb/rpm/appimage) or can be set with CVM_PACKAGE_TYPE.
  The list of download sources can be found at https://github.com/oslook/cursor-ai-downloads

Options:
  --list-local         Lists locally available versions
  --list-remote        Lists versions available for download
  --download <version> Downloads a version
  --update             Downloads and selects the latest version
  --use <version>      Selects a locally available version
  --active             Shows the currently selected version
  --remove <version...>  Removes one or more locally available versions
  --install            Adds an alias `cursor` and downloads the latest version
  --uninstall          Removes the Cursor version manager directory and alias
  --update-script      Updates the (cvm.sh) script to the latest version
  -v --version         Shows the current and latest versions for cvm.sh and Cursor
  -h --help            Shows this message
```

## 🎯 Quick Start

```bash
# Install CVM and download latest Cursor version
cvm --install

# List available versions to download
cvm --list-remote

# Download a specific version
cvm --download 1.7.39

# Switch to a version
cvm --use 1.7.39

# Check what's currently active
cvm --active

# Update to latest version
cvm --update
```

## 🔧 Advanced Configuration

### Environment Variables

| Variable           | Description                                            | Default       |
| ------------------ | ------------------------------------------------------ | ------------- |
| `CVM_PACKAGE_TYPE` | Force specific package type (`appimage`, `rpm`, `deb`) | Auto-detected |

```bash
# Force AppImage even on RPM-based systems
CVM_PACKAGE_TYPE=appimage cvm --install

# Use RPM packages explicitly
CVM_PACKAGE_TYPE=rpm cvm --download 1.7.39
```

### Directory Structure

CVM organizes packages in separate directories:

```
~/.local/share/cvm/
├── app-images/     # AppImage files
├── rpms/          # RPM files + extracted directories
├── debs/          # DEB files + extracted directories
├── assets/        # Icons and assets
└── active         # Symlink to active version
```

### Shell Integration

CVM automatically configures shell aliases based on package type:

- **AppImage**: Complex function with `--no-sandbox` flag for proper sandboxing
- **RPM/DEB**: Simple alias for native package execution

## 📊 Version Information

Get detailed information about your Cursor installation:

```bash
$ cvm --version
Cursor Version Manager (cvm.sh):
  - Current version: 1.2.0
  - Latest version: 1.2.0 ✓

Cursor App Information:
  - Package type: rpm
  - Latest remote version: 1.7.39
  - Latest locally available: 1.7.39
  - Currently active: 1.7.39 (rpm)
```

## 🐛 Troubleshooting

### Common Issues

**Package type detection wrong?**
```bash
# Override auto-detection
CVM_PACKAGE_TYPE=rpm cvm --install
```

**Permission issues with RPM/DEB?**
```bash
# Use sudo for system packages if needed
sudo cvm --install
```

**Desktop entry not working?**
```bash
# Recreate desktop entry
cvm --install
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Original Project**: Forked and improved from [ivstiv/cursor-version-manager](https://github.com/ivstiv/cursor-version-manager)
- **Cursor Team**: For creating an amazing code editor
---

<div align="center">

**Made with ❤️ for the Cursor community on Linux**

[⭐ Star us on GitHub](https://github.com/dagimg-dot/cvm) • [🐛 Report Issues](https://github.com/dagimg-dot/cvm/issues) • [💬 Discussions](https://github.com/dagimg-dot/cvm/discussions)

</div>