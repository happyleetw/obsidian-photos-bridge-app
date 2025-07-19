import Foundation
import Photos

struct PhotoModel: Codable {
    let id: String
    let filename: String?
    let createdDate: Date?
    let modifiedDate: Date?
    let mediaType: String
    let mediaSubtype: String?
    let width: Int
    let height: Int
    let duration: Double?
    let location: LocationModel?
    let isFavorite: Bool
    let thumbnailUrl: String
    let isHidden: Bool
    
    init(from asset: PHAsset) {
        self.id = asset.localIdentifier
        self.filename = asset.value(forKey: "filename") as? String
        self.createdDate = asset.creationDate
        self.modifiedDate = asset.modificationDate
        
        switch asset.mediaType {
        case .image:
            self.mediaType = "image"
        case .video:
            self.mediaType = "video"
        case .audio:
            self.mediaType = "audio"
        default:
            self.mediaType = "unknown"
        }
        
        // Media subtype mapping
        switch asset.mediaSubtypes {
        case .photoLive:
            self.mediaSubtype = "live"
        case .photoHDR:
            self.mediaSubtype = "hdr"
        case .photoPanorama:
            self.mediaSubtype = "panorama"
        case .photoScreenshot:
            self.mediaSubtype = "screenshot"
        case .videoHighFrameRate:
            self.mediaSubtype = "highFrameRate"
        case .videoTimelapse:
            self.mediaSubtype = "timelapse"
        default:
            self.mediaSubtype = nil
        }
        
        self.width = asset.pixelWidth
        self.height = asset.pixelHeight
        self.duration = asset.mediaType == .video ? asset.duration : nil
        self.location = asset.location != nil ? LocationModel(from: asset.location!) : nil
        self.isFavorite = asset.isFavorite
        self.thumbnailUrl = "/api/thumbnails/\(asset.localIdentifier)"
        self.isHidden = asset.isHidden
    }
}

struct LocationModel: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    
    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
    }
}

struct PhotosResponse: Codable {
    let photos: [PhotoModel]
    let total: Int
    let page: Int
    let pageSize: Int
    let hasMore: Bool
}

struct ExportRequest: Codable {
    let destination: String
    let filename: String?
    let keepOriginalName: Bool?
}

struct ExportResponse: Codable {
    let success: Bool
    let filePath: String?
    let originalFilename: String?
    let error: String?
} 