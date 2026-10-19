import AppKit

/// Finds the real album cover for a track.
/// Spotify: the public oEmbed endpoint (no login). Apple Music: the iTunes Search API,
/// then the artwork embedded in the Music library as a last resort.
enum Artwork {
    private static let cache = NSCache<NSString, NSImage>()
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        return URLSession(configuration: c)
    }()

    static func fetch(for track: Track, completion: @escaping (NSImage?) -> Void) {
        let key = "\(track.player.rawValue)|\(track.artist)|\(track.album)|\(track.spotifyID ?? "")" as NSString
        if let hit = cache.object(forKey: key) { return completion(hit) }
        Task {
            var image: NSImage?
            if track.player == .spotify {
                if let id = track.spotifyID { image = await spotifyCover(id: id) }
                if image == nil { image = await spotifyScriptCover() }
            }
            if image == nil { image = await itunesCover(track) }
            if image == nil, track.player == .music { image = await musicLibraryCover() }
            if let image { cache.setObject(image, forKey: key) }
            await MainActor.run { completion(image) }
        }
    }

    private static func data(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func image(_ urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString), let d = await data(url) else { return nil }
        return NSImage(data: d)
    }

    private static func spotifyCover(id: String) async -> NSImage? {
        guard let url = URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/track/\(id)"),
              let d = await data(url),
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let thumb = json["thumbnail_url"] as? String else { return nil }
        // The thumbnail is 300px; the same image id is served at 640px.
        let large = thumb.replacingOccurrences(of: "ab67616d00001e02", with: "ab67616d0000b273")
        if large != thumb, let img = await image(large) { return img }
        return await image(thumb)
    }

    private static func spotifyScriptCover() async -> NSImage? {
