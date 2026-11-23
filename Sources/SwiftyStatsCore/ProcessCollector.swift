import Foundation

public final class ProcessCollector: Sendable {
    public init() {}

    /// Fetches top processes by CPU and RAM in a single fast `ps` pass.
    /// Intended to be called ONLY while the popover is open.
    public func sample(limit: Int = 6) -> ProcessSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aco", "pid=,pcpu=,rss=,comm="]
        process.environment = ["LC_ALL": "C"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ProcessSnapshot()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return ProcessSnapshot()
        }
        return Self.parsePSOutput(output, limit: limit)
    }

    // MARK: - Pure Parser (Unit-Testable)

    public static func parsePSOutput(_ output: String, limit: Int = 6) -> ProcessSnapshot {
        var items: [ProcessItem] = []
        items.reserveCapacity(128)

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Format: "<pid> <pcpu> <rss_kb> <comm with possible spaces>"
            var idx = line.startIndex
            func nextToken() -> Substring? {
                while idx < line.endIndex && line[idx].isWhitespace {
                    idx = line.index(after: idx)
                }
                guard idx < line.endIndex else { return nil }
                let start = idx
                while idx < line.endIndex && !line[idx].isWhitespace {
                    idx = line.index(after: idx)
                }
                return line[start..<idx]
            }

            guard let pidToken = nextToken(),
                  let cpuToken = nextToken(),
                  let rssToken = nextToken(),
                  let pid = Int32(pidToken),
                  let cpu = Double(cpuToken),
                  let rssKB = UInt64(rssToken) else {
                continue
            }

            while idx < line.endIndex && line[idx].isWhitespace {
                idx = line.index(after: idx)
            }
            guard idx < line.endIndex else { continue }
            let name = String(line[idx...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            items.append(
                ProcessItem(
                    id: pid,
                    name: name,
                    cpuPercent: cpu,
                    memoryBytes: rssKB * 1024
                )
            )
        }

        let topCPU = Array(
            items
                .sorted { lhs, rhs in
                    if lhs.cpuPercent != rhs.cpuPercent {
                        return lhs.cpuPercent > rhs.cpuPercent
                    }
                    return lhs.memoryBytes > rhs.memoryBytes
                }
                .prefix(limit)
        )

        let topMemory = Array(
            items
                .sorted { lhs, rhs in
                    if lhs.memoryBytes != rhs.memoryBytes {
                        return lhs.memoryBytes > rhs.memoryBytes
                    }
                    return lhs.cpuPercent > rhs.cpuPercent
                }
                .prefix(limit)
        )

        return ProcessSnapshot(topByCPU: topCPU, topByMemory: topMemory)
    }
}
