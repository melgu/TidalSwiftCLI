//
//  Backup.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation
import TidalSwiftLib

/// The favorites and own playlists of the account
@MainActor
func createBackup(session: Session, progress: ((AccountBackupProgress) -> Void)? = nil) async throws -> AccountBackup {
	do {
		return try await session.backup(progress: progress)
	} catch let error as AccountBackupError {
		throw CLIError(error.description)
	}
}

struct BackupFile: Encodable {
	let path: String
	let favorites: Int
	let playlists: Int
	/// Of all playlists together
	let playlistItems: Int
	let folders: Int
	/// Artists, tracks and videos together
	let blocks: Int
}

/// Writes the backup, replacing a file that is there already
func writeBackup(_ backup: AccountBackup, to path: String) throws -> BackupFile {
	let url = fileURL(path)
	do {
		try backup.data().write(to: url, options: .atomic)
	} catch {
		throw CLIError("Couldn't write \(url.path(percentEncoded: false)): \(error.localizedDescription)")
	}
	return BackupFile(
		path: url.path(percentEncoded: false),
		favorites: backup.favorites.count,
		playlists: backup.playlists.count,
		playlistItems: backup.playlists.reduce(0) { $0 + $1.items.count },
		folders: backup.folders?.count ?? 0,
		blocks: backup.blocks?.count ?? 0
	)
}

/// Reads a file written by `backup create`, or standard input for "-"
func readBackup(from path: String) throws -> AccountBackup {
	let data: Data
	if path == "-" {
		data = FileHandle.standardInput.readDataToEndOfFile()
	} else {
		let url = fileURL(path)
		do {
			data = try Data(contentsOf: url)
		} catch {
			throw CLIError("Couldn't read \(url.path(percentEncoded: false)): \(error.localizedDescription)")
		}
	}
	do {
		return try AccountBackup(data: data)
	} catch let error as AccountBackupError {
		throw CLIError(error.description)
	} catch {
		throw CLIError("\(path == "-" ? "The input" : path) isn't a backup: \(error.localizedDescription)")
	}
}

/// Compares the backup with the account, changing nothing
@MainActor
func restorePlan(session: Session, backup: AccountBackup, options: AccountRestoreOptions) async throws -> AccountRestorePlan {
	do {
		return try await session.restorePlan(for: backup, options: options)
	} catch let error as AccountBackupError {
		throw CLIError(error.description)
	}
}

struct RestorePlanSummary: Encodable {
	struct Changes<Entry: Encodable & Sendable>: Encodable {
		/// Oldest first, the order they're added in
		let add: [Entry]
		let remove: [Entry]
		
		init(_ changes: AccountRestorePlan.Changes<Entry>) {
			add = changes.add
			remove = changes.remove
		}
	}
	
	struct Favorites: Encodable {
		let tracks: Changes<PlaylistExport.Item>
		let videos: Changes<PlaylistExport.Item>
		let albums: Changes<AccountBackup.AlbumEntry>
		let artists: Changes<AccountBackup.ArtistEntry>
		/// Playlists of others
		let playlists: Changes<AccountBackup.PlaylistEntry>
		let mixes: Changes<AccountBackup.MixEntry>
	}
	
	struct FolderMove: Encodable {
		enum Kind: String, Encodable {
			case folder, playlist
		}
		
		let kind: Kind
		/// The name of the folder or the title of the playlist
		let title: String
		/// The folder it's put into, nil for the root
		let folder: String?
		
		init(_ move: FolderChanges.Move) {
			kind = if case .folder = move.item { .folder } else { .playlist }
			title = move.title
			folder = move.folderName
		}
	}
	
	struct Folders: Encodable {
		struct Rename: Encodable {
			let from: String
			let to: String
		}
		
		/// Names of the folders
		let create: [String]
		let rename: [Rename]
		/// In the order they're made
		let move: [FolderMove]
		let delete: [String]
		
		init(_ changes: FolderChanges) {
			create = changes.create.map(\.name)
			rename = changes.rename.map { Rename(from: $0.folder.name, to: $0.name) }
			move = changes.moves.map(FolderMove.init)
			delete = changes.delete.map(\.name)
		}
		
		var isEmpty: Bool {
			create.isEmpty && rename.isEmpty && move.isEmpty && delete.isEmpty
		}
	}
	
	struct PlaylistChange: Encodable {
		enum Action: String, Encodable {
			case create, append, replace, unchanged, delete
		}
		
		let action: Action
		let title: String
		/// The playlist in the account, nil for one to create
		let uuid: String?
		/// Of the backup's playlist, or of the one to delete
		let items: Int
		/// The items an append adds
		let missing: Int?
		
		init(_ change: AccountRestorePlan.PlaylistChange) {
			title = change.title
			switch change {
			case let .create(export):
				(action, uuid, items, missing) = (.create, nil, export.items.count, nil)
			case let .append(export, playlist, count):
				(action, uuid, items, missing) = (.append, playlist.uuid, export.items.count, count)
			case let .replace(export, playlist):
				(action, uuid, items, missing) = (.replace, playlist.uuid, export.items.count, nil)
			case let .unchanged(export, playlist):
				(action, uuid, items, missing) = (.unchanged, playlist.uuid, export.items.count, nil)
			case let .delete(playlist):
				(action, uuid, items, missing) = (.delete, playlist.uuid, playlist.itemIds.count, nil)
			}
		}
	}
	
	let backupDate: Date
	/// The backup was made of another account
	let otherAccount: Bool
	let favorites: Favorites
	/// The account's own playlists
	let playlists: [PlaylistChange]
	/// Nil for backups without folders
	let folders: Folders?
	/// Nil for backups without blocks
	let blocks: Blocks?
	
	struct Blocks: Encodable {
		let artists: Changes<AccountBackup.ArtistEntry>
		let tracks: Changes<PlaylistExport.Item>
		let videos: Changes<PlaylistExport.Item>
	}
	let isEmpty: Bool
	/// Whether the restore also changes what the account has, beyond adding to it
	private let override: Bool
	
	@MainActor
	init(_ plan: AccountRestorePlan, session: Session) {
		backupDate = plan.backup.exportedAt
		otherAccount = plan.backup.userId != session.userId
		favorites = Favorites(
			tracks: Changes(plan.tracks),
			videos: Changes(plan.videos),
			albums: Changes(plan.albums),
			artists: Changes(plan.artists),
			playlists: Changes(plan.playlists),
			mixes: Changes(plan.mixes)
		)
		playlists = plan.ownPlaylists.map(PlaylistChange.init)
		folders = plan.backup.folders == nil ? nil : Folders(plan.folders)
		blocks = plan.backup.blocks == nil ? nil : Blocks(artists: Changes(plan.blocks.artists), tracks: Changes(plan.blocks.tracks), videos: Changes(plan.blocks.videos))
		isEmpty = plan.isEmpty
		override = plan.options.override
	}
	
	/// What the restore removes, replaces or rearranges
	var removesSomething: Bool {
		!favorites.tracks.remove.isEmpty || !favorites.videos.remove.isEmpty || !favorites.albums.remove.isEmpty
			|| !favorites.artists.remove.isEmpty || !favorites.playlists.remove.isEmpty || !favorites.mixes.remove.isEmpty
			|| blocks.map { !$0.artists.remove.isEmpty || !$0.tracks.remove.isEmpty || !$0.videos.remove.isEmpty } == true
			|| playlists.contains { $0.action == .replace || $0.action == .delete }
			|| folders.map { !$0.rename.isEmpty || !$0.delete.isEmpty || (override && !$0.move.isEmpty) } == true
	}
}

struct RestoreSummary: Encodable {
	struct Favorites<Entry: Encodable>: Encodable {
		let added: Int
		let removed: Int
		/// Tidal no longer has them
		let missing: [Entry]
		
		@MainActor
		init(_ result: AccountRestoreResult.Favorites<Entry>) {
			added = result.added.count
			removed = result.removed.count
			missing = result.missing
		}
	}
	
	struct FavoriteResults: Encodable {
		let tracks: Favorites<PlaylistExport.Item>
		/// Tidal no longer knows their ID, so another track of the same recording was added
		let replacedTracks: [PlaylistImportSummary.Replacement]
		let videos: Favorites<PlaylistExport.Item>
		let albums: Favorites<AccountBackup.AlbumEntry>
		let artists: Favorites<AccountBackup.ArtistEntry>
		let playlists: Favorites<AccountBackup.PlaylistEntry>
		let mixes: Favorites<AccountBackup.MixEntry>
	}
	
	struct FolderResults: Encodable {
		let created: [String]
		let renamed: [RestorePlanSummary.Folders.Rename]
		let moved: [RestorePlanSummary.FolderMove]
		/// Playlists Tidal no longer has, and moves that would have put a folder into itself
		let skipped: [RestorePlanSummary.FolderMove]
		let deleted: [String]
		
		@MainActor
		init(_ result: AccountRestoreResult.FolderResult) {
			created = result.created
			renamed = result.renamed.map { .init(from: $0.folder.name, to: $0.name) }
			moved = result.moved.map(RestorePlanSummary.FolderMove.init)
			skipped = result.skipped.map(RestorePlanSummary.FolderMove.init)
			deleted = result.deleted.map(\.name)
		}
		
		var isEmpty: Bool {
			created.isEmpty && renamed.isEmpty && moved.isEmpty && skipped.isEmpty && deleted.isEmpty
		}
	}
	
	struct PlaylistResult: Encodable {
		let action: RestorePlanSummary.PlaylistChange.Action
		let title: String
		/// Nil for deleted playlists
		let playlist: PlaylistSummary?
		let added: Int
		let replaced: [PlaylistImportSummary.Replacement]
		let missing: [PlaylistExport.Item]
	}
	
	let favorites: FavoriteResults
	/// The account's own playlists that changed
	let playlists: [PlaylistResult]
	let unchangedPlaylists: Int
	let folders: FolderResults
	/// `added` are the ones blocked, `removed` the ones unblocked
	let blocks: BlockResults
	
	struct BlockResults: Encodable {
		let artists: Favorites<AccountBackup.ArtistEntry>
		let tracks: Favorites<PlaylistExport.Item>
		let videos: Favorites<PlaylistExport.Item>
	}
	
	@MainActor
	init(_ result: AccountRestoreResult, session: Session) {
		func replacements(_ replaced: [PlaylistImportResult.Replacement]) -> [PlaylistImportSummary.Replacement] {
			replaced.map { PlaylistImportSummary.Replacement(original: $0.original, replacement: TrackSummary($0.track)) }
		}
		favorites = FavoriteResults(
			tracks: Favorites(result.tracks),
			replacedTracks: replacements(result.replacedTracks),
			videos: Favorites(result.videos),
			albums: Favorites(result.albums),
			artists: Favorites(result.artists),
			playlists: Favorites(result.playlists),
			mixes: Favorites(result.mixes)
		)
		folders = FolderResults(result.folders)
		blocks = BlockResults(artists: Favorites(result.blockedArtists), tracks: Favorites(result.blockedTracks), videos: Favorites(result.blockedVideos))
		let changed = result.ownPlaylists.filter { !$0.change.isUnchanged }
		playlists = changed.map { playlist in
			PlaylistResult(
				action: RestorePlanSummary.PlaylistChange(playlist.change).action,
				title: playlist.change.title,
				playlist: playlist.imported.map { PlaylistSummary($0.playlist, session: session) },
				added: playlist.imported?.added.count ?? 0,
				replaced: replacements(playlist.imported?.replaced ?? []),
				missing: playlist.imported?.missing ?? []
			)
		}
		unchangedPlaylists = result.ownPlaylists.count - changed.count
	}
}

@MainActor
func restore(session: Session, plan: AccountRestorePlan, progress: ((AccountRestoreProgress) -> Void)? = nil) async throws -> RestoreSummary {
	do {
		return RestoreSummary(try await session.restore(plan, progress: progress), session: session)
	} catch let error as AccountRestoreError {
		throw CLIError(error.description)
	}
}
