/// What a line of a followed command's output says the command follows, or nil
/// when the line says nothing of it (WP-11): eg the file a `tailing <path>` line
/// names. It is the app's, since each command says so in its own words. The
/// console's window names a followed command by the last name its lines gave,
/// and by its label until one does.
public typealias ConsoleNamer = @Sendable (String) -> String?
