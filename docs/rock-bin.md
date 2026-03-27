ROCK-BIN(1) - General Commands Manual

# NAME

**rock-bin** - Lua environment and package manager

# SYNOPSIS

**rock-bin**
\[*command*]
\[*arguments*]

# DESCRIPTION

**rock-bin**
is a command-line interface tool for managing Lua environments and packages.
It allows users to manage Lua versions, project dependencies, and execute project-defined scripts.

# ENVIRONMENT COMMANDS

**about**

> Show details about current stack (Lua, LuaRocks, Rock).

**update**

> Sync versions from lua.org and LuaRocks GitHub.

**upgrade-rocks**

> Upgrade internal LuaRocks to the latest version.

**implode**

> Uninstall Rock and remove all managed files.

# VERSION MANAGEMENT

**install** *v*

> Download and compile a specific Lua version.

> > $ rock install 5.4.7

**use** *v*

> Switch Lua version (Rock or System).

> > $ rock use 5.4.7

**list**

> List installed and available Lua versions.

# PROJECT MANAGEMENT

**init**

> Create a new rock.toml project file.

**save** *p* \[*@ver*]

> Install and record a dependency (supports @^1.2).

> > $ rock save my-package@1.0

**save-dev** *p* \[*@ver*]

> Install and record a dev-dependency.

> > $ rock save-dev my-dev-package@latest

**remove** *p*

> Uninstall a package and remove from rock.toml.

> > $ rock remove my-package

**restore**

> Install all dependencies from rock.lock/toml.

**run** *s*

> Run a script defined in rock.toml.

> > $ rock init && rock run start

**path**

> Show environment exports for the local project.

# GLOBAL OPTIONS

**-h**, **--help**

> Show this informative screen.

**--version**, **-v**

> Show current rock CLI version.

# EXAMPLES

	$ rock update && rock upgrade-rocks

	$ rock install 5.4.7

	$ rock use 5.4.7

	$ rock init && rock run start

# SEE ALSO

luarocks(1),
lua(1)

rock 0.1.5 - March 26, 2026
