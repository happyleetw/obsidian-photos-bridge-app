import Foundation
import Photos
import AppKit

class PhotosManager: NSObject {
    static let shared = PhotosManager()
    
    private var allPhotos: PHFetchResult<PHAsset>?
    private let imageManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 200, height: 200)
    private var lastLoadTime: Date?
    
    private override init() {
        super.init()
        setupImageManager()
    }
    
    private func setupImageManager() {
        imageManager.allowsCachingHighQualityImages = true
    }
    
    // MARK: - Permission Management
    
    func requestPhotosAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            await loadPhotos()
            return true
        case .denied, .restricted:
            print("Photos access denied")
            return false
        case .notDetermined:
            print("Photos access not determined")
            return false
        @unknown default:
            print("Unknown photos authorization status")
            return false
        }
    }
    
    func checkPhotosAccess() -> PHAuthorizationStatus {
        return PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    // MARK: - Photos Loading
    
    @MainActor
    private func loadPhotos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        // includeAllBurstPhotos is not available in newer iOS/macOS versions
        
        allPhotos = PHAsset.fetchAssets(with: fetchOptions)
        lastLoadTime = Date()
        print("Loaded \(allPhotos?.count ?? 0) photos at \(lastLoadTime!)")
    }
    
    // Add a public method to load photos from main thread
    @MainActor
    func loadPhotosFromMainThread() {
        loadPhotos()
    }
    
    // Check if photos should be automatically reloaded (e.g., if they're older than 5 minutes)
    private func shouldAutoReload() -> Bool {
        guard let lastLoadTime = lastLoadTime else { return true }
        let timeSinceLastLoad = Date().timeIntervalSince(lastLoadTime)
        let autoReloadThreshold: TimeInterval = 5 * 60 // 5 minutes
        return timeSinceLastLoad > autoReloadThreshold
    }
    
    // MARK: - Public API
    
    func getPhotos(page: Int = 1, pageSize: Int = 50, mediaType: PHAssetMediaType? = nil, forceReload: Bool = false) -> PhotosResponse {
        // Check if we need to reload photos
        let shouldReload = forceReload || allPhotos == nil || shouldAutoReload()
        
        if shouldReload {
            Task { @MainActor in
                loadPhotos()
            }
        }
        
        guard let allPhotos = allPhotos else {
            return PhotosResponse(photos: [], total: 0, page: page, pageSize: pageSize, hasMore: false)
        }
        
        var assets: [PHAsset] = []
        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, allPhotos.count)
        
        for i in startIndex..<endIndex {
            let asset = allPhotos.object(at: i)
            
            // Filter by media type if specified
            if let mediaType = mediaType, asset.mediaType != mediaType {
                continue
            }
            
            assets.append(asset)
        }
        
        let photoModels = assets.map { PhotoModel(from: $0) }
        let hasMore = endIndex < allPhotos.count
        
        return PhotosResponse(
            photos: photoModels,
            total: allPhotos.count,
            page: page,
            pageSize: pageSize,
            hasMore: hasMore
        )
    }
    
    func searchPhotos(query: String, page: Int = 1, pageSize: Int = 50) -> PhotosResponse {
        guard let allPhotos = allPhotos else {
            return PhotosResponse(photos: [], total: 0, page: page, pageSize: pageSize, hasMore: false)
        }
        
        var matchedAssets: [PHAsset] = []
        let lowercaseQuery = query.lowercased()
        
        allPhotos.enumerateObjects { asset, _, _ in
            // Search by filename
            if let filename = asset.value(forKey: "filename") as? String,
               filename.lowercased().contains(lowercaseQuery) {
                matchedAssets.append(asset)
                return
            }
            
            // Search by date (basic implementation)
            if let creationDate = asset.creationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let dateString = formatter.string(from: creationDate)
                if dateString.lowercased().contains(lowercaseQuery) {
                    matchedAssets.append(asset)
                    return
                }
            }
        }
        
        // Apply pagination
        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, matchedAssets.count)
        let paginatedAssets = Array(matchedAssets[startIndex..<endIndex])
        
        let photoModels = paginatedAssets.map { PhotoModel(from: $0) }
        let hasMore = endIndex < matchedAssets.count
        
        return PhotosResponse(
            photos: photoModels,
            total: matchedAssets.count,
            page: page,
            pageSize: pageSize,
            hasMore: hasMore
        )
    }
    
    func getAsset(by id: String) -> PHAsset? {
        guard let allPhotos = allPhotos else { return nil }
        
        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            if asset.localIdentifier == id {
                return asset
            }
        }
        
        return nil
    }
    
    // MARK: - Image Processing
    
    func getThumbnail(for asset: PHAsset, completion: @escaping (Data?) -> Void) {
        // First attempt: try high quality format for best results
        let highQualityOptions = PHImageRequestOptions()
        highQualityOptions.isSynchronous = false
        highQualityOptions.deliveryMode = .highQualityFormat
        highQualityOptions.resizeMode = .exact
        highQualityOptions.isNetworkAccessAllowed = true
        
        var hasCompleted = false
        var requestID: PHImageRequestID = 0
        
        // Set up a timeout mechanism
        let timeoutWork = DispatchWorkItem { [weak self] in
            if !hasCompleted {
                hasCompleted = true
                print("High quality thumbnail request timed out for asset \(asset.localIdentifier), trying opportunistic mode")
                // Cancel the ongoing request
                self?.imageManager.cancelImageRequest(requestID)
                // Try opportunistic mode as fallback
                self?.getThumbnailWithOpportunisticMode(for: asset, completion: completion)
            }
        }
        
        // Execute timeout after 8 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 8.0, execute: timeoutWork)
        
        requestID = imageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: highQualityOptions
        ) { [weak self] image, info in
            guard !hasCompleted else { return }
            
            // Check if the request was successful and we got a good quality image
            let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
            let isError = info?[PHImageErrorKey] != nil
            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            
            if let image = image, !isDegraded && !isError && !isCancelled {
                // Success with high quality image
                hasCompleted = true
                timeoutWork.cancel() // Cancel the timeout
                self?.convertImageToJPEGData(image, completion: completion)
            } else if isError || isCancelled {
                // High quality request failed, try opportunistic mode as fallback
                hasCompleted = true
                timeoutWork.cancel() // Cancel the timeout
                print("High quality thumbnail failed for asset \(asset.localIdentifier), trying opportunistic mode")
                self?.getThumbnailWithOpportunisticMode(for: asset, completion: completion)
            }
            // If it's just degraded but not final, wait for the next callback
        }
    }
    
    // Fallback method using opportunistic mode for problematic assets
    private func getThumbnailWithOpportunisticMode(for asset: PHAsset, completion: @escaping (Data?) -> Void) {
        let opportunisticOptions = PHImageRequestOptions()
        opportunisticOptions.isSynchronous = false
        opportunisticOptions.deliveryMode = .opportunistic
        opportunisticOptions.resizeMode = .exact
        opportunisticOptions.isNetworkAccessAllowed = true
        
        imageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: opportunisticOptions
        ) { [weak self] image, _ in
            if let image = image {
                self?.convertImageToJPEGData(image, completion: completion)
            } else {
                print("Failed to generate thumbnail for asset \(asset.localIdentifier)")
                completion(nil)
            }
        }
    }
    
    // Helper method to convert NSImage to JPEG data
    private func convertImageToJPEGData(_ image: NSImage, completion: @escaping (Data?) -> Void) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            completion(nil)
            return
        }
        
        completion(jpegData)
    }
    
    func getOriginalImageData(for asset: PHAsset, completion: @escaping (Data?, String?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        if asset.mediaType == .video {
            // Handle video
            let videoOptions = PHVideoRequestOptions()
            videoOptions.isNetworkAccessAllowed = true
            videoOptions.deliveryMode = .highQualityFormat
            
            imageManager.requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, _ in
                // For video, we would need to handle AVAsset
                // For now, return nil as this requires more complex handling
                completion(nil, nil)
            }
        } else {
            // Handle image
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, _, _ in
                completion(data, dataUTI)
            }
        }
    }
    
    // MARK: - Date-based Search
    
    func getPhotosByDate(dateString: String, page: Int = 1, pageSize: Int = 50) -> PhotosResponse {
        // Parse the date string (expected format: YYYY/MM/DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        
        guard let targetDate = dateFormatter.date(from: dateString) else {
            print("Invalid date format: \(dateString)")
            return PhotosResponse(photos: [], total: 0, page: page, pageSize: pageSize, hasMore: false)
        }
        
        // Create date range for the entire day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: targetDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Create fetch options with date predicate
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startOfDay as NSDate, endOfDay as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // Fetch assets
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        let total = fetchResult.count
        
        // Calculate pagination
        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, total)
        
        guard startIndex < total else {
            return PhotosResponse(photos: [], total: total, page: page, pageSize: pageSize, hasMore: false)
        }
        
        // Convert to PhotoModel array
        var photos: [PhotoModel] = []
        for i in startIndex..<endIndex {
            let asset = fetchResult.object(at: i)
            let photo = PhotoModel(from: asset)
            photos.append(photo)
        }
        
        let hasMore = endIndex < total
        
        print("Found \(photos.count) photos for date \(dateString) (page \(page))")
        
        return PhotosResponse(photos: photos, total: total, page: page, pageSize: pageSize, hasMore: hasMore)
    }
}
