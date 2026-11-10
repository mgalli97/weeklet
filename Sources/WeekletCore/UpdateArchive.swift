import Foundation

/// Accepts one ordinary app bundle, never symlinks, encrypted entries or ZIP64.
/// The publisher's signature and SHA-256 must be verified before using this parser.
public enum UpdateArchive {
    public static func validate(_ data: Data) throws {
        func word(_ offset: Int, _ width: Int) throws -> UInt32 {
            guard offset >= 0, offset <= data.count - width else { throw UpdateFailure.invalidArchive }
            return (0..<width).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << (8 * $1) }
        }
        guard data.count >= 22, data.count <= UpdateTrust.maximumArchiveSize else { throw UpdateFailure.invalidArchive }
        let lower = max(0, data.count - 65_557)
        var end: Int?
        for offset in stride(from: data.count - 22, through: lower, by: -1) {
            if try word(offset, 4) == 0x06054b50, offset + 22 + Int(try word(offset + 20, 2)) == data.count { end = offset; break }
        }
        guard let end, try word(end + 4, 2) == 0, try word(end + 6, 2) == 0 else { throw UpdateFailure.invalidArchive }
        let count = Int(try word(end + 10, 2))
        let size = Int(try word(end + 12, 4))
        let start = Int(try word(end + 16, 4))
        guard count > 0, count <= 4096, try word(end + 8, 2) == UInt32(count), start + size == end else { throw UpdateFailure.invalidArchive }
        var offset = start
        var expanded: UInt64 = 0
        var names: Set<String> = []
        for _ in 0..<count {
            guard try word(offset, 4) == 0x02014b50, offset + 46 <= end else { throw UpdateFailure.invalidArchive }
            let flags = try word(offset + 8, 2)
            let method = try word(offset + 10, 2)
            let compressed = Int(try word(offset + 20, 4))
            let unpacked = try word(offset + 24, 4)
            let nameLength = Int(try word(offset + 28, 2))
            let extra = Int(try word(offset + 30, 2))
            let comment = Int(try word(offset + 32, 2))
            let attributes = try word(offset + 38, 4)
            let local = Int(try word(offset + 42, 4))
            let next = offset + 46 + nameLength + extra + comment
            guard flags & 1 == 0, method == 0 || method == 8, nameLength > 0, next <= end,
                  try word(offset + 34, 2) == 0, unpacked != UInt32.max, compressed < Int(UInt32.max),
                  [UInt32(0), 0x4000, 0x8000].contains((attributes >> 16) & 0xf000) else { throw UpdateFailure.invalidArchive }
            let bytes = data[(offset + 46)..<(offset + 46 + nameLength)]
            guard bytes.allSatisfy({ (32...126).contains($0) && $0 != 92 && $0 != 58 }),
                  let name = String(bytes: bytes, encoding: .utf8),
                  name == "Weeklet.app/" || name.hasPrefix("Weeklet.app/"),
                  names.insert(name.lowercased()).inserted else { throw UpdateFailure.invalidArchive }
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.dropLast().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  parts.last != ".", parts.last != ".." else { throw UpdateFailure.invalidArchive }
            expanded += UInt64(unpacked)
            guard expanded <= 268_435_456, local < start, try word(local, 4) == 0x04034b50 else { throw UpdateFailure.invalidArchive }
            let localNameLength = Int(try word(local + 26, 2))
            let localExtra = Int(try word(local + 28, 2))
            let payload = local + 30 + localNameLength + localExtra
            guard localNameLength == nameLength, payload <= start, compressed <= start - payload,
                  data[(local + 30)..<(local + 30 + localNameLength)] == bytes else { throw UpdateFailure.invalidArchive }
            offset = next
        }
        guard offset == end, names.contains("weeklet.app/contents/info.plist"),
              names.contains("weeklet.app/contents/macos/weeklet"),
              names.contains("weeklet.app/contents/macos/weekletinstaller") else { throw UpdateFailure.invalidArchive }
    }
}
