import Core
import Foundation

enum DownloadPickerPresentation: Equatable, Identifiable {
    case collection(url: String)
    case douyinProfile(url: String)
    case format(url: String, metadata: VideoMetadata?)

    var id: String {
        switch self {
        case let .collection(url): "collection:\(url)"
        case let .douyinProfile(url): "douyin:\(url)"
        case let .format(url, _): "format:\(url)"
        }
    }
}

struct PendingDownloadURL: Equatable {
    let url: String
}
