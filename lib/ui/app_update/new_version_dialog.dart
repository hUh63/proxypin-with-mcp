import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/app_update/desktop_update_dialog.dart';
import 'package:proxypin/ui/app_update/remote_version_entity.dart';
import 'package:proxypin/utils/navigator.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';

class NewVersionDialog extends StatelessWidget {
  NewVersionDialog(
    this.currentVersion,
    this.newVersion, {
    this.canIgnore = true,
    this.isFork = false,
    this.versionKey,
  }) : super(key: _dialogKey);

  final String currentVersion;
  final RemoteVersionEntity newVersion;
  final bool canIgnore;

  /// true = 本分支(fork)更新，false = 上游更新。用于在弹窗内区分来源。
  final bool isFork;

  /// 忽略记录键(来源+版本)，缺省回退到裸版本号以兼容旧逻辑。
  final String? versionKey;

  static final _dialogKey = GlobalKey(debugLabel: 'new version dialog');

  Future<void> show(BuildContext context) async {
    if (_dialogKey.currentContext == null) {
      return showDialog(
        context: context,
        useRootNavigator: true,
        builder: (context) => this,
      );
    } else {
      logger.d("new version dialog is already open");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.appUpdateDialogTitle),
      // scrollable: true,
      content: Container(
          constraints: BoxConstraints(maxHeight: 230, maxWidth: 500),
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.appUpdateUpdateMsg),
              const SizedBox(height: 5),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: "${localizations.appUpdateSourceLbl}: ", style: theme.textTheme.bodySmall),
                    TextSpan(
                      text: isFork
                          ? localizations.appUpdateSourceFork
                          : localizations.appUpdateSourceUpstream,
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: "${localizations.appUpdateCurrentVersionLbl}: ", style: theme.textTheme.bodySmall),
                    TextSpan(text: currentVersion, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: "${localizations.appUpdateNewVersionLbl}: ", style: theme.textTheme.bodySmall),
                    TextSpan(text: newVersion.version, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
              Text(newVersion.content ?? '', style: theme.textTheme.labelMedium),
            ],
          ))),
      actions: [
        Wrap(alignment: WrapAlignment.end, children: [
          if (canIgnore)
            TextButton(
              onPressed: () async {
                SharedPreferencesAsync()
                    .setString(Constants.ignoreReleaseVersionKey, versionKey ?? newVersion.version);
                logger.i("ignored release [${newVersion.version}]");
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(localizations.appUpdateIgnoreBtnTxt),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.appUpdateLaterBtnTxt),
          ),
          TextButton(
            onPressed: () async {
              // 桌面端且有匹配的安装包: 走应用内下载安装流程
              final asset = Platforms.isDesktop() ? newVersion.desktopAsset() : null;
              if (asset != null) {
                final rootContext = NavigatorHelper().navigatorKey.currentContext;
                Navigator.pop(context);
                if (rootContext != null && rootContext.mounted) {
                  await showDesktopUpdateDialog(rootContext, newVersion, asset);
                }
                return;
              }
              await launchUrl(Uri.parse(newVersion.url), mode: LaunchMode.externalApplication);
            },
            child: Text(localizations.appUpdateUpdateNowBtnTxt),
          ),
        ])
      ],
    );
  }
}
