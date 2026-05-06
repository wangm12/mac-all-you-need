import Core
import SwiftUI

struct DownloadsListView: View {
    @Bindable var vm: DownloaderViewModel
    @State private var showAdd = false
    @State private var addURL = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button {
                    showAdd.toggle()
                    addURL = ""
                } label: {
                    Image(systemName: showAdd ? "xmark.circle.fill" : "plus")
                }
            }.padding(8)

            if showAdd {
                HStack(spacing: 8) {
                    TextField("Paste URL…", text: $addURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Download") {
                        let url = addURL
                        showAdd = false
                        addURL = ""
                        Task { await vm.add(url: url) }
                    }
                    .disabled(addURL.isEmpty)
                    .keyboardShortcut(.return)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                Divider()
            }

            Divider()
            List(vm.rows, id: \.id) { record in
                DownloadRowView(record: record, progress: vm.liveProgress[record.id.rawValue])
            }
            .listStyle(.plain)
        }
        .task { await vm.refresh() }
    }
}

struct DownloadRowView: View {
    let record: DownloadRecord
    let progress: DownloadProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title).lineLimit(1)
            ProgressView(value: progress?.fraction ?? (record.state == .completed ? 1 : 0))
            HStack {
                Text(record.state.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)
                if let speed = progress?.speedBytesPerSec {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let eta = progress?.etaSeconds {
                    Text("ETA \(eta)s").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }.padding(.vertical, 4)
    }
}
