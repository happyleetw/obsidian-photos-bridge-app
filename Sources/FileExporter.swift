import Foundation
import Photos
import UniformTypeIdentifiers

class FileExporter {
    static let shared = FileExporter()
    
    private let imageManager = PHImageManager.default()
    
    private init() {}
    
    // MARK: - Export Asset
    
    func exportAsset(_ asset: PHAsset, to destinationPath: String, filename: String?, completion: @escaping (ExportResponse) -> Void) {
        // Ensure destination directory exists
        let destinationURL = URL(fileURLWithPath: destinationPath)
        
        do {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            completion(ExportResponse(success: false, filePath: nil, originalFilename: nil, error: "Failed to create destination directory: \(error.localizedDescription)"))
            return
        }
        
        if asset.mediaType == .video {
            exportVideo(asset, to: destinationPath, filename: filename, completion: completion)
        } else {
            exportImage(asset, to: destinationPath, filename: filename, completion: completion)
        }
    }
    
    // MARK: - Export Image
    
    private func exportImage(_ asset: PHAsset, to destinationPath: String, filename: String?, completion: @escaping (ExportResponse) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, _, info in
            guard let data = data else {
                completion(ExportResponse(success: false, filePath: nil, originalFilename: nil, error: "Failed to get image data"))
                return
            }
            
            // Determine file extension from UTI
            let fileExtension: String
            if let dataUTI = dataUTI {
                fileExtension = self.getFileExtension(from: dataUTI)
            } else {
                fileExtension = "jpg" // fallback
            }
            
            // Generate filename
            let finalFilename: String
            if let customFilename = filename {
                finalFilename = customFilename.hasSuffix(".\(fileExtension)") ? customFilename : "\(customFilename).\(fileExtension)"
            } else {
                let originalFilename = asset.value(forKey: "filename") as? String
                finalFilename = originalFilename ?? self.generateFilename(for: asset, extension: fileExtension)
            }
            
            // Write to destination
            let destinationURL = URL(fileURLWithPath: destinationPath).appendingPathComponent(finalFilename)
            
            do {
                try data.write(to: destinationURL)
                completion(ExportResponse(
                    success: true,
                    filePath: destinationURL.path,
                    originalFilename: asset.value(forKey: "filename") as? String,
                    error: nil
                ))
            } catch {
                completion(ExportResponse(success: false, filePath: nil, originalFilename: nil, error: "Failed to write file: \(error.localizedDescription)"))
            }
        }
    }
    
    // MARK: - Export Video
    
    private func exportVideo(_ asset: PHAsset, to destinationPath: String, filename: String?, completion: @escaping (ExportResponse) -> Void) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
            guard let urlAsset = avAsset as? AVURLAsset else {
                completion(ExportResponse(success: false, filePath: nil, originalFilename: nil, error: "Failed to get video URL"))
                return
            }
            
            let sourceURL = urlAsset.url
            
            // Determine file extension
            let pathExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
            
            // Generate filename
            let finalFilename: String
            if let customFilename = filename {
                finalFilename = customFilename.hasSuffix(".\(pathExtension)") ? customFilename : "\(customFilename).\(pathExtension)"
            } else {
                let originalFilename = asset.value(forKey: "filename") as? String
                finalFilename = originalFilename ?? self.generateFilename(for: asset, extension: pathExtension)
            }
            
            // Copy file to destination
            let destinationURL = URL(fileURLWithPath: destinationPath).appendingPathComponent(finalFilename)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                
                completion(ExportResponse(
                    success: true,
                    filePath: destinationURL.path,
                    originalFilename: asset.value(forKey: "filename") as? String,
                    error: nil
                ))
            } catch {
                completion(ExportResponse(success: false, filePath: nil, originalFilename: nil, error: "Failed to copy video file: \(error.localizedDescription)"))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateFilename(for asset: PHAsset, extension fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        
        let dateString: String
        if let creationDate = asset.creationDate {
            dateString = formatter.string(from: creationDate)
        } else {
            dateString = formatter.string(from: Date())
        }
        
        let mediaTypePrefix: String
        switch asset.mediaType {
        case .image:
            mediaTypePrefix = "IMG"
        case .video:
            mediaTypePrefix = "VID"
        case .audio:
            mediaTypePrefix = "AUD"
        default:
            mediaTypePrefix = "MEDIA"
        }
        
        return "\(mediaTypePrefix)_\(dateString).\(fileExtension)"
    }
    
    private func getFileExtension(from uti: String) -> String {
        // Get file extension from UTI
        if let utType = UTType(uti) {
            return utType.preferredFilenameExtension ?? "bin"
        }
        
        // Fallback mapping
        let utiToExtension: [String: String] = [
            "public.jpeg": "jpg",
            "public.png": "png",
            "public.tiff": "tiff",
            "public.gif": "gif",
            "public.heif": "heif",
            "public.heic": "heic",
            "com.apple.quicktime-movie": "mov",
            "public.mpeg-4": "mp4",
            "public.avi": "avi",
            "public.3gpp": "3gp"
        ]
        
        return utiToExtension[uti] ?? "bin"
    }
    
    // MARK: - Batch Export
    
    func exportMultipleAssets(_ assets: [PHAsset], to destinationPath: String, completion: @escaping ([ExportResponse]) -> Void) {
        let dispatchGroup = DispatchGroup()
        var responses: [ExportResponse] = []
        let responsesQueue = DispatchQueue(label: "export.responses", attributes: .concurrent)
        
        for asset in assets {
            dispatchGroup.enter()
            exportAsset(asset, to: destinationPath, filename: nil) { response in
                responsesQueue.async(flags: .barrier) {
                    responses.append(response)
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(responses)
        }
    }
    
    // MARK: - Utility Methods
    
    func getAvailableSpace(at path: String) -> Int64? {
        do {
            let url = URL(fileURLWithPath: path)
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return values.volumeAvailableCapacity.map { Int64($0) }
        } catch {
            return nil
        }
    }
    
    func estimateFileSize(for asset: PHAsset) -> Int64 {
        // This is a rough estimate based on asset properties
        let pixelCount = Int64(asset.pixelWidth * asset.pixelHeight)
        
        switch asset.mediaType {
        case .image:
            // Rough estimate: 3-4 bytes per pixel for JPEG
            return pixelCount * 3
        case .video:
            // Rough estimate: assume ~10 Mbps for video
            let duration = Int64(asset.duration)
            return duration * 1_250_000 // ~10 Mbps in bytes
        default:
            return 1_000_000 // 1MB fallback
        }
    }
} 