# Flarial User Scripting

This repository contains user-created scripts for Flarial. Follow these guidelines to contribute your own scripts. You can find the official documentation to make your own script [here](https://scripting.flarial.xyz/)

# Make your script public
## Directory Structure

Each script must be categorized into one of the following two directories, based on its actual function:

- `Module` - Scripts that show up as actual modules on the scripting tab
- `Command`- Script that add a prefix command

Examples:
```
scripts/
  └── Module/
      └── ScriptName.lua
```
or

```
scripts/
  └── Command/
      └── ScriptName.lua
```

### ScriptExample.lua Format

```lua
name = "Name of your script"
description = "Detailed discription of what your script is."
author = "Author of the script aka you!"

// Actual code of your script
```

## Submission Process

1. Create your script following the above guidelines
2. Ensure all files are properly formatted
3. Create a pull request with your script
4. Your script will be reviewed, and if everything is in order, it will be added to the repository and made available for the community to download.

For questions or support, please refer to the main Flarial documentation or community channels.