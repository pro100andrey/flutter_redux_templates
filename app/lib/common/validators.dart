import 'package:localization/localization.dart';
import 'package:pro_validator/pro_validator.dart';

final emailValidator = MultiValidator(
  validators: [
    RequiredValidator(
      error: S.current.thisFieldIsRequired,
      ignoreEmptyValues: false,
    ),
    EmailValidator(error: S.current.invalidEmail),
  ],
);

final passwordValidator = MultiValidator(
  validators: [
    RequiredValidator(error: S.current.requiredField, ignoreEmptyValues: false),
    MinLengthValidator(min: 8, error: S.current.minimumLengthSymbols(8)),
    HasUppercaseValidator(error: S.current.mustContainAtLeastOneUppercase),
    HasLowercaseValidator(error: S.current.mustContainAtLeastOneLowercase),
  ],
);

final passwordsMatchValidator = MatchValidator(
  error: S.current.passwordsDoNotMatch,
);
