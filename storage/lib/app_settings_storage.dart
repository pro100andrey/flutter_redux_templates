import 'hive_key_value_storage.dart';

class SettingsStorageKeys {
  static const String onboarding = 'onboarding';
}

class AppSettingsStorage extends HiveKeyValueStorageImpl {
  AppSettingsStorage() : super(storageName: 'settings');

  Future<void> setOnboardingAsDone() async =>
      put(SettingsStorageKeys.onboarding, true);

  Future<bool> onboardingIsDone() async {
    final result = await get<bool?>(
      SettingsStorageKeys.onboarding,
    );

    return result ?? false;
  }
}
