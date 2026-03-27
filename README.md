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
```

## Lua Version Management

Rock provides robust tools for managing different Lua interpreter versions.

### `rock list`

This command displays all Lua interpreter versions currently installed and managed by Rock on your system. It also shows a list of available Lua versions that can be installed from official sources, making it easy to see which environments are ready for use or can be added to your setup.

### `rock install <version>`

Use this command to download, compile, and integrate a specific Lua interpreter version into Rock's management system. For example, `rock install 5.4.7` will set up Lua 5.4.7. This ensures a consistent and isolated Lua environment, preventing conflicts between projects that might require different Lua versions.

### `rock use <version>`

This command allows you to switch the actively used Lua interpreter version for your current shell session or project. You can choose between Lua versions managed by Rock or system-wide installed Lua environments. This flexibility is crucial for developing and testing projects that have specific Lua version requirements, ensuring compatibility and correct execution.

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

Rock is released under the [MIT License](LICENSE).