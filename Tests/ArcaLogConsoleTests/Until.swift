/// Waits on the main actor until `condition` holds, or 5 s pass, so a test
/// reads a console once the lines it waits for have arrived. The suites share
/// this one copy.
@MainActor
func until(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
}
