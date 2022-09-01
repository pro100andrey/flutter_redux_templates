import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../app_state.dart';
import 'models/___state_name____state.dart';

/// returns waiting value
bool select___StateName___IsWaiting(AppState state) =>
    state.wait.isWaitingFor(___StateName___Waiting.wait);

/// Returns [IMap<int, Object>] table
IMap<int, Object> select___StateName___Table(AppState state) =>
    state.___stateName___.table;

/// Returns [Object] value by id
Object select___StateName___ById(
  AppState state, {
  required int id,
}) =>
    select___StateName___Table(state)[id]!;
