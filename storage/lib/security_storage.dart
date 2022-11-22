import 'package:hive/hive.dart';

import 'hive_key_value_security_storage.dart';
import 'models/token_data.dart';

class SecurityStorageKeys {
  static const String tokenData = 'token_data';
}

class SecurityStorage extends KeyValueSecurityStorageImpl {
  SecurityStorage()
      : super(
          storageName: 'security_storage',
          //openssl rand -base64 32
          key: 'zwQbWbzvnl4b/PaqdAGwpmCrZY2seGl6AVAp2GKPo3M=',
        );

  static void registerAdapters() {
    Hive.registerAdapter(TokenDataAdapter());
  }

  Future<void> putTokenData(TokenData value) async =>
      put(SecurityStorageKeys.tokenData, value);

  Future<TokenData?> getTokenData() async =>
      get<TokenData?>(SecurityStorageKeys.tokenData);
}
