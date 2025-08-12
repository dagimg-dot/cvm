# CVM (Cursor Version Manager)

A single-file Bash utility for managing and switching between multiple [Cursor](https://www.cursor.com/) versions with ease.

**Built for linux users that use the AppImage distribution of Cursor.**

## Features

- Download and manage multiple versions of Cursor
- Select the version you want to use
- Remove a version

### Installation

#### Option 1: Install with [eget](https://github.com/zyedidia/eget)

```bash
eget dagimg-dot/cvm --to $HOME/.local/bin
```

#### Option 2: Install system-wide (recommended)

> $HOME/.local/bin/cvm should be in your PATH

```bash
curl -L -o $HOME/.local/bin/cvm https://github.com/dagimg-dot/cvm/releases/download/v1.1.0/cvm.sh
chmod +x $HOME/.local/bin/cvm
```

#### Option 3: Use it as a local **script**

```bash
curl -L -o cvm.sh https://github.com/dagimg-dot/cvm/releases/download/v1.1.0/cvm.sh
chmod +x cvm.sh
```

#### Download cursor and add an alias to it
```bash
# system-wide
cvm --install
# local script
./cvm.sh --install
```

### Usage
```
cvm.sh — Cursor version manager

Examples:
  cvm --version
  cvm --list-local
  cvm --use 1.4.4
  cvm --remove 1.2.3 1.3.0 1.4.0

Notice*:
  The AppImage files are downloaded from the official Cursor releases.
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

> [!NOTE]
> Forked and improved from [ivstiv/cursor-version-manager](https://github.com/ivstiv/cursor-version-manager)