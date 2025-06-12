#!/bin/bash

cd "$(dirname "$0")"

# Generate module index
echo "Generating module index..."
module_files=$(find module -name "*.lua" -type f -print0 | sort -z | tr '\0' '\n')
echo "[" > module-index.json
first=true
for file in $module_files; do
  if [ "$first" = true ]; then
    first=false
  else
    echo "," >> module-index.json
  fi
  filename=$(basename "$file")
  # Extract metadata from the Lua file
  name=$(grep -m1 "^name = " "$file" 2>/dev/null | sed 's/name = "\(.*\)"/\1/' | sed "s/name = '\(.*\)'/\1/")
  description=$(grep -m1 "^description = " "$file" 2>/dev/null | sed 's/description = "\(.*\)"/\1/' | sed "s/description = '\(.*\)'/\1/")
  author=$(grep -m1 "^author = " "$file" 2>/dev/null | sed 's/author = "\(.*\)"/\1/' | sed "s/author = '\(.*\)'/\1/")
  version=$(grep -m1 "^version = " "$file" 2>/dev/null | sed 's/version = "\(.*\)"/\1/' | sed "s/version = '\(.*\)'/\1/")
  
  # Use filename as fallback for name
  if [ -z "$name" ]; then
    name="${filename%.lua}"
  fi
  if [ -z "$version" ]; then
    version="1.0.0"
  fi
  
  echo -n "  {" >> module-index.json
  echo -n "\"filename\": \"$filename\", " >> module-index.json
  echo -n "\"name\": \"$name\", " >> module-index.json
  echo -n "\"description\": \"$description\", " >> module-index.json
  echo -n "\"author\": \"$author\", " >> module-index.json
  echo -n "\"version\": \"$version\", " >> module-index.json
  echo -n "\"type\": \"module\", " >> module-index.json
  echo -n "\"path\": \"$file\"" >> module-index.json
  echo -n "}" >> module-index.json
done
echo "" >> module-index.json
echo "]" >> module-index.json

# Generate command index
echo "Generating command index..."
command_files=$(find command -name "*.lua" -type f -print0 | sort -z | tr '\0' '\n')
echo "[" > command-index.json
first=true
for file in $command_files; do
  if [ "$first" = true ]; then
    first=false
  else
    echo "," >> command-index.json
  fi
  filename=$(basename "$file")
  # Extract metadata from the Lua file
  name=$(grep -m1 "^name = " "$file" 2>/dev/null | sed 's/name = "\(.*\)"/\1/' | sed "s/name = '\(.*\)'/\1/")
  description=$(grep -m1 "^description = " "$file" 2>/dev/null | sed 's/description = "\(.*\)"/\1/' | sed "s/description = '\(.*\)'/\1/")
  author=$(grep -m1 "^author = " "$file" 2>/dev/null | sed 's/author = "\(.*\)"/\1/' | sed "s/author = '\(.*\)'/\1/")
  version=$(grep -m1 "^version = " "$file" 2>/dev/null | sed 's/version = "\(.*\)"/\1/' | sed "s/version = '\(.*\)'/\1/")
  
  # Use filename as fallback for name
  if [ -z "$name" ]; then
    name="${filename%.lua}"
  fi
  if [ -z "$version" ]; then
    version="1.0.0"
  fi
  
  echo -n "  {" >> command-index.json
  echo -n "\"filename\": \"$filename\", " >> command-index.json
  echo -n "\"name\": \"$name\", " >> command-index.json
  echo -n "\"description\": \"$description\", " >> command-index.json
  echo -n "\"author\": \"$author\", " >> command-index.json
  echo -n "\"version\": \"$version\", " >> command-index.json
  echo -n "\"type\": \"command\", " >> command-index.json
  echo -n "\"path\": \"$file\"" >> command-index.json
  echo -n "}" >> command-index.json
done
echo "" >> command-index.json
echo "]" >> command-index.json

echo "Generated indices:"
echo "Module scripts: $(cat module-index.json | grep -c '"filename"')"
echo "Command scripts: $(cat command-index.json | grep -c '"filename"')"