import '../../app_state.dart';
import '../../common/action.dart';

class SetEmailAction extends Action {
  SetEmailAction(this.value);

  final String? value;

  @override
  AppState reduce() => state.copyWith.registration(email: value);
}
