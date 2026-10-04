import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/app_update/remote_version_entity.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'new_version_dialog.dart';

class AppUpdateRepository {
  static final HttpClient httpClient = HttpClient();

  /// 最近一次检查时间戳（毫秒）。用于限制自动检查频率，避免每次启动
  /// 都打 GitHub 未认证接口（60 次/小时/IP），从而频繁触发 403 限流。
  static const String _lastCheckKey = 'app_update_last_check_ms';
  static const Duration _autoCheckInterval = Duration(hours: 6);

  /// 更新检查同时查询**上游**与**本分支(fork)**两个 release 源，并区分来源：
  /// - 优先提示本分支更新(用户装的就是本分支)；
  /// - 本分支无更新时，再提示上游更新(标注为「上游」)。
  /// 两个源的「忽略」记录互不影响。
  ///
  /// [force] 为 true 时忽略自动检查间隔（用户在「关于」页手动点击检查）。
  static Future<void> checkUpdate(BuildContext context,
      {bool canIgnore = true, bool showToast = false, bool force = false}) async {
    try {
      if (!force) {
        final last = await SharedPreferencesAsync().getInt(_lastCheckKey) ?? 0;
        final elapsed = DateTime.now().millisecondsSinceEpoch - last;
        if (elapsed >= 0 && elapsed < _autoCheckInterval.inMilliseconds) {
          logger.d('[AppUpdate] skipped: last check ${elapsed ~/ 60000} min ago');
          return;
        }
      }
      await SharedPreferencesAsync().setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      final latestList = await Future.wait<RemoteVersionEntity?>([
        getLatestVersion(fork: true),
        getLatestVersion(),
      ]);
      final forkLatest = latestList[0];
      final upstreamLatest = latestList[1];

      // 本分支优先。fork 的 release tag 是 fork 计数(tag 号≠应用版本)，
      // 故用资产名解析出的应用版本参与比较，避免误判。
      RemoteVersionEntity? target;
      var isFork = false;
      if (forkLatest != null) {
        final forkVersion = forkLatest.assetAppVersion() ?? forkLatest.version;
        if (compareVersions(AppConfiguration.version, forkVersion)) {
          target = forkLatest;
          isFork = true;
        }
      }
      if (target == null && upstreamLatest != null) {
        if (compareVersions(AppConfiguration.version, upstreamLatest.version)) {
          target = upstreamLatest;
          isFork = false;
        }
      }

      if (target == null) {
        logger.i("already using latest version[${AppConfiguration.version}]");
        if (showToast) {
          AppLocalizations localizations = AppLocalizations.of(context)!;
          CustomToast.success(localizations.appUpdateNotAvailableMsg).show(context);
        }
        return;
      }

      // 忽略记录按「来源+版本」区分，忽略上游不会连带忽略本分支，反之亦然。
      final versionKey = "${isFork ? 'fork' : 'upstream'}:${target.version}";
      if (canIgnore) {
        var ignoreVersion = await SharedPreferencesAsync().getString(Constants.ignoreReleaseVersionKey);
        if (ignoreVersion == versionKey) {
          logger.d("ignored release [$versionKey]");
          return;
        }
      }

      logger.d("new version available(${isFork ? 'fork' : 'upstream'}): $target");

      if (!context.mounted) return;
      NewVersionDialog(
        AppConfiguration.version,
        target,
        canIgnore: canIgnore,
        isFork: isFork,
        versionKey: versionKey,
      ).show(context);
    } catch (e) {
      logger.e("Error checking for updates: $e");
      if (showToast) {
        CustomToast.error(e.toString()).show(context);
      }
    }
  }

  /// Fetches the latest version information from the GitHub releases API.
  ///
  /// [fork] 为 true 时查询本分支(fork)仓库，否则查询上游仓库。
  static Future<RemoteVersionEntity?> getLatestVersion({bool includePreReleases = false, bool fork = false}) async {
    final apiUrl = fork ? Constants.githubForkReleasesApiUrl : Constants.githubReleasesApiUrl;
    late final http.Response response;
    try {
      response = await http.get(Uri.parse(apiUrl));
    } catch (e) {
      logger.w("[AppUpdate] failed to fetch latest version info($apiUrl): $e");
      return null;
    }
    if (response.statusCode != 200 || response.body.isEmpty) {
      if (response.statusCode == 403 || response.statusCode == 429) {
        // GitHub 未认证请求限流（60 次/小时/IP）：可自愈的临时情况，
        // 按 DEBUG 记录，避免每次启动刷 WARNING。
        logger.d('[AppUpdate] rate limited(status=${response.statusCode}), will retry later');
      } else {
        logger.w(
            "[AppUpdate] failed to fetch latest version info($apiUrl): status=${response.statusCode} bodyLen=${response.body.length}");
      }
      return null;
    }

    final List<dynamic> body;
    try {
      body = jsonDecode(response.body) as List;
    } catch (e) {
      logger.w("[AppUpdate] invalid release json($apiUrl): $e");
      return null;
    }
    if (body.isEmpty) return null;

    final releases = body
        .whereType<Map<String, dynamic>>()
        .map((e) => GithubReleaseParser.parse(e))
        .toList();
    if (releases.isEmpty) return null;

    final RemoteVersionEntity latest;
    if (includePreReleases) {
      latest = releases.first;
    } else {
      final stable = releases.where((e) => e.preRelease == false);
      if (stable.isEmpty) return null;
      latest = stable.first;
    }

    logger.d("[AppUpdate] latest version($apiUrl): $latest");
    return latest;
  }

  static bool compareVersions(String currentVersion, String latestVersion) {
    String normalizeVersion(String version) {
      // 去掉版本前缀, 兼容 v / V 两种写法(如 v1.3.3、V1.3.3)
      if (version.isNotEmpty && (version[0] == 'v' || version[0] == 'V')) {
        return version.substring(1);
      }
      return version;
    }

    List<int> parseVersion(String version) {
      // 每段只取前导数字, 兼容 beta / rc 等后缀, 无法解析时按 0 处理
      return normalizeVersion(version).split('.').map((segment) {
        final match = RegExp(r'\d+').firstMatch(segment);
        return match == null ? 0 : int.parse(match.group(0)!);
      }).toList();
    }

    List<int> current = parseVersion(currentVersion);
    List<int> latest = parseVersion(latestVersion);

    for (int i = 0; i < current.length; i++) {
      if (i >= latest.length || current[i] > latest[i]) {
        return false; // 当前版本高于最新版本
      } else if (current[i] < latest[i]) {
        return true; // 需要更新
      }
    }

    return latest.length > current.length; // 最新版本有更多的子版本号
  }
}
