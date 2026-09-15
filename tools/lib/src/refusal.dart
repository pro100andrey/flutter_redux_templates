/// The exception a command raises when what was asked cannot be done here.
///
/// The runner renders it as `✗ <message>` and exits 70, so the message is a
/// sentence for whoever typed the command: what frx found, and what to change.
///
/// **Not a `StateError`, which is what this used to be.** An `Error` means the
/// program has a bug and should die with a stack trace; catching one to print
/// it politely hides the very case that must not be hidden. Everything raised
/// here is instead a conversation — no project under this directory, an
/// `AppState` shape frx cannot wire, a file that does not parse — and none of
/// it is a defect in frx.
class FrxRefusal implements Exception {
  const FrxRefusal(this.message);

  /// The sentence shown after `✗`.
  final String message;

  @override
  String toString() => message;
}
