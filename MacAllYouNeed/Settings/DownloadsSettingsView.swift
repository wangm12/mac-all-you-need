import Core
import SwiftUI

struct DownloadsSettingsView: View {
    let controller: AppController
    @AppStorage("downloadConcurrency", store: AppGroupSettings.defaults) private var concurrency = 3
    @AppStorage("downloadOutputTemplate", store: AppGroupSettings.defaults) private var template = "%(title)s [%(id)s].%(ext)s"
    var body: some View {
        Form {
            Stepper("Concurrent downloads: \(concurrency)", value: $concurrency, in: 1...10)
                .onChange(of: concurrency) { _, n in
                    Task { await controller.downloader.queue.setMaxConcurrent(n) }
                }
            TextField("Output template", text: $template)
            Button("Check for downloader update") {
                NotificationCenter.default.post(name: .downloaderUpdateRequested, object: nil)
            }
        }.padding()
    }
}
