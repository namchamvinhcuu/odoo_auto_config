#!/bin/bash
set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version>"
  echo "Example: ./release.sh 1.1.0"
  exit 1
fi

# Validate semver format
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: Version must be semver (e.g., 1.1.0)"
  exit 1
fi

# Check clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: Working tree not clean. Commit or stash changes first."
  exit 1
fi

# Check tag doesn't exist
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "Error: Tag v$VERSION already exists."
  exit 1
fi

PUBSPEC="pubspec.yaml"

# Bump version in pubspec.yaml
OLD_VERSION=$(grep '^version:' "$PUBSPEC" | head -1)
sed -i "s/^version: .*/version: $VERSION+1/" "$PUBSPEC"
echo "Updated $PUBSPEC: $OLD_VERSION → version: $VERSION+1"

# Update version.json
echo "{\"version\": \"$VERSION\"}" > assets/version.json
echo "Updated assets/version.json → $VERSION"

# Commit, tag, push
git add "$PUBSPEC" assets/version.json
git commit -m "release v$VERSION"
git tag "v$VERSION"
git push origin "$(git branch --show-current)" --tags

echo ""
echo "Done! v$VERSION pushed. GitHub Actions will build & release."
echo "Track: https://github.com/namchamvinhcuu/odoo_auto_config/actions"
