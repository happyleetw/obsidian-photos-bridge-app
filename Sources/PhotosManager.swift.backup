import Foundation
import Photos
import AppKit

class PhotosManager: NSObject {
    static let shared = PhotosManager()
    
    private var allPhotos: PHFetchResult<PHAsset>?
    private let imageManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 200, height: 200)
    
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
        print("Loaded \(allPhotos?.count ?? 0) photos")
    }
    
    // Add a public method to load photos from main thread
    @MainActor
    func loadPhotosFromMainThread() {
        loadPhotos()
    }
    
    // MARK: - Public API
    
    func getPhotos(page: Int = 1, pageSize: Int = 50, mediaType: PHAssetMediaType? = nil) -> PhotosResponse {
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
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        
        imageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image = image else {
                completion(nil)
                return
            }
            
            // Convert NSImage to Data
            guard let tiffData = image.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                completion(nil)
                return
            }
            
            completion(jpegData)
        }
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
} 