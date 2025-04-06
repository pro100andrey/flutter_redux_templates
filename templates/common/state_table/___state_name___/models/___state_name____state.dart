import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part '___state_name____state.freezed.dart';

@freezed
abstract class ___StateName___State with _$___StateName___State {
  const factory ___StateName___State({
    @Default(IMapConst<int, Object>({})) IMap<int, Object> table,
    @Default(IListConst<int>([])) IList<int> view,
  }) = ____StateName___State;
}

enum ___StateName___Waiting { wait }
