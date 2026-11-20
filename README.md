# Ghép Ảnh cho iPhone — nguồn và quy trình build

**Bản thử, chưa kiểm tra trên iPhone thật.** Workflow macOS build và kiểm tra mã, sau khi thành công sẽ tạo artifact IPA chưa ký để sideload. Không đổi đuôi file exe/zip thành IPA.

Bản 1.1 hiển thị **kho ảnh dạng lưới 4 cột ở trên và ảnh đã chọn ở dưới**. Mỗi lần chạm ảnh thêm một ô mới: có thể chạm cùng ảnh nhiều lần, theo đúng thứ tự bấm. Dấu × trên mỗi ảnh dưới chỉ bỏ đúng ô đó. Chọn đủ 4/5/6 ô rồi bấm **Bắt đầu** để xem ghép; bấm **Xong** tự lưu vào Ảnh và quay lại thư viện, sẵn sàng chọn bộ tiếp theo. Quay lại từ màn hình xem ghép vẫn giữ nguyên các ảnh đã chọn.

App cần quyền **đọc và thêm ảnh**. Khi chỉ cấp quyền truy cập một số ảnh, lưới chỉ hiện số ảnh đó và có nút **Chọn thêm ảnh**. Khi từ chối, app có nút mở Cài đặt. Chỉ yêu cầu thumbnail cho các ô đang hiển thị bằng PHCachingImageManager; chưa tải ảnh gốc lúc chạm chọn. Khi bấm Bắt đầu, app mới lấy dữ liệu ảnh hiện tại từ Photos/iCloud; ảnh lặp chỉ tải nguồn một lần trong mỗi bộ. Không tải ảnh cá nhân lên server.

Đọc HEIC/JPEG/PNG bằng ImageIO. 4 ảnh tự ghép 2×2, 5 ảnh có 2 ô trái + 3 ô phải, 6 ảnh có 2 cột × 3 hàng. Chưa hỗ trợ ghép video, nên thư viện chỉ liệt kê ảnh. Không thêm các tab Live/video/album chưa có chức năng.

Bấm **Xong** để dựng PNG 6928×9237 (khoảng 64 MP, theo ảnh thông tin Meitu mà bạn cung cấp) và thêm trực tiếp vào thư viện Ảnh sau khi bạn cấp quyền. Nguồn không bị sửa; cắt giữa ảnh để lấp ô và có viền trắng mảnh bên trong. PNG không nén mất dữ liệu nhưng việc thu nhỏ từ nguồn lớn hơn vẫn giảm số điểm ảnh. Đầu ra sRGB 8-bit SDR, không giữ HDR. HEIF 6,6 MB của Meitu không tương đương PNG 6,6 MB; tốc độ và dung lượng phải đo trên máy thực tế.

## Build khi chỉ có Windows

Cần một repository GitHub riêng và quyền chạy Actions trên máy macOS của GitHub. Chép **nội dung thư mục ios này vào gốc repository**, bao gồm `.github/workflows/build-ipa.yml`. Workflow dùng XcodeGen để tạo project, chạy unit test trên simulator rồi build app cho iPhone. Artifact **GhepAnh-IPA** chứa `GhepAnh-unsigned.ipa` và mã SHA-256. Không tải ảnh cá nhân lên GitHub.

Repository đã được bạn chỉ định: https://github.com/TanNguyenHuy/appghepanh, nhánh `codex/iphone-hd`. Workflow có thể tiêu tốn phút Actions của tài khoản; repository riêng tư có giới hạn/chi phí theo gói. Kiểm tra gồm unit test bố cục/HD/thứ tự ảnh, chọn lặp độc lập từng ô, và UI test chọn cùng ảnh 4 lần → xem ghép → quay lại → lưu → trở lại thư viện trống lựa chọn. Ảnh UI test là ảnh màu giả lập, không phải ảnh cá nhân. Artifact chứa IPA, SHA-256 và ảnh chụp giao diện simulator.

## Cài từ Windows sau khi có IPA

IPA trên là **chưa ký**, không phải file cài ngay bằng cách chạm. Cần công cụ ký/cài như **AltStore Classic + AltServer**, Apple ID của chính bạn, iPhone cắm USB và thao tác Trust. Bạn tự nhập Apple ID/mật khẩu trong công cụ chính thức, không gửi vào chat hoặc repository.

Tài liệu [AltStore Windows chính thức](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) yêu cầu iTunes/iCloud phù hợp, cài AltServer, kết nối iPhone, cài AltStore rồi Trust hồ sơ. Với iOS 16+, cần bật Developer Mode trong Cài đặt → Quyền riêng tư & Bảo mật theo hướng dẫn. Không thể tự bấm xác nhận hoặc nhập mật khẩu trên iPhone từ môi trường Codex này.

Apple ID miễn phí có giới hạn ký/cài và thường cần làm mới ứng dụng sau 7 ngày; xem [Apple Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account/). Chưa cài sideload hoặc chỉnh iPhone trong lượt chuẩn bị này.

Nguồn API: [PHPicker](https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios), [ImageIO thumbnail](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)), [PHAssetCreationRequest](https://developer.apple.com/documentation/photos/phassetcreationrequest).
