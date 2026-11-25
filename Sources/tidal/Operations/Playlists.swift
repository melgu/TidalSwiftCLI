//
//  Playlists.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 31.10.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import Foundation
import TidalSwiftLib

struct PlaylistDetails: Codable {
	/// Has either a track or a video
	struct Item: Codable {
		/// Starts at 1, as used by remove and move
		let position: Int
		let track: TrackSummary?
		let video: VideoSummary?
	}
	
	let playlist: PlaylistSummary
	let items: [Item]
}

/// The account's own playlists and the ones it added to its favorites
@MainActor
func playlists(session: Session, ownOnly: Bool) async throws -> [PlaylistSummary] {
	guard let favorites = await session.favorites?.playlists(order: .name, orderDirection: .ascending) else {
		throw CLIError("Couldn't load playlists")
	}
	let summaries = favorites.map { PlaylistSummary($0.playlist, session: session) }
	return ownOnly ? summaries.filter(\.isOwn) : summaries
}

@MainActor
func playlistDetails(session: Session, reference: String) async throws -> PlaylistDetails {
	let playlist = try await loadPlaylist(reference: reference, session: session)
	let items = try await playlistItems(of: playlist, session: session)
	return PlaylistDetails(
		playlist: PlaylistSummary(playlist, session: session),
		items: items.enumerated().map { position, item in
			PlaylistDetails.Item(
				position: position + 1,
				track: item.track.map(TrackSummary.init),
				video: item.video.map(VideoSummary.init)
			)
		}
	)
}

@MainActor
private func playlistItems(of playlist: Playlist, session: Session) async throws -> [PlaylistItem] {
	guard let items = await session.playlistItems(playlistId: playlist.uuid) else {
		throw CLIError("Couldn't load the items of \(playlist.title)")
	}
	return items
}

@MainActor
func createPlaylist(session: Session, title: String, description: String) async throws -> PlaylistSummary {
	guard let playlist = await session.playlistEditing.create(title: title, description: description) else {
		throw CLIError("Couldn't create the playlist")
	}
	return PlaylistSummary(playlist, session: session)
}

/// Keeps the description unless a new one is given
@MainActor
func editPlaylist(session: Session, reference: String, title: String?, description: String?) async throws -> PlaylistSummary {
	let playlist = try await ownPlaylist(reference: reference, session: session)
	guard await session.playlistEditing.edit(
		playlistId: playlist.uuid,
		title: title ?? playlist.title,
		description: description ?? playlist.description ?? ""
	) else {
		throw CLIError("Couldn't change \(playlist.title)")
	}
	return PlaylistSummary(try await loadPlaylist(reference: playlist.uuid, session: session), session: session)
}

@MainActor
func deletePlaylist(session: Session, reference: String) async throws -> PlaylistSummary {
	let playlist = try await ownPlaylist(reference: reference, session: session)
	guard await session.playlistEditing.delete(playlistId: playlist.uuid) else {
		throw CLIError("Couldn't delete \(playlist.title)")
	}
	return PlaylistSummary(playlist, session: session)
}

struct PlaylistAddition: Encodable {
	let added: [PlaylistItemSummary]
	/// In the playlist already, or given twice
	let skipped: [PlaylistItemSummary]
}

/// Adds tracks and videos, or every item of albums and playlists
@MainActor
func addToPlaylist(session: Session, reference: String, items: [String], kind: ItemKind?, allowDuplicates: Bool) async throws -> PlaylistAddition {
	let playlist = try await ownPlaylist(reference: reference, session: session)
	var additions: [PlaylistItem] = []
	for item in items {
		additions += try await resolvePlaylistItems(of: TidalLink(reference: item, kind: kind), session: session)
	}
	
	// Tidal skips duplicates without saying so, so they're filtered here to report them
	var skipped: [PlaylistItem] = []
	if !allowDuplicates {
		let existing = try await playlistItems(of: playlist, session: session)
		var seen = Set(existing.map(\.mediaId))
		let all = additions
		additions = []
		for item in all {
			if seen.insert(item.mediaId).inserted {
				additions.append(item)
			} else {
				skipped.append(item)
			}
		}
	}
	
	if !additions.isEmpty {
		guard await session.playlistEditing.addTracks(additions.map(\.mediaId), to: playlist.uuid, duplicate: allowDuplicates) else {
			throw CLIError("Couldn't add the items to \(playlist.title)")
		}
	}
	return PlaylistAddition(added: additions.map(PlaylistItemSummary.init), skipped: skipped.map(PlaylistItemSummary.init))
}

/// Removes the items at the given positions, which start at 1. Returns the removed items.
@MainActor
func removeFromPlaylist(session: Session, reference: String, positions: [Int]) async throws -> [PlaylistItemSummary] {
	let playlist = try await ownPlaylist(reference: reference, session: session)
	let items = try await playlistItems(of: playlist, session: session)
	let positions = Set(positions)
	if let invalid = positions.first(where: { !items.indices.contains($0 - 1) }) {
		throw CLIError("\(playlist.title) has no position \(invalid). It has \(items.count) items.")
	}
	
	// From the back, so earlier positions don't shift
	var removed: [PlaylistItemSummary] = []
	for position in positions.sorted(by: >) {
		guard await session.playlistEditing.removeItem(atIndex: position - 1, from: playlist.uuid) else {
			throw CLIError("Couldn't remove position \(position) from \(playlist.title)")
		}
		removed.insert(PlaylistItemSummary(items[position - 1]), at: 0)
	}
	return removed
}

/// Positions start at 1. Returns the moved item.
@MainActor
func moveInPlaylist(session: Session, reference: String, from: Int, to: Int) async throws -> PlaylistItemSummary {
	let playlist = try await ownPlaylist(reference: reference, session: session)
	let items = try await playlistItems(of: playlist, session: session)
	for position in [from, to] where !items.indices.contains(position - 1) {
		throw CLIError("\(playlist.title) has no position \(position). It has \(items.count) items.")
	}
	guard await session.playlistEditing.moveItem(fromIndex: from - 1, toIndex: to - 1, in: playlist.uuid) else {
		throw CLIError("Couldn't move position \(from) in \(playlist.title)")
	}
	return PlaylistItemSummary(items[from - 1])
}

@MainActor
func ownPlaylist(reference: String, session: Session) async throws -> Playlist {
	let playlist = try await loadPlaylist(reference: reference, session: session)
	guard playlist.creator.id == session.userId else {
		throw CLIError("\(playlist.title) belongs to someone else, so it can't be changed")
	}
	return playlist
}

/// A track or video itself, the tracks of an album, or the items of a playlist
@MainActor
func resolvePlaylistItems(of link: TidalLink, session: Session) async throws -> [PlaylistItem] {
	switch link {
	case .track(let id):
		guard let track = await session.track(trackId: id) else {
			throw CLIError("Couldn't load track \(id)")
		}
		return [.track(track)]
	case .video(let id):
		guard let video = await session.video(videoId: id) else {
			throw CLIError("Couldn't load video \(id)")
		}
		return [.video(video)]
	case .album(let id):
		guard let tracks = await session.albumTracks(albumId: id) else {
			throw CLIError("Couldn't load the tracks of album \(id)")
		}
		return tracks.map(PlaylistItem.track)
	case .playlist(let uuid):
		guard let items = await session.playlistItems(playlistId: uuid) else {
			throw CLIError("Couldn't load the items of playlist \(uuid)")
		}
		return items
	case .artist:
		throw CLIError("Only tracks, videos, albums and playlists can be added to a playlist")
	}
}
