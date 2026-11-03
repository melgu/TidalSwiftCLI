#!/bin/zsh
# Prepares a release: sets the version in the code, builds and checks it, then commits and tags.
#
# Usage: ./release.sh <version>, e.g. ./release.sh 1.1.0
# Run it on main with a clean working copy. It doesn't push; push main and the tag afterwards.

set -euo pipefail
cd "$(dirname "$0")"

fail() {
	echo "$1" >&2
	exit 1
}

version=${1:-}
[[ $version =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "Usage: $0 <version>, e.g. $0 1.1.0"

[[ $(git branch --show-current) == main ]] || fail "Releases are made from main."
[[ -z $(git status --porcelain) ]] || fail "Commit or stash the changes first."
! git rev-parse -q --verify "refs/tags/$version" >/dev/null || fail "Tag $version exists already."
# A released version has to build for everyone, which a dependency on a local folder doesn't
! grep -q '\.package(path:' Package.swift || fail "Package.swift depends on a local package. Point it to the release first."

# The version is compiled in, as the binary can't read it from git
version_file=Sources/tidal/Tidal.swift
# Undo the change if anything before the commit fails
trap 'git checkout -- "$version_file"' EXIT
sed -i '' -E "s/^let toolVersion = \".*\"$/let toolVersion = \"$version\"/" "$version_file"
grep -qx "let toolVersion = \"$version\"" "$version_file" || fail "Couldn't set the version in $version_file."

./build.sh release
built=$(.build/release/tidal --version)
[[ $built == $version ]] || fail "The build reports version $built instead of $version."
trap - EXIT

if ! git diff --quiet; then
	git commit -q -m "Bump version to $version" -- "$version_file"
fi
git tag -a "$version" -m "$version"
echo "Tagged $version. Push with: git push origin main $version"
