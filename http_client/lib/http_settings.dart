typedef Authorization = String? Function();
typedef Unauthorized = void Function();

class HttpSettings {
  const HttpSettings({required this.authBearerToken});

  final Authorization authBearerToken;
}
