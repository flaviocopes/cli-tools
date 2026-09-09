import Foundation

public struct TLDRPage: Sendable {
  public var summary: String?
  public var homepage: URL?
  public var examples: [ToolExample]

  /// Parses a tldr page in the standard markdown format.
  public static func parse(_ markdown: String) -> TLDRPage {
    var page = TLDRPage(summary: nil, homepage: nil, examples: [])
    var pendingDescription: String?

    for rawLine in markdown.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)

      if line.hasPrefix("> ") {
        let text = String(line.dropFirst(2))
        if text.hasPrefix("More information:") {
          page.homepage = extractURL(from: text)
        } else if page.summary == nil, !text.hasPrefix("See also:") {
          page.summary = stripInlineCode(text)
        }
      } else if line.hasPrefix("- ") {
        var text = String(line.dropFirst(2))
        if text.hasSuffix(":") {
          text.removeLast()
        }
        pendingDescription = text
      } else if line.hasPrefix("`"), line.hasSuffix("`"), line.count > 2 {
        let command = stripPlaceholders(String(line.dropFirst().dropLast()))
        page.examples.append(
          ToolExample(description: pendingDescription ?? "", command: command)
        )
        pendingDescription = nil
      }
    }

    return page
  }

  private static func extractURL(from text: String) -> URL? {
    guard
      let start = text.firstIndex(of: "<"),
      let end = text.firstIndex(of: ">"),
      start < end
    else {
      return nil
    }
    return URL(string: String(text[text.index(after: start)..<end]))
  }

  private static func stripInlineCode(_ text: String) -> String {
    text.replacingOccurrences(of: "`", with: "")
  }

  private static func stripPlaceholders(_ command: String) -> String {
    command
      .replacingOccurrences(of: "{{", with: "")
      .replacingOccurrences(of: "}}", with: "")
  }
}

extension ToolExample {
  /// Pulls examples out of a tool's `--help` output when it has an examples section.
  public static func parse(help: String, toolName: String) -> [ToolExample] {
    let lines = help.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map(String.init)

    guard let start = lines.firstIndex(where: isExamplesHeader) else {
      return []
    }

    var examples: [ToolExample] = []
    var pendingDescription: String?

    for line in lines.dropFirst(start + 1) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        continue
      }

      if isSectionHeader(line) {
        break
      }

      if let command = command(in: trimmed, toolName: toolName) {
        var description = pendingDescription ?? ""
        var commandText = command

        if let commentRange = commandText.range(of: "  #") ?? commandText.range(of: "\t#") {
          description = commandText[commentRange.upperBound...]
            .trimmingCharacters(in: .whitespaces)
          commandText = String(commandText[..<commentRange.lowerBound])
        }

        examples.append(
          ToolExample(
            description: description,
            command: commandText.trimmingCharacters(in: .whitespaces)
          )
        )
        pendingDescription = nil
      } else if trimmed.hasPrefix("#") {
        pendingDescription = trimmed.drop { $0 == "#" || $0 == " " }.description
      } else {
        pendingDescription = trimmed
      }

      if examples.count >= 12 {
        break
      }
    }

    return examples
  }

  private static func isExamplesHeader(_ line: String) -> Bool {
    var text = line.trimmingCharacters(in: .whitespaces).lowercased()
    if text.hasSuffix(":") {
      text.removeLast()
    }
    return ["examples", "example", "usage examples", "sample usage"].contains(text)
  }

  private static func isSectionHeader(_ line: String) -> Bool {
    guard let first = line.first, !first.isWhitespace else {
      return false
    }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("$") {
      return false
    }
    let isUppercaseHeader = trimmed == trimmed.uppercased() && trimmed.contains(where: \.isLetter)
    return trimmed.hasSuffix(":") || isUppercaseHeader
  }

  private static func command(in line: String, toolName: String) -> String? {
    if line.hasPrefix("$ ") {
      return String(line.dropFirst(2))
    }
    if line == toolName || line.hasPrefix("\(toolName) ") {
      return line
    }
    return nil
  }
}
