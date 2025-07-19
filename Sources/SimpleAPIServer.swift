import Foundation
import Network
import Photos

class SimpleAPIServer {
    static let shared = SimpleAPIServer()
    
    private var listener: NWListener?
    private let port: UInt16 = 44556
    private let photosManager = PhotosManager.shared
    private let fileExporter = FileExporter.shared
    private let queue = DispatchQueue(label: "api.server.queue")
    
    private init() {}
    
    // MARK: - Server Management
    
    func start() -> Bool {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: queue)
            return true
        } catch {
            print("Failed to start server: \(error)")
            return false
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    var isRunning: Bool {
        return listener?.state == .ready
    }
    
    var serverURL: String {
        return "http://localhost:\(port)"
    }
    
    // MARK: - Connection Handling
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            if let error = error {
                print("Connection error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                self?.processRequest(data: data, connection: connection)
                // Don't continue receiving after processing a request
                return
            }
            
            if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func processRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendError(connection: connection, message: "Invalid request")
            return
        }
        
        let lines = requestString.components(separatedBy: .newlines)
        guard let requestLine = lines.first else {
            sendError(connection: connection, message: "Invalid request line")
            return
        }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            sendError(connection: connection, message: "Invalid request format")
            return
        }
        
        let method = components[0]
        let path = components[1]
        
        // Route requests
        routeRequest(method: method, path: path, connection: connection, requestData: data)
    }
    
    // MARK: - Routing
    
    private func routeRequest(method: String, path: String, connection: NWConnection, requestData: Data) {
        // Handle CORS preflight requests
        if method == "OPTIONS" {
            handleOptionsRequest(connection: connection)
            return
        }
        
        switch (method, path) {
        case ("GET", "/api/health"):
            handleHealthCheck(connection: connection)
            
        case ("GET", let p) where p.hasPrefix("/api/photos?"):
            handleGetPhotos(path: p, connection: connection)
            
        case ("GET", let p) where p.hasPrefix("/api/photos/search?"):
            handleSearchPhotos(path: p, connection: connection)
            
        case ("GET", let p) where p.contains("/api/thumbnails/"):
            handleGetThumbnail(path: p, connection: connection)
            
        case ("GET", let p) where p.contains("/api/photos/") && p.contains("/original"):
            handleGetOriginal(path: p, connection: connection)
            
        case ("POST", let p) where p.contains("/api/photos/") && p.contains("/export"):
            handleExportPhoto(path: p, connection: connection, requestData: requestData)
            
        default:
            sendError(connection: connection, message: "Not found", statusCode: 404)
        }
    }
    
    // Handle CORS preflight requests
    private func handleOptionsRequest(connection: NWConnection) {
        let responseString = """
        HTTP/1.1 200 OK\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r
        Access-Control-Max-Age: 86400\r
        Content-Length: 0\r
        \r
        """
        
        guard let headerData = responseString.data(using: .utf8) else { return }
        
        connection.send(content: headerData, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
            // Give a small delay to ensure data is sent
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                connection.cancel()
            }
        })
    }
    
    // MARK: - Request Handlers
    
    private func handleHealthCheck(connection: NWConnection) {
        let response = [
            "status": "ok",
            "version": "1.0.0",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        sendJSONResponse(connection: connection, data: response)
    }
    
    private func handleGetPhotos(path: String, connection: NWConnection) {
        let queryParams = parseQuery(from: path)
        let page = Int(queryParams["page"] ?? "1") ?? 1
        let pageSize = min(Int(queryParams["pageSize"] ?? "50") ?? 50, 200)
        
        let response = photosManager.getPhotos(page: page, pageSize: pageSize)
        sendJSONResponse(connection: connection, data: response)
    }
    
    private func handleSearchPhotos(path: String, connection: NWConnection) {
        let queryParams = parseQuery(from: path)
        guard let query = queryParams["q"], !query.isEmpty else {
            sendError(connection: connection, message: "Missing query parameter")
            return
        }
        
        let page = Int(queryParams["page"] ?? "1") ?? 1
        let pageSize = min(Int(queryParams["pageSize"] ?? "50") ?? 50, 200)
        
        let response = photosManager.searchPhotos(query: query, page: page, pageSize: pageSize)
        sendJSONResponse(connection: connection, data: response)
    }
    
    private func handleGetThumbnail(path: String, connection: NWConnection) {
        guard let photoId = extractPhotoId(from: path, pattern: "/api/thumbnails/") else {
            sendError(connection: connection, message: "Invalid photo ID")
            return
        }
        
        guard let asset = photosManager.getAsset(by: photoId) else {
            sendError(connection: connection, message: "Photo not found", statusCode: 404)
            return
        }
        
        photosManager.getThumbnail(for: asset) { data in
            if let data = data {
                self.sendDataResponse(connection: connection, data: data, contentType: "image/jpeg")
            } else {
                self.sendError(connection: connection, message: "Failed to generate thumbnail")
            }
        }
    }
    
    private func handleGetOriginal(path: String, connection: NWConnection) {
        guard let photoId = extractPhotoId(from: path, pattern: "/api/photos/", suffix: "/original") else {
            sendError(connection: connection, message: "Invalid photo ID")
            return
        }
        
        guard let asset = photosManager.getAsset(by: photoId) else {
            sendError(connection: connection, message: "Photo not found", statusCode: 404)
            return
        }
        
        photosManager.getOriginalImageData(for: asset) { data, uti in
            if let data = data {
                let contentType = self.mimeTypeFromUTI(uti ?? "") ?? "application/octet-stream"
                self.sendDataResponse(connection: connection, data: data, contentType: contentType)
            } else {
                self.sendError(connection: connection, message: "Failed to get original image")
            }
        }
    }
    
    private func handleExportPhoto(path: String, connection: NWConnection, requestData: Data) {
        guard let photoId = extractPhotoId(from: path, pattern: "/api/photos/", suffix: "/export") else {
            sendError(connection: connection, message: "Invalid photo ID")
            return
        }
        
        guard let asset = photosManager.getAsset(by: photoId) else {
            sendError(connection: connection, message: "Photo not found", statusCode: 404)
            return
        }
        
        // Extract POST body (simplified)
        guard let bodyStart = requestData.range(of: "\r\n\r\n".data(using: .utf8)!),
              let bodyData = String(data: requestData.subdata(in: bodyStart.upperBound..<requestData.endIndex), encoding: .utf8),
              let exportRequestData = bodyData.data(using: .utf8) else {
            sendError(connection: connection, message: "Invalid request body")
            return
        }
        
        do {
            let exportRequest = try JSONDecoder().decode(ExportRequest.self, from: exportRequestData)
            
            fileExporter.exportAsset(asset, to: exportRequest.destination, filename: exportRequest.filename) { response in
                self.sendJSONResponse(connection: connection, data: response)
            }
        } catch {
            sendError(connection: connection, message: "Invalid request format: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func parseQuery(from path: String) -> [String: String] {
        guard let queryStart = path.firstIndex(of: "?") else { return [:] }
        let queryString = String(path[path.index(after: queryStart)...])
        
        var params: [String: String] = [:]
        for param in queryString.components(separatedBy: "&") {
            let parts = param.components(separatedBy: "=")
            if parts.count == 2 {
                let key = parts[0].removingPercentEncoding ?? parts[0]
                let value = parts[1].removingPercentEncoding ?? parts[1]
                params[key] = value
            }
        }
        return params
    }
    
    private func extractPhotoId(from path: String, pattern: String, suffix: String = "") -> String? {
        guard let start = path.range(of: pattern)?.upperBound else { return nil }
        let remaining = String(path[start...])
        
        if !suffix.isEmpty {
            guard let end = remaining.range(of: suffix)?.lowerBound else { return nil }
            return String(remaining[..<end])
        } else {
            // Remove query parameters
            let cleanPath = remaining.components(separatedBy: "?")[0]
            return cleanPath
        }
    }
    
    // MARK: - Response Helpers
    
    private func sendJSONResponse<T: Codable>(connection: NWConnection, data: T) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(data)
            
            let responseString = """
            HTTP/1.1 200 OK\r
            Content-Type: application/json\r
            Access-Control-Allow-Origin: *\r
            Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r
            Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r
            Content-Length: \(jsonData.count)\r
            \r
            """
            
            guard let headerData = responseString.data(using: .utf8) else { return }
            let fullResponse = headerData + jsonData
            
            connection.send(content: fullResponse, completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                }
                // Give a small delay to ensure data is sent
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    connection.cancel()
                }
            })
        } catch {
            sendError(connection: connection, message: "JSON encoding failed")
        }
    }
    
    private func sendDataResponse(connection: NWConnection, data: Data, contentType: String) {
        let responseString = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r
        Content-Length: \(data.count)\r
        \r
        """
        
        guard let headerData = responseString.data(using: .utf8) else { return }
        let fullResponse = headerData + data
        
        connection.send(content: fullResponse, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
            // Give a small delay to ensure data is sent
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                connection.cancel()
            }
        })
    }
    
    private func sendError(connection: NWConnection, message: String, statusCode: Int = 400) {
        let errorResponse = [
            "error": message,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: errorResponse)
            
            let responseString = """
            HTTP/1.1 \(statusCode) Error\r
            Content-Type: application/json\r
            Access-Control-Allow-Origin: *\r
            Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r
            Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r
            Content-Length: \(jsonData.count)\r
            \r
            """
            
            guard let headerData = responseString.data(using: .utf8) else { return }
            let fullResponse = headerData + jsonData
            
            connection.send(content: fullResponse, completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                }
                // Give a small delay to ensure data is sent
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    connection.cancel()
                }
            })
        } catch {
            connection.cancel()
        }
    }
    
    private func mimeTypeFromUTI(_ uti: String) -> String? {
        let mimeTypes: [String: String] = [
            "public.jpeg": "image/jpeg",
            "public.png": "image/png",
            "public.tiff": "image/tiff",
            "public.heif": "image/heif",
            "public.heic": "image/heic",
            "com.apple.quicktime-movie": "video/quicktime",
            "public.mpeg-4": "video/mp4"
        ]
        
        return mimeTypes[uti]
    }
} 