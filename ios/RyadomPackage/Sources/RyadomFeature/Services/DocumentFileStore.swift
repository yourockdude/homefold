import Foundation

/// Локальное хранилище файлов документов. Файлы пишутся с классом защиты `complete`
/// (шифруются средствами iOS, пока устройство заблокировано) и исключаются из резервных копий.
public struct DocumentFileStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("DocumentFiles", isDirectory: true)
        }
    }

    public func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    public func exists(_ name: String?) -> Bool {
        guard let name else { return false }
        return FileManager.default.fileExists(atPath: url(for: name).path)
    }

    /// Сохраняет файл и возвращает имя в каталоге.
    @discardableResult
    public func save(_ data: Data, documentId: UUID, kind: DocumentFileKind) throws -> String {
        try prepareDirectory()
        let name = "\(documentId.uuidString).\(kind.fileExtension)"
        try data.write(to: url(for: name), options: [.atomic, .completeFileProtection])
        return name
    }

    public func remove(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// Удаляет файлы, на которые не ссылается ни одна запись.
    public func removeOrphans(keeping names: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where !names.contains(file) { remove(file) }
    }

    private func prepareDirectory() throws {
        var dir = directory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }
}
