import Foundation

/// Why a console would not run a command.
public enum ConsoleError: Error, Equatable, LocalizedError {
  /// Another command is running, named here. Nothing is queued.
  case busy(String)
  /// The command's output ended with no exit status, so how it went is not
  /// known.
  case noExitStatus(String)

  public var errorDescription: String? {
    switch self {
    case .busy(let label): "The console is still running `\(label)`. One command at a time."
    case .noExitStatus(let label): "`\(label)` ended without an exit status."
    }
  }
}
