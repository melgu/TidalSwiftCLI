//
//  PlaylistsCommand.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 31.10.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import ArgumentParser
import Foundation
import TidalSwiftLib

struct Playlists: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "List, show and edit playlists. Playlists are given as a link or UUID.",
		subcommands: [
			List.self,
			Show.self,
			Create.self,
			Edit.self,
			Delete.self,
			Add.self,
			Remove.self,
			Move.self,
			Export.self,
			Import.self
		]
	)
	
	struct List: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "List your playlists and the ones in your favorites."
		)
		
		@Flag(help: "Only list your own playlists.")
		var own = false
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let playlists = try await playlists(session: session, ownOnly: own)
			if output.json {
				try printJSON(playlists)
			} else {
				playlists.forEach { print($0.line) }
			}
		}
	}
	
	struct Show: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Show a playlist and its tracks and videos, with the positions remove and move take."
		)
		
		@Argument(help: "The playlist.")
		var playlist: String
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let details = try await playlistDetails(session: session, reference: playlist)
			if output.json {
				try printJSON(details)
				return
			}
			print(details.playlist.title)
			if let description = details.playlist.description {
				print(description)
			}
			print(details.playlist.url.absoluteString)
			print()
			let width = String(details.items.count).count
			for item in details.items {
				let position = String(repeating: " ", count: width - String(item.position).count) + String(item.position)
				print("\(position)  \(item.line)")
			}
		}
	}
	
	struct Create: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Create a playlist."
		)
		
		@Argument(help: "The title.")
		var title: String
		
		@Option(help: "The description.")
		var description = ""
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let playlist = try await createPlaylist(session: session, title: title, description: description)
			if output.json {
				try printJSON(playlist)
			} else {
				print("Created \(playlist.line)")
			}
		}
	}
	
	struct Edit: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Change the title or description of one of your playlists."
		)
		
		@Argument(help: "The playlist.")
		var playlist: String
		
		@Option(help: "The new title.")
		var title: String?
		
		@Option(help: "The new description. Pass \"\" to remove it.")
		var description: String?
		
		@OptionGroup var output: OutputOptions
		
		func validate() throws {
			if title == nil && description == nil {
				throw ValidationError("Pass --title, --description or both.")
			}
		}
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let edited = try await editPlaylist(session: session, reference: playlist, title: title, description: description)
			if output.json {
				try printJSON(edited)
			} else {
				print("Changed \(edited.line)")
			}
		}
	}
	
	struct Delete: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Delete one of your playlists."
		)
		
		@Argument(help: "The playlist.")
		var playlist: String
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let deleted = try await deletePlaylist(session: session, reference: playlist)
			if output.json {
				try printJSON(deleted)
			} else {
				print("Deleted \(deleted.line)")
			}
		}
	}
	
	struct Add: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Add tracks and videos to one of your playlists. Albums and playlists add all their items."
		)
		
		@Argument(help: "The playlist to add to.")
		var playlist: String
		
		@Argument(help: "Tracks, videos, albums or playlists, as links or IDs.")
		var items: [String]
		
		@Option(name: [.customLong("type"), .short], help: "What the IDs are, if not links.")
		var type: ItemKind?
		
		@Flag(help: "Add items that are in the playlist already.")
		var allowDuplicates = false
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let addition = try await addToPlaylist(session: session, reference: playlist, items: items, kind: type, allowDuplicates: allowDuplicates)
			if output.json {
				try printJSON(addition)
				return
			}
			if !addition.added.isEmpty {
				print("Added:")
				addition.added.forEach { print($0.line) }
			}
			if !addition.skipped.isEmpty {
				print("Skipped, as they're in the playlist already (pass --allow-duplicates to add them anyway):")
				addition.skipped.forEach { print($0.line) }
			}
		}
	}
	
	struct Remove: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Remove items from one of your playlists by their position, as `show` lists them."
		)
		
		@Argument(help: "The playlist.")
		var playlist: String
		
		@Argument(help: "Positions, starting at 1.")
		var positions: [Int]
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let removed = try await removeFromPlaylist(session: session, reference: playlist, positions: positions)
			if output.json {
				try printJSON(removed)
			} else {
				print("Removed:")
				removed.forEach { print($0.line) }
			}
		}
	}
	
	struct Move: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Move an item within one of your playlists, by positions as `show` lists them."
		)
		
		@Argument(help: "The playlist.")
		var playlist: String
		
		@Argument(help: "Current position, starting at 1.")
		var from: Int
		
		@Argument(help: "New position, starting at 1.")
		var to: Int
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let moved = try await moveInPlaylist(session: session, reference: playlist, from: from, to: to)
			if output.json {
				try printJSON(moved)
			} else {
				print("Moved to position \(to): \(moved.line)")
			}
		}
	}
	
	struct Export: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Save a playlist to a JSON file, to back it up or import it elsewhere.",
			discussion: "Works for any playlist, also for someone else's. The file keeps the IDs of the tracks and videos, and their title, artists, album and ISRC to recognize them or find them again."
		)
		
		@Argument(help: "The playlist.")
		var playlist: String
		
		@Option(name: [.customLong("out"), .short], help: "The file to write, replacing it if it exists. Without, the export goes to standard output.")
		var out: String?
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let export = try await exportPlaylist(session: session, reference: playlist)
			guard let out else {
				print(String(decoding: try export.data(), as: UTF8.self))
				return
			}
			let file = try writeExport(export, to: out)
			if output.json {
				try printJSON(file)
			} else {
				print("Exported \(file.playlist) (\(file.items == 1 ? "1 item" : "\(file.items) items")) to \(file.path)")
			}
		}
	}
	
	struct Import: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Create a playlist from a file written by `export`, or add the file's items to one of your playlists.",
			discussion: "Tracks whose ID Tidal no longer knows are looked up by their ISRC and replaced by another track of the same recording. What can't be found is listed as missing. The dates the items were added can't be restored."
		)
		
		@Argument(help: "The file, or - for standard input.")
		var file: String
		
		@Option(help: "One of your playlists to add the items to, instead of creating a new one.")
		var into: String?
		
		@Flag(help: "Replace the title, description and items of the playlist given with --into with those of the file.")
		var override = false
		
		@Flag(help: "With --into, also add items that are in the playlist already.")
		var allowDuplicates = false
		
		@Flag(name: [.customLong("yes"), .short], help: "Don't ask before replacing the items with --override.")
		var yes = false
		
		@OptionGroup var output: OutputOptions
		
		func validate() throws {
			if into == nil && (override || allowDuplicates) {
				throw ValidationError("--override and --allow-duplicates need --into.")
			}
			if override && allowDuplicates {
				throw ValidationError("--override keeps the duplicates of the file, so --allow-duplicates isn't needed.")
			}
		}
		
		@MainActor
		func run() async throws {
			let export = try readExport(from: file)
			let session = try loggedInSession()
			let target: PlaylistImportTarget
			if let into {
				if override {
					try await confirmOverride(of: into, session: session, with: export)
					target = .replace(playlist: into)
				} else {
					target = .append(playlist: into, allowDuplicates: allowDuplicates)
				}
			} else {
				target = .new
			}
			let summary = try await importPlaylist(session: session, export: export, target: target)
			if output.json {
				try printJSON(summary)
				return
			}
			print("\(into == nil ? "Created" : "Imported into") \(summary.playlist.line)")
			print("Added \(summary.added == 1 ? "1 item" : "\(summary.added) items")")
			if !summary.replaced.isEmpty {
				print("Replaced by another track of the same recording, as Tidal no longer knows them:")
				summary.replaced.forEach { print("\($0.original.line)\n  → \($0.replacement.line)") }
			}
			if !summary.skipped.isEmpty {
				print("Skipped, as they're in the playlist already (pass --allow-duplicates to add them anyway):")
				summary.skipped.forEach { print($0.line) }
			}
			if !summary.missing.isEmpty {
				print("Missing, as Tidal no longer has them:")
				summary.missing.forEach { print($0.line) }
			}
		}
		
		@MainActor
		private func confirmOverride(of reference: String, session: Session, with export: PlaylistExport) async throws {
			guard !yes else {
				return
			}
			guard isatty(STDIN_FILENO) != 0, file != "-" else {
				throw CLIError("--override replaces all items of the playlist. Pass --yes to confirm.")
			}
			let playlist = try await ownPlaylist(reference: reference, session: session)
			let items = playlist.numberOfTracks + playlist.numberOfVideos
			FileHandle.standardError.write(Data("Replace \(playlist.title) (\(items) items) with \(export.title) (\(export.items.count) items) from the file? [y/N] ".utf8))
			guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), ["y", "yes"].contains(answer) else {
				throw CLIError("Nothing changed")
			}
		}
	}
}
