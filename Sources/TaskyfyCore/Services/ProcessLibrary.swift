import Foundation

public struct MatchRule: Codable, Sendable, Equatable {
    public let type: String
    public let value: String

    public init(type: String, value: String) {
        self.type = type
        self.value = value
    }

    public func matches(_ candidate: String) -> Bool {
        switch type {
        case "prefix":
            return candidate.hasPrefix(value)
        case "suffix":
            return candidate.hasSuffix(value)
        case "contains":
            return candidate.localizedCaseInsensitiveContains(value)
        case "regex":
            return candidate.range(of: value, options: .regularExpression) != nil
        default:
            return false
        }
    }
}

public struct ProcessTypical: Codable, Sendable, Equatable {
    public let cpu: String?
    public let memory: String?

    public init(cpu: String? = nil, memory: String? = nil) {
        self.cpu = cpu
        self.memory = memory
    }
}

public struct ProcessEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let names: [String]?
    public let match: MatchRule?
    public let title: String
    public let category: String
    public let vendor: String?
    public let oneLiner: String
    public let summary: String
    public let whyHigh: [String]?
    public let whatToDo: [String]?
    public let safeToQuit: String
    public let safeToQuitNote: String?
    public let typical: ProcessTypical?
    public let related: [String]?
    public let keywords: [String]?

    public init(
        id: String,
        names: [String]? = nil,
        match: MatchRule? = nil,
        title: String,
        category: String,
        vendor: String? = nil,
        oneLiner: String,
        summary: String,
        whyHigh: [String]? = nil,
        whatToDo: [String]? = nil,
        safeToQuit: String = "caution",
        safeToQuitNote: String? = nil,
        typical: ProcessTypical? = nil,
        related: [String]? = nil,
        keywords: [String]? = nil
    ) {
        self.id = id
        self.names = names
        self.match = match
        self.title = title
        self.category = category
        self.vendor = vendor
        self.oneLiner = oneLiner
        self.summary = summary
        self.whyHigh = whyHigh
        self.whatToDo = whatToDo
        self.safeToQuit = safeToQuit
        self.safeToQuitNote = safeToQuitNote
        self.typical = typical
        self.related = related
        self.keywords = keywords
    }
}

private struct ProcessDatabaseFile: Codable {
    let version: Int
    let updated: String?
    let processes: [ProcessEntry]
    let patterns: [ProcessEntry]?
}

public final class ProcessLibrary: @unchecked Sendable {
    public static let shared = ProcessLibrary()

    public let entries: [ProcessEntry]
    public let patterns: [ProcessEntry]
    private let byExactName: [String: ProcessEntry]
    private let byLowerName: [String: ProcessEntry]
    private let byID: [String: ProcessEntry]
    private let cacheLock = NSLock()
    private var lookupCache: [String: ProcessEntry?] = [:]

    public init(bundle: Bundle? = nil) {
        let url = Self.locateDatabaseURL(preferredBundle: bundle)
        if let url,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(ProcessDatabaseFile.self, from: data) {
            self.entries = decoded.processes
            self.patterns = decoded.patterns ?? []
        } else {
            self.entries = []
            self.patterns = []
        }

        var exact: [String: ProcessEntry] = [:]
        var lower: [String: ProcessEntry] = [:]
        var idMap: [String: ProcessEntry] = [:]

        for entry in entries {
            idMap[entry.id] = entry
            exact[entry.title] = entry
            lower[entry.title.lowercased()] = entry
            for n in entry.names ?? [] {
                exact[n] = entry
                lower[n.lowercased()] = entry
            }
        }

        self.byExactName = exact
        self.byLowerName = lower
        self.byID = idMap
    }

    private static func locateDatabaseURL(preferredBundle: Bundle?) -> URL? {
        if let b = preferredBundle, let u = b.url(forResource: "processes", withExtension: "json") {
            return u
        }
        if let u = Bundle.main.url(forResource: "processes", withExtension: "json") {
            return u
        }
        if let u = Bundle(for: ProcessLibrary.self).url(forResource: "processes", withExtension: "json") {
            return u
        }
        #if SWIFT_PACKAGE
        if let u = Bundle.module.url(forResource: "processes", withExtension: "json") {
            return u
        }
        #endif
        return nil
    }

    public func lookup(name: String, bundleID: String? = nil, path: String? = nil) -> ProcessEntry? {
        if let hit = byExactName[name] {
            return hit
        }
        if let hit = byLowerName[name.lowercased()] {
            return hit
        }
        if let bid = bundleID {
            if let hit = byExactName[bid] ?? byLowerName[bid.lowercased()] {
                return hit
            }
        }
        if let path {
            let lastComponent = (path as NSString).lastPathComponent
            if let hit = byExactName[lastComponent] ?? byLowerName[lastComponent.lowercased()] {
                return hit
            }
        }

        let cacheKey = "\(name)|\(bundleID ?? "")"
        cacheLock.lock()
        if let cached = lookupCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var matched: ProcessEntry?
        for pattern in patterns {
            if let rule = pattern.match, rule.matches(name) {
                matched = pattern
                break
            }
        }

        cacheLock.lock()
        if lookupCache.count > 1024 {
            lookupCache.removeAll(keepingCapacity: true)
        }
        lookupCache[cacheKey] = matched
        cacheLock.unlock()
        return matched
    }

    public func entry(forID id: String) -> ProcessEntry? {
        byID[id]
    }

    public func search(_ query: String, limit: Int = 25) -> [ProcessEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return Array(entries.prefix(limit))
        }

        var scored: [(Int, ProcessEntry)] = []
        for entry in entries {
            var score = 0
            let lowerTitle = entry.title.lowercased()
            if lowerTitle == trimmed {
                score += 100
            } else if lowerTitle.hasPrefix(trimmed) {
                score += 60
            } else if lowerTitle.contains(trimmed) {
                score += 35
            }

            if let names = entry.names {
                for n in names {
                    let ln = n.lowercased()
                    if ln == trimmed {
                        score += 90
                    } else if ln.hasPrefix(trimmed) {
                        score += 50
                    } else if ln.contains(trimmed) {
                        score += 25
                    }
                }
            }

            if entry.oneLiner.lowercased().contains(trimmed) {
                score += 15
            }
            if entry.summary.lowercased().contains(trimmed) {
                score += 10
            }
            if let kws = entry.keywords, kws.contains(where: { $0.lowercased().contains(trimmed) }) {
                score += 20
            }

            if score > 0 {
                scored.append((score, entry))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
            return lhs.1.title < rhs.1.title
        }

        return Array(scored.prefix(limit).map(\.1))
    }
}
