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
                            statusText: vm.liveStatus[record.id.rawValue],
                            onPause: { Task { await vm.pause(id: record.id) } },
                            onResume: { Task { await vm.resume(id: record.id) } },
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
    let statusText: String?
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void

    /// HLS streams report per-fragment %; use downloaded/total bytes for overall fraction
    private var overallFraction: Double {
        if record.state == .completed { return 1.0 }
        if let p = progress {
            if let dl = p.downloadedBytes, let total = p.totalBytes, total > 0 {
                return min(1, Double(dl) / Double(total))
            }
            return min(1, p.fraction)
        }
        if let total = record.bytesTotal, total > 0 {
            return min(1, Double(record.bytesDownloaded) / Double(total))
        }
        return 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Thumbnail
            if let thumbStr = record.thumbnailURL, let thumbURL = URL(string: thumbStr) {
                AsyncImage(url: thumbURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.2)
                }
                .frame(width: 72, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 72, height: 40)
                    .overlay(Image(systemName: "video").foregroundStyle(.tertiary))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(record.videoTitle ?? record.url).lineLimit(2).font(.body)
                    Spacer()
                    if record.state == .running {
                        Button(action: onPause) {
                            Image(systemName: "pause.circle").font(.caption)
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                    } else if record.state == .paused {
                        Button(action: onResume) {
                            Image(systemName: "play.circle").font(.caption)
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                    } else if record.state == .failed {
                        Button(action: onRetry) {
                            Image(systemName: "arrow.counterclockwise").font(.caption)
                        }.buttonStyle(.plain).foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 6) {
                    if let channel = record.channelName {
                        Text(channel).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let dur = record.durationSeconds, dur > 0 {
                        Text(formatDuration(dur)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                ProgressView(value: overallFraction)
                    .tint(record.state == .failed ? .red : record.state == .completed ? .green : .accentColor)
                HStack {
                    let label = record.state == .running ? (statusText ?? "Running") : record.state.rawValue.capitalized
                    Text(label).font(.caption2)
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
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
