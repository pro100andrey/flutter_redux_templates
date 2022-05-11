import 'package:localization/localization.dart';
import 'package:validator/validator.dart';

final emailValidator = MultiValidator([
  RequiredValidator(error: S.current.thisFieldIsRequired),
  EmailValidator(error: S.current.invalidEmail),
]);

final passwordValidator = MultiValidator([
  RequiredValidator(error: S.current.requiredField),
  MinLengthValidator(8, error: S.current.minimumLengthSymbols(8)),
  HasUppercaseValidator(error: S.current.mustContainAtLeastOneUppercase),
  HasLowercaseValidator(error: S.current.mustContainAtLeastOneLowercase),
]);

final passwordsMatchValidator =
    MatchValidator(error: S.current.passwordsDoNotMatch);
