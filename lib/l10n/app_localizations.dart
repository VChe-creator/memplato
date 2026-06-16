import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('uk')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MemPlato'**
  String get appTitle;

  /// No description provided for @mobileServer.
  ///
  /// In en, this message translates to:
  /// **'Mobile Server'**
  String get mobileServer;

  /// No description provided for @checkingSystem.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get checkingSystem;

  /// No description provided for @step1of3.
  ///
  /// In en, this message translates to:
  /// **'STEP 1 OF 3'**
  String get step1of3;

  /// No description provided for @step2of3.
  ///
  /// In en, this message translates to:
  /// **'STEP 2 OF 3'**
  String get step2of3;

  /// No description provided for @step1title.
  ///
  /// In en, this message translates to:
  /// **'Install Termux'**
  String get step1title;

  /// No description provided for @step1desc.
  ///
  /// In en, this message translates to:
  /// **'Termux is required to run the server. Download and install it.'**
  String get step1desc;

  /// No description provided for @btnDownloadTermux.
  ///
  /// In en, this message translates to:
  /// **'Download Termux'**
  String get btnDownloadTermux;

  /// No description provided for @btnCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get btnCheckAgain;

  /// No description provided for @step2title.
  ///
  /// In en, this message translates to:
  /// **'Permission for MemPlato'**
  String get step2title;

  /// No description provided for @step2desc.
  ///
  /// In en, this message translates to:
  /// **'Allow MemPlato to control Termux.'**
  String get step2desc;

  /// No description provided for @btnGivePermission.
  ///
  /// In en, this message translates to:
  /// **'Give permission'**
  String get btnGivePermission;

  /// No description provided for @btnConfigureTermux.
  ///
  /// In en, this message translates to:
  /// **'Configure Termux'**
  String get btnConfigureTermux;

  /// No description provided for @btnRestartTermux.
  ///
  /// In en, this message translates to:
  /// **'Restart Termux'**
  String get btnRestartTermux;

  /// No description provided for @btnLaunchTermux.
  ///
  /// In en, this message translates to:
  /// **'Open Termux'**
  String get btnLaunchTermux;

  /// No description provided for @btnInstallServer.
  ///
  /// In en, this message translates to:
  /// **'Install server'**
  String get btnInstallServer;

  /// No description provided for @btnCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get btnCheckStatus;

  /// No description provided for @btnStopServer.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get btnStopServer;

  /// No description provided for @btnStartServer.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get btnStartServer;

  /// No description provided for @btnCopyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get btnCopyUrl;

  /// No description provided for @statusOnline.
  ///
  /// In en, this message translates to:
  /// **'MemPlato Online'**
  String get statusOnline;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get statusOffline;

  /// No description provided for @installLogLabel.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get installLogLabel;

  /// No description provided for @urlHint.
  ///
  /// In en, this message translates to:
  /// **'http://localhost:7333'**
  String get urlHint;

  /// No description provided for @autoCheckNote.
  ///
  /// In en, this message translates to:
  /// **'Auto-check every 15 sec'**
  String get autoCheckNote;

  /// No description provided for @installing.
  ///
  /// In en, this message translates to:
  /// **'Installing...'**
  String get installing;

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied!'**
  String get urlCopied;

  /// No description provided for @logStarting.
  ///
  /// In en, this message translates to:
  /// **'🚀 Starting installation...'**
  String get logStarting;

  /// No description provided for @logWaitingTermux.
  ///
  /// In en, this message translates to:
  /// **'🔄 Waiting for Termux to start...'**
  String get logWaitingTermux;

  /// No description provided for @logPreparingServer.
  ///
  /// In en, this message translates to:
  /// **'📋 Preparing server...'**
  String get logPreparingServer;

  /// No description provided for @logCopyingLibs.
  ///
  /// In en, this message translates to:
  /// **'📦 Copying libraries from APK...'**
  String get logCopyingLibs;

  /// No description provided for @logCopyingDeps.
  ///
  /// In en, this message translates to:
  /// **'📦 Copying Python dependencies from APK...'**
  String get logCopyingDeps;

  /// No description provided for @logCopyingPython.
  ///
  /// In en, this message translates to:
  /// **'🐍 Copying Python 3.13.13...'**
  String get logCopyingPython;

  /// No description provided for @logCopyingModel.
  ///
  /// In en, this message translates to:
  /// **'📥 Copying model from APK...\n   (87 MB — ~1 min)'**
  String get logCopyingModel;

  /// No description provided for @logCopyingServer.
  ///
  /// In en, this message translates to:
  /// **'📋 Copying server from APK...'**
  String get logCopyingServer;

  /// No description provided for @logPreparingScript.
  ///
  /// In en, this message translates to:
  /// **'⚙️ Preparing script...'**
  String get logPreparingScript;

  /// No description provided for @logStep1pkg.
  ///
  /// In en, this message translates to:
  /// **'📦 Step 1/4: Installing Python...'**
  String get logStep1pkg;

  /// No description provided for @logStep2wheels.
  ///
  /// In en, this message translates to:
  /// **'⚙️ Step 2/4: Installing libraries...\n   (no compilation — fast!)'**
  String get logStep2wheels;

  /// No description provided for @logStep2pip.
  ///
  /// In en, this message translates to:
  /// **'⚙️ Step 2/4: Installing libraries...'**
  String get logStep2pip;

  /// No description provided for @logPipOk.
  ///
  /// In en, this message translates to:
  /// **'✅ Libraries installed!'**
  String get logPipOk;

  /// No description provided for @logMcpOk.
  ///
  /// In en, this message translates to:
  /// **'✅ All libraries installed!\n📋 Step 3/4: Copying server...'**
  String get logMcpOk;

  /// No description provided for @logStep3copy.
  ///
  /// In en, this message translates to:
  /// **'📋 Step 3/4: Copying server...'**
  String get logStep3copy;

  /// No description provided for @logStep3model.
  ///
  /// In en, this message translates to:
  /// **'📥 Step 3/4: Copying model from APK...\n '**
  String get logStep3model;

  /// No description provided for @logStep4start.
  ///
  /// In en, this message translates to:
  /// **'🚀 Step 4/4: Starting server...'**
  String get logStep4start;

  /// No description provided for @logStepTunnel.
  ///
  /// In en, this message translates to:
  /// **'🔑 Setting up tunnel...'**
  String get logStepTunnel;

  /// No description provided for @logTunnelStarted.
  ///
  /// In en, this message translates to:
  /// **'✅ Tunnel started!'**
  String get logTunnelStarted;

  /// No description provided for @logErrorNoPython.
  ///
  /// In en, this message translates to:
  /// **'❌ Error: Python failed to install.\n\nCheck your internet and try again.'**
  String get logErrorNoPython;

  /// No description provided for @logErrorServerFailed.
  ///
  /// In en, this message translates to:
  /// **'❌ Server failed to start.\n\n.'**
  String get logErrorServerFailed;

  /// No description provided for @logDoneWithUrl.
  ///
  /// In en, this message translates to:
  /// **'✅ Done!\n🌐 Your URL:\n{url}'**
  String logDoneWithUrl(String url);

  /// No description provided for @logDoneNoUrl.
  ///
  /// In en, this message translates to:
  /// **'✅ Installation complete!'**
  String get logDoneNoUrl;

  /// No description provided for @termuxSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Termux Setup'**
  String get termuxSetupTitle;

  /// No description provided for @termuxSetupDesc.
  ///
  /// In en, this message translates to:
  /// **'Open Termux and enter the command below. Then press Exit and return here.'**
  String get termuxSetupDesc;

  /// No description provided for @termuxExitNote.
  ///
  /// In en, this message translates to:
  /// **'After entering the command — press Exit Termux.'**
  String get termuxExitNote;

  /// No description provided for @btnCopyCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get btnCopyCommand;

  /// No description provided for @btnOpenTermux.
  ///
  /// In en, this message translates to:
  /// **'Open Termux'**
  String get btnOpenTermux;

  /// No description provided for @commandCopied.
  ///
  /// In en, this message translates to:
  /// **'Command copied!'**
  String get commandCopied;

  /// No description provided for @exitTermuxHint.
  ///
  /// In en, this message translates to:
  /// **'Exit Termux and return here'**
  String get exitTermuxHint;

  /// No description provided for @notifDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications disabled'**
  String get notifDialogTitle;

  /// No description provided for @notifDialogDesc.
  ///
  /// In en, this message translates to:
  /// **'MemPlato won\'t be able to notify you when Termux finishes installing. Enable notifications in Android settings.'**
  String get notifDialogDesc;

  /// No description provided for @btnLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get btnLater;

  /// No description provided for @btnEnableNotif.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get btnEnableNotif;

  /// No description provided for @permDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Termux Permission'**
  String get permDialogTitle;

  /// No description provided for @permDialogDesc.
  ///
  /// In en, this message translates to:
  /// **'MemPlato needs permission:\n1. Open settings\n2. Run commands in Termux environment\n3. Enable it'**
  String get permDialogDesc;

  /// No description provided for @btnCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get btnCancel;

  /// No description provided for @btnOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get btnOpenSettings;

  /// No description provided for @downloadTermuxTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Termux'**
  String get downloadTermuxTitle;

  /// No description provided for @downloadWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why Termux?'**
  String get downloadWhyTitle;

  /// No description provided for @downloadWhyDesc.
  ///
  /// In en, this message translates to:
  /// **'Termux is a terminal for Android. MemPlato uses it to run the server directly on your phone.'**
  String get downloadWhyDesc;

  /// No description provided for @downloadFileName.
  ///
  /// In en, this message translates to:
  /// **'termux-app.v.universal.apk'**
  String get downloadFileName;

  /// No description provided for @downloadSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get downloadSourceLabel;

  /// No description provided for @downloadWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get downloadWarningTitle;

  /// No description provided for @downloadWarningDesc.
  ///
  /// In en, this message translates to:
  /// **'Termux is no longer updated on Google Play. Download only from GitHub — this is the official source from Termux developers.'**
  String get downloadWarningDesc;

  /// No description provided for @downloadSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get downloadSecurityTitle;

  /// No description provided for @downloadSecurityDesc.
  ///
  /// In en, this message translates to:
  /// **'Termux is open source on GitHub. Verified by the community. No hidden features. 1. Download the file 2. Allow installation from unknown sources 3. Install Termux.'**
  String get downloadSecurityDesc;

  /// No description provided for @agreeLabel.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get agreeLabel;

  /// No description provided for @termsLink.
  ///
  /// In en, this message translates to:
  /// **'terms of use'**
  String get termsLink;

  /// No description provided for @btnClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get btnClose;

  /// No description provided for @btnDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get btnDownload;

  /// No description provided for @termsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get termsTitle;

  /// No description provided for @termsText.
  ///
  /// In en, this message translates to:
  /// **'By using MemPlato you agree to the terms of use of the application.'**
  String get termsText;

  /// No description provided for @agreeCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I accept the terms of use'**
  String get agreeCheckbox;

  /// No description provided for @btnAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get btnAccept;

  /// No description provided for @logCopyingFile.
  ///
  /// In en, this message translates to:
  /// **'📦 Copying {name}...'**
  String logCopyingFile(String name);

  /// No description provided for @logErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'❌ Error: {error}'**
  String logErrorGeneric(String error);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'uk': return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
