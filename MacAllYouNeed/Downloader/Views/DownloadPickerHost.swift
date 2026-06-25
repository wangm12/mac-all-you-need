import Core
import SwiftUI

struct DownloadPickerHost: View {
    @Bindable var vm: DownloaderViewModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $vm.presentedPicker) { picker in
                switch picker {
                case let .collection(url):
                    DownloadCollectionPickerSheet(sourceURL: url, vm: vm) {
                        vm.dismissPicker()
                    }
                case let .douyinProfile(url):
                    DownloadDouyinProfilePickerSheet(profileURL: url, vm: vm) {
                        vm.dismissPicker()
                    }
                case let .format(url, metadata, isRefiningResolutions):
                    DownloadFormatSheet(
                        sourceURL: url,
                        metadata: metadata,
                        isRefiningResolutions: isRefiningResolutions,
                        onClose: { vm.dismissPicker() },
                        onDownload: { preset in
                            Task { await vm.enqueueFromFormatSheet(url: url, preset: preset) }
                        }
                    )
                }
            }
    }
}
