import Foundation
import Security

struct BookingVercelProjectReference: Equatable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BookingConfigurationError.invalidField("Add a Vercel project ID or name.")
        }
        guard trimmed.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw BookingConfigurationError.invalidField("Use a Vercel project ID or name without spaces or slashes.")
        }
        self.rawValue = trimmed
    }
}

struct BookingVercelTeamReference: Equatable, Sendable {
    let rawValue: String

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.rawValue = trimmed
    }

    var queryItem: URLQueryItem {
        if rawValue.hasPrefix("team_") {
            return URLQueryItem(name: "teamId", value: rawValue)
        }
        return URLQueryItem(name: "slug", value: rawValue)
    }
}

struct BookingVercelDeploymentConfiguration: Equatable, Sendable {
    let token: String
    let project: BookingVercelProjectReference
    let team: BookingVercelTeamReference?
    let allowedOrigin: String
    let inboxAdminToken: String

    init(
        token: String,
        project: BookingVercelProjectReference,
        team: BookingVercelTeamReference?,
        allowedOrigin: String,
        inboxAdminToken: String
    ) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw BookingConfigurationError.invalidField("Add a Vercel token.")
        }
        let trimmedOrigin = allowedOrigin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOrigin.isEmpty else {
            throw BookingConfigurationError.invalidField("Add a booking page URL before deploying the Vercel inbox.")
        }
        let trimmedAdminToken = inboxAdminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAdminToken.isEmpty else {
            throw BookingConfigurationError.invalidField("Create an inbox admin token before deploying the Vercel inbox.")
        }

        self.token = trimmedToken
        self.project = project
        self.team = team
        self.allowedOrigin = trimmedOrigin
        self.inboxAdminToken = trimmedAdminToken
    }
}

struct BookingVercelDeploymentResult: Equatable, Sendable {
    let deploymentID: String
    let inboxURL: URL
    let blobStoreID: String
}

struct BookingVercelDeploymentClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.vercel.com")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func deploy(
        configuration: BookingVercelDeploymentConfiguration,
        templateDirectory: URL,
        fileManager: FileManager = .default
    ) async throws -> BookingVercelDeploymentResult {
        let project = try await resolveProject(configuration: configuration)
        let blobStore = try await ensureBlobStore(
            configuration: configuration,
            project: project
        )
        try await upsertEnvironment(configuration: configuration)
        let files = try Self.deploymentFiles(
            from: templateDirectory,
            fileManager: fileManager
        )
        return try await createDeployment(
            configuration: configuration,
            files: files,
            blobStoreID: blobStore.id
        )
    }

    func resolveProject(
        configuration: BookingVercelDeploymentConfiguration
    ) async throws -> Project {
        let request = try authorizedRequest(
            path: "/v9/projects/\(Self.pathComponent(configuration.project.rawValue))",
            method: "GET",
            token: configuration.token,
            team: configuration.team
        )
        return try await send(request, expecting: Project.self)
    }

    func ensureBlobStore(
        configuration: BookingVercelDeploymentConfiguration,
        project: Project
    ) async throws -> BlobStore {
        let stores = try await listBlobStores(configuration: configuration)
        let expectedStoreName = Self.blobStoreName(for: configuration.project.rawValue)
        if let existingStore = stores.first(where: { store in
            (store.type == nil || store.type == "blob")
                && (store.projectsMetadata?.contains { $0.projectID == project.id } == true)
        }) {
            return existingStore
        }
        if let unconnectedStore = stores.first(where: { store in
            (store.type == nil || store.type == "blob") && store.name == expectedStoreName
        }) {
            try await connectBlobStore(
                unconnectedStore,
                project: project,
                configuration: configuration
            )
            return unconnectedStore
        }

        let createdStore = try await createBlobStore(configuration: configuration)
        try await connectBlobStore(
            createdStore,
            project: project,
            configuration: configuration
        )
        return createdStore
    }

    func listBlobStores(
        configuration: BookingVercelDeploymentConfiguration
    ) async throws -> [BlobStore] {
        let request = try authorizedRequest(
            path: "/v1/storage/stores",
            method: "GET",
            token: configuration.token,
            team: configuration.team
        )
        let response = try await send(request, expecting: ListBlobStoresResponse.self)
        return response.stores
    }

    func createBlobStore(
        configuration: BookingVercelDeploymentConfiguration
    ) async throws -> BlobStore {
        var request = try authorizedRequest(
            path: "/v1/storage/stores/blob",
            method: "POST",
            token: configuration.token,
            team: configuration.team
        )
        request.httpBody = try Self.encoder.encode(
            CreateBlobStoreBody(
                name: Self.blobStoreName(for: configuration.project.rawValue)
            )
        )
        let response = try await send(request, expecting: CreateBlobStoreResponse.self)
        return response.store
    }

    func connectBlobStore(
        _ store: BlobStore,
        project: Project,
        configuration: BookingVercelDeploymentConfiguration
    ) async throws {
        var request = try authorizedRequest(
            path: "/v1/storage/stores/\(Self.pathComponent(store.id))/connections",
            method: "POST",
            token: configuration.token,
            team: configuration.team
        )
        request.httpBody = try Self.encoder.encode(
            ConnectBlobStoreBody(
                envVarEnvironments: ["production"],
                projectId: project.id
            )
        )
        try await sendIgnoringBody(request)
    }

    func upsertEnvironment(configuration: BookingVercelDeploymentConfiguration) async throws {
        var request = try authorizedRequest(
            path: "/v10/projects/\(Self.pathComponent(configuration.project.rawValue))/env",
            method: "POST",
            token: configuration.token,
            team: configuration.team,
            queryItems: [URLQueryItem(name: "upsert", value: "true")]
        )
        let body = [
            EnvironmentVariable(
                key: "ALLOWED_ORIGIN",
                value: configuration.allowedOrigin,
                type: "plain"
            ),
            EnvironmentVariable(
                key: "INBOX_ADMIN_TOKEN",
                value: configuration.inboxAdminToken,
                type: "encrypted"
            ),
            EnvironmentVariable(
                key: "MAX_PENDING_REQUESTS",
                value: "100",
                type: "plain"
            ),
        ]
        request.httpBody = try Self.encoder.encode(body)
        try await sendIgnoringBody(request)
    }

    func createDeployment(
        configuration: BookingVercelDeploymentConfiguration,
        files: [DeploymentFile],
        blobStoreID: String
    ) async throws -> BookingVercelDeploymentResult {
        var request = try authorizedRequest(
            path: "/v13/deployments",
            method: "POST",
            token: configuration.token,
            team: configuration.team
        )
        request.httpBody = try Self.encoder.encode(
            CreateDeploymentBody(
                name: configuration.project.rawValue,
                project: configuration.project.rawValue,
                files: files
            )
        )
        let response = try await send(request, expecting: CreateDeploymentResponse.self)
        guard let inboxURL = Self.deploymentURL(from: response.url) else {
            throw BookingVercelDeploymentError.invalidDeploymentURL
        }

        return BookingVercelDeploymentResult(
            deploymentID: response.id,
            inboxURL: inboxURL,
            blobStoreID: blobStoreID
        )
    }

    static func defaultTemplateDirectory(fileManager: FileManager = .default) throws -> URL {
        let bundledNames = ["booking-relay-vercel", "vercel"]
        for name in bundledNames {
            if let bundledTemplate = Bundle.main.url(forResource: name, withExtension: nil),
               isTemplateDirectory(bundledTemplate, fileManager: fileManager) {
                return bundledTemplate
            }
        }

        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let repositoryTemplate = workingDirectory
            .appendingPathComponent("templates", isDirectory: true)
            .appendingPathComponent("booking-relay", isDirectory: true)
            .appendingPathComponent("vercel", isDirectory: true)
        if isTemplateDirectory(repositoryTemplate, fileManager: fileManager) {
            return repositoryTemplate
        }

        throw BookingConfigurationError.invalidField("The Vercel inbox template is missing from this app.")
    }

    static func deploymentFiles(
        from templateDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [DeploymentFile] {
        guard isTemplateDirectory(templateDirectory, fileManager: fileManager) else {
            throw BookingConfigurationError.invalidField("The Vercel inbox template is missing required files.")
        }

        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: templateDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            throw BookingConfigurationError.invalidField("The Vercel inbox template could not be read.")
        }

        var files: [DeploymentFile] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }
            let relativePath = fileURL.path
                .dropFirst(templateDirectory.path.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relativePath.isEmpty else { continue }
            let data = try Data(contentsOf: fileURL)
            files.append(
                DeploymentFile(
                    file: relativePath,
                    data: data.base64EncodedString()
                )
            )
        }

        return files.sorted { $0.file < $1.file }
    }

    private func authorizedRequest(
        path: String,
        method: String,
        token: String,
        team: BookingVercelTeamReference?,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems + [team?.queryItem].compactMap { $0 }
        guard let url = components?.url else {
            throw BookingConfigurationError.invalidField("The Vercel API request could not be created.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func sendIgnoringBody(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        expecting type: Response.Type
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try Self.decoder.decode(Response.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookingVercelDeploymentError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? Self.decoder.decode(ErrorResponse.self, from: data).error.message)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw BookingVercelDeploymentError.api(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private static func isTemplateDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) -> Bool {
        fileManager.fileExists(atPath: directory.appendingPathComponent("package.json").path)
            && fileManager.fileExists(atPath: directory.appendingPathComponent("vercel.json").path)
            && fileManager.fileExists(atPath: directory.appendingPathComponent("api/healthz.js").path)
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func deploymentURL(from value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(value)")
    }

    private static func blobStoreName(for projectName: String) -> String {
        let normalized = projectName
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber {
                    return character
                }
                return "-"
            }
        let collapsed = String(normalized)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let suffix = collapsed.isEmpty ? "inbox" : collapsed
        return "calendar-busy-sync-\(suffix)"
    }

    static func generateAdminToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw BookingConfigurationError.invalidField("The inbox admin token could not be generated.")
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

extension BookingVercelDeploymentClient {
    struct DeploymentFile: Codable, Equatable, Sendable {
        var file: String
        var data: String
        var encoding = "base64"
    }

    struct Project: Codable, Equatable, Sendable {
        var id: String
        var name: String
    }

    struct BlobStore: Codable, Equatable, Sendable {
        var id: String
        var name: String?
        var type: String?
        var projectsMetadata: [ProjectMetadata]?
    }

    struct ProjectMetadata: Codable, Equatable, Sendable {
        var projectID: String

        enum CodingKeys: String, CodingKey {
            case projectID = "projectId"
        }
    }
}

private extension BookingVercelDeploymentClient {
    struct EnvironmentVariable: Encodable {
        var key: String
        var value: String
        var type: String
        var target = ["production"]
    }

    struct CreateDeploymentBody: Encodable {
        var name: String
        var project: String
        var target = "production"
        var files: [DeploymentFile]
    }

    struct CreateDeploymentResponse: Decodable {
        var id: String
        var url: String
    }

    struct ListBlobStoresResponse: Decodable {
        var stores: [BlobStore]
    }

    struct CreateBlobStoreBody: Encodable {
        var name: String
        var region = "iad1"
        var access = "public"
    }

    struct CreateBlobStoreResponse: Decodable {
        var store: BlobStore
    }

    struct ConnectBlobStoreBody: Encodable {
        var envVarEnvironments: [String]
        var projectId: String
        var type = "integration"
    }

    struct ErrorResponse: Decodable {
        var error: ErrorDetail
    }

    struct ErrorDetail: Decodable {
        var message: String
    }

}

enum BookingVercelDeploymentError: LocalizedError, Equatable {
    case api(statusCode: Int, message: String)
    case invalidResponse
    case invalidDeploymentURL

    var errorDescription: String? {
        switch self {
        case let .api(statusCode, message):
            return "Vercel returned \(statusCode): \(message)"
        case .invalidResponse:
            return "Vercel returned a response this app could not read."
        case .invalidDeploymentURL:
            return "Vercel did not return a deployment URL."
        }
    }

    var isAuthenticationFailure: Bool {
        if case let .api(statusCode, _) = self {
            return statusCode == 401
        }
        return false
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
