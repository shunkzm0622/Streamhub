import UIKit
import WebKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = PlayerController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class PlayerController: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var web: WKWebView!
    private var entry: URL!

    private let playerURL = URL(string: "https://shun-player.invalid/index.html")!
    private var pendingPlayerNavigation = false
    private var legacyEntry: URL?
    private let migrationFlag = "shunPlayerStorageMigrated"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.035, green: 0.055, blue: 0.106, alpha: 1)
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            NSLog("Audio session: %@", error.localizedDescription)
        }
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(self, name: "exportChannels")
        config.userContentController.add(self, name: "checkUpdate")
        web = WKWebView(frame: .zero, configuration: config)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([web.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
                                    web.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
                                    web.topAnchor.constraint(equalTo: safe.topAnchor),
                                    web.bottomAnchor.constraint(equalTo: safe.bottomAnchor)])
        entry = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web")!
        restoreWebUpdate()
        if UserDefaults.standard.bool(forKey: migrationFlag) {
            openPlayer()
        } else {
            let previousBuild = UserDefaults.standard.integer(forKey: "webBuild")
            let saved = updatesRoot.appendingPathComponent(String(previousBuild)).appendingPathComponent("index.html")
            let legacy = previousBuild > 0 && FileManager.default.fileExists(atPath: saved.path) ? saved : entry!
            legacyEntry = legacy
            web.loadFileURL(legacy, allowingReadAccessTo: legacy.deletingLastPathComponent())
        }
    }

    private func openPlayer(seed: [String: String]? = nil) {
        do {
            var html = try String(contentsOf: entry, encoding: .utf8)
            let channels = try Data(contentsOf: entry.deletingLastPathComponent().appendingPathComponent("channels.js"))
            html = html.replacingOccurrences(of: "<script src=\"channels.js\"></script>",
                with: "<script src=\"data:text/javascript;base64,\(channels.base64EncodedString())\"></script>")
            if let seed = seed {
                let data = try JSONEncoder().encode(seed).base64EncodedString()
                let restore = """
                <script>
                try {
                  const bytes = Uint8Array.from(atob('\(data)'), c => c.charCodeAt(0));
                  for (const [k,v] of Object.entries(JSON.parse(new TextDecoder().decode(bytes)))) {
                    if (localStorage.getItem(k) === null) localStorage.setItem(k,v);
                  }
                  window.shunDidRestore = true;
                } catch {}
                </script>
                """
                html = html.replacingOccurrences(of: "<head>", with: "<head>" + restore)
            }
            pendingPlayerNavigation = true
            web.loadSimulatedRequest(URLRequest(url: playerURL), responseHTML: html)
        } catch {
            let alert = UIAlertController(title: "Không mở được trình phát", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Thử lại", style: .default) { _ in self.openPlayer(seed: seed) })
            present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let legacy = legacyEntry, webView.url?.standardizedFileURL == legacy.standardizedFileURL {
            legacyEntry = nil
            let snapshot = """
            Object.fromEntries(Object.keys(localStorage)
              .filter(k => k === 'streamhub_v1_library' || k === 'streamhub_v1_favorites' || k.startsWith('streamhub.signal.v1:'))
              .map(k => [k,localStorage.getItem(k)]))
            """
            webView.evaluateJavaScript(snapshot) { value, _ in self.openPlayer(seed: value as? [String: String]) }
        } else if webView.url == playerURL && !UserDefaults.standard.bool(forKey: migrationFlag) {
            webView.evaluateJavaScript("window.shunDidRestore === true") { value, _ in
                if value as? Bool == true { UserDefaults.standard.set(true, forKey: self.migrationFlag) }
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if pendingPlayerNavigation, url == playerURL, navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.navigationType == .other {
            pendingPlayerNavigation = false
            decisionHandler(.allow)
            return
        }
        let external = ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        if navigationAction.targetFrame == nil || (navigationAction.targetFrame?.isMainFrame == true && external) {
            decisionHandler(.cancel)
            if external && navigationAction.navigationType == .linkActivated { UIApplication.shared.open(url) }
            else if external && navigationAction.sourceFrame.isMainFrame && navigationAction.targetFrame == nil { UIApplication.shared.open(url) }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "Shun Entertainment", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Đồng ý", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    private struct WebUpdate: Decodable {
        let native: String
        let build: Int
        let html: String
        let channels: String
    }
    private var bundledBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }
    private var nativeID: String {
        guard let url = Bundle.main.url(forResource: "native-id", withExtension: "txt", subdirectory: "Web") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    private var updatesRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WebUpdates", isDirectory: true)
    }
    private var activeBuild: Int = 0

    private func restoreWebUpdate() {
        activeBuild = bundledBuild
        let number = UserDefaults.standard.integer(forKey: "webBuild")
        guard number > bundledBuild, !nativeID.isEmpty else { return }
        let dir = updatesRoot.appendingPathComponent(String(number))
        guard (try? String(contentsOf: dir.appendingPathComponent("native-id.txt"), encoding: .utf8)) == nativeID,
              ["index.html","channels.js"].allSatisfy({ FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }) else { return }
        entry = dir.appendingPathComponent("index.html")
        activeBuild = number
    }

    private func apply(_ update: WebUpdate) throws {
        guard !update.html.isEmpty, !update.channels.isEmpty else { throw URLError(.cannotDecodeContentData) }
        let fm = FileManager.default
        let stage = updatesRoot.appendingPathComponent(UUID().uuidString)
        let dir = updatesRoot.appendingPathComponent(String(update.build))
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        try update.html.write(to: stage.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try update.channels.write(to: stage.appendingPathComponent("channels.js"), atomically: true, encoding: .utf8)
        try update.native.write(to: stage.appendingPathComponent("native-id.txt"), atomically: true, encoding: .utf8)
        if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
        try fm.moveItem(at: stage, to: dir)
        UserDefaults.standard.set(update.build, forKey: "webBuild")
        restoreWebUpdate()
        openPlayer()
    }

    private var updating = false
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        var build: Int? {
            let prefix = "ios-build-"
            guard !draft, !prerelease, tag_name.hasPrefix(prefix),
                  assets.contains(where: { $0.name == "web-update.json" }),
                  assets.contains(where: { $0.name == "ShunEntertainment-unsigned.ipa" }) else { return nil }
            return Int(tag_name.dropFirst(prefix.count))
        }
    }
    private func requireOK(_ response: URLResponse, step: String) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw NSError(domain: "ShunUpdate", code: code, userInfo: [NSLocalizedDescriptionKey: "\(step): HTTP \(code)"])
        }
    }

    @MainActor
    private func checkForUpdate() async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        func status(_ text: String) {
            web.callAsyncJavaScript("document.getElementById('updateStatus').textContent = text",
                                    arguments: ["text": text], in: nil, in: .page, completionHandler: nil)
        }
        do {
            status("Đang kiểm tra GitHub…")
            let endpoint = URL(string: "https://api.github.com/repos/shunkzm0622/Streamhub/releases?per_page=100")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
            try requireOK(response, step: "Đọc danh sách bản phát hành")
            let releases = try JSONDecoder().decode([Release].self, from: data)
            guard let release = releases.filter({ $0.build != nil }).max(by: { ($0.build ?? 0) < ($1.build ?? 0) }),
                  let latest = release.build,
                  let payloadURL = release.assets.first(where: { $0.name == "web-update.json" })?.browser_download_url,
                  let ipaURL = release.assets.first(where: { $0.name == "ShunEntertainment-unsigned.ipa" })?.browser_download_url else {
                status("GitHub chưa có bản phát hành iOS đủ tệp."); return
            }
            guard latest > activeBuild else { status("Bạn đang dùng build \(activeBuild), đã cập nhật."); return }
            status("Đang tải gói cập nhật…")
            let (payload, reply) = try await URLSession.shared.data(from: payloadURL)
            try requireOK(reply, step: "Tải web-update.json")
            let update = try JSONDecoder().decode(WebUpdate.self, from: payload)
            guard update.build == latest else { throw URLError(.cannotDecodeContentData) }
            if !nativeID.isEmpty && update.native == nativeID {
                try apply(update)
                return
            }
            status("Bản mới thay đổi phần iOS. Đang tải IPA để ký…")
            let (temp, result) = try await URLSession.shared.download(from: ipaURL)
            try requireOK(result, step: "Tải IPA")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("ShunEntertainment-\(latest).ipa")
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            try FileManager.default.moveItem(at: temp, to: file)
            let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            status("Chọn ứng dụng ký hoặc Lưu vào Tệp, rồi nhập IPA để ký và cài đè.")
            present(sheet, animated: true)
        } catch {
            status("Chưa thể cập nhật: \(error.localizedDescription) [\((error as NSError).code)]")
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "checkUpdate", message.frameInfo.isMainFrame,
           message.frameInfo.request.url == playerURL, web.url == playerURL {
            Task { await checkForUpdate() }
            return
        }
        guard message.name == "exportChannels", message.frameInfo.isMainFrame,
              message.frameInfo.request.url == playerURL, web.url == playerURL,
              let json = message.body as? String else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shun-entertainment-channels.json")
        do {
            try Data(json.utf8).write(to: file, options: .atomic)
            let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            present(sheet, animated: true)
        } catch {
            let alert = UIAlertController(title: "Không xuất được danh sách", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Đóng", style: .default))
            present(alert, animated: true)
        }
    }
}
