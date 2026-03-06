# Rock

A modern Lua environment and package manager, inspired by `npm`, `nvm`, and `pyenv`.

## Features

- **Dependency Management**: NPM-style versioning (`^`, `~`) with `rock.toml`.
- **Security & Reproducibility**: Deterministic installs using `rock.lock`.
- **Script Runner**: Run custom commands and pipelines with `rock run`.
- **Auto-Environment**: Automatic configuration of `LUA_PATH` and `LUA_CPATH` for your project.
- **Zero-Dependency Install**: Self-contained installer that bootstraps its own Lua engine.

## Installation

You can install Rock using `curl` or `wget`. The installer will bootstrap a local Lua environment and configure your shell profile.

### Using cURL
```bash
curl -s https://raw.githubusercontent.com/lvitals/rock/main/scripts/install.sh | bash
```

### Using Wget
```bash
wget -qO- https://raw.githubusercontent.com/lvitals/rock/main/scripts/install.sh | bash
```

## Quick Start

```bash
# Initialize a new project
rock init

# Install a dependency
rock save dkjson@^2.1

# Install a dependency with custom compilation flags (e.g., database drivers)
rock save rio MYSQL_INCDIR=/usr/include/mysql

# Install a development dependency
rock save-dev busted

# Run a script defined in rock.toml
rock run test

## Configuration

Rock can be configured per-project using a `.rockrc` file. This file stores build flags for specific packages and global project settings.

### Custom Modules Path
By default, Rock installs dependencies into `lua_modules`. You can change this (e.g., to `vendor`) using:

```bash
rock config modules_path vendor
```

After changing this, run `rock install` to reinstall dependencies into the new directory.

### Build Flags
When you install a package with extra flags (like `MYSQL_INCDIR`), Rock automatically saves them to `.rockrc` so subsequent `rock install` calls on other machines will use the same flags.

## License

MIT
MIT
