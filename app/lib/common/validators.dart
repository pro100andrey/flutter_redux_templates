import 'package:localization/localization.dart';
import 'package:pro_validator/pro_validator.dart';

S get s => S.current;

ValidatorGroup get emailValidator =>
    RequiredValidator(error: s.requiredField) &
    EmailValidator(error: s.invalidEmail);

ValidatorGroup get passwordValidator =>
    RequiredValidator(error: s.requiredField) &
    MinLengthValidator(min: 8, error: s.minimumLengthSymbols(8)) &
    HasUppercaseValidator(error: s.mustContainAtLeastOneUppercase) &
    HasLowercaseValidator(error: s.mustContainAtLeastOneLowercase);

MatchValidator get passwordsMatchValidator => MatchValidator(
  error: s.passwordsDoNotMatch,
);
