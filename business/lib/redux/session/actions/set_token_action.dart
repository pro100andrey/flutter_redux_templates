import '../../app_state.dart';
import '../../common/action.dart';

class SetTokenAction extends Action {
  SetTokenAction({required this.value});

  final String value;

  @override
  AppState reduce() => state.copyWith.session(token: value);
}
