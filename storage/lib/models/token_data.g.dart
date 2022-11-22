// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'token_data.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TokenDataAdapter extends TypeAdapter<TokenData> {
  @override
  final int typeId = 1;

  @override
  TokenData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TokenData(
      token: fields[0] as String,
    );
  }

  @override
  void write(BinaryWriter writer, TokenData obj) {
    writer
      ..writeByte(1)
      ..writeByte(0)
      ..write(obj.token);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
