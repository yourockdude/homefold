import UIKit

/// Подготовка и показ фото профиля.
enum AvatarImage {
    /// Сторона готового квадрата, px. Хватает для аватара 3× до ~100 pt.
    static let side: CGFloat = 320
    /// Дальше фото не уходит на сервер и не хранится: защита от гигантских файлов.
    static let maxBytes = 512 * 1024

    /// Обрезает фото по центру до квадрата, сжимает и отдаёт JPEG. nil — это не изображение.
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let target = CGSize(width: side, height: side)
        let scale = side / min(image.size.width, image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
        for quality in [0.85, 0.7, 0.5] {
            if let jpeg = rendered.jpegData(compressionQuality: quality), jpeg.count <= maxBytes { return jpeg }
        }
        return nil
    }

    // NSCache потокобезопасен.
    private nonisolated(unsafe) static let cache = NSCache<NSNumber, UIImage>()

    /// Декодирует с кэшем: аватар перерисовывается часто, а JPEG разбирать каждый раз незачем.
    static func decoded(_ data: Data?) -> UIImage? {
        guard let data else { return nil }
        let key = NSNumber(value: data.hashValue)
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
