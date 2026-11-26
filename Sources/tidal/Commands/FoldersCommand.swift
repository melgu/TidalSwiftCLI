//
//  FoldersCommand.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 26.11.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import ArgumentParser
import Foundation
import TidalSwiftLib

struct Folders: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "List and arrange the folders of your playlists. Folders are given by their ID or name.",
		subcommands: [
			List.self,
			Create.self,
			Rename.self,
			Move.self,
			Delete.self
		]
	)
	
	struct List: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "List your folders with the playlists in them, your own and the ones in your favorites."
		)
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let tree = try await folderTree(session: session)
			if output.json {
				try printJSON(tree)
				return
			}
			func printContents(folders: [FolderSummary], playlists: [PlaylistSummary], indent: String) {
				for folder in folders {
					print("\(indent)\(folder.line)")
					printContents(folders: folder.folders, playlists: folder.playlists, indent: indent + "  ")
				}
				playlists.forEach { print("\(indent)\($0.line)") }
			}
			printContents(folders: tree.folders, playlists: tree.playlists, indent: "")
		}
	}
	
	struct Create: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Create a folder."
		)
		
		@Argument(help: "The name.")
		var name: String
		
		@Option(name: .customLong("in"), help: "The folder to create it in. Without, it's created at the root.")
		var parent: String?
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let creation = try await createFolder(session: session, name: name, in: parent)
			if output.json {
				try printJSON(creation)
			} else {
				print("Created \(creation.folder.line)" + (creation.parent.map { " in \($0.name)" } ?? ""))
			}
		}
	}
	
	struct Rename: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Rename a folder."
		)
		
		@Argument(help: "The folder.")
		var folder: String
		
		@Argument(help: "The new name.")
		var name: String
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let rename = try await renameFolder(session: session, reference: folder, to: name)
			if output.json {
				try printJSON(rename)
			} else {
				print("Renamed \(rename.from) to \(rename.to)")
			}
		}
	}
	
	struct Move: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Move playlists and folders into a folder, or to the root.",
			discussion: "A playlist is in one folder only, so moving it takes it out of its current one. A folder takes what's in it along."
		)
		
		@Argument(help: "Playlists, as links or UUIDs, and folders, by ID or name. Your own playlists and the ones in your favorites.")
		var items: [String]
		
		@Option(help: "The folder to move them into.")
		var into: String?
		
		@Flag(help: "Move them to the root, out of any folder.")
		var root = false
		
		@OptionGroup var output: OutputOptions
		
		func validate() throws {
			if (into == nil) == !root {
				throw ValidationError("Pass either --into or --root.")
			}
		}
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let result = try await moveToFolder(session: session, items: items, into: into)
			if output.json {
				try printJSON(result)
				return
			}
			print("Moved to \(result.folder?.name ?? "the root"):")
			result.folders.forEach { print($0.line) }
			result.playlists.forEach { print($0.line) }
		}
	}
	
	struct Delete: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			abstract: "Delete a folder. The playlists and folders in it are kept and moved to the root."
		)
		
		@Argument(help: "The folder.")
		var folder: String
		
		@OptionGroup var output: OutputOptions
		
		@MainActor
		func run() async throws {
			let session = try loggedInSession()
			let deletion = try await deleteFolder(session: session, reference: folder)
			if output.json {
				try printJSON(deletion)
				return
			}
			print("Deleted \(deletion.folder.line)")
			if !deletion.movedFolders.isEmpty || !deletion.movedPlaylists.isEmpty {
				print("Moved to the root:")
				deletion.movedFolders.forEach { print($0.line) }
				deletion.movedPlaylists.forEach { print($0.line) }
			}
		}
	}
}

extension FolderReference {
	var line: String {
		"\(id)  \(name)/"
	}
}

extension FolderSummary {
	var line: String {
		"\(id)  \(name)/"
	}
}
