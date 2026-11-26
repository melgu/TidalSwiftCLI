//
//  Tools.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 01.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation
import MCP
import TidalSwiftLib

// The tools of `tidal mcp`, each backed by the same operation as the matching command

private let readOnly = Tool.Annotations(readOnlyHint: true)
/// Clients assume tools are destructive unless told otherwise
private let additive = Tool.Annotations(readOnlyHint: false, destructiveHint: false)
private let destructive = Tool.Annotations(readOnlyHint: false, destructiveHint: true)

let tools: [Tool] = [
	Tool(
		name: "account",
		title: "Account",
		description: "The logged in Tidal account: user name, country and subscription.",
		inputSchema: schema([:]),
		annotations: readOnly
	),
	Tool(
		name: "search",
		title: "Search",
		description: "Search Tidal for tracks, albums, artists, playlists and videos.",
		inputSchema: schema([
			"query": string("What to search for"),
			"types": array(kindProperty("Only return these types. Defaults to all.")),
			"limit": integer("Maximum results per type. Defaults to 10.")
		], required: ["query"]),
		annotations: readOnly
	),
	Tool(
		name: "artist_releases",
		title: "Artist Releases",
		description: "An artist's releases of one type, newest first. Unlike search, the list is complete, so it answers questions like an artist's latest album.",
		inputSchema: schema([
			"artist": string("An artist link or ID"),
			"type": .object([
				"type": "string",
				"enum": .array(ReleaseType.allCases.map { .string($0.rawValue) }),
				"description": "Which releases. Appearances are compilations and other artists' albums. Defaults to albums."
			]),
			"limit": integer("Maximum number of releases. Defaults to all.")
		], required: ["artist"]),
		annotations: readOnly
	),
	Tool(
		name: "new_releases",
		title: "New Releases",
		description: "The newest releases of the account's favorite artists, newest first, as the app's New Releases shows them.",
		inputSchema: schema([
			"include_eps_and_singles": boolean("Include EPs and singles, not only albums"),
			"limit": integer("Maximum number of releases. Defaults to 40.")
		]),
		annotations: readOnly
	),
	Tool(
		name: "list_playlists",
		title: "List Playlists",
		description: "The account's own playlists and the ones it added to its favorites. Only own playlists (isOwn) can be changed.",
		inputSchema: schema([
			"own_only": boolean("Only list the account's own playlists")
		]),
		annotations: readOnly
	),
	Tool(
		name: "show_playlist",
		title: "Show Playlist",
		description: "A playlist and its tracks and videos, with the positions remove_from_playlist and move_in_playlist take.",
		inputSchema: schema([
			"playlist": string(playlistDescription)
		], required: ["playlist"]),
		annotations: readOnly
	),
	Tool(
		name: "create_playlist",
		title: "Create Playlist",
		description: "Create an empty playlist.",
		inputSchema: schema([
			"title": string("The title"),
			"description": string("The description")
		], required: ["title"]),
		annotations: additive
	),
	Tool(
		name: "edit_playlist",
		title: "Edit Playlist",
		description: "Change the title or description of one of the account's playlists. What isn't given stays as it is.",
		inputSchema: schema([
			"playlist": string(playlistDescription),
			"title": string("The new title"),
			"description": string("The new description. An empty string removes it.")
		], required: ["playlist"]),
		annotations: additive
	),
	Tool(
		name: "delete_playlist",
		title: "Delete Playlist",
		description: "Delete one of the account's playlists. This can't be undone.",
		inputSchema: schema([
			"playlist": string(playlistDescription)
		], required: ["playlist"]),
		annotations: destructive
	),
	Tool(
		name: "add_to_playlist",
		title: "Add to Playlist",
		description: "Add tracks and videos to one of the account's playlists. Albums and playlists add all their items. Items in the playlist already are skipped and listed as such.",
		inputSchema: schema([
			"playlist": string(playlistDescription),
			"items": array(string("A track, video, album or playlist")),
			"type": kindProperty(typeDescription),
			"allow_duplicates": boolean("Add items that are in the playlist already")
		], required: ["playlist", "items"]),
		annotations: additive
	),
	Tool(
		name: "remove_from_playlist",
		title: "Remove from Playlist",
		description: "Remove items from one of the account's playlists by their position, as show_playlist lists them.",
		inputSchema: schema([
			"playlist": string(playlistDescription),
			"positions": array(integer("A position, starting at 1"))
		], required: ["playlist", "positions"]),
		annotations: destructive
	),
	Tool(
		name: "move_in_playlist",
		title: "Move in Playlist",
		description: "Move an item within one of the account's playlists, by positions as show_playlist lists them.",
		inputSchema: schema([
			"playlist": string(playlistDescription),
			"from": integer("Current position, starting at 1"),
			"to": integer("New position, starting at 1")
		], required: ["playlist", "from", "to"]),
		annotations: additive
	),
	Tool(
		name: "export_playlist",
		title: "Export Playlist",
		description: "Save any playlist to a JSON file, to back it up or import it with import_playlist. The file keeps the IDs of the tracks and videos, and their title, artists, album and ISRC.",
		inputSchema: schema([
			"playlist": string(playlistDescription),
			"path": string("The file to write, replacing it if it exists")
		], required: ["playlist", "path"]),
		// Replaces the file
		annotations: destructive
	),
	Tool(
		name: "import_playlist",
		title: "Import Playlist",
		description: "Create a playlist from a file written by export_playlist, or add the file's items to one of the account's playlists. Tracks whose ID Tidal no longer knows are replaced by another track of the same recording, the rest is listed as missing.",
		inputSchema: schema([
			"path": string("The file"),
			"into": string("One of the account's playlists to add the items to, instead of creating a new one. A link or UUID."),
			"override": boolean("Replace the title, description and all items of the playlist given with into with those of the file"),
			"allow_duplicates": boolean("With into, also add items that are in the playlist already")
		], required: ["path"]),
		annotations: destructive
	),
	Tool(
		name: "list_favorites",
		title: "List Favorites",
		description: "The account's favorite tracks, albums, artists, playlists or videos.",
		inputSchema: schema([
			"type": kindProperty("What to list")
		], required: ["type"]),
		annotations: readOnly
	),
	Tool(
		name: "add_favorites",
		title: "Add Favorites",
		description: "Add items to the favorites.",
		inputSchema: schema([
			"items": array(string(itemDescription)),
			"type": kindProperty(typeDescription)
		], required: ["items"]),
		annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: true)
	),
	Tool(
		name: "remove_favorites",
		title: "Remove Favorites",
		description: "Remove items from the favorites.",
		inputSchema: schema([
			"items": array(string(itemDescription)),
			"type": kindProperty(typeDescription)
		], required: ["items"]),
		annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: true, idempotentHint: true)
	),
	Tool(
		name: "backup_account",
		title: "Back Up Account",
		description: "Save the account's favorites, including mixes, its own playlists, the folders of its playlists and its blocked artists, tracks and videos to a JSON file, to restore them with restore_account. Favorite playlists of others are kept as favorites, not with their items.",
		inputSchema: schema([
			"path": string("The file to write, replacing it if it exists")
		], required: ["path"]),
		// Replaces the file
		annotations: destructive
	),
	Tool(
		name: "restore_account",
		title: "Restore Account",
		description: """
			Restore a file written by backup_account. Without override, it only adds: missing favorites and playlists, \
			the items a playlist is missing at its end, missing folders and missing blocks, and puts playlists and folders at the root into their folder. \
			Favorites get the date of the backup again, apart from mixes. \
			Playlists are found by UUID, or else by a title only one playlist has, folders by ID or their name within their parent. \
			Tracks whose ID Tidal no longer knows are replaced by another track of the same recording, the rest is listed as missing. \
			Check what changes with dry_run first, especially with override.
			""",
		inputSchema: schema([
			"path": string("The file"),
			"override": boolean("Also remove favorites the backup doesn't have, replace the title, description, visibility and items of playlists that differ, rename folders, move folders and playlists to where the backup has them, and unblock what the backup doesn't block"),
			"delete_playlists": boolean("With override, also delete the account's playlists and folders that the backup doesn't have. The contents of a deleted folder are moved to the root."),
			"dry_run": boolean("Only return what would change")
		], required: ["path"]),
		annotations: destructive
	),
	Tool(
		name: "download",
		title: "Download",
		description: """
			Download a track, album, artist, playlist or video to a folder on this Mac. \
			Tracks come in the best quality the logins get: Max (FLAC up to 24 bit / 192 kHz) with the Hi-Res login, \
			High (FLAC 16 bit / 44.1 kHz) otherwise. Dolby Atmos needs the Dolby Atmos login. \
			The user adds a login with `tidal login --atmos` or `tidal login --hi-res` in a terminal. \
			Albums and playlists get a folder of their own, artists one per album. Existing files are replaced.
			""",
		inputSchema: schema([
			"item": string(itemDescription),
			"type": kindProperty(typeDescription),
			"quality": .object([
				"type": "string",
				"enum": .array(DownloadQuality.allCases.map { .string($0.rawValue) }),
				"description": .string("Stereo quality: \(DownloadQuality.summary) Defaults to max.")
			]),
			"atmos": boolean("Download Dolby Atmos instead of stereo where available"),
			"folder": string("Folder to download into, may start with ~. Defaults to ~/Downloads.")
		], required: ["item"]),
		annotations: additive
	)
]

/// Runs a tool and returns its result as text, mostly the JSON `--json` prints
@MainActor
func callTool(_ name: String, arguments: ToolArguments, session: Session, progress: @escaping (String) -> Void) async throws -> String {
	switch name {
	case "account":
		return try jsonString(await account(session: session))
	case "search":
		let kinds = try arguments.kinds("types").map(Set.init) ?? Set(ItemKind.allCases)
		let limit = try arguments.optionalInt("limit") ?? 10
		return try jsonString(await search(session: session, term: arguments.string("query"), kinds: kinds, limit: limit))
	case "artist_releases":
		let type = try arguments.optionalString("type").map { string in
			guard let type = ReleaseType(rawValue: string) else {
				throw CLIError("type must be one of \(ReleaseType.allCases.map(\.rawValue).joined(separator: ", "))")
			}
			return type
		} ?? .albums
		return try jsonString(await artistReleases(session: session, reference: arguments.string("artist"), type: type, limit: arguments.optionalInt("limit")))
	case "new_releases":
		return try jsonString(await newReleases(
			session: session,
			includeEpsAndSingles: arguments.bool("include_eps_and_singles"),
			limit: arguments.optionalInt("limit") ?? 40
		))
	case "list_playlists":
		return try jsonString(await playlists(session: session, ownOnly: arguments.bool("own_only")))
	case "show_playlist":
		return try jsonString(await playlistDetails(session: session, reference: arguments.string("playlist")))
	case "create_playlist":
		let description = try arguments.optionalString("description") ?? ""
		return try jsonString(await createPlaylist(session: session, title: arguments.string("title"), description: description))
	case "edit_playlist":
		let title = try arguments.optionalString("title")
		let description = try arguments.optionalString("description")
		guard title != nil || description != nil else {
			throw CLIError("Pass title, description or both")
		}
		return try jsonString(await editPlaylist(session: session, reference: arguments.string("playlist"), title: title, description: description))
	case "delete_playlist":
		return try jsonString(await deletePlaylist(session: session, reference: arguments.string("playlist")))
	case "add_to_playlist":
		return try jsonString(await addToPlaylist(
			session: session,
			reference: arguments.string("playlist"),
			items: arguments.strings("items"),
			kind: arguments.kind("type"),
			allowDuplicates: arguments.bool("allow_duplicates")
		))
	case "remove_from_playlist":
		return try jsonString(await removeFromPlaylist(session: session, reference: arguments.string("playlist"), positions: arguments.ints("positions")))
	case "move_in_playlist":
		return try jsonString(await moveInPlaylist(session: session, reference: arguments.string("playlist"), from: arguments.int("from"), to: arguments.int("to")))
	case "export_playlist":
		let export = try await exportPlaylist(session: session, reference: arguments.string("playlist"))
		return try jsonString(writeExport(export, to: arguments.string("path")))
	case "import_playlist":
		let path = try arguments.string("path")
		// Standard input carries the protocol
		guard path != "-" else {
			throw CLIError("path must be a file")
		}
		let export = try readExport(from: path)
		let into = try arguments.optionalString("into")
		let override = try arguments.bool("override")
		let allowDuplicates = try arguments.bool("allow_duplicates")
		let target: PlaylistImportTarget
		switch (into, override) {
		case (nil, _):
			guard !override && !allowDuplicates else {
				throw CLIError("override and allow_duplicates need into")
			}
			target = .new
		case let (playlist?, true):
			target = .replace(playlist: playlist)
		case let (playlist?, false):
			target = .append(playlist: playlist, allowDuplicates: allowDuplicates)
		}
		return try jsonString(await importPlaylist(session: session, export: export, target: target))
	case "list_favorites":
		guard let kind = try arguments.kind("type") else {
			throw CLIError("Missing argument type")
		}
		return try jsonString(await favorites(session: session, kind: kind))
	case "add_favorites", "remove_favorites":
		let isFavorite = name == "add_favorites"
		let kind = try arguments.kind("type")
		// Resolved first, so a typo doesn't leave the favorites half changed
		let links = try arguments.strings("items").map { try TidalLink(reference: $0, kind: kind) }
		for link in links {
			try await changeFavorite(session: session, link: link, isFavorite: isFavorite)
		}
		return "\(isFavorite ? "Added" : "Removed") \(links.count == 1 ? "1 item" : "\(links.count) items")"
	case "backup_account":
		let backup = try await createBackup(session: session)
		return try jsonString(writeBackup(backup, to: arguments.string("path")))
	case "restore_account":
		let path = try arguments.string("path")
		// Standard input carries the protocol
		guard path != "-" else {
			throw CLIError("path must be a file")
		}
		let backup = try readBackup(from: path)
		let override = try arguments.bool("override")
		let deletePlaylists = try arguments.bool("delete_playlists")
		guard override || !deletePlaylists else {
			throw CLIError("delete_playlists needs override")
		}
		let plan = try await restorePlan(session: session, backup: backup, options: AccountRestoreOptions(override: override, deletePlaylists: deletePlaylists))
		if try arguments.bool("dry_run") {
			return try jsonString(RestorePlanSummary(plan, session: session))
		}
		return try jsonString(await restore(session: session, plan: plan))
	case "download":
		let link = try TidalLink(reference: arguments.string("item"), kind: arguments.kind("type"))
		let destination = try downloadFolder(path: arguments.optionalString("folder"), fallback: .downloadsDirectory)
		let quality = try arguments.optionalString("quality").map { string in
			guard let quality = DownloadQuality(rawValue: string) else {
				throw CLIError("quality must be one of \(DownloadQuality.allCases.map(\.rawValue).joined(separator: ", "))")
			}
			return quality
		} ?? .max
		let options = DownloadOptions(audioQuality: quality.audioQuality, preferDolbyAtmos: try arguments.bool("atmos"), destination: destination)
		var summary = try await download(session: session, link: link, options: options, progress: progress)
		summary.warnings = downloadWarnings(session: session, options: options)
		return try jsonString(summary)
	default:
		throw MCPError.invalidParams("Unknown tool \(name)")
	}
}

private let playlistDescription = "A playlist link or UUID"
private let itemDescription = "A Tidal link, playlist UUID or ID"
private let typeDescription = "What bare IDs are. Not needed for links and UUIDs."

private func schema(_ properties: [String: Value], required: [String] = []) -> Value {
	.object([
		"type": "object",
		"properties": .object(properties),
		"required": .array(required.map { .string($0) })
	])
}

private func string(_ description: String) -> Value {
	.object(["type": "string", "description": .string(description)])
}

private func integer(_ description: String) -> Value {
	.object(["type": "integer", "description": .string(description)])
}

private func boolean(_ description: String) -> Value {
	.object(["type": "boolean", "description": .string(description)])
}

private func array(_ items: Value) -> Value {
	.object(["type": "array", "items": items])
}

private func kindProperty(_ description: String) -> Value {
	.object([
		"type": "string",
		"enum": .array(ItemKind.allCases.map { .string($0.rawValue) }),
		"description": .string(description)
	])
}
