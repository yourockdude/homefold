import Foundation
import CryptoKit

/// UUID версии 5 (SHA-1 от пространства имён и имени). Нужен, чтобы выполнение серии на одну и ту же дату
/// получало один и тот же идентификатор на всех устройствах — повторная генерация не создаёт дублей.
enum DeterministicUUID {
    static func make(namespace: UUID, name: String) -> UUID {
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array(name.utf8))
        var hash = Array(Insecure.SHA1.hash(data: data).prefix(16))
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
    }
}
