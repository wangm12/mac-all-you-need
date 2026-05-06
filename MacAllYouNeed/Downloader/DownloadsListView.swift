import AppKit
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
                    if showAdd {
                        if let clip = NSPasteboard.general.string(forType: .string),
                           clip.hasPrefix("http")
                        {
                            addURL = clip
                        } else {
                            addURL = ""
                        }
                    }
                } label: {
                    Image(systemName: showAdd ? "xmark.circle.fill" : "plus")
                }
            }.padding(8)

            if showAdd {
                HStack(spacing: 8) {
                    TextField("Paste URL…", text: $addURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Download") {
                        let url = addURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !url.isEmpty else { return }
                        showAdd = false; addURL = ""
                        Task { await vm.add(url: url) }
                    }
                    .disabled(addURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return)
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
                Divider()
            }

            Divider()
            if vm.rows.isEmpty {
                Text("No downloads yet").foregroundStyle(.tertiary).font(.callout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.rows, id: \.id) { record in
                        DownloadRowView(
                            record: record,
                            progress: vm.liveProgress[record.id.rawValue]
                        ) { Task { await vm.retry(record: record) } }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { vm.rows[$0].id }
                        Task { await vm.delete(ids: ids) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await vm.refresh() }
    }
}

struct DownloadRowView: View {
    let record: DownloadRecord
    let progress: DownloadProgress?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.title.isEmpty ? record.url : record.title).lineLimit(1)
                Spacer()
                if record.state == .failed {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.counterclockwise").font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(.orange)
                }
            }
            ProgressView(value: progress?.fraction ?? (record.state == .completed ? 1 : 0))
                .tint(record.state == .failed ? .red : record.state == .completed ? .green : .accentColor)
            HStack {
                Text(record.state.rawValue.capitalized).font(.caption2)
                    .foregroundStyle(record.state == .failed ? .red : .secondary)
                if let speed = progress?.speedBytesPerSec {
                    Text("· \(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let eta = progress?.etaSeconds, eta > 0 {
                    Text("ETA \(eta)s").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }.padding(.vertical, 4)
    }
}
