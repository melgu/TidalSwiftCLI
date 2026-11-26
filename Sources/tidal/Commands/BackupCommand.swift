//
//  BackupCommand.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import ArgumentParser
import Foundation
import TidalSwiftLib

struct BackupCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "backup",
		abstract: "Back up the favorites and playlists of the account, and restore them.",
		subcommands: [
			Create.self,
			Restore.self
		]
	)
	
	struct Create: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Save the favorites, your own playlists and their folders to a JSON file.",
			discussion: "The file keeps the IDs of the favorites and playlist items, with the date they were added, and their title, artists and ISRC to recognize them or find them again. Favorite playlists of others are kept as favorites, not with their items. Favorite mixes, the folders of the playlists, whether a playlist is public, and the blocked artists, tracks and videos are kept as well."
		)
		
		@Option(name: [.customLong("out"), .short], help: "The file to write, replacing it if it exists. Without, the backup goes to standard output.")
		var out: String?
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let progress: ((AccountBackupProgress) -> Void)? = showsProgress ? { printProgress($0) } : nil
			let backup = try await createBackup(session: session, progress: progress)
			guard let out else {
				print(String(decoding: try backup.data(), as: UTF8.self))
				return
			}
			let file = try writeBackup(backup, to: out)
			if output.json {
				try printJSON(file)
			} else {
				print("Backed up \(count(file.favorites, "favorite")), \(count(file.playlists, "playlist")) (\(count(file.playlistItems, "item"))), \(count(file.folders, "folder")) and \(count(file.blocks, "block")) to \(file.path)")
			}
		}
		
		private func printProgress(_ progress: AccountBackupProgress) {
			switch progress {
			case .loadingFavorites:
				printToStderr("Loading the favorites")
			case .loadingFolders:
				printToStderr("Loading the folders")
			case let .loadingPlaylist(title, number, total):
				printToStderr("Loading playlist \(number) of \(total): \(title)")
			}
		}
	}
	
	struct Restore: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Add the favorites, playlists, folders and blocks of a backup that the account is missing.",
			discussion: """
				Without --override, nothing is removed: missing favorites, playlists, folders and blocks are added, playlists that still exist get the items they're missing at their end, \
				and playlists and folders at the root are put into their folder. \
				Playlists are found by their UUID, or else by their title if only one playlist has it, and folders by their ID or their name within their parent, \
				so restoring again doesn't create them twice.

				Favorites get the date they were added before, apart from mixes, which are added oldest first, so they keep their order. \
				Tracks whose ID Tidal no longer knows are replaced by another track of the same recording, found by their ISRC. What can't be found is listed as missing.

				If Tidal rejects a change, the restore stops. Restoring again continues with what is still missing.
				"""
		)
		
		@Argument(help: "The file, or - for standard input.")
		var file: String
		
		@Flag(help: "Make the account match the backup: also remove favorites the backup doesn't have, replace the title, description, visibility and items of playlists that differ, rename folders, move folders and playlists to where the backup has them, and unblock what the backup doesn't block. Keeps playlists and folders the backup doesn't have.")
		var override = false
		
		@Flag(help: "With --override, also delete your playlists and folders that the backup doesn't have. The contents of a deleted folder are moved to the root.")
		var delete = false
		
		@Flag(help: "Only show what would change.")
		var dryRun = false
		
		@Flag(name: [.customLong("yes"), .short], help: "Don't ask before removing or replacing anything with --override.")
		var yes = false
		
		@OptionGroup var output: OutputOptions
		
		func validate() throws {
			if delete && !override {
				throw ValidationError("--delete needs --override.")
			}
		}
		
		@MainActor
		func run() async throws {
			let backup = try readBackup(from: file)
			let session = try loggedInSession()
			if showsProgress {
				printToStderr("Comparing the backup with the account")
			}
			let plan = try await restorePlan(session: session, backup: backup, options: AccountRestoreOptions(override: override, deletePlaylists: delete))
			let summary = RestorePlanSummary(plan, session: session)
			if dryRun {
				if output.json {
					try printJSON(summary)
				} else {
					summary.printLines()
				}
				return
			}
			// An empty plan changes nothing, but still gives the JSON of a restore
			if summary.isEmpty && !output.json {
				print("The account already has everything in the backup")
				return
			}
			if !summary.isEmpty {
				try confirm(summary)
			}
			let progress: ((AccountRestoreProgress) -> Void)? = showsProgress ? { printProgress($0) } : nil
			let result = try await restore(session: session, plan: plan, progress: progress)
			if output.json {
				try printJSON(result)
			} else {
				result.printLines()
			}
		}
		
		/// Asks before removing or replacing anything, and before restoring another account's backup
		private func confirm(_ summary: RestorePlanSummary) throws {
			guard (summary.removesSomething || summary.otherAccount) && !yes else {
				return
			}
			guard isatty(STDIN_FILENO) != 0, file != "-" else {
				throw CLIError(summary.removesSomething
					? "--override removes or replaces favorites, playlists and folders. Check them with --dry-run, then pass --yes to confirm."
					: "The backup is of another account. Pass --yes to restore it anyway.")
			}
			summary.printLines(to: printToStderr)
			FileHandle.standardError.write(Data("\nRestore? [y/N] ".utf8))
			guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), ["y", "yes"].contains(answer) else {
				throw CLIError("Nothing changed")
			}
		}
		
		private func printProgress(_ progress: AccountRestoreProgress) {
			switch progress {
			case let .restoringPlaylist(title, number, total):
				printToStderr("Restoring playlist \(number) of \(total): \(title)")
			case let .addingFavorites(kind, count):
				printToStderr("Adding \(count) favorite \(kind.noun(count))")
			case let .removingFavorites(kind, count):
				printToStderr("Removing \(count) favorite \(kind.noun(count))")
			case .restoringFolders:
				printToStderr("Restoring the folders")
			case let .blocking(kind, count):
				printToStderr("Blocking \(count) \(kind.noun(count))")
			case let .unblocking(kind, count):
				printToStderr("Unblocking \(count) \(kind.noun(count))")
			}
		}
	}
}

/// Progress goes to stderr, but only to a terminal
private var showsProgress: Bool {
	isatty(STDERR_FILENO) != 0
}

private func count(_ count: Int, _ noun: String) -> String {
	count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
}

extension FavoriteKind {
	func noun(_ count: Int) -> String {
		guard count == 1 else {
			return rawValue
		}
		return self == .mixes ? "mix" : String(rawValue.dropLast())
	}
}

extension BlockKind {
	func noun(_ count: Int) -> String {
		count == 1 ? String(rawValue.dropLast()) : rawValue
	}
}

extension AccountBackup.MixEntry {
	var line: String {
		"\(id)  \(title)" + (subTitle.map { " – \($0)" } ?? "")
	}
}

extension RestorePlanSummary.FolderMove {
	var line: String {
		"\(kind == .folder ? "Folder " : "")\(title) → \(folder ?? "root")"
	}
}

extension AccountBackup.AlbumEntry {
	var line: String {
		let title = version.map { "\(self.title) (\($0))" } ?? self.title
		return "\(id)  \(title) – \(artists.joined(separator: ", "))"
	}
}

extension AccountBackup.ArtistEntry {
	var line: String {
		"\(id)  \(name)"
	}
}

extension AccountBackup.PlaylistEntry {
	var line: String {
		"\(uuid)  \(title)" + (creator.map { " (by \($0))" } ?? "")
	}
}

extension RestorePlanSummary {
	func printLines(to write: (String) -> Void = { print($0) }) {
		if otherAccount {
			write("The backup is of another account.")
		}
		write("Backup of \(backupDate.formatted(date: .abbreviated, time: .shortened))")
		guard !isEmpty else {
			write("The account already has everything in the backup")
			return
		}
		
		let sections: [(FavoriteKind, add: Int, remove: [String])] = [
			(.tracks, favorites.tracks.add.count, favorites.tracks.remove.map(\.line)),
			(.videos, favorites.videos.add.count, favorites.videos.remove.map(\.line)),
			(.albums, favorites.albums.add.count, favorites.albums.remove.map(\.line)),
			(.artists, favorites.artists.add.count, favorites.artists.remove.map(\.line)),
			(.playlists, favorites.playlists.add.count, favorites.playlists.remove.map(\.line)),
			(.mixes, favorites.mixes.add.count, favorites.mixes.remove.map(\.line))
		]
		write("\nFavorites")
		for (kind, add, remove) in sections {
			var changes: [String] = []
			if add > 0 {
				changes.append("add \(add)")
			}
			if !remove.isEmpty {
				changes.append("remove \(remove.count)")
			}
			write("  \(kind.rawValue.capitalized): \(changes.isEmpty ? "unchanged" : changes.joined(separator: ", "))")
			remove.forEach { write("    − \($0)") }
		}
		
		write("\nPlaylists")
		let unchanged = playlists.filter { $0.action == .unchanged }.count
		for playlist in playlists where playlist.action != .unchanged {
			let details = switch playlist.action {
			case .create: "create, \(count(playlist.items, "item"))"
			case .append: "add \(count(playlist.missing ?? 0, "missing item"))"
			case .replace: "replace with \(count(playlist.items, "item"))"
			case .delete: "delete, \(count(playlist.items, "item"))"
			case .unchanged: "unchanged"
			}
			write("  \(playlist.title): \(details)")
		}
		if unchanged > 0 {
			write("  \(count(unchanged, "playlist")) unchanged")
		}
		
		write("\nBlocked")
		if let blocks {
			let sections: [(BlockKind, add: Int, remove: [String])] = [
				(.artists, blocks.artists.add.count, blocks.artists.remove.map(\.line)),
				(.tracks, blocks.tracks.add.count, blocks.tracks.remove.map(\.line)),
				(.videos, blocks.videos.add.count, blocks.videos.remove.map(\.line))
			]
			for (kind, add, remove) in sections {
				var changes: [String] = []
				if add > 0 {
					changes.append("block \(add)")
				}
				if !remove.isEmpty {
					changes.append("unblock \(remove.count)")
				}
				write("  \(kind.rawValue.capitalized): \(changes.isEmpty ? "unchanged" : changes.joined(separator: ", "))")
				remove.forEach { write("    − \($0)") }
			}
		} else {
			write("  Not in the backup, left as they are")
		}
		
		write("\nFolders")
		guard let folders else {
			write("  Not in the backup, left as they are")
			return
		}
		guard !folders.isEmpty else {
			write("  unchanged")
			return
		}
		folders.create.forEach { write("  Create \($0)") }
		folders.rename.forEach { write("  Rename \($0.from) to \($0.to)") }
		folders.move.forEach { write("  Move \($0.line)") }
		folders.delete.forEach { write("  Delete \($0), moving what's in it to the root") }
	}
}

extension RestoreSummary {
	func printLines() {
		let sections: [(FavoriteKind, added: Int, removed: Int, missing: [String])] = [
			(.tracks, favorites.tracks.added + favorites.replacedTracks.count, favorites.tracks.removed, favorites.tracks.missing.map(\.line)),
			(.videos, favorites.videos.added, favorites.videos.removed, favorites.videos.missing.map(\.line)),
			(.albums, favorites.albums.added, favorites.albums.removed, favorites.albums.missing.map(\.line)),
			(.artists, favorites.artists.added, favorites.artists.removed, favorites.artists.missing.map(\.line)),
			(.playlists, favorites.playlists.added, favorites.playlists.removed, favorites.playlists.missing.map(\.line)),
			(.mixes, favorites.mixes.added, favorites.mixes.removed, favorites.mixes.missing.map(\.line))
		]
		print("Favorites")
		for (kind, added, removed, missing) in sections {
			var changes: [String] = []
			if added > 0 {
				changes.append("added \(added)")
			}
			if removed > 0 {
				changes.append("removed \(removed)")
			}
			print("  \(kind.rawValue.capitalized): \(changes.isEmpty ? "unchanged" : changes.joined(separator: ", "))")
			if !missing.isEmpty {
				print("    Missing, as Tidal no longer has them:")
				missing.forEach { print("      \($0)") }
			}
		}
		if !favorites.replacedTracks.isEmpty {
			print("  Replaced by another track of the same recording, as Tidal no longer knows them:")
			favorites.replacedTracks.forEach { print("    \($0.original.line)\n      → \($0.replacement.line)") }
		}
		
		print("\nPlaylists")
		for result in playlists {
			let action = switch result.action {
			case .create: "Created"
			case .append: "Added to"
			case .replace: "Replaced"
			case .delete: "Deleted"
			case .unchanged: "Unchanged"
			}
			print("  \(action) \(result.playlist?.line ?? result.title)")
			if result.action != .delete {
				print("    Added \(count(result.added + result.replaced.count, "item"))")
			}
			if !result.replaced.isEmpty {
				print("    Replaced by another track of the same recording, as Tidal no longer knows them:")
				result.replaced.forEach { print("      \($0.original.line)\n        → \($0.replacement.line)") }
			}
			if !result.missing.isEmpty {
				print("    Missing, as Tidal no longer has them:")
				result.missing.forEach { print("      \($0.line)") }
			}
		}
		if unchangedPlaylists > 0 {
			print("  \(count(unchangedPlaylists, "playlist")) unchanged")
		}
		
		let blockSections: [(BlockKind, added: Int, removed: Int, missing: [String])] = [
			(.artists, blocks.artists.added, blocks.artists.removed, blocks.artists.missing.map(\.line)),
			(.tracks, blocks.tracks.added, blocks.tracks.removed, blocks.tracks.missing.map(\.line)),
			(.videos, blocks.videos.added, blocks.videos.removed, blocks.videos.missing.map(\.line))
		]
		if blockSections.contains(where: { $0.added > 0 || $0.removed > 0 || !$0.missing.isEmpty }) {
			print("\nBlocked")
			for (kind, added, removed, missing) in blockSections {
				var changes: [String] = []
				if added > 0 {
					changes.append("blocked \(added)")
				}
				if removed > 0 {
					changes.append("unblocked \(removed)")
				}
				print("  \(kind.rawValue.capitalized): \(changes.isEmpty ? "unchanged" : changes.joined(separator: ", "))")
				if !missing.isEmpty {
					print("    Missing, as Tidal no longer has them:")
					missing.forEach { print("      \($0)") }
				}
			}
		}
		
		guard !folders.isEmpty else {
			return
		}
		print("\nFolders")
		folders.created.forEach { print("  Created \($0)") }
		folders.renamed.forEach { print("  Renamed \($0.from) to \($0.to)") }
		folders.moved.forEach { print("  Moved \($0.line)") }
		folders.deleted.forEach { print("  Deleted \($0)") }
		if !folders.skipped.isEmpty {
			print("  Not moved, as Tidal no longer has the playlist or the folder would be inside itself:")
			folders.skipped.forEach { print("    \($0.line)") }
		}
	}
}
