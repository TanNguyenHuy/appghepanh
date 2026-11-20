import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

struct PhotoItem: Identifiable {
    let id = UUID()
    let url: URL
    let thumbnail: UIImage
}

@MainActor final class Editor: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var preview: UIImage?
    @Published var selected: UUID?
    @Published var busy = false
    @Published var status = "Chọn ảnh → ghép 2×2 / 5 / 6 → Xong để lưu vào Ảnh."
    @Published var error: String?
    private var generation = 0
    private let work = DispatchQueue(label: "GhepAnh.render", qos: .userInitiated)

    func importPhotos(_ results: [PHPickerResult]) {
        guard !results.isEmpty else { return }
        guard photos.count + results.count <= 6 else {
            error = "Tối đa 6 ảnh mỗi lượt. Các ảnh đang chọn vẫn được giữ."; return
        }
        busy = true
        Task {
            var imported: [PhotoItem] = []
            var importedURLs: [URL] = []
            do {
                for result in results {
                    let url = try await Self.copyPhoto(result.itemProvider)
                    importedURLs.append(url)
                    let image = try await Task.detached(priority: .userInitiated) {
                        try Collage.thumbnail(url, maxEdge: 160)
                    }.value
                    imported.append(PhotoItem(url: url, thumbnail: UIImage(cgImage: image)))
                }
                photos += imported
                selected = photos.last?.id
                busy = false
                updatePreview()
            } catch {
                for url in importedURLs { try? FileManager.default.removeItem(at: url) }
                busy = false
                self.error = error.localizedDescription
            }
        }
    }

    private static func copyPhoto(_ provider: NSItemProvider) async throws -> URL {
        let identifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { source, error in
                guard let source = source else {
                    continuation.resume(throwing: error ?? Failure("Chưa tải được ảnh, hãy kiểm tra kết nối iCloud.")); return
                }
                do {
                    let name = UUID().uuidString + "." + (source.pathExtension.isEmpty ? "heic" : source.pathExtension)
                    let target = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try FileManager.default.copyItem(at: source, to: target)
                    continuation.resume(returning: target)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func updatePreview() {
        generation += 1
        let current = generation
        let urls = photos.map(\.url)
        guard (4...6).contains(urls.count) else {
            preview = nil
            status = "Đã chọn \(urls.count) ảnh. Chọn thêm hoặc nhân đôi để đủ 4 ô."
            return
        }
        work.async {
            let result = Result { try Collage.render(urls, size: CGSize(width: 600, height: 800)) }
            Task { @MainActor in
                guard current == self.generation else { return }
                switch result {
                case .success(let image):
                    self.preview = UIImage(cgImage: image)
                    self.status = "PNG 6928 × 9237 • viền trắng mảnh • Xong để lưu."
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    func duplicate() {
        guard photos.count < 6, let photo = photos.first(where: { $0.id == selected }) else { return }
        let item = PhotoItem(url: photo.url, thumbnail: photo.thumbnail)
        let index = photos.firstIndex(where: { $0.id == selected })!
        photos.insert(item, at: index+1)
        selected = item.id
        updatePreview()
    }

    func remove() {
        let removed = photos.first { $0.id == selected }?.url
        photos.removeAll { $0.id == selected }
        if let url = removed, !photos.contains(where: { $0.url == url }) {
            try? FileManager.default.removeItem(at: url)
        }
        selected = photos.last?.id
        updatePreview()
    }

    func move(_ delta: Int) {
        guard let index = photos.firstIndex(where: { $0.id == selected }), photos.indices.contains(index+delta) else { return }
        photos.swapAt(index, index+delta)
        updatePreview()
    }

    func save() {
        guard (4...6).contains(photos.count), !busy else { return }
        busy = true
        status = "Đang lưu vào thư viện Ảnh…"
        let urls = photos.map(\.url)
        Task {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                busy = false
                error = "Cho phép thêm ảnh trong Cài đặt → Ghép Ảnh → Ảnh, rồi thử lại."
                return
            }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    work.async {
                        do { try Collage.writePNG(urls, to: destination); continuation.resume() }
                        catch { continuation.resume(throwing: error) }
                    }
                }
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: destination, options: nil)
                }
                photos = []
                preview = nil
                selected = nil
                generation += 1
                for url in Set(urls) { try? FileManager.default.removeItem(at: url) }
                status = "Đã lưu vào Ảnh. Chọn ảnh cho lượt tiếp theo."
            } catch { self.error = error.localizedDescription }
            try? FileManager.default.removeItem(at: destination)
            busy = false
        }
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    let limit: Int
    let finished: ([PHPickerResult]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = max(1, limit)
        config.selection = .ordered
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let finished: ([PHPickerResult]) -> Void
        init(_ finished: @escaping ([PHPickerResult]) -> Void) { self.finished = finished }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            finished(results)
        }
    }
}

struct EditorView: View {
    @StateObject private var editor = Editor()
    @State private var picking = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ghép ảnh").font(.title2.bold())
                Spacer()
                Button("Xong", action: editor.save)
                    .buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(!(4...6).contains(editor.photos.count) || editor.busy)
            }.padding().foregroundStyle(.white)
            ZStack {
                Color.black
                if let image = editor.preview {
                    Image(uiImage: image).resizable().scaledToFit().padding(12)
                } else {
                    Text("4 ảnh: 2×2\n5 hoặc 6 ảnh: tự đổi mẫu")
                        .multilineTextAlignment(.center).foregroundStyle(.white)
                }
            }.frame(maxHeight: .infinity)
            VStack(spacing: 12) {
                HStack {
                    Button("Chọn ảnh", systemImage: "plus") { picking = true }
                        .disabled(editor.photos.count >= 6 || editor.busy)
                    Spacer()
                    Text("\(editor.photos.count) / 6 ảnh").foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(editor.photos.enumerated()), id: \.element.id) { index, photo in
                            Button { editor.selected = photo.id } label: {
                                VStack {
                                    Image(uiImage: photo.thumbnail).resizable().scaledToFill()
                                        .frame(width: 64, height: 72).clipped()
                                    Text("\(index+1)").font(.caption)
                                }.padding(3).border(editor.selected == photo.id ? Color.pink : Color.clear, width: 2)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(height: 105)
                HStack {
                    Button { editor.move(-1) } label: { Image(systemName: "arrow.left") }.accessibilityLabel("Đưa ảnh sang trái")
                    Button { editor.move(1) } label: { Image(systemName: "arrow.right") }.accessibilityLabel("Đưa ảnh sang phải")
                    Spacer()
                    Button("Nhân đôi", action: editor.duplicate).disabled(editor.photos.count >= 6)
                    Button("Bỏ ảnh", action: editor.remove)
                }.disabled(editor.busy || editor.selected == nil)
                Text(editor.status).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }.padding().background(Color(.systemBackground))
        }.background(.black)
        .sheet(isPresented: $picking) {
            PhotoPicker(limit: 6-editor.photos.count) { results in
                picking = false
                editor.importPhotos(results)
            }
        }
        .alert("Chưa hoàn thành", isPresented: Binding(get: { editor.error != nil }, set: { if !$0 { editor.error = nil } })) {
            Button("Đóng", role: .cancel) { editor.error = nil }
        } message: { Text(editor.error ?? "") }
    }
}

@main struct GhepAnhApp: App {
    var body: some Scene { WindowGroup { EditorView() } }
}
