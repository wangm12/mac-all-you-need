import SwiftUI

struct ClipCard: View {
    let item: DockItem
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let favicons: FaviconCache
    let cardBackground: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
            SourceAppBadge(app: item.sourceApp, cardBackground: cardBackground)
        }
        .background(cardBackground)
        .cornerRadius(10)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.kind {
        case .text, .rtf:
            TextCard(item: item)
        case .image:
            ImageCard(item: item, loader: imageLoader)
        case .file:
            FileCard(item: item, loader: fileLoader)
        case .link:
            LinkCard(item: item, favicons: favicons)
        case .color:
            ColorCard(item: item)
        case .code:
            CodeCard(item: item)
        }
    }
}
