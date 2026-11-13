#!/bin/zsh
# Releases a new version: sets the version in the code, builds a universal binary and checks it,
# commits and tags, pushes, creates the GitHub release with the binary, and updates the Homebrew formula.
#
# Usage: ./release.sh <version> [--notes <file>], e.g. ./release.sh 1.1.0
#   --notes  Release notes in Markdown. Without it, the notes are written in the editor ($VISUAL,
#            $EDITOR or TextEdit), from a template listing the commits since the last release.
# Run it on main with a clean working copy. It needs gh, logged in, and a clone of melgu/homebrew-tap
# at ../homebrew-tap (or TIDAL_TAP_DIR), also on main and clean.

set -euo pipefail
cd "$(dirname "$0")"

fail() {
	echo "$1" >&2
	exit 1
}

usage="Usage: $0 <version> [--notes <file>], e.g. $0 1.1.0"
version=""
notes_input=""
while (( $# )); do
	case $1 in
		--notes)
			(( $# >= 2 )) || fail $usage
			notes_input=$2
			shift
			;;
		-*) fail $usage ;;
		*)
			[[ -z $version ]] || fail $usage
			version=$1
			;;
	esac
	shift
done
[[ $version =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail $usage
[[ -z $notes_input || -f $notes_input ]] || fail "No notes at $notes_input."
tap=${TIDAL_TAP_DIR:-../homebrew-tap}
formula=$tap/Formula/tidalswift-cli.rb

[[ $(git branch --show-current) == main ]] || fail "Releases are made from main."
[[ -z $(git status --porcelain) ]] || fail "Commit or stash the changes first."
git fetch -q origin
git merge-base --is-ancestor origin/main main || fail "main is behind origin/main. Pull first."
! git rev-parse -q --verify "refs/tags/$version" >/dev/null || fail "Tag $version exists already."
# A released version has to build for everyone, which a dependency on a local folder doesn't
! grep -q '\.package(path:' Package.swift || fail "Package.swift depends on a local package. Point it to the release first."
gh auth status >/dev/null 2>&1 || fail "Log in with gh auth login first."
[[ -f $formula ]] || fail "No formula at $formula. Clone melgu/homebrew-tap there or set TIDAL_TAP_DIR."
[[ $(git -C "$tap" branch --show-current) == main && -z $(git -C "$tap" status --porcelain) ]] || fail "The tap at $tap has to be on main and clean."
git -C "$tap" pull -q --ff-only

# Asked first, so leaving the editor without notes doesn't leave a half-made release behind
previous=$(git describe --tags --abbrev=0 2>/dev/null || true)
# Kept until the release is made, so a failed run continues with the notes written already
notes=${TMPDIR:-/tmp}/tidal-release-notes-$version.md
if [[ -n $notes_input ]]; then
	cp "$notes_input" "$notes"
else
	[[ -t 0 ]] || fail "Pass the release notes with --notes <file>, as there's no terminal for the editor."
	commits=$(git log --format='- %s' ${previous:+$previous..}HEAD)
	[[ -f $notes ]] && echo "Continuing with the notes from the last run." || cat >|$notes <<-EOF
	New
	-

	Improvements
	-

	Fixes
	-

	<!--
	Release notes for tidal $version, in Markdown, for people using the tool: what changed for them,
	not how. Delete the sections you don't need. This comment is left out.

	Commits since ${previous:-the first one}:
	$commits
	-->
	EOF
	editor=${VISUAL:-${EDITOR:-}}
	if [[ -n $editor ]]; then
		${=editor} "$notes"
	else
		echo "Quit TextEdit when you're done."
		open -W -t "$notes"
	fi
fi
body=$(perl -0pe 's/<!--.*?-->\n?//gs' "$notes")
# Template lines that weren't filled in
! grep -qxE -- '-[[:space:]]*' <<<"$body" || fail "The notes still have empty \"-\" lines. Fill them in or delete them. They're in $notes."
grep -q '[^[:space:]]' <<<"$body" || fail "The notes are empty."

# The version is compiled in, as the binary can't read it from git
version_file=Sources/tidal/Tidal.swift
# Undo the change if anything before the commit fails
trap 'git checkout -- "$version_file"' EXIT
sed -i '' -E "s/^let toolVersion = \".*\"$/let toolVersion = \"$version\"/" "$version_file"
grep -qx "let toolVersion = \"$version\"" "$version_file" || fail "Couldn't set the version in $version_file."

binary=$(./build.sh universal | tee /dev/stderr | tail -n 1)
built=$("$binary" --version)
[[ $built == $version ]] || fail "The build reports version $built instead of $version."
[[ $(lipo -archs "$binary") == *arm64* && $(lipo -archs "$binary") == *x86_64* ]] || fail "The build isn't universal."
trap - EXIT

# The archive Homebrew downloads, with the license the GPL asks to ship alongside
dist=.build/dist
archive=$dist/tidal-$version-macos.tar.gz
[[ ! -e $dist ]] || trash "$dist"
mkdir -p "$dist/tidal-$version"
cp "$binary" LICENSE README.md "$dist/tidal-$version/"
COPYFILE_DISABLE=1 tar -czf "$archive" -C "$dist" "tidal-$version"
checksum=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)

if ! git diff --quiet; then
	git commit -q -m "Bump version to $version" -- "$version_file"
fi
git tag -a "$version" -m "$version"
git push -q origin main "$version"

gh release create "$version" "$archive" --title "$version" --notes "$body" --verify-tag
trash "$notes"

sed -i '' -E \
	-e "s|download/[^/]+/tidal-[^/]+-macos\.tar\.gz|download/$version/tidal-$version-macos.tar.gz|" \
	-e "s|sha256 \"[0-9a-f]*\"|sha256 \"$checksum\"|" \
	"$formula"
grep -q "download/$version/tidal-$version-macos.tar.gz" "$formula" && grep -q "sha256 \"$checksum\"" "$formula" || fail "Couldn't update $formula."
git -C "$tap" commit -q -m "tidalswift-cli $version" -- Formula/tidalswift-cli.rb
git -C "$tap" push -q

echo "Released $version. Update with: brew upgrade tidalswift-cli"
