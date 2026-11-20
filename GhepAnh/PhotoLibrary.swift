import SwiftUI
import Photos
import PhotosUI

@MainActor final class PhotoLibrary: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var assets: [PHAsset] = []
    @Published var permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    let manager = PHCachingImageManager()
    private var byID: [String: PHAsset] = [:]

    override init() {
        super.init()
        manager.allowsCachingHighQualityImages = false
        PHPhotoLibrary.shared().register(self)
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    func requestAccess() async {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        reload()
    }

    func reload() {
        permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard permission == .authorized || permission == .limited else {
            assets = []; byID = [:]; return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var images: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in images.append(asset) }
        assets = images
        byID = Dictionary(uniqueKeysWithValues: images.map { ($0.localIdentifier, $0) })
    }

    func asset(_ identifier: String) -> PHAsset? { byID[identifier] }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.reload() }
    }
}

struct AssetThumbnail: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    @State private var image: UIImage?
    @State private var requestID = PHInvalidImageRequestID

    var body: some View {
        GeometryReader { box in
            ZStack {
                Color(.systemGray6)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: box.size.width, height: box.size.height).clipped()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            requestID = manager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFill, options: options) { result, info in
                    guard (info?[PHImageCancelledKey] as? Bool) != true, let result else { return }
                    Task { @MainActor in image = result }
                }
        }
        .onDisappear {
            if requestID != PHInvalidImageRequestID { manager.cancelImageRequest(requestID) }
            requestID = PHInvalidImageRequestID
        }
    }
}

struct LimitedPhotoPicker: UIViewControllerRepresentable {
    let finished: () -> Void
    func makeUIViewController(context: Context) -> Host { Host(finished: finished) }
    func updateUIViewController(_ controller: Host, context: Context) {}
    final class Host: UIViewController {
        let finished: () -> Void
        private var presented = false
        init(finished: @escaping () -> Void) { self.finished = finished; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !presented else { return }
            presented = true
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self) { [weak self] _ in
                Task { @MainActor in self?.finished() }
            }
        }
    }
}
