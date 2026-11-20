import SwiftUI
import Photos

struct SelectedStrip: View {
    @ObservedObject var editor: Editor
    @ObservedObject var library: PhotoLibrary

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(editor.photos.enumerated()), id: \.element.id) { index, photo in
                    ZStack(alignment: .topTrailing) {
                        Button { editor.selected = photo.id } label: {
                            VStack(spacing: 4) {
                                if let asset = library.asset(photo.assetID) {
                                    AssetThumbnail(asset: asset, manager: library.manager).frame(width: 48, height: 64)
                                } else {
                                    Color(.systemGray6).frame(width: 48, height: 64)
                                }
                                Text("\(index+1)").font(.caption).foregroundStyle(.secondary)
                            }.padding(3)
                                .overlay(Rectangle().stroke(editor.selected == photo.id ? Color.pink : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel("Ô ảnh \(index+1)")
                        Button { editor.remove(photo.id) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                                .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65))
                                .frame(width: 44, height: 44, alignment: .topTrailing)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).offset(x: 6, y: -3)
                            .accessibilityLabel("Bỏ ô ảnh \(index+1)")
                            .accessibilityIdentifier("selectedRemove-\(index)")
                    }
                }
            }.padding(.top, 6).padding(.horizontal, 3)
        }.frame(height: 100).disabled(editor.busy)
    }
}

struct EditorView: View {
    @StateObject private var editor = Editor()
    @StateObject private var library = PhotoLibrary()
    @Environment(\.scenePhase) private var scenePhase
    @State private var limitedPicker = false
    @State private var scrollAnchor: String?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        Group {
            if editor.showingPreview { previewScreen }
            else { libraryScreen }
        }
        .preferredColorScheme(.light)
        .task {
            // Unit tests use synthetic images and must not open a photo-permission prompt.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                await library.requestAccess()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { library.reload() } }
        .sheet(isPresented: $limitedPicker) {
            LimitedPhotoPicker { limitedPicker = false; library.reload() }
        }
        .alert("Chưa hoàn thành", isPresented: Binding(get: { editor.error != nil }, set: { if !$0 { editor.error = nil } })) {
            Button("Đóng", role: .cancel) { editor.error = nil }
        } message: { Text(editor.error ?? "") }
    }

    private var libraryScreen: some View {
        VStack(spacing: 0) {
            Text("Gần đây").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
            HStack(alignment: .top) {
                VStack(spacing: 8) {
                    Text("Tất cả").font(.headline)
                    Capsule().fill(Color.pink).frame(width: 28, height: 3)
                }
                Spacer()
                if library.permission == .limited {
                    Button("Chọn thêm ảnh") { limitedPicker = true }.font(.subheadline)
                } else {
                    Text("\(library.assets.count) ảnh").font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 3)

            if library.permission == .authorized || library.permission == .limited {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(library.assets, id: \.localIdentifier) { asset in
                            Button { editor.pick(asset.localIdentifier) } label: {
                                AssetThumbnail(asset: asset, manager: library.manager)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(alignment: .topTrailing) {
                                        if editor.count(asset.localIdentifier) > 0 {
                                            Text("×\(editor.count(asset.localIdentifier))")
                                                .font(.caption.bold()).foregroundStyle(.white)
                                                .padding(6).background(.pink, in: Capsule()).padding(5)
                                        }
                                    }
                            }.buttonStyle(.plain)
                                .disabled(editor.busy || editor.photos.count >= 6)
                                .accessibilityLabel("Thêm ảnh vào bộ ghép")
                                .accessibilityValue("Đã chọn \(editor.count(asset.localIdentifier)) lần")
                                .accessibilityIdentifier("libraryPhoto-\(asset.localIdentifier)")
                        }
                    }.scrollTargetLayout()
                    if library.assets.isEmpty {
                        Text("Chưa có ảnh được phép truy cập.").foregroundStyle(.secondary).padding(.top, 50)
                    }
                }.scrollPosition(id: $scrollAnchor)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Cho phép truy cập ảnh để hiển thị thư viện ngay tại đây.")
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                    if library.permission == .denied || library.permission == .restricted {
                        Button("Mở Cài đặt") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    } else {
                        Button("Cho phép truy cập ảnh") { Task { await library.requestAccess() } }
                    }
                    Spacer()
                }.frame(maxWidth: .infinity)
            }
        }
        .background(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("\(editor.photos.count) / 6 ảnh đã chọn").font(.subheadline)
                        .accessibilityIdentifier("selectionCount")
                    Spacer()
                    Button(action: editor.preparePreview) {
                        if editor.busy { ProgressView().tint(.white) }
                        else { Text("Bắt đầu").font(.subheadline.weight(.semibold)) }
                    }.buttonStyle(.borderedProminent).tint(.black)
                        .disabled(!(4...6).contains(editor.photos.count) || editor.busy)
                        .accessibilityIdentifier("startCollage")
                }
                SelectedStrip(editor: editor, library: library)
                Text(editor.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                .background(.white).overlay(alignment: .top) { Divider() }
        }
    }

    private var previewScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Button { editor.showingPreview = false } label: {
                    Label("Chọn ảnh", systemImage: "chevron.left")
                }.disabled(editor.busy).accessibilityIdentifier("backToLibrary")
                Spacer()
                Button("Xong", action: editor.save).buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(editor.busy).accessibilityIdentifier("saveCollage")
            }.padding().foregroundStyle(.white)
            ZStack {
                Color.black
                if let image = editor.preview {
                    Image(uiImage: image).resizable().scaledToFit().padding(12)
                        .accessibilityLabel("Ảnh ghép xem trước")
                        .accessibilityIdentifier("collagePreview")
                }
                if editor.busy { ProgressView().tint(.white).scaleEffect(1.5) }
            }.frame(maxHeight: .infinity)
            VStack(spacing: 8) {
                SelectedStrip(editor: editor, library: library)
                HStack {
                    Button { editor.move(-1) } label: { Image(systemName: "arrow.left") }.accessibilityLabel("Đưa ảnh sang trái")
                    Button { editor.move(1) } label: { Image(systemName: "arrow.right") }.accessibilityLabel("Đưa ảnh sang phải")
                    Spacer()
                    Text("\(editor.photos.count) ảnh • HEIC HD").font(.subheadline).foregroundStyle(.secondary)
                }.disabled(editor.busy)
                Text(editor.status).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }.padding().background(.white)
        }.background(.black)
    }
}

@main struct GhepAnhApp: App {
    var body: some Scene { WindowGroup { EditorView() } }
}
