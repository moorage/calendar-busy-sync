import Foundation

struct BookingGitHubRepository: Equatable, Sendable {
    var owner: String
    var name: String

    var slug: String {
        "\(owner)/\(name)"
    }

    var sshRemoteURLString: String {
        "git@github.com:\(slug).git"
    }

    var pagesURL: URL {
        if name.lowercased() == "\(owner.lowercased()).github.io" {
            return URL(string: "https://\(owner).github.io/")!
        }

        return URL(string: "https://\(owner).github.io/\(name)/")!
    }

    init(rawValue: String) throws {
        let value = Self.normalizedRepositoryValue(from: rawValue)
        let parts = value.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2,
              Self.isValidName(parts[0]),
              Self.isValidName(parts[1])
        else {
            throw BookingConfigurationError.invalidField("Use a GitHub repository like owner/repo, a GitHub clone URL, or gh repo clone owner/repo.")
        }

        self.owner = parts[0]
        self.name = parts[1]
    }

    private static func normalizedRepositoryValue(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandValue = repositoryValueFromCommand(trimmed) ?? trimmed

        if let url = URL(string: commandValue),
           let host = url.host,
           host.lowercased() == "github.com"
        {
            return stripGitSuffix(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }

        let scpPrefix = "git@github.com:"
        if commandValue.hasPrefix(scpPrefix) {
            return stripGitSuffix(String(commandValue.dropFirst(scpPrefix.count)))
        }

        return stripGitSuffix(commandValue.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static func repositoryValueFromCommand(_ value: String) -> String? {
        let tokens = shellLikeTokens(from: value)
        guard !tokens.isEmpty else { return nil }

        let normalizedTokens = tokens.first == "$" ? Array(tokens.dropFirst()) : tokens
        guard normalizedTokens.count >= 3 else { return nil }

        if normalizedTokens[0] == "gh", normalizedTokens[1] == "repo" {
            return firstRepositoryArgument(in: Array(normalizedTokens.dropFirst(3)))
        }

        if normalizedTokens[0] == "git", normalizedTokens[1] == "clone" {
            return firstRepositoryArgument(in: Array(normalizedTokens.dropFirst(2)))
        }

        return nil
    }

    private static func firstRepositoryArgument(in arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                return arguments.dropFirst(index + 1).first
            }
            if argument.hasPrefix("-") {
                index += argument.contains("=") ? 1 : 2
                continue
            }
            return argument
        }
        return nil
    }

    private static func shellLikeTokens(from value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for character in value {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func stripGitSuffix(_ value: String) -> String {
        value.hasSuffix(".git") ? String(value.dropLast(4)) : value
    }

    private static func isValidName(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }
}

struct BookingGitHubDeployKey: Equatable, Sendable {
    var publicKey: String
    var privateKeyPEM: String
    var fingerprint: String
}

struct BookingGitCommand: Equatable, Sendable {
    var executableURL: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL?
}

struct BookingGitCommandResult: Equatable, Sendable {
    var standardOutput: String
    var standardError: String
}

protocol BookingGitCommandRunning: Sendable {
    func run(_ command: BookingGitCommand) async throws -> BookingGitCommandResult
}

enum BookingGitCommandError: LocalizedError, Equatable {
    case failed(
        executable: String,
        arguments: [String],
        status: Int32,
        standardOutput: String,
        standardError: String
    )

    var errorDescription: String? {
        switch self {
        case let .failed(executable, arguments, status, standardOutput, standardError):
            let output = standardError.isEmpty ? standardOutput : standardError
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = ([executable] + arguments).joined(separator: " ")
            if detail.isEmpty {
                return "\(command) failed with status \(status)."
            }
            return "\(command) failed with status \(status): \(detail)"
        }
    }
}

#if os(macOS)
struct ProcessBookingGitCommandRunner: BookingGitCommandRunning {
    func run(_ command: BookingGitCommand) async throws -> BookingGitCommandResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.currentDirectoryURL = command.workingDirectory

            var environment = ProcessInfo.processInfo.environment
            for (key, value) in command.environment {
                environment[key] = value
            }
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let standardOutput = String(data: outputData, encoding: .utf8) ?? ""
            let standardError = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw BookingGitCommandError.failed(
                    executable: command.executableURL.path,
                    arguments: command.arguments,
                    status: process.terminationStatus,
                    standardOutput: standardOutput,
                    standardError: standardError
                )
            }

            return BookingGitCommandResult(
                standardOutput: standardOutput,
                standardError: standardError
            )
        }.value
    }
}

nonisolated enum BookingGitHubDeployKeyGenerator {
    static func generate(
        repository: BookingGitHubRepository,
        fileManager: FileManager = .default,
        commandRunner: any BookingGitCommandRunning = ProcessBookingGitCommandRunner()
    ) async throws -> BookingGitHubDeployKey {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("booking-github-key-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        let privateKeyURL = tempRoot.appendingPathComponent("deploy-key")
        let publicKeyURL = tempRoot.appendingPathComponent("deploy-key.pub")
        _ = try await commandRunner.run(
            BookingGitCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/ssh-keygen"),
                arguments: [
                    "-t", "ed25519",
                    "-C", "calendar-busy-sync:\(repository.slug)",
                    "-f", privateKeyURL.path,
                    "-N", "",
                ],
                environment: [:],
                workingDirectory: tempRoot
            )
        )

        let fingerprintResult = try await commandRunner.run(
            BookingGitCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/ssh-keygen"),
                arguments: ["-lf", publicKeyURL.path],
                environment: [:],
                workingDirectory: tempRoot
            )
        )
        let fingerprint = fingerprintResult.standardOutput
            .split(whereSeparator: \.isWhitespace)
            .dropFirst()
            .first
            .map(String.init) ?? ""

        guard let privateKey = String(data: try Data(contentsOf: privateKeyURL), encoding: .utf8),
              let publicKey = String(data: try Data(contentsOf: publicKeyURL), encoding: .utf8)
        else {
            throw BookingConfigurationError.invalidField("The deploy key could not be read after generation.")
        }

        return BookingGitHubDeployKey(
            publicKey: publicKey.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKey.trimmingCharacters(in: .whitespacesAndNewlines),
            fingerprint: fingerprint
        )
    }
}
#endif

nonisolated enum BookingGitHubPublisher {
    struct PublishSummary: Equatable, Sendable {
        var uploadedCount: Int
        var skippedCount: Int
        var overwrittenCount: Int
        var remoteChangedPaths: [String]

        var changedCount: Int {
            uploadedCount + overwrittenCount
        }

        var didChangeRemote: Bool {
            changedCount > 0
        }
    }

    struct FilePublishPlan: Equatable, Sendable {
        var shouldUpload: Bool
        var isOverwrite: Bool
        var remoteChangedPath: String?
    }

    static func publishDirectory(
        at directory: URL,
        repository: BookingGitHubRepository,
        branch: String,
        privateKeyPEM: String,
        fileManager: FileManager = .default,
        commandRunner: (any BookingGitCommandRunning)? = nil,
        workingDirectoryRoot: URL? = nil
    ) async throws -> PublishSummary {
        #if os(macOS)
        let files = try localFiles(in: directory, fileManager: fileManager)
        guard !files.isEmpty else {
            throw BookingConfigurationError.invalidField("Generate page files before publishing.")
        }

        let normalizedBranch = try normalizeBranch(branch)
        let tempRoot = (workingDirectoryRoot ?? fileManager.temporaryDirectory)
            .appendingPathComponent("booking-github-publish-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        let privateKeyURL = tempRoot.appendingPathComponent("deploy-key")
        try writePrivateKey(privateKeyPEM, to: privateKeyURL, fileManager: fileManager)
        let environment = gitSSHEngineEnvironment(privateKeyURL: privateKeyURL)
        let runner = commandRunner ?? ProcessBookingGitCommandRunner()
        let worktreeURL = tempRoot.appendingPathComponent(repository.name, isDirectory: true)

        _ = try await runner.run(
            BookingGitCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["clone", repository.sshRemoteURLString, worktreeURL.path],
                environment: environment,
                workingDirectory: tempRoot
            )
        )
        try await prepareBranch(
            normalizedBranch,
            in: worktreeURL,
            environment: environment,
            runner: runner
        )

        let localRelativePaths = files.map(\.relativePath)
        let remoteFiles = try localFiles(in: worktreeURL, fileManager: fileManager)
        let unexpectedPaths = unexpectedRootContentPaths(
            localPaths: localRelativePaths,
            remotePaths: remoteFiles.map(\.relativePath)
        )
        if let firstUnexpectedPath = unexpectedPaths.first {
            throw BookingConfigurationError.invalidField(
                "Use an empty GitHub Pages repository. Remove \(firstUnexpectedPath) before publishing."
            )
        }

        let plan = try publishPlan(
            files: files,
            remoteRoot: worktreeURL,
            fileManager: fileManager
        )
        for file in files where plan[file.relativePath]?.shouldUpload == true {
            let destination = worktreeURL.appendingPathComponent(file.relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: file.url, to: destination)
        }

        let status = try await runner.run(
            BookingGitCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["status", "--porcelain"],
                environment: environment,
                workingDirectory: worktreeURL
            )
        )
        guard !status.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return publishSummary(from: plan)
        }

        _ = try await runner.run(
            BookingGitCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["add", "--all"],
                environment: environment,
                workingDirectory: worktreeURL
            )
        )
        _ = try await runner.run(
            BookingGitCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: [
                    "-c", "user.name=Calendar Busy Sync",
                    "-c", "user.email=calendar-busy-sync@users.noreply.github.com",
                    "commit",
                    "-m", "Publish booking page files",
                ],
                environment: environment,
                workingDirectory: worktreeURL
            )
        )
        _ = try await runner.run(
            BookingGitCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["push", "origin", "HEAD:\(normalizedBranch)"],
                environment: environment,
                workingDirectory: worktreeURL
            )
        )

        return publishSummary(from: plan)
        #else
        throw BookingConfigurationError.invalidField("GitHub publishing from the app is available on macOS.")
        #endif
    }

    static func verifyDeployKey(
        repository: BookingGitHubRepository,
        privateKeyPEM: String,
        fileManager: FileManager = .default,
        commandRunner: (any BookingGitCommandRunning)? = nil
    ) async throws {
        #if os(macOS)
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("booking-github-verify-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        let privateKeyURL = tempRoot.appendingPathComponent("deploy-key")
        try writePrivateKey(privateKeyPEM, to: privateKeyURL, fileManager: fileManager)
        _ = try await (commandRunner ?? ProcessBookingGitCommandRunner()).run(
            BookingGitCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["ls-remote", repository.sshRemoteURLString, "HEAD"],
                environment: gitSSHEngineEnvironment(privateKeyURL: privateKeyURL),
                workingDirectory: tempRoot
            )
        )
        #else
        throw BookingConfigurationError.invalidField("GitHub publishing from the app is available on macOS.")
        #endif
    }

    static func unexpectedRootContentPaths(
        localPaths: [String],
        remotePaths: [String]
    ) -> [String] {
        let localPathSet = Set(localPaths)
        return Set(remotePaths)
            .subtracting(localPathSet)
            .sorted()
    }

    static func filePublishPlan(
        relativePath: String,
        localData: Data,
        remoteData: Data?
    ) -> FilePublishPlan {
        guard let remoteData else {
            return FilePublishPlan(
                shouldUpload: true,
                isOverwrite: false,
                remoteChangedPath: nil
            )
        }

        guard remoteData != localData else {
            return FilePublishPlan(
                shouldUpload: false,
                isOverwrite: false,
                remoteChangedPath: nil
            )
        }

        return FilePublishPlan(
            shouldUpload: true,
            isOverwrite: true,
            remoteChangedPath: relativePath
        )
    }

    static func publishPlan(
        files: [(url: URL, relativePath: String)],
        remoteRoot: URL,
        fileManager: FileManager
    ) throws -> [String: FilePublishPlan] {
        var plan: [String: FilePublishPlan] = [:]
        for file in files {
            let localData = try Data(contentsOf: file.url)
            let remoteURL = remoteRoot.appendingPathComponent(file.relativePath)
            let remoteData = fileManager.fileExists(atPath: remoteURL.path)
                ? try Data(contentsOf: remoteURL)
                : nil
            plan[file.relativePath] = filePublishPlan(
                relativePath: file.relativePath,
                localData: localData,
                remoteData: remoteData
            )
        }
        return plan
    }

    private static func localFiles(
        in directory: URL,
        fileManager: FileManager
    ) throws -> [(url: URL, relativePath: String)] {
        let basePath = directory.resolvingSymlinksInPath().path
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw BookingConfigurationError.invalidField("Page files folder could not be read.")
        }

        var files: [(url: URL, relativePath: String)] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            let filePath = fileURL.resolvingSymlinksInPath().path
            let relativePathPrefix = "\(basePath)/"
            guard filePath.hasPrefix(relativePathPrefix) else {
                throw BookingConfigurationError.invalidField("Page files folder could not be read.")
            }
            let relativePath = String(filePath.dropFirst(relativePathPrefix.count))
            files.append((url: fileURL, relativePath: relativePath))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    #if os(macOS)
    private static func prepareBranch(
        _ branch: String,
        in worktreeURL: URL,
        environment: [String: String],
        runner: any BookingGitCommandRunning
    ) async throws {
        do {
            _ = try await runner.run(
                BookingGitCommand(
                    executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                    arguments: ["rev-parse", "--verify", "HEAD"],
                    environment: environment,
                    workingDirectory: worktreeURL
                )
            )
            do {
                _ = try await runner.run(
                    BookingGitCommand(
                        executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                        arguments: ["checkout", branch],
                        environment: environment,
                        workingDirectory: worktreeURL
                    )
                )
            } catch {
                _ = try await runner.run(
                    BookingGitCommand(
                        executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                        arguments: ["checkout", "-B", branch],
                        environment: environment,
                        workingDirectory: worktreeURL
                    )
                )
            }
        } catch {
            _ = try await runner.run(
                BookingGitCommand(
                    executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                    arguments: ["checkout", "-B", branch],
                    environment: environment,
                    workingDirectory: worktreeURL
                )
            )
        }
    }

    private static func writePrivateKey(
        _ privateKeyPEM: String,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let normalizedPrivateKey = privateKeyPEM.hasSuffix("\n") ? privateKeyPEM : "\(privateKeyPEM)\n"
        try Data(normalizedPrivateKey.utf8).write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func gitSSHEngineEnvironment(privateKeyURL: URL) -> [String: String] {
        [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_SSH_COMMAND": "/usr/bin/ssh -i \(shellQuoted(privateKeyURL.path)) -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new",
        ]
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    #endif

    private static func normalizeBranch(_ branch: String) throws -> String {
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBranch = trimmedBranch.isEmpty ? "main" : trimmedBranch
        guard normalizedBranch.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]*$"#, options: .regularExpression) != nil,
              !normalizedBranch.contains(".."),
              !normalizedBranch.hasSuffix("/")
        else {
            throw BookingConfigurationError.invalidField("Use a Git branch like main or gh-pages.")
        }
        return normalizedBranch
    }

    private static func publishSummary(from plan: [String: FilePublishPlan]) -> PublishSummary {
        let values = Array(plan.values)
        return PublishSummary(
            uploadedCount: values.filter { $0.shouldUpload && !$0.isOverwrite }.count,
            skippedCount: values.filter { !$0.shouldUpload }.count,
            overwrittenCount: values.filter(\.isOverwrite).count,
            remoteChangedPaths: values.compactMap(\.remoteChangedPath).sorted()
        )
    }
}
