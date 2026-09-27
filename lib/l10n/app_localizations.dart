import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart' deferred as app_localizations_en;
import 'app_localizations_es.dart' deferred as app_localizations_es;
import 'app_localizations_id.dart' deferred as app_localizations_id;
import 'app_localizations_pt.dart' deferred as app_localizations_pt;
import 'app_localizations_th.dart' deferred as app_localizations_th;
import 'app_localizations_vi.dart' deferred as app_localizations_vi;
import 'app_localizations_zh.dart' deferred as app_localizations_zh;

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
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('id'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('th'),
    Locale('vi'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @breakpoint.
  ///
  /// In en, this message translates to:
  /// **'Breakpoint'**
  String get breakpoint;

  /// No description provided for @breakpointRule.
  ///
  /// In en, this message translates to:
  /// **'Breakpoint Rule'**
  String get breakpointRule;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @toolbox.
  ///
  /// In en, this message translates to:
  /// **'Toolbox'**
  String get toolbox;

  /// No description provided for @preference.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preference;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Proxy Filter'**
  String get filter;

  /// No description provided for @script.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get script;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port: '**
  String get port;

  /// No description provided for @proxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get proxy;

  /// No description provided for @externalProxy.
  ///
  /// In en, this message translates to:
  /// **'External Proxy'**
  String get externalProxy;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @proxySetting.
  ///
  /// In en, this message translates to:
  /// **'Proxy Setting'**
  String get proxySetting;

  /// No description provided for @setAs.
  ///
  /// In en, this message translates to:
  /// **'Set as '**
  String get setAs;

  /// No description provided for @systemProxy.
  ///
  /// In en, this message translates to:
  /// **'System Proxy'**
  String get systemProxy;

  /// No description provided for @enabledHTTP2.
  ///
  /// In en, this message translates to:
  /// **'Enable HTTP2'**
  String get enabledHTTP2;

  /// No description provided for @serverNotStart.
  ///
  /// In en, this message translates to:
  /// **'Proxy server not started'**
  String get serverNotStart;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @config.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get config;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @httpsProxy.
  ///
  /// In en, this message translates to:
  /// **'HTTPS Proxy'**
  String get httpsProxy;

  /// No description provided for @setting.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get setting;

  /// No description provided for @mobileConnect.
  ///
  /// In en, this message translates to:
  /// **'Mobile Connect'**
  String get mobileConnect;

  /// No description provided for @connectRemote.
  ///
  /// In en, this message translates to:
  /// **'Connect Remote'**
  String get connectRemote;

  /// No description provided for @remoteDevice.
  ///
  /// In en, this message translates to:
  /// **'Remote Device'**
  String get remoteDevice;

  /// No description provided for @remoteDeviceList.
  ///
  /// In en, this message translates to:
  /// **'Remote Device List'**
  String get remoteDeviceList;

  /// No description provided for @myQRCode.
  ///
  /// In en, this message translates to:
  /// **'My QR Code'**
  String get myQRCode;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get followSystem;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @autoStartup.
  ///
  /// In en, this message translates to:
  /// **'Auto Start Recording Traffic'**
  String get autoStartup;

  /// No description provided for @autoStartupDescribe.
  ///
  /// In en, this message translates to:
  /// **'Automatically start recording traffic when the program starts'**
  String get autoStartupDescribe;

  /// No description provided for @minimizeToTrayTitle.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray on close'**
  String get minimizeToTrayTitle;

  /// No description provided for @minimizeToTraySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Closing the window will keep ProxyPin running and hide it to the system tray.'**
  String get minimizeToTraySubtitle;

  /// No description provided for @trayClosePromptContent.
  ///
  /// In en, this message translates to:
  /// **'Closing the window will keep ProxyPin running in the system tray. Do you want to minimize it now?'**
  String get trayClosePromptContent;

  /// No description provided for @trayCloseExitAnyway.
  ///
  /// In en, this message translates to:
  /// **'Exit anyway'**
  String get trayCloseExitAnyway;

  /// No description provided for @trayCloseMinimizeToTray.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray'**
  String get trayCloseMinimizeToTray;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @execute.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get execute;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @confirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm operation'**
  String get confirmTitle;

  /// No description provided for @confirmContent.
  ///
  /// In en, this message translates to:
  /// **'Are you sure about this operation?'**
  String get confirmContent;

  /// No description provided for @addSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successfully added'**
  String get addSuccess;

  /// No description provided for @saveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get saveSuccess;

  /// No description provided for @operationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Operation succeeded'**
  String get operationSuccess;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import successful'**
  String get importSuccess;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Export successful'**
  String get exportSuccess;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// No description provided for @deleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Delete successful'**
  String get deleteSuccess;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @fail.
  ///
  /// In en, this message translates to:
  /// **'fail'**
  String get fail;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'success'**
  String get success;

  /// No description provided for @emptyData.
  ///
  /// In en, this message translates to:
  /// **'Empty Data'**
  String get emptyData;

  /// No description provided for @requestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Request successful'**
  String get requestSuccess;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @modify.
  ///
  /// In en, this message translates to:
  /// **'Modify'**
  String get modify;

  /// No description provided for @responseType.
  ///
  /// In en, this message translates to:
  /// **'Response Type'**
  String get responseType;

  /// No description provided for @request.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get request;

  /// No description provided for @response.
  ///
  /// In en, this message translates to:
  /// **'Response'**
  String get response;

  /// No description provided for @statusCode.
  ///
  /// In en, this message translates to:
  /// **'Status code'**
  String get statusCode;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @example.
  ///
  /// In en, this message translates to:
  /// **'Example: '**
  String get example;

  /// No description provided for @responseHeader.
  ///
  /// In en, this message translates to:
  /// **'Headers'**
  String get responseHeader;

  /// No description provided for @requestHeader.
  ///
  /// In en, this message translates to:
  /// **'Headers'**
  String get requestHeader;

  /// No description provided for @requestLine.
  ///
  /// In en, this message translates to:
  /// **'Request Line'**
  String get requestLine;

  /// No description provided for @requestMethod.
  ///
  /// In en, this message translates to:
  /// **'Request Method'**
  String get requestMethod;

  /// No description provided for @param.
  ///
  /// In en, this message translates to:
  /// **'Param'**
  String get param;

  /// No description provided for @replaceBodyWith.
  ///
  /// In en, this message translates to:
  /// **'Replace Body With:'**
  String get replaceBodyWith;

  /// No description provided for @redirectTo.
  ///
  /// In en, this message translates to:
  /// **'Redirect To:'**
  String get redirectTo;

  /// No description provided for @redirect.
  ///
  /// In en, this message translates to:
  /// **'Redirect'**
  String get redirect;

  /// No description provided for @cannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Cannot be empty'**
  String get cannotBeEmpty;

  /// No description provided for @requestRewriteList.
  ///
  /// In en, this message translates to:
  /// **'Request Rewrite List'**
  String get requestRewriteList;

  /// No description provided for @requestRewriteRule.
  ///
  /// In en, this message translates to:
  /// **'Request Rewrite Rule'**
  String get requestRewriteRule;

  /// No description provided for @requestRewriteEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Request Rewrite'**
  String get requestRewriteEnable;

  /// No description provided for @action.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get action;

  /// No description provided for @multiple.
  ///
  /// In en, this message translates to:
  /// **'Multiple'**
  String get multiple;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get moveDown;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @requestRewriteDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {size} rule(s)?'**
  String requestRewriteDeleteConfirm(Object size);

  /// No description provided for @useGuide.
  ///
  /// In en, this message translates to:
  /// **'Use Guide'**
  String get useGuide;

  /// No description provided for @pleaseEnter.
  ///
  /// In en, this message translates to:
  /// **'Please Enter'**
  String get pleaseEnter;

  /// No description provided for @click.
  ///
  /// In en, this message translates to:
  /// **'Click'**
  String get click;

  /// No description provided for @loadRemoteScript.
  ///
  /// In en, this message translates to:
  /// **'load remote script'**
  String get loadRemoteScript;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @clickEdit.
  ///
  /// In en, this message translates to:
  /// **'Click Edit'**
  String get clickEdit;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select file'**
  String get selectFile;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get match;

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @matchRule.
  ///
  /// In en, this message translates to:
  /// **'Match Rule'**
  String get matchRule;

  /// No description provided for @emptyMatchAll.
  ///
  /// In en, this message translates to:
  /// **'Empty means match all'**
  String get emptyMatchAll;

  /// No description provided for @newBuilt.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newBuilt;

  /// No description provided for @reportServers.
  ///
  /// In en, this message translates to:
  /// **'Report Servers'**
  String get reportServers;

  /// No description provided for @addReportServer.
  ///
  /// In en, this message translates to:
  /// **'Add Report Server'**
  String get addReportServer;

  /// No description provided for @editReportServer.
  ///
  /// In en, this message translates to:
  /// **'Edit Report Server'**
  String get editReportServer;

  /// No description provided for @splitReport.
  ///
  /// In en, this message translates to:
  /// **'Split Report'**
  String get splitReport;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @compression.
  ///
  /// In en, this message translates to:
  /// **'Compression'**
  String get compression;

  /// No description provided for @compressionNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get compressionNone;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @enableSelect.
  ///
  /// In en, this message translates to:
  /// **'Enable Select'**
  String get enableSelect;

  /// No description provided for @disableSelect.
  ///
  /// In en, this message translates to:
  /// **'Disable Select'**
  String get disableSelect;

  /// No description provided for @deleteSelect.
  ///
  /// In en, this message translates to:
  /// **'Delete Select'**
  String get deleteSelect;

  /// No description provided for @testData.
  ///
  /// In en, this message translates to:
  /// **'Test Data'**
  String get testData;

  /// No description provided for @noChangesDetected.
  ///
  /// In en, this message translates to:
  /// **'No changes detected'**
  String get noChangesDetected;

  /// No description provided for @enterMatchData.
  ///
  /// In en, this message translates to:
  /// **'Enter the data to be matched'**
  String get enterMatchData;

  /// No description provided for @modifyRequestHeader.
  ///
  /// In en, this message translates to:
  /// **'Modify Header'**
  String get modifyRequestHeader;

  /// No description provided for @headerName.
  ///
  /// In en, this message translates to:
  /// **'Header Name'**
  String get headerName;

  /// No description provided for @headerValue.
  ///
  /// In en, this message translates to:
  /// **'Header Value'**
  String get headerValue;

  /// No description provided for @deleteHeaderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to delete the request header?'**
  String get deleteHeaderConfirm;

  /// No description provided for @sequence.
  ///
  /// In en, this message translates to:
  /// **'All Requests'**
  String get sequence;

  /// No description provided for @domainList.
  ///
  /// In en, this message translates to:
  /// **'Domain List'**
  String get domainList;

  /// No description provided for @domainWhitelist.
  ///
  /// In en, this message translates to:
  /// **'Proxy Domain Whitelist'**
  String get domainWhitelist;

  /// No description provided for @domainBlacklist.
  ///
  /// In en, this message translates to:
  /// **'Proxy Domain Blacklist'**
  String get domainBlacklist;

  /// No description provided for @domainFilter.
  ///
  /// In en, this message translates to:
  /// **'Proxy Domain List'**
  String get domainFilter;

  /// No description provided for @appWhitelist.
  ///
  /// In en, this message translates to:
  /// **'App Whitelist'**
  String get appWhitelist;

  /// No description provided for @appWhitelistDescribe.
  ///
  /// In en, this message translates to:
  /// **'Only proxy Apps on the whitelist. If the whitelist is enabled, the blacklist will be invalid'**
  String get appWhitelistDescribe;

  /// No description provided for @appBlacklist.
  ///
  /// In en, this message translates to:
  /// **'App Blacklist'**
  String get appBlacklist;

  /// No description provided for @scanCode.
  ///
  /// In en, this message translates to:
  /// **'Scan Code Connect'**
  String get scanCode;

  /// No description provided for @addBlacklist.
  ///
  /// In en, this message translates to:
  /// **'Add Proxy Blacklist'**
  String get addBlacklist;

  /// No description provided for @addWhitelist.
  ///
  /// In en, this message translates to:
  /// **'Add Proxy Whitelist'**
  String get addWhitelist;

  /// No description provided for @deleteWhitelist.
  ///
  /// In en, this message translates to:
  /// **'Delete Proxy Whitelist'**
  String get deleteWhitelist;

  /// No description provided for @domainListSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Last Request Time: {time},  Count: {count}'**
  String domainListSubtitle(Object count, Object time);

  /// No description provided for @selectAction.
  ///
  /// In en, this message translates to:
  /// **'Select action'**
  String get selectAction;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copyHost.
  ///
  /// In en, this message translates to:
  /// **'Copy Host'**
  String get copyHost;

  /// No description provided for @copyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get copyUrl;

  /// No description provided for @copyRawRequest.
  ///
  /// In en, this message translates to:
  /// **'Copy Raw Request'**
  String get copyRawRequest;

  /// No description provided for @copyRequestResponse.
  ///
  /// In en, this message translates to:
  /// **'Copy Request and Response'**
  String get copyRequestResponse;

  /// No description provided for @copyCurl.
  ///
  /// In en, this message translates to:
  /// **'Copy cURL'**
  String get copyCurl;

  /// No description provided for @copyAsPythonRequests.
  ///
  /// In en, this message translates to:
  /// **'Copy as Python Requests'**
  String get copyAsPythonRequests;

  /// No description provided for @copyAsFetch.
  ///
  /// In en, this message translates to:
  /// **'Copy as fetch'**
  String get copyAsFetch;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @repeatAllRequests.
  ///
  /// In en, this message translates to:
  /// **'Repeat All Requests'**
  String get repeatAllRequests;

  /// No description provided for @repeatDomainRequests.
  ///
  /// In en, this message translates to:
  /// **'Repeat Domain Requests'**
  String get repeatDomainRequests;

  /// No description provided for @customRepeat.
  ///
  /// In en, this message translates to:
  /// **'Custom Repeat'**
  String get customRepeat;

  /// No description provided for @repeatCount.
  ///
  /// In en, this message translates to:
  /// **'Iterations'**
  String get repeatCount;

  /// No description provided for @repeatInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval(ms)'**
  String get repeatInterval;

  /// No description provided for @repeatDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay(ms)'**
  String get repeatDelay;

  /// No description provided for @scheduleTime.
  ///
  /// In en, this message translates to:
  /// **'Schedule Time'**
  String get scheduleTime;

  /// No description provided for @fixed.
  ///
  /// In en, this message translates to:
  /// **'fixed'**
  String get fixed;

  /// No description provided for @random.
  ///
  /// In en, this message translates to:
  /// **'random'**
  String get random;

  /// No description provided for @keepCustomSettings.
  ///
  /// In en, this message translates to:
  /// **'Keep custom settings'**
  String get keepCustomSettings;

  /// No description provided for @editRequest.
  ///
  /// In en, this message translates to:
  /// **'Edit and Request'**
  String get editRequest;

  /// No description provided for @reSendRequest.
  ///
  /// In en, this message translates to:
  /// **'The request has been resent'**
  String get reSendRequest;

  /// No description provided for @viewExport.
  ///
  /// In en, this message translates to:
  /// **'View Export'**
  String get viewExport;

  /// No description provided for @exportDomainHar.
  ///
  /// In en, this message translates to:
  /// **'Export This Domain HAR'**
  String get exportDomainHar;

  /// No description provided for @timeDesc.
  ///
  /// In en, this message translates to:
  /// **'Descending by time'**
  String get timeDesc;

  /// No description provided for @timeAsc.
  ///
  /// In en, this message translates to:
  /// **'Ascending by time'**
  String get timeAsc;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear Search'**
  String get clearSearch;

  /// No description provided for @requestType.
  ///
  /// In en, this message translates to:
  /// **'Request type'**
  String get requestType;

  /// No description provided for @keyword.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get keyword;

  /// No description provided for @keywordSearchScope.
  ///
  /// In en, this message translates to:
  /// **'Keyword search scope: '**
  String get keywordSearchScope;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @deleteFavorite.
  ///
  /// In en, this message translates to:
  /// **'Delete Favorite'**
  String get deleteFavorite;

  /// No description provided for @emptyFavorite.
  ///
  /// In en, this message translates to:
  /// **'Empty Favorite'**
  String get emptyFavorite;

  /// No description provided for @deleteFavoriteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Favorite deleted'**
  String get deleteFavoriteSuccess;

  /// No description provided for @historyRecord.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyRecord;

  /// No description provided for @historyCacheTime.
  ///
  /// In en, this message translates to:
  /// **'Cache Time'**
  String get historyCacheTime;

  /// No description provided for @historyManualSave.
  ///
  /// In en, this message translates to:
  /// **'Manual Save'**
  String get historyManualSave;

  /// No description provided for @historyDay.
  ///
  /// In en, this message translates to:
  /// **'{day} days'**
  String historyDay(Object day);

  /// No description provided for @historyForever.
  ///
  /// In en, this message translates to:
  /// **'Forever'**
  String get historyForever;

  /// No description provided for @historyRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} Records {length}'**
  String historyRecordTitle(Object length, Object name);

  /// No description provided for @historyEmptyName.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get historyEmptyName;

  /// No description provided for @historySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Records {requestLength}  file {size}'**
  String historySubtitle(Object requestLength, Object size);

  /// No description provided for @historyUnSave.
  ///
  /// In en, this message translates to:
  /// **'Current record is not saved'**
  String get historyUnSave;

  /// No description provided for @historyDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to delete this history?'**
  String get historyDeleteConfirm;

  /// No description provided for @requestEdit.
  ///
  /// In en, this message translates to:
  /// **'Request Editing'**
  String get requestEdit;

  /// No description provided for @encode.
  ///
  /// In en, this message translates to:
  /// **'Encode'**
  String get encode;

  /// No description provided for @requestBody.
  ///
  /// In en, this message translates to:
  /// **'Request Body'**
  String get requestBody;

  /// No description provided for @responseBody.
  ///
  /// In en, this message translates to:
  /// **'Response Body'**
  String get responseBody;

  /// No description provided for @requestRewrite.
  ///
  /// In en, this message translates to:
  /// **'Request Rewrite'**
  String get requestRewrite;

  /// No description provided for @newWindow.
  ///
  /// In en, this message translates to:
  /// **'New Window'**
  String get newWindow;

  /// No description provided for @httpRequest.
  ///
  /// In en, this message translates to:
  /// **'HTTP Request'**
  String get httpRequest;

  /// No description provided for @enabledHttps.
  ///
  /// In en, this message translates to:
  /// **'Enable HTTPS Proxy'**
  String get enabledHttps;

  /// No description provided for @installRootCa.
  ///
  /// In en, this message translates to:
  /// **'Install Certificate'**
  String get installRootCa;

  /// No description provided for @installCaLocal.
  ///
  /// In en, this message translates to:
  /// **'Install Certificate to Local-Machine'**
  String get installCaLocal;

  /// No description provided for @downloadRootCa.
  ///
  /// In en, this message translates to:
  /// **'Download Certificate'**
  String get downloadRootCa;

  /// No description provided for @downloadRootCaNote.
  ///
  /// In en, this message translates to:
  /// **'Note: If you set the default browser to other than Safari, click this line to copy and paste the link to Safari browser'**
  String get downloadRootCaNote;

  /// No description provided for @generateCA.
  ///
  /// In en, this message translates to:
  /// **'Generate new root certificate'**
  String get generateCA;

  /// No description provided for @generateCADescribe.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to generate a new root certificate? If confirmed,\nYou need to reinstall and trust the new certificate'**
  String get generateCADescribe;

  /// No description provided for @resetDefaultCA.
  ///
  /// In en, this message translates to:
  /// **'Reset Default Root Certificate'**
  String get resetDefaultCA;

  /// No description provided for @resetDefaultCADescribe.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to reset to the default root certificate?\nProxyPin default root certificate is the same for all users.'**
  String get resetDefaultCADescribe;

  /// No description provided for @exportCaP12.
  ///
  /// In en, this message translates to:
  /// **'Export Root Certificate(.p12)'**
  String get exportCaP12;

  /// No description provided for @importCaP12.
  ///
  /// In en, this message translates to:
  /// **'Import Root Certificate(.p12)'**
  String get importCaP12;

  /// No description provided for @trustCa.
  ///
  /// In en, this message translates to:
  /// **'Trust Certificate'**
  String get trustCa;

  /// No description provided for @profileDownload.
  ///
  /// In en, this message translates to:
  /// **'Profile Download'**
  String get profileDownload;

  /// No description provided for @exportCA.
  ///
  /// In en, this message translates to:
  /// **'Export Root Certificate'**
  String get exportCA;

  /// No description provided for @exportPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Export Private Key'**
  String get exportPrivateKey;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @installCaDescribe.
  ///
  /// In en, this message translates to:
  /// **'Install CA Setting > Profile Download > Install'**
  String get installCaDescribe;

  /// No description provided for @trustCaDescribe.
  ///
  /// In en, this message translates to:
  /// **'Trust CA Setting > General > About > Certificate Trust Setting'**
  String get trustCaDescribe;

  /// No description provided for @androidRoot.
  ///
  /// In en, this message translates to:
  /// **'System Certificate (ROOT Device)'**
  String get androidRoot;

  /// No description provided for @androidRootMagisk.
  ///
  /// In en, this message translates to:
  /// **'Magisk module: \nAndroid ROOT devices can be used Magisk ProxyPinCA System Certificate Module, After installing and restarting the phone Check the system certificate to see if there is a ProxyPinCA certificate. If there is, it indicates that the certificate has been successfully installed。'**
  String get androidRootMagisk;

  /// No description provided for @androidRootRename.
  ///
  /// In en, this message translates to:
  /// **'If the module does not take effect, you can install the system root certificate according to the online tutorial, and name the root certificate {name}'**
  String androidRootRename(Object name);

  /// No description provided for @androidRootCADownload.
  ///
  /// In en, this message translates to:
  /// **'Download System Certificate(.0)'**
  String get androidRootCADownload;

  /// No description provided for @androidUserCA.
  ///
  /// In en, this message translates to:
  /// **'User Certificate'**
  String get androidUserCA;

  /// No description provided for @androidUserCATips.
  ///
  /// In en, this message translates to:
  /// **'Tips: Android7+ many apps will not trust user certificates'**
  String get androidUserCATips;

  /// No description provided for @androidUserCAInstall.
  ///
  /// In en, this message translates to:
  /// **'Open settings -> Security -> Encryption and credentials -> Install certificate -> CA certificate'**
  String get androidUserCAInstall;

  /// No description provided for @androidUserXposed.
  ///
  /// In en, this message translates to:
  /// **'It is recommended to use the Xposed module for packet capture (no need for ROOT), click to view wiki'**
  String get androidUserXposed;

  /// No description provided for @configWifiProxy.
  ///
  /// In en, this message translates to:
  /// **'Configure mobile Wi-Fi proxy'**
  String get configWifiProxy;

  /// No description provided for @caInstallGuide.
  ///
  /// In en, this message translates to:
  /// **'Certificate Installation Guide'**
  String get caInstallGuide;

  /// No description provided for @caAndroidBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open Google Browser on Android devices：'**
  String get caAndroidBrowser;

  /// No description provided for @caIosBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open Safari on iOS devices：'**
  String get caIosBrowser;

  /// No description provided for @localIP.
  ///
  /// In en, this message translates to:
  /// **'Local IP '**
  String get localIP;

  /// No description provided for @mobileScan.
  ///
  /// In en, this message translates to:
  /// **'Configure Wi-Fi proxy or Scan with Mobile App'**
  String get mobileScan;

  /// No description provided for @decode.
  ///
  /// In en, this message translates to:
  /// **'Decode'**
  String get decode;

  /// No description provided for @encodeInput.
  ///
  /// In en, this message translates to:
  /// **'Enter the content to be converted'**
  String get encodeInput;

  /// No description provided for @encodeResult.
  ///
  /// In en, this message translates to:
  /// **'Conversion Result'**
  String get encodeResult;

  /// No description provided for @encodeFail.
  ///
  /// In en, this message translates to:
  /// **'Encoding failed'**
  String get encodeFail;

  /// No description provided for @decodeFail.
  ///
  /// In en, this message translates to:
  /// **'Decoding failed'**
  String get decodeFail;

  /// No description provided for @shareUrl.
  ///
  /// In en, this message translates to:
  /// **'Share Request URL'**
  String get shareUrl;

  /// No description provided for @shareCurl.
  ///
  /// In en, this message translates to:
  /// **'Share cURL Request'**
  String get shareCurl;

  /// No description provided for @requestResponse.
  ///
  /// In en, this message translates to:
  /// **'Request and Response'**
  String get requestResponse;

  /// No description provided for @captureDetail.
  ///
  /// In en, this message translates to:
  /// **'Capture Detail'**
  String get captureDetail;

  /// No description provided for @proxyPinSoftware.
  ///
  /// In en, this message translates to:
  /// **'ProxyPin Open source traffic capture software for all platforms'**
  String get proxyPinSoftware;

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @curlSchemeRequest.
  ///
  /// In en, this message translates to:
  /// **'If the curl format is recognized, should it be converted into an HTTP request?'**
  String get curlSchemeRequest;

  /// No description provided for @appExitTips.
  ///
  /// In en, this message translates to:
  /// **'Press again to exit the program'**
  String get appExitTips;

  /// No description provided for @remoteConnectDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Check remote connection failed, disconnected'**
  String get remoteConnectDisconnect;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @remoteConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected {os}, traffic will be forwarded to {os}'**
  String remoteConnected(Object os);

  /// No description provided for @remoteConnectForward.
  ///
  /// In en, this message translates to:
  /// **'Remote connection, forwarding requests to other terminals'**
  String get remoteConnectForward;

  /// No description provided for @connectSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connect successful'**
  String get connectSuccess;

  /// No description provided for @connectedRemote.
  ///
  /// In en, this message translates to:
  /// **'Connected to remote'**
  String get connectedRemote;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @ipLayerProxy.
  ///
  /// In en, this message translates to:
  /// **'IP Layer Proxy'**
  String get ipLayerProxy;

  /// No description provided for @ipLayerProxyDesc.
  ///
  /// In en, this message translates to:
  /// **'IP layer proxy can capture Flutter app requests'**
  String get ipLayerProxyDesc;

  /// No description provided for @inputAddress.
  ///
  /// In en, this message translates to:
  /// **'Input Address'**
  String get inputAddress;

  /// No description provided for @syncConfig.
  ///
  /// In en, this message translates to:
  /// **'Sync configuration'**
  String get syncConfig;

  /// No description provided for @pullConfigFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to pull configuration, please check the network connection'**
  String get pullConfigFail;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @invalidQRCode.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized QR code'**
  String get invalidQRCode;

  /// No description provided for @remoteConnectFail.
  ///
  /// In en, this message translates to:
  /// **'Connection failed，Please check if it is allowed on the same LAN and firewall, iOS needs to enable local network permissions'**
  String get remoteConnectFail;

  /// No description provided for @remoteConnectSuccessTips.
  ///
  /// In en, this message translates to:
  /// **'Your phone needs to enable packet capture in order to capture requests'**
  String get remoteConnectSuccessTips;

  /// No description provided for @windowMode.
  ///
  /// In en, this message translates to:
  /// **'Window Mode'**
  String get windowMode;

  /// No description provided for @windowModeSubTitle.
  ///
  /// In en, this message translates to:
  /// **'Enabled Packet Capture, Enter the background, Display a small window'**
  String get windowModeSubTitle;

  /// No description provided for @pipIcon.
  ///
  /// In en, this message translates to:
  /// **'Window shortcut icon'**
  String get pipIcon;

  /// No description provided for @pipIconDescribe.
  ///
  /// In en, this message translates to:
  /// **'Show quick access to small window Icon'**
  String get pipIconDescribe;

  /// No description provided for @bottomNavigation.
  ///
  /// In en, this message translates to:
  /// **'Bottom Navigation'**
  String get bottomNavigation;

  /// No description provided for @bottomNavigationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bottom navigation bar is displayed, effective after restart'**
  String get bottomNavigationSubtitle;

  /// No description provided for @memoryCleanup.
  ///
  /// In en, this message translates to:
  /// **'Memory Cleanup'**
  String get memoryCleanup;

  /// No description provided for @memoryCleanupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically clean up requests on memory limit reached and keep 32 most recent after cleaning'**
  String get memoryCleanupSubtitle;

  /// No description provided for @maxRequestCount.
  ///
  /// In en, this message translates to:
  /// **'Request Record Limit'**
  String get maxRequestCount;

  /// No description provided for @maxRequestCountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Max number of requests kept in the list; oldest requests are dropped automatically when exceeded'**
  String get maxRequestCountSubtitle;

  /// No description provided for @clearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm before clearing captured records'**
  String get clearConfirm;

  /// No description provided for @clearConfirmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show a confirmation dialog before clearing captured records'**
  String get clearConfirmSubtitle;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @externalProxyAuth.
  ///
  /// In en, this message translates to:
  /// **'Proxy Auth (Optional)'**
  String get externalProxyAuth;

  /// No description provided for @externalProxyServer.
  ///
  /// In en, this message translates to:
  /// **'Proxy Server'**
  String get externalProxyServer;

  /// No description provided for @externalProxyConnectFailure.
  ///
  /// In en, this message translates to:
  /// **'External Proxy Connect failure'**
  String get externalProxyConnectFailure;

  /// No description provided for @externalProxyFailureConfirm.
  ///
  /// In en, this message translates to:
  /// **'Access to all http will fail due to network connectivity issues，Do you want to continue setting up external proxies。'**
  String get externalProxyFailureConfirm;

  /// No description provided for @mobileDisplayPacketCapture.
  ///
  /// In en, this message translates to:
  /// **'Mobile Display Packet Capture:'**
  String get mobileDisplayPacketCapture;

  /// No description provided for @proxyPortRepeat.
  ///
  /// In en, this message translates to:
  /// **'Startup failed, please check the port number {port} is occupied。'**
  String proxyPortRepeat(Object port);

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @proxyIgnoreDomain.
  ///
  /// In en, this message translates to:
  /// **'Proxy ignores domain'**
  String get proxyIgnoreDomain;

  /// No description provided for @domainWhitelistDescribe.
  ///
  /// In en, this message translates to:
  /// **'Only proxy domain names on the whitelist. If the whitelist is enabled, the blacklist will be invalid'**
  String get domainWhitelistDescribe;

  /// No description provided for @domainBlacklistDescribe.
  ///
  /// In en, this message translates to:
  /// **'Domain names on the blacklist will not be proxied'**
  String get domainBlacklistDescribe;

  /// No description provided for @domain.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get domain;

  /// No description provided for @enableScript.
  ///
  /// In en, this message translates to:
  /// **'Enable Script'**
  String get enableScript;

  /// No description provided for @scriptUseDescribe.
  ///
  /// In en, this message translates to:
  /// **'Use JavaScript to modify requests and responses'**
  String get scriptUseDescribe;

  /// No description provided for @scriptEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit script'**
  String get scriptEdit;

  /// No description provided for @scrollEnd.
  ///
  /// In en, this message translates to:
  /// **'Scroll to End'**
  String get scrollEnd;

  /// No description provided for @logger.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get logger;

  /// No description provided for @material3.
  ///
  /// In en, this message translates to:
  /// **'Material 3 is the latest version of Google’s open-source design system'**
  String get material3;

  /// No description provided for @iosVpnBackgroundAudio.
  ///
  /// In en, this message translates to:
  /// **'After turning on packet capture, exit to the background. In order to maintain the main UI thread for network communication, a silent audio playback will be enabled to keep the main thread running. Otherwise, it will only run in the background for 30 seconds. Do you agree to play audio in the background after turning on packet capture?'**
  String get iosVpnBackgroundAudio;

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markRead;

  /// No description provided for @autoRead.
  ///
  /// In en, this message translates to:
  /// **'Auto read'**
  String get autoRead;

  /// No description provided for @highlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlight;

  /// No description provided for @blue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get blue;

  /// No description provided for @green.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get green;

  /// No description provided for @yellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get yellow;

  /// No description provided for @red.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get red;

  /// No description provided for @pink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get pink;

  /// No description provided for @gray.
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get gray;

  /// No description provided for @underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underline;

  /// No description provided for @requestBlock.
  ///
  /// In en, this message translates to:
  /// **'Request Block'**
  String get requestBlock;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @certHashName.
  ///
  /// In en, this message translates to:
  /// **'CA Hash Name'**
  String get certHashName;

  /// No description provided for @regExp.
  ///
  /// In en, this message translates to:
  /// **'RegExp'**
  String get regExp;

  /// No description provided for @systemCertName.
  ///
  /// In en, this message translates to:
  /// **'System Certificate Name'**
  String get systemCertName;

  /// No description provided for @qrCode.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get qrCode;

  /// No description provided for @jsonViewer.
  ///
  /// In en, this message translates to:
  /// **'JSON Viewer'**
  String get jsonViewer;

  /// No description provided for @xmlViewer.
  ///
  /// In en, this message translates to:
  /// **'XML Viewer'**
  String get xmlViewer;

  /// No description provided for @textDiff.
  ///
  /// In en, this message translates to:
  /// **'Text Diff'**
  String get textDiff;

  /// No description provided for @textEditor.
  ///
  /// In en, this message translates to:
  /// **'Text Editor'**
  String get textEditor;

  /// No description provided for @compare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get compare;

  /// No description provided for @diffOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get diffOriginal;

  /// No description provided for @diffChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get diffChanged;

  /// No description provided for @diffIdentical.
  ///
  /// In en, this message translates to:
  /// **'Two texts are identical'**
  String get diffIdentical;

  /// No description provided for @diffSummary.
  ///
  /// In en, this message translates to:
  /// **'+{added} −{removed}'**
  String diffSummary(int added, int removed);

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @compact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get compact;

  /// No description provided for @wordWrap.
  ///
  /// In en, this message translates to:
  /// **'Word Wrap'**
  String get wordWrap;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @generateQrCode.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generateQrCode;

  /// No description provided for @saveImage.
  ///
  /// In en, this message translates to:
  /// **'Save Image'**
  String get saveImage;

  /// No description provided for @selectImage.
  ///
  /// In en, this message translates to:
  /// **'Select Image'**
  String get selectImage;

  /// No description provided for @inputContent.
  ///
  /// In en, this message translates to:
  /// **'Input Content'**
  String get inputContent;

  /// No description provided for @errorCorrectLevel.
  ///
  /// In en, this message translates to:
  /// **'Error Correct'**
  String get errorCorrectLevel;

  /// No description provided for @output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get output;

  /// No description provided for @timestamp.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get timestamp;

  /// No description provided for @convert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get convert;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'DateTime'**
  String get time;

  /// No description provided for @nowTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Now timestamp'**
  String get nowTimestamp;

  /// No description provided for @hosts.
  ///
  /// In en, this message translates to:
  /// **'Hosts'**
  String get hosts;

  /// No description provided for @toAddress.
  ///
  /// In en, this message translates to:
  /// **'To Address'**
  String get toAddress;

  /// No description provided for @encrypt.
  ///
  /// In en, this message translates to:
  /// **'Encrypt'**
  String get encrypt;

  /// No description provided for @decrypt.
  ///
  /// In en, this message translates to:
  /// **'Decrypt'**
  String get decrypt;

  /// No description provided for @cipher.
  ///
  /// In en, this message translates to:
  /// **'Cipher'**
  String get cipher;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @appUpdateCheckVersion.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get appUpdateCheckVersion;

  /// No description provided for @appUpdateNotAvailableMsg.
  ///
  /// In en, this message translates to:
  /// **'Already Using The Latest Version'**
  String get appUpdateNotAvailableMsg;

  /// No description provided for @appUpdateDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get appUpdateDialogTitle;

  /// No description provided for @appUpdateUpdateMsg.
  ///
  /// In en, this message translates to:
  /// **'A new version of ProxyPin is available. Would you like to update now?'**
  String get appUpdateUpdateMsg;

  /// No description provided for @appUpdateCurrentVersionLbl.
  ///
  /// In en, this message translates to:
  /// **'Current Version'**
  String get appUpdateCurrentVersionLbl;

  /// No description provided for @appUpdateNewVersionLbl.
  ///
  /// In en, this message translates to:
  /// **'New Version'**
  String get appUpdateNewVersionLbl;

  /// No description provided for @appUpdateUpdateNowBtnTxt.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get appUpdateUpdateNowBtnTxt;

  /// No description provided for @appUpdateLaterBtnTxt.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get appUpdateLaterBtnTxt;

  /// No description provided for @appUpdateIgnoreBtnTxt.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get appUpdateIgnoreBtnTxt;

  /// No description provided for @appUpdateInstallNow.
  ///
  /// In en, this message translates to:
  /// **'Install Now'**
  String get appUpdateInstallNow;

  /// No description provided for @appUpdateRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get appUpdateRetry;

  /// No description provided for @appUpdateBackgroundDownload.
  ///
  /// In en, this message translates to:
  /// **'Download in background'**
  String get appUpdateBackgroundDownload;

  /// No description provided for @appUpdateOpenDownloadPage.
  ///
  /// In en, this message translates to:
  /// **'Open Download Page'**
  String get appUpdateOpenDownloadPage;

  /// No description provided for @requestMap.
  ///
  /// In en, this message translates to:
  /// **'Request Map'**
  String get requestMap;

  /// No description provided for @requestMapDescribe.
  ///
  /// In en, this message translates to:
  /// **'Do not request remote services, use local configuration or script for response'**
  String get requestMapDescribe;

  /// No description provided for @automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @certNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Certificate not installed'**
  String get certNotInstalled;

  /// No description provided for @openNewWindow.
  ///
  /// In en, this message translates to:
  /// **'Open New Window'**
  String get openNewWindow;

  /// No description provided for @sponsorDonate.
  ///
  /// In en, this message translates to:
  /// **'Sponsor / Donate'**
  String get sponsorDonate;

  /// No description provided for @sponsorSupport.
  ///
  /// In en, this message translates to:
  /// **'Support ongoing development'**
  String get sponsorSupport;

  /// No description provided for @sponsorThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you for supporting this open-source project by choosing any of the following methods to help its long-term development.'**
  String get sponsorThanks;

  /// No description provided for @sponsorAfdian.
  ///
  /// In en, this message translates to:
  /// **'AFDIAN'**
  String get sponsorAfdian;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @privacyContent.
  ///
  /// In en, this message translates to:
  /// **'This open-source packet capture tool runs entirely on your device. It has no backend server and does not collect, store, or upload any personal data. All captured traffic is processed locally and is only forwarded when you explicitly use remote forwarding. Permissions (e.g., network, storage, and camera for QR codes) are used solely to provide features. You can audit the behavior in the public source code.'**
  String get privacyContent;

  /// No description provided for @requestCrypto.
  ///
  /// In en, this message translates to:
  /// **'Request Crypto'**
  String get requestCrypto;

  /// No description provided for @cryptoDecoded.
  ///
  /// In en, this message translates to:
  /// **'Decoded'**
  String get cryptoDecoded;

  /// No description provided for @cryptoDecodeToggle.
  ///
  /// In en, this message translates to:
  /// **'Decrypt'**
  String get cryptoDecodeToggle;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @cryptoRuleField.
  ///
  /// In en, this message translates to:
  /// **'Field Name'**
  String get cryptoRuleField;

  /// No description provided for @cryptoIvPrefixLabel.
  ///
  /// In en, this message translates to:
  /// **'IV Prefix'**
  String get cryptoIvPrefixLabel;

  /// No description provided for @cryptoIvPrefixTooltip.
  ///
  /// In en, this message translates to:
  /// **'Use the first N bytes of the response body as IV'**
  String get cryptoIvPrefixTooltip;

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @remoteUrl.
  ///
  /// In en, this message translates to:
  /// **'Remote URL'**
  String get remoteUrl;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @environment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get environment;

  /// No description provided for @environmentVariables.
  ///
  /// In en, this message translates to:
  /// **'Environment Variables'**
  String get environmentVariables;

  /// No description provided for @envGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get envGlobal;

  /// No description provided for @envManage.
  ///
  /// In en, this message translates to:
  /// **'Manage Environments…'**
  String get envManage;

  /// No description provided for @envNone.
  ///
  /// In en, this message translates to:
  /// **'No Environment'**
  String get envNone;

  /// No description provided for @envDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this environment?'**
  String get envDeleteConfirm;

  /// No description provided for @envEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No variables yet. Click + to add.'**
  String get envEmptyHint;

  /// No description provided for @envUsageHint.
  ///
  /// In en, this message translates to:
  /// **'Reference variables as %s in rules, or read/write via context.env in scripts.'**
  String get envUsageHint;

  /// No description provided for @envInsertBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Insert built-in variable'**
  String get envInsertBuiltIn;

  /// No description provided for @weakNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network Throttling'**
  String get weakNetwork;

  /// No description provided for @weakNetworkPreset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get weakNetworkPreset;

  /// No description provided for @weakNetworkPresetOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get weakNetworkPresetOffline;

  /// No description provided for @weakNetworkPresetSlow.
  ///
  /// In en, this message translates to:
  /// **'Slow'**
  String get weakNetworkPresetSlow;

  /// No description provided for @weakNetworkPresetWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get weakNetworkPresetWeak;

  /// No description provided for @weakNetworkLatency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get weakNetworkLatency;

  /// No description provided for @weakNetworkUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get weakNetworkUpload;

  /// No description provided for @weakNetworkDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get weakNetworkDownload;

  /// No description provided for @weakNetworkBandwidth.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth'**
  String get weakNetworkBandwidth;

  /// No description provided for @weakNetworkLossRate.
  ///
  /// In en, this message translates to:
  /// **'Packet Loss'**
  String get weakNetworkLossRate;

  /// No description provided for @weakNetworkRules.
  ///
  /// In en, this message translates to:
  /// **'URL Rules'**
  String get weakNetworkRules;

  /// No description provided for @mcpService.
  ///
  /// In en, this message translates to:
  /// **'MCP Server'**
  String get mcpService;

  /// No description provided for @mcpServiceDescribe.
  ///
  /// In en, this message translates to:
  /// **'Starts a local HTTP server for Model Context Protocol (MCP) communication with AI tools such as Claude.'**
  String get mcpServiceDescribe;

  /// No description provided for @mcpEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable MCP Server'**
  String get mcpEnable;

  /// No description provided for @mcpPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get mcpPort;

  /// No description provided for @mcpAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced settings'**
  String get mcpAdvanced;

  /// No description provided for @mcpConfig.
  ///
  /// In en, this message translates to:
  /// **'MCP Configuration'**
  String get mcpConfig;

  /// No description provided for @mcpRedact.
  ///
  /// In en, this message translates to:
  /// **'Redact sensitive data before sending to AI'**
  String get mcpRedact;

  /// No description provided for @mcpRedactDescribe.
  ///
  /// In en, this message translates to:
  /// **'Automatically redact sensitive information before it is sent to AI tools.'**
  String get mcpRedactDescribe;

  /// No description provided for @mcpHintRun.
  ///
  /// In en, this message translates to:
  /// **'Run this command in Terminal to add ProxyPin MCP to {client}.'**
  String mcpHintRun(String client);

  /// No description provided for @mcpAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About MCP Integration'**
  String get mcpAboutTitle;

  /// No description provided for @mcpAboutText.
  ///
  /// In en, this message translates to:
  /// **'MCP (Model Context Protocol) lets AI assistants like Claude interact with ProxyPin. AI can read captured HTTP traffic, create debugging rules (Map Local, Map Remote, Breakpoints), and help analyze network issues.'**
  String get mcpAboutText;

  /// No description provided for @mcpLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more about MCP'**
  String get mcpLearnMore;

  /// No description provided for @mcpSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get mcpSkills;

  /// No description provided for @mcpSkillsTitle.
  ///
  /// In en, this message translates to:
  /// **'MCP Skills'**
  String get mcpSkillsTitle;

  /// No description provided for @mcpSkillsReadonly.
  ///
  /// In en, this message translates to:
  /// **'Read-only traffic tools'**
  String get mcpSkillsReadonly;

  /// No description provided for @mcpSkillsRules.
  ///
  /// In en, this message translates to:
  /// **'Rules, replay & environment tools'**
  String get mcpSkillsRules;

  /// No description provided for @mcpEndpoint.
  ///
  /// In en, this message translates to:
  /// **'MCP Endpoint'**
  String get mcpEndpoint;

  /// No description provided for @mcpAccessToken.
  ///
  /// In en, this message translates to:
  /// **'Access Token'**
  String get mcpAccessToken;

  /// No description provided for @mcpLanGuide.
  ///
  /// In en, this message translates to:
  /// **'Keep this phone and your computer on the same Wi-Fi, then run one of the commands below in your computer\'s terminal, or paste the configuration into your AI client\'s MCP settings.'**
  String get mcpLanGuide;

  /// No description provided for @mcpLanTokenNote.
  ///
  /// In en, this message translates to:
  /// **'The token authorizes full access to the MCP tools. Tap the refresh button next to the token to revoke it and issue a new one.'**
  String get mcpLanTokenNote;

  /// No description provided for @mcpOtherClients.
  ///
  /// In en, this message translates to:
  /// **'Other AI clients'**
  String get mcpOtherClients;

  /// No description provided for @mcpOtherClientsHint.
  ///
  /// In en, this message translates to:
  /// **'Universal Streamable HTTP config for Cursor, Cline, Gemini CLI, Cherry Studio, VS Code Copilot and other MCP clients. Paste the URL and Bearer token, or the full JSON, into the client\'s MCP settings.'**
  String get mcpOtherClientsHint;

  /// No description provided for @mcpOneClick.
  ///
  /// In en, this message translates to:
  /// **'One-click setup on your computer'**
  String get mcpOneClick;

  /// No description provided for @mcpOneClickHint.
  ///
  /// In en, this message translates to:
  /// **'Copy the matching command and run it on the computer: Terminal for macOS/Linux, PowerShell for Windows. It auto-detects installed AI clients (Claude Code, Codex, Cursor, Gemini CLI) and configures them over Wi-Fi.'**
  String get mcpOneClickHint;

  /// No description provided for @mcpRegenerateToken.
  ///
  /// In en, this message translates to:
  /// **'Reset token'**
  String get mcpRegenerateToken;

  /// No description provided for @mcpStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get mcpStatusRunning;

  /// No description provided for @mcpStatusStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get mcpStatusStopped;

  /// No description provided for @mcpClientLabel.
  ///
  /// In en, this message translates to:
  /// **'AI client'**
  String get mcpClientLabel;

  /// No description provided for @mcpTransportLabel.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get mcpTransportLabel;

  /// No description provided for @mcpCommandLabel.
  ///
  /// In en, this message translates to:
  /// **'Connect command'**
  String get mcpCommandLabel;

  /// No description provided for @mcpClientsIntl.
  ///
  /// In en, this message translates to:
  /// **'International'**
  String get mcpClientsIntl;

  /// No description provided for @mcpClientsDomestic.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get mcpClientsDomestic;

  /// No description provided for @mcpTransportStdio.
  ///
  /// In en, this message translates to:
  /// **'stdio'**
  String get mcpTransportStdio;

  /// No description provided for @mcpTransportHttp.
  ///
  /// In en, this message translates to:
  /// **'HTTP'**
  String get mcpTransportHttp;

  /// No description provided for @mcpHintTerminal.
  ///
  /// In en, this message translates to:
  /// **'Copy and run in your terminal.'**
  String get mcpHintTerminal;

  /// No description provided for @mcpHintJson.
  ///
  /// In en, this message translates to:
  /// **'Paste into your client\'s MCP settings.'**
  String get mcpHintJson;

  /// No description provided for @mcpHintCopilot.
  ///
  /// In en, this message translates to:
  /// **'Paste into VS Code settings.json → mcp.servers.'**
  String get mcpHintCopilot;

  /// No description provided for @mcpHintLingma.
  ///
  /// In en, this message translates to:
  /// **'Tongyi Lingma IDE → Profile → Settings → MCP Service → Add manually (STDIO type).'**
  String get mcpHintLingma;

  /// No description provided for @mcpHintCherry.
  ///
  /// In en, this message translates to:
  /// **'Cherry Studio → Settings → MCP Servers → Add.'**
  String get mcpHintCherry;

  /// No description provided for @mcpHintDoubao.
  ///
  /// In en, this message translates to:
  /// **'MarsCode IDE → Settings → MCP → Add (STDIO type).'**
  String get mcpHintDoubao;

  /// No description provided for @mcpSetup.
  ///
  /// In en, this message translates to:
  /// **'Auto setup'**
  String get mcpSetup;

  /// No description provided for @mcpStartChat.
  ///
  /// In en, this message translates to:
  /// **'Start chat'**
  String get mcpStartChat;

  /// No description provided for @mcpOpenTerminal.
  ///
  /// In en, this message translates to:
  /// **'Run in terminal'**
  String get mcpOpenTerminal;

  /// No description provided for @mcpSetupDone.
  ///
  /// In en, this message translates to:
  /// **'Configured. Restart your AI client to apply.'**
  String get mcpSetupDone;

  /// No description provided for @mcpSetupFail.
  ///
  /// In en, this message translates to:
  /// **'Setup failed: '**
  String get mcpSetupFail;

  /// No description provided for @mcpCliMissing.
  ///
  /// In en, this message translates to:
  /// **'CLI {cli} not found on PATH. Use \"Run in terminal\" instead.'**
  String mcpCliMissing(Object cli);

  /// No description provided for @mcpUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This client does not support auto setup, configure it manually.'**
  String get mcpUnsupported;

  /// No description provided for @mcpCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get mcpCopy;

  /// No description provided for @mcpCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get mcpCopied;

  /// No description provided for @mcpStartFailed.
  ///
  /// In en, this message translates to:
  /// **'MCP service failed to start'**
  String get mcpStartFailed;

  /// No description provided for @mcpPrivacyHint.
  ///
  /// In en, this message translates to:
  /// **'Only listens on 127.0.0.1 (this machine). Data leaves the app only when an AI client explicitly requests it via a tool.'**
  String get mcpPrivacyHint;

  /// No description provided for @securityAiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis of Audit Results'**
  String get securityAiTitle;

  /// No description provided for @securityAiNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI service not configured. Go to Settings → MCP Connection → AI Analysis, and fill in the endpoint and API key.'**
  String get securityAiNotConfigured;

  /// No description provided for @securityAiRawFallback.
  ///
  /// In en, this message translates to:
  /// **'Raw AI reply (couldn\\'t be parsed into structured advice; shown as-is)'**
  String get securityAiRawFallback;

  /// No description provided for @securityAiCopied.
  ///
  /// In en, this message translates to:
  /// **'AI analysis copied'**
  String get securityAiCopied;

  /// No description provided for @securityAiAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Start Analysis'**
  String get securityAiAnalyze;

  /// No description provided for @securityAiReanalyze.
  ///
  /// In en, this message translates to:
  /// **'Re-analyze'**
  String get securityAiReanalyze;

  /// No description provided for @securityAiTopRisks.
  ///
  /// In en, this message translates to:
  /// **'Top priorities'**
  String get securityAiTopRisks;

  /// No description provided for @securityAiFixes.
  ///
  /// In en, this message translates to:
  /// **'Fix suggestions'**
  String get securityAiFixes;

  /// No description provided for @securityAiActionsHeader.
  ///
  /// In en, this message translates to:
  /// **'Suggested ProxyPin setting changes (each needs confirmation)'**
  String get securityAiActionsHeader;

  /// No description provided for @securityAiApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get securityAiApply;

  /// No description provided for @securityAiApplyTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply Setting'**
  String get securityAiApplyTitle;

  /// No description provided for @securityAiApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get securityAiApplied;

  /// No description provided for @securityAiApplyUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This setting can\\'t be changed automatically'**
  String get securityAiApplyUnsupported;

  /// No description provided for @securityAiStateOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get securityAiStateOn;

  /// No description provided for @securityAiStateOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get securityAiStateOff;

  /// No description provided for @securityAiActionEnableSsl.
  ///
  /// In en, this message translates to:
  /// **'Enable SSL capture'**
  String get securityAiActionEnableSsl;

  /// No description provided for @securityAiActionEnableSystemProxy.
  ///
  /// In en, this message translates to:
  /// **'Enable system proxy'**
  String get securityAiActionEnableSystemProxy;

  /// No description provided for @securityAiActionAntiCache.
  ///
  /// In en, this message translates to:
  /// **'Enable anti-cache'**
  String get securityAiActionAntiCache;

  /// No description provided for @securityAiActionMcpAllowLan.
  ///
  /// In en, this message translates to:
  /// **'Allow LAN access to MCP'**
  String get securityAiActionMcpAllowLan;

  /// No description provided for @securityAiActionMcpAuth.
  ///
  /// In en, this message translates to:
  /// **'Require MCP authentication'**
  String get securityAiActionMcpAuth;

  /// No description provided for @securityAiApplyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Set "$key" to $value?

AI\\'s reason: $reason'**
  String securityAiApplyConfirm(String key, String value, String reason);


  /// No description provided for @wafTitle.
  ///
  /// In en, this message translates to:
  /// **'WAF Payload Mutation'**
  String get wafTitle;

  /// No description provided for @wafLoadFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter a payload first'**
  String get wafLoadFirst;

  /// No description provided for @wafPasteResponse.
  ///
  /// In en, this message translates to:
  /// **'Paste the response headers or block page snippet'**
  String get wafPasteResponse;

  /// No description provided for @wafAppliedCombo.
  ///
  /// In en, this message translates to:
  /// **'Applied the combo for $waf'**
  String wafAppliedCombo(String waf);

  /// No description provided for @wafNeedAuth.
  ///
  /// In en, this message translates to:
  /// **'Check "I have authorization to test this target" first'**
  String get wafNeedAuth;

  /// No description provided for @wafNeedUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a target URL'**
  String get wafNeedUrl;

  /// No description provided for @wafNeedPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Put a {{PAYLOAD}} marker somewhere to inject'**
  String wafNeedPlaceholder(String mark);

  /// No description provided for @wafNoVariant.
  ///
  /// In en, this message translates to:
  /// **'Nothing under the current selection changes the request. Try another payload or technique.'**
  String get wafNoVariant;

  /// No description provided for @wafDoneAll.
  ///
  /// In en, this message translates to:
  /// **'All sent: $total total, $bypass suspected bypass'**
  String wafDoneAll(int total, int bypass);

  /// No description provided for @wafDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'① and ② only transform strings locally and send nothing; ③ "active probing" really sends requests, so you must check the authorization box first.
Use only on targets you own or are authorized to test — attempting to bypass someone else\\'s protections without authorization may be illegal. Probing is serial, batched (default 200 per batch), with no brute force and no concurrency.'**
  String get wafDisclaimer;

  /// No description provided for @wafStep1Title.
  ///
  /// In en, this message translates to:
  /// **'① Identify the WAF (optional)'**
  String get wafStep1Title;

  /// No description provided for @wafStep1Hint.
  ///
  /// In en, this message translates to:
  /// **'Paste response headers or a block page you already captured; it matches by signature — no active probing.'**
  String get wafStep1Hint;

  /// No description provided for @wafPickNameHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a WAF name to apply the recommended combo'**
  String get wafPickNameHint;

  /// No description provided for @wafStep2Title.
  ///
  /// In en, this message translates to:
  /// **'② Enter a payload and choose mutations'**
  String get wafStep2Title;

  /// No description provided for @wafStep3Title.
  ///
  /// In en, this message translates to:
  /// **'③ Active probing (really sends requests)'**
  String get wafStep3Title;

  /// No description provided for @wafStep3Hint.
  ///
  /// In en, this message translates to:
  /// **'Put {{PAYLOAD}} where you want to inject (URL / header / body). A baseline with the original payload goes first, then each checked technique, comparing responses to see which one wasn\\'t blocked.'**
  String wafStep3Hint(String mark);

  /// No description provided for @wafWillProbe.
  ///
  /// In en, this message translates to:
  /// **'This run will probe (decided by ①②): $names'**
  String wafWillProbe(String names);

  /// No description provided for @wafBatchHint.
  ///
  /// In en, this message translates to:
  /// **'Up to $max per batch; after each batch it stops and you decide whether to continue — nothing is fired off all at once.'**
  String wafBatchHint(int max);

  /// No description provided for @wafExtraHeaders.
  ///
  /// In en, this message translates to:
  /// **'Extra request headers (optional, one per line)'**
  String get wafExtraHeaders;

  /// No description provided for @wafAuthCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I have authorization to test this target'**
  String get wafAuthCheckbox;

  /// No description provided for @wafNextBatch.
  ///
  /// In en, this message translates to:
  /// **'Continue next batch ($remaining left)'**
  String wafNextBatch(int remaining);

  /// No description provided for @wafLimitsHard.
  ///
  /// In en, this message translates to:
  /// **'Delay floor $min ms, hard cap $max records — these two can\\'t be crossed. Beyond that it stops being "probing" and becomes a traffic flood against the target.'**
  String wafLimitsHard(int min, int max);

  /// No description provided for @wafPayloadCopied.
  ///
  /// In en, this message translates to:
  /// **'Payload copied'**
  String get wafPayloadCopied;

  /// No description provided for @wafCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied: $name'**
  String wafCopied(String name);


  /// No description provided for @guideTitle.
  ///
  /// In en, this message translates to:
  /// **'User Guide'**
  String get guideTitle;

  /// No description provided for @guideMarkLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'Markup Legend'**
  String get guideMarkLegendTitle;

  /// No description provided for @guideMarkLegend.
  ///
  /// In en, this message translates to:
  /// **'Highlights in docs are shown with several markup styles:

• ==yellow highlight==: key steps
• bold (theme color): important concepts and entry points
• __underline__: settings that need extra attention
• ~orange wavy~: common mistakes
• ~~strikethrough~~: deprecated or discouraged
• monospace background: commands, paths, code

Code blocks have "Demo" and "Copy" buttons at the bottom right.'**
  String get guideMarkLegend;

  /// No description provided for @guideMarkSyntax.
  ///
  /// In en, this message translates to:
  /// **'Markup syntax: **bold** ==highlight== __underline__ ~~strikethrough~~ ~wavy~ code; a code block can take <!--demo:text--> for a demo note.'**
  String get guideMarkSyntax;

  /// No description provided for @guideMarkCopied.
  ///
  /// In en, this message translates to:
  /// **'Markup syntax copied'**
  String get guideMarkCopied;

  /// No description provided for @guideCopySyntax.
  ///
  /// In en, this message translates to:
  /// **'Copy syntax'**
  String get guideCopySyntax;

  /// No description provided for @guideMarkReset.
  ///
  /// In en, this message translates to:
  /// **'Default markup restored'**
  String get guideMarkReset;

  /// No description provided for @guideRenderError.
  ///
  /// In en, this message translates to:
  /// **'Render error (fell back to plain text): $error'**
  String guideRenderError(String error);

  /// No description provided for @guideDemoTitle.
  ///
  /// In en, this message translates to:
  /// **'Demo · $heading'**
  String guideDemoTitle(String heading);

  /// No description provided for @guideDemoDefault.
  ///
  /// In en, this message translates to:
  /// **'This code/config demonstrates usage in the "$heading" section. Drop it into the matching feature page to reproduce.'**
  String guideDemoDefault(String heading);

  /// No description provided for @guideGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get guideGotIt;

  /// No description provided for @guideDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get guideDemo;

  /// No description provided for @guideCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get guideCodeCopied;

  /// No description provided for @guideLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more ($visible / $total shown)'**
  String guideLoadMore(int visible, int total);


  /// No description provided for @wafBatchDone.
  ///
  /// In en, this message translates to:
  /// **'Batch done, $remaining left to send'**
  String wafBatchDone(int remaining);

  /// No description provided for @wafProbeError.
  ///
  /// In en, this message translates to:
  /// **'Probe error: $error'**
  String wafProbeError(String error);

  /// No description provided for @wafCompare.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get wafCompare;

  /// No description provided for @wafNotIdentified.
  ///
  /// In en, this message translates to:
  /// **'Not identified'**
  String get wafNotIdentified;

  /// No description provided for @wafGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get wafGenerate;

  /// No description provided for @wafClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get wafClearSelection;

  /// No description provided for @wafTargetUrl.
  ///
  /// In en, this message translates to:
  /// **'Target URL (with {{PAYLOAD}})'**
  String get wafTargetUrl;

  /// No description provided for @wafBodyOptional.
  ///
  /// In en, this message translates to:
  /// **'Request body (optional)'**
  String get wafBodyOptional;

  /// No description provided for @wafStartProbe.
  ///
  /// In en, this message translates to:
  /// **'Start probing'**
  String get wafStartProbe;

  /// No description provided for @wafClearResults.
  ///
  /// In en, this message translates to:
  /// **'Clear results'**
  String get wafClearResults;

  /// No description provided for @wafAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get wafAdvanced;

  /// No description provided for @wafAdvancedSummary.
  ///
  /// In en, this message translates to:
  /// **'Delay $delayms · Timeout $timeouts · Max $max per batch'**
  String wafAdvancedSummary(int delay, int timeout, int max);

  /// No description provided for @wafInterval.
  ///
  /// In en, this message translates to:
  /// **'Request delay'**
  String get wafInterval;

  /// No description provided for @wafTimeout.
  ///
  /// In en, this message translates to:
  /// **'Per-request timeout'**
  String get wafTimeout;

  /// No description provided for @wafMaxProbes.
  ///
  /// In en, this message translates to:
  /// **'Max per batch'**
  String get wafMaxProbes;

  /// No description provided for @wafNRecords.
  ///
  /// In en, this message translates to:
  /// **'$count'**
  String wafNRecords(int count);

  /// No description provided for @wafAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get wafAll;

  /// No description provided for @wafResultMeta.
  ///
  /// In en, this message translates to:
  /// **'HTTP $status · $bytes bytes · $msms'**
  String wafResultMeta(String status, int bytes, int ms);

  /// No description provided for @wafCopyPayload.
  ///
  /// In en, this message translates to:
  /// **'Copy payload'**
  String get wafCopyPayload;


  /// No description provided for @aiNewChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get aiNewChat;

  /// No description provided for @aiClearChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear current chat'**
  String get aiClearChatTitle;

  /// No description provided for @aiClearChatConfirm.
  ///
  /// In en, this message translates to:
  /// **'This clears all messages in the current chat and cannot be undone.'**
  String get aiClearChatConfirm;

  /// No description provided for @aiConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get aiConversations;

  /// No description provided for @aiClearCurrent.
  ///
  /// In en, this message translates to:
  /// **'Clear current'**
  String get aiClearCurrent;

  /// No description provided for @aiNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get aiNewConversation;

  /// No description provided for @aiNMessages.
  ///
  /// In en, this message translates to:
  /// **'$count messages'**
  String aiNMessages(int count);

  /// No description provided for @aiCloseAndClear.
  ///
  /// In en, this message translates to:
  /// **'Close and clear this chat'**
  String get aiCloseAndClear;

  /// No description provided for @aiDeleteChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get aiDeleteChatTitle;

  /// No description provided for @aiDeleteChatConfirm.
  ///
  /// In en, this message translates to:
  /// **'Messages in this chat can\\'t be recovered after deletion.'**
  String get aiDeleteChatConfirm;

  /// No description provided for @aiPickAttachment.
  ///
  /// In en, this message translates to:
  /// **'Choose what to attach'**
  String get aiPickAttachment;

  /// No description provided for @aiAttachRequests.
  ///
  /// In en, this message translates to:
  /// **'Captured requests'**
  String get aiAttachRequests;

  /// No description provided for @aiAttachRequestsSub.
  ///
  /// In en, this message translates to:
  /// **'Multi-select from the latest 30'**
  String get aiAttachRequestsSub;

  /// No description provided for @aiAttachEndpoints.
  ///
  /// In en, this message translates to:
  /// **'API endpoint list'**
  String get aiAttachEndpoints;

  /// No description provided for @aiAttachEndpointsSub.
  ///
  /// In en, this message translates to:
  /// **'Auto-extract all endpoints with stats'**
  String get aiAttachEndpointsSub;

  /// No description provided for @aiAttachText.
  ///
  /// In en, this message translates to:
  /// **'Custom text'**
  String get aiAttachText;

  /// No description provided for @aiAttachTextSub.
  ///
  /// In en, this message translates to:
  /// **'Paste anything as context'**
  String get aiAttachTextSub;

  /// No description provided for @aiNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No captured requests'**
  String get aiNoRequests;

  /// No description provided for @aiPickRequests.
  ///
  /// In en, this message translates to:
  /// **'Choose captured requests (multi-select)'**
  String get aiPickRequests;

  /// No description provided for @aiStatus.
  ///
  /// In en, this message translates to:
  /// **'Status $code'**
  String aiStatus(int code);

  /// No description provided for @aiNoResponse.
  ///
  /// In en, this message translates to:
  /// **'No response'**
  String get aiNoResponse;

  /// No description provided for @aiAttachTextHint.
  ///
  /// In en, this message translates to:
  /// **'Paste anything as context for the AI'**
  String get aiAttachTextHint;

  /// No description provided for @aiAnalyzeFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed: $error'**
  String aiAnalyzeFailed(String error);

  /// No description provided for @aiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis'**
  String get aiTitle;

  /// No description provided for @aiAgentOn.
  ///
  /// In en, this message translates to:
  /// **'Agent mode on: AI can call ProxyPin features automatically'**
  String get aiAgentOn;

  /// No description provided for @aiAgentOff.
  ///
  /// In en, this message translates to:
  /// **'Agent mode off: only manual messages'**
  String get aiAgentOff;

  /// No description provided for @aiAttachTooltip.
  ///
  /// In en, this message translates to:
  /// **'Attach info (multi-select)'**
  String get aiAttachTooltip;

  /// No description provided for @aiConvTooltip.
  ///
  /// In en, this message translates to:
  /// **'Conversations (new / switch / delete / clear)'**
  String get aiConvTooltip;

  /// No description provided for @aiConfigTooltip.
  ///
  /// In en, this message translates to:
  /// **'AI settings'**
  String get aiConfigTooltip;

  /// No description provided for @aiThinking.
  ///
  /// In en, this message translates to:
  /// **'AI is thinking…'**
  String get aiThinking;

  /// No description provided for @aiInputAgent.
  ///
  /// In en, this message translates to:
  /// **'Ask (Agent mode: AI can fetch data)'**
  String get aiInputAgent;

  /// No description provided for @aiInputPlain.
  ///
  /// In en, this message translates to:
  /// **'Type a question'**
  String get aiInputPlain;

  /// No description provided for @aiEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat with AI to analyze captured traffic'**
  String get aiEmptyTitle;

  /// No description provided for @aiEmptyHint1.
  ///
  /// In en, this message translates to:
  /// **'Tap 📎 at top right to attach requests / endpoint list / text'**
  String get aiEmptyHint1;

  /// No description provided for @aiEmptyHint2.
  ///
  /// In en, this message translates to:
  /// **'Turn on 🤖 Agent mode to let AI call ProxyPin features'**
  String get aiEmptyHint2;

  /// No description provided for @aiToolCalled.
  ///
  /// In en, this message translates to:
  /// **'Called tool $name'**
  String aiToolCalled(String name);

  /// No description provided for @aiCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get aiCopied;

  /// No description provided for @aiConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis Settings'**
  String get aiConfigTitle;

  /// No description provided for @aiEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable AI Analysis'**
  String get aiEnable;

  /// No description provided for @aiEnableSub.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible API; data is sent to the service you configure'**
  String get aiEnableSub;

  /// No description provided for @aiProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get aiProvider;

  /// No description provided for @aiCustomService.
  ///
  /// In en, this message translates to:
  /// **'Custom service…'**
  String get aiCustomService;

  /// No description provided for @aiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get aiBaseUrl;

  /// No description provided for @aiBaseUrlHelper.
  ///
  /// In en, this message translates to:
  /// **'Custom provider — enter an OpenAI-compatible URL'**
  String get aiBaseUrlHelper;

  /// No description provided for @aiModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiModelLabel;

  /// No description provided for @aiAgentSection.
  ///
  /// In en, this message translates to:
  /// **'Agent mode'**
  String get aiAgentSection;

  /// No description provided for @aiAgentHint2.
  ///
  /// In en, this message translates to:
  /// **'Once on, AI can call ProxyPin tools to fetch data'**
  String get aiAgentHint2;

  /// No description provided for @aiMaxRounds.
  ///
  /// In en, this message translates to:
  /// **'Max tool rounds: $count'**
  String aiMaxRounds(int count);

  /// No description provided for @aiAgentExtra.
  ///
  /// In en, this message translates to:
  /// **'Agent extra instructions'**
  String get aiAgentExtra;

  /// No description provided for @aiAgentExtraHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. check security risks first; POST only…'**
  String get aiAgentExtraHint;

  /// No description provided for @aiImportOk.
  ///
  /// In en, this message translates to:
  /// **'Config imported'**
  String get aiImportOk;

  /// No description provided for @aiImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: $error'**
  String aiImportFailed(String error);

  /// No description provided for @aiImportFromFile.
  ///
  /// In en, this message translates to:
  /// **'Import config from file (JSON)'**
  String get aiImportFromFile;

  /// No description provided for @aiJsonFormatHint.
  ///
  /// In en, this message translates to:
  /// **'JSON format: $example'**
  String aiJsonFormatHint(String example);

  /// No description provided for @aiConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'AI settings saved'**
  String get aiConfigSaved;


  /// No description provided for @quicTitle.
  ///
  /// In en, this message translates to:
  /// **'QUIC Connections'**
  String get quicTitle;

  /// No description provided for @quicKeylogTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import a key log (SSLKEYLOGFILE) to enable 1-RTT stream decryption'**
  String get quicKeylogTooltip;

  /// No description provided for @quicCopySessionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy the session list (tab-separated, paste straight into a spreadsheet)'**
  String get quicCopySessionsTooltip;

  /// No description provided for @quicNoSni.
  ///
  /// In en, this message translates to:
  /// **'(no SNI)'**
  String get quicNoSni;

  /// No description provided for @quicPacketsBytes.
  ///
  /// In en, this message translates to:
  /// **'$packets packets / $bytes'**
  String quicPacketsBytes(int packets, String bytes);

  /// No description provided for @quicLastActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity $time'**
  String quicLastActivity(String time);

  /// No description provided for @quicCopiedSessions.
  ///
  /// In en, this message translates to:
  /// **'Copied $count sessions'**
  String quicCopiedSessions(int count);

  /// No description provided for @quicRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh (waiting for new QUIC packets)'**
  String get quicRefreshTooltip;

  /// No description provided for @quicClearRecords.
  ///
  /// In en, this message translates to:
  /// **'Clear records'**
  String get quicClearRecords;

  /// No description provided for @quicClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all QUIC connection records? Recorded sessions and key logs cannot be restored.'**
  String get quicClearConfirm;

  /// No description provided for @quicBannerNoKeylog.
  ///
  /// In en, this message translates to:
  /// **'Only QUIC connection-level metadata is shown (which domains use QUIC and connection stats). HTTP/3 content is encrypted with TLS 1.3 and cannot be decrypted by default; import a key log (SSLKEYLOGFILE) from the key icon at top right and matching connections will automatically decrypt 1-RTT stream data; or turn on Intercept QUIC to force a TCP fallback and capture full requests.'**
  String get quicBannerNoKeylog;

  /// No description provided for @quicBannerKeylogLoaded.
  ///
  /// In en, this message translates to:
  /// **'Imported $keys keys (covering $connections connections). Matching connections decrypt 1-RTT automatically (client direction only; HEADERS is QPACK-decoded including the dynamic table). For connections that did not match, turn on Intercept QUIC to fall back to TCP.'**
  String quicBannerKeylogLoaded(int keys, int connections);

  /// No description provided for @quicNoSniUnresolved.
  ///
  /// In en, this message translates to:
  /// **'(SNI not resolved)'**
  String get quicNoSniUnresolved;

  /// No description provided for @quicSessionSummary.
  ///
  /// In en, this message translates to:
  /// **'QUIC $version · $remote · first seen $firstSeen · last activity $ago'**
  String quicSessionSummary(String version, String remote, String firstSeen, String ago);

  /// No description provided for @quicSessionIds.
  ///
  /// In en, this message translates to:
  /// **'connection $dcid… · $packets packets / $frames frames · $bytes$decrypted'**
  String quicSessionIds(String dcid, int packets, int frames, String bytes, String decrypted);

  /// No description provided for @quicDecryptedSegments.
  ///
  /// In en, this message translates to:
  /// **' · $count segments decrypted'**
  String quicDecryptedSegments(int count);

  /// No description provided for @quicTimelineTitle.
  ///
  /// In en, this message translates to:
  /// **'QUIC packet volume in the last 10 minutes'**
  String get quicTimelineTitle;

  /// No description provided for @quicTimelineNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get quicTimelineNoData;

  /// No description provided for @quicTimelineSummary.
  ///
  /// In en, this message translates to:
  /// **'$packets packets · $bytes · traffic in $buckets buckets'**
  String quicTimelineSummary(int packets, String bytes, int buckets);

  /// No description provided for @quicTenMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'10 minutes ago'**
  String get quicTenMinutesAgo;

  /// No description provided for @quicPerCellTenSeconds.
  ///
  /// In en, this message translates to:
  /// **'10s per cell'**
  String get quicPerCellTenSeconds;

  /// No description provided for @quicNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get quicNow;

  /// No description provided for @quicImportedNKeys.
  ///
  /// In en, this message translates to:
  /// **'Imported $keys keys, covering $connections connections'**
  String quicImportedNKeys(int keys, int connections);

  /// No description provided for @quicNoNewKeyEntries.
  ///
  /// In en, this message translates to:
  /// **'No new key entries were parsed (make sure the file is in NSS key log format)'**
  String get quicNoNewKeyEntries;

  /// No description provided for @quicImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: $error'**
  String quicImportFailed(String error);

  /// No description provided for @quicDecryptedTitle.
  ///
  /// In en, this message translates to:
  /// **'$host · Decrypted content'**
  String quicDecryptedTitle(String host);

  /// No description provided for @quicDecryptedAbout.
  ///
  /// In en, this message translates to:
  /// **'$segments segments in total (client direction, 1-RTT). HEADERS is QPACK-compressed: static and dynamic table references are both decoded, and the dynamic table is restored in order from this connection\\'s QPACK encoder stream$table.'**
  String quicDecryptedAbout(int segments, String table);

  /// No description provided for @quicQpackTableUsed.
  ///
  /// In en, this message translates to:
  /// **' ($inserted inserted, $live live)'**
  String quicQpackTableUsed(int inserted, int live);

  /// No description provided for @quicQpackTableUnused.
  ///
  /// In en, this message translates to:
  /// **' (this connection does not use the dynamic table)'**
  String get quicQpackTableUnused;

  /// No description provided for @quicHttp3Headers.
  ///
  /// In en, this message translates to:
  /// **'HTTP/3 headers · $count QPACK-decoded entries'**
  String quicHttp3Headers(int count);

  /// No description provided for @quicStatConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get quicStatConnections;

  /// No description provided for @quicStatHosts.
  ///
  /// In en, this message translates to:
  /// **'Hosts'**
  String get quicStatHosts;

  /// No description provided for @quicStatPackets.
  ///
  /// In en, this message translates to:
  /// **'Packets'**
  String get quicStatPackets;

  /// No description provided for @quicStatTraffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get quicStatTraffic;

  /// No description provided for @quicStatActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get quicStatActive;

  /// No description provided for @quicSecondsAgo.
  ///
  /// In en, this message translates to:
  /// **'$seconds seconds ago'**
  String quicSecondsAgo(int seconds);

  /// No description provided for @quicMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'$minutes minutes ago'**
  String quicMinutesAgo(int minutes);

  /// No description provided for @quicHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'$hours hours ago'**
  String quicHoursAgo(int hours);

  /// No description provided for @quicEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No QUIC connections captured yet'**
  String get quicEmptyTitle;

  /// No description provided for @quicEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'After VPN capture is on, when a target app uses QUIC/HTTP3 (video, some social and game apps), its connections are recorded automatically: SNI host, QUIC version, connection ID and packet/frame stats.'**
  String get quicEmptyDesc;

  /// No description provided for @quicEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tip: most apps use TCP/HTTP2 by default. To see QUIC records, temporarily turn Intercept QUIC off in preferences and restart capture; decrypting payloads still requires turning Intercept QUIC on to fall back to TCP.'**
  String get quicEmptyHint;


  /// No description provided for @pinningDeployDone.
  ///
  /// In en, this message translates to:
  /// **'Script deployed to $path'**
  String pinningDeployDone(String path);

  /// No description provided for @pinningDeployFailed.
  ///
  /// In en, this message translates to:
  /// **'Deploy failed: $reason'**
  String pinningDeployFailed(String reason);

  /// No description provided for @pinningNeedPackage.
  ///
  /// In en, this message translates to:
  /// **'Enter the target package name'**
  String get pinningNeedPackage;

  /// No description provided for @pinningAttaching.
  ///
  /// In en, this message translates to:
  /// **'Attaching…'**
  String get pinningAttaching;

  /// No description provided for @pinningAttached.
  ///
  /// In en, this message translates to:
  /// **'Attached: $result'**
  String pinningAttached(String result);

  /// No description provided for @pinningAttachFailed.
  ///
  /// In en, this message translates to:
  /// **'Attach failed: $result'**
  String pinningAttachFailed(String result);

  /// No description provided for @pinningStopDone.
  ///
  /// In en, this message translates to:
  /// **'Injection stopped'**
  String get pinningStopDone;

  /// No description provided for @pinningStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Stop failed'**
  String get pinningStopFailed;

  /// No description provided for @pinningTitle.
  ///
  /// In en, this message translates to:
  /// **'SSL Pinning Bypass Helper'**
  String get pinningTitle;

  /// No description provided for @pinningRefreshEnv.
  ///
  /// In en, this message translates to:
  /// **'Refresh environment'**
  String get pinningRefreshEnv;

  /// No description provided for @pinningAndroidOnly.
  ///
  /// In en, this message translates to:
  /// **'Android only'**
  String get pinningAndroidOnly;

  /// No description provided for @pinningViewLog.
  ///
  /// In en, this message translates to:
  /// **'View log'**
  String get pinningViewLog;

  /// No description provided for @pinningNotice.
  ///
  /// In en, this message translates to:
  /// **'Use only on devices you own and on apps you are authorized to test. Bypassing certificate pinning is runtime intervention into the target process. No third-party binaries (frida-server, Xposed modules) are bundled.'**
  String get pinningNotice;

  /// No description provided for @pinningEnvTitle.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get pinningEnvTitle;

  /// No description provided for @pinningChecking.
  ///
  /// In en, this message translates to:
  /// **'checking…'**
  String get pinningChecking;

  /// No description provided for @pinningReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to attach'**
  String get pinningReady;

  /// No description provided for @pinningNotReady.
  ///
  /// In en, this message translates to:
  /// **'Not ready. Need root + frida-inject (recommended) or frida CLI on device. You can still generate the script and run it from a PC.'**
  String get pinningNotReady;

  /// No description provided for @pinningStep1Title.
  ///
  /// In en, this message translates to:
  /// **'1. Generate & deploy hook script'**
  String get pinningStep1Title;

  /// No description provided for @pinningStep1Hint.
  ///
  /// In en, this message translates to:
  /// **'Covers Conscrypt TrustManagerImpl, SSLContext.init, OkHttp CertificatePinner, HostnameVerifier.'**
  String get pinningStep1Hint;

  /// No description provided for @pinningDeploy.
  ///
  /// In en, this message translates to:
  /// **'Deploy to device'**
  String get pinningDeploy;

  /// No description provided for @pinningScriptCopied.
  ///
  /// In en, this message translates to:
  /// **'Script copied'**
  String get pinningScriptCopied;

  /// No description provided for @pinningCopyScript.
  ///
  /// In en, this message translates to:
  /// **'Copy script'**
  String get pinningCopyScript;

  /// No description provided for @pinningStep2Title.
  ///
  /// In en, this message translates to:
  /// **'2. Attach to target app'**
  String get pinningStep2Title;

  /// No description provided for @pinningPackageHint.
  ///
  /// In en, this message translates to:
  /// **'Package name'**
  String get pinningPackageHint;

  /// No description provided for @pinningSpawn.
  ///
  /// In en, this message translates to:
  /// **'Spawn mode (app checks on launch)'**
  String get pinningSpawn;

  /// No description provided for @pinningAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get pinningAttach;

  /// No description provided for @pinningOtherOptions.
  ///
  /// In en, this message translates to:
  /// **'Other options'**
  String get pinningOtherOptions;

  /// No description provided for @pinningOtherHint.
  ///
  /// In en, this message translates to:
  /// **'· First rule out "CA not installed": layer 1 is solved by installing the CA into the system store.
· With Magisk/LSPosed, a ready-made pinning-bypass module is simpler.
· Flutter apps use Dart\\'s own root list and need separate handling.'**
  String get pinningOtherHint;

  /// No description provided for @cloudServerSaved.
  ///
  /// In en, this message translates to:
  /// **'Server URL saved'**
  String get cloudServerSaved;

  /// No description provided for @cloudNeedCredentials.
  ///
  /// In en, this message translates to:
  /// **'Enter username and password'**
  String get cloudNeedCredentials;

  /// No description provided for @cloudAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: $error'**
  String cloudAuthFailed(String error);

  /// No description provided for @cloudSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get cloudSignedIn;

  /// No description provided for @cloudSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get cloudSignedOut;

  /// No description provided for @cloudNoLocalWorkspace.
  ///
  /// In en, this message translates to:
  /// **'No local workspace yet'**
  String get cloudNoLocalWorkspace;

  /// No description provided for @cloudPickWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Pick a workspace'**
  String get cloudPickWorkspace;

  /// No description provided for @cloudPushFailed.
  ///
  /// In en, this message translates to:
  /// **'Push failed: $error'**
  String cloudPushFailed(String error);

  /// No description provided for @cloudPushed.
  ///
  /// In en, this message translates to:
  /// **'Pushed to cloud'**
  String get cloudPushed;

  /// No description provided for @cloudRemoteEmpty.
  ///
  /// In en, this message translates to:
  /// **'Remote workspace is empty'**
  String get cloudRemoteEmpty;

  /// No description provided for @cloudPulled.
  ///
  /// In en, this message translates to:
  /// **'Pulled $count requests'**
  String cloudPulled(int count);

  /// No description provided for @cloudPullFailed.
  ///
  /// In en, this message translates to:
  /// **'Pull failed: $error'**
  String cloudPullFailed(String error);

  /// No description provided for @cloudDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this workspace copy from the cloud? This cannot be undone.'**
  String get cloudDeleteConfirm;

  /// No description provided for @cloudDeleted.
  ///
  /// In en, this message translates to:
  /// **'Removed from cloud'**
  String get cloudDeleted;

  /// No description provided for @cloudRealtimeFailed.
  ///
  /// In en, this message translates to:
  /// **'Realtime connect failed'**
  String get cloudRealtimeFailed;

  /// No description provided for @cloudTitle.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get cloudTitle;

  /// No description provided for @cloudServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get cloudServer;

  /// No description provided for @cloudServerHint.
  ///
  /// In en, this message translates to:
  /// **'Your own server. A runnable Node implementation ships with the docs.'**
  String get cloudServerHint;

  /// No description provided for @cloudAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get cloudAccount;

  /// No description provided for @cloudSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get cloudSignOut;

  /// No description provided for @cloudSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get cloudSignIn;

  /// No description provided for @cloudRegister.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get cloudRegister;

  /// No description provided for @cloudRealtime.
  ///
  /// In en, this message translates to:
  /// **'Realtime'**
  String get cloudRealtime;

  /// No description provided for @cloudRealtimeOn.
  ///
  /// In en, this message translates to:
  /// **'Connected — changes from others arrive live'**
  String get cloudRealtimeOn;

  /// No description provided for @cloudRealtimeOff.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get cloudRealtimeOff;

  /// No description provided for @cloudWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Cloud workspaces'**
  String get cloudWorkspaces;

  /// No description provided for @cloudPushLocal.
  ///
  /// In en, this message translates to:
  /// **'Push a local workspace'**
  String get cloudPushLocal;

  /// No description provided for @cloudNoRemote.
  ///
  /// In en, this message translates to:
  /// **'Nothing on the server yet'**
  String get cloudNoRemote;

  /// No description provided for @cloudPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get cloudPull;

  /// No description provided for @cloudDeleteRemote.
  ///
  /// In en, this message translates to:
  /// **'Delete on server'**
  String get cloudDeleteRemote;

  /// No description provided for @cloudTeam.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get cloudTeam;

  /// No description provided for @cloudTapRefresh.
  ///
  /// In en, this message translates to:
  /// **'(tap refresh)'**
  String get cloudTapRefresh;

  /// No description provided for @cloudInviteUser.
  ///
  /// In en, this message translates to:
  /// **'Invite user'**
  String get cloudInviteUser;

  /// No description provided for @cloudInvited.
  ///
  /// In en, this message translates to:
  /// **'Invited $name'**
  String cloudInvited(String name);

  /// No description provided for @cloudInviteFailed.
  ///
  /// In en, this message translates to:
  /// **'Invite failed: $error'**
  String cloudInviteFailed(String error);

  /// No description provided for @cloudInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get cloudInvite;


  /// No description provided for @sslP12FileEmpty.
  ///
  /// In en, this message translates to:
  /// **'The selected file is empty, please choose the .p12 file again'**
  String get sslP12FileEmpty;

  /// No description provided for @sslAutoInstallHint.
  ///
  /// In en, this message translates to:
  /// **'Auto install (needs Root; written as a module, reboot required)
Modern Android keeps /system and /apex read-only, so instead of copying files we install a module'**
  String get sslAutoInstallHint;

  /// No description provided for @sslAutoInstallToSystem.
  ///
  /// In en, this message translates to:
  /// **'Auto install to system'**
  String get sslAutoInstallToSystem;

  /// No description provided for @sslRemoveSystemCA.
  ///
  /// In en, this message translates to:
  /// **'Remove system CA'**
  String get sslRemoveSystemCA;

  /// No description provided for @sslRemoveSystemCAConfirm.
  ///
  /// In en, this message translates to:
  /// **'This deletes the CA written into the system trust store (Magisk module); HTTPS capture will stop working. Continue?'**
  String get sslRemoveSystemCAConfirm;

  /// No description provided for @sslRemoveInstalledSystemCA.
  ///
  /// In en, this message translates to:
  /// **'Remove installed system CA'**
  String get sslRemoveInstalledSystemCA;

  /// No description provided for @sslNoModuleManager.
  ///
  /// In en, this message translates to:
  /// **'No Magisk / KernelSU / APatch?'**
  String get sslNoModuleManager;

  /// No description provided for @sslRuntimeMountDesc.
  ///
  /// In en, this message translates to:
  /// **'Mount the CA into the system trust store via root: a runtime mount that reverts on reboot, fully reversible, no device reboot needed. For rooted devices without a module manager.'**
  String get sslRuntimeMountDesc;

  /// No description provided for @sslMountToTrustStore.
  ///
  /// In en, this message translates to:
  /// **'Mount to system trust store (root)'**
  String get sslMountToTrustStore;

  /// No description provided for @sslUnmountRuntimeCA.
  ///
  /// In en, this message translates to:
  /// **'Unmount runtime CA'**
  String get sslUnmountRuntimeCA;

  /// No description provided for @sslUnmountRuntimeCAConfirm.
  ///
  /// In en, this message translates to:
  /// **'This unmounts the runtime CA; HTTPS capture will stop working. Continue?'**
  String get sslUnmountRuntimeCAConfirm;

  /// No description provided for @sslRestartZygote.
  ///
  /// In en, this message translates to:
  /// **'Restart zygote (apply to running apps)'**
  String get sslRestartZygote;

  /// No description provided for @sslAndroid13MountHint.
  ///
  /// In en, this message translates to:
  /// **'Android 13: Mount the certificate to \\'/system/etc/security/cacerts\\' directory'**
  String get sslAndroid13MountHint;

  /// No description provided for @sslAndroid14MountHint.
  ///
  /// In en, this message translates to:
  /// **'Android 14: Mount the certificate to \\'/apex/com.android.conscrypt/cacerts\\' directory'**
  String get sslAndroid14MountHint;

  /// No description provided for @sslAndroidCaInstallNote.
  ///
  /// In en, this message translates to:
  /// **'Note: Pick CA certificate (not VPN and app certificate) during install; on Android 14+ the CA directory lives in APEX, so copying the file alone may not take effect — a bind-mount module is usually required'**
  String get sslAndroidCaInstallNote;

  /// No description provided for @sslNoModuleDirMsg.
  ///
  /// In en, this message translates to:
  /// **'No /data/adb/modules found: this device has no Magisk/KernelSU/APatch. Download the CA and install it as a module manually.'**
  String get sslNoModuleDirMsg;

  /// No description provided for @sslInstallFailedRoot.
  ///
  /// In en, this message translates to:
  /// **'Install failed ($output). Make sure root is granted.'**
  String sslInstallFailedRoot(String output);

  /// No description provided for @sslModuleInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed as a Magisk module. Reboot to take effect.'**
  String get sslModuleInstalled;

  /// No description provided for @sslAutoInstallFailedRoot.
  ///
  /// In en, this message translates to:
  /// **'Auto install failed: $error. Make sure root is granted.'**
  String sslAutoInstallFailedRoot(String error);

  /// No description provided for @sslRemovedReboot.
  ///
  /// In en, this message translates to:
  /// **'Removed. Reboot to take effect.'**
  String get sslRemovedReboot;

  /// No description provided for @sslRemoveFailedRoot.
  ///
  /// In en, this message translates to:
  /// **'Remove failed. Make sure root is granted.'**
  String get sslRemoveFailedRoot;

  /// No description provided for @sslRemoveFailedError.
  ///
  /// In en, this message translates to:
  /// **'Remove failed: $error'**
  String sslRemoveFailedError(String error);

  /// No description provided for @sslMountingGrantRoot.
  ///
  /// In en, this message translates to:
  /// **'Mounting, please grant root when prompted'**
  String get sslMountingGrantRoot;

  /// No description provided for @sslMountedTrustStore.
  ///
  /// In en, this message translates to:
  /// **'Mounted into the system trust store (reverts on reboot). Restart the target app, or tap "Restart zygote".'**
  String get sslMountedTrustStore;

  /// No description provided for @sslMountFailed.
  ///
  /// In en, this message translates to:
  /// **'Mount failed: $message'**
  String sslMountFailed(String message);

  /// No description provided for @sslUnmountedRestored.
  ///
  /// In en, this message translates to:
  /// **'Unmounted. The system trust store is back to its original state.'**
  String get sslUnmountedRestored;

  /// No description provided for @sslUnmountFailed.
  ///
  /// In en, this message translates to:
  /// **'Unmount failed: $message'**
  String sslUnmountFailed(String message);

  /// No description provided for @sslZygoteRestarted.
  ///
  /// In en, this message translates to:
  /// **'zygote restart signalled; all apps will restart briefly'**
  String get sslZygoteRestarted;

  /// No description provided for @sslZygoteRestartFailed.
  ///
  /// In en, this message translates to:
  /// **'Restart failed: $message'**
  String sslZygoteRestartFailed(String message);

  /// No description provided for @sslCertNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Certificate Not Installed'**
  String get sslCertNotInstalled;

  /// No description provided for @sslTapInstallRootCA.
  ///
  /// In en, this message translates to:
  /// **'Tap "Install Root CA" to proceed'**
  String get sslTapInstallRootCA;

  /// No description provided for @sslCertNotTrusted.
  ///
  /// In en, this message translates to:
  /// **'Certificate Not Trusted'**
  String get sslCertNotTrusted;

  /// No description provided for @sslCertInstalledTrusted.
  ///
  /// In en, this message translates to:
  /// **'Certificate Installed & Trusted'**
  String get sslCertInstalledTrusted;

  /// No description provided for @sslGuide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get sslGuide;


  /// No description provided for @mcpAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'MCP Automation'**
  String get mcpAutoTitle;

  /// No description provided for @mcpAutoTutorial.
  ///
  /// In en, this message translates to:
  /// **'Tutorial'**
  String get mcpAutoTutorial;

  /// No description provided for @mcpAutoRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get mcpAutoRefresh;

  /// No description provided for @mcpAutoRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Refreshed'**
  String get mcpAutoRefreshed;

  /// No description provided for @mcpAutoCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get mcpAutoCancel;

  /// No description provided for @mcpAutoSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get mcpAutoSave;

  /// No description provided for @mcpAutoConfirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get mcpAutoConfirm;

  /// No description provided for @mcpAutoClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get mcpAutoClose;

  /// No description provided for @mcpAutoDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get mcpAutoDelete;

  /// No description provided for @mcpAutoEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get mcpAutoEdit;

  /// No description provided for @mcpAutoEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get mcpAutoEnable;

  /// No description provided for @mcpAutoEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get mcpAutoEnabled;

  /// No description provided for @mcpAutoDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get mcpAutoDisabled;

  /// No description provided for @mcpAutoName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get mcpAutoName;

  /// No description provided for @mcpAutoDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get mcpAutoDescription;

  /// No description provided for @mcpAutoValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get mcpAutoValue;

  /// No description provided for @mcpAutoEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get mcpAutoEmpty;

  /// No description provided for @mcpAutoUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed'**
  String get mcpAutoUnnamed;

  /// No description provided for @mcpAutoCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get mcpAutoCustom;

  /// No description provided for @mcpAutoPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get mcpAutoPriority;

  /// No description provided for @mcpAutoConditionType.
  ///
  /// In en, this message translates to:
  /// **'Condition type'**
  String get mcpAutoConditionType;

  /// No description provided for @mcpAutoTargetParams.
  ///
  /// In en, this message translates to:
  /// **'Target / parameters (JSON)'**
  String get mcpAutoTargetParams;

  /// No description provided for @mcpAutoTabTasks.
  ///
  /// In en, this message translates to:
  /// **'Scheduled tasks'**
  String get mcpAutoTabTasks;

  /// No description provided for @mcpAutoTabEvents.
  ///
  /// In en, this message translates to:
  /// **'Event listeners'**
  String get mcpAutoTabEvents;

  /// No description provided for @mcpAutoTabRules.
  ///
  /// In en, this message translates to:
  /// **'Rule engine'**
  String get mcpAutoTabRules;

  /// No description provided for @mcpAutoTabWorkflows.
  ///
  /// In en, this message translates to:
  /// **'Workflows'**
  String get mcpAutoTabWorkflows;

  /// No description provided for @mcpAutoStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get mcpAutoStatusChecking;

  /// No description provided for @mcpAutoStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get mcpAutoStatusRunning;

  /// No description provided for @mcpAutoStatusStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get mcpAutoStatusStopped;

  /// No description provided for @mcpAutoTapToStop.
  ///
  /// In en, this message translates to:
  /// **'Tap to stop MCP automation'**
  String get mcpAutoTapToStop;

  /// No description provided for @mcpAutoTapToStart.
  ///
  /// In en, this message translates to:
  /// **'Tap to start MCP automation'**
  String get mcpAutoTapToStart;

  /// No description provided for @mcpAutoServiceStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start the MCP service. Check that the MCP service is enabled in settings.'**
  String get mcpAutoServiceStartFailed;

  /// No description provided for @mcpAutoServiceStopped.
  ///
  /// In en, this message translates to:
  /// **'MCP service stopped'**
  String get mcpAutoServiceStopped;

  /// No description provided for @mcpAutoServiceStarted.
  ///
  /// In en, this message translates to:
  /// **'MCP service started'**
  String get mcpAutoServiceStarted;

  /// No description provided for @mcpAutoServiceNotStarted.
  ///
  /// In en, this message translates to:
  /// **'MCP service is not running. Start it on the Connection page first.'**
  String get mcpAutoServiceNotStarted;

  /// No description provided for @mcpAutoEditRoot.
  ///
  /// In en, this message translates to:
  /// **'Edit Root'**
  String get mcpAutoEditRoot;

  /// No description provided for @mcpAutoAddRoot.
  ///
  /// In en, this message translates to:
  /// **'Add Root'**
  String get mcpAutoAddRoot;

  /// No description provided for @mcpAutoRootUriHint.
  ///
  /// In en, this message translates to:
  /// **'proxypin://workspace or file:///path/to/dir'**
  String get mcpAutoRootUriHint;

  /// No description provided for @mcpAutoRootUriRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the Root URI'**
  String get mcpAutoRootUriRequired;

  /// No description provided for @mcpAutoRootUpdated.
  ///
  /// In en, this message translates to:
  /// **'Root updated'**
  String get mcpAutoRootUpdated;

  /// No description provided for @mcpAutoRootAdded.
  ///
  /// In en, this message translates to:
  /// **'Root added'**
  String get mcpAutoRootAdded;

  /// No description provided for @mcpAutoRootDeleted.
  ///
  /// In en, this message translates to:
  /// **'Root deleted'**
  String get mcpAutoRootDeleted;

  /// No description provided for @mcpAutoNoRoots.
  ///
  /// In en, this message translates to:
  /// **'No Roots'**
  String get mcpAutoNoRoots;

  /// No description provided for @mcpAutoNoRootsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + at bottom right to add a Root
Add a proxypin:// or file:// resource root and edit it freely'**
  String get mcpAutoNoRootsHint;

  /// No description provided for @mcpAutoDeleteRootConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this Root configuration?'**
  String get mcpAutoDeleteRootConfirm;

  /// No description provided for @mcpAutoReading.
  ///
  /// In en, this message translates to:
  /// **'Reading $name…'**
  String mcpAutoReading(String name);

  /// No description provided for @mcpAutoReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Read failed: $error'**
  String mcpAutoReadFailed(String error);

  /// No description provided for @mcpAutoScriptNotFound.
  ///
  /// In en, this message translates to:
  /// **'Script not found: $name'**
  String mcpAutoScriptNotFound(String name);

  /// No description provided for @mcpAutoScriptExecuted.
  ///
  /// In en, this message translates to:
  /// **'Script executed: $name'**
  String mcpAutoScriptExecuted(String name);

  /// No description provided for @mcpAutoScriptRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Script failed: $error'**
  String mcpAutoScriptRunFailed(String error);

  /// No description provided for @mcpAutoNoTasks.
  ///
  /// In en, this message translates to:
  /// **'No scheduled tasks'**
  String get mcpAutoNoTasks;

  /// No description provided for @mcpAutoNoTasksHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + at bottom right to add a task
Pick both the run time and what to run'**
  String get mcpAutoNoTasksHint;

  /// No description provided for @mcpAutoNextPrefix.
  ///
  /// In en, this message translates to:
  /// **'Next: '**
  String get mcpAutoNextPrefix;

  /// No description provided for @mcpAutoLastRun.
  ///
  /// In en, this message translates to:
  /// **' • Last run: $time'**
  String mcpAutoLastRun(String time);

  /// No description provided for @mcpAutoRanTimes.
  ///
  /// In en, this message translates to:
  /// **' • Ran $count/$total times'**
  String mcpAutoRanTimes(int count, int total);

  /// No description provided for @mcpAutoDeleteTaskConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel and delete this scheduled task?'**
  String get mcpAutoDeleteTaskConfirm;

  /// No description provided for @mcpAutoAddTask.
  ///
  /// In en, this message translates to:
  /// **'Add scheduled task'**
  String get mcpAutoAddTask;

  /// No description provided for @mcpAutoTaskName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get mcpAutoTaskName;

  /// No description provided for @mcpAutoScheduleMode.
  ///
  /// In en, this message translates to:
  /// **'Schedule mode:'**
  String get mcpAutoScheduleMode;

  /// No description provided for @mcpAutoModeOnce.
  ///
  /// In en, this message translates to:
  /// **'One-off'**
  String get mcpAutoModeOnce;

  /// No description provided for @mcpAutoModeDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get mcpAutoModeDaily;

  /// No description provided for @mcpAutoModeWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get mcpAutoModeWeekly;

  /// No description provided for @mcpAutoModeInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get mcpAutoModeInterval;

  /// No description provided for @mcpAutoCronLabel.
  ///
  /// In en, this message translates to:
  /// **'Cron expression'**
  String get mcpAutoCronLabel;

  /// No description provided for @mcpAutoCronHint.
  ///
  /// In en, this message translates to:
  /// **'min hour day month weekday, e.g. 0 9 * * 1-5'**
  String get mcpAutoCronHint;

  /// No description provided for @mcpAutoCronHelper.
  ///
  /// In en, this message translates to:
  /// **'Supports * , - / wildcards'**
  String get mcpAutoCronHelper;

  /// No description provided for @mcpAutoCronRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a Cron expression'**
  String get mcpAutoCronRequired;

  /// No description provided for @mcpAutoCronInvalidHint.
  ///
  /// In en, this message translates to:
  /// **'Invalid expression, please check'**
  String get mcpAutoCronInvalidHint;

  /// No description provided for @mcpAutoCronNextAt.
  ///
  /// In en, this message translates to:
  /// **'Next run: $time'**
  String mcpAutoCronNextAt(String time);

  /// No description provided for @mcpAutoCronPresetWorkday.
  ///
  /// In en, this message translates to:
  /// **'9am on weekdays'**
  String get mcpAutoCronPresetWorkday;

  /// No description provided for @mcpAutoCronPresetEvery30.
  ///
  /// In en, this message translates to:
  /// **'Every 30 minutes'**
  String get mcpAutoCronPresetEvery30;

  /// No description provided for @mcpAutoCronPresetMidnight.
  ///
  /// In en, this message translates to:
  /// **'Every day at midnight'**
  String get mcpAutoCronPresetMidnight;

  /// No description provided for @mcpAutoExecDateTime.
  ///
  /// In en, this message translates to:
  /// **'Run date & time:'**
  String get mcpAutoExecDateTime;

  /// No description provided for @mcpAutoExecTime.
  ///
  /// In en, this message translates to:
  /// **'Run time:'**
  String get mcpAutoExecTime;

  /// No description provided for @mcpAutoPickDate.
  ///
  /// In en, this message translates to:
  /// **'Select run date'**
  String get mcpAutoPickDate;

  /// No description provided for @mcpAutoRepeatOn.
  ///
  /// In en, this message translates to:
  /// **'Repeat on:'**
  String get mcpAutoRepeatOn;

  /// No description provided for @mcpAutoWeekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get mcpAutoWeekdayMon;

  /// No description provided for @mcpAutoWeekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get mcpAutoWeekdayTue;

  /// No description provided for @mcpAutoWeekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get mcpAutoWeekdayWed;

  /// No description provided for @mcpAutoWeekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get mcpAutoWeekdayThu;

  /// No description provided for @mcpAutoWeekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get mcpAutoWeekdayFri;

  /// No description provided for @mcpAutoWeekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get mcpAutoWeekdaySat;

  /// No description provided for @mcpAutoWeekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get mcpAutoWeekdaySun;

  /// No description provided for @mcpAutoPickWeekday.
  ///
  /// In en, this message translates to:
  /// **'Select at least one weekday'**
  String get mcpAutoPickWeekday;

  /// No description provided for @mcpAutoIntervalMinutes.
  ///
  /// In en, this message translates to:
  /// **'Interval (minutes)'**
  String get mcpAutoIntervalMinutes;

  /// No description provided for @mcpAutoIntervalMinutesHelp.
  ///
  /// In en, this message translates to:
  /// **'e.g. 30 runs the task every 30 minutes'**
  String get mcpAutoIntervalMinutesHelp;

  /// No description provided for @mcpAutoRepeatCount.
  ///
  /// In en, this message translates to:
  /// **'Repeat count'**
  String get mcpAutoRepeatCount;

  /// No description provided for @mcpAutoRepeatCountHelp.
  ///
  /// In en, this message translates to:
  /// **'e.g. 5 stops after 5 runs; leave empty for unlimited'**
  String get mcpAutoRepeatCountHelp;

  /// No description provided for @mcpAutoTaskAction.
  ///
  /// In en, this message translates to:
  /// **'Task action:'**
  String get mcpAutoTaskAction;

  /// No description provided for @mcpAutoActionScript.
  ///
  /// In en, this message translates to:
  /// **'Run script'**
  String get mcpAutoActionScript;

  /// No description provided for @mcpAutoActionTool.
  ///
  /// In en, this message translates to:
  /// **'Call MCP tool'**
  String get mcpAutoActionTool;

  /// No description provided for @mcpAutoActionWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Run workflow'**
  String get mcpAutoActionWorkflow;

  /// No description provided for @mcpAutoActionWebhook.
  ///
  /// In en, this message translates to:
  /// **'Send Webhook'**
  String get mcpAutoActionWebhook;

  /// No description provided for @mcpAutoPickScript.
  ///
  /// In en, this message translates to:
  /// **'Select script'**
  String get mcpAutoPickScript;

  /// No description provided for @mcpAutoNoScriptAddFirst.
  ///
  /// In en, this message translates to:
  /// **'No scripts yet, add one on the Scripts page first'**
  String get mcpAutoNoScriptAddFirst;

  /// No description provided for @mcpAutoPickTool.
  ///
  /// In en, this message translates to:
  /// **'Select MCP tool'**
  String get mcpAutoPickTool;

  /// No description provided for @mcpAutoNoTools.
  ///
  /// In en, this message translates to:
  /// **'No tools'**
  String get mcpAutoNoTools;

  /// No description provided for @mcpAutoToolsNeedStart.
  ///
  /// In en, this message translates to:
  /// **'MCP is not running, tools unavailable'**
  String get mcpAutoToolsNeedStart;

  /// No description provided for @mcpAutoPickWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Select workflow'**
  String get mcpAutoPickWorkflow;

  /// No description provided for @mcpAutoNoWorkflowAddFirst.
  ///
  /// In en, this message translates to:
  /// **'No workflows yet, add one on the Workflows page first'**
  String get mcpAutoNoWorkflowAddFirst;

  /// No description provided for @mcpAutoTaskNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a task name'**
  String get mcpAutoTaskNameRequired;

  /// No description provided for @mcpAutoIntervalInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid interval in minutes'**
  String get mcpAutoIntervalInvalid;

  /// No description provided for @mcpAutoCronInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid Cron expression'**
  String get mcpAutoCronInvalid;

  /// No description provided for @mcpAutoTaskActionIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Complete the task action configuration'**
  String get mcpAutoTaskActionIncomplete;

  /// No description provided for @mcpAutoTaskAdded.
  ///
  /// In en, this message translates to:
  /// **'Scheduled task added'**
  String get mcpAutoTaskAdded;

  /// No description provided for @mcpAutoTaskCancelled.
  ///
  /// In en, this message translates to:
  /// **'Task cancelled'**
  String get mcpAutoTaskCancelled;

  /// No description provided for @mcpAutoNoListeners.
  ///
  /// In en, this message translates to:
  /// **'No event listeners'**
  String get mcpAutoNoListeners;

  /// No description provided for @mcpAutoNoListenersHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + to register a listener
Log or run tasks when triggered'**
  String get mcpAutoNoListenersHint;

  /// No description provided for @mcpAutoRemoveListenerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this event listener?'**
  String get mcpAutoRemoveListenerConfirm;

  /// No description provided for @mcpAutoEventTypesInfo.
  ///
  /// In en, this message translates to:
  /// **'Event types'**
  String get mcpAutoEventTypesInfo;

  /// No description provided for @mcpAutoEventTypesBody.
  ///
  /// In en, this message translates to:
  /// **'• HTTP request event: triggered when the URL regex matches
• Network status event: connected / disconnected / wifi / weak
• Proxy status event: started / stopped / paused / resumed
• Capture threshold event: capture count reaches the threshold'**
  String get mcpAutoEventTypesBody;

  /// No description provided for @mcpAutoAddListener.
  ///
  /// In en, this message translates to:
  /// **'Add event listener'**
  String get mcpAutoAddListener;

  /// No description provided for @mcpAutoEventHttp.
  ///
  /// In en, this message translates to:
  /// **'HTTP request event'**
  String get mcpAutoEventHttp;

  /// No description provided for @mcpAutoEventNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network status event'**
  String get mcpAutoEventNetwork;

  /// No description provided for @mcpAutoEventProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy status event'**
  String get mcpAutoEventProxy;

  /// No description provided for @mcpAutoEventCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture threshold event'**
  String get mcpAutoEventCapture;

  /// No description provided for @mcpAutoUrlRegex.
  ///
  /// In en, this message translates to:
  /// **'URL regex'**
  String get mcpAutoUrlRegex;

  /// No description provided for @mcpAutoCaptureThreshold.
  ///
  /// In en, this message translates to:
  /// **'Capture count threshold'**
  String get mcpAutoCaptureThreshold;

  /// No description provided for @mcpAutoDescHttp.
  ///
  /// In en, this message translates to:
  /// **'HTTP request: $pattern'**
  String mcpAutoDescHttp(String pattern);

  /// No description provided for @mcpAutoDescNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network status: $status'**
  String mcpAutoDescNetwork(String status);

  /// No description provided for @mcpAutoDescProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy status: $status'**
  String mcpAutoDescProxy(String status);

  /// No description provided for @mcpAutoDescCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture threshold: $count'**
  String mcpAutoDescCapture(int count);

  /// No description provided for @mcpAutoListenerAdded.
  ///
  /// In en, this message translates to:
  /// **'Listener registered'**
  String get mcpAutoListenerAdded;

  /// No description provided for @mcpAutoListenerRemoved.
  ///
  /// In en, this message translates to:
  /// **'Listener removed'**
  String get mcpAutoListenerRemoved;

  /// No description provided for @mcpAutoNoRules.
  ///
  /// In en, this message translates to:
  /// **'No automation rules'**
  String get mcpAutoNoRules;

  /// No description provided for @mcpAutoNoRulesHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add a rule
Rules run actions automatically when conditions match'**
  String get mcpAutoNoRulesHint;

  /// No description provided for @mcpAutoRuleSummary.
  ///
  /// In en, this message translates to:
  /// **'$conditions conditions • $actions actions • $enabled'**
  String mcpAutoRuleSummary(int conditions, int actions, String enabled);

  /// No description provided for @mcpAutoDeleteRuleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this rule?'**
  String get mcpAutoDeleteRuleConfirm;

  /// No description provided for @mcpAutoConditionsInline.
  ///
  /// In en, this message translates to:
  /// **'Conditions:'**
  String get mcpAutoConditionsInline;

  /// No description provided for @mcpAutoActionsInline.
  ///
  /// In en, this message translates to:
  /// **'Actions:'**
  String get mcpAutoActionsInline;

  /// No description provided for @mcpAutoRuleEngineInfo.
  ///
  /// In en, this message translates to:
  /// **'Rule engine'**
  String get mcpAutoRuleEngineInfo;

  /// No description provided for @mcpAutoRuleEngineInfoBody.
  ///
  /// In en, this message translates to:
  /// **'14 condition operators and 8 action types
Rules persist to mcp_rules.json across restarts'**
  String get mcpAutoRuleEngineInfoBody;

  /// No description provided for @mcpAutoEditRule.
  ///
  /// In en, this message translates to:
  /// **'Edit rule'**
  String get mcpAutoEditRule;

  /// No description provided for @mcpAutoAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get mcpAutoAddRule;

  /// No description provided for @mcpAutoRuleName.
  ///
  /// In en, this message translates to:
  /// **'Rule name'**
  String get mcpAutoRuleName;

  /// No description provided for @mcpAutoSectionConditions.
  ///
  /// In en, this message translates to:
  /// **'Conditions'**
  String get mcpAutoSectionConditions;

  /// No description provided for @mcpAutoSectionActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get mcpAutoSectionActions;

  /// No description provided for @mcpAutoRuleNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a rule name'**
  String get mcpAutoRuleNameRequired;

  /// No description provided for @mcpAutoRuleUpdated.
  ///
  /// In en, this message translates to:
  /// **'Rule updated'**
  String get mcpAutoRuleUpdated;

  /// No description provided for @mcpAutoRuleAdded.
  ///
  /// In en, this message translates to:
  /// **'Rule added'**
  String get mcpAutoRuleAdded;

  /// No description provided for @mcpAutoRuleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Rule deleted'**
  String get mcpAutoRuleDeleted;

  /// No description provided for @mcpAutoShortProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get mcpAutoShortProxy;

  /// No description provided for @mcpAutoShortNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get mcpAutoShortNetwork;

  /// No description provided for @mcpAutoShortSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get mcpAutoShortSystem;

  /// No description provided for @mcpAutoCondTypeHttp.
  ///
  /// In en, this message translates to:
  /// **'HTTP request'**
  String get mcpAutoCondTypeHttp;

  /// No description provided for @mcpAutoCondTypeProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy status'**
  String get mcpAutoCondTypeProxy;

  /// No description provided for @mcpAutoCondTypeNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network status'**
  String get mcpAutoCondTypeNetwork;

  /// No description provided for @mcpAutoCondTypeSystem.
  ///
  /// In en, this message translates to:
  /// **'System status'**
  String get mcpAutoCondTypeSystem;

  /// No description provided for @mcpAutoOpContains.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get mcpAutoOpContains;

  /// No description provided for @mcpAutoOpStartsWith.
  ///
  /// In en, this message translates to:
  /// **'starts with'**
  String get mcpAutoOpStartsWith;

  /// No description provided for @mcpAutoOpEndsWith.
  ///
  /// In en, this message translates to:
  /// **'ends with'**
  String get mcpAutoOpEndsWith;

  /// No description provided for @mcpAutoOpMatches.
  ///
  /// In en, this message translates to:
  /// **'matches'**
  String get mcpAutoOpMatches;

  /// No description provided for @mcpAutoOpInList.
  ///
  /// In en, this message translates to:
  /// **'in list'**
  String get mcpAutoOpInList;

  /// No description provided for @mcpAutoOpNotInList.
  ///
  /// In en, this message translates to:
  /// **'not in list'**
  String get mcpAutoOpNotInList;

  /// No description provided for @mcpAutoOpExists.
  ///
  /// In en, this message translates to:
  /// **'exists'**
  String get mcpAutoOpExists;

  /// No description provided for @mcpAutoOpNotExists.
  ///
  /// In en, this message translates to:
  /// **'does not exist'**
  String get mcpAutoOpNotExists;

  /// No description provided for @mcpAutoActLog.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get mcpAutoActLog;

  /// No description provided for @mcpAutoActNotify.
  ///
  /// In en, this message translates to:
  /// **'Notify'**
  String get mcpAutoActNotify;

  /// No description provided for @mcpAutoActStopCapture.
  ///
  /// In en, this message translates to:
  /// **'Stop capture'**
  String get mcpAutoActStopCapture;

  /// No description provided for @mcpAutoActStartCapture.
  ///
  /// In en, this message translates to:
  /// **'Start capture'**
  String get mcpAutoActStartCapture;

  /// No description provided for @mcpAutoActExportData.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get mcpAutoActExportData;

  /// No description provided for @mcpAutoFieldMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get mcpAutoFieldMethod;

  /// No description provided for @mcpAutoFieldStatusCode.
  ///
  /// In en, this message translates to:
  /// **'Status code'**
  String get mcpAutoFieldStatusCode;

  /// No description provided for @mcpAutoFieldDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration (ms)'**
  String get mcpAutoFieldDuration;

  /// No description provided for @mcpAutoFieldHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get mcpAutoFieldHost;

  /// No description provided for @mcpAutoFieldPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get mcpAutoFieldPath;

  /// No description provided for @mcpAutoFieldReqContentType.
  ///
  /// In en, this message translates to:
  /// **'Request Content-Type'**
  String get mcpAutoFieldReqContentType;

  /// No description provided for @mcpAutoFieldRespContentType.
  ///
  /// In en, this message translates to:
  /// **'Response Content-Type'**
  String get mcpAutoFieldRespContentType;

  /// No description provided for @mcpAutoFieldReqSize.
  ///
  /// In en, this message translates to:
  /// **'Request size'**
  String get mcpAutoFieldReqSize;

  /// No description provided for @mcpAutoFieldRespSize.
  ///
  /// In en, this message translates to:
  /// **'Response size'**
  String get mcpAutoFieldRespSize;

  /// No description provided for @mcpAutoFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get mcpAutoFieldType;

  /// No description provided for @mcpAutoFieldTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get mcpAutoFieldTimestamp;

  /// No description provided for @mcpAutoFieldMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory usage (MB)'**
  String get mcpAutoFieldMemory;

  /// No description provided for @mcpAutoFieldCaptureCount.
  ///
  /// In en, this message translates to:
  /// **'Capture count'**
  String get mcpAutoFieldCaptureCount;

  /// No description provided for @mcpAutoFieldDisk.
  ///
  /// In en, this message translates to:
  /// **'Disk usage (MB)'**
  String get mcpAutoFieldDisk;

  /// No description provided for @mcpAutoFieldCpu.
  ///
  /// In en, this message translates to:
  /// **'CPU usage (%)'**
  String get mcpAutoFieldCpu;

  /// No description provided for @mcpAutoStatusStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get mcpAutoStatusStarted;

  /// No description provided for @mcpAutoStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get mcpAutoStatusPaused;

  /// No description provided for @mcpAutoStatusResumed.
  ///
  /// In en, this message translates to:
  /// **'Resumed'**
  String get mcpAutoStatusResumed;

  /// No description provided for @mcpAutoStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get mcpAutoStatusConnected;

  /// No description provided for @mcpAutoStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get mcpAutoStatusDisconnected;

  /// No description provided for @mcpAutoStatusMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile data'**
  String get mcpAutoStatusMobile;

  /// No description provided for @mcpAutoStatusWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak network'**
  String get mcpAutoStatusWeak;

  /// No description provided for @mcpAutoNoPrompts.
  ///
  /// In en, this message translates to:
  /// **'No Prompts'**
  String get mcpAutoNoPrompts;

  /// No description provided for @mcpAutoTapInvokePrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap + to invoke a Prompt'**
  String get mcpAutoTapInvokePrompt;

  /// No description provided for @mcpAutoPromptDescWithArgs.
  ///
  /// In en, this message translates to:
  /// **'$desc
Parameters: $params'**
  String mcpAutoPromptDescWithArgs(String desc, String params);

  /// No description provided for @mcpAutoNoPromptAvailable.
  ///
  /// In en, this message translates to:
  /// **'No Prompts available'**
  String get mcpAutoNoPromptAvailable;

  /// No description provided for @mcpAutoInvokePrompt.
  ///
  /// In en, this message translates to:
  /// **'Invoke Prompt'**
  String get mcpAutoInvokePrompt;

  /// No description provided for @mcpAutoPromptNoArgs.
  ///
  /// In en, this message translates to:
  /// **'This Prompt takes no arguments'**
  String get mcpAutoPromptNoArgs;

  /// No description provided for @mcpAutoRequiredArg.
  ///
  /// In en, this message translates to:
  /// **'Fill in the required argument: $name'**
  String mcpAutoRequiredArg(String name);

  /// No description provided for @mcpAutoInvokingPrompt.
  ///
  /// In en, this message translates to:
  /// **'Invoking Prompt…'**
  String get mcpAutoInvokingPrompt;

  /// No description provided for @mcpAutoInvoke.
  ///
  /// In en, this message translates to:
  /// **'Invoke'**
  String get mcpAutoInvoke;

  /// No description provided for @mcpAutoNoResult.
  ///
  /// In en, this message translates to:
  /// **'No content returned'**
  String get mcpAutoNoResult;

  /// No description provided for @mcpAutoNoWorkflows.
  ///
  /// In en, this message translates to:
  /// **'No workflows'**
  String get mcpAutoNoWorkflows;

  /// No description provided for @mcpAutoNoWorkflowsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + to create a workflow
Chain multiple script nodes in order'**
  String get mcpAutoNoWorkflowsHint;

  /// No description provided for @mcpAutoUnnamedWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Unnamed workflow'**
  String get mcpAutoUnnamedWorkflow;

  /// No description provided for @mcpAutoNodesCount.
  ///
  /// In en, this message translates to:
  /// **'$count nodes'**
  String mcpAutoNodesCount(int count);

  /// No description provided for @mcpAutoDeleteWorkflowConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this workflow?'**
  String get mcpAutoDeleteWorkflowConfirm;

  /// No description provided for @mcpAutoWorkflowDeleted.
  ///
  /// In en, this message translates to:
  /// **'Workflow deleted'**
  String get mcpAutoWorkflowDeleted;

  /// No description provided for @mcpAutoNoNodes.
  ///
  /// In en, this message translates to:
  /// **'No nodes'**
  String get mcpAutoNoNodes;

  /// No description provided for @mcpAutoDependsOn.
  ///
  /// In en, this message translates to:
  /// **'Depends on: $deps'**
  String mcpAutoDependsOn(String deps);

  /// No description provided for @mcpAutoNoDeps.
  ///
  /// In en, this message translates to:
  /// **'No dependencies'**
  String get mcpAutoNoDeps;

  /// No description provided for @mcpAutoEditWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Edit workflow'**
  String get mcpAutoEditWorkflow;

  /// No description provided for @mcpAutoAddWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Add workflow'**
  String get mcpAutoAddWorkflow;

  /// No description provided for @mcpAutoWorkflowName.
  ///
  /// In en, this message translates to:
  /// **'Workflow name'**
  String get mcpAutoWorkflowName;

  /// No description provided for @mcpAutoNodes.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get mcpAutoNodes;

  /// No description provided for @mcpAutoTapAddNode.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add a node'**
  String get mcpAutoTapAddNode;

  /// No description provided for @mcpAutoTopoHint.
  ///
  /// In en, this message translates to:
  /// **'Nodes run in dependency order; dependencies appear as selectable chips.'**
  String get mcpAutoTopoHint;

  /// No description provided for @mcpAutoWorkflowNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a workflow name'**
  String get mcpAutoWorkflowNameRequired;

  /// No description provided for @mcpAutoWorkflowUpdated.
  ///
  /// In en, this message translates to:
  /// **'Workflow updated'**
  String get mcpAutoWorkflowUpdated;

  /// No description provided for @mcpAutoWorkflowAdded.
  ///
  /// In en, this message translates to:
  /// **'Workflow added'**
  String get mcpAutoWorkflowAdded;

  /// No description provided for @mcpAutoWorkflowNoNodes.
  ///
  /// In en, this message translates to:
  /// **'The workflow has no nodes'**
  String get mcpAutoWorkflowNoNodes;

  /// No description provided for @mcpAutoWorkflowStart.
  ///
  /// In en, this message translates to:
  /// **'Running workflow: $name'**
  String mcpAutoWorkflowStart(String name);

  /// No description provided for @mcpAutoWorkflowDone.
  ///
  /// In en, this message translates to:
  /// **'Workflow finished'**
  String get mcpAutoWorkflowDone;


  /// No description provided for @mcpConnSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'MCP Settings'**
  String get mcpConnSettingsTitle;

  /// No description provided for @mcpConnAutomationConfig.
  ///
  /// In en, this message translates to:
  /// **'Automation settings'**
  String get mcpConnAutomationConfig;

  /// No description provided for @mcpConnAllowLanHint.
  ///
  /// In en, this message translates to:
  /// **'Devices on the same network can connect to this device\\'s MCP service'**
  String get mcpConnAllowLanHint;

  /// No description provided for @mcpConnTokenAuth.
  ///
  /// In en, this message translates to:
  /// **'Access token authentication'**
  String get mcpConnTokenAuth;

  /// No description provided for @mcpConnTokenAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'Bearer token required (recommended)'**
  String get mcpConnTokenAuthRequired;

  /// No description provided for @mcpConnTokenAuthDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled: any device on the same network can read captured traffic!'**
  String get mcpConnTokenAuthDisabled;

  /// No description provided for @mcpConnKeepAlive.
  ///
  /// In en, this message translates to:
  /// **'Background keep-alive'**
  String get mcpConnKeepAlive;

  /// No description provided for @mcpConnKeepAliveDesc.
  ///
  /// In en, this message translates to:
  /// **'Add this app to the battery-optimization whitelist and lift background restrictions, so capture and the MCP service are less likely to be killed by the system (requires Shizuku / root / Dhizuku)'**
  String get mcpConnKeepAliveDesc;

  /// No description provided for @mcpConnStrictValidation.
  ///
  /// In en, this message translates to:
  /// **'Strict parameter validation'**
  String get mcpConnStrictValidation;

  /// No description provided for @mcpConnStrictValidationDesc.
  ///
  /// In en, this message translates to:
  /// **'Validate parameters against each tool\\'s declared inputSchema and report call errors early (takes effect immediately)'**
  String get mcpConnStrictValidationDesc;

  /// No description provided for @mcpConnTokenNotGenerated.
  ///
  /// In en, this message translates to:
  /// **'Not generated (created automatically once LAN access is enabled)'**
  String get mcpConnTokenNotGenerated;

  /// No description provided for @mcpConnTokenCopied.
  ///
  /// In en, this message translates to:
  /// **'Token copied'**
  String get mcpConnTokenCopied;

  /// No description provided for @mcpConnRegenerateTokenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Regenerate (the old token stops working immediately)'**
  String get mcpConnRegenerateTokenTooltip;

  /// No description provided for @mcpConnRegenerateTokenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to regenerate token: $error'**
  String mcpConnRegenerateTokenFailed(String error);

  /// No description provided for @mcpConnClientCommands.
  ///
  /// In en, this message translates to:
  /// **'AI client connection commands'**
  String get mcpConnClientCommands;

  /// No description provided for @mcpConnClientCommandsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Claude Code / Codex / curl / one-click scripts'**
  String get mcpConnClientCommandsSubtitle;

  /// No description provided for @mcpConnCurlSelfCheck.
  ///
  /// In en, this message translates to:
  /// **'curl self-check'**
  String get mcpConnCurlSelfCheck;

  /// No description provided for @mcpConnOneClickConfigShell.
  ///
  /// In en, this message translates to:
  /// **'One-click setup (shell)'**
  String get mcpConnOneClickConfigShell;

  /// No description provided for @mcpConnOneClickConfigPowershell.
  ///
  /// In en, this message translates to:
  /// **'One-click setup (PowerShell)'**
  String get mcpConnOneClickConfigPowershell;

  /// No description provided for @mcpConnNeedLanAccessForToken.
  ///
  /// In en, this message translates to:
  /// **'(Enable LAN access first to generate a token)'**
  String get mcpConnNeedLanAccessForToken;

  /// No description provided for @mcpConnAutoStart.
  ///
  /// In en, this message translates to:
  /// **'Auto-start'**
  String get mcpConnAutoStart;

  /// No description provided for @mcpConnServicePort.
  ///
  /// In en, this message translates to:
  /// **'Service port'**
  String get mcpConnServicePort;

  /// No description provided for @mcpConnConnectionInfo.
  ///
  /// In en, this message translates to:
  /// **'Connection info'**
  String get mcpConnConnectionInfo;

  /// No description provided for @mcpConnProtocolVersion.
  ///
  /// In en, this message translates to:
  /// **'MCP protocol version: $version (stateless core, compatible with the legacy handshake)'**
  String mcpConnProtocolVersion(String version);

  /// No description provided for @mcpConnDeviceIp.
  ///
  /// In en, this message translates to:
  /// **'Device IP'**
  String get mcpConnDeviceIp;

  /// No description provided for @mcpConnDeviceIpCopied.
  ///
  /// In en, this message translates to:
  /// **'Device IP copied'**
  String get mcpConnDeviceIpCopied;

  /// No description provided for @mcpConnApiUrl.
  ///
  /// In en, this message translates to:
  /// **'API URL (Streamable HTTP)'**
  String get mcpConnApiUrl;

  /// No description provided for @mcpConnApiUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'API URL copied'**
  String get mcpConnApiUrlCopied;

  /// No description provided for @mcpConnSseUrl.
  ///
  /// In en, this message translates to:
  /// **'SSE URL (legacy transport)'**
  String get mcpConnSseUrl;

  /// No description provided for @mcpConnSseUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'SSE URL copied'**
  String get mcpConnSseUrlCopied;

  /// No description provided for @mcpConnHealthCheck.
  ///
  /// In en, this message translates to:
  /// **'Health Check'**
  String get mcpConnHealthCheck;

  /// No description provided for @mcpConnHealthCheckUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'Health Check URL copied'**
  String get mcpConnHealthCheckUrlCopied;

  /// No description provided for @mcpConnFloatingBall.
  ///
  /// In en, this message translates to:
  /// **'Floating ball'**
  String get mcpConnFloatingBall;

  /// No description provided for @mcpConnFloatingBallDesc.
  ///
  /// In en, this message translates to:
  /// **'The desktop floating ball shows MCP status; tap it for a quick panel. The foreground service helps keep the app alive.'**
  String get mcpConnFloatingBallDesc;

  /// No description provided for @mcpConnFloatingBallColorDesc.
  ///
  /// In en, this message translates to:
  /// **'Color #$hex · Opacity $percent%'**
  String mcpConnFloatingBallColorDesc(String hex, int percent);

  /// No description provided for @mcpConnCustomFloatingBall.
  ///
  /// In en, this message translates to:
  /// **'Custom floating ball'**
  String get mcpConnCustomFloatingBall;

  /// No description provided for @mcpConnPresetColors.
  ///
  /// In en, this message translates to:
  /// **'Preset colors'**
  String get mcpConnPresetColors;

  /// No description provided for @mcpConnPresetM3Purple.
  ///
  /// In en, this message translates to:
  /// **'M3 Purple'**
  String get mcpConnPresetM3Purple;

  /// No description provided for @mcpConnPresetDeepSeaBlue.
  ///
  /// In en, this message translates to:
  /// **'Deep Sea Blue'**
  String get mcpConnPresetDeepSeaBlue;

  /// No description provided for @mcpConnPresetEmeraldGreen.
  ///
  /// In en, this message translates to:
  /// **'Emerald Green'**
  String get mcpConnPresetEmeraldGreen;

  /// No description provided for @mcpConnPresetCoralOrange.
  ///
  /// In en, this message translates to:
  /// **'Coral Orange'**
  String get mcpConnPresetCoralOrange;

  /// No description provided for @mcpConnPresetRoseRed.
  ///
  /// In en, this message translates to:
  /// **'Rose Red'**
  String get mcpConnPresetRoseRed;

  /// No description provided for @mcpConnPresetGraphiteBlack.
  ///
  /// In en, this message translates to:
  /// **'Graphite Black'**
  String get mcpConnPresetGraphiteBlack;

  /// No description provided for @mcpConnCustomColorRgb.
  ///
  /// In en, this message translates to:
  /// **'Custom color (RGB)'**
  String get mcpConnCustomColorRgb;

  /// No description provided for @mcpConnOpacityPercent.
  ///
  /// In en, this message translates to:
  /// **'Opacity $percent%'**
  String mcpConnOpacityPercent(int percent);

  /// No description provided for @mcpConnConfirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get mcpConnConfirm;

  /// No description provided for @mcpConnFloatingBallPermission.
  ///
  /// In en, this message translates to:
  /// **'Floating ball permission'**
  String get mcpConnFloatingBallPermission;

  /// No description provided for @mcpConnFloatingBallNeedOverlayPermission.
  ///
  /// In en, this message translates to:
  /// **'The floating ball needs "Display over other apps" permission. System settings has been opened for you; come back and turn it on again after granting it.'**
  String get mcpConnFloatingBallNeedOverlayPermission;

  /// No description provided for @mcpConnFloatingBallStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start the floating ball: $reason'**
  String mcpConnFloatingBallStartFailed(String reason);

  /// No description provided for @mcpConnFloatingBallStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop the floating ball: $reason'**
  String mcpConnFloatingBallStopFailed(String reason);

  /// No description provided for @mcpConnUnknownReason.
  ///
  /// In en, this message translates to:
  /// **'Unknown reason'**
  String get mcpConnUnknownReason;

  /// No description provided for @mcpConnFloatingBallStartedHint.
  ///
  /// In en, this message translates to:
  /// **'The floating ball is on. If you cannot see it on screen, check the system "Show floating windows" and the vendor "Background pop-up" permissions.'**
  String get mcpConnFloatingBallStartedHint;

  /// No description provided for @mcpConnFloatingBallCallFailed.
  ///
  /// In en, this message translates to:
  /// **'Floating ball call failed: $error'**
  String mcpConnFloatingBallCallFailed(String error);

  /// No description provided for @mcpConnOverlayGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted "Display over other apps"'**
  String get mcpConnOverlayGranted;

  /// No description provided for @mcpConnOverlayNotGranted.
  ///
  /// In en, this message translates to:
  /// **'Not granted — tap to open system settings and enable it, otherwise the floating ball cannot show'**
  String get mcpConnOverlayNotGranted;

  /// No description provided for @mcpConnEnableFloatingBall.
  ///
  /// In en, this message translates to:
  /// **'Enable floating ball'**
  String get mcpConnEnableFloatingBall;

  /// No description provided for @mcpConnFloatingBallEnabledDesc.
  ///
  /// In en, this message translates to:
  /// **'Show MCP status as a floating window to improve keep-alive'**
  String get mcpConnFloatingBallEnabledDesc;

  /// No description provided for @mcpConnFloatingBallPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Grant the floating ball permission above first'**
  String get mcpConnFloatingBallPermissionRequired;

  /// No description provided for @mcpConnAutoDock.
  ///
  /// In en, this message translates to:
  /// **'Auto-dock after 3 seconds idle'**
  String get mcpConnAutoDock;

  /// No description provided for @mcpConnAutoDockDesc.
  ///
  /// In en, this message translates to:
  /// **'The floating ball snaps to the screen edge so it does not block the view'**
  String get mcpConnAutoDockDesc;

  /// No description provided for @mcpConnCustomFloatingBallStyle.
  ///
  /// In en, this message translates to:
  /// **'Custom floating ball style'**
  String get mcpConnCustomFloatingBallStyle;

  /// No description provided for @mcpConnAiConfigGuide.
  ///
  /// In en, this message translates to:
  /// **'AI configuration guide'**
  String get mcpConnAiConfigGuide;

  /// No description provided for @mcpConnAiConfigGuideDesc.
  ///
  /// In en, this message translates to:
  /// **'Paste the configuration below into your AI client\\'s MCP config file and Cursor / Windsurf / Claude Desktop / Cherry Studio and other MCP-capable AI tools can read captured traffic and control ProxyPin. Make sure the phone and the computer are on the same LAN and the MCP service is enabled. The server supports both the latest stateless protocol (2026-07-28) and the legacy handshake protocol.'**
  String get mcpConnAiConfigGuideDesc;

  /// No description provided for @mcpConnAiConfigCopied.
  ///
  /// In en, this message translates to:
  /// **'AI configuration copied'**
  String get mcpConnAiConfigCopied;

  /// No description provided for @mcpConnControlMode.
  ///
  /// In en, this message translates to:
  /// **'Control mode'**
  String get mcpConnControlMode;

  /// No description provided for @mcpConnCurrentMode.
  ///
  /// In en, this message translates to:
  /// **'Current mode'**
  String get mcpConnCurrentMode;

  /// No description provided for @mcpConnAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get mcpConnAccessibility;

  /// No description provided for @mcpConnAccessibilityService.
  ///
  /// In en, this message translates to:
  /// **'Accessibility service'**
  String get mcpConnAccessibilityService;

  /// No description provided for @mcpConnRootPermission.
  ///
  /// In en, this message translates to:
  /// **'Root permission'**
  String get mcpConnRootPermission;

  /// No description provided for @mcpConnAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get mcpConnAvailable;

  /// No description provided for @mcpConnUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get mcpConnUnavailable;

  /// No description provided for @mcpConnNotGranted.
  ///
  /// In en, this message translates to:
  /// **'Not authorized'**
  String get mcpConnNotGranted;

  /// No description provided for @mcpConnNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'Not enabled'**
  String get mcpConnNotEnabled;

  /// No description provided for @mcpConnOpenAccessibilitySettings.
  ///
  /// In en, this message translates to:
  /// **'Open accessibility settings'**
  String get mcpConnOpenAccessibilitySettings;

  /// No description provided for @mcpConnShizukuGranted.
  ///
  /// In en, this message translates to:
  /// **'Shizuku authorized'**
  String get mcpConnShizukuGranted;

  /// No description provided for @mcpConnRequestShizuku.
  ///
  /// In en, this message translates to:
  /// **'Request Shizuku authorization'**
  String get mcpConnRequestShizuku;

  /// No description provided for @mcpConnShizukuAuthIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Authorization not completed: make sure Shizuku is running, then pick this app in the Shizuku app to authorize it; or choose “Allow” in the dialog'**
  String get mcpConnShizukuAuthIncomplete;

  /// No description provided for @mcpConnRootGranted.
  ///
  /// In en, this message translates to:
  /// **'Root authorized'**
  String get mcpConnRootGranted;

  /// No description provided for @mcpConnRequestRoot.
  ///
  /// In en, this message translates to:
  /// **'Request root authorization'**
  String get mcpConnRequestRoot;

  /// No description provided for @mcpConnRootAuthIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Authorization not completed: allow it in the Magisk/KernelSU dialog, or make sure the device is rooted'**
  String get mcpConnRootAuthIncomplete;

  /// No description provided for @mcpConnDhizukuGranted.
  ///
  /// In en, this message translates to:
  /// **'Dhizuku authorized'**
  String get mcpConnDhizukuGranted;

  /// No description provided for @mcpConnRequestDhizuku.
  ///
  /// In en, this message translates to:
  /// **'Request Dhizuku authorization'**
  String get mcpConnRequestDhizuku;

  /// No description provided for @mcpConnDhizukuAuthIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Authorization not completed: make sure Dhizuku is installed and Owner activation is finished'**
  String get mcpConnDhizukuAuthIncomplete;

  /// No description provided for @mcpConnAvailableTools.
  ///
  /// In en, this message translates to:
  /// **'Available tools'**
  String get mcpConnAvailableTools;

  /// No description provided for @mcpConnToolCount.
  ///
  /// In en, this message translates to:
  /// **'$count tools'**
  String mcpConnToolCount(int count);

  /// No description provided for @mcpConnDisabledToolsHint.
  ///
  /// In en, this message translates to:
  /// **'Disabled tools are hidden from the tool list and cannot be called by AI.'**
  String get mcpConnDisabledToolsHint;

  /// No description provided for @mcpConnToolSetConfig.
  ///
  /// In en, this message translates to:
  /// **'Change ProxyPin settings (system proxy, SSL capture toggle)'**
  String get mcpConnToolSetConfig;

  /// No description provided for @mcpConnToolExportHar.
  ///
  /// In en, this message translates to:
  /// **'Export capture records to a HAR file'**
  String get mcpConnToolExportHar;

  /// No description provided for @mcpConnToolImportHar.
  ///
  /// In en, this message translates to:
  /// **'Import a HAR file into capture records'**
  String get mcpConnToolImportHar;

  /// No description provided for @mcpConnToolSearchRequests.
  ///
  /// In en, this message translates to:
  /// **'Search requests by URL, method, status code, domain, etc.'**
  String get mcpConnToolSearchRequests;

  /// No description provided for @mcpConnToolGenerateCode.
  ///
  /// In en, this message translates to:
  /// **'Generate code from a request (curl, Python, Go, JavaScript, Node.js)'**
  String get mcpConnToolGenerateCode;

  /// No description provided for @mcpConnToolGetCurl.
  ///
  /// In en, this message translates to:
  /// **'Generate the cURL command for a request'**
  String get mcpConnToolGetCurl;

  /// No description provided for @mcpConnToolGetRecentRequests.
  ///
  /// In en, this message translates to:
  /// **'Get the list of recently captured requests'**
  String get mcpConnToolGetRecentRequests;

  /// No description provided for @mcpConnToolGetRequestDetails.
  ///
  /// In en, this message translates to:
  /// **'Get full details of a request (request/response headers and bodies, cookies)'**
  String get mcpConnToolGetRequestDetails;

  /// No description provided for @mcpConnToolStartProxy.
  ///
  /// In en, this message translates to:
  /// **'Start the proxy service'**
  String get mcpConnToolStartProxy;

  /// No description provided for @mcpConnToolStopProxy.
  ///
  /// In en, this message translates to:
  /// **'Stop the proxy service'**
  String get mcpConnToolStopProxy;

  /// No description provided for @mcpConnToolGetProxyStatus.
  ///
  /// In en, this message translates to:
  /// **'Query the proxy service status'**
  String get mcpConnToolGetProxyStatus;

  /// No description provided for @mcpConnToolClearRequests.
  ///
  /// In en, this message translates to:
  /// **'Clear capture records'**
  String get mcpConnToolClearRequests;

  /// No description provided for @mcpConnToolReplayRequest.
  ///
  /// In en, this message translates to:
  /// **'Replay a given request'**
  String get mcpConnToolReplayRequest;

  /// No description provided for @mcpConnToolUpdateScript.
  ///
  /// In en, this message translates to:
  /// **'Update the JS script injected into pages'**
  String get mcpConnToolUpdateScript;

  /// No description provided for @mcpConnToolGetScripts.
  ///
  /// In en, this message translates to:
  /// **'Get the list of configured JS scripts'**
  String get mcpConnToolGetScripts;

  /// No description provided for @mcpConnToolGetStatistics.
  ///
  /// In en, this message translates to:
  /// **'Get capture statistics'**
  String get mcpConnToolGetStatistics;

  /// No description provided for @mcpConnToolCompareRequests.
  ///
  /// In en, this message translates to:
  /// **'Compare the differences between two requests'**
  String get mcpConnToolCompareRequests;

  /// No description provided for @mcpConnToolFindSimilarRequests.
  ///
  /// In en, this message translates to:
  /// **'Find requests similar to a given request'**
  String get mcpConnToolFindSimilarRequests;

  /// No description provided for @mcpConnToolExtractApiEndpoints.
  ///
  /// In en, this message translates to:
  /// **'Extract aggregated API endpoint info from capture records'**
  String get mcpConnToolExtractApiEndpoints;

  /// No description provided for @mcpConnToolFindSensitiveData.
  ///
  /// In en, this message translates to:
  /// **'Search requests for sensitive data (passwords, keys, phone numbers, ID numbers, etc.)'**
  String get mcpConnToolFindSensitiveData;

  /// No description provided for @mcpConnToolGetCookieInfo.
  ///
  /// In en, this message translates to:
  /// **'Analyze a domain\\'s cookies (value, HttpOnly, Secure, expiry)'**
  String get mcpConnToolGetCookieInfo;

  /// No description provided for @mcpConnToolGetDomainSummary.
  ///
  /// In en, this message translates to:
  /// **'Summarize a domain\\'s traffic (methods, status codes, average duration, error count)'**
  String get mcpConnToolGetDomainSummary;

  /// No description provided for @mcpConnToolGetPendingIntercepts.
  ///
  /// In en, this message translates to:
  /// **'List pending requests/responses in the breakpoint queue'**
  String get mcpConnToolGetPendingIntercepts;

  /// No description provided for @mcpConnToolApproveIntercept.
  ///
  /// In en, this message translates to:
  /// **'Release a breakpoint intercept (you may edit the request first)'**
  String get mcpConnToolApproveIntercept;

  /// No description provided for @mcpConnToolRejectIntercept.
  ///
  /// In en, this message translates to:
  /// **'Reject a breakpoint intercept (abort the request or drop the response)'**
  String get mcpConnToolRejectIntercept;

  /// No description provided for @mcpConnToolToggleBreakpoint.
  ///
  /// In en, this message translates to:
  /// **'Enable or disable breakpoint interception'**
  String get mcpConnToolToggleBreakpoint;

  /// No description provided for @mcpConnToolAddWeakNetworkRule.
  ///
  /// In en, this message translates to:
  /// **'Add a weak-network rule (rate limit, delay, etc.)'**
  String get mcpConnToolAddWeakNetworkRule;

  /// No description provided for @mcpConnToolAddCustomNetworkProfile.
  ///
  /// In en, this message translates to:
  /// **'Add a custom network profile'**
  String get mcpConnToolAddCustomNetworkProfile;

  /// No description provided for @mcpConnToolListWeakNetworkRules.
  ///
  /// In en, this message translates to:
  /// **'List all weak-network rules'**
  String get mcpConnToolListWeakNetworkRules;

  /// No description provided for @mcpConnToolRemoveWeakNetworkRule.
  ///
  /// In en, this message translates to:
  /// **'Remove a weak-network rule'**
  String get mcpConnToolRemoveWeakNetworkRule;

  /// No description provided for @mcpConnToolToggleWeakNetwork.
  ///
  /// In en, this message translates to:
  /// **'Enable or disable weak-network simulation'**
  String get mcpConnToolToggleWeakNetwork;

  /// No description provided for @mcpConnToolListEnvironments.
  ///
  /// In en, this message translates to:
  /// **'List all environments'**
  String get mcpConnToolListEnvironments;

  /// No description provided for @mcpConnToolSetEnvironmentVariable.
  ///
  /// In en, this message translates to:
  /// **'Set an environment variable value'**
  String get mcpConnToolSetEnvironmentVariable;

  /// No description provided for @mcpConnToolCreateEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Create a new environment'**
  String get mcpConnToolCreateEnvironment;

  /// No description provided for @mcpConnToolSetActiveEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Switch the active environment'**
  String get mcpConnToolSetActiveEnvironment;

  /// No description provided for @mcpConnToolRemoveEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Delete a given environment'**
  String get mcpConnToolRemoveEnvironment;

  /// No description provided for @mcpConnToolToggleEnvironmentVariables.
  ///
  /// In en, this message translates to:
  /// **'Enable or disable environment variables'**
  String get mcpConnToolToggleEnvironmentVariables;

  /// No description provided for @mcpConnToolGetDeviceInfo.
  ///
  /// In en, this message translates to:
  /// **'Get device info (model, OS version, root status)'**
  String get mcpConnToolGetDeviceInfo;

  /// No description provided for @mcpConnToolGetCurrentActivity.
  ///
  /// In en, this message translates to:
  /// **'Get the current foreground activity'**
  String get mcpConnToolGetCurrentActivity;

  /// No description provided for @mcpConnToolDumpUi.
  ///
  /// In en, this message translates to:
  /// **'Export the UI hierarchy tree of the current screen'**
  String get mcpConnToolDumpUi;

  /// No description provided for @mcpConnToolTapScreen.
  ///
  /// In en, this message translates to:
  /// **'Simulate a tap at screen coordinates'**
  String get mcpConnToolTapScreen;

  /// No description provided for @mcpConnToolLongPress.
  ///
  /// In en, this message translates to:
  /// **'Simulate a long press at screen coordinates'**
  String get mcpConnToolLongPress;

  /// No description provided for @mcpConnToolSwipeScreen.
  ///
  /// In en, this message translates to:
  /// **'Simulate a screen swipe'**
  String get mcpConnToolSwipeScreen;

  /// No description provided for @mcpConnToolKeyEvent.
  ///
  /// In en, this message translates to:
  /// **'Send a key event (e.g. back or volume key)'**
  String get mcpConnToolKeyEvent;

  /// No description provided for @mcpConnToolInputText.
  ///
  /// In en, this message translates to:
  /// **'Type text into the current input field'**
  String get mcpConnToolInputText;

  /// No description provided for @mcpConnToolScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Capture the current screen'**
  String get mcpConnToolScreenshot;

  /// No description provided for @mcpConnToolOpenAccessibilitySettings.
  ///
  /// In en, this message translates to:
  /// **'Open the system accessibility settings page'**
  String get mcpConnToolOpenAccessibilitySettings;

  /// No description provided for @mcpConnToolShell.
  ///
  /// In en, this message translates to:
  /// **'Run a shell command (supports Root/Shizuku/Dhizuku modes)'**
  String get mcpConnToolShell;


  /// No description provided for @auditPlaintextHttpTitle.
  ///
  /// In en, this message translates to:
  /// **'Sensitive Data Sent Over Plaintext HTTP'**
  String get auditPlaintextHttpTitle;

  /// No description provided for @auditPlaintextHttpDetailUrl.
  ///
  /// In en, this message translates to:
  /// **'This request is sent over plaintext http:// and carries sensitive fields such as passwords / tokens in the URL query string, which a man-in-the-middle can read directly.'**
  String get auditPlaintextHttpDetailUrl;

  /// No description provided for @auditPlaintextHttpDetailBody.
  ///
  /// In en, this message translates to:
  /// **'This request is sent over plaintext http:// and carries sensitive fields such as passwords / tokens in the request body, which a man-in-the-middle can read directly.'**
  String get auditPlaintextHttpDetailBody;

  /// No description provided for @auditPlaintextHttpSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Use HTTPS; when HTTP is unavoidable, do not carry credentials directly in the URL or request body.'**
  String get auditPlaintextHttpSuggestion;

  /// No description provided for @auditPlaintextBodyTitle.
  ///
  /// In en, this message translates to:
  /// **'Request Body Sent Over Plaintext HTTP'**
  String get auditPlaintextBodyTitle;

  /// No description provided for @auditPlaintextBodyDetail.
  ///
  /// In en, this message translates to:
  /// **'This request uses http:// and has a request body, so the content is fully plaintext on the wire.'**
  String get auditPlaintextBodyDetail;

  /// No description provided for @auditPlaintextBodySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Enforce HTTPS for endpoints that handle login, payment or privacy.'**
  String get auditPlaintextBodySuggestion;

  /// No description provided for @auditUrlSecretTitle.
  ///
  /// In en, this message translates to:
  /// **'Sensitive Parameters in the URL'**
  String get auditUrlSecretTitle;

  /// No description provided for @auditUrlSecretDetail.
  ///
  /// In en, this message translates to:
  /// **'Query parameters $names look like credentials / keys. URLs are written into browser history, proxy and server logs.'**
  String auditUrlSecretDetail(String names);

  /// No description provided for @auditUrlSecretSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Move sensitive parameters into the request body or headers (for example Authorization).'**
  String get auditUrlSecretSuggestion;

  /// No description provided for @auditPasswordBodyTitle.
  ///
  /// In en, this message translates to:
  /// **'Password Submitted in a Plaintext Body'**
  String get auditPasswordBodyTitle;

  /// No description provided for @auditPasswordBodyDetail.
  ///
  /// In en, this message translates to:
  /// **'The request body contains fields such as password / pwd with plaintext values.'**
  String get auditPasswordBodyDetail;

  /// No description provided for @auditPasswordBodySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Keep the whole path on HTTPS and make sure the server never echoes or logs passwords.'**
  String get auditPasswordBodySuggestion;

  /// No description provided for @auditCookieFlagTitle.
  ///
  /// In en, this message translates to:
  /// **'Cookie Missing Security Attributes'**
  String get auditCookieFlagTitle;

  /// No description provided for @auditCookieFlagDetail.
  ///
  /// In en, this message translates to:
  /// **'Set-Cookie "$name" is missing $missing, so it can be read by scripts or transmitted in cleartext.'**
  String auditCookieFlagDetail(String name, String missing);

  /// No description provided for @auditCookieFlagSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Add Secure and HttpOnly to session cookies, and set SameSite=Lax/Strict as needed.'**
  String get auditCookieFlagSuggestion;

  /// No description provided for @auditMissingHeadersTitle.
  ///
  /// In en, this message translates to:
  /// **'HTML Response Missing Security Headers'**
  String get auditMissingHeadersTitle;

  /// No description provided for @auditMissingHeadersDetail.
  ///
  /// In en, this message translates to:
  /// **'Missing $missing; the browser has no extra constraint against content sniffing and script injection.'**
  String auditMissingHeadersDetail(String missing);

  /// No description provided for @auditMissingHeadersSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Add security response headers such as nosniff and CSP as needed.'**
  String get auditMissingHeadersSuggestion;

  /// No description provided for @auditFingerprintTitle.
  ///
  /// In en, this message translates to:
  /// **'Response Exposes Server Fingerprint'**
  String get auditFingerprintTitle;

  /// No description provided for @auditFingerprintDetail.
  ///
  /// In en, this message translates to:
  /// **'$header: $value, which helps an attacker pick known vulnerabilities.'**
  String auditFingerprintDetail(String header, String value);

  /// No description provided for @auditFingerprintSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Hide or generalize version information at the gateway.'**
  String get auditFingerprintSuggestion;

  /// No description provided for @auditPrivateKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Response Body May Contain a Private Key'**
  String get auditPrivateKeyTitle;

  /// No description provided for @auditPrivateKeyDetail.
  ///
  /// In en, this message translates to:
  /// **'A PEM private key marker appears in the response; if it is a real key, this is a severe leak.'**
  String get auditPrivateKeyDetail;

  /// No description provided for @auditPrivateKeySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Rotate the key immediately and make sure the server never sends private keys to clients.'**
  String get auditPrivateKeySuggestion;

  /// No description provided for @auditSecretTitle.
  ///
  /// In en, this message translates to:
  /// **'Response Body Returns Secret Fields in Plaintext'**
  String get auditSecretTitle;

  /// No description provided for @auditSecretDetail.
  ///
  /// In en, this message translates to:
  /// **'Fields such as $names are returned in plaintext.'**
  String auditSecretDetail(String names);

  /// No description provided for @auditSecretSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Return the minimum set of fields; key material should never be sent to clients.'**
  String get auditSecretSuggestion;

  /// No description provided for @auditPiiTitle.
  ///
  /// In en, this message translates to:
  /// **'Response Body Contains Personal Information'**
  String get auditPiiTitle;

  /// No description provided for @auditPiiDetail.
  ///
  /// In en, this message translates to:
  /// **'Fields such as $names carry personal data such as ID numbers / phone numbers.'**
  String auditPiiDetail(String names);

  /// No description provided for @auditPiiSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Mask personal data or return it on a minimal-necessary basis, and comply with data protection requirements.'**
  String get auditPiiSuggestion;

  /// No description provided for @auditErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Error Response Leaks Internal Information'**
  String get auditErrorTitle;

  /// No description provided for @auditErrorDetail.
  ///
  /// In en, this message translates to:
  /// **'Debug / stack trace signatures ($trace) appear in the response, which may expose the framework, paths or database structure.'**
  String auditErrorDetail(String trace);

  /// No description provided for @auditErrorSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Disable detailed errors in production and return a generic error message.'**
  String get auditErrorSuggestion;

  /// No description provided for @auditCorsTitle.
  ///
  /// In en, this message translates to:
  /// **'CORS Allows Any Origin with Credentials'**
  String get auditCorsTitle;

  /// No description provided for @auditCorsDetail.
  ///
  /// In en, this message translates to:
  /// **'Access-Control-Allow-Origin is * while Allow-Credentials is true, so the risk of cross-site credential reads is high.'**
  String get auditCorsDetail;

  /// No description provided for @auditCorsSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Restrict allowed origins to a fixed allowlist and avoid * together with Allow-Credentials.'**
  String get auditCorsSuggestion;

  /// No description provided for @auditJwtNoneTitle.
  ///
  /// In en, this message translates to:
  /// **'JWT Uses alg=none (Unsigned)'**
  String get auditJwtNoneTitle;

  /// No description provided for @auditJwtNoneDetail.
  ///
  /// In en, this message translates to:
  /// **'The token declares algorithm none, so anyone can tamper with the payload and it cannot be verified.'**
  String get auditJwtNoneDetail;

  /// No description provided for @auditJwtNoneSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Enforce signature algorithm validation on the server and reject alg=none.'**
  String get auditJwtNoneSuggestion;

  /// No description provided for @auditJwtExpiryTitle.
  ///
  /// In en, this message translates to:
  /// **'JWT Has No Expiry'**
  String get auditJwtExpiryTitle;

  /// No description provided for @auditJwtExpiryDetail.
  ///
  /// In en, this message translates to:
  /// **'The token payload has no exp field, so it stays valid forever after being issued.'**
  String get auditJwtExpiryDetail;

  /// No description provided for @auditJwtExpirySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Set a reasonable expiry for tokens and support refresh.'**
  String get auditJwtExpirySuggestion;

  /// No description provided for @auditHttp10Title.
  ///
  /// In en, this message translates to:
  /// **'Uses Outdated HTTP/1.0'**
  String get auditHttp10Title;

  /// No description provided for @auditHttp10Detail.
  ///
  /// In en, this message translates to:
  /// **'This connection uses HTTP/1.0, whose connection reuse and caching strategy is outdated.'**
  String get auditHttp10Detail;

  /// No description provided for @auditHttp10Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to HTTP/1.1 or HTTP/2.'**
  String get auditHttp10Suggestion;

  /// No description provided for @auditSqlTitle.
  ///
  /// In en, this message translates to:
  /// **'Possible SQL Injection Trace (Database Error Echoed)'**
  String get auditSqlTitle;

  /// No description provided for @auditSqlDetail.
  ///
  /// In en, this message translates to:
  /// **'The response contains a $signature database error signature, which means this endpoint echoes SQL errors back to the caller; if client-controlled parameters triggered it, there is a SQL injection risk.'**
  String auditSqlDetail(String signature);

  /// No description provided for @auditSqlSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Use parameterized queries / prepared statements and never concatenate SQL; disable detailed database errors in production and return a generic message. (Passive detection: based only on the response characteristics of captured traffic; no probe request was sent.)'**
  String get auditSqlSuggestion;

  /// No description provided for @auditXssTitle.
  ///
  /// In en, this message translates to:
  /// **'Possible XSS Reflection Trace (Unencoded Parameters Echoed in HTML)'**
  String get auditXssTitle;

  /// No description provided for @auditXssDetail.
  ///
  /// In en, this message translates to:
  /// **'The response echoes request parameter values verbatim into HTML without HTML entity encoding, and the echoed content contains special characters such as $meta; if an attacker can control that value, the browser may parse it as tags or script.'**
  String auditXssDetail(String meta);

  /// No description provided for @auditXssSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Encode according to the output context (HTML entity encoding) and pair the page with CSP; do not concatenate request parameters into HTML. (Passive detection: based only on the response characteristics of captured traffic; no probe request was sent.)'**
  String get auditXssSuggestion;

  /// No description provided for @auditCustomHitDetail.
  ///
  /// In en, this message translates to:
  /// **'Matched custom rule "$name" ($describe).'**
  String auditCustomHitDetail(String name, String describe);

  /// No description provided for @auditCustomHitSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Confirm against your business security requirements whether this content should appear.'**
  String get auditCustomHitSuggestion;

  /// No description provided for @auditSecretPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Private key'**
  String get auditSecretPrivateKey;

  /// No description provided for @auditPiiIdCard.
  ///
  /// In en, this message translates to:
  /// **'ID number'**
  String get auditPiiIdCard;

  /// No description provided for @auditPiiPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get auditPiiPhone;

  /// No description provided for @auditRuleDescribe.
  ///
  /// In en, this message translates to:
  /// **'Scope: $target; Match: $match'**
  String auditRuleDescribe(String target, String match);

  /// No description provided for @auditTargetUrl.
  ///
  /// In en, this message translates to:
  /// **'Request URL'**
  String get auditTargetUrl;

  /// No description provided for @auditTargetRequestHeader.
  ///
  /// In en, this message translates to:
  /// **'Request headers'**
  String get auditTargetRequestHeader;

  /// No description provided for @auditTargetRequestBody.
  ///
  /// In en, this message translates to:
  /// **'Request body'**
  String get auditTargetRequestBody;

  /// No description provided for @auditTargetResponseHeader.
  ///
  /// In en, this message translates to:
  /// **'Response headers'**
  String get auditTargetResponseHeader;

  /// No description provided for @auditTargetResponseBody.
  ///
  /// In en, this message translates to:
  /// **'Response body'**
  String get auditTargetResponseBody;

  /// No description provided for @auditTargetAny.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get auditTargetAny;

  /// No description provided for @auditMatchKeyword.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get auditMatchKeyword;

  /// No description provided for @auditMatchRegex.
  ///
  /// In en, this message translates to:
  /// **'Regex'**
  String get auditMatchRegex;

  /// No description provided for @diagSummaryOk.
  ///
  /// In en, this message translates to:
  /// **'Capture path is basically ready'**
  String get diagSummaryOk;

  /// No description provided for @diagSummaryIssues.
  ///
  /// In en, this message translates to:
  /// **'Problems that affect capture were detected; see the error items in items'**
  String get diagSummaryIssues;

  /// No description provided for @diagSuggestStartProxy.
  ///
  /// In en, this message translates to:
  /// **'Start the capture service first (call the start_proxy tool, or have the user tap Start Capture in the UI)'**
  String get diagSuggestStartProxy;

  /// No description provided for @diagSuggestInstallCert.
  ///
  /// In en, this message translates to:
  /// **'Install and trust the root certificate: without HTTPS trust you will see batches of handshake failures (the exclamation-mark packets in the list)'**
  String get diagSuggestInstallCert;

  /// No description provided for @diagSuggestSystemProxy.
  ///
  /// In en, this message translates to:
  /// **'The system proxy does not point to this app: have the user enable the system proxy in Preferences, or check whether another proxy tool has taken it over'**
  String get diagSuggestSystemProxy;

  /// No description provided for @diagSuggestPinning.
  ///
  /// In en, this message translates to:
  /// **'Domains that look like they pin certificates: such apps need runtime intervention on the device to decrypt, and the common approach is a hook framework (for example LSPosed with a module like TrustMeAlready). Note that this interferes with the target app and should only be done on your own device and within the scope you are authorized for'**
  String get diagSuggestPinning;

  /// No description provided for @diagSuggestNoTraffic.
  ///
  /// In en, this message translates to:
  /// **'No new traffic right now: trigger a request in the app or browser being captured, then let the AI read the session list'**
  String get diagSuggestNoTraffic;

  /// No description provided for @diagSuggestChecklist.
  ///
  /// In en, this message translates to:
  /// **'If everything above looks fine but you still capture nothing, check these categories: ① the target uses QUIC/HTTP3 (enable Block QUIC on the phone, disable QUIC in the browser); ② Flutter apps (Dart ships its own root CA list and does not read the system CA); ③ the app enables certificate pinning (SSL Pinning) - matched if an SSL Certificate Pinning (suspected) item appears above; ④ processes with their own network stack on Windows (need Enhanced Windows Takeover or a TUN tool); ⑤ Mac App Store sandboxed apps (need Network Extension/TUN; unsigned builds from this repository cannot take over)'**
  String get diagSuggestChecklist;

  /// No description provided for @diagItemProxyService.
  ///
  /// In en, this message translates to:
  /// **'Proxy Service'**
  String get diagItemProxyService;

  /// No description provided for @diagProxyListening.
  ///
  /// In en, this message translates to:
  /// **'Listening on 127.0.0.1:$port'**
  String diagProxyListening(int port);

  /// No description provided for @diagProxyNotRunning.
  ///
  /// In en, this message translates to:
  /// **'Not running, so no traffic can be captured. Tap Start Capture first'**
  String get diagProxyNotRunning;

  /// No description provided for @diagItemSystemProxy.
  ///
  /// In en, this message translates to:
  /// **'System Proxy'**
  String get diagItemSystemProxy;

  /// No description provided for @diagSystemProxyMatched.
  ///
  /// In en, this message translates to:
  /// **'Points to this app at $host:$port'**
  String diagSystemProxyMatched(String host, int port);

  /// No description provided for @diagSystemProxyOff.
  ///
  /// In en, this message translates to:
  /// **'The system proxy is off, so app traffic will not go through this tool'**
  String get diagSystemProxyOff;

  /// No description provided for @diagSystemProxyMismatch.
  ///
  /// In en, this message translates to:
  /// **'Points to $host:$port, which does not match this app port $expected (maybe taken over by another proxy tool, or left over from an abnormal exit)'**
  String diagSystemProxyMismatch(String host, int port, int expected);

  /// No description provided for @diagItemTrafficEntry.
  ///
  /// In en, this message translates to:
  /// **'Traffic Entry'**
  String get diagItemTrafficEntry;

  /// No description provided for @diagMobileVpnEntry.
  ///
  /// In en, this message translates to:
  /// **'On mobile, the VPN tunnel handles IP-layer traffic (no system proxy needed)'**
  String get diagMobileVpnEntry;

  /// No description provided for @diagCaInSystemStore.
  ///
  /// In en, this message translates to:
  /// **'Already in the system trust store'**
  String get diagCaInSystemStore;

  /// No description provided for @diagCaUserStore.
  ///
  /// In en, this message translates to:
  /// **'Only in the user certificate store: since Android 7 apps do not trust user certificates by default, you may see "certificate installed but HTTPS cannot be captured or reports an error". To take effect for all apps it must be installed into the system certificate directory with root (on Android 14+ that is /apex/com.android.conscrypt/cacerts), or configure network_security_config for the target app'**
  String get diagCaUserStore;

  /// No description provided for @diagCaInstalledUnknown.
  ///
  /// In en, this message translates to:
  /// **'Installed (cannot distinguish the system store from the user store)'**
  String get diagCaInstalledUnknown;

  /// No description provided for @diagCaMissingAndroid.
  ///
  /// In en, this message translates to:
  /// **'Root certificate not detected: go to HTTPS Certificate -> Install Root Certificate and follow the guide; choose CA certificate rather than VPN and app certificate during installation'**
  String get diagCaMissingAndroid;

  /// No description provided for @diagCaMissingDesktop.
  ///
  /// In en, this message translates to:
  /// **'Root certificate not detected; HTTPS will fail the handshake (seen as batches of exclamation-mark packets in the list)'**
  String get diagCaMissingDesktop;

  /// No description provided for @diagItemCaRoot.
  ///
  /// In en, this message translates to:
  /// **'CA Root Certificate'**
  String get diagItemCaRoot;

  /// No description provided for @diagCaDesktopHint.
  ///
  /// In en, this message translates to:
  /// **'On desktop, confirm in the Certificate page that the root certificate is installed into the system trusted roots'**
  String get diagCaDesktopHint;

  /// No description provided for @diagReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Read failed: $error'**
  String diagReadFailed(String error);

  /// No description provided for @diagItemSslPinning.
  ///
  /// In en, this message translates to:
  /// **'SSL Certificate Pinning (suspected)'**
  String get diagItemSslPinning;

  /// No description provided for @diagSslPinningDetail.
  ///
  /// In en, this message translates to:
  /// **'The CA certificate is ready, but $count domains only established a TLS tunnel and their content is never readable: $sample. This usually means the peer enabled certificate pinning (SSL Pinning), or ships its own root CA list and does not read the system CA. Note that these apps are not offline: they rejected the certificate of this tool and therefore closed the connection.'**
  String diagSslPinningDetail(int count, String sample);

  /// No description provided for @diagItemWinTakeover.
  ///
  /// In en, this message translates to:
  /// **'Enhanced Windows Takeover'**
  String get diagItemWinTakeover;

  /// No description provided for @diagWinTakeoverOn.
  ///
  /// In en, this message translates to:
  /// **'On: the WinHTTP service and CLI tools (curl/git/node) also go through the proxy'**
  String get diagWinTakeoverOn;

  /// No description provided for @diagWinTakeoverOff.
  ///
  /// In en, this message translates to:
  /// **'Off: apps with their own network stack, the WinHTTP service and CLI tools may not be captured. Enable it in Preferences -> Windows Takeover (the WinHTTP part requires administrator rights)'**
  String get diagWinTakeoverOff;

  /// No description provided for @diagItemRecentTraffic.
  ///
  /// In en, this message translates to:
  /// **'Recent Traffic'**
  String get diagItemRecentTraffic;

  /// No description provided for @diagNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests captured in this session yet'**
  String get diagNoRequests;

  /// No description provided for @diagTrafficFresh.
  ///
  /// In en, this message translates to:
  /// **'$count requests, latest $ago seconds ago'**
  String diagTrafficFresh(int count, int ago);

  /// No description provided for @diagTrafficStale.
  ///
  /// In en, this message translates to:
  /// **'$count requests, latest $ago seconds ago (no new traffic coming in)'**
  String diagTrafficStale(int count, int ago);

  /// No description provided for @diagItemExtensionMemory.
  ///
  /// In en, this message translates to:
  /// **'Extension Memory'**
  String get diagItemExtensionMemory;

  /// No description provided for @diagExtMemUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available (the extension process cannot be read while the VPN is stopped)'**
  String get diagExtMemUnavailable;

  /// No description provided for @diagExtMemDetail.
  ///
  /// In en, this message translates to:
  /// **'Current $rss MB, peak $peak MB, $connections connections, $buffered MB buffered'**
  String diagExtMemDetail(String rss, String peak, String connections, String buffered);

  /// No description provided for @diagExtMemNearLimit.
  ///
  /// In en, this message translates to:
  /// **' (approaching the extension memory limit; consider reducing concurrency or lowering the buffered-send cap)'**
  String get diagExtMemNearLimit;


  /// No description provided for @auditPageVerifyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Active verification (one request per captured domain, checking security headers)'**
  String get auditPageVerifyTooltip;

  /// No description provided for @auditPageNoVerifiableHosts.
  ///
  /// In en, this message translates to:
  /// **'No verifiable domains captured yet'**
  String get auditPageNoVerifiableHosts;

  /// No description provided for @auditPageVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Active verification'**
  String get auditPageVerifyTitle;

  /// No description provided for @auditPageVerifyIntro.
  ///
  /// In en, this message translates to:
  /// **'It sends one GET each to the domains below that **already appeared in the captured traffic**, looking only at the security response headers:'**
  String get auditPageVerifyIntro;

  /// No description provided for @auditPageVerifyScope.
  ///
  /// In en, this message translates to:
  /// **'$hosts domains in total, sent one after another with a \$$delayms gap, up to $max. No port scanning, no payloads.'**
  String auditPageVerifyScope(int hosts, int delay, int max);

  /// No description provided for @auditPageVerifyAuthz.
  ///
  /// In en, this message translates to:
  /// **'Only do this for targets you own or are authorized to test.'**
  String get auditPageVerifyAuthz;

  /// No description provided for @auditPageVerifyStart.
  ///
  /// In en, this message translates to:
  /// **'Start verification'**
  String get auditPageVerifyStart;

  /// No description provided for @auditPageVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification failed: $error'**
  String auditPageVerifyFailed(String error);

  /// No description provided for @auditPageVerifyResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification results'**
  String get auditPageVerifyResultTitle;

  /// No description provided for @auditPageVerifyResultIntro.
  ///
  /// In en, this message translates to:
  /// **'This only checked whether the security response headers below are present. Missing does not mean a vulnerability, but the server configuration is worth a look.'**
  String get auditPageVerifyResultIntro;

  /// No description provided for @auditPageVerifyHostFailed.
  ///
  /// In en, this message translates to:
  /// **'$host — verification failed: $error'**
  String auditPageVerifyHostFailed(String host, String error);

  /// No description provided for @auditPageVerifyHeadersAllPresent.
  ///
  /// In en, this message translates to:
  /// **'All of these response headers are present'**
  String get auditPageVerifyHeadersAllPresent;

  /// No description provided for @auditPageVerifyHeaderMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing $name — $desc'**
  String auditPageVerifyHeaderMissing(String name, String desc);

  /// No description provided for @diagPageRerun.
  ///
  /// In en, this message translates to:
  /// **'Re-run'**
  String get diagPageRerun;

  /// No description provided for @diagPageTip.
  ///
  /// In en, this message translates to:
  /// **'Checks whether the local capture path works. Read-only detection; it never changes your system settings. The same conclusion can be handed to AI via the MCP tool diagnose_capture.'**
  String get diagPageTip;

  /// No description provided for @diagPageNextSteps.
  ///
  /// In en, this message translates to:
  /// **'Start here'**
  String get diagPageNextSteps;

  /// No description provided for @diagPageCauseQuicTitle.
  ///
  /// In en, this message translates to:
  /// **'Targets that use QUIC / HTTP3'**
  String get diagPageCauseQuicTitle;

  /// No description provided for @diagPageCauseQuicDesc.
  ///
  /// In en, this message translates to:
  /// **'Enable "Block QUIC" on the phone so the app falls back to TCP; on desktop browsers, disable QUIC in chrome://flags and retry'**
  String get diagPageCauseQuicDesc;

  /// No description provided for @diagPageCauseFlutterTitle.
  ///
  /// In en, this message translates to:
  /// **'Flutter apps'**
  String get diagPageCauseFlutterTitle;

  /// No description provided for @diagPageCauseFlutterDesc.
  ///
  /// In en, this message translates to:
  /// **'Dart ships its own root CA list and does not read the system CA, so HTTPS stays unreadable even with a certificate installed. Trust it inside the app, or capture its network library calls instead'**
  String get diagPageCauseFlutterDesc;

  /// No description provided for @diagPageCausePinningTitle.
  ///
  /// In en, this message translates to:
  /// **'Apps with certificate pinning (SSL Pinning) enabled'**
  String get diagPageCausePinningTitle;

  /// No description provided for @diagPageCausePinningDesc.
  ///
  /// In en, this message translates to:
  /// **'The app has a certificate fingerprint built in, so MITM is rejected and you see waves of handshake failures (exclamation-mark packets)'**
  String get diagPageCausePinningDesc;

  /// No description provided for @diagPageCauseWinStackTitle.
  ///
  /// In en, this message translates to:
  /// **'Processes on Windows with their own network stack'**
  String get diagPageCauseWinStackTitle;

  /// No description provided for @diagPageCauseWinStackDesc.
  ///
  /// In en, this message translates to:
  /// **'The system proxy cannot reach them. Use "Preferences → Enhanced Windows Takeover"; if that still fails, put ProxyPin behind a TUN-capable tool'**
  String get diagPageCauseWinStackDesc;

  /// No description provided for @diagPageCauseMasTitle.
  ///
  /// In en, this message translates to:
  /// **'Apps from the Mac App Store'**
  String get diagPageCauseMasTitle;

  /// No description provided for @diagPageCauseMasDesc.
  ///
  /// In en, this message translates to:
  /// **'Sandboxed and strictly signed, the system proxy is ineffective and Network Extension/TUN is required (unsigned builds from this repository cannot do it)'**
  String get diagPageCauseMasDesc;

  /// No description provided for @diagPageCauseProxyIgnoredTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy changed but the app ignores it'**
  String get diagPageCauseProxyIgnoredTitle;

  /// No description provided for @diagPageCauseProxyIgnoredDesc.
  ///
  /// In en, this message translates to:
  /// **'Switch to the app\\'s own proxy settings, or take over uniformly with a TUN-capable tool'**
  String get diagPageCauseProxyIgnoredDesc;

  /// No description provided for @diagPageCommonCausesTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing captured? Match your case below'**
  String get diagPageCommonCausesTitle;


  /// No description provided for @mcpConnDeskClientWizard.
  ///
  /// In en, this message translates to:
  /// **'Client connection wizard (Claude Code / Codex / Cursor)'**
  String get mcpConnDeskClientWizard;

  /// No description provided for @mcpConnDeskPortConfig.
  ///
  /// In en, this message translates to:
  /// **'Port settings'**
  String get mcpConnDeskPortConfig;

  /// No description provided for @mcpConnDeskServicePort.
  ///
  /// In en, this message translates to:
  /// **'MCP service port'**
  String get mcpConnDeskServicePort;

  /// No description provided for @mcpConnDeskIpAddress.
  ///
  /// In en, this message translates to:
  /// **'IP Address'**
  String get mcpConnDeskIpAddress;

  /// No description provided for @mcpConnDeskAiConfigHint.
  ///
  /// In en, this message translates to:
  /// **'Add the following configuration to your AI tool (such as Cursor, Windsurf, etc.):'**
  String get mcpConnDeskAiConfigHint;

  /// No description provided for @mcpConnDeskConfigCopied.
  ///
  /// In en, this message translates to:
  /// **'Configuration copied'**
  String get mcpConnDeskConfigCopied;

  /// No description provided for @mcpConnDeskCopyConfig.
  ///
  /// In en, this message translates to:
  /// **'Copy config'**
  String get mcpConnDeskCopyConfig;

  /// No description provided for @mcpConnDeskControlModeDesc.
  ///
  /// In en, this message translates to:
  /// **'ProxyPin MCP supports two connection methods:'**
  String get mcpConnDeskControlModeDesc;

  /// No description provided for @mcpConnDeskModeMcpTitle.
  ///
  /// In en, this message translates to:
  /// **'MCP (recommended)'**
  String get mcpConnDeskModeMcpTitle;

  /// No description provided for @mcpConnDeskModeMcpDesc.
  ///
  /// In en, this message translates to:
  /// **'Standard MCP protocol with full features'**
  String get mcpConnDeskModeMcpDesc;

  /// No description provided for @mcpConnDeskModeSseDesc.
  ///
  /// In en, this message translates to:
  /// **'Server-Sent Events, compatible with legacy clients'**
  String get mcpConnDeskModeSseDesc;


  /// No description provided for @prefSplashTitle.
  ///
  /// In en, this message translates to:
  /// **'Splash Screen'**
  String get prefSplashTitle;

  /// No description provided for @prefSplashDesc.
  ///
  /// In en, this message translates to:
  /// **'Uses the system splash screen by default; you can switch to a custom branded page'**
  String get prefSplashDesc;

  /// No description provided for @prefSplashBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get prefSplashBackground;

  /// No description provided for @prefSplashBgOff.
  ///
  /// In en, this message translates to:
  /// **'Original splash (default)'**
  String get prefSplashBgOff;

  /// No description provided for @prefSplashBgGradient.
  ///
  /// In en, this message translates to:
  /// **'Gradient branded page'**
  String get prefSplashBgGradient;

  /// No description provided for @prefSplashBgCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom image'**
  String get prefSplashBgCustom;

  /// No description provided for @prefSplashBgTransparent.
  ///
  /// In en, this message translates to:
  /// **'Follow theme (recommended)'**
  String get prefSplashBgTransparent;

  /// No description provided for @prefSplashDuration.
  ///
  /// In en, this message translates to:
  /// **'Display duration'**
  String get prefSplashDuration;

  /// No description provided for @prefSplashDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'$seconds s'**
  String prefSplashDurationSeconds(String seconds);

  /// No description provided for @prefSplashDurationFixed.
  ///
  /// In en, this message translates to:
  /// **'The original splash screen is a system screen and does not support a custom duration'**
  String get prefSplashDurationFixed;

  /// No description provided for @prefSplashNotSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get prefSplashNotSelected;

  /// No description provided for @prefSplashSelectedTapChange.
  ///
  /// In en, this message translates to:
  /// **'Set, tap to change'**
  String get prefSplashSelectedTapChange;

  /// No description provided for @prefSplashSubtitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom caption'**
  String get prefSplashSubtitleLabel;

  /// No description provided for @prefSplashSubtitleDefault.
  ///
  /// In en, this message translates to:
  /// **'Shows version info by default'**
  String get prefSplashSubtitleDefault;

  /// No description provided for @prefSplashSubtitleUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The original splash screen does not support a custom caption; switch to gradient/transparent to enable it'**
  String get prefSplashSubtitleUnsupported;

  /// No description provided for @prefSplashSubtitleField.
  ///
  /// In en, this message translates to:
  /// **'Caption text'**
  String get prefSplashSubtitleField;

  /// No description provided for @prefSplashSubtitleHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to restore the default (version info)'**
  String get prefSplashSubtitleHint;

  /// No description provided for @prefMtls.
  ///
  /// In en, this message translates to:
  /// **'Mutual TLS (mTLS)'**
  String get prefMtls;

  /// No description provided for @prefMtlsChainLabel.
  ///
  /// In en, this message translates to:
  /// **'Client certificate chain (PEM)'**
  String get prefMtlsChainLabel;

  /// No description provided for @prefMtlsKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Client private key (PEM, unencrypted)'**
  String get prefMtlsKeyLabel;

  /// No description provided for @prefMtlsHint.
  ///
  /// In en, this message translates to:
  /// **'The certificate chain contains -----BEGIN CERTIFICATE-----, and the private key contains -----BEGIN PRIVATE KEY----- (encrypted keys are not supported). Applies to newly established HTTPS connections after configuration.'**
  String get prefMtlsHint;

  /// No description provided for @prefMtlsSelectBoth.
  ///
  /// In en, this message translates to:
  /// **'Select the certificate chain and private key files first'**
  String get prefMtlsSelectBoth;

  /// No description provided for @prefMtlsChainInvalid.
  ///
  /// In en, this message translates to:
  /// **'Incorrect certificate chain format (PEM required)'**
  String get prefMtlsChainInvalid;

  /// No description provided for @prefMtlsKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Incorrect private key format (unencrypted PEM required)'**
  String get prefMtlsKeyInvalid;

  /// No description provided for @prefMtlsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load the certificate; check the file contents'**
  String get prefMtlsLoadFailed;

  /// No description provided for @prefMtlsEnabled.
  ///
  /// In en, this message translates to:
  /// **'mTLS enabled'**
  String get prefMtlsEnabled;

  /// No description provided for @prefRootDenied.
  ///
  /// In en, this message translates to:
  /// **'Root permission not granted; system-level fallback cannot run'**
  String get prefRootDenied;

  /// No description provided for @prefSysFallbackOn.
  ///
  /// In en, this message translates to:
  /// **'System-level fallback enabled: UDP:443 will be dropped (stops working after a system reboot)'**
  String get prefSysFallbackOn;

  /// No description provided for @prefSysFallbackOff.
  ///
  /// In en, this message translates to:
  /// **'System-level fallback disabled'**
  String get prefSysFallbackOff;

  /// No description provided for @prefExecFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: $error'**
  String prefExecFailed(String error);

  /// No description provided for @prefIptablesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'iptables unavailable'**
  String get prefIptablesUnavailable;

  /// No description provided for @prefMonet.
  ///
  /// In en, this message translates to:
  /// **'Monet theming'**
  String get prefMonet;

  /// No description provided for @prefMonetDesc.
  ///
  /// In en, this message translates to:
  /// **'Android 12+: colors follow the wallpaper (theme and splash screen pick colors automatically)'**
  String get prefMonetDesc;

  /// No description provided for @prefPredictiveBack.
  ///
  /// In en, this message translates to:
  /// **'Predictive back'**
  String get prefPredictiveBack;

  /// No description provided for @prefPredictiveBackDesc.
  ///
  /// In en, this message translates to:
  /// **'Android 14+ predictive back gesture animation (Material 3 page transitions)'**
  String get prefPredictiveBackDesc;

  /// No description provided for @prefCaptureBodyLimit.
  ///
  /// In en, this message translates to:
  /// **'Capture body limit'**
  String get prefCaptureBodyLimit;

  /// No description provided for @prefBlockQuic.
  ///
  /// In en, this message translates to:
  /// **'Intercept QUIC (UDP:443)'**
  String get prefBlockQuic;

  /// No description provided for @prefQuicBlocked.
  ///
  /// In en, this message translates to:
  /// **'Intercepted $count QUIC packets; forcing a fallback to TCP so traffic can be captured'**
  String prefQuicBlocked(int count);

  /// No description provided for @prefQuicBlockDesc.
  ///
  /// In en, this message translates to:
  /// **'Drop UDP 443 to force apps back to TCP so HTTPS traffic can be captured'**
  String get prefQuicBlockDesc;

  /// No description provided for @prefQuicBlockOff.
  ///
  /// In en, this message translates to:
  /// **'Turned off; takes effect after restarting capture'**
  String get prefQuicBlockOff;

  /// No description provided for @prefSysFallbackDesc.
  ///
  /// In en, this message translates to:
  /// **'System-level fallback (requires Root + iptables): drop all UDP:443 to force a fallback to TCP; stops working after a system reboot'**
  String get prefSysFallbackDesc;

  /// No description provided for @prefDisable.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get prefDisable;

  /// No description provided for @prefMtlsEnabledTapConfig.
  ///
  /// In en, this message translates to:
  /// **'Enabled · tap to configure the client certificate'**
  String get prefMtlsEnabledTapConfig;

  /// No description provided for @prefMtlsDesc.
  ///
  /// In en, this message translates to:
  /// **'Provide a client certificate (PEM) during the TLS handshake with the upstream server'**
  String get prefMtlsDesc;

  /// No description provided for @prefRootMode.
  ///
  /// In en, this message translates to:
  /// **'Root-mode capture'**
  String get prefRootMode;

  /// No description provided for @prefRootModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Redirect the outbound traffic of the system to the local proxy with root privileges, bypassing apps that refuse to connect when a VPN is detected; the device must be rooted and this is mutually exclusive with VPN capture'**
  String get prefRootModeDesc;

  /// No description provided for @prefWanUnit.
  ///
  /// In en, this message translates to:
  /// **'0K'**
  String get prefWanUnit;

  /// No description provided for @cfgManagement.
  ///
  /// In en, this message translates to:
  /// **'Config Management'**
  String get cfgManagement;

  /// No description provided for @cfgManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Import/export config, back up or restore settings'**
  String get cfgManagementDesc;

  /// No description provided for @cfgExport.
  ///
  /// In en, this message translates to:
  /// **'Export Config'**
  String get cfgExport;

  /// No description provided for @cfgExportDesc.
  ///
  /// In en, this message translates to:
  /// **'Export the current config as a JSON file for backup or sharing'**
  String get cfgExportDesc;

  /// No description provided for @cfgImport.
  ///
  /// In en, this message translates to:
  /// **'Import Config'**
  String get cfgImport;

  /// No description provided for @cfgImportDesc.
  ///
  /// In en, this message translates to:
  /// **'Import config from a JSON file; the current config will be overwritten'**
  String get cfgImportDesc;

  /// No description provided for @cfgCopyToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy config to clipboard'**
  String get cfgCopyToClipboard;

  /// No description provided for @cfgCopyToClipboardDesc.
  ///
  /// In en, this message translates to:
  /// **'Generate config text; paste it on another device to import (no file transfer needed)'**
  String get cfgCopyToClipboardDesc;

  /// No description provided for @cfgImportFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Import config from clipboard'**
  String get cfgImportFromClipboard;

  /// No description provided for @cfgImportFromClipboardDesc.
  ///
  /// In en, this message translates to:
  /// **'Read the config text from the clipboard; the current config will be overwritten'**
  String get cfgImportFromClipboardDesc;

  /// No description provided for @cfgBackupDesc.
  ///
  /// In en, this message translates to:
  /// **'View, restore or delete automatically backed-up config files'**
  String get cfgBackupDesc;

  /// No description provided for @cfgNotice.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get cfgNotice;

  /// No description provided for @cfgNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'• Exporting includes all proxy settings, filter rules, MCP config and more
• Importing completely overwrites the current config, so proceed with care
• Exporting the config regularly as a backup is recommended
• The config file is in JSON format and can be viewed in a text editor'**
  String get cfgNoticeBody;

  /// No description provided for @cfgExporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting config'**
  String get cfgExporting;

  /// No description provided for @cfgExportPreparing.
  ///
  /// In en, this message translates to:
  /// **'Please wait, preparing the export file...'**
  String get cfgExportPreparing;

  /// No description provided for @cfgPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get cfgPreparing;

  /// No description provided for @cfgSelectSaveLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose save location'**
  String get cfgSelectSaveLocation;

  /// No description provided for @cfgExportedTo.
  ///
  /// In en, this message translates to:
  /// **'Config exported to: $path'**
  String cfgExportedTo(String path);

  /// No description provided for @cfgExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: $error'**
  String cfgExportFailed(String error);

  /// No description provided for @cfgConfirmImport.
  ///
  /// In en, this message translates to:
  /// **'Confirm import'**
  String get cfgConfirmImport;

  /// No description provided for @cfgImportConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Importing the config will completely overwrite the current config. Continue?

Exporting the current config as a backup first is recommended.'**
  String get cfgImportConfirmBody;

  /// No description provided for @cfgImportSuccessRestart.
  ///
  /// In en, this message translates to:
  /// **'Config imported successfully; some settings may need an app restart to take effect'**
  String get cfgImportSuccessRestart;

  /// No description provided for @cfgImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: $error'**
  String cfgImportFailed(String error);

  /// No description provided for @cfgCopied.
  ///
  /// In en, this message translates to:
  /// **'Config copied to the clipboard; paste it on another device to import'**
  String get cfgCopied;

  /// No description provided for @cfgCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Copy failed: $error'**
  String cfgCopyFailed(String error);

  /// No description provided for @cfgImportConfirmBodyShort.
  ///
  /// In en, this message translates to:
  /// **'Importing will overwrite the current config. Continue?'**
  String get cfgImportConfirmBodyShort;

  /// No description provided for @cfgClipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'There is no text in the clipboard'**
  String get cfgClipboardEmpty;

  /// No description provided for @cfgClipboardNotConfig.
  ///
  /// In en, this message translates to:
  /// **'The clipboard content is not config JSON; copy the config text first'**
  String get cfgClipboardNotConfig;


  /// No description provided for @devToolCron.
  ///
  /// In en, this message translates to:
  /// **'Cron expression'**
  String get devToolCron;

  /// No description provided for @devToolJwt.
  ///
  /// In en, this message translates to:
  /// **'JWT decode'**
  String get devToolJwt;

  /// No description provided for @devToolSha.
  ///
  /// In en, this message translates to:
  /// **'SHA hash'**
  String get devToolSha;

  /// No description provided for @devToolCronExampleWorkday.
  ///
  /// In en, this message translates to:
  /// **'9 AM on weekdays'**
  String get devToolCronExampleWorkday;

  /// No description provided for @devToolCronExampleMonthly.
  ///
  /// In en, this message translates to:
  /// **'8:30 on the 1st of each month'**
  String get devToolCronExampleMonthly;

  /// No description provided for @devToolCronExampleMidnight.
  ///
  /// In en, this message translates to:
  /// **'Midnight every day'**
  String get devToolCronExampleMidnight;

  /// No description provided for @devToolCronExampleEvery15Min.
  ///
  /// In en, this message translates to:
  /// **'Every 15 minutes'**
  String get devToolCronExampleEvery15Min;

  /// No description provided for @devToolCronExampleEvery2Hours.
  ///
  /// In en, this message translates to:
  /// **'Every 2 hours'**
  String get devToolCronExampleEvery2Hours;

  /// No description provided for @devToolCronExampleMondayNoon.
  ///
  /// In en, this message translates to:
  /// **'Noon every Monday'**
  String get devToolCronExampleMondayNoon;

  /// No description provided for @devToolCronParseError.
  ///
  /// In en, this message translates to:
  /// **'Cannot parse this expression; check each field'**
  String get devToolCronParseError;

  /// No description provided for @devToolCronHint.
  ///
  /// In en, this message translates to:
  /// **'min hour day month weekday'**
  String get devToolCronHint;

  /// No description provided for @devToolCronParse.
  ///
  /// In en, this message translates to:
  /// **'Parse'**
  String get devToolCronParse;

  /// No description provided for @devToolCronNextRuns.
  ///
  /// In en, this message translates to:
  /// **'Next 6 run times'**
  String get devToolCronNextRuns;

  /// No description provided for @devToolCronFieldHelp.
  ///
  /// In en, this message translates to:
  /// **'Field reference'**
  String get devToolCronFieldHelp;

  /// No description provided for @devToolCronWildcardHint.
  ///
  /// In en, this message translates to:
  /// **'Wildcards: * any  ·  , list  ·  - range  ·  / step'**
  String get devToolCronWildcardHint;

  /// No description provided for @devToolCronExamples.
  ///
  /// In en, this message translates to:
  /// **'Common examples (tap to fill)'**
  String get devToolCronExamples;

  /// No description provided for @devToolCronFieldMinute.
  ///
  /// In en, this message translates to:
  /// **'Minute'**
  String get devToolCronFieldMinute;

  /// No description provided for @devToolCronFieldHour.
  ///
  /// In en, this message translates to:
  /// **'Hour'**
  String get devToolCronFieldHour;

  /// No description provided for @devToolCronFieldDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get devToolCronFieldDay;

  /// No description provided for @devToolCronFieldMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get devToolCronFieldMonth;

  /// No description provided for @devToolCronFieldWeek.
  ///
  /// In en, this message translates to:
  /// **'Weekday'**
  String get devToolCronFieldWeek;

  /// No description provided for @devToolCronFieldWeekRange.
  ///
  /// In en, this message translates to:
  /// **'0-6 (0 is Sunday)'**
  String get devToolCronFieldWeekRange;

  /// No description provided for @devToolJwtInvalid.
  ///
  /// In en, this message translates to:
  /// **'A JWT should have at least two Base64Url segments (header.payload.signature)'**
  String get devToolJwtInvalid;

  /// No description provided for @devToolJwtDecodeFailed.
  ///
  /// In en, this message translates to:
  /// **'Decode failed: $error'**
  String devToolJwtDecodeFailed(String error);

  /// No description provided for @devToolJwtExpiry.
  ///
  /// In en, this message translates to:
  /// **'$time ($status)'**
  String devToolJwtExpiry(String time, String status);

  /// No description provided for @devToolJwtExpLabel.
  ///
  /// In en, this message translates to:
  /// **'Expires at: $time'**
  String devToolJwtExpLabel(String time);

  /// No description provided for @devToolJwtExpired.
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get devToolJwtExpired;

  /// No description provided for @devToolJwtValid.
  ///
  /// In en, this message translates to:
  /// **'valid'**
  String get devToolJwtValid;

  /// No description provided for @devToolJwtLabel.
  ///
  /// In en, this message translates to:
  /// **'Paste a JWT token'**
  String get devToolJwtLabel;

  /// No description provided for @devToolJwtHint.
  ///
  /// In en, this message translates to:
  /// **'You can paste an Authorization value with the Bearer prefix'**
  String get devToolJwtHint;

  /// No description provided for @devToolUuidCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get devToolUuidCount;

  /// No description provided for @devToolUuidUppercase.
  ///
  /// In en, this message translates to:
  /// **'Uppercase'**
  String get devToolUuidUppercase;

  /// No description provided for @devToolUuidGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate UUID v4'**
  String get devToolUuidGenerate;

  /// No description provided for @devToolUuidEmpty.
  ///
  /// In en, this message translates to:
  /// **'Tap the button above to generate'**
  String get devToolUuidEmpty;

  /// No description provided for @devToolCopiedAll.
  ///
  /// In en, this message translates to:
  /// **'Copied all'**
  String get devToolCopiedAll;

  /// No description provided for @devToolCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get devToolCopyAll;

  /// No description provided for @devToolShaInput.
  ///
  /// In en, this message translates to:
  /// **'Input text'**
  String get devToolShaInput;

  /// No description provided for @devToolShaNote.
  ///
  /// In en, this message translates to:
  /// **'Computed over UTF-8; to verify files/binary, use the hex tool on captured traffic.'**
  String get devToolShaNote;

  /// No description provided for @calcTitle.
  ///
  /// In en, this message translates to:
  /// **'Calculator'**
  String get calcTitle;

  /// No description provided for @calcTabIntConvert.
  ///
  /// In en, this message translates to:
  /// **'Radix / Two\\'s complement'**
  String get calcTabIntConvert;

  /// No description provided for @calcTabBitwise.
  ///
  /// In en, this message translates to:
  /// **'Bitwise'**
  String get calcTabBitwise;

  /// No description provided for @calcTabEndian.
  ///
  /// In en, this message translates to:
  /// **'Endianness'**
  String get calcTabEndian;

  /// No description provided for @calcTabCrcHash.
  ///
  /// In en, this message translates to:
  /// **'CRC / Hash'**
  String get calcTabCrcHash;

  /// No description provided for @calcEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a value and tap "Calculate" to see the result'**
  String get calcEmptyHint;

  /// No description provided for @calcCopiedKey.
  ///
  /// In en, this message translates to:
  /// **'Copied $name'**
  String calcCopiedKey(String name);

  /// No description provided for @calcCompute.
  ///
  /// In en, this message translates to:
  /// **'Calculate'**
  String get calcCompute;

  /// No description provided for @calcLabelValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get calcLabelValue;

  /// No description provided for @calcIntValueHint.
  ///
  /// In en, this message translates to:
  /// **'Accepts 0x / 0b / 0o / decimal, optional leading minus'**
  String get calcIntValueHint;

  /// No description provided for @calcLabelWidth.
  ///
  /// In en, this message translates to:
  /// **'Bit width'**
  String get calcLabelWidth;

  /// No description provided for @calcNBits.
  ///
  /// In en, this message translates to:
  /// **'$bits bits'**
  String calcNBits(int bits);

  /// No description provided for @calcLabelOperation.
  ///
  /// In en, this message translates to:
  /// **'Operation'**
  String get calcLabelOperation;

  /// No description provided for @calcLabelOperandA.
  ///
  /// In en, this message translates to:
  /// **'Operand A'**
  String get calcLabelOperandA;

  /// No description provided for @calcLabelShiftAmount.
  ///
  /// In en, this message translates to:
  /// **'Shift amount (decimal)'**
  String get calcLabelShiftAmount;

  /// No description provided for @calcLabelOperandB.
  ///
  /// In en, this message translates to:
  /// **'Operand B'**
  String get calcLabelOperandB;

  /// No description provided for @calcHintShiftExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. 4'**
  String get calcHintShiftExample;

  /// No description provided for @calcHintOperandBExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. 0x0FF0'**
  String get calcHintOperandBExample;

  /// No description provided for @calcLabelHexData.
  ///
  /// In en, this message translates to:
  /// **'Hex data'**
  String get calcLabelHexData;

  /// No description provided for @calcHintHexDataExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. 0x78563412'**
  String get calcHintHexDataExample;

  /// No description provided for @calcLabelByteWidth.
  ///
  /// In en, this message translates to:
  /// **'Byte width'**
  String get calcLabelByteWidth;

  /// No description provided for @calcByteWidthAuto.
  ///
  /// In en, this message translates to:
  /// **'Match input length'**
  String get calcByteWidthAuto;

  /// No description provided for @calcNBytes.
  ///
  /// In en, this message translates to:
  /// **'$bytes bytes'**
  String calcNBytes(int bytes);

  /// No description provided for @calcLabelMachineOrValue.
  ///
  /// In en, this message translates to:
  /// **'Machine code or number'**
  String get calcLabelMachineOrValue;

  /// No description provided for @calcIeeeHint.
  ///
  /// In en, this message translates to:
  /// **'Hex machine code (e.g. 0x3f800000) or a decimal fraction (e.g. 1.5)'**
  String get calcIeeeHint;

  /// No description provided for @calcLabelPrecision.
  ///
  /// In en, this message translates to:
  /// **'Precision'**
  String get calcLabelPrecision;

  /// No description provided for @calcLabelAlgorithm.
  ///
  /// In en, this message translates to:
  /// **'Algorithm'**
  String get calcLabelAlgorithm;

  /// No description provided for @calcLabelInputFormat.
  ///
  /// In en, this message translates to:
  /// **'Input format'**
  String get calcLabelInputFormat;

  /// No description provided for @calcLabelData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get calcLabelData;


  /// No description provided for @wsPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get wsPageTitle;

  /// No description provided for @wsPageNew.
  ///
  /// In en, this message translates to:
  /// **'New workspace'**
  String get wsPageNew;

  /// No description provided for @wsPageNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name (e.g. "Payment module", "Test env")'**
  String get wsPageNameHint;

  /// No description provided for @wsPageRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename workspace'**
  String get wsPageRenameTitle;

  /// No description provided for @wsPageDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace'**
  String get wsPageDeleteTitle;

  /// No description provided for @wsPageDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete "$name" and its local data? This cannot be undone.'**
  String wsPageDeleteConfirm(String name);

  /// No description provided for @wsPageNoCaptureData.
  ///
  /// In en, this message translates to:
  /// **'No captured requests to save'**
  String get wsPageNoCaptureData;

  /// No description provided for @wsPageSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved $count to "$name"'**
  String wsPageSavedTo(int count, String name);

  /// No description provided for @wsPageSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: $error'**
  String wsPageSaveFailed(String error);

  /// No description provided for @wsPageEmptyWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace is empty'**
  String get wsPageEmptyWorkspace;

  /// No description provided for @wsPageImportedToHistory.
  ///
  /// In en, this message translates to:
  /// **'Imported $count requests to history'**
  String wsPageImportedToHistory(int count);

  /// No description provided for @wsPageImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: $error'**
  String wsPageImportFailed(String error);

  /// No description provided for @wsPageServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace server'**
  String get wsPageServerTitle;

  /// No description provided for @wsPageServerUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Base URL (e.g. http://10.0.0.5:8787)'**
  String get wsPageServerUrlHint;

  /// No description provided for @wsPageTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Token (optional)'**
  String get wsPageTokenTitle;

  /// No description provided for @wsPageServerSaved.
  ///
  /// In en, this message translates to:
  /// **'Server config saved'**
  String get wsPageServerSaved;

  /// No description provided for @wsPageServerCleared.
  ///
  /// In en, this message translates to:
  /// **'Server config cleared'**
  String get wsPageServerCleared;

  /// No description provided for @wsPageServerNeeded.
  ///
  /// In en, this message translates to:
  /// **'Configure the workspace server first'**
  String get wsPageServerNeeded;

  /// No description provided for @wsPagePushed.
  ///
  /// In en, this message translates to:
  /// **'Pushed to server ($bytes bytes)'**
  String wsPagePushed(int bytes);

  /// No description provided for @wsPagePushFailed.
  ///
  /// In en, this message translates to:
  /// **'Push failed: $error'**
  String wsPagePushFailed(String error);

  /// No description provided for @wsPageServerNoWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Server has no workspaces'**
  String get wsPageServerNoWorkspaces;

  /// No description provided for @wsPagePulled.
  ///
  /// In en, this message translates to:
  /// **'Pulled $count workspaces'**
  String wsPagePulled(int count);

  /// No description provided for @wsPagePullFailed.
  ///
  /// In en, this message translates to:
  /// **'Pull failed: $error'**
  String wsPagePullFailed(String error);

  /// No description provided for @wsPageServerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Server settings'**
  String get wsPageServerTooltip;

  /// No description provided for @wsPagePullFromServer.
  ///
  /// In en, this message translates to:
  /// **'Pull from server'**
  String get wsPagePullFromServer;

  /// No description provided for @wsPageEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No workspace yet. Create one, save the current capture into it, and manage captures per project.'**
  String get wsPageEmptyHint;

  /// No description provided for @wsPageCustomServer.
  ///
  /// In en, this message translates to:
  /// **'Custom server'**
  String get wsPageCustomServer;

  /// No description provided for @wsPageServerNotConfiguredHint.
  ///
  /// In en, this message translates to:
  /// **'Not configured. Only needed if you want to share/backup to your own server.'**
  String get wsPageServerNotConfiguredHint;

  /// No description provided for @wsPageSaveCurrent.
  ///
  /// In en, this message translates to:
  /// **'Save current capture'**
  String get wsPageSaveCurrent;

  /// No description provided for @wsPageImportToHistory.
  ///
  /// In en, this message translates to:
  /// **'Import to history'**
  String get wsPageImportToHistory;

  /// No description provided for @wsPagePushToServer.
  ///
  /// In en, this message translates to:
  /// **'Push to server'**
  String get wsPagePushToServer;

  /// No description provided for @wsPageItemMeta.
  ///
  /// In en, this message translates to:
  /// **'$count requests · $time'**
  String wsPageItemMeta(int count, String time);

  /// No description provided for @logViewReadyHint.
  ///
  /// In en, this message translates to:
  /// **'Log viewer is ready: runtime logs will show up here in real time (up to 500 entries).'**
  String get logViewReadyHint;

  /// No description provided for @logViewExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Logs exported'**
  String get logViewExportSuccess;

  /// No description provided for @logViewExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Log export failed'**
  String get logViewExportFailed;

  /// No description provided for @logViewExportError.
  ///
  /// In en, this message translates to:
  /// **'Export failed: $error'**
  String logViewExportError(String error);

  /// No description provided for @logViewClearLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear logs'**
  String get logViewClearLogs;

  /// No description provided for @logViewClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all logs? This cannot be undone.'**
  String get logViewClearConfirm;

  /// No description provided for @logViewCleared.
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logViewCleared;

  /// No description provided for @logViewTitle.
  ///
  /// In en, this message translates to:
  /// **'Log management'**
  String get logViewTitle;

  /// No description provided for @logViewTapToPause.
  ///
  /// In en, this message translates to:
  /// **'Recording, tap to pause'**
  String get logViewTapToPause;

  /// No description provided for @logViewTapToResume.
  ///
  /// In en, this message translates to:
  /// **'Paused, tap to resume'**
  String get logViewTapToResume;

  /// No description provided for @logViewRecordingResumed.
  ///
  /// In en, this message translates to:
  /// **'Log recording enabled'**
  String get logViewRecordingResumed;

  /// No description provided for @logViewRecordingPaused.
  ///
  /// In en, this message translates to:
  /// **'Log recording paused'**
  String get logViewRecordingPaused;

  /// No description provided for @logViewMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get logViewMore;

  /// No description provided for @logViewSearchLogs.
  ///
  /// In en, this message translates to:
  /// **'Search logs'**
  String get logViewSearchLogs;

  /// No description provided for @logViewExportLogs.
  ///
  /// In en, this message translates to:
  /// **'Export logs'**
  String get logViewExportLogs;

  /// No description provided for @logViewNoLogs.
  ///
  /// In en, this message translates to:
  /// **'No logs yet'**
  String get logViewNoLogs;

  /// No description provided for @logViewStatTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get logViewStatTotal;

  /// No description provided for @logViewStatDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get logViewStatDebug;

  /// No description provided for @logViewStatInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logViewStatInfo;

  /// No description provided for @logViewStatWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get logViewStatWarning;

  /// No description provided for @logViewStatError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logViewStatError;

  /// No description provided for @logViewTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get logViewTime;

  /// No description provided for @logViewTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get logViewTag;

  /// No description provided for @logViewMessage.
  ///
  /// In en, this message translates to:
  /// **'Message:'**
  String get logViewMessage;

  /// No description provided for @logViewStack.
  ///
  /// In en, this message translates to:
  /// **'Stack:'**
  String get logViewStack;

  /// No description provided for @cmpTitle.
  ///
  /// In en, this message translates to:
  /// **'Request comparison'**
  String get cmpTitle;

  /// No description provided for @cmpTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get cmpTabOverview;

  /// No description provided for @cmpHasDiff.
  ///
  /// In en, this message translates to:
  /// **'Differences found'**
  String get cmpHasDiff;

  /// No description provided for @cmpIdentical.
  ///
  /// In en, this message translates to:
  /// **'Identical'**
  String get cmpIdentical;

  /// No description provided for @cmpTotalChanges.
  ///
  /// In en, this message translates to:
  /// **'$count changes in total'**
  String cmpTotalChanges(int count);

  /// No description provided for @cmpFieldMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get cmpFieldMethod;

  /// No description provided for @cmpChangeStats.
  ///
  /// In en, this message translates to:
  /// **'Change summary'**
  String get cmpChangeStats;

  /// No description provided for @cmpHeaderChanges.
  ///
  /// In en, this message translates to:
  /// **'Header changes'**
  String get cmpHeaderChanges;

  /// No description provided for @cmpQueryChanges.
  ///
  /// In en, this message translates to:
  /// **'Parameter changes'**
  String get cmpQueryChanges;

  /// No description provided for @cmpBodyChanges.
  ///
  /// In en, this message translates to:
  /// **'Body changes'**
  String get cmpBodyChanges;

  /// No description provided for @cmpStatusChanges.
  ///
  /// In en, this message translates to:
  /// **'Status code changes'**
  String get cmpStatusChanges;

  /// No description provided for @cmpDetailedReport.
  ///
  /// In en, this message translates to:
  /// **'Detailed report'**
  String get cmpDetailedReport;

  /// No description provided for @cmpNoHeaderChanges.
  ///
  /// In en, this message translates to:
  /// **'No header changes'**
  String get cmpNoHeaderChanges;

  /// No description provided for @cmpOldValue.
  ///
  /// In en, this message translates to:
  /// **'Old: $value'**
  String cmpOldValue(String value);

  /// No description provided for @cmpNewValue.
  ///
  /// In en, this message translates to:
  /// **'New: $value'**
  String cmpNewValue(String value);

  /// No description provided for @cmpNoBodyChanges.
  ///
  /// In en, this message translates to:
  /// **'No body changes'**
  String get cmpNoBodyChanges;

  /// No description provided for @cmpBodyA.
  ///
  /// In en, this message translates to:
  /// **'Request body A'**
  String get cmpBodyA;

  /// No description provided for @cmpBodyB.
  ///
  /// In en, this message translates to:
  /// **'Request body B'**
  String get cmpBodyB;

  /// No description provided for @cmpNoResponseData.
  ///
  /// In en, this message translates to:
  /// **'No response data'**
  String get cmpNoResponseData;

  /// No description provided for @cmpResponseHeaderChanges.
  ///
  /// In en, this message translates to:
  /// **'Response header changes ($count)'**
  String cmpResponseHeaderChanges(int count);

  /// No description provided for @cmpNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get cmpNoChanges;

  /// No description provided for @cmpResponseBodyA.
  ///
  /// In en, this message translates to:
  /// **'Response body A'**
  String get cmpResponseBodyA;

  /// No description provided for @cmpResponseBodyB.
  ///
  /// In en, this message translates to:
  /// **'Response body B'**
  String get cmpResponseBodyB;

  /// No description provided for @cmpModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get cmpModified;

  /// No description provided for @cmpRequestLabel.
  ///
  /// In en, this message translates to:
  /// **'Request $label'**
  String cmpRequestLabel(String label);

  /// No description provided for @cmpEmpty.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get cmpEmpty;


  /// No description provided for @backupCreated.
  ///
  /// In en, this message translates to:
  /// **'Backup created: $name ($count items)'**
  String backupCreated(String name, int count);

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: $error'**
  String backupFailed(String error);

  /// No description provided for @backupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up now (config + certificate + scripts + workspace)'**
  String get backupNow;

  /// No description provided for @backupAutoToAppDataDir.
  ///
  /// In en, this message translates to:
  /// **'Configuration automatically backs up to the app data directory'**
  String get backupAutoToAppDataDir;

  /// No description provided for @backupOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get backupOk;

  /// No description provided for @backupConfirmRestore.
  ///
  /// In en, this message translates to:
  /// **'Confirm restore'**
  String get backupConfirmRestore;

  /// No description provided for @backupRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restoring backup "$name" will overwrite the current configuration. Continue?'**
  String backupRestoreConfirm(String name);

  /// No description provided for @backupConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm delete'**
  String get backupConfirmDelete;

  /// No description provided for @backupRestoredApplied.
  ///
  /// In en, this message translates to:
  /// **'Restored $restored files; the configuration is now in effect'**
  String backupRestoredApplied(int restored);

  /// No description provided for @backupRestoredNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Restored $restored files (configuration not applied$failedSuffix)'**
  String backupRestoredNotApplied(int restored, String failedSuffix);

  /// No description provided for @backupFailedSuffix.
  ///
  /// In en, this message translates to:
  /// **', $failed items failed'**
  String backupFailedSuffix(int failed);

  /// No description provided for @backupAppliedSuffix.
  ///
  /// In en, this message translates to:
  /// **', the configuration is now in effect'**
  String get backupAppliedSuffix;

  /// No description provided for @backupConfigRestored.
  ///
  /// In en, this message translates to:
  /// **'Configuration restored'**
  String get backupConfigRestored;

  /// No description provided for @backupRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: $error'**
  String backupRestoreFailed(String error);

  /// No description provided for @backupRestoredSummary.
  ///
  /// In en, this message translates to:
  /// **'Restored $restored files$applied$failed'**
  String backupRestoredSummary(int restored, String applied, String failed);

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get backupRestored;

  /// No description provided for @backupChooseSaveLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose a save location'**
  String get backupChooseSaveLocation;

  /// No description provided for @backupExportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to: $path'**
  String backupExportedTo(String path);

  /// No description provided for @backupExportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export backup file'**
  String get backupExportDialogTitle;

  /// No description provided for @backupExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Exported successfully'**
  String get backupExportSuccess;

  /// No description provided for @backupExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: $error'**
  String backupExportFailed(String error);

  /// No description provided for @backupDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete backup "$name"?'**
  String backupDeleteConfirm(String name);

  /// No description provided for @backupDeleteConfirmDesktop.
  ///
  /// In en, this message translates to:
  /// **'Delete backup file "$name"?

This cannot be undone.'**
  String backupDeleteConfirmDesktop(String name);

  /// No description provided for @backupDeleted.
  ///
  /// In en, this message translates to:
  /// **'Backup deleted'**
  String get backupDeleted;

  /// No description provided for @backupDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: $error'**
  String backupDeleteFailed(String error);

  /// No description provided for @backupDirNotFound.
  ///
  /// In en, this message translates to:
  /// **'Backup directory does not exist'**
  String get backupDirNotFound;

  /// No description provided for @backupRestoreConfirmDesktop.
  ///
  /// In en, this message translates to:
  /// **'Restore backup file "$name"?

The current configuration will be overwritten.'**
  String backupRestoreConfirmDesktop(String name);

  /// No description provided for @backupViewTitle.
  ///
  /// In en, this message translates to:
  /// **'View backup: $name'**
  String backupViewTitle(String name);

  /// No description provided for @backupViewFailed.
  ///
  /// In en, this message translates to:
  /// **'View failed: $error'**
  String backupViewFailed(String error);

  /// No description provided for @backupCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get backupCopied;

  /// No description provided for @backupJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get backupJustNow;


  /// No description provided for @cfgDeskGeneratingConfig.
  ///
  /// In en, this message translates to:
  /// **'Generating config file...'**
  String get cfgDeskGeneratingConfig;

  /// No description provided for @cfgDeskCannotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Unable to read the file'**
  String get cfgDeskCannotReadFile;

  /// No description provided for @rootProxyNoAccess.
  ///
  /// In en, this message translates to:
  /// **'Root permission not granted: the device may not be rooted, or you did not tap Allow in the authorization dialog'**
  String get rootProxyNoAccess;

  /// No description provided for @rootProxyClosed.
  ///
  /// In en, this message translates to:
  /// **'Turned off; the iptables rules have been cleaned up'**
  String get rootProxyClosed;

  /// No description provided for @rootProxyStopError.
  ///
  /// In en, this message translates to:
  /// **'Error while turning it off: rules may still be present; retry or reboot the device'**
  String get rootProxyStopError;

  /// No description provided for @rootProxyNeedCapture.
  ///
  /// In en, this message translates to:
  /// **'Start capture first: enabling redirection while the proxy port is not listening will cut the device off the network'**
  String get rootProxyNeedCapture;

  /// No description provided for @rootProxyNeedStopVpn.
  ///
  /// In en, this message translates to:
  /// **'Stop VPN capture first: the two capture methods cannot be used at the same time'**
  String get rootProxyNeedStopVpn;

  /// No description provided for @rootProxyStartDenied.
  ///
  /// In en, this message translates to:
  /// **'Failed to enable; make sure root permission has been granted'**
  String get rootProxyStartDenied;

  /// No description provided for @rootProxyStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to enable: $reason'**
  String rootProxyStartFailed(String reason);

  /// No description provided for @rootProxyActive.
  ///
  /// In en, this message translates to:
  /// **'Redirection is active'**
  String get rootProxyActive;

  /// No description provided for @rootProxyInactive.
  ///
  /// In en, this message translates to:
  /// **'Not active'**
  String get rootProxyInactive;

  /// No description provided for @rootProxyTargetPort.
  ///
  /// In en, this message translates to:
  /// **'Target port: $port　Protection: leftover rules are cleaned up automatically on the next launch'**
  String rootProxyTargetPort(int port);

  /// No description provided for @rootProxyCheckRoot.
  ///
  /// In en, this message translates to:
  /// **'Check root permission'**
  String get rootProxyCheckRoot;

  /// No description provided for @rootProxyFirstCheck.
  ///
  /// In en, this message translates to:
  /// **'The first check will bring up the su authorization dialog'**
  String get rootProxyFirstCheck;

  /// No description provided for @rootProxyGranted.
  ///
  /// In en, this message translates to:
  /// **'Root permission granted'**
  String get rootProxyGranted;

  /// No description provided for @rootProxyNotGranted.
  ///
  /// In en, this message translates to:
  /// **'Root permission not granted'**
  String get rootProxyNotGranted;

  /// No description provided for @rootProxyNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get rootProxyNotesTitle;

  /// No description provided for @rootProxyNotesBody.
  ///
  /// In en, this message translates to:
  /// **'· The device must be rooted and su permission granted;
· The idea is to add a chain for ProxyPin only to the nat table, redirecting outbound TCP connections to the proxy port, without making any other changes;
· Only IPv4 is handled; IPv6 traffic stays direct;
· Mutually exclusive with VPN capture, so turn the VPN off first;
· If the phone shows “connected to WiFi but no internet”, turn this off first; the app also cleans up leftover rules on every launch.'**
  String get rootProxyNotesBody;


  /// No description provided for @fuzzDictDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Imported dictionary'**
  String get fuzzDictDefaultName;

  /// No description provided for @fuzzDictImported.
  ///
  /// In en, this message translates to:
  /// **'Imported "$name"'**
  String fuzzDictImported(String name);

  /// No description provided for @fuzzDictDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete dictionary'**
  String get fuzzDictDeleteTitle;

  /// No description provided for @fuzzDictDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete "$name"?'**
  String fuzzDictDeleteConfirm(String name);

  /// No description provided for @fuzzDictTitle.
  ///
  /// In en, this message translates to:
  /// **'Fuzz Dictionary'**
  String get fuzzDictTitle;

  /// No description provided for @fuzzDictTips.
  ///
  /// In en, this message translates to:
  /// **'Tap a dictionary to fill it into the current injection. No built-in attack payload library — the built-ins are just boundary/type-anomaly strings; fill, import or script the rest yourself.'**
  String get fuzzDictTips;

  /// No description provided for @fuzzDictNoCustom.
  ///
  /// In en, this message translates to:
  /// **'No custom dictionaries yet'**
  String get fuzzDictNoCustom;

  /// No description provided for @fuzzDictImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get fuzzDictImportFile;

  /// No description provided for @fuzzDictNEntries.
  ///
  /// In en, this message translates to:
  /// **'$count values'**
  String fuzzDictNEntries(int count);

  /// No description provided for @fuzzDictExpanded.
  ///
  /// In en, this message translates to:
  /// **'Expanded to $count values: $preview'**
  String fuzzDictExpanded(int count, String preview);

  /// No description provided for @fuzzDictScriptFailed.
  ///
  /// In en, this message translates to:
  /// **'Script failed: $error'**
  String fuzzDictScriptFailed(String error);

  /// No description provided for @fuzzDictNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give the dictionary a name'**
  String get fuzzDictNameRequired;

  /// No description provided for @fuzzDictCreate.
  ///
  /// In en, this message translates to:
  /// **'New dictionary'**
  String get fuzzDictCreate;

  /// No description provided for @fuzzDictEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit dictionary'**
  String get fuzzDictEditTitle;

  /// No description provided for @fuzzDictScriptLabel.
  ///
  /// In en, this message translates to:
  /// **'Script (optional, JS; assign the array to result)'**
  String get fuzzDictScriptLabel;

  /// No description provided for @fuzzDictTestRun.
  ///
  /// In en, this message translates to:
  /// **'Try it'**
  String get fuzzDictTestRun;

  /// No description provided for @fuzzDictScriptNote.
  ///
  /// In en, this message translates to:
  /// **'The script output is merged with the values above and de-duplicated'**
  String get fuzzDictScriptNote;

  /// No description provided for @apiEpTitle.
  ///
  /// In en, this message translates to:
  /// **'API Endpoints ($count)'**
  String apiEpTitle(int count);

  /// No description provided for @apiEpSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search endpoints...'**
  String get apiEpSearchHint;

  /// No description provided for @apiEpTotalEndpoints.
  ///
  /// In en, this message translates to:
  /// **'Total endpoints'**
  String get apiEpTotalEndpoints;

  /// No description provided for @apiEpResourceGroups.
  ///
  /// In en, this message translates to:
  /// **'Resource groups'**
  String get apiEpResourceGroups;

  /// No description provided for @apiEpTotalRequests.
  ///
  /// In en, this message translates to:
  /// **'Total requests'**
  String get apiEpTotalRequests;

  /// No description provided for @apiEpPathCalls.
  ///
  /// In en, this message translates to:
  /// **'$path · $count requests'**
  String apiEpPathCalls(String path, int count);

  /// No description provided for @apiEpCallsSuccess.
  ///
  /// In en, this message translates to:
  /// **'$count calls · Success rate $rate'**
  String apiEpCallsSuccess(int count, String rate);

  /// No description provided for @apiEpNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching endpoints found'**
  String get apiEpNoMatch;

  /// No description provided for @apiEpGroupView.
  ///
  /// In en, this message translates to:
  /// **'Group view'**
  String get apiEpGroupView;

  /// No description provided for @apiEpListView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get apiEpListView;

  /// No description provided for @apiEpGroupByDomain.
  ///
  /// In en, this message translates to:
  /// **'Group by host'**
  String get apiEpGroupByDomain;

  /// No description provided for @apiEpExportOpenApi.
  ///
  /// In en, this message translates to:
  /// **'Export as OpenAPI'**
  String get apiEpExportOpenApi;

  /// No description provided for @apiEpSwaggerFormat.
  ///
  /// In en, this message translates to:
  /// **'Swagger format'**
  String get apiEpSwaggerFormat;

  /// No description provided for @apiEpExportPostman.
  ///
  /// In en, this message translates to:
  /// **'Export as Postman'**
  String get apiEpExportPostman;

  /// No description provided for @apiEpCollectionFormat.
  ///
  /// In en, this message translates to:
  /// **'Collection format'**
  String get apiEpCollectionFormat;

  /// No description provided for @apiEpExportJson.
  ///
  /// In en, this message translates to:
  /// **'Export as JSON'**
  String get apiEpExportJson;

  /// No description provided for @apiEpExported.
  ///
  /// In en, this message translates to:
  /// **'$label exported'**
  String apiEpExported(String label);

  /// No description provided for @apiEpExportFailed.
  ///
  /// In en, this message translates to:
  /// **'$label export failed: $error'**
  String apiEpExportFailed(String label, String error);

  /// No description provided for @apiEpFullUrl.
  ///
  /// In en, this message translates to:
  /// **'Full URL'**
  String get apiEpFullUrl;

  /// No description provided for @apiEpCallCount.
  ///
  /// In en, this message translates to:
  /// **'Call count'**
  String get apiEpCallCount;

  /// No description provided for @apiEpAvgResponseTime.
  ///
  /// In en, this message translates to:
  /// **'Avg response time'**
  String get apiEpAvgResponseTime;

  /// No description provided for @apiEpFirstSeen.
  ///
  /// In en, this message translates to:
  /// **'First seen'**
  String get apiEpFirstSeen;

  /// No description provided for @apiEpLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get apiEpLastSeen;

  /// No description provided for @apiEpTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get apiEpTags;


  /// No description provided for @perfLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load data: $error'**
  String perfLoadFailed(String error);

  /// No description provided for @perfTitle.
  ///
  /// In en, this message translates to:
  /// **'Performance Monitoring'**
  String get perfTitle;

  /// No description provided for @perfRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get perfRetry;

  /// No description provided for @perfLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading data...'**
  String get perfLoading;

  /// No description provided for @perfLastUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last updated: $time'**
  String perfLastUpdate(String time);

  /// No description provided for @perfProxyStatus.
  ///
  /// In en, this message translates to:
  /// **'Proxy Status'**
  String get perfProxyStatus;

  /// No description provided for @perfRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get perfRunning;

  /// No description provided for @perfStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get perfStopped;

  /// No description provided for @perfOverview.
  ///
  /// In en, this message translates to:
  /// **'Performance Overview'**
  String get perfOverview;

  /// No description provided for @perfTotalRequests.
  ///
  /// In en, this message translates to:
  /// **'Total Requests'**
  String get perfTotalRequests;

  /// No description provided for @perfConnectionPool.
  ///
  /// In en, this message translates to:
  /// **'Connection Pool Status'**
  String get perfConnectionPool;

  /// No description provided for @perfActiveConnections.
  ///
  /// In en, this message translates to:
  /// **'Active Connections'**
  String get perfActiveConnections;

  /// No description provided for @perfIdleConnections.
  ///
  /// In en, this message translates to:
  /// **'Idle Connections'**
  String get perfIdleConnections;

  /// No description provided for @perfMetrics.
  ///
  /// In en, this message translates to:
  /// **'Performance Metrics'**
  String get perfMetrics;

  /// No description provided for @perfAvgResponseTime.
  ///
  /// In en, this message translates to:
  /// **'Average Response Time'**
  String get perfAvgResponseTime;

  /// No description provided for @perfQps.
  ///
  /// In en, this message translates to:
  /// **'QPS (requests per second)'**
  String get perfQps;

  /// No description provided for @perfRequestStats.
  ///
  /// In en, this message translates to:
  /// **'Request Statistics'**
  String get perfRequestStats;

  /// No description provided for @perfNoBreakdown.
  ///
  /// In en, this message translates to:
  /// **'No breakdown data'**
  String get perfNoBreakdown;

  /// No description provided for @rqTitle.
  ///
  /// In en, this message translates to:
  /// **'Send Queue'**
  String get rqTitle;

  /// No description provided for @rqClearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished tasks'**
  String get rqClearFinished;

  /// No description provided for @rqIntro.
  ///
  /// In en, this message translates to:
  /// **'All replay tasks started during this run (repeated, batch, or scheduled) are gathered here: check progress, success and failure counts, and the queue of pending requests. Tasks are in-memory and cleared on restart.'**
  String get rqIntro;

  /// No description provided for @rqCancelTask.
  ///
  /// In en, this message translates to:
  /// **'Cancel task (stop further sending)'**
  String get rqCancelTask;

  /// No description provided for @rqRemoveRecord.
  ///
  /// In en, this message translates to:
  /// **'Remove record'**
  String get rqRemoveRecord;

  /// No description provided for @rqStatRetried.
  ///
  /// In en, this message translates to:
  /// **'Retried'**
  String get rqStatRetried;

  /// No description provided for @rqStatPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get rqStatPlanned;

  /// No description provided for @rqLastError.
  ///
  /// In en, this message translates to:
  /// **'Last error: $error'**
  String rqLastError(String error);

  /// No description provided for @rqPendingRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending requests ($count)'**
  String rqPendingRequests(int count);

  /// No description provided for @rqMoreRemaining.
  ///
  /// In en, this message translates to:
  /// **'... and $count more'**
  String rqMoreRemaining(int count);

  /// No description provided for @rqStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get rqStatusScheduled;

  /// No description provided for @rqStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get rqStatusRunning;

  /// No description provided for @rqStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get rqStatusCompleted;

  /// No description provided for @rqStatusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get rqStatusCanceled;

  /// No description provided for @rqEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No replay tasks yet'**
  String get rqEmptyTitle;

  /// No description provided for @rqEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tasks show up here after you start a replay (batch or scheduled)'**
  String get rqEmptyHint;

  /// No description provided for @bvDescTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Unix timestamp (seconds)'**
  String get bvDescTimestamp;

  /// No description provided for @bvDescTimestampMs.
  ///
  /// In en, this message translates to:
  /// **'Unix timestamp (milliseconds)'**
  String get bvDescTimestampMs;

  /// No description provided for @bvDescDatetime.
  ///
  /// In en, this message translates to:
  /// **'ISO 8601 date-time'**
  String get bvDescDatetime;

  /// No description provided for @bvDescDate.
  ///
  /// In en, this message translates to:
  /// **'Date (yyyy-MM-dd)'**
  String get bvDescDate;

  /// No description provided for @bvDescTime.
  ///
  /// In en, this message translates to:
  /// **'Time (HH:mm:ss)'**
  String get bvDescTime;

  /// No description provided for @bvDescUnixDate.
  ///
  /// In en, this message translates to:
  /// **'Days since 1970'**
  String get bvDescUnixDate;

  /// No description provided for @bvDescUuid.
  ///
  /// In en, this message translates to:
  /// **'Random UUID (different on every reference)'**
  String get bvDescUuid;

  /// No description provided for @bvTitle.
  ///
  /// In en, this message translates to:
  /// **'Built-in variables'**
  String get bvTitle;

  /// No description provided for @bvIntro.
  ///
  /// In en, this message translates to:
  /// **'These variables need no definition — reference them directly anywhere $mark is supported (rewrite rules, report URLs, scripts, etc.). Tap to copy.'**
  String bvIntro(String mark);

  /// No description provided for @bvCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied $text'**
  String bvCopied(String text);

  /// No description provided for @bvGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get bvGotIt;


  /// No description provided for @toolboxNavCalcTip.
  ///
  /// In en, this message translates to:
  /// **'Base conversion / two\\'s complement · bitwise ops · endianness · IEEE754 · CRC/hash'**
  String get toolboxNavCalcTip;

  /// No description provided for @toolboxNavMcpTip.
  ///
  /// In en, this message translates to:
  /// **'MCP Server settings'**
  String get toolboxNavMcpTip;

  /// No description provided for @toolboxNavLogView.
  ///
  /// In en, this message translates to:
  /// **'Log viewer'**
  String get toolboxNavLogView;

  /// No description provided for @toolboxNavWaf.
  ///
  /// In en, this message translates to:
  /// **'WAF mutation'**
  String get toolboxNavWaf;

  /// No description provided for @toolboxNavWafTip.
  ///
  /// In en, this message translates to:
  /// **'Payload-equivalent mutation + WAF signature comparison + active probing (probing sends real requests and requires authorization)'**
  String get toolboxNavWafTip;

  /// No description provided for @toolboxNavPinningTip.
  ///
  /// In en, this message translates to:
  /// **'Certificate-pinning bypass helper: detect the frida environment · generate/deploy hook scripts · one-tap injection'**
  String get toolboxNavPinningTip;

  /// No description provided for @toolboxNavWorkspaceTip.
  ///
  /// In en, this message translates to:
  /// **'Manage captures separately per project/environment (standard HAR storage) · can hook up a custom server for sharing/backup'**
  String get toolboxNavWorkspaceTip;

  /// No description provided for @toolboxNavCloudTip.
  ///
  /// In en, this message translates to:
  /// **'Account · cloud-hosted workspaces · real-time multi-user collaboration (self-hosted server)'**
  String get toolboxNavCloudTip;

  /// No description provided for @toolboxNavAiTip.
  ///
  /// In en, this message translates to:
  /// **'AI chat analysis of captured data (Agent mode supported)'**
  String get toolboxNavAiTip;

  /// No description provided for @deskNavUpgradeTitle.
  ///
  /// In en, this message translates to:
  /// **'What\\'s new in V$version'**
  String deskNavUpgradeTitle(String version);

  /// No description provided for @deskNavUpgradeBody.
  ///
  /// In en, this message translates to:
  /// **'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.
Click the HTTPS capture (lock) icon, choose "Install Root Certificate", and follow the prompts to complete installation.

1. Added a built-in MCP server so AI assistants (e.g. Claude) can inspect and debug captured traffic;
2. Added built-in dynamic variables for environments;
3. Request rewrite rules can now be reordered with move up/down actions;
4. Fixed a crash triggered by the Windows context menu;
5. Fixed multi-value headers (e.g. multiple Set-Cookie) being incorrectly merged when handled by scripts or rewrite rules;
6. Fixed h2c (plaintext HTTP/2) capture, non-ASCII domain normalization, and certificate validation failures for IP hosts;
7. Fixed an iOS 13 crash, dropped bodies for close-delimited responses, Android VPN destination-port recording, and other issues.
'**
  String get deskNavUpgradeBody;

  /// No description provided for @setNavThemeTip.
  ///
  /// In en, this message translates to:
  /// **'Theme settings are in the top toolbar — click the sun/moon icon to switch'**
  String get setNavThemeTip;

  /// No description provided for @setNavProxyDomainsHint.
  ///
  /// In en, this message translates to:
  /// **'Use \\';\\' to separate multiple entries'**
  String get setNavProxyDomainsHint;

  /// No description provided for @setNavClearProxyResidue.
  ///
  /// In en, this message translates to:
  /// **'Clear leftover system proxy'**
  String get setNavClearProxyResidue;

  /// No description provided for @setNavClearProxyResidueDesc.
  ///
  /// In en, this message translates to:
  /// **'Click here to recover when the network is broken after an abnormal exit'**
  String get setNavClearProxyResidueDesc;

  /// No description provided for @setNavProxyResidueCleared.
  ///
  /// In en, this message translates to:
  /// **'System proxy settings cleared — the network should be back to normal'**
  String get setNavProxyResidueCleared;

  /// No description provided for @setNavRepair.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get setNavRepair;

  /// No description provided for @mobNavUpgradeTitle.
  ///
  /// In en, this message translates to:
  /// **'What\\'s new in V$version'**
  String mobNavUpgradeTitle(String version);

  /// No description provided for @mobNavUpgradeBody.
  ///
  /// In en, this message translates to:
  /// **'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.

1. Added a built-in MCP server so AI assistants (e.g. Claude) can inspect and debug captured traffic;
2. Added built-in dynamic variables for environments;
3. Request rewrite rules can now be reordered with move up/down actions;
4. Fixed a crash triggered by the Windows context menu;
5. Fixed multi-value headers (e.g. multiple Set-Cookie) being incorrectly merged when handled by scripts or rewrite rules;
6. Fixed h2c (plaintext HTTP/2) capture, non-ASCII domain normalization, and certificate validation failures for IP hosts;
7. Fixed an iOS 13 crash, dropped bodies for close-delimited responses, Android VPN destination-port recording, and other issues.
'**
  String get mobNavUpgradeBody;

  /// No description provided for @appFilterUnknownApp.
  ///
  /// In en, this message translates to:
  /// **'Unknown app'**
  String get appFilterUnknownApp;

  /// No description provided for @appFilterClearInvalid.
  ///
  /// In en, this message translates to:
  /// **'clear invalid apps'**
  String get appFilterClearInvalid;

  /// No description provided for @appFilterWhitelistHint.
  ///
  /// In en, this message translates to:
  /// **'When no whitelist application is set, all applications will be captured'**
  String get appFilterWhitelistHint;

  /// No description provided for @appFilterRemoveWhitelistConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this app from the whitelist?'**
  String get appFilterRemoveWhitelistConfirm;

  /// No description provided for @appFilterRemoveBlacklistConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this app from the blacklist?'**
  String get appFilterRemoveBlacklistConfirm;

  /// No description provided for @appFilterSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Please enter the application or package name'**
  String get appFilterSearchHint;

  /// No description provided for @appFilterShowSystemApps.
  ///
  /// In en, this message translates to:
  /// **'Show system apps'**
  String get appFilterShowSystemApps;

  /// No description provided for @contentBodyOriginalMb.
  ///
  /// In en, this message translates to:
  /// **'($size MB original)'**
  String contentBodyOriginalMb(String size);

  /// No description provided for @contentBodyOriginalKb.
  ///
  /// In en, this message translates to:
  /// **'($size KB original)'**
  String contentBodyOriginalKb(String size);

  /// No description provided for @contentBodyTruncatedTip.
  ///
  /// In en, this message translates to:
  /// **'Trimmed to the capture size limit — the full content was not kept'**
  String get contentBodyTruncatedTip;

  /// No description provided for @contentBodyTruncatedBadge.
  ///
  /// In en, this message translates to:
  /// **'Trimmed $size'**
  String contentBodyTruncatedBadge(String size);

  /// No description provided for @contentBodySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: $error'**
  String contentBodySaveFailed(String error);

  /// No description provided for @contentBodyDecodeTruncatedTip.
  ///
  /// In en, this message translates to:
  /// **'Response body is large — the preview only decodes up to the limit (adjustable in Settings → Capture size limit). Preview only; forwarding and saved content are unaffected.'**
  String get contentBodyDecodeTruncatedTip;

  /// No description provided for @contentBodyPreviewTruncated.
  ///
  /// In en, this message translates to:
  /// **'Preview truncated'**
  String get contentBodyPreviewTruncated;

}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return lookupAppLocalizations(locale);
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'en',
    'es',
    'id',
    'pt',
    'th',
    'vi',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

Future<AppLocalizations> lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return app_localizations_zh.loadLibrary().then(
              (dynamic _) => app_localizations_zh.AppLocalizationsZhHant(),
            );
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return app_localizations_pt.loadLibrary().then(
              (dynamic _) => app_localizations_pt.AppLocalizationsPtBr(),
            );
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return app_localizations_en.loadLibrary().then(
        (dynamic _) => app_localizations_en.AppLocalizationsEn(),
      );
    case 'es':
      return app_localizations_es.loadLibrary().then(
        (dynamic _) => app_localizations_es.AppLocalizationsEs(),
      );
    case 'id':
      return app_localizations_id.loadLibrary().then(
        (dynamic _) => app_localizations_id.AppLocalizationsId(),
      );
    case 'pt':
      return app_localizations_pt.loadLibrary().then(
        (dynamic _) => app_localizations_pt.AppLocalizationsPt(),
      );
    case 'th':
      return app_localizations_th.loadLibrary().then(
        (dynamic _) => app_localizations_th.AppLocalizationsTh(),
      );
    case 'vi':
      return app_localizations_vi.loadLibrary().then(
        (dynamic _) => app_localizations_vi.AppLocalizationsVi(),
      );
    case 'zh':
      return app_localizations_zh.loadLibrary().then(
        (dynamic _) => app_localizations_zh.AppLocalizationsZh(),
      );
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
