import SwiftUI
import UIKit

struct MedicineBoxPhotosEditorView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Binding var photos: [UIImage?]
    var editable: Bool = true

    @State private var activeIndex = 0
    @State private var showCamera = false
    @State private var previewImage: UIImage?
    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editable {
                Text(L10n.t("photos.edit_hint", locale: localizationManager.locale))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(0..<MedicineBoxFace.count, id: \.self) { index in
                    photoCell(at: index)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                stepTitle: L10n.t(MedicineBoxFace.stepKeys[indexForCamera], locale: localizationManager.locale),
                stepHint: L10n.t("scan.step_hint", locale: localizationManager.locale),
                stepIndex: indexForCamera + 1,
                totalSteps: MedicineBoxFace.count
            ) { image in
                if let image {
                    photos[indexForCamera] = image
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPreview) {
            if let previewImage {
                NavigationStack {
                    ZoomablePhotoView(image: previewImage)
                        .navigationTitle(L10n.t("photos.preview", locale: localizationManager.locale))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L10n.t("action.close", locale: localizationManager.locale)) {
                                    showPreview = false
                                }
                            }
                        }
                }
                .preferredColorScheme(.light)
            }
        }
    }

    @State private var indexForCamera = 0

    private func photoCell(at index: Int) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = photos[index] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.searchBackground)
                            .overlay {
                                Image(systemName: editable ? "plus.viewfinder" : "photo")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.textMuted)
                            }
                    }
                }
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if editable, photos[index] != nil {
                    Button {
                        photos[index] = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(4)
                }
            }

            Text(L10n.t(MedicineBoxFace.stepKeys[index], locale: localizationManager.locale))
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let image = photos[index], !editable {
                previewImage = image
                showPreview = true
            } else if editable {
                indexForCamera = index
                showCamera = true
            } else if let image = photos[index] {
                previewImage = image
                showPreview = true
            }
        }
    }
}

private struct ZoomablePhotoView: View {
    let image: UIImage

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding()
        }
        .background(Color.black)
    }
}
