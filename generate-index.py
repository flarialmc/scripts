#!/usr/bin/env python3
import os
import json
import re
from pathlib import Path

def extract_metadata(file_path):
    """Extract metadata from a Lua script file."""
    metadata = {
        'name': '',
        'description': '',
        'author': '',
        'version': '1.0.0'
    }
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Extract metadata using regex
        patterns = {
            'name': r'^name\s*=\s*["\']([^"\']*)["\']',
            'description': r'^description\s*=\s*["\']([^"\']*)["\']',
            'author': r'^author\s*=\s*["\']([^"\']*)["\']',
            'version': r'^version\s*=\s*["\']([^"\']*)["\']'
        }
        
        for key, pattern in patterns.items():
            match = re.search(pattern, content, re.MULTILINE)
            if match:
                metadata[key] = match.group(1)
    
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
    
    return metadata

def generate_index(script_type):
    """Generate index for module or command scripts."""
    script_dir = Path(script_type)
    if not script_dir.exists():
        print(f"Directory {script_type} does not exist")
        return []
    
    scripts = []
    for lua_file in script_dir.glob('*.lua'):
        metadata = extract_metadata(lua_file)
        
        # Use filename as fallback for name
        if not metadata['name']:
            metadata['name'] = lua_file.stem
        
        script_entry = {
            'filename': lua_file.name,
            'name': metadata['name'],
            'description': metadata['description'],
            'author': metadata['author'],
            'version': metadata['version'],
            'type': script_type,
            'path': str(lua_file)
        }
        scripts.append(script_entry)
    
    # Sort by filename
    scripts.sort(key=lambda x: x['filename'])
    return scripts

def main():
    # Change to script directory
    os.chdir(Path(__file__).parent)
    
    # Generate module index
    print("Generating module index...")
    module_scripts = generate_index('module')
    with open('module-index.json', 'w', encoding='utf-8') as f:
        json.dump(module_scripts, f, indent=2, ensure_ascii=False)
    
    # Generate command index
    print("Generating command index...")
    command_scripts = generate_index('command')
    with open('command-index.json', 'w', encoding='utf-8') as f:
        json.dump(command_scripts, f, indent=2, ensure_ascii=False)
    
    print(f"Generated indices:")
    print(f"Module scripts: {len(module_scripts)}")
    print(f"Command scripts: {len(command_scripts)}")

if __name__ == '__main__':
    main()