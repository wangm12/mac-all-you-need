@testable import Core
import XCTest

final class PlaylistEntryListerTests: XCTestCase {
    func testEntryDisplayTitleUsesPlaylistIndex() {
        let json: [String: Any] = [
            "title": "Unknown",
            "playlist_index": 3,
            "playlist_title": "Series",
            "id": "abc"
        ]
        let title = PlaylistEntryLister.entryDisplayTitle(json: json, playlistTitle: "Series")
        XCTAssertEqual(title, "Series · p03")
    }

    func testParseRowsFromDumpLines() throws {
        let stdout = """
        {"_type":"playlist","title":"My List","n_entries":2}
        {"_type":"video","id":"1","title":"One","webpage_url":"https://example.com/1","duration":10,"playlist_index":1}
        {"_type":"video","id":"2","title":"Two","webpage_url":"https://example.com/2","duration":20,"playlist_index":2}
        """
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ytdlp-\(UUID().uuidString)")
        let script = temp.appendingPathComponent("yt-dlp")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let sh = """
        #!/bin/sh
        cat <<'EOF'
        \(stdout)
        EOF
        """
        try sh.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let result = try PlaylistEntryLister.listSync(
            url: "https://example.com/playlist",
            ytdlp: script,
            cookieFile: nil
        )
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.collectionTitle, "My List")
    }
}
