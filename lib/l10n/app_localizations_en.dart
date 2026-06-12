// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MemPlato';

  @override
  String get mobileServer => 'Mobile Server';

  @override
  String get checkingSystem => 'Checking...';

  @override
  String get step1of3 => 'STEP 1 OF 3';

  @override
  String get step2of3 => 'STEP 2 OF 3';

  @override
  String get step1title => 'Install Termux';

  @override
  String get step1desc => 'Termux is required to run the server. Download and install it.';

  @override
  String get btnDownloadTermux => 'Download Termux';

  @override
  String get btnCheckAgain => 'Check again';

  @override
  String get step2title => 'Permission for MemPlato';

  @override
  String get step2desc => 'Allow MemPlato to control Termux.';

  @override
  String get btnGivePermission => 'Give permission';

  @override
  String get btnConfigureTermux => 'Configure Termux';

  @override
  String get btnRestartTermux => 'Restart Termux';

  @override
  String get btnLaunchTermux => 'Open Termux';

  @override
  String get btnInstallServer => 'Install server';

  @override
  String get btnCheckStatus => 'Check';

  @override
  String get btnCopyUrl => 'Copy URL';

  @override
  String get statusOnline => 'MemPlato Online';

  @override
  String get statusOffline => 'Unavailable';

  @override
  String get installLogLabel => 'URL';

  @override
  String get urlHint => 'http://localhost:7333';

  @override
  String get autoCheckNote => 'Auto-check every 15 sec';

  @override
  String get installing => 'Installing...';

  @override
  String get urlCopied => 'URL copied!';

  @override
  String get logStarting => '🚀 Starting installation...';

  @override
  String get logWaitingTermux => '🔄 Waiting for Termux to start...';

  @override
  String get logPreparingServer => '📋 Preparing server...';

  @override
  String get logCopyingLibs => '📦 Copying libraries from APK...';

  @override
  String get logCopyingDeps => '📦 Copying Python dependencies from APK...';

  @override
  String get logCopyingPython => '🐍 Copying Python 3.13.13...';

  @override
  String get logCopyingModel => '📥 Copying model from APK...\n   (87 MB — ~1 min)';

  @override
  String get logCopyingServer => '📋 Copying server from APK...';

  @override
  String get logPreparingScript => '⚙️ Preparing script...';

  @override
  String get logStep1pkg => '📦 Step 1/4: Installing Python...';

  @override
  String get logStep2wheels => '⚙️ Step 2/4: Installing libraries...\n   (no compilation — fast!)';

  @override
  String get logStep2pip => '⚙️ Step 2/4: Installing libraries...';

  @override
  String get logPipOk => '✅ Libraries installed!';

  @override
  String get logMcpOk => '✅ All libraries installed!\n📋 Step 3/4: Copying server...';

  @override
  String get logStep3copy => '📋 Step 3/4: Copying server...';

  @override
  String get logStep3model => '📥 Step 3/4: Copying model from APK...\n ';

  @override
  String get logStep4start => '🚀 Step 4/4: Starting server...';

  @override
  String get logStepTunnel => '🔑 Setting up tunnel...';

  @override
  String get logTunnelStarted => '✅ Tunnel started!';

  @override
  String get logErrorNoPython => '❌ Error: Python failed to install.\n\nCheck your internet and try again.';

  @override
  String get logErrorServerFailed => '❌ Server failed to start.\n\n.';

  @override
  String logDoneWithUrl(String url) {
    return '✅ Done!\n🌐 Your URL:\n$url';
  }

  @override
  String get logDoneNoUrl => '✅ Installation complete!';

  @override
  String get termuxSetupTitle => 'Termux Setup';

  @override
  String get termuxSetupDesc => 'Open Termux and enter the command below. Then press Exit and return here.';

  @override
  String get termuxExitNote => 'After entering the command — press Exit Termux.';

  @override
  String get btnCopyCommand => 'Copy';

  @override
  String get btnOpenTermux => 'Open Termux';

  @override
  String get commandCopied => 'Command copied!';

  @override
  String get exitTermuxHint => 'Exit Termux and return here';

  @override
  String get notifDialogTitle => 'Notifications disabled';

  @override
  String get notifDialogDesc => 'MemPlato won\'t be able to notify you when Termux finishes installing. Enable notifications in Android settings.';

  @override
  String get btnLater => 'Later';

  @override
  String get btnEnableNotif => 'Enable';

  @override
  String get permDialogTitle => 'Termux Permission';

  @override
  String get permDialogDesc => 'MemPlato needs permission:\n1. Open settings\n2. Run commands in Termux environment\n3. Enable it';

  @override
  String get btnCancel => 'Cancel';

  @override
  String get btnOpenSettings => 'Open settings';

  @override
  String get downloadTermuxTitle => 'Download Termux';

  @override
  String get downloadWhyTitle => 'Why Termux?';

  @override
  String get downloadWhyDesc => 'Termux is a terminal for Android. MemPlato uses it to run the server directly on your phone.';

  @override
  String get downloadFileName => 'termux-app.v.universal.apk';

  @override
  String get downloadSourceLabel => 'Source';

  @override
  String get downloadWarningTitle => 'Warning';

  @override
  String get downloadWarningDesc => 'Termux is no longer updated on Google Play. Download only from GitHub — this is the official source from Termux developers.';

  @override
  String get downloadSecurityTitle => 'Security';

  @override
  String get downloadSecurityDesc => 'Termux is open source on GitHub. Verified by the community. No hidden features. 1. Download the file 2. Allow installation from unknown sources 3. Install Termux.';

  @override
  String get agreeLabel => 'I agree to the ';

  @override
  String get termsLink => 'terms of use';

  @override
  String get btnClose => 'Close';

  @override
  String get btnDownload => 'Download';

  @override
  String get termsTitle => 'Terms of Use';

  @override
  String get termsText => 'By using MemPlato you agree to the terms of use of the application.';

  @override
  String get agreeCheckbox => 'I accept the terms of use';

  @override
  String get btnAccept => 'Accept';

  @override
  String logCopyingFile(String name) {
    return '📦 Copying $name...';
  }

  @override
  String logErrorGeneric(String error) {
    return '❌ Error: $error';
  }
}
