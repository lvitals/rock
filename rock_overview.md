# Rock CLI Overview

Rock is a command-line interface tool that functions as a Lua environment and package manager. It allows users to manage Lua versions, project dependencies, and execute project-defined scripts efficiently.

## Usage

`rock <command> [arguments]`

## Environment Commands

*   **about**: Show details about the current stack (Lua, LuaRocks, Rock).
*   **update**: Synchronize versions from lua.org and LuaRocks GitHub.
*   **upgrade-rocks**: Upgrade the internal LuaRocks to its latest version.
*   **implode**: Uninstall Rock and remove all associated managed files.

## Version Management

*   **list**: List all installed and available Lua versions.
*   **install <v>**: Download and compile a specific Lua version (e.g., `rock install 5.4.7`).
*   **use <v>**: Switch the active Lua version (either Rock-managed or System-wide).

## Project Management

*   **init**: Create a new `rock.toml` project configuration file.
*   **save <p>[@ver]**: Install a package and record it as a dependency in `rock.toml`. Supports version specifications like `@^1.2`.
*   **save-dev <p>[@ver]**: Install a package and record it as a development dependency.
*   **remove <p>**: Uninstall a package and remove its entry from `rock.toml`.
*   **restore**: Install all dependencies listed in `rock.lock` or `rock.toml`.
*   **run <s>**: Execute a script defined within the `rock.toml` file.
*   **path**: Display environment exports relevant to the local project.

## Global Options

*   **help, --help, -h**: Show this informative screen.
*   **--version, -v**: Display the current Rock CLI version.

## Examples

```bash
# Update Rock and upgrade internal LuaRocks
$ rock update && rock upgrade-rocks

# Install a specific Lua version
$ rock install 5.4.7

# Switch to using Lua version 5.4.7
$ rock use 5.4.7

# Initialize a new project and run a start script
$ rock init && rock run start
```