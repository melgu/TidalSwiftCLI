//
//  PlaylistTransfer.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 25.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation
import TidalSwiftLib

/// Any playlist, also one of someone else
@MainActor
func exportPlaylist(session: Session, reference: String) async throws -> PlaylistExport {
	let playlist = try await loadPlaylist(reference: reference, session: session)
	guard let export = await session.exportPlaylist(playlistId: playlist.uuid) else {
		throw CLIError("Couldn't load the items of \(playlist.title)")
	}
	return export
}

struct PlaylistExportFile: Encodable {
	let playlist: String
	let items: Int
	let path: String
}

/// Writes the export, replacing a file that is there already
func writeExport(_ export: PlaylistExport, to path: String) throws -> PlaylistExportFile {
	let url = fileURL(path)
	do {
		try export.data().write(to: url, options: .atomic)
	} catch {
		throw CLIError("Couldn't write \(url.path(percentEncoded: false)): \(error.localizedDescription)")
	}
	return PlaylistExportFile(playlist: export.title, items: export.items.count, path: url.path(percentEncoded: false))
}

/// Reads a file written by `export`, or standard input for "-"
func readExport(from path: String) throws -> PlaylistExport {
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
		return try PlaylistExport(data: data)
	} catch let error as PlaylistExportError {
		throw CLIError(error.description)
	} catch {
		throw CLIError("\(path == "-" ? "The input" : path) isn't a playlist export: \(error.localizedDescription)")
	}
}

private func fileURL(_ path: String) -> URL {
	URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .notDirectory)
}

enum PlaylistImportTarget {
	case new
	case append(playlist: String, allowDuplicates: Bool)
	/// Replaces the title, description and items
	case replace(playlist: String)
}

struct PlaylistImportSummary: Encodable {
	struct Replacement: Encodable {
		let original: PlaylistExport.Item
		let replacement: TrackSummary
	}
	
	let playlist: PlaylistSummary
	/// Added by their own ID
	let added: Int
	/// Tidal no longer knows their ID, so another track of the same recording was added
	let replaced: [Replacement]
	/// In the playlist already
	let skipped: [PlaylistExport.Item]
	/// Tidal no longer has them
	let missing: [PlaylistExport.Item]
}

@MainActor
func importPlaylist(session: Session, export: PlaylistExport, target: PlaylistImportTarget) async throws -> PlaylistImportSummary {
	let mode: PlaylistImportMode
	switch target {
	case .new:
		mode = .new
	case let .append(reference, allowDuplicates):
		mode = .append(playlistId: try await ownPlaylist(reference: reference, session: session).uuid, duplicates: allowDuplicates)
	case let .replace(reference):
		mode = .replace(playlistId: try await ownPlaylist(reference: reference, session: session).uuid)
	}
	let result: PlaylistImportResult
	do {
		result = try await session.playlistEditing.importPlaylist(export, mode: mode)
	} catch let error as PlaylistImportError {
		throw CLIError(error.description)
	}
	return PlaylistImportSummary(
		playlist: PlaylistSummary(result.playlist, session: session),
		added: result.added.count,
		replaced: result.replaced.map { PlaylistImportSummary.Replacement(original: $0.original, replacement: TrackSummary($0.track)) },
		skipped: result.skipped,
		missing: result.missing
	)
}
