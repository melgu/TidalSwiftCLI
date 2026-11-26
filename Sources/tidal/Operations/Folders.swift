//
//  Folders.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 26.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation
import TidalSwiftLib

struct FolderReference: Encodable {
	let id: String
	let name: String
	
	@MainActor
	init(_ folder: PlaylistFolder) {
		id = folder.id
		name = folder.name
	}
}

/// A folder with what's in it, each sorted by name
struct FolderSummary: Encodable {
	let id: String
	let name: String
	let folders: [FolderSummary]
	let playlists: [PlaylistSummary]
}

/// The folders and playlists at the root, with what's in the folders
struct FolderTree: Encodable {
	let folders: [FolderSummary]
	let playlists: [PlaylistSummary]
}

/// The account's own playlists and favorite playlists of others, in their folders
@MainActor
func folderTree(session: Session) async throws -> FolderTree {
	let items = try await collection(session: session)
	var folders: [String?: [PlaylistFolder]] = [:]
	var playlists: [String?: [PlaylistSummary]] = [:]
	for item in items {
		switch item {
		case let .folder(folder):
			folders[folder.parentId, default: []].append(folder)
		case let .playlist(playlist, folderId, _):
			playlists[folderId, default: []].append(PlaylistSummary(playlist, session: session))
		}
	}
	// Tidal keeps no order of its own, so it's by name as in `playlists list`
	func contents(of folderId: String?) -> ([FolderSummary], [PlaylistSummary]) {
		let subfolders = (folders[folderId] ?? [])
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
			.map { folder in
				let (folders, playlists) = contents(of: folder.id)
				return FolderSummary(id: folder.id, name: folder.name, folders: folders, playlists: playlists)
			}
		let playlists = (playlists[folderId] ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
		return (subfolders, playlists)
	}
	let (rootFolders, rootPlaylists) = contents(of: nil)
	return FolderTree(folders: rootFolders, playlists: rootPlaylists)
}

struct FolderCreation: Encodable {
	let folder: FolderReference
	/// Nil for the root
	let parent: FolderReference?
}

/// - Parameter parent: A folder's ID or name, nil for the root
@MainActor
func createFolder(session: Session, name: String, in parent: String?) async throws -> FolderCreation {
	let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !name.isEmpty else {
		throw CLIError("The folder needs a name")
	}
	var parentFolder: PlaylistFolder?
	if let parent {
		parentFolder = try folder(parent, in: try await collection(session: session))
	}
	guard let folder = await session.playlistFolders.create(name: name, in: parentFolder?.id) else {
		throw CLIError("Couldn't create the folder \(name)")
	}
	return FolderCreation(folder: FolderReference(folder), parent: parentFolder.map(FolderReference.init))
}

struct FolderRename: Encodable {
	let id: String
	let from: String
	let to: String
}

@MainActor
func renameFolder(session: Session, reference: String, to name: String) async throws -> FolderRename {
	let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !name.isEmpty else {
		throw CLIError("The folder needs a name")
	}
	let folder = try folder(reference, in: try await collection(session: session))
	guard await session.playlistFolders.rename(folderId: folder.id, to: name) else {
		throw CLIError("Couldn't rename \(folder.name)")
	}
	return FolderRename(id: folder.id, from: folder.name, to: name)
}

struct FolderMoveResult: Encodable {
	/// Nil for the root
	let folder: FolderReference?
	let folders: [FolderReference]
	let playlists: [PlaylistSummary]
}

/// Moves playlists, given as links or UUIDs, and folders, given by ID or name, into a folder
/// - Parameter target: A folder's ID or name, nil for the root
@MainActor
func moveToFolder(session: Session, items references: [String], into target: String?) async throws -> FolderMoveResult {
	let items = try await collection(session: session)
	let targetFolder = try target.map { try folder($0, in: items) }
	
	// All resolved first, so a typo doesn't leave half of them moved
	var folders: [PlaylistFolder] = []
	var playlists: [Playlist] = []
	for reference in references {
		switch try folderOrPlaylist(reference, in: items) {
		case let .folder(folder):
			if !folders.contains(folder) {
				folders.append(folder)
			}
		case let .playlist(playlist, _, _):
			if !playlists.contains(where: { $0.uuid == playlist.uuid }) {
				playlists.append(playlist)
			}
		}
	}
	if let targetFolder {
		let parents = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String?)? in
			guard case let .folder(folder) = item else { return nil }
			return (folder.id, folder.parentId)
		})
		for folder in folders where isWithin(targetFolder.id, folder: folder.id, parents: parents) {
			throw CLIError(folder.id == targetFolder.id ? "\(folder.name) can't be moved into itself" : "\(targetFolder.name) is inside \(folder.name), so \(folder.name) can't be moved into it")
		}
	}
	
	if !playlists.isEmpty {
		guard await session.playlistFolders.move(playlists: playlists.map(\.uuid), to: targetFolder?.id) else {
			throw CLIError("Couldn't move the playlists to \(targetFolder?.name ?? "the root")")
		}
	}
	for folder in folders {
		guard await session.playlistFolders.move(folderId: folder.id, to: targetFolder?.id) else {
			throw CLIError("Couldn't move \(folder.name) to \(targetFolder?.name ?? "the root")")
		}
	}
	return FolderMoveResult(
		folder: targetFolder.map(FolderReference.init),
		folders: folders.map(FolderReference.init),
		playlists: playlists.map { PlaylistSummary($0, session: session) }
	)
}

struct FolderDeletion: Encodable {
	let folder: FolderReference
	/// What was in the folder and is at the root now
	let movedFolders: [FolderReference]
	let movedPlaylists: [PlaylistSummary]
}

/// Deletes a folder, but not what's in it, which is moved to the root
@MainActor
func deleteFolder(session: Session, reference: String) async throws -> FolderDeletion {
	let items = try await collection(session: session)
	let folder = try folder(reference, in: items)
	let contents = items.filter { $0.folderId == folder.id }
	guard await session.playlistFolders.delete(folderId: folder.id) else {
		throw CLIError("Couldn't delete \(folder.name)")
	}
	return FolderDeletion(
		folder: FolderReference(folder),
		movedFolders: contents.compactMap { item in
			guard case let .folder(folder) = item else { return nil }
			return FolderReference(folder)
		},
		movedPlaylists: contents.compactMap { item in
			guard case let .playlist(playlist, _, _) = item else { return nil }
			return PlaylistSummary(playlist, session: session)
		}
	)
}

// MARK: - Finding folders

@MainActor
private func collection(session: Session) async throws -> [PlaylistFolderItem] {
	guard let items = await session.playlistFolders.all() else {
		throw CLIError("Couldn't load the folders")
	}
	return items
}

/// A folder by its ID, or else by its name, which only one folder may have
@MainActor
private func folder(_ reference: String, in items: [PlaylistFolderItem]) throws -> PlaylistFolder {
	guard let folder = try findFolder(reference, in: items) else {
		throw CLIError("There's no folder \(reference)")
	}
	return folder
}

@MainActor
private func findFolder(_ reference: String, in items: [PlaylistFolderItem]) throws -> PlaylistFolder? {
	let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
	let folders = items.compactMap { item -> PlaylistFolder? in
		guard case let .folder(folder) = item else { return nil }
		return folder
	}
	if let folder = folders.first(where: { $0.id.caseInsensitiveCompare(reference) == .orderedSame }) {
		return folder
	}
	var named = folders.filter { $0.name == reference }
	if named.isEmpty {
		named = folders.filter { $0.name.caseInsensitiveCompare(reference) == .orderedSame }
	}
	guard named.count <= 1 else {
		throw CLIError("Several folders are called \(reference), so give one by its ID: \(named.map(\.id).joined(separator: ", "))")
	}
	return named.first
}

/// A folder by ID or name, or a playlist by link or UUID, of the account's own and favorite playlists
@MainActor
private func folderOrPlaylist(_ reference: String, in items: [PlaylistFolderItem]) throws -> PlaylistFolderItem {
	let link = try? TidalLink(reference: reference, kind: .playlist)
	if case let .playlist(uuid) = link {
		if let folder = try findFolder(uuid, in: items) {
			return .folder(folder)
		}
		guard let playlist = items.first(where: { item in
			if case let .playlist(playlist, _, _) = item { playlist.uuid == uuid } else { false }
		}) else {
			throw CLIError("\(reference) is neither one of your playlists nor one in your favorites, so it isn't in a folder")
		}
		return playlist
	}
	guard let folder = try findFolder(reference, in: items) else {
		throw CLIError("\(reference) is neither a folder nor a playlist link or UUID")
	}
	return .folder(folder)
}

/// Whether `id` is the folder or inside it
private func isWithin(_ id: String, folder: String, parents: [String: String?]) -> Bool {
	var current: String? = id
	var seen: Set<String> = []
	while let next = current, seen.insert(next).inserted {
		if next == folder {
			return true
		}
		current = parents[next] ?? nil
	}
	return false
}
