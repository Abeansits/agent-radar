import Foundation
import RadarCore

// Simple CLI for agent-radar
// Usage:
//   radar set "<name>" [--type X] [--status Y] [--summary "one line"] [--detail "rich text"]
//   radar board [--status waiting_on_user] [--all] [--pretty]
//   radar get "<name>"
//   radar rm "<name>"

@main
struct DoodleCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else {
            printUsage()
            exit(0)
        }

        do {
            switch cmd {
            case "set":
                try handleSet(Array(args.dropFirst()))
            case "board":
                try handleBoard(Array(args.dropFirst()))
            case "get":
                try handleGet(Array(args.dropFirst()))
            case "rm", "remove", "delete":
                try handleRm(Array(args.dropFirst()))
            case "help", "--help", "-h":
                printUsage()
            default:
                fputs("Unknown command: \(cmd)\n", stderr)
                printUsage()
                exit(2)
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func printUsage() {
        let usage = """
        radar — living status board for multi-agent work

        Commands:
          radar set "<name>" [--type TYPE] [--status STATUS] [--summary "text"] [--detail "text"]
              Create or update an item (name is stable key after normalization).

          radar board [--status STATUS] [--all] [--pretty]
              Print board. JSON by default (for agents). --pretty for humans.
              Excludes done items unless --all.

          radar get "<name>"
              Print single item as JSON (or "null" if not found).

          radar rm "<name>"
              Remove an item.

        Env:
          RADAR_BOARD_PATH    Override board file (default ~/.agent-radar/board.json)
          RADAR_SOURCE        Attribution (fallback DOODLE_SOURCE/AGENT_NAME)

        Examples:
          radar set "Auth middleware" --type session --status waiting_on_user --summary "Rate limit work" --detail "Token bucket vs fixed?"
          radar board --pretty
          RADAR_SOURCE=conductor radar set "JWT decision" --status active --summary "Chose sessions"
        """
        print(usage)
    }

    // MARK: - Handlers

    static func handleSet(_ args: [String]) throws {
        var name: String?
        var type: String?
        var status: String?
        var summary: String?
        var detail: String?

        var i = 0
        while i < args.count {
            let arg = args[i]
            if !arg.hasPrefix("--") {
                if name == nil {
                    name = arg
                    i += 1
                    continue
                } else {
                    // Allow name as first positional
                }
            }
            switch arg {
            case "--type":
                i += 1
                type = i < args.count ? args[i] : nil
            case "--status":
                i += 1
                status = i < args.count ? args[i] : nil
            case "--summary":
                i += 1
                summary = i < args.count ? args[i] : nil
            case "--detail":
                i += 1
                detail = i < args.count ? args[i] : nil
            default:
                if name == nil && !arg.hasPrefix("--") {
                    name = arg
                }
            }
            i += 1
        }

        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            fputs("set requires a name argument\n", stderr)
            printUsage()
            exit(2)
        }

        // Validate status to the known set (typos like "waiting" make items invisible to UI/badge).
        let validStatuses = ["active", "waiting_on_user", "blocked", "done"]
        if let s = status, !validStatuses.contains(s) {
            fputs("invalid --status '\(s)'. Valid values: \(validStatuses.joined(separator: ", "))\n", stderr)
            exit(2)
        }

        let item = try BoardStore.set(
            displayName: name,
            type: type,
            status: status,
            summary: summary,
            detail: detail
        )

        // Emit JSON of the written item for scripts/agents
        let data = try JSONEncoder().encode(item)
        if let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    }

    static func handleBoard(_ args: [String]) throws {
        var filterStatus: String?
        var includeAll = false
        var pretty = false

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--status":
                i += 1
                if i < args.count { filterStatus = args[i] }
            case "--all":
                includeAll = true
            case "--pretty":
                pretty = true
            default:
                break
            }
            i += 1
        }

        let items = try BoardStore.loadFiltered(status: filterStatus, includeDone: includeAll)

        if pretty {
            print(BoardStore.prettyPrint(items: items))
            // Footer hint on stderr so agents see it on reads (conductor)
            fputs("\nTIP: use stable names, put the human-readable ask in --detail, prefer updating existing items by name. Read with `radar board` on status questions.\n", stderr)
        } else {
            // Default: JSON array for agents / machines
            let data = try JSONEncoder().encode(items)
            if let s = String(data: data, encoding: .utf8) {
                print(s)
            }
            // Footer hint (subtle, on stderr so it doesn't break JSON consumers but conductors often read stderr or logs)
            fputs("\nTIP: use stable names, put the human-readable ask in --detail, prefer updating existing items by name. Read with `radar board` on status questions.\n", stderr)
        }
    }

    static func handleGet(_ args: [String]) throws {
        guard let rawName = args.first, !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fputs("get requires a name\n", stderr)
            exit(2)
        }
        if let item = try BoardStore.get(name: rawName) {
            let data = try JSONEncoder().encode(item)
            if let s = String(data: data, encoding: .utf8) {
                print(s)
            }
        } else {
            // Not found: emit JSON null token + exit 0 (script friendly).
            print("null")
            exit(0)
        }
    }

    static func handleRm(_ args: [String]) throws {
        guard let rawName = args.first, !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fputs("rm requires a name\n", stderr)
            exit(2)
        }
        let removed = try BoardStore.remove(name: rawName)
        if removed {
            print("removed")
        } else {
            print("not found")
        }
    }
}
