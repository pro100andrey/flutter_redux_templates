import '../../app_state.dart';
import '../../common/action.dart';

class SetLanguageAction extends Action {
  SetLanguageAction(this.locale);

  final String locale;

  @override
  AppState reduce() => state.copyWith.language(locale: locale);
}
