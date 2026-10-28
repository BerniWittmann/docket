#!/bin/zsh
# Prints the next semantic version from the Conventional Commits since the last v* tag,
# and whether those commits warrant a release:
#   feat!: or BREAKING CHANGE → major, feat: → minor, fix: or perf: → patch, anything else → no release.
# Output (GitHub Actions friendly): version=1.2.3 and release=true|false
set -euo pipefail
cd "${0:A:h}/.."

last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)
range=$([[ $last == v0.0.0 ]] && echo HEAD || echo "$last..HEAD")
subjects=$(git log "$range" --format=%s)
bodies=$(git log "$range" --format=%b)

IFS=. read -r major minor patch <<< "${last#v}"
release=true
if grep -qE '^[a-z]+(\([^)]*\))?!:' <<< "$subjects" || grep -q 'BREAKING CHANGE' <<< "$bodies"; then
  major=$((major + 1)); minor=0; patch=0
elif grep -qE '^feat(\([^)]*\))?:' <<< "$subjects"; then
  minor=$((minor + 1)); patch=0
elif grep -qE '^(fix|perf)(\([^)]*\))?:' <<< "$subjects"; then
  patch=$((patch + 1))
else
  release=false
fi

echo "version=$major.$minor.$patch"
echo "release=$release"
