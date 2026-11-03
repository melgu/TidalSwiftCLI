#!/bin/zsh
# Builds tidal and signs it with a development certificate. The Keychain remembers
# "Always Allow" by signing identity, so an ad hoc signed build would prompt after every build.
#
# Usage: ./build.sh [debug|release|universal|install]
# universal builds release for Apple silicon and Intel in one binary, as released.
# install builds release and copies it to /usr/local/bin, so it runs from any folder
# and later development builds don't change it. Set TIDAL_INSTALL_DIR for another folder.
# It also installs zsh completion to /usr/local/share/zsh/site-functions, or TIDAL_COMPLETION_DIR.
# Set TIDAL_CODESIGN_IDENTITY if there's more than one "Apple Development" certificate.

set -euo pipefail
cd "$(dirname "$0")"

mode=${1:-debug}
identity=${TIDAL_CODESIGN_IDENTITY:-Apple Development}

case $mode in
	debug|release) build=(-c "$mode") ;;
	universal) build=(-c release --arch arm64 --arch x86_64) ;;
	install) build=(-c release) ;;
	*) echo "Usage: $0 [debug|release|universal|install]" >&2; exit 64 ;;
esac

swift build "${build[@]}"
binary="$(swift build "${build[@]}" --show-bin-path)/tidal"
codesign --force --sign "$identity" --identifier de.melgu.TidalSwift.cli "$binary"

if [[ $mode == install ]]; then
	destination=${TIDAL_INSTALL_DIR:-/usr/local/bin}
	# Copied rather than linked, keeping the signature. Overwriting the file in place would make macOS
	# kill it at launch, as it caches the signature per file, and break running MCP servers.
	# A new file moved over the old one avoids both.
	cp "$binary" "$destination/.tidal.new"
	mv -f "$destination/.tidal.new" "$destination/tidal"
	echo "$destination/tidal"

	# Completion for commands, options and their values, regenerated so it matches this build
	completions=${TIDAL_COMPLETION_DIR:-/usr/local/share/zsh/site-functions}
	if [[ -d $completions ]]; then
		"$destination/tidal" --generate-completion-script zsh >| "$completions/_tidal"
		echo "$completions/_tidal"
	fi
else
	echo "$binary"
fi
