# TidalSwiftCLI

`tidal`, a command line tool for Tidal: search, artist releases, new releases of your favorite artists, playlists, favorites, backup and restore of your account, and downloads. It also runs as an MCP server, so AI assistants can use your Tidal account. Built on [TidalSwiftLib](https://github.com/melgu/TidalSwiftLib), the library behind the [TidalSwift](https://github.com/melgu/TidalSwift) app.

Requires macOS 14.



## Installation

With [Homebrew](https://brew.sh):

```sh
brew install melgu/tap/tidalswift-cli
```

This installs `tidal` with completion for zsh, bash and fish, for Apple silicon and Intel Macs.

Or build it from source with Swift 6.2:

```sh
git clone https://github.com/melgu/TidalSwiftCLI
cd TidalSwiftCLI
./build.sh install
```

This installs `tidal` to `/usr/local/bin` and its zsh completion to `/usr/local/share/zsh/site-functions`. `build.sh` signs the binary with an "Apple Development" certificate, so the Keychain remembers its access to the login.



## Usage

```sh
tidal login                       # asks which login: Dolby Atmos or Hi-Res
tidal login --atmos               # Dolby Atmos login: approve this device in the browser
tidal login --hi-res              # Hi-Res login: log in in the browser, paste the error page's address
tidal search "Jacob Collier"
tidal artist https://tidal.com/browse/artist/123456 --type eps-and-singles
tidal new-releases --include-eps-and-singles
tidal playlists list
tidal playlists export <playlist> --out roadtrip.json
tidal playlists import roadtrip.json                                    # as a new playlist
tidal playlists import roadtrip.json --into <playlist> --override       # replaces its items
tidal favorites add https://tidal.com/browse/album/123456
tidal backup create --out tidal-backup.json                             # see Backup & Restore below
tidal download https://tidal.com/browse/album/123456
```

Items are given as Tidal links or IDs. Most commands take `--json` for output that other tools can read. `tidal help <command>` shows all options.

The two logins get different qualities. The Dolby Atmos login gets High (FLAC 16 bit / 44.1 kHz) and Dolby Atmos, the Hi-Res login Low, High and Max (FLAC up to 24 bit / 192 kHz), but no Dolby Atmos. Log in with both to get everything: downloads then take each from the login that gets it.



## Backup & Restore

`tidal backup create` saves your favorite tracks, videos, albums, artists, playlists and mixes, all your own playlists with their items and whether they're public, the folders of your playlists, and the artists, tracks and videos you blocked to one JSON file. `tidal backup restore` brings them back, also into another account:

```sh
tidal backup create --out tidal-backup.json
tidal backup restore tidal-backup.json --dry-run                        # shows what would change
tidal backup restore tidal-backup.json                                  # adds what's missing
tidal backup restore tidal-backup.json --override                       # also removes, replaces and moves
tidal backup restore tidal-backup.json --override --delete              # also deletes playlists and folders not in the backup
```

- Without `--override`, a restore only adds: missing favorites, missing playlists, the items a playlist is missing, at its end, missing folders and missing blocks. Playlists and folders at the root are put into their folder.
- `--override` makes the account match the backup. It removes favorites the backup doesn't have, replaces the title, description, visibility and items of playlists that differ, renames folders, moves folders and playlists to where the backup has them, and unblocks what the backup doesn't block. Playlists and folders the backup doesn't have are kept, unless `--delete` is given, which moves the contents of a deleted folder to the root. It asks before removing anything, or takes `--yes`.
- Playlists are found by their UUID, or else by their title if only one playlist has it, and folders by their ID or their name within their parent, so restoring twice doesn't create them twice.
- Favorites get the date they were added before. Mixes keep their order, but get the date of the restore, as Tidal can't set theirs.
- Tracks whose ID Tidal no longer knows are replaced by another track of the same recording, found by their ISRC. What can't be found is listed as missing.
- If Tidal rejects a change, the restore stops. Restoring again continues with what is still missing.

Single playlists can be exported and imported the same way with `tidal playlists export` and `tidal playlists import`.



## MCP Server

`tidal mcp` runs an MCP server on stdin and stdout with tools for search, releases, playlists, favorites, backups and downloads. If the account isn't logged in yet, it asks the client to show the login link. To add it to Claude Code for all projects:

```sh
claude mcp add -s user tidal -- tidal mcp
```

Other clients take the command `tidal` with the argument `mcp`.



## License

TidalSwiftCLI is licensed under the [GNU General Public License v3.0](LICENSE).
