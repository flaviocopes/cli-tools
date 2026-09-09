import Foundation

/// A named option a command accepts, with the help text shown for it.
struct Option {
  var name: String
  var help: String
  var takesValue: Bool = false
  var aliases: [String] = []

  var display: String {
    takesValue ? "\(name) <value>" : name
  }
}

/// A command, its usage line, and the options it understands.
struct CommandSpec {
  var name: String
  var summary: String
  var usage: String
  var options: [Option]
  var details: String? = nil
  var aliases: [String] = []
}

/// Options and positional values parsed from the command line.
struct ParsedArguments {
  var positionals: [String] = []
  var flags: Set<String> = []
  var values: [String: String] = [:]

  func has(_ flag: String) -> Bool {
    flags.contains(flag)
  }

  func value(_ name: String) -> String? {
    values[name]
  }

  func int(_ name: String) throws -> Int? {
    guard let raw = values[name] else { return nil }
    guard let number = Int(raw), number >= 0 else {
      throw CLIError.invalidValue(option: name, value: raw)
    }
    return number
  }

  /// Parses `arguments` against `spec`, rejecting options it does not list.
  static func parse(_ arguments: [String], for spec: CommandSpec) throws -> ParsedArguments {
    var parsed = ParsedArguments()
    var index = 0

    while index < arguments.count {
      let argument = arguments[index]
      index += 1

      guard argument.hasPrefix("-"), argument != "-" else {
        parsed.positionals.append(argument)
        continue
      }

      var name = argument
      var inlineValue: String?
      if let equals = argument.firstIndex(of: "="), argument.hasPrefix("--") {
        name = String(argument[..<equals])
        inlineValue = String(argument[argument.index(after: equals)...])
      }

      guard let option = spec.options.first(where: { $0.name == name || $0.aliases.contains(name) }) else {
        throw CLIError.unknownOption(name, command: spec.name)
      }

      if option.takesValue {
        if let inlineValue {
          parsed.values[option.name] = inlineValue
        } else if index < arguments.count {
          parsed.values[option.name] = arguments[index]
          index += 1
        } else {
          throw CLIError.missingValue(option: option.name)
        }
      } else {
        parsed.flags.insert(option.name)
      }
    }

    return parsed
  }
}

enum CLIError: LocalizedError {
  case missingTool(command: String)
  case unknownCommand(String)
  case unknownOption(String, command: String)
  case missingValue(option: String)
  case invalidValue(option: String, value: String)
  case noExamples(String)

  var errorDescription: String? {
    switch self {
    case .missingTool(let command):
      "Add a tool name. Example: clitools \(command) gh"
    case .unknownCommand(let command):
      "Unknown command '\(command)'. Run 'clitools help' to see the commands."
    case .unknownOption(let option, let command):
      "Unknown option '\(option)'. Run 'clitools help \(command)' to see the options."
    case .missingValue(let option):
      "Option '\(option)' needs a value."
    case .invalidValue(let option, let value):
      "'\(value)' is not a valid value for '\(option)'."
    case .noExamples(let name):
      "No examples found for \(name)."
    }
  }
}
