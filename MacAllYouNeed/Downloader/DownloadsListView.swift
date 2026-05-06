import Core
import SwiftUI

struct DownloadsListView: View {
    @Bindable var vm: DownloaderViewModel
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .keyboardShortcut(.init("N"), modifiers: .command)
            }.padding(8)
            Divider()
            List(vm.rows, id: \.id) { record in
                DownloadRowView(record: record, progress: vm.liveProgress[record.id.rawValue])
            }
            .listStyle(.plain)
        }
        .sheet(isPresented: $showAdd) {
            AddDownloadDialog { url in
                Task { await vm.add(url: url) }
            }
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

struct AddDownloadDialog: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var url: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Add download").font(.headline)
            TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Download") { onSubmit(url); dismiss() }
                    .keyboardShortcut(.return).disabled(url.isEmpty)
            }
        }.padding(16).frame(width: 420)
    }
}
