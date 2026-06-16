// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'MemPlato';

  @override
  String get mobileServer => 'Mobile Server';

  @override
  String get checkingSystem => 'Перевірка...';

  @override
  String get step1of3 => 'КРОК 1 З 3';

  @override
  String get step2of3 => 'КРОК 2 З 3';

  @override
  String get step1title => 'Встановіть Termux';

  @override
  String get step1desc => 'Для роботи сервера потрібен Termux. Завантажте та встановіть його.';

  @override
  String get btnDownloadTermux => 'Завантажити Termux';

  @override
  String get btnCheckAgain => 'Перевірити знову';

  @override
  String get step2title => 'Дозвіл для MemPlato';

  @override
  String get step2desc => 'Надайте MemPlato дозвіл на керування Termux.';

  @override
  String get btnGivePermission => 'Надати дозвіл';

  @override
  String get btnConfigureTermux => 'Налаштувати Termux';

  @override
  String get btnRestartTermux => 'Перезапустити Termux';

  @override
  String get btnLaunchTermux => 'Відкрити Termux';

  @override
  String get btnInstallServer => 'Встановити сервер';

  @override
  String get btnCheckStatus => 'Перевірити';

  @override
  String get btnStopServer => 'Зупинити';

  @override
  String get btnStartServer => 'Запустити';

  @override
  String get btnCopyUrl => 'Копіювати URL';

  @override
  String get statusOnline => 'MemPlato Online';

  @override
  String get statusOffline => 'Недоступний';

  @override
  String get installLogLabel => 'URL';

  @override
  String get urlHint => 'http://localhost:7333';

  @override
  String get autoCheckNote => 'Автоперевірка кожні 15 сек';

  @override
  String get installing => 'Встановлення...';

  @override
  String get urlCopied => 'URL скопійовано!';

  @override
  String get logStarting => '🚀 Починаємо встановлення...';

  @override
  String get logWaitingTermux => '🔄 Очікуємо запуску Termux...';

  @override
  String get logPreparingServer => '📋 Підготовка сервера...';

  @override
  String get logCopyingLibs => '📦 Копіювання бібліотек з APK...';

  @override
  String get logCopyingDeps => '📦 Копіювання Python залежностей з APK...';

  @override
  String get logCopyingPython => '🐍 Копіювання Python 3.13.13...';

  @override
  String get logCopyingModel => '📥 Копіювання моделі з APK...\n   (87 МБ — займе ~1 хв)';

  @override
  String get logCopyingServer => '📋 Копіювання сервера з APK...';

  @override
  String get logPreparingScript => '⚙️ Підготовка скрипта...';

  @override
  String get logStep1pkg => '📦 Крок 1/4: Встановлення Python...';

  @override
  String get logStep2wheels => '⚙️ Крок 2/4: Встановлення бібліотек...\n   (без компіляції — швидко!)';

  @override
  String get logStep2pip => '⚙️ Крок 2/4: Встановлення бібліотек...';

  @override
  String get logPipOk => '✅ Бібліотеки встановлено!';

  @override
  String get logMcpOk => '✅ Всі бібліотеки встановлено!\n📋 Крок 3/4: Копіювання сервера...';

  @override
  String get logStep3copy => '📋 Крок 3/4: Копіювання сервера...';

  @override
  String get logStep3model => '📥 Крок 3/4: Копіювання моделі з APK...\n ';

  @override
  String get logStep4start => '🚀 Крок 4/4: Запуск сервера...';

  @override
  String get logStepTunnel => '🔑 Налаштування тунелю...';

  @override
  String get logTunnelStarted => '✅ Тунель запущено!';

  @override
  String get logErrorNoPython => '❌ Помилка: Python не встановився.\n\nПеревір інтернет і спробуй ще раз.';

  @override
  String get logErrorServerFailed => '❌ Сервер не запустився.\n\n.';

  @override
  String logDoneWithUrl(String url) {
    return '✅ Готово!\n🌐 Твій URL:\n$url';
  }

  @override
  String get logDoneNoUrl => '✅ Встановлення завершено!';

  @override
  String get termuxSetupTitle => 'Налаштування Termux';

  @override
  String get termuxSetupDesc => 'Відкрийте Termux та введіть команду нижче. Потім натисніть Exit та поверніться.';

  @override
  String get termuxExitNote => 'Після введення команди — натисніть Exit Termux.';

  @override
  String get btnCopyCommand => 'Копіювати';

  @override
  String get btnOpenTermux => 'Відкрити Termux';

  @override
  String get commandCopied => 'Команду скопійовано!';

  @override
  String get exitTermuxHint => 'Exit Termux і поверніться сюди';

  @override
  String get notifDialogTitle => 'Сповіщення вимкнені';

  @override
  String get notifDialogDesc => 'MemPlato не зможе повідомити вас коли Termux завершить встановлення. Увімкніть сповіщення в Android налаштуваннях.';

  @override
  String get btnLater => 'Пізніше';

  @override
  String get btnEnableNotif => 'Увімкнути';

  @override
  String get permDialogTitle => 'Дозвіл Termux';

  @override
  String get permDialogDesc => 'Для роботи MemPlato потрібен дозвіл:\n1. Відкрийте налаштування\n2. Run commands in Termux environment\n3. Увімкніть';

  @override
  String get btnCancel => 'Скасувати';

  @override
  String get btnOpenSettings => 'Відкрити налаштування';

  @override
  String get downloadTermuxTitle => 'Завантажити Termux';

  @override
  String get downloadWhyTitle => 'Навіщо потрібен Termux?';

  @override
  String get downloadWhyDesc => 'Termux — це термінал для Android. MemPlato використовує його для запуску сервера прямо на телефоні.';

  @override
  String get downloadFileName => 'termux-app.v.universal.apk';

  @override
  String get downloadSourceLabel => 'Джерело';

  @override
  String get downloadWarningTitle => 'Увага';

  @override
  String get downloadWarningDesc => 'Termux більше не оновлюється в Google Play. Завантажуйте тільки з GitHub — це офіційне джерело від розробників Termux.';

  @override
  String get downloadSecurityTitle => 'Безпека';

  @override
  String get downloadSecurityDesc => 'Termux — відкритий код на GitHub від Google. Перевіряється спільнотою. Жодних прихованих функцій. 1. Завантажте файл 2. Дозвольте встановлення з невідомих джерел 3. Встановіть Termux.';

  @override
  String get agreeLabel => 'Я погоджуюся з ';

  @override
  String get termsLink => 'умовами використання';

  @override
  String get btnClose => 'Закрити';

  @override
  String get btnDownload => 'Завантажити';

  @override
  String get termsTitle => 'Умови використання';

  @override
  String get termsText => 'Використовуючи MemPlato ви погоджуєтесь з умовами використання додатку.';

  @override
  String get agreeCheckbox => 'Я приймаю умови використання';

  @override
  String get btnAccept => 'Прийняти';

  @override
  String logCopyingFile(String name) {
    return '📦 Копіювання $name...';
  }

  @override
  String logErrorGeneric(String error) {
    return '❌ Помилка: $error';
  }
}
