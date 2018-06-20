#!/bin/sh

# Script to untar a directory structure
#
# Usage:
#
# ./untar_recursive.sh archived_dir.tar
#

# Get tar file and name of directory where it's being extracted
target_tar="$(readlink --canonicalize $1)"
target_dir="$(readlink --canonicalize `tar -tf $1 | head -1 | cut -f1 -d"/"`)"

# Untar top-level
tar xf $target_tar

# Loop over directory structure
# If there's a tar file, we untar it in place and then delete the tar file
# This may be slow on large directories/file counts, as it has to run multiple
# find commands to completion.
# The PATH modification step removes . from PATH (the current working directory,
# as it raises an error with the -execdir option in find
PATH="$(echo "$PATH" | sed -e 's/:.:/:/')"
while true; do
  find $target_dir -type f -name "*.tar" -execdir tar xf '{}' ';' -delete
  if [ -z "$(find $target_dir -type f -name "*.tar")" ]; then
    break
  fi
done
