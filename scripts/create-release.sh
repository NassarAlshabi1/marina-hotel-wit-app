#!/bin/bash
set -euo pipefail

echo "Marina Hotel Mobile - Release Creator"

HAS_GH=true
command -v gh >/dev/null 2>&1 || HAS_GH=false

VERSION=""
NOTES_FILE=""
AUTO_YES=false

usage() {
  echo "Usage: $0 [-v vX.Y.Z] [-n notes.md] [-y]"
}

while getopts ":v:n:yh" opt; do
  case $opt in
    v) VERSION="$OPTARG" ;;
    n) NOTES_FILE="$OPTARG" ;;
    y) AUTO_YES=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "git not found"
  exit 1
fi

if [ -z "$VERSION" ]; then
  echo "Current pubspec version:" $(grep '^version:' mobile/pubspec.yaml | awk '{print $2}')
  read -rp "Enter release tag (e.g. v1.0.1): " VERSION
fi

if [[ ! $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid tag format"
  exit 1
fi

if git tag -l | grep -q "^${VERSION}$"; then
  echo "Tag already exists: $VERSION"
  exit 1
fi

if [ "$AUTO_YES" = false ]; then
  echo "Tag: $VERSION"
  read -rp "Continue? (y/N): " CONF
  [[ "$CONF" =~ ^[Yy]$ ]] || { echo "Canceled"; exit 1; }
fi

MSG="Marina Hotel Mobile ${VERSION}"
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  git tag -a "$VERSION" -F "$NOTES_FILE"
else
  git tag -a "$VERSION" -m "$MSG"
fi

git push origin "$VERSION"

echo "Tag pushed: $VERSION"

echo "Release build will run on GitHub Actions (release-apk.yml)."

if [ "$HAS_GH" = true ]; then
  echo "Actions: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/actions"
  echo "Releases: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/releases"
fi
