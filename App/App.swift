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
        web.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent())
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
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

    private var updating = false
    private struct Runs: Decodable {
        struct Run: Decodable { let run_number: Int }
        let workflow_runs: [Run]
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
            let endpoint = URL(string: "https://api.github.com/repos/shunkzm0622/Streamhub/actions/workflows/ios.yml/runs?branch=ios-ipa&status=success&per_page=1")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let latest = try JSONDecoder().decode(Runs.self, from: data).workflow_runs.first?.run_number else { throw URLError(.badServerResponse) }
            let installed = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
            guard latest > installed else { status("Bạn đang dùng build \\(installed), đã cập nhật."); return }
            status("Đang tải IPA build \\(latest)…")
            let url = URL(string: "https://github.com/shunkzm0622/Streamhub/releases/download/ios-build-\\(latest)/ShunEntertainment-unsigned.ipa")!
            let (temp, result) = try await URLSession.shared.download(from: url)
            guard (result as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("ShunEntertainment-\\(latest).ipa")
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            try FileManager.default.moveItem(at: temp, to: file)
            let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            status("Chọn ứng dụng ký hoặc Lưu vào Tệp, rồi nhập IPA để ký và cài đè.")
            present(sheet, animated: true)
        } catch {
            status("Chưa thể cập nhật. Kiểm tra kết nối và thử lại.")
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "checkUpdate", message.frameInfo.isMainFrame,
           message.frameInfo.request.url?.standardizedFileURL == entry.standardizedFileURL {
            Task { await checkForUpdate() }
            return
        }
        guard message.name == "exportChannels", message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.standardizedFileURL == entry.standardizedFileURL,
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
