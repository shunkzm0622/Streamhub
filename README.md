# Shun Entertainment cho iOS

Mở ShunEntertainment.xcodeproj trên macOS có Xcode 15 trở lên. Chọn scheme ShunEntertainment, chọn iPhone Simulator và bấm Run. Dự án hỗ trợ iOS 16 trở lên, iPhone và iPad.

Để chạy trên iPhone thật, chọn Signing & Capabilities, chọn Team của bạn và đổi Bundle Identifier nếu cần. Chọn iPhone làm thiết bị chạy. Để phát hành qua TestFlight, dùng Product → Archive và ký bằng tài khoản Apple Developer của bạn.

Giao diện IPTV và danh sách mặc định được đóng gói trong App/Web. App dùng WKWebView, ưu tiên HLS gốc trên iOS. Traffic camera mở trang Traffic.Camera.HCM trực tuyến. Luồng phát, bản đồ và các thư viện media từ CDN cần mạng. Khả năng phát từng kênh phụ thuộc nguồn, codec và HTTPS. Nguồn, yêu thích và trạng thái tín hiệu lưu riêng trên thiết bị.

Bản sao lấy từ shunkzm0622/Streamhub. Việc chỉnh App/Web chỉ tác động bản iOS. GitHub Actions trên nhánh ios-ipa build cho thiết bị arm64. Mở lần chạy Build Shun Entertainment IPA và tải artifact ShunEntertainment-unsigned-IPA. Giải nén rồi ký IPA bằng chứng chỉ và provisioning profile phù hợp trước khi cài lên thiết bị thật.
