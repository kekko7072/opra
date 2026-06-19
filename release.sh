#!/usr/bin/env bash
#
# release.sh — cut a macOS release.
#
# Prompts for the new version (and build) number, bumps MARKETING_VERSION /
# CURRENT_PROJECT_VERSION in the Xcode project, commits the bump, and pushes to `main`.
# Pushing to `main` triggers the "Build and Release" GitHub Actions workflow, which
# builds, code-signs, notarizes, and publishes the .dmg / .app.zip as a GitHub Release
# tagged v<version>-build<build>.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PBXPROJ="$REPO_ROOT/macos/Opra.xcodeproj/project.pbxproj"
BRANCH="main"

cd "$REPO_ROOT"

# --- sanity checks ---
command -v git >/dev/null 2>&1 || { echo "error: git not found on PATH"; exit 1; }
[ -f "$PBXPROJ" ] || { echo "error: cannot find $PBXPROJ"; exit 1; }

current_version="$(grep -m1 -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ" | sed 's/MARKETING_VERSION = //')"
current_build="$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [^;]*' "$PBXPROJ" | sed 's/CURRENT_PROJECT_VERSION = //')"

echo "Current release: ${current_version} (build ${current_build})"
echo

# Warn (don't block) if there are unrelated uncommitted changes — they won't be released.
if [ -n "$(git status --porcelain)" ]; then
  echo "⚠️  Working tree has uncommitted changes. Only the version bump will be committed;"
  echo "    anything else stays local and will NOT be part of this release:"
  git status --short | sed 's/^/      /'
  echo
fi

# --- prompt for the new version / build ---
read -r -p "New release version [${current_version}]: " new_version
new_version="${new_version:-$current_version}"

default_build=$(( current_build + 1 ))
read -r -p "New build number [${default_build}]: " new_build
new_build="${new_build:-$default_build}"

# --- validate ---
if ! [[ "$new_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "error: version '${new_version}' should look like X.Y or X.Y.Z"; exit 1
fi
if ! [[ "$new_build" =~ ^[0-9]+$ ]]; then
  echo "error: build number '${new_build}' must be an integer"; exit 1
fi

tag="v${new_version}-build${new_build}"
echo
echo "About to release ${new_version} (build ${new_build})  →  tag ${tag}"
echo "This commits the version bump and pushes to '${BRANCH}', triggering the release workflow."
read -r -p "Continue? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# --- confirm branch ---
cur_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$cur_branch" != "$BRANCH" ]; then
  read -r -p "You're on '${cur_branch}', not '${BRANCH}'. Push HEAD to '${BRANCH}' anyway? [y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# --- apply version bump to every build config ---
sed -i '' \
  -e "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = ${new_version}/g" \
  -e "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = ${new_build}/g" \
  "$PBXPROJ"

echo "Bumped project to ${new_version} (build ${new_build})."

# --- commit & push (only the version bump) ---
git add "$PBXPROJ"
git commit -m "Release ${new_version} (build ${new_build})"
git push origin "HEAD:${BRANCH}"

echo
echo "✅ Pushed. The 'Build and Release' workflow will publish release ${tag}."
echo "   Track it at: https://github.com/kekko7072/Opra/actions"
