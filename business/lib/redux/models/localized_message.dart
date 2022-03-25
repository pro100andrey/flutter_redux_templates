class LocalizedMessage {
  const LocalizedMessage({
    this.title,
    this.message,
  });

  final String? title;
  final String? message;

  @override
  String toString() => 'LocalizedMessage(title: $title, message: $message)';
}
