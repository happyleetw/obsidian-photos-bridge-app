import Foundation
import GCDWebServer
import Photos

class APIServer {
    static let shared = APIServer()
    
    private let webServer = GCDWebServer()
    private let port: UInt = 44556
    private let photosManager = PhotosManager.shared
    private let fileExporter = FileExporter.shared
    
    private init() {
        setupRoutes()
    }
    
    // MARK: - Server Management
    
    func start() -> Bool {
        return webServer.start(withPort: port, bonjourName: nil)
    }
    
    func stop() {
        webServer.stop()
    }
    
    var isRunning: Bool {
        return webServer.isRunning
    }
    
    var serverURL: String {
        return "http://localhost:\(port)"
    }
    
    // MARK: - Route Setup
    
    private func setupRoutes() {
        // Health check endpoint
        webServer.addHandler(forMethod: "GET", path: "/api/health", request: GCDWebServerRequest.self) { request in
            guard let response = GCDWebServerDataResponse(jsonObject: [
                "status": "ok",
                "version": "1.0.0",
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]) else {
                return GCDWebServerErrorResponse(statusCode: 500)
            }
            response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            response.setValue("GET, POST, PUT, DELETE, OPTIONS", forAdditionalHeader: "Access-Control-Allow-Methods")
            response.setValue("Content-Type, Authorization, X-Requested-With", forAdditionalHeader: "Access-Control-Allow-Headers")
            return response
        }
        
        // Get photos list
        webServer.addHandler(forMethod: "GET", path: "/api/photos", request: GCDWebServerRequest.self) { request in
            return self.handleGetPhotos(request: request)
        }
        
        // Search photos
        webServer.addHandler(forMethod: "GET", path: "/api/photos/search", request: GCDWebServerRequest.self) { request in
            return self.handleSearchPhotos(request: request)
        }
        
        // Get photos by date
        webServer.addHandler(forMethod: "GET", path: "/api/photos/date", request: GCDWebServerRequest.self) { request in
            return self.handleGetPhotosByDate(request: request)
        }
        
        // Get thumbnail
        webServer.addHandler(forMethod: "GET", pathRegex: "^/api/thumbnails/(.+)$", request: GCDWebServerRequest.self) { request in
            return self.handleGetThumbnail(request: request)
        }
        
        // Get original image
        webServer.addHandler(forMethod: "GET", pathRegex: "^/api/photos/(.+)/original$", request: GCDWebServerRequest.self) { request in
            return self.handleGetOriginal(request: request)
        }
        
        // Export photo
        webServer.addHandler(forMethod: "POST", pathRegex: "^/api/photos/(.+)/export$", request: GCDWebServerDataRequest.self) { request in
            return self.handleExportPhoto(request: request as! GCDWebServerDataRequest)
        }
        
        // CORS support for browser requests
        webServer.addHandler(forMethod: "OPTIONS", pathRegex: ".*", request: GCDWebServerRequest.self) { request in
            let response = GCDWebServerDataResponse()
            response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            response.setValue("GET, POST, PUT, DELETE, OPTIONS", forAdditionalHeader: "Access-Control-Allow-Methods")
            response.setValue("Content-Type, Authorization, X-Requested-With", forAdditionalHeader: "Access-Control-Allow-Headers")
            response.setValue("86400", forAdditionalHeader: "Access-Control-Max-Age")
            return response
        }
    }
    
    // MARK: - Route Handlers
    
    private func handleGetPhotos(request: GCDWebServerRequest) -> GCDWebServerResponse? {
        // Parse query parameters
        let page = Int(request.query?["page"] as? String ?? "1") ?? 1
        let pageSize = min(Int(request.query?["pageSize"] as? String ?? "50") ?? 50, 200) // Max 200
        
        // Parse refresh parameter
        let forceReload = (request.query?["refresh"] as? String)?.lowercased() == "true"
        
        let mediaTypeString = request.query?["mediaType"] as? String
        var mediaType: PHAssetMediaType?
        
        if let mediaTypeString = mediaTypeString {
            switch mediaTypeString.lowercased() {
            case "image":
                mediaType = .image
            case "video":
                mediaType = .video
            case "audio":
                mediaType = .audio
            default:
                mediaType = nil
            }
        }
        
        let response = photosManager.getPhotos(page: page, pageSize: pageSize, mediaType: mediaType, forceReload: forceReload)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(response)
            
            let httpResponse = GCDWebServerDataResponse(data: jsonData, contentType: "application/json")
            httpResponse.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            return httpResponse
        } catch {
            return createErrorResponse(message: "Failed to encode response: \(error.localizedDescription)")
        }
    }
    
    private func handleSearchPhotos(request: GCDWebServerRequest) -> GCDWebServerResponse? {
        guard let query = request.query?["q"] as? String, !query.isEmpty else {
            return createErrorResponse(message: "Missing or empty search query parameter 'q'")
        }
        
        let page = Int(request.query?["page"] as? String ?? "1") ?? 1
        let pageSize = min(Int(request.query?["pageSize"] as? String ?? "50") ?? 50, 200)
        
        let response = photosManager.searchPhotos(query: query, page: page, pageSize: pageSize)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(response)
            
            let httpResponse = GCDWebServerDataResponse(data: jsonData, contentType: "application/json")
            httpResponse.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            return httpResponse
        } catch {
            return createErrorResponse(message: "Failed to encode response: \(error.localizedDescription)")
        }
    }
    
    private func handleGetPhotosByDate(request: GCDWebServerRequest) -> GCDWebServerResponse? {
        guard let dateString = request.query?["date"] as? String, !dateString.isEmpty else {
            return createErrorResponse(message: "Missing or empty date parameter (format: YYYY/MM/DD)")
        }
        
        let page = Int(request.query?["page"] as? String ?? "1") ?? 1
        let pageSize = min(Int(request.query?["pageSize"] as? String ?? "50") ?? 50, 200)
        
        let response = photosManager.getPhotosByDate(dateString: dateString, page: page, pageSize: pageSize)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(response)
            
            let httpResponse = GCDWebServerDataResponse(data: jsonData, contentType: "application/json")
            httpResponse.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            return httpResponse
        } catch {
            return createErrorResponse(message: "Failed to encode response: \(error.localizedDescription)")
        }
    }
    
    private func handleGetThumbnail(request: GCDWebServerRequest) -> GCDWebServerResponse? {
        let path = request.path
        guard let photoId = extractPhotoId(from: path, pattern: "^/api/thumbnails/(.+)$") else {
            return createErrorResponse(message: "Invalid photo ID")
        }
        
        guard let asset = photosManager.getAsset(by: photoId) else {
            return createErrorResponse(message: "Photo not found", statusCode: 404)
        }
        
        // Use a semaphore to make the async call synchronous for this handler
        let semaphore = DispatchSemaphore(value: 0)
        var thumbnailData: Data?
        
        photosManager.getThumbnail(for: asset) { data in
            thumbnailData = data
            semaphore.signal()
        }
        
        semaphore.wait()
        
        guard let data = thumbnailData else {
            return createErrorResponse(message: "Failed to generate thumbnail", statusCode: 500)
        }
        
        let response = GCDWebServerDataResponse(data: data, contentType: "image/jpeg")
        response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
        return response
    }
    
    private func handleGetOriginal(request: GCDWebServerRequest) -> GCDWebServerResponse? {
        let path = request.path
        guard let photoId = extractPhotoId(from: path, pattern: "^/api/photos/(.+)/original$") else {
            return createErrorResponse(message: "Invalid photo ID")
        }
        
        guard let asset = photosManager.getAsset(by: photoId) else {
            return createErrorResponse(message: "Photo not found", statusCode: 404)
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var imageData: Data?
        var contentType = "application/octet-stream"
        
        photosManager.getOriginalImageData(for: asset) { data, dataUTI in
            imageData = data
            if let uti = dataUTI {
                contentType = self.mimeTypeFromUTI(uti) ?? "application/octet-stream"
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        guard let data = imageData else {
            return createErrorResponse(message: "Failed to get original image data", statusCode: 500)
        }
        
        let response = GCDWebServerDataResponse(data: data, contentType: contentType)
        response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
        return response
    }
    
    private func handleExportPhoto(request: GCDWebServerDataRequest) -> GCDWebServerResponse? {
        let path = request.path
        guard let photoId = extractPhotoId(from: path, pattern: "^/api/photos/(.+)/export$") else {
            return createErrorResponse(message: "Invalid photo ID")
        }
        
        guard let asset = photosManager.getAsset(by: photoId) else {
            return createErrorResponse(message: "Photo not found", statusCode: 404)
        }
        
        let requestData = request.data
        
        do {
            let exportRequest = try JSONDecoder().decode(ExportRequest.self, from: requestData)
            
            let semaphore = DispatchSemaphore(value: 0)
            var exportResponse: ExportResponse?
            
            fileExporter.exportAsset(asset, to: exportRequest.destination, filename: exportRequest.filename) { response in
                exportResponse = response
                semaphore.signal()
            }
            
            semaphore.wait()
            
            guard let response = exportResponse else {
                return createErrorResponse(message: "Export failed", statusCode: 500)
            }
            
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(response)
            
            let httpResponse = GCDWebServerDataResponse(data: jsonData, contentType: "application/json")
            httpResponse.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            return httpResponse
            
        } catch {
            return createErrorResponse(message: "Invalid request body: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractPhotoId(from path: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let range = NSRange(location: 0, length: path.utf16.count)
        guard let match = regex.firstMatch(in: path, range: range) else { return nil }
        
        let idRange = match.range(at: 1)
        guard idRange.location != NSNotFound else { return nil }
        
        return String(path[Range(idRange, in: path)!])
    }
    
    private func createErrorResponse(message: String, statusCode: Int = 400) -> GCDWebServerDataResponse? {
        let errorResponse = [
            "error": message,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: errorResponse) else {
            return GCDWebServerDataResponse(text: message)
        }
        
        let response = GCDWebServerDataResponse(data: jsonData, contentType: "application/json")
        response.statusCode = statusCode
        response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
        return response
    }
    
    private func mimeTypeFromUTI(_ uti: String) -> String? {
        let mimeTypes: [String: String] = [
            "public.jpeg": "image/jpeg",
            "public.png": "image/png",
            "public.tiff": "image/tiff",
            "public.heif": "image/heif",
            "public.heic": "image/heic",
            "com.apple.quicktime-movie": "video/quicktime",
            "public.mpeg-4": "video/mp4",
            "public.avi": "video/avi"
        ]
        
        return mimeTypes[uti]
    }
} 