import 'package:localization/localization.dart';
import 'package:validator/validator.dart';

final emailValidator = MultiValidator(
  validators: [
    RequiredValidator(error: S.current.thisFieldIsRequired),
    EmailValidator(error: S.current.invalidEmail),
  ],
);

final passwordValidator = MultiValidator(
  validators: [
    RequiredValidator(error: S.current.requiredField),
    MinLengthValidator(min: 8, error: S.current.minimumLengthSymbols(8)),
    HasUppercaseValidator(error: S.current.mustContainAtLeastOneUppercase),
    HasLowercaseValidator(error: S.current.mustContainAtLeastOneLowercase),
  ],
);

final passwordsMatchValidator =
    MatchValidator(error: S.current.passwordsDoNotMatch);
