#!/bin/sh

set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backup_base="$repo_dir/backup"
timestamp=$(date '+%Y%m%d-%H%M%S')
backup_dir="$backup_base/$timestamp"

suffix=0
while [ -e "$backup_dir" ]; do
  suffix=$((suffix + 1))
  backup_dir="$backup_base/$timestamp-$suffix"
done

mkdir -p "$backup_base"

backup_existing() {
  destination=$1
  relative_path=$2

  if [ -e "$destination" ] || [ -L "$destination" ]; then
    backup_path="$backup_dir/$relative_path"
    mkdir -p "$(dirname -- "$backup_path")"
    mv -- "$destination" "$backup_path"
    printf 'backup  %s -> %s\n' "$destination" "$backup_path"
  fi
}

install_directory() {
  relative_path=$1
  destination="$HOME/$relative_path"

  if [ -d "$destination" ] && [ ! -L "$destination" ]; then
    return
  fi

  backup_existing "$destination" "$relative_path"
  mkdir -p "$destination"
}

install_file() {
  source_file=$1
  relative_path=${source_file#"$repo_dir/"}
  destination="$HOME/$relative_path"

  backup_existing "$destination" "$relative_path"
  cp -p -- "$source_file" "$destination"
  printf 'install %s\n' "$destination"
}

# Add another top-level path here when this repository starts managing it.
for source_root in "$repo_dir/.config"; do
  [ -d "$source_root" ] || continue

  find "$source_root" -type d -print | while IFS= read -r source_directory; do
    relative_path=${source_directory#"$repo_dir/"}
    install_directory "$relative_path"
  done

  find "$source_root" -type f -print | while IFS= read -r source_file; do
    install_file "$source_file"
  done
done

if [ -d "$backup_dir" ]; then
  printf '\nBackup saved in %s\n' "$backup_dir"
else
  printf '\nNo existing files needed to be backed up.\n'
fi
