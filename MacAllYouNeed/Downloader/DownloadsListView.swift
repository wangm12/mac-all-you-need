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
                           clip.hasPrefix("http") { addURL = clip } else { addURL = "" }
                    }
                } label: { Image(systemName: showAdd ? "xmark.circle.fill" : "plus") }
            }.padding(8)

            if showAdd {
                HStack(spacing: 8) {
                    TextField("Paste URL…", text: $addURL).textFieldStyle(.roundedBorder)
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
                            progress: vm.liveProgress[record.id.rawValue],
                            onPause: { Task { await vm.pause(id: record.id) } },
                            onResume: { Task { await vm.resume(id: record.id) } },
                            onStop: { Task { await vm.cancel(id: record.id) } },
                            onRetry: { Task { await vm.retry(record: record) } }
                        )
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
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
    let onRetry: () -> Void

    /// HLS streams report per-fragment %; use downloaded/total bytes for overall fraction
    private var overallFraction: Double {
        if let p = progress {
            if let dl = p.downloadedBytes, let total = p.totalBytes, total > 0 {
                return min(1, Double(dl) / Double(total))
            }
            return min(1, p.fraction)
        }
        // No live progress — use persisted bytes (shown while paused / after resume)
        if let total = record.bytesTotal, total > 0 {
            return min(1, Double(record.bytesDownloaded) / Double(total))
        }
        return record.state == .completed ? 1 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.title.isEmpty ? record.url : record.title).lineLimit(1)
                Spacer()
                if record.state == .running {
                    Button(action: onPause) {
                        Image(systemName: "pause.circle").font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Button(action: onStop) {
                        Image(systemName: "stop.circle").font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(.red)
                } else if record.state == .paused {
                    Button(action: onResume) {
                        Image(systemName: "play.circle").font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Button(action: onStop) {
                        Image(systemName: "stop.circle").font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(.red)
                } else if record.state == .failed {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.counterclockwise").font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(.orange)
                }
            }
            ProgressView(value: overallFraction)
                .tint(record.state == .failed ? .red : record.state == .completed ? .green : .accentColor)
            HStack {
                Text(record.state.rawValue.capitalized).font(.caption2)
                    .foregroundStyle(record.state == .failed ? .red : record.state == .completed ? .green : .secondary)
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
