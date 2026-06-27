import SwiftData
import SwiftUI

struct MedicineCoverThumbnail: View {
    @Environment(\.modelContext) private var modelContext

    let medicine: Medicine
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12
    var placeholderColor: Color = AppTheme.primary

    private var coverImage: UIImage? {
        MedicineBoxPhotoStore.loadCoverPhoto(for: medicine, context: modelContext)
    }

    var body: some View {
        Group {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(coverImage == nil ? placeholderColor.opacity(0.1) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.border.opacity(coverImage == nil ? 0 : 0.35), lineWidth: 1)
        }
    }

    private var placeholder: some View {
        Image(systemName: "pills.fill")
            .font(.title2)
            .foregroundStyle(placeholderColor)
    }
}
