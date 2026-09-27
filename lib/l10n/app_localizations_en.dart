// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get breakpoint => 'Breakpoint';

  @override
  String get breakpointRule => 'Breakpoint Rule';

  @override
  String get name => 'Name';

  @override
  String get requests => 'Requests';

  @override
  String get favorites => 'Favorites';

  @override
  String get history => 'History';

  @override
  String get toolbox => 'Toolbox';

  @override
  String get preference => 'Preferences';

  @override
  String get feedback => 'Feedback';

  @override
  String get about => 'About';

  @override
  String get filter => 'Proxy Filter';

  @override
  String get script => 'Script';

  @override
  String get share => 'Share';

  @override
  String get port => 'Port: ';

  @override
  String get proxy => 'Proxy';

  @override
  String get externalProxy => 'External Proxy';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get proxySetting => 'Proxy Setting';

  @override
  String get setAs => 'Set as ';

  @override
  String get systemProxy => 'System Proxy';

  @override
  String get enabledHTTP2 => 'Enable HTTP2';

  @override
  String get serverNotStart => 'Proxy server not started';

  @override
  String get download => 'Download';

  @override
  String get config => 'Configuration';

  @override
  String get version => 'Version';

  @override
  String get start => 'Start';

  @override
  String get stop => 'Stop';

  @override
  String get clear => 'Clear';

  @override
  String get httpsProxy => 'HTTPS Proxy';

  @override
  String get setting => 'Settings';

  @override
  String get mobileConnect => 'Mobile Connect';

  @override
  String get connectRemote => 'Connect Remote';

  @override
  String get remoteDevice => 'Remote Device';

  @override
  String get remoteDeviceList => 'Remote Device List';

  @override
  String get myQRCode => 'My QR Code';

  @override
  String get theme => 'Theme';

  @override
  String get followSystem => 'Follow System';

  @override
  String get themeColor => 'Theme Color';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get autoStartup => 'Auto Start Recording Traffic';

  @override
  String get autoStartupDescribe =>
      'Automatically start recording traffic when the program starts';

  @override
  String get minimizeToTrayTitle => 'Minimize to tray on close';

  @override
  String get minimizeToTraySubtitle =>
      'Closing the window will keep ProxyPin running and hide it to the system tray.';

  @override
  String get trayClosePromptContent =>
      'Closing the window will keep ProxyPin running in the system tray. Do you want to minimize it now?';

  @override
  String get trayCloseExitAnyway => 'Exit anyway';

  @override
  String get trayCloseMinimizeToTray => 'Minimize to tray';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String get execute => 'Execute';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get confirm => 'Confirm';

  @override
  String get confirmTitle => 'Confirm operation';

  @override
  String get confirmContent => 'Are you sure about this operation?';

  @override
  String get addSuccess => 'Successfully added';

  @override
  String get saveSuccess => 'Saved successfully';

  @override
  String get operationSuccess => 'Operation succeeded';

  @override
  String get import => 'Import';

  @override
  String get importSuccess => 'Import successful';

  @override
  String get importFailed => 'Import failed';

  @override
  String get export => 'Export';

  @override
  String get exportSuccess => 'Export successful';

  @override
  String get exportFailed => 'Export failed';

  @override
  String get deleteSuccess => 'Delete successful';

  @override
  String get send => 'Send';

  @override
  String get fail => 'fail';

  @override
  String get success => 'success';

  @override
  String get emptyData => 'Empty Data';

  @override
  String get requestSuccess => 'Request successful';

  @override
  String get add => 'Add';

  @override
  String get all => 'All';

  @override
  String get modify => 'Modify';

  @override
  String get responseType => 'Response Type';

  @override
  String get request => 'Request';

  @override
  String get response => 'Response';

  @override
  String get statusCode => 'Status code';

  @override
  String get duration => 'Duration';

  @override
  String get done => 'Done';

  @override
  String get type => 'Type';

  @override
  String get enable => 'Enable';

  @override
  String get example => 'Example: ';

  @override
  String get responseHeader => 'Headers';

  @override
  String get requestHeader => 'Headers';

  @override
  String get requestLine => 'Request Line';

  @override
  String get requestMethod => 'Request Method';

  @override
  String get param => 'Param';

  @override
  String get replaceBodyWith => 'Replace Body With:';

  @override
  String get redirectTo => 'Redirect To:';

  @override
  String get redirect => 'Redirect';

  @override
  String get cannotBeEmpty => 'Cannot be empty';

  @override
  String get requestRewriteList => 'Request Rewrite List';

  @override
  String get requestRewriteRule => 'Request Rewrite Rule';

  @override
  String get requestRewriteEnable => 'Enable Request Rewrite';

  @override
  String get action => 'Action';

  @override
  String get multiple => 'Multiple';

  @override
  String get edit => 'Edit';

  @override
  String get moveUp => 'Move Up';

  @override
  String get moveDown => 'Move Down';

  @override
  String get disabled => 'Disabled';

  @override
  String requestRewriteDeleteConfirm(Object size) {
    return 'Delete $size rule(s)?';
  }

  @override
  String get useGuide => 'Use Guide';

  @override
  String get pleaseEnter => 'Please Enter';

  @override
  String get click => 'Click';

  @override
  String get loadRemoteScript => 'load remote script';

  @override
  String get replace => 'Replace';

  @override
  String get clickEdit => 'Click Edit';

  @override
  String get refresh => 'Refresh';

  @override
  String get selectFile => 'Select file';

  @override
  String get match => 'Match';

  @override
  String get value => 'Value';

  @override
  String get matchRule => 'Match Rule';

  @override
  String get emptyMatchAll => 'Empty means match all';

  @override
  String get newBuilt => 'New';

  @override
  String get reportServers => 'Report Servers';

  @override
  String get addReportServer => 'Add Report Server';

  @override
  String get editReportServer => 'Edit Report Server';

  @override
  String get splitReport => 'Split Report';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get compression => 'Compression';

  @override
  String get compressionNone => 'None';

  @override
  String get newFolder => 'New Folder';

  @override
  String get enableSelect => 'Enable Select';

  @override
  String get disableSelect => 'Disable Select';

  @override
  String get deleteSelect => 'Delete Select';

  @override
  String get testData => 'Test Data';

  @override
  String get noChangesDetected => 'No changes detected';

  @override
  String get enterMatchData => 'Enter the data to be matched';

  @override
  String get modifyRequestHeader => 'Modify Header';

  @override
  String get headerName => 'Header Name';

  @override
  String get headerValue => 'Header Value';

  @override
  String get deleteHeaderConfirm => 'Do you want to delete the request header?';

  @override
  String get sequence => 'All Requests';

  @override
  String get domainList => 'Domain List';

  @override
  String get domainWhitelist => 'Proxy Domain Whitelist';

  @override
  String get domainBlacklist => 'Proxy Domain Blacklist';

  @override
  String get domainFilter => 'Proxy Domain List';

  @override
  String get appWhitelist => 'App Whitelist';

  @override
  String get appWhitelistDescribe =>
      'Only proxy Apps on the whitelist. If the whitelist is enabled, the blacklist will be invalid';

  @override
  String get appBlacklist => 'App Blacklist';

  @override
  String get scanCode => 'Scan Code Connect';

  @override
  String get addBlacklist => 'Add Proxy Blacklist';

  @override
  String get addWhitelist => 'Add Proxy Whitelist';

  @override
  String get deleteWhitelist => 'Delete Proxy Whitelist';

  @override
  String domainListSubtitle(Object count, Object time) {
    return 'Last Request Time: $time,  Count: $count';
  }

  @override
  String get selectAction => 'Select action';

  @override
  String get select => 'Select';

  @override
  String get copy => 'Copy';

  @override
  String get copyHost => 'Copy Host';

  @override
  String get copyUrl => 'Copy URL';

  @override
  String get copyRawRequest => 'Copy Raw Request';

  @override
  String get copyRequestResponse => 'Copy Request and Response';

  @override
  String get copyCurl => 'Copy cURL';

  @override
  String get copyAsPythonRequests => 'Copy as Python Requests';

  @override
  String get copyAsFetch => 'Copy as fetch';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get repeat => 'Repeat';

  @override
  String get repeatAllRequests => 'Repeat All Requests';

  @override
  String get repeatDomainRequests => 'Repeat Domain Requests';

  @override
  String get customRepeat => 'Custom Repeat';

  @override
  String get repeatCount => 'Iterations';

  @override
  String get repeatInterval => 'Interval(ms)';

  @override
  String get repeatDelay => 'Delay(ms)';

  @override
  String get scheduleTime => 'Schedule Time';

  @override
  String get fixed => 'fixed';

  @override
  String get random => 'random';

  @override
  String get keepCustomSettings => 'Keep custom settings';

  @override
  String get editRequest => 'Edit and Request';

  @override
  String get reSendRequest => 'The request has been resent';

  @override
  String get viewExport => 'View Export';

  @override
  String get exportDomainHar => 'Export This Domain HAR';

  @override
  String get timeDesc => 'Descending by time';

  @override
  String get timeAsc => 'Ascending by time';

  @override
  String get search => 'Search';

  @override
  String get clearSearch => 'Clear Search';

  @override
  String get requestType => 'Request type';

  @override
  String get keyword => 'Keyword';

  @override
  String get keywordSearchScope => 'Keyword search scope: ';

  @override
  String get favorite => 'Favorite';

  @override
  String get deleteFavorite => 'Delete Favorite';

  @override
  String get emptyFavorite => 'Empty Favorite';

  @override
  String get deleteFavoriteSuccess => 'Favorite deleted';

  @override
  String get historyRecord => 'History';

  @override
  String get historyCacheTime => 'Cache Time';

  @override
  String get historyManualSave => 'Manual Save';

  @override
  String historyDay(Object day) {
    return '$day days';
  }

  @override
  String get historyForever => 'Forever';

  @override
  String historyRecordTitle(Object length, Object name) {
    return '$name Records $length';
  }

  @override
  String get historyEmptyName => 'Name cannot be empty';

  @override
  String historySubtitle(Object requestLength, Object size) {
    return 'Records $requestLength  file $size';
  }

  @override
  String get historyUnSave => 'Current record is not saved';

  @override
  String get historyDeleteConfirm => 'Do you want to delete this history?';

  @override
  String get requestEdit => 'Request Editing';

  @override
  String get encode => 'Encode';

  @override
  String get requestBody => 'Request Body';

  @override
  String get responseBody => 'Response Body';

  @override
  String get requestRewrite => 'Request Rewrite';

  @override
  String get newWindow => 'New Window';

  @override
  String get httpRequest => 'HTTP Request';

  @override
  String get enabledHttps => 'Enable HTTPS Proxy';

  @override
  String get installRootCa => 'Install Certificate';

  @override
  String get installCaLocal => 'Install Certificate to Local-Machine';

  @override
  String get downloadRootCa => 'Download Certificate';

  @override
  String get downloadRootCaNote =>
      'Note: If you set the default browser to other than Safari, click this line to copy and paste the link to Safari browser';

  @override
  String get generateCA => 'Generate new root certificate';

  @override
  String get generateCADescribe =>
      'Are you sure you want to generate a new root certificate? If confirmed,\nYou need to reinstall and trust the new certificate';

  @override
  String get resetDefaultCA => 'Reset Default Root Certificate';

  @override
  String get resetDefaultCADescribe =>
      'Are you sure you want to reset to the default root certificate?\nProxyPin default root certificate is the same for all users.';

  @override
  String get exportCaP12 => 'Export Root Certificate(.p12)';

  @override
  String get importCaP12 => 'Import Root Certificate(.p12)';

  @override
  String get trustCa => 'Trust Certificate';

  @override
  String get profileDownload => 'Profile Download';

  @override
  String get exportCA => 'Export Root Certificate';

  @override
  String get exportPrivateKey => 'Export Private Key';

  @override
  String get install => 'Install';

  @override
  String get installCaDescribe =>
      'Install CA Setting > Profile Download > Install';

  @override
  String get trustCaDescribe =>
      'Trust CA Setting > General > About > Certificate Trust Setting';

  @override
  String get androidRoot => 'System Certificate (ROOT Device)';

  @override
  String get androidRootMagisk =>
      'Magisk module: \nAndroid ROOT devices can be used Magisk ProxyPinCA System Certificate Module, After installing and restarting the phone Check the system certificate to see if there is a ProxyPinCA certificate. If there is, it indicates that the certificate has been successfully installed。';

  @override
  String androidRootRename(Object name) {
    return 'If the module does not take effect, you can install the system root certificate according to the online tutorial, and name the root certificate $name';
  }

  @override
  String get androidRootCADownload => 'Download System Certificate(.0)';

  @override
  String get androidUserCA => 'User Certificate';

  @override
  String get androidUserCATips =>
      'Tips: Android7+ many apps will not trust user certificates';

  @override
  String get androidUserCAInstall =>
      'Open settings -> Security -> Encryption and credentials -> Install certificate -> CA certificate';

  @override
  String get androidUserXposed =>
      'It is recommended to use the Xposed module for packet capture (no need for ROOT), click to view wiki';

  @override
  String get configWifiProxy => 'Configure mobile Wi-Fi proxy';

  @override
  String get caInstallGuide => 'Certificate Installation Guide';

  @override
  String get caAndroidBrowser => 'Open Google Browser on Android devices：';

  @override
  String get caIosBrowser => 'Open Safari on iOS devices：';

  @override
  String get localIP => 'Local IP ';

  @override
  String get mobileScan => 'Configure Wi-Fi proxy or Scan with Mobile App';

  @override
  String get decode => 'Decode';

  @override
  String get encodeInput => 'Enter the content to be converted';

  @override
  String get encodeResult => 'Conversion Result';

  @override
  String get encodeFail => 'Encoding failed';

  @override
  String get decodeFail => 'Decoding failed';

  @override
  String get shareUrl => 'Share Request URL';

  @override
  String get shareCurl => 'Share cURL Request';

  @override
  String get requestResponse => 'Request and Response';

  @override
  String get captureDetail => 'Capture Detail';

  @override
  String get proxyPinSoftware =>
      'ProxyPin Open source traffic capture software for all platforms';

  @override
  String get prompt => 'Prompt';

  @override
  String get curlSchemeRequest =>
      'If the curl format is recognized, should it be converted into an HTTP request?';

  @override
  String get appExitTips => 'Press again to exit the program';

  @override
  String get remoteConnectDisconnect =>
      'Check remote connection failed, disconnected';

  @override
  String get connect => 'Connect';

  @override
  String get reconnect => 'Reconnect';

  @override
  String remoteConnected(Object os) {
    return 'Connected $os, traffic will be forwarded to $os';
  }

  @override
  String get remoteConnectForward =>
      'Remote connection, forwarding requests to other terminals';

  @override
  String get connectSuccess => 'Connect successful';

  @override
  String get connectedRemote => 'Connected to remote';

  @override
  String get connected => 'Connected';

  @override
  String get notConnected => 'Not connected';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get ipLayerProxy => 'IP Layer Proxy';

  @override
  String get ipLayerProxyDesc =>
      'IP layer proxy can capture Flutter app requests';

  @override
  String get inputAddress => 'Input Address';

  @override
  String get syncConfig => 'Sync configuration';

  @override
  String get pullConfigFail =>
      'Failed to pull configuration, please check the network connection';

  @override
  String get sync => 'Sync';

  @override
  String get invalidQRCode => 'Unrecognized QR code';

  @override
  String get remoteConnectFail =>
      'Connection failed，Please check if it is allowed on the same LAN and firewall, iOS needs to enable local network permissions';

  @override
  String get remoteConnectSuccessTips =>
      'Your phone needs to enable packet capture in order to capture requests';

  @override
  String get windowMode => 'Window Mode';

  @override
  String get windowModeSubTitle =>
      'Enabled Packet Capture, Enter the background, Display a small window';

  @override
  String get pipIcon => 'Window shortcut icon';

  @override
  String get pipIconDescribe => 'Show quick access to small window Icon';

  @override
  String get bottomNavigation => 'Bottom Navigation';

  @override
  String get bottomNavigationSubtitle =>
      'Bottom navigation bar is displayed, effective after restart';

  @override
  String get memoryCleanup => 'Memory Cleanup';

  @override
  String get memoryCleanupSubtitle =>
      'Automatically clean up requests on memory limit reached and keep 32 most recent after cleaning';

  @override
  String get maxRequestCount => 'Request Record Limit';

  @override
  String get maxRequestCountSubtitle =>
      'Max number of requests kept in the list; oldest requests are dropped automatically when exceeded';

  @override
  String get clearConfirm => 'Confirm before clearing captured records';

  @override
  String get clearConfirmSubtitle =>
      'Show a confirmation dialog before clearing captured records';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get custom => 'Custom';

  @override
  String get externalProxyAuth => 'Proxy Auth (Optional)';

  @override
  String get externalProxyServer => 'Proxy Server';

  @override
  String get externalProxyConnectFailure => 'External Proxy Connect failure';

  @override
  String get externalProxyFailureConfirm =>
      'Access to all http will fail due to network connectivity issues，Do you want to continue setting up external proxies。';

  @override
  String get mobileDisplayPacketCapture => 'Mobile Display Packet Capture:';

  @override
  String proxyPortRepeat(Object port) {
    return 'Startup failed, please check the port number $port is occupied。';
  }

  @override
  String get reset => 'Reset';

  @override
  String get proxyIgnoreDomain => 'Proxy ignores domain';

  @override
  String get domainWhitelistDescribe =>
      'Only proxy domain names or URL paths on the whitelist (wildcards supported, e.g. example.com/api/). If the whitelist is enabled, the blacklist will be invalid';

  @override
  String get domainBlacklistDescribe =>
      'Domain names or URL paths on the blacklist will not be proxied';

  @override
  String get domain => 'Host';

  @override
  String get enableScript => 'Enable Script';

  @override
  String get scriptUseDescribe =>
      'Use JavaScript to modify requests and responses';

  @override
  String get scriptEdit => 'Edit script';

  @override
  String get scrollEnd => 'Scroll to End';

  @override
  String get logger => 'Log';

  @override
  String get material3 =>
      'Material 3 is the latest version of Google’s open-source design system';

  @override
  String get iosVpnBackgroundAudio =>
      'After turning on packet capture, exit to the background. In order to maintain the main UI thread for network communication, a silent audio playback will be enabled to keep the main thread running. Otherwise, it will only run in the background for 30 seconds. Do you agree to play audio in the background after turning on packet capture?';

  @override
  String get markRead => 'Mark as read';

  @override
  String get autoRead => 'Auto read';

  @override
  String get highlight => 'Highlight';

  @override
  String get blue => 'Blue';

  @override
  String get green => 'Green';

  @override
  String get yellow => 'Yellow';

  @override
  String get red => 'Red';

  @override
  String get pink => 'Pink';

  @override
  String get gray => 'Gray';

  @override
  String get underline => 'Underline';

  @override
  String get requestBlock => 'Request Block';

  @override
  String get other => 'Other';

  @override
  String get certHashName => 'CA Hash Name';

  @override
  String get regExp => 'RegExp';

  @override
  String get systemCertName => 'System Certificate Name';

  @override
  String get qrCode => 'QR Code';

  @override
  String get jsonViewer => 'JSON Viewer';

  @override
  String get xmlViewer => 'XML Viewer';

  @override
  String get textDiff => 'Text Diff';

  @override
  String get textEditor => 'Text Editor';

  @override
  String get compare => 'Compare';

  @override
  String get diffOriginal => 'Original';

  @override
  String get diffChanged => 'Changed';

  @override
  String get diffIdentical => 'Two texts are identical';

  @override
  String diffSummary(int added, int removed) {
    return '+$added −$removed';
  }

  @override
  String get text => 'Text';

  @override
  String get format => 'Format';

  @override
  String get compact => 'Compact';

  @override
  String get wordWrap => 'Word Wrap';

  @override
  String get scanQrCode => 'Scan QR Code';

  @override
  String get generateQrCode => 'Generate';

  @override
  String get saveImage => 'Save Image';

  @override
  String get selectImage => 'Select Image';

  @override
  String get inputContent => 'Input Content';

  @override
  String get errorCorrectLevel => 'Error Correct';

  @override
  String get output => 'Output';

  @override
  String get timestamp => 'Timestamp';

  @override
  String get convert => 'Convert';

  @override
  String get time => 'DateTime';

  @override
  String get nowTimestamp => 'Now timestamp';

  @override
  String get hosts => 'Hosts';

  @override
  String get toAddress => 'To Address';

  @override
  String get encrypt => 'Encrypt';

  @override
  String get decrypt => 'Decrypt';

  @override
  String get cipher => 'Cipher';

  @override
  String get view => 'View';

  @override
  String get appUpdateCheckVersion => 'Check for Updates';

  @override
  String get appUpdateNotAvailableMsg => 'Already Using The Latest Version';

  @override
  String get appUpdateDialogTitle => 'Update Available';

  @override
  String get appUpdateUpdateMsg =>
      'A new version of ProxyPin is available. Would you like to update now?';

  @override
  String get appUpdateCurrentVersionLbl => 'Current Version';

  @override
  String get appUpdateNewVersionLbl => 'New Version';

  @override
  String get appUpdateUpdateNowBtnTxt => 'Update Now';

  @override
  String get appUpdateLaterBtnTxt => 'Later';

  @override
  String get appUpdateIgnoreBtnTxt => 'Ignore';

  @override
  String get appUpdateInstallNow => 'Install Now';

  @override
  String get appUpdateRetry => 'Retry';

  @override
  String get appUpdateBackgroundDownload => 'Download in background';

  @override
  String get appUpdateOpenDownloadPage => 'Open Download Page';

  @override
  String get requestMap => 'Request Map';

  @override
  String get requestMapDescribe =>
      'Do not request remote services, use local configuration or script for response';

  @override
  String get automatic => 'Automatic';

  @override
  String get manual => 'Manual';

  @override
  String get certNotInstalled => 'Certificate not installed';

  @override
  String get openNewWindow => 'Open New Window';

  @override
  String get sponsorDonate => 'Sponsor / Donate';

  @override
  String get sponsorSupport => 'Support ongoing development';

  @override
  String get sponsorThanks =>
      'Thank you for supporting this open-source project by choosing any of the following methods to help its long-term development.';

  @override
  String get sponsorAfdian => 'AFDIAN';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get privacyContent =>
      'This open-source packet capture tool runs entirely on your device. It has no backend server and does not collect, store, or upload any personal data. All captured traffic is processed locally and is only forwarded when you explicitly use remote forwarding. Permissions (e.g., network, storage, and camera for QR codes) are used solely to provide features. You can audit the behavior in the public source code.';

  @override
  String get requestCrypto => 'Request Crypto';

  @override
  String get cryptoDecoded => 'Decoded';

  @override
  String get cryptoDecodeToggle => 'Decrypt';

  @override
  String get optional => 'Optional';

  @override
  String get cryptoRuleField => 'Field Name';

  @override
  String get cryptoIvPrefixLabel => 'IV Prefix';

  @override
  String get cryptoIvPrefixTooltip =>
      'Use the first N bytes of the response body as IV';

  @override
  String get local => 'Local';

  @override
  String get remoteUrl => 'Remote URL';

  @override
  String get preview => 'Preview';

  @override
  String get environment => 'Environment';

  @override
  String get environmentVariables => 'Environment Variables';

  @override
  String get envGlobal => 'Global';

  @override
  String get envManage => 'Manage Environments…';

  @override
  String get envNone => 'No Environment';

  @override
  String get envDeleteConfirm => 'Delete this environment?';

  @override
  String get envEmptyHint => 'No variables yet. Click + to add.';

  @override
  String get envUsageHint =>
      'Reference variables as %s in rules, or read/write via context.env in scripts.';

  @override
  String get envInsertBuiltIn => 'Insert built-in variable';

  @override
  String get weakNetwork => 'Network Throttling';

  @override
  String get weakNetworkPreset => 'Preset';

  @override
  String get weakNetworkPresetOffline => 'Offline';

  @override
  String get weakNetworkPresetSlow => 'Slow';

  @override
  String get weakNetworkPresetWeak => 'Weak';

  @override
  String get weakNetworkLatency => 'Latency';

  @override
  String get weakNetworkUpload => 'Upload';

  @override
  String get weakNetworkDownload => 'Download';

  @override
  String get weakNetworkBandwidth => 'Bandwidth';

  @override
  String get weakNetworkLossRate => 'Packet Loss';

  @override
  String get weakNetworkRules => 'URL Rules';

  @override
  String get mcpService => 'MCP Server';

  @override
  String get mcpServiceDescribe =>
      'Starts a local HTTP server for Model Context Protocol (MCP) communication with AI tools such as Claude.';

  @override
  String get mcpEnable => 'Enable MCP Server';

  @override
  String get mcpPort => 'Port';

  @override
  String get mcpAdvanced => 'Advanced settings';

  @override
  String get mcpConfig => 'MCP Configuration';

  @override
  String get mcpRedact => 'Redact sensitive data before sending to AI';

  @override
  String get mcpRedactDescribe => 'Automatically redact sensitive information before it is sent to AI tools.';

  @override
  String mcpHintRun(String client) {
    return 'Run this command in Terminal to add ProxyPin MCP to $client.';
  }

  @override
  String get mcpAboutTitle => 'About MCP Integration';

  @override
  String get mcpAboutText =>
      'MCP (Model Context Protocol) lets AI assistants like Claude interact with ProxyPin. AI can read captured HTTP traffic, create debugging rules (Map Local, Map Remote, Breakpoints), and help analyze network issues.';

  @override
  String get mcpLearnMore => 'Learn more about MCP';

  @override
  String get mcpSkills => 'Skills';

  @override
  String get mcpSkillsTitle => 'MCP Skills';

  @override
  String get mcpSkillsReadonly => 'Read-only traffic tools';

  @override
  String get mcpSkillsRules => 'Rules, replay & environment tools';

  @override
  String get mcpEndpoint => 'MCP Endpoint';

  @override
  String get mcpAccessToken => 'Access Token';

  @override
  String get mcpLanGuide =>
      'Keep this phone and your computer on the same Wi-Fi, then run one of the commands below in your computer\'s terminal, or paste the configuration into your AI client\'s MCP settings.';

  @override
  String get mcpLanTokenNote =>
      'The token authorizes full access to the MCP tools. Tap the refresh button next to the token to revoke it and issue a new one.';

  @override
  String get mcpOtherClients => 'Other AI clients';

  @override
  String get mcpOtherClientsHint =>
      'Universal Streamable HTTP config for Cursor, Cline, Gemini CLI, Cherry Studio, VS Code Copilot and other MCP clients. Paste the URL and Bearer token, or the full JSON, into the client\'s MCP settings.';

  @override
  String get mcpOneClick => 'One-click setup on your computer';

  @override
  String get mcpOneClickHint =>
      'Copy the matching command and run it on the computer: Terminal for macOS/Linux, PowerShell for Windows. It auto-detects installed AI clients (Claude Code, Codex, Cursor, Gemini CLI) and configures them over Wi-Fi.';

  @override
  String get mcpRegenerateToken => 'Reset token';

  @override
  String get mcpStatusRunning => 'Running';

  @override
  String get mcpStatusStopped => 'Stopped';

  @override
  String get mcpClientLabel => 'AI client';

  @override
  String get mcpTransportLabel => 'Transport';

  @override
  String get mcpCommandLabel => 'Connect command';

  @override
  String get mcpClientsIntl => 'International';

  @override
  String get mcpClientsDomestic => 'Chinese';

  @override
  String get mcpTransportStdio => 'stdio';

  @override
  String get mcpTransportHttp => 'HTTP';

  @override
  String get mcpHintTerminal => 'Copy and run in your terminal.';

  @override
  String get mcpHintJson => 'Paste into your client\'s MCP settings.';

  @override
  String get mcpHintCopilot => 'Paste into VS Code settings.json → mcp.servers.';

  @override
  String get mcpHintLingma => 'Tongyi Lingma IDE → Profile → Settings → MCP Service → Add manually (STDIO type).';

  @override
  String get mcpHintCherry => 'Cherry Studio → Settings → MCP Servers → Add.';

  @override
  String get mcpHintDoubao => 'MarsCode IDE → Settings → MCP → Add (STDIO type).';

  @override
  String get mcpSetup => 'Auto setup';

  @override
  String get mcpStartChat => 'Start chat';

  @override
  String get mcpOpenTerminal => 'Run in terminal';

  @override
  String get mcpSetupDone => 'Configured. Restart your AI client to apply.';

  @override
  String get mcpSetupFail => 'Setup failed: ';

  @override
  String mcpCliMissing(Object cli) {
    return 'CLI $cli not found on PATH. Use \"Run in terminal\" instead.';
  }

  @override
  String get mcpUnsupported => 'This client does not support auto setup, configure it manually.';

  @override
  String get mcpCopy => 'Copy';

  @override
  String get mcpCopied => 'Copied';

  @override
  String get mcpStartFailed => 'MCP service failed to start';

  @override
  String get mcpPrivacyHint =>
      'Only listens on 127.0.0.1 (this machine). Data leaves the app only when an AI client explicitly requests it via a tool.';


  @override
  String get securityAiTitle => 'AI Analysis of Audit Results';

  @override
  String get securityAiNotConfigured => 'AI service not configured. Go to Settings → MCP Connection → AI Analysis, and fill in the endpoint and API key.';

  @override
  String get securityAiRawFallback => 'Raw AI reply (couldn\'t be parsed into structured advice; shown as-is)';

  @override
  String get securityAiCopied => 'AI analysis copied';

  @override
  String get securityAiAnalyze => 'Start Analysis';

  @override
  String get securityAiReanalyze => 'Re-analyze';

  @override
  String get securityAiTopRisks => 'Top priorities';

  @override
  String get securityAiFixes => 'Fix suggestions';

  @override
  String get securityAiActionsHeader => 'Suggested ProxyPin setting changes (each needs confirmation)';

  @override
  String get securityAiApply => 'Apply';

  @override
  String get securityAiApplyTitle => 'Apply Setting';

  @override
  String get securityAiApplied => 'Applied';

  @override
  String get securityAiApplyUnsupported => 'This setting can\'t be changed automatically';

  @override
  String get securityAiStateOn => 'On';

  @override
  String get securityAiStateOff => 'Off';

  @override
  String get securityAiActionEnableSsl => 'Enable SSL capture';

  @override
  String get securityAiActionEnableSystemProxy => 'Enable system proxy';

  @override
  String get securityAiActionAntiCache => 'Enable anti-cache';

  @override
  String get securityAiActionMcpAllowLan => 'Allow LAN access to MCP';

  @override
  String get securityAiActionMcpAuth => 'Require MCP authentication';

  @override
  String securityAiApplyConfirm(String key, String value, String reason) {
    return 'Set "$key" to $value?\n\nAI\'s reason: $reason';
  }


  @override
  String get wafTitle => 'WAF Payload Mutation';

  @override
  String get wafLoadFirst => 'Enter a payload first';

  @override
  String get wafPasteResponse => 'Paste the response headers or block page snippet';

  @override
  String wafAppliedCombo(String waf) {
    return 'Applied the combo for $waf';
  }

  @override
  String get wafNeedAuth => 'Check "I have authorization to test this target" first';

  @override
  String get wafNeedUrl => 'Enter a target URL';

  @override
  String wafNeedPlaceholder(String mark) {
    return 'Put a $mark marker somewhere to inject';
  }

  @override
  String get wafNoVariant => 'Nothing under the current selection changes the request. Try another payload or technique.';

  @override
  String wafDoneAll(int total, int bypass) {
    return 'All sent: $total total, $bypass suspected bypass';
  }

  @override
  String get wafDisclaimer => '① and ② only transform strings locally and send nothing; ③ "active probing" really sends requests, so you must check the authorization box first.\nUse only on targets you own or are authorized to test — attempting to bypass someone else\'s protections without authorization may be illegal. Probing is serial, batched (default 200 per batch), with no brute force and no concurrency.';

  @override
  String get wafStep1Title => '① Identify the WAF (optional)';

  @override
  String get wafStep1Hint => 'Paste response headers or a block page you already captured; it matches by signature — no active probing.';

  @override
  String get wafPickNameHint => 'Tap a WAF name to apply the recommended combo';

  @override
  String get wafStep2Title => '② Enter a payload and choose mutations';

  @override
  String get wafStep3Title => '③ Active probing (really sends requests)';

  @override
  String wafStep3Hint(String mark) {
    return 'Put $mark where you want to inject (URL / header / body). A baseline with the original payload goes first, then each checked technique, comparing responses to see which one wasn\'t blocked.';
  }

  @override
  String wafWillProbe(String names) {
    return 'This run will probe (decided by ①②): $names';
  }

  @override
  String wafBatchHint(int max) {
    return 'Up to $max per batch; after each batch it stops and you decide whether to continue — nothing is fired off all at once.';
  }

  @override
  String get wafExtraHeaders => 'Extra request headers (optional, one per line)';

  @override
  String get wafAuthCheckbox => 'I have authorization to test this target';

  @override
  String wafNextBatch(int remaining) {
    return 'Continue next batch ($remaining left)';
  }

  @override
  String wafLimitsHard(int min, int max) {
    return 'Delay floor $min ms, hard cap $max records — these two can\'t be crossed. Beyond that it stops being "probing" and becomes a traffic flood against the target.';
  }

  @override
  String get wafPayloadCopied => 'Payload copied';

  @override
  String wafCopied(String name) {
    return 'Copied: $name';
  }


  @override
  String get guideTitle => 'User Guide';

  @override
  String get guideMarkLegendTitle => 'Markup Legend';

  @override
  String get guideMarkLegend => 'Highlights in docs are shown with several markup styles:\n\n• ==yellow highlight==: key steps\n• bold (theme color): important concepts and entry points\n• __underline__: settings that need extra attention\n• ~orange wavy~: common mistakes\n• ~~strikethrough~~: deprecated or discouraged\n• monospace background: commands, paths, code\n\nCode blocks have "Demo" and "Copy" buttons at the bottom right.';

  @override
  String get guideMarkSyntax => 'Markup syntax: **bold** ==highlight== __underline__ ~~strikethrough~~ ~wavy~ code; a code block can take <!--demo:text--> for a demo note.';

  @override
  String get guideMarkCopied => 'Markup syntax copied';

  @override
  String get guideCopySyntax => 'Copy syntax';

  @override
  String get guideMarkReset => 'Default markup restored';

  @override
  String guideRenderError(String error) {
    return 'Render error (fell back to plain text): $error';
  }

  @override
  String guideDemoTitle(String heading) {
    return 'Demo · $heading';
  }

  @override
  String guideDemoDefault(String heading) {
    return 'This code/config demonstrates usage in the "$heading" section. Drop it into the matching feature page to reproduce.';
  }

  @override
  String get guideGotIt => 'Got it';

  @override
  String get guideDemo => 'Demo';

  @override
  String get guideCodeCopied => 'Code copied';

  @override
  String guideLoadMore(int visible, int total) {
    return 'Load more ($visible / $total shown)';
  }


  @override
  String wafBatchDone(int remaining) {
    return 'Batch done, $remaining left to send';
  }

  @override
  String wafProbeError(String error) {
    return 'Probe error: $error';
  }

  @override
  String get wafCompare => 'Match';

  @override
  String get wafNotIdentified => 'Not identified';

  @override
  String get wafGenerate => 'Generate';

  @override
  String get wafClearSelection => 'Clear selection';

  @override
  String get wafTargetUrl => 'Target URL';

  @override
  String get wafBodyOptional => 'Request body (optional)';

  @override
  String get wafStartProbe => 'Start probing';

  @override
  String get wafClearResults => 'Clear results';

  @override
  String get wafAdvanced => 'Advanced';

  @override
  String wafAdvancedSummary(int delay, int timeout, int max) {
    return 'Delay $delayms · Timeout $timeouts · Max $max per batch';
  }

  @override
  String get wafInterval => 'Request delay';

  @override
  String get wafTimeout => 'Per-request timeout';

  @override
  String get wafMaxProbes => 'Max per batch';

  @override
  String wafNRecords(int count) {
    return '$count';
  }

  @override
  String get wafAll => 'All';

  @override
  String wafResultMeta(String status, int bytes, int ms) {
    return 'HTTP $status · $bytes bytes · $msms';
  }

  @override
  String get wafCopyPayload => 'Copy payload';


  @override
  String get aiNewChat => 'New chat';

  @override
  String get aiClearChatTitle => 'Clear current chat';

  @override
  String get aiClearChatConfirm => 'This clears all messages in the current chat and cannot be undone.';

  @override
  String get aiConversations => 'Conversations';

  @override
  String get aiClearCurrent => 'Clear current';

  @override
  String get aiNewConversation => 'New chat';

  @override
  String aiNMessages(int count) {
    return '$count messages';
  }

  @override
  String get aiCloseAndClear => 'Close and clear this chat';

  @override
  String get aiDeleteChatTitle => 'Delete chat';

  @override
  String get aiDeleteChatConfirm => 'Messages in this chat can\'t be recovered after deletion.';

  @override
  String get aiPickAttachment => 'Choose what to attach';

  @override
  String get aiAttachRequests => 'Captured requests';

  @override
  String get aiAttachRequestsSub => 'Multi-select from the latest 30';

  @override
  String get aiAttachEndpoints => 'API endpoint list';

  @override
  String get aiAttachEndpointsSub => 'Auto-extract all endpoints with stats';

  @override
  String get aiAttachText => 'Custom text';

  @override
  String get aiAttachTextSub => 'Paste anything as context';

  @override
  String get aiNoRequests => 'No captured requests';

  @override
  String get aiPickRequests => 'Choose captured requests (multi-select)';

  @override
  String aiStatus(int code) {
    return 'Status $code';
  }

  @override
  String get aiNoResponse => 'No response';

  @override
  String get aiAttachTextHint => 'Paste anything as context for the AI';

  @override
  String aiAnalyzeFailed(String error) {
    return 'Analysis failed: $error';
  }

  @override
  String get aiTitle => 'AI Analysis';

  @override
  String get aiAgentOn => 'Agent mode on: AI can call ProxyPin features automatically';

  @override
  String get aiAgentOff => 'Agent mode off: only manual messages';

  @override
  String get aiAttachTooltip => 'Attach info (multi-select)';

  @override
  String get aiConvTooltip => 'Conversations (new / switch / delete / clear)';

  @override
  String get aiConfigTooltip => 'AI settings';

  @override
  String get aiThinking => 'AI is thinking…';

  @override
  String get aiInputAgent => 'Ask (Agent mode: AI can fetch data)';

  @override
  String get aiInputPlain => 'Type a question';

  @override
  String get aiEmptyTitle => 'Chat with AI to analyze captured traffic';

  @override
  String get aiEmptyHint1 => 'Tap 📎 at top right to attach requests / endpoint list / text';

  @override
  String get aiEmptyHint2 => 'Turn on 🤖 Agent mode to let AI call ProxyPin features';

  @override
  String aiToolCalled(String name) {
    return 'Called tool $name';
  }

  @override
  String get aiCopied => 'Copied';

  @override
  String get aiConfigTitle => 'AI Analysis Settings';

  @override
  String get aiEnable => 'Enable AI Analysis';

  @override
  String get aiEnableSub => 'OpenAI-compatible API; data is sent to the service you configure';

  @override
  String get aiProvider => 'Provider';

  @override
  String get aiCustomService => 'Custom service…';

  @override
  String get aiBaseUrl => 'Base URL';

  @override
  String get aiBaseUrlHelper => 'Custom provider — enter an OpenAI-compatible URL';

  @override
  String get aiModelLabel => 'Model';

  @override
  String get aiAgentSection => 'Agent mode';

  @override
  String get aiAgentHint2 => 'Once on, AI can call ProxyPin tools to fetch data';

  @override
  String aiMaxRounds(int count) {
    return 'Max tool rounds: $count';
  }

  @override
  String get aiAgentExtra => 'Agent extra instructions';

  @override
  String get aiAgentExtraHint => 'e.g. check security risks first; POST only…';

  @override
  String get aiImportOk => 'Config imported';

  @override
  String aiImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get aiImportFromFile => 'Import config from file (JSON)';

  @override
  String aiJsonFormatHint(String example) {
    return 'JSON format: $example';
  }

  @override
  String get aiConfigSaved => 'AI settings saved';


  @override
  String get quicTitle => 'QUIC Connections';

  @override
  String get quicKeylogTooltip => 'Import a key log (SSLKEYLOGFILE) to enable 1-RTT stream decryption';

  @override
  String get quicCopySessionsTooltip => 'Copy the session list (tab-separated, paste straight into a spreadsheet)';

  @override
  String get quicNoSni => '(no SNI)';

  @override
  String quicPacketsBytes(int packets, String bytes) {
    return '$packets packets / $bytes';
  }

  @override
  String quicLastActivity(String time) {
    return 'Last activity $time';
  }

  @override
  String quicCopiedSessions(int count) {
    return 'Copied $count sessions';
  }

  @override
  String get quicRefreshTooltip => 'Refresh (waiting for new QUIC packets)';

  @override
  String get quicClearRecords => 'Clear records';

  @override
  String get quicClearConfirm => 'Clear all QUIC connection records? Recorded sessions and key logs cannot be restored.';

  @override
  String get quicBannerNoKeylog => 'Only QUIC connection-level metadata is shown (which domains use QUIC and connection stats). HTTP/3 content is encrypted with TLS 1.3 and cannot be decrypted by default; import a key log (SSLKEYLOGFILE) from the key icon at top right and matching connections will automatically decrypt 1-RTT stream data; or turn on Intercept QUIC to force a TCP fallback and capture full requests.';

  @override
  String quicBannerKeylogLoaded(int keys, int connections) {
    return 'Imported $keys keys (covering $connections connections). Matching connections decrypt 1-RTT automatically (client direction only; HEADERS is QPACK-decoded including the dynamic table). For connections that did not match, turn on Intercept QUIC to fall back to TCP.';
  }

  @override
  String get quicNoSniUnresolved => '(SNI not resolved)';

  @override
  String quicSessionSummary(String version, String remote, String firstSeen, String ago) {
    return 'QUIC $version · $remote · first seen $firstSeen · last activity $ago';
  }

  @override
  String quicSessionIds(String dcid, int packets, int frames, String bytes, String decrypted) {
    return 'connection $dcid… · $packets packets / $frames frames · $bytes$decrypted';
  }

  @override
  String quicDecryptedSegments(int count) {
    return ' · $count segments decrypted';
  }

  @override
  String get quicTimelineTitle => 'QUIC packet volume in the last 10 minutes';

  @override
  String get quicTimelineNoData => 'No data';

  @override
  String quicTimelineSummary(int packets, String bytes, int buckets) {
    return '$packets packets · $bytes · traffic in $buckets buckets';
  }

  @override
  String get quicTenMinutesAgo => '10 minutes ago';

  @override
  String get quicPerCellTenSeconds => '10s per cell';

  @override
  String get quicNow => 'Now';

  @override
  String quicImportedNKeys(int keys, int connections) {
    return 'Imported $keys keys, covering $connections connections';
  }

  @override
  String get quicNoNewKeyEntries => 'No new key entries were parsed (make sure the file is in NSS key log format)';

  @override
  String quicImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String quicDecryptedTitle(String host) {
    return '$host · Decrypted content';
  }

  @override
  String quicDecryptedAbout(int segments, String table) {
    return '$segments segments in total (client direction, 1-RTT). HEADERS is QPACK-compressed: static and dynamic table references are both decoded, and the dynamic table is restored in order from this connection\'s QPACK encoder stream$table.';
  }

  @override
  String quicQpackTableUsed(int inserted, int live) {
    return ' ($inserted inserted, $live live)';
  }

  @override
  String get quicQpackTableUnused => ' (this connection does not use the dynamic table)';

  @override
  String quicHttp3Headers(int count) {
    return 'HTTP/3 headers · $count QPACK-decoded entries';
  }

  @override
  String get quicStatConnections => 'Connections';

  @override
  String get quicStatHosts => 'Hosts';

  @override
  String get quicStatPackets => 'Packets';

  @override
  String get quicStatTraffic => 'Traffic';

  @override
  String get quicStatActive => 'Active';

  @override
  String quicSecondsAgo(int seconds) {
    return '$seconds seconds ago';
  }

  @override
  String quicMinutesAgo(int minutes) {
    return '$minutes minutes ago';
  }

  @override
  String quicHoursAgo(int hours) {
    return '$hours hours ago';
  }

  @override
  String get quicEmptyTitle => 'No QUIC connections captured yet';

  @override
  String get quicEmptyDesc => 'After VPN capture is on, when a target app uses QUIC/HTTP3 (video, some social and game apps), its connections are recorded automatically: SNI host, QUIC version, connection ID and packet/frame stats.';

  @override
  String get quicEmptyHint => 'Tip: most apps use TCP/HTTP2 by default. To see QUIC records, temporarily turn Intercept QUIC off in preferences and restart capture; decrypting payloads still requires turning Intercept QUIC on to fall back to TCP.';


  @override
  String pinningDeployDone(String path) {
    return 'Script deployed to $path';
  }

  @override
  String pinningDeployFailed(String reason) {
    return 'Deploy failed: $reason';
  }

  @override
  String get pinningNeedPackage => 'Enter the target package name';

  @override
  String get pinningAttaching => 'Attaching…';

  @override
  String pinningAttached(String result) {
    return 'Attached: $result';
  }

  @override
  String pinningAttachFailed(String result) {
    return 'Attach failed: $result';
  }

  @override
  String get pinningStopDone => 'Injection stopped';

  @override
  String get pinningStopFailed => 'Stop failed';

  @override
  String get pinningTitle => 'SSL Pinning Bypass Helper';

  @override
  String get pinningRefreshEnv => 'Refresh environment';

  @override
  String get pinningAndroidOnly => 'Android only';

  @override
  String get pinningViewLog => 'View log';

  @override
  String get pinningNotice => 'Use only on devices you own and on apps you are authorized to test. Bypassing certificate pinning is runtime intervention into the target process. No third-party binaries (frida-server, Xposed modules) are bundled.';

  @override
  String get pinningEnvTitle => 'Environment';

  @override
  String get pinningChecking => 'checking…';

  @override
  String get pinningReady => 'Ready to attach';

  @override
  String get pinningNotReady => 'Not ready. Need root + frida-inject (recommended) or frida CLI on device. You can still generate the script and run it from a PC.';

  @override
  String get pinningStep1Title => '1. Generate & deploy hook script';

  @override
  String get pinningStep1Hint => 'Covers Conscrypt TrustManagerImpl, SSLContext.init, OkHttp CertificatePinner, HostnameVerifier.';

  @override
  String get pinningDeploy => 'Deploy to device';

  @override
  String get pinningScriptCopied => 'Script copied';

  @override
  String get pinningCopyScript => 'Copy script';

  @override
  String get pinningStep2Title => '2. Attach to target app';

  @override
  String get pinningPackageHint => 'Package name';

  @override
  String get pinningSpawn => 'Spawn mode (app checks on launch)';

  @override
  String get pinningAttach => 'Attach';

  @override
  String get pinningOtherOptions => 'Other options';

  @override
  String get pinningOtherHint => '· First rule out "CA not installed": layer 1 is solved by installing the CA into the system store.\n· With Magisk/LSPosed, a ready-made pinning-bypass module is simpler.\n· Flutter apps use Dart\'s own root list and need separate handling.';

  @override
  String get cloudServerSaved => 'Server URL saved';

  @override
  String get cloudNeedCredentials => 'Enter username and password';

  @override
  String cloudAuthFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get cloudSignedIn => 'Signed in';

  @override
  String get cloudSignedOut => 'Signed out';

  @override
  String get cloudNoLocalWorkspace => 'No local workspace yet';

  @override
  String get cloudPickWorkspace => 'Pick a workspace';

  @override
  String cloudPushFailed(String error) {
    return 'Push failed: $error';
  }

  @override
  String get cloudPushed => 'Pushed to cloud';

  @override
  String get cloudRemoteEmpty => 'Remote workspace is empty';

  @override
  String cloudPulled(int count) {
    return 'Pulled $count requests';
  }

  @override
  String cloudPullFailed(String error) {
    return 'Pull failed: $error';
  }

  @override
  String get cloudDeleteConfirm => 'Remove this workspace copy from the cloud? This cannot be undone.';

  @override
  String get cloudDeleted => 'Removed from cloud';

  @override
  String get cloudRealtimeFailed => 'Realtime connect failed';

  @override
  String get cloudTitle => 'Cloud';

  @override
  String get cloudServer => 'Server';

  @override
  String get cloudServerHint => 'Your own server. A runnable Node implementation ships with the docs.';

  @override
  String get cloudAccount => 'Account';

  @override
  String get cloudSignOut => 'Sign out';

  @override
  String get cloudSignIn => 'Sign in';

  @override
  String get cloudRegister => 'Register';

  @override
  String get cloudRealtime => 'Realtime';

  @override
  String get cloudRealtimeOn => 'Connected — changes from others arrive live';

  @override
  String get cloudRealtimeOff => 'Not connected';

  @override
  String get cloudWorkspaces => 'Cloud workspaces';

  @override
  String get cloudPushLocal => 'Push a local workspace';

  @override
  String get cloudNoRemote => 'Nothing on the server yet';

  @override
  String get cloudPull => 'Pull';

  @override
  String get cloudDeleteRemote => 'Delete on server';

  @override
  String get cloudTeam => 'Team';

  @override
  String get cloudTapRefresh => '(tap refresh)';

  @override
  String get cloudInviteUser => 'Invite user';

  @override
  String cloudInvited(String name) {
    return 'Invited $name';
  }

  @override
  String cloudInviteFailed(String error) {
    return 'Invite failed: $error';
  }

  @override
  String get cloudInvite => 'Invite';


  @override
  String get sslP12FileEmpty => 'The selected file is empty, please choose the .p12 file again';

  @override
  String get sslAutoInstallHint => 'Auto install (needs Root; written as a module, reboot required)\nModern Android keeps /system and /apex read-only, so instead of copying files we install a module';

  @override
  String get sslAutoInstallToSystem => 'Auto install to system';

  @override
  String get sslRemoveSystemCA => 'Remove system CA';

  @override
  String get sslRemoveSystemCAConfirm => 'This deletes the CA written into the system trust store (Magisk module); HTTPS capture will stop working. Continue?';

  @override
  String get sslRemoveInstalledSystemCA => 'Remove installed system CA';

  @override
  String get sslNoModuleManager => 'No Magisk / KernelSU / APatch?';

  @override
  String get sslRuntimeMountDesc => 'Mount the CA into the system trust store via root: a runtime mount that reverts on reboot, fully reversible, no device reboot needed. For rooted devices without a module manager.';

  @override
  String get sslMountToTrustStore => 'Mount to system trust store (root)';

  @override
  String get sslUnmountRuntimeCA => 'Unmount runtime CA';

  @override
  String get sslUnmountRuntimeCAConfirm => 'This unmounts the runtime CA; HTTPS capture will stop working. Continue?';

  @override
  String get sslRestartZygote => 'Restart zygote (apply to running apps)';

  @override
  String get sslAndroid13MountHint => 'Android 13: Mount the certificate to \'/system/etc/security/cacerts\' directory';

  @override
  String get sslAndroid14MountHint => 'Android 14: Mount the certificate to \'/apex/com.android.conscrypt/cacerts\' directory';

  @override
  String get sslAndroidCaInstallNote => 'Note: Pick CA certificate (not VPN and app certificate) during install; on Android 14+ the CA directory lives in APEX, so copying the file alone may not take effect — a bind-mount module is usually required';

  @override
  String get sslNoModuleDirMsg => 'No /data/adb/modules found: this device has no Magisk/KernelSU/APatch. Download the CA and install it as a module manually.';

  @override
  String sslInstallFailedRoot(String output) {
    return 'Install failed ($output). Make sure root is granted.';
  }

  @override
  String get sslModuleInstalled => 'Installed as a Magisk module. Reboot to take effect.';

  @override
  String sslAutoInstallFailedRoot(String error) {
    return 'Auto install failed: $error. Make sure root is granted.';
  }

  @override
  String get sslRemovedReboot => 'Removed. Reboot to take effect.';

  @override
  String get sslRemoveFailedRoot => 'Remove failed. Make sure root is granted.';

  @override
  String sslRemoveFailedError(String error) {
    return 'Remove failed: $error';
  }

  @override
  String get sslMountingGrantRoot => 'Mounting, please grant root when prompted';

  @override
  String get sslMountedTrustStore => 'Mounted into the system trust store (reverts on reboot). Restart the target app, or tap "Restart zygote".';

  @override
  String sslMountFailed(String message) {
    return 'Mount failed: $message';
  }

  @override
  String get sslUnmountedRestored => 'Unmounted. The system trust store is back to its original state.';

  @override
  String sslUnmountFailed(String message) {
    return 'Unmount failed: $message';
  }

  @override
  String get sslZygoteRestarted => 'zygote restart signalled; all apps will restart briefly';

  @override
  String sslZygoteRestartFailed(String message) {
    return 'Restart failed: $message';
  }

  @override
  String get sslCertNotInstalled => 'Certificate Not Installed';

  @override
  String get sslTapInstallRootCA => 'Tap "Install Root CA" to proceed';

  @override
  String get sslCertNotTrusted => 'Certificate Not Trusted';

  @override
  String get sslCertInstalledTrusted => 'Certificate Installed & Trusted';

  @override
  String get sslGuide => 'Guide';


  @override
  String get mcpAutoTitle => 'MCP Automation';

  @override
  String get mcpAutoTutorial => 'Tutorial';

  @override
  String get mcpAutoRefresh => 'Refresh';

  @override
  String get mcpAutoRefreshed => 'Refreshed';

  @override
  String get mcpAutoCancel => 'Cancel';

  @override
  String get mcpAutoSave => 'Save';

  @override
  String get mcpAutoConfirm => 'OK';

  @override
  String get mcpAutoClose => 'Close';

  @override
  String get mcpAutoDelete => 'Delete';

  @override
  String get mcpAutoEdit => 'Edit';

  @override
  String get mcpAutoEnable => 'Enable';

  @override
  String get mcpAutoEnabled => 'Enabled';

  @override
  String get mcpAutoDisabled => 'Disabled';

  @override
  String get mcpAutoName => 'Name';

  @override
  String get mcpAutoDescription => 'Description';

  @override
  String get mcpAutoValue => 'Value';

  @override
  String get mcpAutoEmpty => 'Empty';

  @override
  String get mcpAutoUnnamed => 'Unnamed';

  @override
  String get mcpAutoCustom => 'Custom';

  @override
  String get mcpAutoPriority => 'Priority';

  @override
  String get mcpAutoConditionType => 'Condition type';

  @override
  String get mcpAutoTargetParams => 'Target / parameters (JSON)';

  @override
  String get mcpAutoTabTasks => 'Scheduled tasks';

  @override
  String get mcpAutoTabEvents => 'Event listeners';

  @override
  String get mcpAutoTabRules => 'Rule engine';

  @override
  String get mcpAutoTabWorkflows => 'Workflows';

  @override
  String get mcpAutoStatusChecking => 'Checking…';

  @override
  String get mcpAutoStatusRunning => 'Running';

  @override
  String get mcpAutoStatusStopped => 'Stopped';

  @override
  String get mcpAutoTapToStop => 'Tap to stop MCP automation';

  @override
  String get mcpAutoTapToStart => 'Tap to start MCP automation';

  @override
  String get mcpAutoServiceStartFailed => 'Failed to start the MCP service. Check that the MCP service is enabled in settings.';

  @override
  String get mcpAutoServiceStopped => 'MCP service stopped';

  @override
  String get mcpAutoServiceStarted => 'MCP service started';

  @override
  String get mcpAutoServiceNotStarted => 'MCP service is not running. Start it on the Connection page first.';

  @override
  String get mcpAutoEditRoot => 'Edit Root';

  @override
  String get mcpAutoAddRoot => 'Add Root';

  @override
  String get mcpAutoRootUriHint => 'proxypin://workspace or file:///path/to/dir';

  @override
  String get mcpAutoRootUriRequired => 'Enter the Root URI';

  @override
  String get mcpAutoRootUpdated => 'Root updated';

  @override
  String get mcpAutoRootAdded => 'Root added';

  @override
  String get mcpAutoRootDeleted => 'Root deleted';

  @override
  String get mcpAutoNoRoots => 'No Roots';

  @override
  String get mcpAutoNoRootsHint => 'Tap + at bottom right to add a Root\nAdd a proxypin:// or file:// resource root and edit it freely';

  @override
  String get mcpAutoDeleteRootConfirm => 'Delete this Root configuration?';

  @override
  String mcpAutoReading(String name) {
    return 'Reading $name…';
  }

  @override
  String mcpAutoReadFailed(String error) {
    return 'Read failed: $error';
  }

  @override
  String mcpAutoScriptNotFound(String name) {
    return 'Script not found: $name';
  }

  @override
  String mcpAutoScriptExecuted(String name) {
    return 'Script executed: $name';
  }

  @override
  String mcpAutoScriptRunFailed(String error) {
    return 'Script failed: $error';
  }

  @override
  String get mcpAutoNoTasks => 'No scheduled tasks';

  @override
  String get mcpAutoNoTasksHint => 'Tap + at bottom right to add a task\nPick both the run time and what to run';

  @override
  String get mcpAutoNextPrefix => 'Next: ';

  @override
  String mcpAutoLastRun(String time) {
    return ' • Last run: $time';
  }

  @override
  String mcpAutoRanTimes(int count, int total) {
    return ' • Ran $count/$total times';
  }

  @override
  String get mcpAutoDeleteTaskConfirm => 'Cancel and delete this scheduled task?';

  @override
  String get mcpAutoAddTask => 'Add scheduled task';

  @override
  String get mcpAutoTaskName => 'Task name';

  @override
  String get mcpAutoScheduleMode => 'Schedule mode:';

  @override
  String get mcpAutoModeOnce => 'One-off';

  @override
  String get mcpAutoModeDaily => 'Daily';

  @override
  String get mcpAutoModeWeekly => 'Weekly';

  @override
  String get mcpAutoModeInterval => 'Interval';

  @override
  String get mcpAutoCronLabel => 'Cron expression';

  @override
  String get mcpAutoCronHint => 'min hour day month weekday, e.g. 0 9 * * 1-5';

  @override
  String get mcpAutoCronHelper => 'Supports * , - / wildcards';

  @override
  String get mcpAutoCronRequired => 'Enter a Cron expression';

  @override
  String get mcpAutoCronInvalidHint => 'Invalid expression, please check';

  @override
  String mcpAutoCronNextAt(String time) {
    return 'Next run: $time';
  }

  @override
  String get mcpAutoCronPresetWorkday => '9am on weekdays';

  @override
  String get mcpAutoCronPresetEvery30 => 'Every 30 minutes';

  @override
  String get mcpAutoCronPresetMidnight => 'Every day at midnight';

  @override
  String get mcpAutoExecDateTime => 'Run date & time:';

  @override
  String get mcpAutoExecTime => 'Run time:';

  @override
  String get mcpAutoPickDate => 'Select run date';

  @override
  String get mcpAutoRepeatOn => 'Repeat on:';

  @override
  String get mcpAutoWeekdayMon => 'Mon';

  @override
  String get mcpAutoWeekdayTue => 'Tue';

  @override
  String get mcpAutoWeekdayWed => 'Wed';

  @override
  String get mcpAutoWeekdayThu => 'Thu';

  @override
  String get mcpAutoWeekdayFri => 'Fri';

  @override
  String get mcpAutoWeekdaySat => 'Sat';

  @override
  String get mcpAutoWeekdaySun => 'Sun';

  @override
  String get mcpAutoPickWeekday => 'Select at least one weekday';

  @override
  String get mcpAutoIntervalMinutes => 'Interval (minutes)';

  @override
  String get mcpAutoIntervalMinutesHelp => 'e.g. 30 runs the task every 30 minutes';

  @override
  String get mcpAutoRepeatCount => 'Repeat count';

  @override
  String get mcpAutoRepeatCountHelp => 'e.g. 5 stops after 5 runs; leave empty for unlimited';

  @override
  String get mcpAutoTaskAction => 'Task action:';

  @override
  String get mcpAutoActionScript => 'Run script';

  @override
  String get mcpAutoActionTool => 'Call MCP tool';

  @override
  String get mcpAutoActionWorkflow => 'Run workflow';

  @override
  String get mcpAutoActionWebhook => 'Send Webhook';

  @override
  String get mcpAutoPickScript => 'Select script';

  @override
  String get mcpAutoNoScriptAddFirst => 'No scripts yet, add one on the Scripts page first';

  @override
  String get mcpAutoPickTool => 'Select MCP tool';

  @override
  String get mcpAutoNoTools => 'No tools';

  @override
  String get mcpAutoToolsNeedStart => 'MCP is not running, tools unavailable';

  @override
  String get mcpAutoPickWorkflow => 'Select workflow';

  @override
  String get mcpAutoNoWorkflowAddFirst => 'No workflows yet, add one on the Workflows page first';

  @override
  String get mcpAutoTaskNameRequired => 'Enter a task name';

  @override
  String get mcpAutoIntervalInvalid => 'Enter a valid interval in minutes';

  @override
  String get mcpAutoCronInvalid => 'Invalid Cron expression';

  @override
  String get mcpAutoTaskActionIncomplete => 'Complete the task action configuration';

  @override
  String get mcpAutoTaskAdded => 'Scheduled task added';

  @override
  String get mcpAutoTaskCancelled => 'Task cancelled';

  @override
  String get mcpAutoNoListeners => 'No event listeners';

  @override
  String get mcpAutoNoListenersHint => 'Tap + to register a listener\nLog or run tasks when triggered';

  @override
  String get mcpAutoRemoveListenerConfirm => 'Remove this event listener?';

  @override
  String get mcpAutoEventTypesInfo => 'Event types';

  @override
  String get mcpAutoEventTypesBody => '• HTTP request event: triggered when the URL regex matches\n• Network status event: connected / disconnected / wifi / weak\n• Proxy status event: started / stopped / paused / resumed\n• Capture threshold event: capture count reaches the threshold';

  @override
  String get mcpAutoAddListener => 'Add event listener';

  @override
  String get mcpAutoEventHttp => 'HTTP request event';

  @override
  String get mcpAutoEventNetwork => 'Network status event';

  @override
  String get mcpAutoEventProxy => 'Proxy status event';

  @override
  String get mcpAutoEventCapture => 'Capture threshold event';

  @override
  String get mcpAutoUrlRegex => 'URL regex';

  @override
  String get mcpAutoCaptureThreshold => 'Capture count threshold';

  @override
  String mcpAutoDescHttp(String pattern) {
    return 'HTTP request: $pattern';
  }

  @override
  String mcpAutoDescNetwork(String status) {
    return 'Network status: $status';
  }

  @override
  String mcpAutoDescProxy(String status) {
    return 'Proxy status: $status';
  }

  @override
  String mcpAutoDescCapture(int count) {
    return 'Capture threshold: $count';
  }

  @override
  String get mcpAutoListenerAdded => 'Listener registered';

  @override
  String get mcpAutoListenerRemoved => 'Listener removed';

  @override
  String get mcpAutoNoRules => 'No automation rules';

  @override
  String get mcpAutoNoRulesHint => 'Tap + to add a rule\nRules run actions automatically when conditions match';

  @override
  String mcpAutoRuleSummary(int conditions, int actions, String enabled) {
    return '$conditions conditions • $actions actions • $enabled';
  }

  @override
  String get mcpAutoDeleteRuleConfirm => 'Delete this rule?';

  @override
  String get mcpAutoConditionsInline => 'Conditions:';

  @override
  String get mcpAutoActionsInline => 'Actions:';

  @override
  String get mcpAutoRuleEngineInfo => 'Rule engine';

  @override
  String get mcpAutoRuleEngineInfoBody => '14 condition operators and 8 action types\nRules persist to mcp_rules.json across restarts';

  @override
  String get mcpAutoEditRule => 'Edit rule';

  @override
  String get mcpAutoAddRule => 'Add rule';

  @override
  String get mcpAutoRuleName => 'Rule name';

  @override
  String get mcpAutoSectionConditions => 'Conditions';

  @override
  String get mcpAutoSectionActions => 'Actions';

  @override
  String get mcpAutoRuleNameRequired => 'Enter a rule name';

  @override
  String get mcpAutoRuleUpdated => 'Rule updated';

  @override
  String get mcpAutoRuleAdded => 'Rule added';

  @override
  String get mcpAutoRuleDeleted => 'Rule deleted';

  @override
  String get mcpAutoShortProxy => 'Proxy';

  @override
  String get mcpAutoShortNetwork => 'Network';

  @override
  String get mcpAutoShortSystem => 'System';

  @override
  String get mcpAutoCondTypeHttp => 'HTTP request';

  @override
  String get mcpAutoCondTypeProxy => 'Proxy status';

  @override
  String get mcpAutoCondTypeNetwork => 'Network status';

  @override
  String get mcpAutoCondTypeSystem => 'System status';

  @override
  String get mcpAutoOpContains => 'contains';

  @override
  String get mcpAutoOpStartsWith => 'starts with';

  @override
  String get mcpAutoOpEndsWith => 'ends with';

  @override
  String get mcpAutoOpMatches => 'matches';

  @override
  String get mcpAutoOpInList => 'in list';

  @override
  String get mcpAutoOpNotInList => 'not in list';

  @override
  String get mcpAutoOpExists => 'exists';

  @override
  String get mcpAutoOpNotExists => 'does not exist';

  @override
  String get mcpAutoActLog => 'Log';

  @override
  String get mcpAutoActNotify => 'Notify';

  @override
  String get mcpAutoActStopCapture => 'Stop capture';

  @override
  String get mcpAutoActStartCapture => 'Start capture';

  @override
  String get mcpAutoActExportData => 'Export data';

  @override
  String get mcpAutoFieldMethod => 'Method';

  @override
  String get mcpAutoFieldStatusCode => 'Status code';

  @override
  String get mcpAutoFieldDuration => 'Duration (ms)';

  @override
  String get mcpAutoFieldHost => 'Host';

  @override
  String get mcpAutoFieldPath => 'Path';

  @override
  String get mcpAutoFieldReqContentType => 'Request Content-Type';

  @override
  String get mcpAutoFieldRespContentType => 'Response Content-Type';

  @override
  String get mcpAutoFieldReqSize => 'Request size';

  @override
  String get mcpAutoFieldRespSize => 'Response size';

  @override
  String get mcpAutoFieldType => 'Type';

  @override
  String get mcpAutoFieldTimestamp => 'Timestamp';

  @override
  String get mcpAutoFieldMemory => 'Memory usage (MB)';

  @override
  String get mcpAutoFieldCaptureCount => 'Capture count';

  @override
  String get mcpAutoFieldDisk => 'Disk usage (MB)';

  @override
  String get mcpAutoFieldCpu => 'CPU usage (%)';

  @override
  String get mcpAutoStatusStarted => 'Started';

  @override
  String get mcpAutoStatusPaused => 'Paused';

  @override
  String get mcpAutoStatusResumed => 'Resumed';

  @override
  String get mcpAutoStatusConnected => 'Connected';

  @override
  String get mcpAutoStatusDisconnected => 'Disconnected';

  @override
  String get mcpAutoStatusMobile => 'Mobile data';

  @override
  String get mcpAutoStatusWeak => 'Weak network';

  @override
  String get mcpAutoNoPrompts => 'No Prompts';

  @override
  String get mcpAutoTapInvokePrompt => 'Tap + to invoke a Prompt';

  @override
  String mcpAutoPromptDescWithArgs(String desc, String params) {
    return '$desc\nParameters: $params';
  }

  @override
  String get mcpAutoNoPromptAvailable => 'No Prompts available';

  @override
  String get mcpAutoInvokePrompt => 'Invoke Prompt';

  @override
  String get mcpAutoPromptNoArgs => 'This Prompt takes no arguments';

  @override
  String mcpAutoRequiredArg(String name) {
    return 'Fill in the required argument: $name';
  }

  @override
  String get mcpAutoInvokingPrompt => 'Invoking Prompt…';

  @override
  String get mcpAutoInvoke => 'Invoke';

  @override
  String get mcpAutoNoResult => 'No content returned';

  @override
  String get mcpAutoNoWorkflows => 'No workflows';

  @override
  String get mcpAutoNoWorkflowsHint => 'Tap + to create a workflow\nChain multiple script nodes in order';

  @override
  String get mcpAutoUnnamedWorkflow => 'Unnamed workflow';

  @override
  String mcpAutoNodesCount(int count) {
    return '$count nodes';
  }

  @override
  String get mcpAutoDeleteWorkflowConfirm => 'Delete this workflow?';

  @override
  String get mcpAutoWorkflowDeleted => 'Workflow deleted';

  @override
  String get mcpAutoNoNodes => 'No nodes';

  @override
  String mcpAutoDependsOn(String deps) {
    return 'Depends on: $deps';
  }

  @override
  String get mcpAutoNoDeps => 'No dependencies';

  @override
  String get mcpAutoEditWorkflow => 'Edit workflow';

  @override
  String get mcpAutoAddWorkflow => 'Add workflow';

  @override
  String get mcpAutoWorkflowName => 'Workflow name';

  @override
  String get mcpAutoNodes => 'Nodes';

  @override
  String get mcpAutoTapAddNode => 'Tap + to add a node';

  @override
  String get mcpAutoTopoHint => 'Nodes run in dependency order; dependencies appear as selectable chips.';

  @override
  String get mcpAutoWorkflowNameRequired => 'Enter a workflow name';

  @override
  String get mcpAutoWorkflowUpdated => 'Workflow updated';

  @override
  String get mcpAutoWorkflowAdded => 'Workflow added';

  @override
  String get mcpAutoWorkflowNoNodes => 'The workflow has no nodes';

  @override
  String mcpAutoWorkflowStart(String name) {
    return 'Running workflow: $name';
  }

  @override
  String get mcpAutoWorkflowDone => 'Workflow finished';


  @override
  String get mcpConnSettingsTitle => 'MCP Settings';

  @override
  String get mcpConnAutomationConfig => 'Automation settings';

  @override
  String get mcpConnAllowLanHint => 'Devices on the same network can connect to this device\'s MCP service';

  @override
  String get mcpConnTokenAuth => 'Access token authentication';

  @override
  String get mcpConnTokenAuthRequired => 'Bearer token required (recommended)';

  @override
  String get mcpConnTokenAuthDisabled => 'Disabled: any device on the same network can read captured traffic!';

  @override
  String get mcpConnKeepAlive => 'Background keep-alive';

  @override
  String get mcpConnKeepAliveDesc => 'Add this app to the battery-optimization whitelist and lift background restrictions, so capture and the MCP service are less likely to be killed by the system (requires Shizuku / root / Dhizuku)';

  @override
  String get mcpConnStrictValidation => 'Strict parameter validation';

  @override
  String get mcpConnStrictValidationDesc => 'Validate parameters against each tool\'s declared inputSchema and report call errors early (takes effect immediately)';

  @override
  String get mcpConnTokenNotGenerated => 'Not generated (created automatically once LAN access is enabled)';

  @override
  String get mcpConnTokenCopied => 'Token copied';

  @override
  String get mcpConnRegenerateTokenTooltip => 'Regenerate (the old token stops working immediately)';

  @override
  String mcpConnRegenerateTokenFailed(String error) {
    return 'Failed to regenerate token: $error';
  }

  @override
  String get mcpConnClientCommands => 'AI client connection commands';

  @override
  String get mcpConnClientCommandsSubtitle => 'Claude Code / Codex / curl / one-click scripts';

  @override
  String get mcpConnCurlSelfCheck => 'curl self-check';

  @override
  String get mcpConnOneClickConfigShell => 'One-click setup (shell)';

  @override
  String get mcpConnOneClickConfigPowershell => 'One-click setup (PowerShell)';

  @override
  String get mcpConnNeedLanAccessForToken => '(Enable LAN access first to generate a token)';

  @override
  String get mcpConnAutoStart => 'Auto-start';

  @override
  String get mcpConnServicePort => 'Service port';

  @override
  String get mcpConnConnectionInfo => 'Connection info';

  @override
  String mcpConnProtocolVersion(String version) {
    return 'MCP protocol version: $version (stateless core, compatible with the legacy handshake)';
  }

  @override
  String get mcpConnDeviceIp => 'Device IP';

  @override
  String get mcpConnDeviceIpCopied => 'Device IP copied';

  @override
  String get mcpConnApiUrl => 'API URL (Streamable HTTP)';

  @override
  String get mcpConnApiUrlCopied => 'API URL copied';

  @override
  String get mcpConnSseUrl => 'SSE URL (legacy transport)';

  @override
  String get mcpConnSseUrlCopied => 'SSE URL copied';

  @override
  String get mcpConnHealthCheck => 'Health Check';

  @override
  String get mcpConnHealthCheckUrlCopied => 'Health Check URL copied';

  @override
  String get mcpConnFloatingBall => 'Floating ball';

  @override
  String get mcpConnFloatingBallDesc => 'The desktop floating ball shows MCP status; tap it for a quick panel. The foreground service helps keep the app alive.';

  @override
  String mcpConnFloatingBallColorDesc(String hex, int percent) {
    return 'Color #$hex · Opacity $percent%';
  }

  @override
  String get mcpConnCustomFloatingBall => 'Custom floating ball';

  @override
  String get mcpConnPresetColors => 'Preset colors';

  @override
  String get mcpConnPresetM3Purple => 'M3 Purple';

  @override
  String get mcpConnPresetDeepSeaBlue => 'Deep Sea Blue';

  @override
  String get mcpConnPresetEmeraldGreen => 'Emerald Green';

  @override
  String get mcpConnPresetCoralOrange => 'Coral Orange';

  @override
  String get mcpConnPresetRoseRed => 'Rose Red';

  @override
  String get mcpConnPresetGraphiteBlack => 'Graphite Black';

  @override
  String get mcpConnCustomColorRgb => 'Custom color (RGB)';

  @override
  String mcpConnOpacityPercent(int percent) {
    return 'Opacity $percent%';
  }

  @override
  String get mcpConnConfirm => 'OK';

  @override
  String get mcpConnFloatingBallPermission => 'Floating ball permission';

  @override
  String get mcpConnFloatingBallNeedOverlayPermission => 'The floating ball needs "Display over other apps" permission. System settings has been opened for you; come back and turn it on again after granting it.';

  @override
  String mcpConnFloatingBallStartFailed(String reason) {
    return 'Failed to start the floating ball: $reason';
  }

  @override
  String mcpConnFloatingBallStopFailed(String reason) {
    return 'Failed to stop the floating ball: $reason';
  }

  @override
  String get mcpConnUnknownReason => 'Unknown reason';

  @override
  String get mcpConnFloatingBallStartedHint => 'The floating ball is on. If you cannot see it on screen, check the system "Show floating windows" and the vendor "Background pop-up" permissions.';

  @override
  String mcpConnFloatingBallCallFailed(String error) {
    return 'Floating ball call failed: $error';
  }

  @override
  String get mcpConnOverlayGranted => 'Granted "Display over other apps"';

  @override
  String get mcpConnOverlayNotGranted => 'Not granted — tap to open system settings and enable it, otherwise the floating ball cannot show';

  @override
  String get mcpConnEnableFloatingBall => 'Enable floating ball';

  @override
  String get mcpConnFloatingBallEnabledDesc => 'Show MCP status as a floating window to improve keep-alive';

  @override
  String get mcpConnFloatingBallPermissionRequired => 'Grant the floating ball permission above first';

  @override
  String get mcpConnAutoDock => 'Auto-dock after 3 seconds idle';

  @override
  String get mcpConnAutoDockDesc => 'The floating ball snaps to the screen edge so it does not block the view';

  @override
  String get mcpConnCustomFloatingBallStyle => 'Custom floating ball style';

  @override
  String get mcpConnAiConfigGuide => 'AI configuration guide';

  @override
  String get mcpConnAiConfigGuideDesc => 'Paste the configuration below into your AI client\'s MCP config file and Cursor / Windsurf / Claude Desktop / Cherry Studio and other MCP-capable AI tools can read captured traffic and control ProxyPin. Make sure the phone and the computer are on the same LAN and the MCP service is enabled. The server supports both the latest stateless protocol (2026-07-28) and the legacy handshake protocol.';

  @override
  String get mcpConnAiConfigCopied => 'AI configuration copied';

  @override
  String get mcpConnControlMode => 'Control mode';

  @override
  String get mcpConnCurrentMode => 'Current mode';

  @override
  String get mcpConnAccessibility => 'Accessibility';

  @override
  String get mcpConnAccessibilityService => 'Accessibility service';

  @override
  String get mcpConnRootPermission => 'Root permission';

  @override
  String get mcpConnAvailable => 'Available';

  @override
  String get mcpConnUnavailable => 'Unavailable';

  @override
  String get mcpConnNotGranted => 'Not authorized';

  @override
  String get mcpConnNotEnabled => 'Not enabled';

  @override
  String get mcpConnOpenAccessibilitySettings => 'Open accessibility settings';

  @override
  String get mcpConnShizukuGranted => 'Shizuku authorized';

  @override
  String get mcpConnRequestShizuku => 'Request Shizuku authorization';

  @override
  String get mcpConnShizukuAuthIncomplete => 'Authorization not completed: make sure Shizuku is running, then pick this app in the Shizuku app to authorize it; or choose “Allow” in the dialog';

  @override
  String get mcpConnRootGranted => 'Root authorized';

  @override
  String get mcpConnRequestRoot => 'Request root authorization';

  @override
  String get mcpConnRootAuthIncomplete => 'Authorization not completed: allow it in the Magisk/KernelSU dialog, or make sure the device is rooted';

  @override
  String get mcpConnDhizukuGranted => 'Dhizuku authorized';

  @override
  String get mcpConnRequestDhizuku => 'Request Dhizuku authorization';

  @override
  String get mcpConnDhizukuAuthIncomplete => 'Authorization not completed: make sure Dhizuku is installed and Owner activation is finished';

  @override
  String get mcpConnAvailableTools => 'Available tools';

  @override
  String mcpConnToolCount(int count) {
    return '$count tools';
  }

  @override
  String get mcpConnDisabledToolsHint => 'Disabled tools are hidden from the tool list and cannot be called by AI.';

  @override
  String get mcpConnToolSetConfig => 'Change ProxyPin settings (system proxy, SSL capture toggle)';

  @override
  String get mcpConnToolExportHar => 'Export capture records to a HAR file';

  @override
  String get mcpConnToolImportHar => 'Import a HAR file into capture records';

  @override
  String get mcpConnToolSearchRequests => 'Search requests by URL, method, status code, domain, etc.';

  @override
  String get mcpConnToolGenerateCode => 'Generate code from a request (curl, Python, Go, JavaScript, Node.js)';

  @override
  String get mcpConnToolGetCurl => 'Generate the cURL command for a request';

  @override
  String get mcpConnToolGetRecentRequests => 'Get the list of recently captured requests';

  @override
  String get mcpConnToolGetRequestDetails => 'Get full details of a request (request/response headers and bodies, cookies)';

  @override
  String get mcpConnToolStartProxy => 'Start the proxy service';

  @override
  String get mcpConnToolStopProxy => 'Stop the proxy service';

  @override
  String get mcpConnToolGetProxyStatus => 'Query the proxy service status';

  @override
  String get mcpConnToolClearRequests => 'Clear capture records';

  @override
  String get mcpConnToolReplayRequest => 'Replay a given request';

  @override
  String get mcpConnToolUpdateScript => 'Update the JS script injected into pages';

  @override
  String get mcpConnToolGetScripts => 'Get the list of configured JS scripts';

  @override
  String get mcpConnToolGetStatistics => 'Get capture statistics';

  @override
  String get mcpConnToolCompareRequests => 'Compare the differences between two requests';

  @override
  String get mcpConnToolFindSimilarRequests => 'Find requests similar to a given request';

  @override
  String get mcpConnToolExtractApiEndpoints => 'Extract aggregated API endpoint info from capture records';

  @override
  String get mcpConnToolFindSensitiveData => 'Search requests for sensitive data (passwords, keys, phone numbers, ID numbers, etc.)';

  @override
  String get mcpConnToolGetCookieInfo => 'Analyze a domain\'s cookies (value, HttpOnly, Secure, expiry)';

  @override
  String get mcpConnToolGetDomainSummary => 'Summarize a domain\'s traffic (methods, status codes, average duration, error count)';

  @override
  String get mcpConnToolGetPendingIntercepts => 'List pending requests/responses in the breakpoint queue';

  @override
  String get mcpConnToolApproveIntercept => 'Release a breakpoint intercept (you may edit the request first)';

  @override
  String get mcpConnToolRejectIntercept => 'Reject a breakpoint intercept (abort the request or drop the response)';

  @override
  String get mcpConnToolToggleBreakpoint => 'Enable or disable breakpoint interception';

  @override
  String get mcpConnToolAddWeakNetworkRule => 'Add a weak-network rule (rate limit, delay, etc.)';

  @override
  String get mcpConnToolAddCustomNetworkProfile => 'Add a custom network profile';

  @override
  String get mcpConnToolListWeakNetworkRules => 'List all weak-network rules';

  @override
  String get mcpConnToolRemoveWeakNetworkRule => 'Remove a weak-network rule';

  @override
  String get mcpConnToolToggleWeakNetwork => 'Enable or disable weak-network simulation';

  @override
  String get mcpConnToolListEnvironments => 'List all environments';

  @override
  String get mcpConnToolSetEnvironmentVariable => 'Set an environment variable value';

  @override
  String get mcpConnToolCreateEnvironment => 'Create a new environment';

  @override
  String get mcpConnToolSetActiveEnvironment => 'Switch the active environment';

  @override
  String get mcpConnToolRemoveEnvironment => 'Delete a given environment';

  @override
  String get mcpConnToolToggleEnvironmentVariables => 'Enable or disable environment variables';

  @override
  String get mcpConnToolGetDeviceInfo => 'Get device info (model, OS version, root status)';

  @override
  String get mcpConnToolGetCurrentActivity => 'Get the current foreground activity';

  @override
  String get mcpConnToolDumpUi => 'Export the UI hierarchy tree of the current screen';

  @override
  String get mcpConnToolTapScreen => 'Simulate a tap at screen coordinates';

  @override
  String get mcpConnToolLongPress => 'Simulate a long press at screen coordinates';

  @override
  String get mcpConnToolSwipeScreen => 'Simulate a screen swipe';

  @override
  String get mcpConnToolKeyEvent => 'Send a key event (e.g. back or volume key)';

  @override
  String get mcpConnToolInputText => 'Type text into the current input field';

  @override
  String get mcpConnToolScreenshot => 'Capture the current screen';

  @override
  String get mcpConnToolOpenAccessibilitySettings => 'Open the system accessibility settings page';

  @override
  String get mcpConnToolShell => 'Run a shell command (supports Root/Shizuku/Dhizuku modes)';


  @override
  String get auditPlaintextHttpTitle => 'Sensitive Data Sent Over Plaintext HTTP';

  @override
  String get auditPlaintextHttpDetailUrl => 'This request is sent over plaintext http:// and carries sensitive fields such as passwords / tokens in the URL query string, which a man-in-the-middle can read directly.';

  @override
  String get auditPlaintextHttpDetailBody => 'This request is sent over plaintext http:// and carries sensitive fields such as passwords / tokens in the request body, which a man-in-the-middle can read directly.';

  @override
  String get auditPlaintextHttpSuggestion => 'Use HTTPS; when HTTP is unavoidable, do not carry credentials directly in the URL or request body.';

  @override
  String get auditPlaintextBodyTitle => 'Request Body Sent Over Plaintext HTTP';

  @override
  String get auditPlaintextBodyDetail => 'This request uses http:// and has a request body, so the content is fully plaintext on the wire.';

  @override
  String get auditPlaintextBodySuggestion => 'Enforce HTTPS for endpoints that handle login, payment or privacy.';

  @override
  String get auditUrlSecretTitle => 'Sensitive Parameters in the URL';

  @override
  String auditUrlSecretDetail(String names) {
    return 'Query parameters $names look like credentials / keys. URLs are written into browser history, proxy and server logs.';
  }

  @override
  String get auditUrlSecretSuggestion => 'Move sensitive parameters into the request body or headers (for example Authorization).';

  @override
  String get auditPasswordBodyTitle => 'Password Submitted in a Plaintext Body';

  @override
  String get auditPasswordBodyDetail => 'The request body contains fields such as password / pwd with plaintext values.';

  @override
  String get auditPasswordBodySuggestion => 'Keep the whole path on HTTPS and make sure the server never echoes or logs passwords.';

  @override
  String get auditCookieFlagTitle => 'Cookie Missing Security Attributes';

  @override
  String auditCookieFlagDetail(String name, String missing) {
    return 'Set-Cookie "$name" is missing $missing, so it can be read by scripts or transmitted in cleartext.';
  }

  @override
  String get auditCookieFlagSuggestion => 'Add Secure and HttpOnly to session cookies, and set SameSite=Lax/Strict as needed.';

  @override
  String get auditMissingHeadersTitle => 'HTML Response Missing Security Headers';

  @override
  String auditMissingHeadersDetail(String missing) {
    return 'Missing $missing; the browser has no extra constraint against content sniffing and script injection.';
  }

  @override
  String get auditMissingHeadersSuggestion => 'Add security response headers such as nosniff and CSP as needed.';

  @override
  String get auditFingerprintTitle => 'Response Exposes Server Fingerprint';

  @override
  String auditFingerprintDetail(String header, String value) {
    return '$header: $value, which helps an attacker pick known vulnerabilities.';
  }

  @override
  String get auditFingerprintSuggestion => 'Hide or generalize version information at the gateway.';

  @override
  String get auditPrivateKeyTitle => 'Response Body May Contain a Private Key';

  @override
  String get auditPrivateKeyDetail => 'A PEM private key marker appears in the response; if it is a real key, this is a severe leak.';

  @override
  String get auditPrivateKeySuggestion => 'Rotate the key immediately and make sure the server never sends private keys to clients.';

  @override
  String get auditSecretTitle => 'Response Body Returns Secret Fields in Plaintext';

  @override
  String auditSecretDetail(String names) {
    return 'Fields such as $names are returned in plaintext.';
  }

  @override
  String get auditSecretSuggestion => 'Return the minimum set of fields; key material should never be sent to clients.';

  @override
  String get auditPiiTitle => 'Response Body Contains Personal Information';

  @override
  String auditPiiDetail(String names) {
    return 'Fields such as $names carry personal data such as ID numbers / phone numbers.';
  }

  @override
  String get auditPiiSuggestion => 'Mask personal data or return it on a minimal-necessary basis, and comply with data protection requirements.';

  @override
  String get auditErrorTitle => 'Error Response Leaks Internal Information';

  @override
  String auditErrorDetail(String trace) {
    return 'Debug / stack trace signatures ($trace) appear in the response, which may expose the framework, paths or database structure.';
  }

  @override
  String get auditErrorSuggestion => 'Disable detailed errors in production and return a generic error message.';

  @override
  String get auditCorsTitle => 'CORS Allows Any Origin with Credentials';

  @override
  String get auditCorsDetail => 'Access-Control-Allow-Origin is * while Allow-Credentials is true, so the risk of cross-site credential reads is high.';

  @override
  String get auditCorsSuggestion => 'Restrict allowed origins to a fixed allowlist and avoid * together with Allow-Credentials.';

  @override
  String get auditJwtNoneTitle => 'JWT Uses alg=none (Unsigned)';

  @override
  String get auditJwtNoneDetail => 'The token declares algorithm none, so anyone can tamper with the payload and it cannot be verified.';

  @override
  String get auditJwtNoneSuggestion => 'Enforce signature algorithm validation on the server and reject alg=none.';

  @override
  String get auditJwtExpiryTitle => 'JWT Has No Expiry';

  @override
  String get auditJwtExpiryDetail => 'The token payload has no exp field, so it stays valid forever after being issued.';

  @override
  String get auditJwtExpirySuggestion => 'Set a reasonable expiry for tokens and support refresh.';

  @override
  String get auditHttp10Title => 'Uses Outdated HTTP/1.0';

  @override
  String get auditHttp10Detail => 'This connection uses HTTP/1.0, whose connection reuse and caching strategy is outdated.';

  @override
  String get auditHttp10Suggestion => 'Upgrade to HTTP/1.1 or HTTP/2.';

  @override
  String get auditSqlTitle => 'Possible SQL Injection Trace (Database Error Echoed)';

  @override
  String auditSqlDetail(String signature) {
    return 'The response contains a $signature database error signature, which means this endpoint echoes SQL errors back to the caller; if client-controlled parameters triggered it, there is a SQL injection risk.';
  }

  @override
  String get auditSqlSuggestion => 'Use parameterized queries / prepared statements and never concatenate SQL; disable detailed database errors in production and return a generic message. (Passive detection: based only on the response characteristics of captured traffic; no probe request was sent.)';

  @override
  String get auditXssTitle => 'Possible XSS Reflection Trace (Unencoded Parameters Echoed in HTML)';

  @override
  String auditXssDetail(String meta) {
    return 'The response echoes request parameter values verbatim into HTML without HTML entity encoding, and the echoed content contains special characters such as $meta; if an attacker can control that value, the browser may parse it as tags or script.';
  }

  @override
  String get auditXssSuggestion => 'Encode according to the output context (HTML entity encoding) and pair the page with CSP; do not concatenate request parameters into HTML. (Passive detection: based only on the response characteristics of captured traffic; no probe request was sent.)';

  @override
  String auditCustomHitDetail(String name, String describe) {
    return 'Matched custom rule "$name" ($describe).';
  }

  @override
  String get auditCustomHitSuggestion => 'Confirm against your business security requirements whether this content should appear.';

  @override
  String get auditSecretPrivateKey => 'Private key';

  @override
  String get auditPiiIdCard => 'ID number';

  @override
  String get auditPiiPhone => 'Phone number';

  @override
  String auditRuleDescribe(String target, String match) {
    return 'Scope: $target; Match: $match';
  }

  @override
  String get auditTargetUrl => 'Request URL';

  @override
  String get auditTargetRequestHeader => 'Request headers';

  @override
  String get auditTargetRequestBody => 'Request body';

  @override
  String get auditTargetResponseHeader => 'Response headers';

  @override
  String get auditTargetResponseBody => 'Response body';

  @override
  String get auditTargetAny => 'Everything';

  @override
  String get auditMatchKeyword => 'Keyword';

  @override
  String get auditMatchRegex => 'Regex';

  @override
  String get diagSummaryOk => 'Capture path is basically ready';

  @override
  String get diagSummaryIssues => 'Problems that affect capture were detected; see the error items in items';

  @override
  String get diagSuggestStartProxy => 'Start the capture service first (call the start_proxy tool, or have the user tap Start Capture in the UI)';

  @override
  String get diagSuggestInstallCert => 'Install and trust the root certificate: without HTTPS trust you will see batches of handshake failures (the exclamation-mark packets in the list)';

  @override
  String get diagSuggestSystemProxy => 'The system proxy does not point to this app: have the user enable the system proxy in Preferences, or check whether another proxy tool has taken it over';

  @override
  String get diagSuggestPinning => 'Domains that look like they pin certificates: such apps need runtime intervention on the device to decrypt, and the common approach is a hook framework (for example LSPosed with a module like TrustMeAlready). Note that this interferes with the target app and should only be done on your own device and within the scope you are authorized for';

  @override
  String get diagSuggestNoTraffic => 'No new traffic right now: trigger a request in the app or browser being captured, then let the AI read the session list';

  @override
  String get diagSuggestChecklist => 'If everything above looks fine but you still capture nothing, check these categories: ① the target uses QUIC/HTTP3 (enable Block QUIC on the phone, disable QUIC in the browser); ② Flutter apps (Dart ships its own root CA list and does not read the system CA); ③ the app enables certificate pinning (SSL Pinning) - matched if an SSL Certificate Pinning (suspected) item appears above; ④ processes with their own network stack on Windows (need Enhanced Windows Takeover or a TUN tool); ⑤ Mac App Store sandboxed apps (need Network Extension/TUN; unsigned builds from this repository cannot take over)';

  @override
  String get diagItemProxyService => 'Proxy Service';

  @override
  String diagProxyListening(int port) {
    return 'Listening on 127.0.0.1:$port';
  }

  @override
  String get diagProxyNotRunning => 'Not running, so no traffic can be captured. Tap Start Capture first';

  @override
  String get diagItemSystemProxy => 'System Proxy';

  @override
  String diagSystemProxyMatched(String host, int port) {
    return 'Points to this app at $host:$port';
  }

  @override
  String get diagSystemProxyOff => 'The system proxy is off, so app traffic will not go through this tool';

  @override
  String diagSystemProxyMismatch(String host, int port, int expected) {
    return 'Points to $host:$port, which does not match this app port $expected (maybe taken over by another proxy tool, or left over from an abnormal exit)';
  }

  @override
  String get diagItemTrafficEntry => 'Traffic Entry';

  @override
  String get diagMobileVpnEntry => 'On mobile, the VPN tunnel handles IP-layer traffic (no system proxy needed)';

  @override
  String get diagCaInSystemStore => 'Already in the system trust store';

  @override
  String get diagCaUserStore => 'Only in the user certificate store: since Android 7 apps do not trust user certificates by default, you may see "certificate installed but HTTPS cannot be captured or reports an error". To take effect for all apps it must be installed into the system certificate directory with root (on Android 14+ that is /apex/com.android.conscrypt/cacerts), or configure network_security_config for the target app';

  @override
  String get diagCaInstalledUnknown => 'Installed (cannot distinguish the system store from the user store)';

  @override
  String get diagCaMissingAndroid => 'Root certificate not detected: go to HTTPS Certificate -> Install Root Certificate and follow the guide; choose CA certificate rather than VPN and app certificate during installation';

  @override
  String get diagCaMissingDesktop => 'Root certificate not detected; HTTPS will fail the handshake (seen as batches of exclamation-mark packets in the list)';

  @override
  String get diagItemCaRoot => 'CA Root Certificate';

  @override
  String get diagCaDesktopHint => 'On desktop, confirm in the Certificate page that the root certificate is installed into the system trusted roots';

  @override
  String diagReadFailed(String error) {
    return 'Read failed: $error';
  }

  @override
  String get diagItemSslPinning => 'SSL Certificate Pinning (suspected)';

  @override
  String diagSslPinningDetail(int count, String sample) {
    return 'The CA certificate is ready, but $count domains only established a TLS tunnel and their content is never readable: $sample. This usually means the peer enabled certificate pinning (SSL Pinning), or ships its own root CA list and does not read the system CA. Note that these apps are not offline: they rejected the certificate of this tool and therefore closed the connection.';
  }

  @override
  String get diagItemWinTakeover => 'Enhanced Windows Takeover';

  @override
  String get diagWinTakeoverOn => 'On: the WinHTTP service and CLI tools (curl/git/node) also go through the proxy';

  @override
  String get diagWinTakeoverOff => 'Off: apps with their own network stack, the WinHTTP service and CLI tools may not be captured. Enable it in Preferences -> Windows Takeover (the WinHTTP part requires administrator rights)';

  @override
  String get diagItemRecentTraffic => 'Recent Traffic';

  @override
  String get diagNoRequests => 'No requests captured in this session yet';

  @override
  String diagTrafficFresh(int count, int ago) {
    return '$count requests, latest $ago seconds ago';
  }

  @override
  String diagTrafficStale(int count, int ago) {
    return '$count requests, latest $ago seconds ago (no new traffic coming in)';
  }

  @override
  String get diagItemExtensionMemory => 'Extension Memory';

  @override
  String get diagExtMemUnavailable => 'Not available (the extension process cannot be read while the VPN is stopped)';

  @override
  String diagExtMemDetail(String rss, String peak, String connections, String buffered) {
    return 'Current $rss MB, peak $peak MB, $connections connections, $buffered MB buffered';
  }

  @override
  String get diagExtMemNearLimit => ' (approaching the extension memory limit; consider reducing concurrency or lowering the buffered-send cap)';


  @override
  String get auditPageVerifyTooltip => 'Active verification (one request per captured domain, checking security headers)';

  @override
  String get auditPageNoVerifiableHosts => 'No verifiable domains captured yet';

  @override
  String get auditPageVerifyTitle => 'Active verification';

  @override
  String get auditPageVerifyIntro => 'It sends one GET each to the domains below that **already appeared in the captured traffic**, looking only at the security response headers:';

  @override
  String auditPageVerifyScope(int hosts, int delay, int max) {
    return '$hosts domains in total, sent one after another with a \$$delayms gap, up to $max. No port scanning, no payloads.';
  }

  @override
  String get auditPageVerifyAuthz => 'Only do this for targets you own or are authorized to test.';

  @override
  String get auditPageVerifyStart => 'Start verification';

  @override
  String auditPageVerifyFailed(String error) {
    return 'Verification failed: $error';
  }

  @override
  String get auditPageVerifyResultTitle => 'Verification results';

  @override
  String get auditPageVerifyResultIntro => 'This only checked whether the security response headers below are present. Missing does not mean a vulnerability, but the server configuration is worth a look.';

  @override
  String auditPageVerifyHostFailed(String host, String error) {
    return '$host — verification failed: $error';
  }

  @override
  String get auditPageVerifyHeadersAllPresent => 'All of these response headers are present';

  @override
  String auditPageVerifyHeaderMissing(String name, String desc) {
    return 'Missing $name — $desc';
  }

  @override
  String get diagPageRerun => 'Re-run';

  @override
  String get diagPageTip => 'Checks whether the local capture path works. Read-only detection; it never changes your system settings. The same conclusion can be handed to AI via the MCP tool diagnose_capture.';

  @override
  String get diagPageNextSteps => 'Start here';

  @override
  String get diagPageCauseQuicTitle => 'Targets that use QUIC / HTTP3';

  @override
  String get diagPageCauseQuicDesc => 'Enable "Block QUIC" on the phone so the app falls back to TCP; on desktop browsers, disable QUIC in chrome://flags and retry';

  @override
  String get diagPageCauseFlutterTitle => 'Flutter apps';

  @override
  String get diagPageCauseFlutterDesc => 'Dart ships its own root CA list and does not read the system CA, so HTTPS stays unreadable even with a certificate installed. Trust it inside the app, or capture its network library calls instead';

  @override
  String get diagPageCausePinningTitle => 'Apps with certificate pinning (SSL Pinning) enabled';

  @override
  String get diagPageCausePinningDesc => 'The app has a certificate fingerprint built in, so MITM is rejected and you see waves of handshake failures (exclamation-mark packets)';

  @override
  String get diagPageCauseWinStackTitle => 'Processes on Windows with their own network stack';

  @override
  String get diagPageCauseWinStackDesc => 'The system proxy cannot reach them. Use "Preferences → Enhanced Windows Takeover"; if that still fails, put ProxyPin behind a TUN-capable tool';

  @override
  String get diagPageCauseMasTitle => 'Apps from the Mac App Store';

  @override
  String get diagPageCauseMasDesc => 'Sandboxed and strictly signed, the system proxy is ineffective and Network Extension/TUN is required (unsigned builds from this repository cannot do it)';

  @override
  String get diagPageCauseProxyIgnoredTitle => 'Proxy changed but the app ignores it';

  @override
  String get diagPageCauseProxyIgnoredDesc => 'Switch to the app\'s own proxy settings, or take over uniformly with a TUN-capable tool';

  @override
  String get diagPageCommonCausesTitle => 'Nothing captured? Match your case below';


  @override
  String get mcpConnDeskClientWizard => 'Client connection wizard (Claude Code / Codex / Cursor)';

  @override
  String get mcpConnDeskPortConfig => 'Port settings';

  @override
  String get mcpConnDeskServicePort => 'MCP service port';

  @override
  String get mcpConnDeskIpAddress => 'IP Address';

  @override
  String get mcpConnDeskAiConfigHint => 'Add the following configuration to your AI tool (such as Cursor, Windsurf, etc.):';

  @override
  String get mcpConnDeskConfigCopied => 'Configuration copied';

  @override
  String get mcpConnDeskCopyConfig => 'Copy config';

  @override
  String get mcpConnDeskControlModeDesc => 'ProxyPin MCP supports two connection methods:';

  @override
  String get mcpConnDeskModeMcpTitle => 'MCP (recommended)';

  @override
  String get mcpConnDeskModeMcpDesc => 'Standard MCP protocol with full features';

  @override
  String get mcpConnDeskModeSseDesc => 'Server-Sent Events, compatible with legacy clients';


  @override
  String get prefSplashTitle => 'Splash Screen';

  @override
  String get prefSplashDesc => 'Uses the system splash screen by default; you can switch to a custom branded page';

  @override
  String get prefSplashBackground => 'Background';

  @override
  String get prefSplashBgOff => 'Original splash (default)';

  @override
  String get prefSplashBgGradient => 'Gradient branded page';

  @override
  String get prefSplashBgCustom => 'Custom image';

  @override
  String get prefSplashBgTransparent => 'Follow theme (recommended)';

  @override
  String get prefSplashDuration => 'Display duration';

  @override
  String prefSplashDurationSeconds(String seconds) {
    return '$seconds s';
  }

  @override
  String get prefSplashDurationFixed => 'The original splash screen is a system screen and does not support a custom duration';

  @override
  String get prefSplashNotSelected => 'Not selected';

  @override
  String get prefSplashSelectedTapChange => 'Set, tap to change';

  @override
  String get prefSplashSubtitleLabel => 'Custom caption';

  @override
  String get prefSplashSubtitleDefault => 'Shows version info by default';

  @override
  String get prefSplashSubtitleUnsupported => 'The original splash screen does not support a custom caption; switch to gradient/transparent to enable it';

  @override
  String get prefSplashSubtitleField => 'Caption text';

  @override
  String get prefSplashSubtitleHint => 'Leave empty to restore the default (version info)';

  @override
  String get prefMtls => 'Mutual TLS (mTLS)';

  @override
  String get prefMtlsChainLabel => 'Client certificate chain (PEM)';

  @override
  String get prefMtlsKeyLabel => 'Client private key (PEM, unencrypted)';

  @override
  String get prefMtlsHint => 'The certificate chain contains -----BEGIN CERTIFICATE-----, and the private key contains -----BEGIN PRIVATE KEY----- (encrypted keys are not supported). Applies to newly established HTTPS connections after configuration.';

  @override
  String get prefMtlsSelectBoth => 'Select the certificate chain and private key files first';

  @override
  String get prefMtlsChainInvalid => 'Incorrect certificate chain format (PEM required)';

  @override
  String get prefMtlsKeyInvalid => 'Incorrect private key format (unencrypted PEM required)';

  @override
  String get prefMtlsLoadFailed => 'Failed to load the certificate; check the file contents';

  @override
  String get prefMtlsEnabled => 'mTLS enabled';

  @override
  String get prefRootDenied => 'Root permission not granted; system-level fallback cannot run';

  @override
  String get prefSysFallbackOn => 'System-level fallback enabled: UDP:443 will be dropped (stops working after a system reboot)';

  @override
  String get prefSysFallbackOff => 'System-level fallback disabled';

  @override
  String prefExecFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get prefIptablesUnavailable => 'iptables unavailable';

  @override
  String get prefMonet => 'Monet theming';

  @override
  String get prefMonetDesc => 'Android 12+: colors follow the wallpaper (theme and splash screen pick colors automatically)';

  @override
  String get prefPredictiveBack => 'Predictive back';

  @override
  String get prefPredictiveBackDesc => 'Android 14+ predictive back gesture animation (Material 3 page transitions)';

  @override
  String get prefCaptureBodyLimit => 'Capture body limit';

  @override
  String get prefBlockQuic => 'Intercept QUIC (UDP:443)';

  @override
  String prefQuicBlocked(int count) {
    return 'Intercepted $count QUIC packets; forcing a fallback to TCP so traffic can be captured';
  }

  @override
  String get prefQuicBlockDesc => 'Drop UDP 443 to force apps back to TCP so HTTPS traffic can be captured';

  @override
  String get prefQuicBlockOff => 'Turned off; takes effect after restarting capture';

  @override
  String get prefSysFallbackDesc => 'System-level fallback (requires Root + iptables): drop all UDP:443 to force a fallback to TCP; stops working after a system reboot';

  @override
  String get prefDisable => 'Turn off';

  @override
  String get prefMtlsEnabledTapConfig => 'Enabled · tap to configure the client certificate';

  @override
  String get prefMtlsDesc => 'Provide a client certificate (PEM) during the TLS handshake with the upstream server';

  @override
  String get prefRootMode => 'Root-mode capture';

  @override
  String get prefRootModeDesc => 'Redirect the outbound traffic of the system to the local proxy with root privileges, bypassing apps that refuse to connect when a VPN is detected; the device must be rooted and this is mutually exclusive with VPN capture';

  @override
  String get prefWanUnit => '0K';

  @override
  String get cfgManagement => 'Config Management';

  @override
  String get cfgManagementDesc => 'Import/export config, back up or restore settings';

  @override
  String get cfgExport => 'Export Config';

  @override
  String get cfgExportDesc => 'Export the current config as a JSON file for backup or sharing';

  @override
  String get cfgImport => 'Import Config';

  @override
  String get cfgImportDesc => 'Import config from a JSON file; the current config will be overwritten';

  @override
  String get cfgCopyToClipboard => 'Copy config to clipboard';

  @override
  String get cfgCopyToClipboardDesc => 'Generate config text; paste it on another device to import (no file transfer needed)';

  @override
  String get cfgImportFromClipboard => 'Import config from clipboard';

  @override
  String get cfgImportFromClipboardDesc => 'Read the config text from the clipboard; the current config will be overwritten';

  @override
  String get cfgBackupDesc => 'View, restore or delete automatically backed-up config files';

  @override
  String get cfgNotice => 'Notes';

  @override
  String get cfgNoticeBody => '• Exporting includes all proxy settings, filter rules, MCP config and more\n• Importing completely overwrites the current config, so proceed with care\n• Exporting the config regularly as a backup is recommended\n• The config file is in JSON format and can be viewed in a text editor';

  @override
  String get cfgExporting => 'Exporting config';

  @override
  String get cfgExportPreparing => 'Please wait, preparing the export file...';

  @override
  String get cfgPreparing => 'Preparing...';

  @override
  String get cfgSelectSaveLocation => 'Choose save location';

  @override
  String cfgExportedTo(String path) {
    return 'Config exported to: $path';
  }

  @override
  String cfgExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get cfgConfirmImport => 'Confirm import';

  @override
  String get cfgImportConfirmBody => 'Importing the config will completely overwrite the current config. Continue?\n\nExporting the current config as a backup first is recommended.';

  @override
  String get cfgImportSuccessRestart => 'Config imported successfully; some settings may need an app restart to take effect';

  @override
  String cfgImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get cfgCopied => 'Config copied to the clipboard; paste it on another device to import';

  @override
  String cfgCopyFailed(String error) {
    return 'Copy failed: $error';
  }

  @override
  String get cfgImportConfirmBodyShort => 'Importing will overwrite the current config. Continue?';

  @override
  String get cfgClipboardEmpty => 'There is no text in the clipboard';

  @override
  String get cfgClipboardNotConfig => 'The clipboard content is not config JSON; copy the config text first';


  @override
  String get devToolCron => 'Cron expression';

  @override
  String get devToolJwt => 'JWT decode';

  @override
  String get devToolSha => 'SHA hash';

  @override
  String get devToolCronExampleWorkday => '9 AM on weekdays';

  @override
  String get devToolCronExampleMonthly => '8:30 on the 1st of each month';

  @override
  String get devToolCronExampleMidnight => 'Midnight every day';

  @override
  String get devToolCronExampleEvery15Min => 'Every 15 minutes';

  @override
  String get devToolCronExampleEvery2Hours => 'Every 2 hours';

  @override
  String get devToolCronExampleMondayNoon => 'Noon every Monday';

  @override
  String get devToolCronParseError => 'Cannot parse this expression; check each field';

  @override
  String get devToolCronHint => 'min hour day month weekday';

  @override
  String get devToolCronParse => 'Parse';

  @override
  String get devToolCronNextRuns => 'Next 6 run times';

  @override
  String get devToolCronFieldHelp => 'Field reference';

  @override
  String get devToolCronWildcardHint => 'Wildcards: * any  ·  , list  ·  - range  ·  / step';

  @override
  String get devToolCronExamples => 'Common examples (tap to fill)';

  @override
  String get devToolCronFieldMinute => 'Minute';

  @override
  String get devToolCronFieldHour => 'Hour';

  @override
  String get devToolCronFieldDay => 'Day';

  @override
  String get devToolCronFieldMonth => 'Month';

  @override
  String get devToolCronFieldWeek => 'Weekday';

  @override
  String get devToolCronFieldWeekRange => '0-6 (0 is Sunday)';

  @override
  String get devToolJwtInvalid => 'A JWT should have at least two Base64Url segments (header.payload.signature)';

  @override
  String devToolJwtDecodeFailed(String error) {
    return 'Decode failed: $error';
  }

  @override
  String devToolJwtExpiry(String time, String status) {
    return '$time ($status)';
  }

  @override
  String devToolJwtExpLabel(String time) {
    return 'Expires at: $time';
  }

  @override
  String get devToolJwtExpired => 'expired';

  @override
  String get devToolJwtValid => 'valid';

  @override
  String get devToolJwtLabel => 'Paste a JWT token';

  @override
  String get devToolJwtHint => 'You can paste an Authorization value with the Bearer prefix';

  @override
  String get devToolUuidCount => 'Count';

  @override
  String get devToolUuidUppercase => 'Uppercase';

  @override
  String get devToolUuidGenerate => 'Generate UUID v4';

  @override
  String get devToolUuidEmpty => 'Tap the button above to generate';

  @override
  String get devToolCopiedAll => 'Copied all';

  @override
  String get devToolCopyAll => 'Copy all';

  @override
  String get devToolShaInput => 'Input text';

  @override
  String get devToolShaNote => 'Computed over UTF-8; to verify files/binary, use the hex tool on captured traffic.';

  @override
  String get calcTitle => 'Calculator';

  @override
  String get calcTabIntConvert => 'Radix / Two\'s complement';

  @override
  String get calcTabBitwise => 'Bitwise';

  @override
  String get calcTabEndian => 'Endianness';

  @override
  String get calcTabCrcHash => 'CRC / Hash';

  @override
  String get calcEmptyHint => 'Enter a value and tap "Calculate" to see the result';

  @override
  String calcCopiedKey(String name) {
    return 'Copied $name';
  }

  @override
  String get calcCompute => 'Calculate';

  @override
  String get calcLabelValue => 'Value';

  @override
  String get calcIntValueHint => 'Accepts 0x / 0b / 0o / decimal, optional leading minus';

  @override
  String get calcLabelWidth => 'Bit width';

  @override
  String calcNBits(int bits) {
    return '$bits bits';
  }

  @override
  String get calcLabelOperation => 'Operation';

  @override
  String get calcLabelOperandA => 'Operand A';

  @override
  String get calcLabelShiftAmount => 'Shift amount (decimal)';

  @override
  String get calcLabelOperandB => 'Operand B';

  @override
  String get calcHintShiftExample => 'e.g. 4';

  @override
  String get calcHintOperandBExample => 'e.g. 0x0FF0';

  @override
  String get calcLabelHexData => 'Hex data';

  @override
  String get calcHintHexDataExample => 'e.g. 0x78563412';

  @override
  String get calcLabelByteWidth => 'Byte width';

  @override
  String get calcByteWidthAuto => 'Match input length';

  @override
  String calcNBytes(int bytes) {
    return '$bytes bytes';
  }

  @override
  String get calcLabelMachineOrValue => 'Machine code or number';

  @override
  String get calcIeeeHint => 'Hex machine code (e.g. 0x3f800000) or a decimal fraction (e.g. 1.5)';

  @override
  String get calcLabelPrecision => 'Precision';

  @override
  String get calcLabelAlgorithm => 'Algorithm';

  @override
  String get calcLabelInputFormat => 'Input format';

  @override
  String get calcLabelData => 'Data';


  @override
  String get wsPageTitle => 'Workspaces';

  @override
  String get wsPageNew => 'New workspace';

  @override
  String get wsPageNameHint => 'Name (e.g. "Payment module", "Test env")';

  @override
  String get wsPageRenameTitle => 'Rename workspace';

  @override
  String get wsPageDeleteTitle => 'Delete workspace';

  @override
  String wsPageDeleteConfirm(String name) {
    return 'Delete "$name" and its local data? This cannot be undone.';
  }

  @override
  String get wsPageNoCaptureData => 'No captured requests to save';

  @override
  String wsPageSavedTo(int count, String name) {
    return 'Saved $count to "$name"';
  }

  @override
  String wsPageSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get wsPageEmptyWorkspace => 'Workspace is empty';

  @override
  String wsPageImportedToHistory(int count) {
    return 'Imported $count requests to history';
  }

  @override
  String wsPageImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get wsPageServerTitle => 'Workspace server';

  @override
  String get wsPageServerUrlHint => 'Base URL (e.g. http://10.0.0.5:8787)';

  @override
  String get wsPageTokenTitle => 'Token (optional)';

  @override
  String get wsPageServerSaved => 'Server config saved';

  @override
  String get wsPageServerCleared => 'Server config cleared';

  @override
  String get wsPageServerNeeded => 'Configure the workspace server first';

  @override
  String wsPagePushed(int bytes) {
    return 'Pushed to server ($bytes bytes)';
  }

  @override
  String wsPagePushFailed(String error) {
    return 'Push failed: $error';
  }

  @override
  String get wsPageServerNoWorkspaces => 'Server has no workspaces';

  @override
  String wsPagePulled(int count) {
    return 'Pulled $count workspaces';
  }

  @override
  String wsPagePullFailed(String error) {
    return 'Pull failed: $error';
  }

  @override
  String get wsPageServerTooltip => 'Server settings';

  @override
  String get wsPagePullFromServer => 'Pull from server';

  @override
  String get wsPageEmptyHint => 'No workspace yet. Create one, save the current capture into it, and manage captures per project.';

  @override
  String get wsPageCustomServer => 'Custom server';

  @override
  String get wsPageServerNotConfiguredHint => 'Not configured. Only needed if you want to share/backup to your own server.';

  @override
  String get wsPageSaveCurrent => 'Save current capture';

  @override
  String get wsPageImportToHistory => 'Import to history';

  @override
  String get wsPagePushToServer => 'Push to server';

  @override
  String wsPageItemMeta(int count, String time) {
    return '$count requests · $time';
  }

  @override
  String get logViewReadyHint => 'Log viewer is ready: runtime logs will show up here in real time (up to 500 entries).';

  @override
  String get logViewExportSuccess => 'Logs exported';

  @override
  String get logViewExportFailed => 'Log export failed';

  @override
  String logViewExportError(String error) {
    return 'Export failed: $error';
  }

  @override
  String get logViewClearLogs => 'Clear logs';

  @override
  String get logViewClearConfirm => 'Clear all logs? This cannot be undone.';

  @override
  String get logViewCleared => 'Logs cleared';

  @override
  String get logViewTitle => 'Log management';

  @override
  String get logViewTapToPause => 'Recording, tap to pause';

  @override
  String get logViewTapToResume => 'Paused, tap to resume';

  @override
  String get logViewRecordingResumed => 'Log recording enabled';

  @override
  String get logViewRecordingPaused => 'Log recording paused';

  @override
  String get logViewMore => 'More';

  @override
  String get logViewSearchLogs => 'Search logs';

  @override
  String get logViewExportLogs => 'Export logs';

  @override
  String get logViewNoLogs => 'No logs yet';

  @override
  String get logViewStatTotal => 'Total';

  @override
  String get logViewStatDebug => 'Debug';

  @override
  String get logViewStatInfo => 'Info';

  @override
  String get logViewStatWarning => 'Warning';

  @override
  String get logViewStatError => 'Error';

  @override
  String get logViewTime => 'Time';

  @override
  String get logViewTag => 'Tag';

  @override
  String get logViewMessage => 'Message:';

  @override
  String get logViewStack => 'Stack:';

  @override
  String get cmpTitle => 'Request comparison';

  @override
  String get cmpTabOverview => 'Overview';

  @override
  String get cmpHasDiff => 'Differences found';

  @override
  String get cmpIdentical => 'Identical';

  @override
  String cmpTotalChanges(int count) {
    return '$count changes in total';
  }

  @override
  String get cmpFieldMethod => 'Method';

  @override
  String get cmpChangeStats => 'Change summary';

  @override
  String get cmpHeaderChanges => 'Header changes';

  @override
  String get cmpQueryChanges => 'Parameter changes';

  @override
  String get cmpBodyChanges => 'Body changes';

  @override
  String get cmpStatusChanges => 'Status code changes';

  @override
  String get cmpDetailedReport => 'Detailed report';

  @override
  String get cmpNoHeaderChanges => 'No header changes';

  @override
  String cmpOldValue(String value) {
    return 'Old: $value';
  }

  @override
  String cmpNewValue(String value) {
    return 'New: $value';
  }

  @override
  String get cmpNoBodyChanges => 'No body changes';

  @override
  String get cmpBodyA => 'Request body A';

  @override
  String get cmpBodyB => 'Request body B';

  @override
  String get cmpNoResponseData => 'No response data';

  @override
  String cmpResponseHeaderChanges(int count) {
    return 'Response header changes ($count)';
  }

  @override
  String get cmpNoChanges => 'No changes';

  @override
  String get cmpResponseBodyA => 'Response body A';

  @override
  String get cmpResponseBodyB => 'Response body B';

  @override
  String get cmpModified => 'Modified';

  @override
  String cmpRequestLabel(String label) {
    return 'Request $label';
  }

  @override
  String get cmpEmpty => '(empty)';


  @override
  String backupCreated(String name, int count) {
    return 'Backup created: $name ($count items)';
  }

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get backupNow => 'Back up now (config + certificate + scripts + workspace)';

  @override
  String get backupAutoToAppDataDir => 'Configuration automatically backs up to the app data directory';

  @override
  String get backupOk => 'OK';

  @override
  String get backupConfirmRestore => 'Confirm restore';

  @override
  String backupRestoreConfirm(String name) {
    return 'Restoring backup "$name" will overwrite the current configuration. Continue?';
  }

  @override
  String get backupConfirmDelete => 'Confirm delete';

  @override
  String backupRestoredApplied(int restored) {
    return 'Restored $restored files; the configuration is now in effect';
  }

  @override
  String backupRestoredNotApplied(int restored, String failedSuffix) {
    return 'Restored $restored files (configuration not applied$failedSuffix)';
  }

  @override
  String backupFailedSuffix(int failed) {
    return ', $failed items failed';
  }

  @override
  String get backupAppliedSuffix => ', the configuration is now in effect';

  @override
  String get backupConfigRestored => 'Configuration restored';

  @override
  String backupRestoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String backupRestoredSummary(int restored, String applied, String failed) {
    return 'Restored $restored files$applied$failed';
  }

  @override
  String get backupRestored => 'Backup restored';

  @override
  String get backupChooseSaveLocation => 'Choose a save location';

  @override
  String backupExportedTo(String path) {
    return 'Exported to: $path';
  }

  @override
  String get backupExportDialogTitle => 'Export backup file';

  @override
  String get backupExportSuccess => 'Exported successfully';

  @override
  String backupExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String backupDeleteConfirm(String name) {
    return 'Delete backup "$name"?';
  }

  @override
  String backupDeleteConfirmDesktop(String name) {
    return 'Delete backup file "$name"?\n\nThis cannot be undone.';
  }

  @override
  String get backupDeleted => 'Backup deleted';

  @override
  String backupDeleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get backupDirNotFound => 'Backup directory does not exist';

  @override
  String backupRestoreConfirmDesktop(String name) {
    return 'Restore backup file "$name"?\n\nThe current configuration will be overwritten.';
  }

  @override
  String backupViewTitle(String name) {
    return 'View backup: $name';
  }

  @override
  String backupViewFailed(String error) {
    return 'View failed: $error';
  }

  @override
  String get backupCopied => 'Copied to clipboard';

  @override
  String get backupJustNow => 'Just now';


  @override
  String get cfgDeskGeneratingConfig => 'Generating config file...';

  @override
  String get cfgDeskCannotReadFile => 'Unable to read the file';

  @override
  String get rootProxyNoAccess => 'Root permission not granted: the device may not be rooted, or you did not tap Allow in the authorization dialog';

  @override
  String get rootProxyClosed => 'Turned off; the iptables rules have been cleaned up';

  @override
  String get rootProxyStopError => 'Error while turning it off: rules may still be present; retry or reboot the device';

  @override
  String get rootProxyNeedCapture => 'Start capture first: enabling redirection while the proxy port is not listening will cut the device off the network';

  @override
  String get rootProxyNeedStopVpn => 'Stop VPN capture first: the two capture methods cannot be used at the same time';

  @override
  String get rootProxyStartDenied => 'Failed to enable; make sure root permission has been granted';

  @override
  String rootProxyStartFailed(String reason) {
    return 'Failed to enable: $reason';
  }

  @override
  String get rootProxyActive => 'Redirection is active';

  @override
  String get rootProxyInactive => 'Not active';

  @override
  String rootProxyTargetPort(int port) {
    return 'Target port: $port　Protection: leftover rules are cleaned up automatically on the next launch';
  }

  @override
  String get rootProxyCheckRoot => 'Check root permission';

  @override
  String get rootProxyFirstCheck => 'The first check will bring up the su authorization dialog';

  @override
  String get rootProxyGranted => 'Root permission granted';

  @override
  String get rootProxyNotGranted => 'Root permission not granted';

  @override
  String get rootProxyNotesTitle => 'Notes';

  @override
  String get rootProxyNotesBody => '· The device must be rooted and su permission granted;\n· The idea is to add a chain for ProxyPin only to the nat table, redirecting outbound TCP connections to the proxy port, without making any other changes;\n· Only IPv4 is handled; IPv6 traffic stays direct;\n· Mutually exclusive with VPN capture, so turn the VPN off first;\n· If the phone shows “connected to WiFi but no internet”, turn this off first; the app also cleans up leftover rules on every launch.';


  @override
  String get fuzzDictDefaultName => 'Imported dictionary';

  @override
  String fuzzDictImported(String name) {
    return 'Imported "$name"';
  }

  @override
  String get fuzzDictDeleteTitle => 'Delete dictionary';

  @override
  String fuzzDictDeleteConfirm(String name) {
    return 'Delete "$name"?';
  }

  @override
  String get fuzzDictTitle => 'Fuzz Dictionary';

  @override
  String get fuzzDictTips => 'Tap a dictionary to fill it into the current injection. No built-in attack payload library — the built-ins are just boundary/type-anomaly strings; fill, import or script the rest yourself.';

  @override
  String get fuzzDictNoCustom => 'No custom dictionaries yet';

  @override
  String get fuzzDictImportFile => 'Import from file';

  @override
  String fuzzDictNEntries(int count) {
    return '$count values';
  }

  @override
  String fuzzDictExpanded(int count, String preview) {
    return 'Expanded to $count values: $preview';
  }

  @override
  String fuzzDictScriptFailed(String error) {
    return 'Script failed: $error';
  }

  @override
  String get fuzzDictNameRequired => 'Give the dictionary a name';

  @override
  String get fuzzDictCreate => 'New dictionary';

  @override
  String get fuzzDictEditTitle => 'Edit dictionary';

  @override
  String get fuzzDictScriptLabel => 'Script (optional, JS; assign the array to result)';

  @override
  String get fuzzDictTestRun => 'Try it';

  @override
  String get fuzzDictScriptNote => 'The script output is merged with the values above and de-duplicated';

  @override
  String apiEpTitle(int count) {
    return 'API Endpoints ($count)';
  }

  @override
  String get apiEpSearchHint => 'Search endpoints...';

  @override
  String get apiEpTotalEndpoints => 'Total endpoints';

  @override
  String get apiEpResourceGroups => 'Resource groups';

  @override
  String get apiEpTotalRequests => 'Total requests';

  @override
  String apiEpPathCalls(String path, int count) {
    return '$path · $count requests';
  }

  @override
  String apiEpCallsSuccess(int count, String rate) {
    return '$count calls · Success rate $rate';
  }

  @override
  String get apiEpNoMatch => 'No matching endpoints found';

  @override
  String get apiEpGroupView => 'Group view';

  @override
  String get apiEpListView => 'List view';

  @override
  String get apiEpGroupByDomain => 'Group by host';

  @override
  String get apiEpExportOpenApi => 'Export as OpenAPI';

  @override
  String get apiEpSwaggerFormat => 'Swagger format';

  @override
  String get apiEpExportPostman => 'Export as Postman';

  @override
  String get apiEpCollectionFormat => 'Collection format';

  @override
  String get apiEpExportJson => 'Export as JSON';

  @override
  String apiEpExported(String label) {
    return '$label exported';
  }

  @override
  String apiEpExportFailed(String label, String error) {
    return '$label export failed: $error';
  }

  @override
  String get apiEpFullUrl => 'Full URL';

  @override
  String get apiEpCallCount => 'Call count';

  @override
  String get apiEpAvgResponseTime => 'Avg response time';

  @override
  String get apiEpFirstSeen => 'First seen';

  @override
  String get apiEpLastSeen => 'Last seen';

  @override
  String get apiEpTags => 'Tags';


  @override
  String perfLoadFailed(String error) {
    return 'Failed to load data: $error';
  }

  @override
  String get perfTitle => 'Performance Monitoring';

  @override
  String get perfRetry => 'Retry';

  @override
  String get perfLoading => 'Loading data...';

  @override
  String perfLastUpdate(String time) {
    return 'Last updated: $time';
  }

  @override
  String get perfProxyStatus => 'Proxy Status';

  @override
  String get perfRunning => 'Running';

  @override
  String get perfStopped => 'Stopped';

  @override
  String get perfOverview => 'Performance Overview';

  @override
  String get perfTotalRequests => 'Total Requests';

  @override
  String get perfConnectionPool => 'Connection Pool Status';

  @override
  String get perfActiveConnections => 'Active Connections';

  @override
  String get perfIdleConnections => 'Idle Connections';

  @override
  String get perfMetrics => 'Performance Metrics';

  @override
  String get perfAvgResponseTime => 'Average Response Time';

  @override
  String get perfQps => 'QPS (requests per second)';

  @override
  String get perfRequestStats => 'Request Statistics';

  @override
  String get perfNoBreakdown => 'No breakdown data';

  @override
  String get rqTitle => 'Send Queue';

  @override
  String get rqClearFinished => 'Clear finished tasks';

  @override
  String get rqIntro => 'All replay tasks started during this run (repeated, batch, or scheduled) are gathered here: check progress, success and failure counts, and the queue of pending requests. Tasks are in-memory and cleared on restart.';

  @override
  String get rqCancelTask => 'Cancel task (stop further sending)';

  @override
  String get rqRemoveRecord => 'Remove record';

  @override
  String get rqStatRetried => 'Retried';

  @override
  String get rqStatPlanned => 'Planned';

  @override
  String rqLastError(String error) {
    return 'Last error: $error';
  }

  @override
  String rqPendingRequests(int count) {
    return 'Pending requests ($count)';
  }

  @override
  String rqMoreRemaining(int count) {
    return '... and $count more';
  }

  @override
  String get rqStatusScheduled => 'Waiting to send';

  @override
  String get rqStatusRunning => 'Sending';

  @override
  String get rqStatusCompleted => 'Completed';

  @override
  String get rqStatusCanceled => 'Canceled';

  @override
  String get rqEmptyTitle => 'No replay tasks yet';

  @override
  String get rqEmptyHint => 'Tasks show up here after you start a replay (batch or scheduled)';

  @override
  String get bvDescTimestamp => 'Unix timestamp (seconds)';

  @override
  String get bvDescTimestampMs => 'Unix timestamp (milliseconds)';

  @override
  String get bvDescDatetime => 'ISO 8601 date-time';

  @override
  String get bvDescDate => 'Date (yyyy-MM-dd)';

  @override
  String get bvDescTime => 'Time (HH:mm:ss)';

  @override
  String get bvDescUnixDate => 'Days since 1970';

  @override
  String get bvDescUuid => 'Random UUID (different on every reference)';

  @override
  String get bvTitle => 'Built-in variables';

  @override
  String bvIntro(String mark) {
    return 'These variables need no definition — reference them directly anywhere $mark is supported (rewrite rules, report URLs, scripts, etc.). Tap to copy.';
  }

  @override
  String bvCopied(String text) {
    return 'Copied $text';
  }

  @override
  String get bvGotIt => 'Got it';


  @override
  String get toolboxNavCalcTip => 'Base conversion / two\'s complement · bitwise ops · endianness · IEEE754 · CRC/hash';

  @override
  String get toolboxNavMcpTip => 'MCP Server settings';

  @override
  String get toolboxNavLogView => 'Log viewer';

  @override
  String get toolboxNavWaf => 'WAF mutation';

  @override
  String get toolboxNavWafTip => 'Payload-equivalent mutation + WAF signature comparison + active probing (probing sends real requests and requires authorization)';

  @override
  String get toolboxNavPinningTip => 'Certificate-pinning bypass helper: detect the frida environment · generate/deploy hook scripts · one-tap injection';

  @override
  String get toolboxNavWorkspaceTip => 'Manage captures separately per project/environment (standard HAR storage) · can hook up a custom server for sharing/backup';

  @override
  String get toolboxNavCloudTip => 'Account · cloud-hosted workspaces · real-time multi-user collaboration (self-hosted server)';

  @override
  String get toolboxNavAiTip => 'AI chat analysis of captured data (Agent mode supported)';

  @override
  String deskNavUpgradeTitle(String version) {
    return 'What\'s new in V$version';
  }

  @override
  String get deskNavUpgradeBody => 'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.\nClick the HTTPS capture (lock) icon, choose "Install Root Certificate", and follow the prompts to complete installation.\n\n1. Added a built-in MCP server so AI assistants (e.g. Claude) can inspect and debug captured traffic;\n2. Added built-in dynamic variables for environments;\n3. Request rewrite rules can now be reordered with move up/down actions;\n4. Fixed a crash triggered by the Windows context menu;\n5. Fixed multi-value headers (e.g. multiple Set-Cookie) being incorrectly merged when handled by scripts or rewrite rules;\n6. Fixed h2c (plaintext HTTP/2) capture, non-ASCII domain normalization, and certificate validation failures for IP hosts;\n7. Fixed an iOS 13 crash, dropped bodies for close-delimited responses, Android VPN destination-port recording, and other issues.\n';

  @override
  String get setNavThemeTip => 'Theme settings are in the top toolbar — click the sun/moon icon to switch';

  @override
  String get setNavProxyDomainsHint => 'Use \';\' to separate multiple entries';

  @override
  String get setNavClearProxyResidue => 'Clear leftover system proxy';

  @override
  String get setNavClearProxyResidueDesc => 'Click here to recover when the network is broken after an abnormal exit';

  @override
  String get setNavProxyResidueCleared => 'System proxy settings cleared — the network should be back to normal';

  @override
  String get setNavRepair => 'Repair';

  @override
  String mobNavUpgradeTitle(String version) {
    return 'What\'s new in V$version';
  }

  @override
  String get mobNavUpgradeBody => 'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.\n\n1. Added a built-in MCP server so AI assistants (e.g. Claude) can inspect and debug captured traffic;\n2. Added built-in dynamic variables for environments;\n3. Request rewrite rules can now be reordered with move up/down actions;\n4. Fixed a crash triggered by the Windows context menu;\n5. Fixed multi-value headers (e.g. multiple Set-Cookie) being incorrectly merged when handled by scripts or rewrite rules;\n6. Fixed h2c (plaintext HTTP/2) capture, non-ASCII domain normalization, and certificate validation failures for IP hosts;\n7. Fixed an iOS 13 crash, dropped bodies for close-delimited responses, Android VPN destination-port recording, and other issues.\n';

  @override
  String get appFilterUnknownApp => 'Unknown app';

  @override
  String get appFilterClearInvalid => 'clear invalid apps';

  @override
  String get appFilterWhitelistHint => 'When no whitelist application is set, all applications will be captured';

  @override
  String get appFilterRemoveWhitelistConfirm => 'Remove this app from the whitelist?';

  @override
  String get appFilterRemoveBlacklistConfirm => 'Remove this app from the blacklist?';

  @override
  String get appFilterSearchHint => 'Please enter the application or package name';

  @override
  String get appFilterShowSystemApps => 'Show system apps';

  @override
  String contentBodyOriginalMb(String size) {
    return '($size MB original)';
  }

  @override
  String contentBodyOriginalKb(String size) {
    return '($size KB original)';
  }

  @override
  String get contentBodyTruncatedTip => 'Trimmed to the capture size limit — the full content was not kept';

  @override
  String contentBodyTruncatedBadge(String size) {
    return 'Trimmed $size';
  }

  @override
  String contentBodySaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get contentBodyDecodeTruncatedTip => 'Response body is large — the preview only decodes up to the limit (adjustable in Settings → Capture size limit). Preview only; forwarding and saved content are unaffected.';

  @override
  String get contentBodyPreviewTruncated => 'Preview truncated';


  @override
  String guideLoadFailed(String error) {
    return 'Failed to load document: $error';
  }

  @override
  String get guideSearchHint => 'Search documents';

  @override
  String get guideMarkResetTooltip => 'Reset the markup legend';

  @override
  String get wsRuleMgrFrameActionTitle => 'Frame-level actions';

  @override
  String get wsRuleMgrActionLabel => 'Action';

  @override
  String get wsRuleMgrActionObserve => 'Match only, do not intervene';

  @override
  String get wsRuleMgrActionRewrite => 'Rewrite the frame content';

  @override
  String get wsRuleMgrActionDrop => 'Drop the frame';

  @override
  String get wsRuleMgrActionDelay => 'Delay the forwarding';

  @override
  String get wsRuleMgrActionDuplicate => 'Send the frame again';

  @override
  String get wsRuleMgrPayloadMatchLabel => 'Frame content match (empty = all frames in this direction)';

  @override
  String get wsRuleMgrPayloadMatchHint => 'Applies the match mode above to the frame content, e.g. login';

  @override
  String get wsRuleMgrReplaceWith => 'Replace with';

  @override
  String get wsRuleMgrRewriteNote => 'Fragmented, compressed and control frames are not rewritten and are forwarded as-is';

  @override
  String get wsRuleMgrDelayMs => 'Delay (ms)';


  @override
  String pcCertInstallToSystem(String detail) {
    return ' Install certificate to this system，$detail';
  }

  @override
  String get pcCertMacTrustHint => 'After installation, double-click to select “Always Trust”。\n If installation and opening fail，Please export the certificate and drag it to the system certificate';

  @override
  String get pcCertWinTrustHint => 'choice“Trusted Root Certificate Authority”';

  @override
  String get pcCertLinuxGuide => 'Install the certificate to this system), take Ubuntu as an example to download the certificate:\nFirst copy the certificate to /usr/local/share/ca-certificates/, and then execute update-ca-certificates.\nFor other systems, please search online for installing root certificates.';

  @override
  String get pcCertFirefoxHint => 'Note: FireFox has its own trusted certificate library, so you need to manually import the required certificates in the settings.';

  @override
  String get pcCertTrustTitle => 'Install and Trust ProxyPin CA Certificate';

  @override
  String get pcCertTrustDesc => 'ProxyPin can decrypt encrypted traffic on the fly and enable to see raw HTTPS requests and responses.';

  @override
  String get pcCertInstalledTitle => 'Certificate Installed';

  @override
  String get pcCertInstallSuccess => 'Certificate installed successfully';

  @override
  String get pcCertInstallFailed => 'Certificate installation failed, please try manual installation';

  @override
  String fuzzerDictFilled(String name, String count) {
    return 'Filled $count values from “$name”';
  }

  @override
  String fuzzerDictFailed(String error) {
    return 'Failed to expand dictionary: $error';
  }

  @override
  String get fuzzerFillFromDict => 'Fill from dictionary';

  @override
  String fuzzerPayloadCount(String count) {
    return '$count entries';
  }

  @override
  String get fuzzerRulesTitle => 'Anomaly rules (compare with baseline)';

  @override
  String get fuzzerNoRuleEnabled => 'No rule enabled';

  @override
  String fuzzerRulesEnabled(String names) {
    return 'Enabled: $names';
  }

  @override
  String get fuzzerRulesNote => 'Rules only flag what differs from the baseline; they do not prove a vulnerability — the conclusion is yours.';

  @override
  String get capLimitUnlimitedOption => 'Unlimited (keep full content, default)';

  @override
  String get capLimitOption128 => '128 KB (head and a little content only)';

  @override
  String get capLimitUnlimitedDesc => 'Unlimited: keep the full request/response body';

  @override
  String capLimitSizeMb(String mb) {
    return 'Limit $mb MB: only the first $mb MB is kept for display';
  }

  @override
  String capLimitSizeKb(String kb) {
    return 'Limit $kb KB: only the first $kb KB is kept for display';
  }

  @override
  String get capLimitDesc => 'Bodies over the limit keep only the first N bytes (compressed bodies are released entirely), to reduce memory usage during long captures.\nTrimming happens after forwarding completes and does not affect the actual forwarding.';

  @override
  String get navBarMultiSeparatorHint => 'Use \';\' to separate multiple entries';

  @override
  String navBarAiEnabled(String model) {
    return 'Enabled · $model';
  }

  @override
  String get navBarAiNotConfigured => 'Not configured · connect an OpenAI-compatible API to analyze captured requests';

  @override
  String get navBarLogSubtitle => 'View and export app runtime logs';

  @override
  String get navBarDocSubtitle => 'Tutorials · specs · dev docs (built-in offline)';


  @override
  String get updRestartHint => 'The app will quit and restart to complete the update.';

  @override
  String get updPreparing => 'Preparing update...';

  @override
  String get updDownloading => 'Downloading update...';

  @override
  String get updReadyToInstall => 'Update downloaded and ready to install';

  @override
  String get updLaunchingInstaller => 'Launching installer...';

  @override
  String get updFailed => 'Update failed';

  @override
  String get updCancelled => 'Update cancelled';

  @override
  String updDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get updInvalidUrl => 'Invalid download URL';

  @override
  String updDownloadHttpError(int code) {
    return 'Download failed (HTTP $code)';
  }

  @override
  String get updVerifyFailed => 'Downloaded file verification failed';

  @override
  String get updInstallerMissing => 'Installer file missing';

  @override
  String get updInPlaceFailed => 'In-place update failed, please install manually';

  @override
  String updLaunchFailed(String error) {
    return 'Failed to launch installer: $error';
  }

  @override
  String get updPlatformUnsupported => 'Auto-install is not supported on this platform';

  @override
  String updMacExtractFailed(String error) {
    return 'Failed to extract the update package: $error';
  }

  @override
  String get updMacAppNotFound => 'App not found in the update package';

  @override
  String get updMacMultipleApps => 'Multiple apps found in the update package; cannot determine the install target';

  @override
  String get updMacInvalidApp => 'Invalid app structure in the update package';

  @override
  String get updMacAuthFailed => 'Authorization was cancelled or the privileged install failed';

  @override
  String updWinUacLaunchFailed(int code) {
    return 'Failed to launch the update script with UAC elevation (ShellExecuteW result $code)';
  }

  @override
  String get updWinUacTimeout => 'Timed out waiting for the elevated update script to start; make sure you clicked "Yes" in the permission prompt';

  @override
  String get updWinExeNotFound => 'Executable not found in the update package';

  @override
  String get updWinMultipleExe => 'Multiple executables found in the update package; cannot determine which one to launch';


  @override
  String get domainAddHelper => 'Host or URL prefix; * is wildcard';

  @override
  String splashSubtitle(String version) {
    return 'v$version · Open-source free traffic capture tool';
  }

  @override
  String get bvVariableWord => 'variable';

  @override
  String bvSampleVariable(String lb, String word, String rb) {
    return '$lb$lb$word$rb$rb';
  }

  @override
  String imageRenderFailed(String error) {
    return 'Unable to render image: $error';
  }

  @override
  String get copyValue => 'Copy Value';

  @override
  String repeatBatchCount(int count) {
    return 'Repeat $count requests in batch';
  }

  @override
  String get aiSettings => 'AI Settings';

  @override
  String get millisecond => 'Millisecond';

  @override
  String get minute => 'Minute';

  @override
  String get searchHistory => 'Search history';

  @override
  String get clearSearchHistory => 'Clear search history?';

  @override
  String get languageChineseSimplified => '简体中文';

  @override
  String get languageChineseTraditional => '繁體中文';

  @override
  String get invalidRewriteRuleList => 'The content is not a valid rewrite rule list';

  @override
  String get scriptConsoleTitle => 'Script Console';

  @override
  String get remoteDeviceDisconnected => 'Remote device disconnected';

  @override
  String get cryptoRuleEmpty => 'No decryption rules yet';

  @override
  String get cryptoRuleEmptyHint => 'Tap + in the top right to add a request to decrypt';

  @override
  String get cryptoRuleFieldHintEmpty => 'empty = whole body';

  @override
  String get jsonViewerEmptyHint => 'Paste or open a JSON file';

  @override
  String get aboutSlogan => 'Full platform open source free capture HTTP(S) traffic software';

  @override
  String get downloadAddress => 'Download';

  @override
  String get beautifyNotSupported => 'Beautify is not supported for this type';

  @override
  String repeatResultSuccess(int count) {
    return 'Success: $count';
  }

  @override
  String repeatResultFail(int count) {
    return 'Fail: $count';
  }

  @override
  String repeatResultRetry(int count) {
    return 'Retries: $count';
  }

  @override
  String repeatResultError(String error) {
    return 'Error: $error';
  }
}
