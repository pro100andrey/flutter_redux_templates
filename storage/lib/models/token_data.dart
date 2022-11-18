import 'package:hive/hive.dart';

import 'hive_types.dart';

part 'token_data.g.dart';

@HiveType(typeId: HiveTypes.tokenData)
class TokenData extends HiveObject {
  TokenData({
    required this.token,
  });

  @HiveField(0)
  String token;
}
