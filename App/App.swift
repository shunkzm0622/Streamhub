import SwiftUI
import AVKit
import KSPlayer
import WebKit

struct Station: Decodable, Identifiable {
    struct Server: Decodable { let name: String; let url: String }
    let id: String
    let name: String
    let group: String
    let logo: String?
    let servers: [Server]
}

@main
struct ShunNativeApp: App {
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
    var body: some Scene { WindowGroup { Television().preferredColorScheme(.dark) } }
}

@MainActor
final class Playback: NSObject, ObservableObject, KSPlayerLayerDelegate {
    @Published var layer: KSPlayerLayer?
    @Published var status = ""
    @Published var station: Station?
    @Published var server = 0
    func tune(_ channel: Station, index: Int = 0) {
        guard channel.servers.indices.contains(index),
              let url = URL(string: channel.servers[index].url) else { return }
        layer?.delegate = nil
        layer?.stop()
        station = channel
        server = index
        status = "Đang kết nối…"
        KSOptions.firstPlayerType = url.pathExtension.lowercased() == "mpd" ? KSMEPlayer.self : KSAVPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        layer = KSPlayerLayer(url: url, isAutoPlay: true, options: KSOptions(), delegate: self)
    }
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        guard layer === self.layer else { return }
        if state == .bufferFinished { status = "" }
        if state == .buffering { status = "Đang tải…" }
    }
    func player(layer: KSPlayerLayer, finish error: Error?) {
        guard layer === self.layer else { return }
        status = error?.localizedDescription ?? "Đã kết thúc"
    }
    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {}
    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}
}

struct VideoSurface: UIViewRepresentable {
    let layer: KSPlayerLayer
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        if let video = layer.player.view {
            host.addSubview(video)
            video.frame = host.bounds
            video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        return host
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct TrafficCamera: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.load(URLRequest(url: URL(string: "https://shunkzm0622.github.io/Traffic.Camera.HCM/")!))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct Television: View {
    @StateObject private var playback = Playback()
    @State private var catalog: [Station] = []
    @State private var query = ""
    @State private var group = ""
    @State private var camera = false
    @State private var message = ""
    @State private var latestIPA: URL?
    @State private var latestBuild = 0
    @State private var checking = false
    @State private var showUpdate = false
    private struct NativeRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    @MainActor private func checkUpdate(manual: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let installed = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
            var page = 1
            var best = installed
            var download: URL?
            while true {
                let url = URL(string: "https://api.github.com/repos/shunkzm0622/Streamhub/releases?per_page=100&page=\(page)")!
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let releases = try JSONDecoder().decode([NativeRelease].self, from: data)
                for release in releases where !release.draft && !release.prerelease && release.tag_name.hasPrefix("ios-native-") {
                    guard let build = Int(release.tag_name.dropFirst("ios-native-".count)), build > best,
                          let asset = release.assets.first(where: { $0.name == "ShunNative-unsigned.ipa" }) else { continue }
                    best = build
                    download = asset.browser_download_url
                }
                if releases.count < 100 { break }
                page += 1
            }
            latestIPA = download
            latestBuild = best
            if manual {
                if download != nil { showUpdate = true }
                else { message = "Bạn đang dùng Shun Native Build \(installed), phiên bản mới nhất." }
            }
        } catch {
            if manual { message = "Chưa kiểm tra được bản mới. \(error.localizedDescription)" }
        }
    }
    @State private var onlyFavorites = false
    @AppStorage("nativeFavorites") private var favoriteData = Data()
    private var favorites: Set<String> { (try? JSONDecoder().decode(Set<String>.self, from: favoriteData)) ?? [] }
    private var visible: [Station] {
        let saved = favorites
        return catalog.filter { (group.isEmpty || $0.group == group) && (!onlyFavorites || saved.contains($0.id)) && (query.isEmpty || $0.name.localizedStandardContains(query) || $0.group.localizedStandardContains(query)) }
    }
    private func decode(_ data: Data) throws -> [Station] {
        let rows = try JSONDecoder().decode([Station].self, from: data).filter { !$0.servers.isEmpty }
        guard !rows.isEmpty else { throw URLError(.cannotParseResponse) }
        return rows
    }
    private var cache: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("stations.json") }
    private func refresh() async {
        do {
            let url = URL(string:"https://raw.githubusercontent.com/shunkzm0622/Streamhub/ios-native-swiftui/iptv_channels_grouped.json")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let updated = try decode(data)
            try data.write(to: cache, options: .atomic)
            catalog = updated
            message = "Đã cập nhật \(updated.count) kênh."
        } catch { message = error.localizedDescription }
    }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let layer = playback.layer { VideoSurface(layer: layer).id(ObjectIdentifier(layer)) }
                if !playback.status.isEmpty || playback.station == nil {
                    Text(playback.station == nil ? "Chọn kênh để xem" : playback.status).font(.caption).padding(8).background(.black.opacity(0.7)).allowsHitTesting(false)
                }
            }.aspectRatio(16/9, contentMode:.fit)
            HStack(spacing:8) {
                Text(playback.station?.name ?? "Shun Entertainment").font(.headline).lineLimit(1)
                Spacer(minLength:0)
                if let current = playback.station, current.servers.count > 1 {
                    Menu {
                        ForEach(current.servers.indices, id:\.self) { i in
                            Button { playback.tune(current,index:i) } label: {
                                if i == playback.server { Label(current.servers[i].name, systemImage:"checkmark") }
                                else { Text(current.servers[i].name) }
                            }
                        }
                    } label: { Text("Server ▾").font(.subheadline).padding(.horizontal,8).frame(height:44).controlChip() }
                }
                Button { playback.layer?.isPipActive = true } label: { Label("PiP",systemImage:"pip.enter").font(.subheadline).padding(.horizontal,8).frame(height:44).controlChip() }.disabled(playback.layer == nil)
                Menu {
                    Toggle("Chỉ hiện yêu thích", isOn: $onlyFavorites)
                    Button("Traffic Camera") { camera = true }
                    Button(latestIPA == nil ? "Kiểm tra cập nhật ứng dụng" : "Tải Build \(latestBuild)") {
                        if latestIPA != nil { showUpdate = true } else { Task { await checkUpdate(manual: true) } }
                    }.disabled(checking)
                    Button("Cập nhật danh sách") { Task { await refresh() } }
                } label: { Image(systemName:latestIPA == nil ? "ellipsis.circle" : "arrow.down.circle.fill").frame(width:38,height:44).controlChip() }
            }.padding(.horizontal,10).padding(.vertical,6).background(Color(red:0.06,green:0.10,blue:0.16))
            HStack {
                Image(systemName:"magnifyingglass")
                TextField("Tìm tên kênh, nhóm…",text:$query)
                Menu {
                    Button("Tất cả danh mục") { group = "" }
                    ForEach(Set(catalog.map(\.group)).sorted(),id:\.self) { item in Button(item) { group = item } }
                } label: { Label(group.isEmpty ? "Danh mục" : group,systemImage:"line.3.horizontal.decrease.circle").lineLimit(1) }
                Button { Task { await refresh() } } label: { Image(systemName:"arrow.clockwise").frame(width:36,height:44).controlChip() }.accessibilityLabel("Tải lại danh sách")
            }.padding(.horizontal,10).padding(.vertical,4)
            List(visible) { station in
                Button { playback.tune(station) } label: {
                    HStack {
                        AsyncImage(url: URL(string:station.logo ?? "")) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName:"tv") }.frame(width:48,height:32)
                        VStack(alignment:.leading) { Text(station.name).foregroundColor(.primary); Text(station.group).font(.caption).foregroundColor(.secondary) }
                        Spacer()
                        if playback.station?.id == station.id { Image(systemName:"speaker.wave.2.fill") }
                    }
                }.listRowBackground(Color(red:0.06,green:0.095,blue:0.15)).swipeActions {
                    Button("Yêu thích") {
                        var set = favorites
                        if !set.insert(station.id).inserted { set.remove(station.id) }
                        if let data = try? JSONEncoder().encode(set) { favoriteData = data }
                    }.tint(.orange)
                }
            }.listStyle(.plain)
        }.background(Color(red:0.035,green:0.055,blue:0.10)).tint(.mint).sheet(isPresented:$camera) {
            NavigationStack { TrafficCamera().navigationTitle("Traffic Camera").navigationBarTitleDisplayMode(.inline).toolbar { Button("Đóng") { camera = false } } }
        }.task {
            do {
                if let data = try? Data(contentsOf: cache), let rows = try? decode(data) { catalog = rows }
                else if let url = Bundle.main.url(forResource:"stations",withExtension:"json",subdirectory:"Web") { catalog = try decode(Data(contentsOf:url)) }
            } catch { message = error.localizedDescription }
            await checkUpdate(manual: false)
        }.confirmationDialog("Shun Native Build \(latestBuild)", isPresented:$showUpdate, titleVisibility:.visible) {
            if let url = latestIPA { Link("Tải IPA từ GitHub", destination:url) }
            Button("Để sau", role:.cancel) {}
        } message: { Text("Ký và cài đè IPA để cập nhật ứng dụng.") }
        .alert("Shun Native",isPresented:Binding(get:{ !message.isEmpty },set:{ if !$0 { message = "" } })) { Button("Đóng") { message = "" } } message: { Text(message) }
    }
}

private extension View {
    func controlChip() -> some View {
        self.foregroundStyle(.white)
            .background(Color(red:0.10,green:0.16,blue:0.24), in: RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Color.white.opacity(0.16)))
    }
}
