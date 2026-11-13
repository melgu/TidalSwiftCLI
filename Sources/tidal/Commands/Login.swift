//
//  Login.swift
//  TidalSwiftCLI
//
//  Created by Melvin Gundlach on 31.10.26.
//  Copyright © 2026 Melvin Gundlach. All rights reserved.
//

import ArgumentParser
import Foundation
import TidalSwiftLib

struct Login: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Log in to Tidal in the browser.",
		discussion: """
			There are two logins, which get different qualities:
			  Dolby Atmos (--atmos)  High (FLAC 16 bit / 44.1 kHz) and Dolby Atmos. Approve the login in the browser.
			  Hi-Res (--hi-res)      Low, High and Max (FLAC up to 24 bit / 192 kHz), but no Dolby Atmos. \
			Log in in the browser, then paste the address of the error page Tidal shows.
			Without either option, the command asks. Logging in with the other one as well keeps both, \
			so downloads get Hi-Res and Dolby Atmos.
			"""
	)
	
	enum Choice: EnumerableFlag {
		case atmos
		case hiRes
		
		static func help(for value: Choice) -> ArgumentHelp? {
			switch value {
			case .atmos: "Log in with the Dolby Atmos login."
			case .hiRes: "Log in with the Hi-Res login."
			}
		}
	}
	
	@Flag var choice: Choice?
	
	@MainActor
	func run() async throws {
		let session = makeSession()
		// A stored login of the other kind stays, and the new one is added to it
		_ = session.loadSession()
		
		switch try choice ?? ask(existing: session.loginKinds) {
		case .atmos:
			try await logInWithDevice(session: session)
		case .hiRes:
			try await logInWithPKCE(session: session)
		}
		
		session.saveConfig()
		let account = try await account(session: session)
		print("Logged in as \(account.username) (\(account.logins.joined(separator: " and ")))")
	}
	
	/// Asks on the terminal which login to use, marking the ones that exist
	@MainActor
	private func ask(existing: Set<LoginKind>) throws -> Choice {
		guard isatty(STDIN_FILENO) != 0 else {
			throw CLIError("Choose the login with --atmos or --hi-res.")
		}
		func mark(_ kind: LoginKind) -> String {
			existing.contains(kind) ? " (logged in)" : ""
		}
		printToStderr("""
			Which login?
			  1  Dolby Atmos\(mark(.device)): High (FLAC 16 bit / 44.1 kHz) and Dolby Atmos
			  2  Hi-Res\(mark(.pkce)): Low, High and Max (FLAC up to 24 bit / 192 kHz), but no Dolby Atmos
			""")
		while true {
			FileHandle.standardError.write(Data("Choose 1 or 2: ".utf8))
			guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
				throw CLIError("No login chosen")
			}
			switch answer {
			case "1", "atmos", "dolby atmos":
				return .atmos
			case "2", "hi-res", "hires":
				return .hiRes
			default:
				continue
			}
		}
	}
	
	@MainActor
	private func logInWithDevice(session: Session) async throws {
		for await state in session.startAuthorization() {
			switch state {
			case .waiting, .success:
				break
			case .pending(let loginUrl, let expiration):
				printToStderr("Open this link and approve the login:\n\(loginUrl.absoluteString)")
				printToStderr("Waiting until \(expiration.formatted(date: .omitted, time: .shortened)) …")
			case .failure(let error):
				throw CLIError("Login failed: \(loginFailureReason(error))")
			}
		}
	}
	
	@MainActor
	private func logInWithPKCE(session: Session) async throws {
		let authorization = session.startPKCEAuthorization()
		printToStderr("Open this link and log in:\n\(authorization.loginUrl.absoluteString)")
		printToStderr("Tidal then shows an error page. Paste its address here:")
		let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard let redirectUrl = URL(string: line), PKCEAuthorization.isRedirect(redirectUrl) else {
			throw CLIError("That's not the address of the error page. Run `tidal login --hi-res` again.")
		}
		do {
			try await session.finishPKCEAuthorization(authorization, redirectUrl: redirectUrl)
		} catch {
			throw CLIError("Login failed: \(loginFailureReason(error))")
		}
	}
}

private func loginFailureReason(_ error: Error) -> String {
	switch error as? SessionError {
	case .differentAccount:
		"This is another Tidal account than the one already logged in. Run `tidal logout` first to switch accounts."
	case .invalidCredentials(let description):
		description ?? "Tidal rejected the login."
	case .network:
		"Couldn't reach Tidal. Check your internet connection."
	default:
		error.localizedDescription
	}
}

struct Logout: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Remove the stored logins."
	)
	
	@MainActor
	func run() async throws {
		makeSession().logout()
		print("Logged out")
	}
}
