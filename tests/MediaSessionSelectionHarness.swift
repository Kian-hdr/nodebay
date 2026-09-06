import Foundation

@main
struct MediaSessionSelectionHarness {
    typealias Candidate = MediaSessionCandidate<String>

    static func source(_ id: String, app: String = "player", title: String = "Track",
                       available: Bool = true, playing: Bool = false,
                       generic: Bool = false, appSource: Bool = true) -> Candidate {
        Candidate(id: id, state: PlaybackState(bundleIdentifier: app, isPlaying: playing, title: title),
                  isAvailable: available, isGeneric: generic, isAppSource: appSource)
    }

    static func visible(_ candidates: [Candidate]) -> [String] {
        MediaSessionSelection.visible(candidates).map(\.id)
    }

    static func selected(_ candidates: [Candidate], current: String, preferred: String = "system") -> String? {
        MediaSessionSelection.selectedID(current: current, preferred: preferred, candidates: candidates)
    }

    static func main() {
        let empty = PlaybackState(bundleIdentifier: "com.apple.Music")
        precondition(empty.title.isEmpty && empty.artist.isEmpty && empty.album.isEmpty)
        precondition(!empty.hasMedia)
        precondition(visible([Candidate(id: "music", state: empty, isAvailable: true,
                                       isGeneric: false, isAppSource: true)]).isEmpty)
        print("PASS empty application has no invented metadata or selectable session")

        let closed = source("music", available: false, playing: true)
        let paused = source("spotify", app: "spotify", playing: false)
        precondition(visible([closed, paused]) == ["spotify"])
        precondition(selected([closed, paused], current: "music", preferred: "music") == "spotify")
        print("PASS closed apps disappear while independent paused sessions survive")

        let playing = source("quicktime", app: "quicktime", playing: true)
        precondition(selected([paused, playing], current: "spotify") == "spotify")
        precondition(selected([paused, playing], current: "closed") == "quicktime")
        precondition(selected([paused, playing], current: "closed", preferred: "spotify") == "spotify")
        print("PASS selection stays stable and closed-source fallback honors preference then playback")

        let generic = source("system", app: "quicktime", title: "Old document", generic: true, appSource: false)
        let front = source("quicktime", app: "quicktime", title: "Current front document")
        precondition(visible([generic, front]) == ["quicktime"])
        precondition(selected([generic, front], current: "system") == "quicktime")
        print("PASS dedicated app session replaces stale generic metadata and control target")

        let browser = source("system", app: "chrome", title: "Video A", generic: true, appSource: false)
        let tabA = source("tab-a", app: "chrome", title: "Video A", appSource: false)
        let tabB = source("tab-b", app: "chrome", title: "Video B", appSource: false)
        precondition(visible([browser, tabA, tabB]) == ["tab-a", "tab-b"])
        precondition(selected([browser, tabA, tabB], current: "system") == "tab-a")
        precondition(selected([tabA, tabB], current: "tab-a") == "tab-a")
        precondition(selected([tabB], current: "tab-a") == "tab-b")
        print("PASS exact browser tab identity survives selection and tab-close fallback")

        let duplicateTitle = source("tab-c", app: "chrome", title: "Video A", appSource: false)
        precondition(visible([browser, tabA, duplicateTitle]) == ["system", "tab-a", "tab-c"])
        precondition(selected([browser, tabA, duplicateTitle], current: "system") == "system")
        precondition(visible([browser, tabB]) == ["system", "tab-b"])
        print("PASS ambiguous or unmatched browser tabs never silently change control target")

        let otherApp = source("music", app: "music", title: "Video A")
        precondition(visible([browser, otherApp]) == ["system", "music"])
        precondition(selected([], current: "system") == nil)
        precondition(selected([closed], current: "music") == nil)
        print("PASS same titles in different apps remain distinct; no sessions yields no selection")
    }
}
