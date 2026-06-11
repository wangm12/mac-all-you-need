import Foundation

public enum DownloadSpeedMode: String {
    case balanced
    case gentle
    case turbo
}

public struct YtDlpArgumentOptions {
    public var concurrentFragments: Int
    public var sleepInterval: Double
    public var speedMode: DownloadSpeedMode
    public var externalDownloader: String?

    public init(
        concurrentFragments: Int = 4,
        sleepInterval: Double = 0,
        speedMode: DownloadSpeedMode = .balanced,
        externalDownloader: String? = nil
    ) {
        self.concurrentFragments = concurrentFragments
        self.sleepInterval = sleepInterval
        self.speedMode = speedMode
        self.externalDownloader = externalDownloader
    }
}

public enum YtDlpArgumentBuilder {
    public static func build(
        record: DownloadRecord,
        cookies: [String],
        formatArgs: [String],
        batchArgs: [String],
        options: YtDlpArgumentOptions
    ) -> [String] {
        var args = cookies + formatArgs
        let isDouyin = record.url.contains("douyin.com")
        let fragments = isDouyin ? min(2, max(1, options.concurrentFragments)) : max(1, options.concurrentFragments)
        args += ["--concurrent-fragments", String(fragments)]

        if options.sleepInterval > 0 {
            args += ["--sleep-interval", Self.trimmedNumber(options.sleepInterval)]
        }

        switch options.speedMode {
        case .balanced:
            args += ["--retry-sleep", "fragment:linear=1::3"]
        case .gentle:
            args += ["--retry-sleep", "fragment:linear=2::5"]
        case .turbo:
            args += ["--retry-sleep", "fragment:linear=0.2::1.5"]
        }

        if let external = options.externalDownloader?.trimmingCharacters(in: .whitespacesAndNewlines),
           !external.isEmpty
        {
            args += ["--downloader", external]
        }

        if record.nativeYoutubePlaylist == true {
            args.append("--yes-playlist")
        }

        if record.url.contains("douyin.com") {
            args += ["--referer", "https://www.douyin.com/"]
            args += ["--add-header", "Origin:https://www.douyin.com"]
            args += ["--add-header", "Accept-Language:zh-CN,zh;q=0.9,en-US;q=0.8"]
            args += ["--sleep-requests", "1"]
            args += ["--sleep-interval", "1"]
        }

        if let referer = record.referer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !referer.isEmpty
        {
            args += ["--referer", referer]
        }

        if let headers = record.customHeaders, !headers.isEmpty {
            for key in headers.keys.sorted() {
                let headerKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                let headerValue = (headers[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !headerKey.isEmpty, !headerValue.isEmpty {
                    args += ["--add-header", "\(headerKey):\(headerValue)"]
                }
            }
        }

        return args + batchArgs
    }

    private static func trimmedNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(value)
    }
}
