import SwiftUI
import Photos
import UniformTypeIdentifiers

struct PhotoItem: Identifiable {
    let id = UUID()
    let assetID: String
}

@MainActor final class Editor: ObservableObject {
    @Published private(set) var photos: [PhotoItem] = []
    @Published var preview: UIImage?
    @Published var selected: UUID?
    @Published var busy = false
    @Published var showingPreview = false
    @Published var status = "Chạm ảnh để chọn. Chạm lại để dùng cùng ảnh thêm lần nữa."
    @Published var error: String?
    private var sourceFiles: [String: URL] = [:]
    private let work = DispatchQueue(label: "GhepAnh.render", qos: .userInitiated)

    func pick(_ assetID: String) {
        guard !busy, photos.count < 6 else { return }
        let item = PhotoItem(assetID: assetID)
        photos.append(item)
        selected = item.id
        preview = nil
        status = photos.count == 6 ? "Đã đủ 6 ảnh. Bấm Bắt đầu để xem ảnh ghép." :
            "Đã chọn \(photos.count) ảnh. Có thể chạm lại cùng ảnh."
    }

    func count(_ assetID: String) -> Int { photos.filter { $0.assetID == assetID }.count }

    func remove(_ id: UUID) {
        guard !busy, let item = photos.first(where: { $0.id == id }) else { return }
        photos.removeAll { $0.id == id }
        if !photos.contains(where: { $0.assetID == item.assetID }), let url = sourceFiles.removeValue(forKey: item.assetID) {
            try? FileManager.default.removeItem(at: url)
        }
        if selected == id { selected = photos.last?.id }
        if showingPreview {
            if photos.count < 4 { showingPreview = false; preview = nil }
            else { preparePreview() }
        }
        status = "Đã chọn \(photos.count) / 6 ảnh."
    }

    func move(_ delta: Int) {
        guard !busy, let index = photos.firstIndex(where: { $0.id == selected }), photos.indices.contains(index+delta) else { return }
        photos.swapAt(index, index+delta)
        if showingPreview { preparePreview() }
    }

    private static func exportSource(_ identifier: String) async throws -> URL {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw Failure("Ảnh không còn trong thư viện được phép truy cập. Hãy chọn lại ảnh.")
        }
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                guard (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                guard let data else {
                    let failure = (info?[PHImageErrorKey] as? Error) ?? Failure("Chưa tải được ảnh; hãy kiểm tra kết nối iCloud rồi thử lại.")
                    continuation.resume(throwing: failure); return
                }
                do {
                    let ext = uti.flatMap { UTType($0)?.preferredFilenameExtension } ?? "image"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"."+ext)
                    try data.write(to: url, options: .atomic)
                    continuation.resume(returning: url)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func sources() async throws -> [URL] {
        for photo in photos where sourceFiles[photo.assetID] == nil {
            sourceFiles[photo.assetID] = try await Self.exportSource(photo.assetID)
        }
        return try photos.map {
            guard let url = sourceFiles[$0.assetID] else { throw Failure("Chưa tải được ảnh nguồn.") }
            return url
        }
    }

    func preparePreview() {
        guard (4...6).contains(photos.count), !busy else { return }
        busy = true
        status = "Đang chuẩn bị ảnh ghép…"
        Task {
            do {
                let urls = try await sources()
                let image: CGImage = try await withCheckedThrowingContinuation { continuation in
                    work.async {
                        do { continuation.resume(returning: try Collage.render(urls, size: CGSize(width: 600, height: 800))) }
                        catch { continuation.resume(throwing: error) }
                    }
                }
                preview = UIImage(cgImage: image)
                showingPreview = true
                status = "PNG HD 6928 × 9237. Bấm Xong để lưu vào Ảnh."
            } catch {
                self.error = error.localizedDescription
                status = "Chưa tải được ảnh ghép. Các ảnh đã chọn vẫn được giữ."
            }
            busy = false
        }
    }

    func save() {
        guard (4...6).contains(photos.count), !busy else { return }
        busy = true
        status = "Đang lưu vào thư viện Ảnh…"
        Task {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                busy = false
                status = "Chưa lưu được. Các ảnh đã chọn vẫn được giữ."
                error = "Cho phép thêm ảnh trong Cài đặt → Ghép Ảnh → Ảnh rồi thử lại."
                return
            }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
            do {
                let urls = try await sources()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    work.async {
                        do { try Collage.writePNG(urls, to: destination); continuation.resume() }
                        catch { continuation.resume(throwing: error) }
                    }
                }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: destination, options: nil)
                }
                photos = []; preview = nil; selected = nil; showingPreview = false
                for url in sourceFiles.values { try? FileManager.default.removeItem(at: url) }
                sourceFiles = [:]
                status = "Đã lưu vào Ảnh. Chọn ảnh cho lượt tiếp theo."
            } catch {
                self.error = error.localizedDescription
                status = "Chưa lưu được. Các ảnh đã chọn vẫn được giữ."
            }
            try? FileManager.default.removeItem(at: destination)
            busy = false
        }
    }
}
