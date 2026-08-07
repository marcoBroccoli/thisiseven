#if os(iOS)
    import UIKit

    enum AvatarJPEG {
        static let maxEdge: CGFloat = 512
        static let maxBytes = 500 * 1024

        /// Downscale + JPEG-encode for `PUT /v1/me/avatar`.
        static func prepare(_ data: Data) -> Data? {
            guard let image = UIImage(data: data) else { return nil }
            let fitted = fit(image, maxEdge: maxEdge)
            var quality: CGFloat = 0.85
            while quality >= 0.55 {
                if let jpeg = fitted.jpegData(compressionQuality: quality),
                   jpeg.count <= maxBytes
                {
                    return jpeg
                }
                quality -= 0.1
            }
            return fitted.jpegData(compressionQuality: 0.55)
        }

        private static func fit(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
            let size = image.size
            let longest = max(size.width, size.height)
            guard longest > maxEdge, longest > 0 else { return image }
            let scale = maxEdge / longest
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
#endif
