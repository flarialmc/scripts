# Flarial User Scripting

This repository contains user-created scripts for Flarial. Follow these guidelines to contribute your own scripts.

## Directory Structure

Each script must be in its own directory named with a UUID v4. The directory must contain:

- `main.json` - Script metadata and configuration
- `main.lua` (or other .lua file) - The actual script implementation

Example:
```
scripts/
  └── 06e549b6-5653-4ea7-92c9-a8cd14067806/
      ├── main.json
      └── main.lua
```

## Creating a New Script

1. Generate a UUID v4 for your script (you can use online tools or programming libraries)
2. Create a new directory with the UUID name
3. Create the required files as described below

### main.json Format

```json
{
    "id": "your-uuid-here",
    "name": "Script Name",
    "description": "A brief description of what your script does",
    "author": "Your Name",
    "version": "1.0.0",
    "main_class": "main.lua",
    "api_revision": 2,
    "createdAt": "2025-02-28T00:00:00Z",
    "updatedAt": "2025-03-03T00:00:00Z"
}
```

## Submission Process

1. Create your script following the above guidelines
2. Ensure all files are properly formatted
3. Submit your script through the appropriate channels

For questions or support, please refer to the main Flarial documentation or community channels.