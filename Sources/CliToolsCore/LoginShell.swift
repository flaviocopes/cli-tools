import Foundation

/// Apps opened from Finder or the Dock start with `/usr/bin:/bin:/usr/sbin:/sbin` as their PATH,
/// so they miss every folder your shell config adds. This asks your login shell for its PATH.
public enum LoginShell {
  static let marker = "__CLITOOLS_PATH__"

  /// Puts the folders of your login shell's PATH in front of this process's PATH.
  /// Call it at launch, before other threads start: `setenv` isn't thread-safe.
  public static func adoptPath(timeout: TimeInterval = 3) {
    guard let shellPath = path(timeout: timeout) else {
      return
    }

    let current = ProcessInfo.processInfo.environment["PATH", default: ""]
    setenv("PATH", merge(shellPath, current), 1)
  }

  /// The PATH your login shell sets up, or nil when the shell fails or takes longer than `timeout`.
  public static func path(timeout: TimeInterval = 3) -> String? {
    let outputURL = FileManager.default.temporaryDirectory
      .appending(path: "clitools-shell-path-\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)

    guard let output = try? FileHandle(forWritingTo: outputURL) else {
      return nil
    }

    defer {
      try? output.close()
      try? FileManager.default.removeItem(at: outputURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-ilc", "printf \(marker); /usr/bin/printenv PATH"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }

    do {
      try process.run()
    } catch {
      return nil
    }

    if finished.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      return nil
    }

    try? output.synchronize()
    guard let data = try? Data(contentsOf: outputURL) else {
      return nil
    }

    return parse(String(decoding: data, as: UTF8.self))
  }

  /// Interactive shells can print a greeting first, so the PATH is whatever follows the last marker.
  static func parse(_ output: String) -> String? {
    guard let range = output.range(of: marker, options: .backwards) else {
      return nil
    }

    let path = output[range.upperBound...]
      .prefix { !$0.isNewline }
      .trimmingCharacters(in: .whitespaces)
    return path.contains("/") ? path : nil
  }

  static func merge(_ first: String, _ second: String) -> String {
    var seen = Set<String>()
    return (first.split(separator: ":") + second.split(separator: ":"))
      .map(String.init)
      .filter { seen.insert($0).inserted }
      .joined(separator: ":")
  }

  private static var shell: String {
    if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
      let path = String(cString: shell)
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    return "/bin/zsh"
  }
}
