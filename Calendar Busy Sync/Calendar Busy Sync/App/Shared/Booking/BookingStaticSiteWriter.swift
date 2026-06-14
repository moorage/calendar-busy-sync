import Foundation

struct BookingStaticSiteWriteSummary: Equatable, Sendable {
    var outputDirectory: URL
    var writtenRelativePaths: [String]
}

enum BookingStaticSiteWriter {
    static func write(
        artifacts: [BookingStaticSiteArtifact],
        to outputDirectory: URL,
        templateDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> BookingStaticSiteWriteSummary {
        if let templateDirectory = try Self.validTemplateDirectory(templateDirectory, fileManager: fileManager)
            ?? Self.defaultTemplateDirectory(fileManager: fileManager) {
            if fileManager.fileExists(atPath: outputDirectory.path) {
                try fileManager.removeItem(at: outputDirectory)
            }
            try fileManager.copyItem(at: templateDirectory, to: outputDirectory)
        } else {
            try fileManager.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        }

        var writtenPaths: [String] = []
        for artifact in artifacts {
            let destination = outputDirectory.appendingPathComponent(artifact.relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try artifact.data.write(to: destination, options: .atomic)
            writtenPaths.append(artifact.relativePath)
        }

        return BookingStaticSiteWriteSummary(
            outputDirectory: outputDirectory,
            writtenRelativePaths: writtenPaths.sorted()
        )
    }

    @discardableResult
    static func seedEditableTemplate(
        at destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let editableIndex = destinationDirectory.appendingPathComponent("index.html")
        if fileManager.fileExists(atPath: editableIndex.path) {
            return false
        }

        if fileManager.fileExists(atPath: destinationDirectory.path) {
            throw BookingConfigurationError.invalidField(
                "Editable booking template folder exists but is missing index.html."
            )
        }

        guard let seedDirectory = Self.defaultTemplateDirectory(fileManager: fileManager) else {
            throw BookingConfigurationError.invalidField(
                "Booking page template is missing from the app bundle."
            )
        }

        try fileManager.createDirectory(
            at: destinationDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: seedDirectory, to: destinationDirectory)
        return true
    }

    private static func validTemplateDirectory(
        _ templateDirectory: URL?,
        fileManager: FileManager
    ) throws -> URL? {
        guard let templateDirectory else {
            return nil
        }

        guard fileManager.fileExists(atPath: templateDirectory.appendingPathComponent("index.html").path) else {
            throw BookingConfigurationError.invalidField(
                "Editable booking template folder is missing index.html."
            )
        }

        return templateDirectory
    }

    private static func defaultTemplateDirectory(fileManager: FileManager) -> URL? {
        if let bundledTemplate = Bundle.main.url(forResource: "booking-site", withExtension: nil),
           fileManager.fileExists(atPath: bundledTemplate.appendingPathComponent("index.html").path) {
            return bundledTemplate
        }

        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let repositoryTemplate = workingDirectory
            .appendingPathComponent("templates", isDirectory: true)
            .appendingPathComponent("booking-site", isDirectory: true)
        if fileManager.fileExists(atPath: repositoryTemplate.appendingPathComponent("index.html").path) {
            return repositoryTemplate
        }

        return nil
    }
}
