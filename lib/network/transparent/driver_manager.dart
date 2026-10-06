/*
 * Copyright 2023 Hongen Wang
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:proxypin/network/transparent/windivert.dart';

/// WinDivert 运行库（`WinDivert.dll` + `WinDivert64.sys`）的检测结果。
class WindivertStatus {
  final bool dllFound;
  final String? dllPath;
  final String? version;
  final bool sysFound;
  final String? sysPath;

  /// 一键放置的目标目录（通常是 exe 同目录）。
  final String targetDir;

  /// 已探查过的目录。
  final List<String> searchedDirs;

  WindivertStatus({
    required this.dllFound,
    this.dllPath,
    this.version,
    required this.sysFound,
    this.sysPath,
    required this.targetDir,
    required this.searchedDirs,
  });

  /// dll 与 sys 都在，说明驱动运行库齐备。
  bool get ready => dllFound && sysFound;
}

/// 系统内其它内核抓包/注入能力的探测结果。
///
/// - [netfilter*]：NetFilter SDK（HTTP Debugger 使用的商业内核过滤框架）的痕迹；
/// - [npcapFound]：Npcap（WinPcap 后继，供 PCAP 抓包）。
///
/// 这些探测都是**只读**的（查文件 / 查服务），不加载、不安装任何第三方组件。
class KernelDriverStatus {
  final bool supported; // 是否 Windows
  final bool netfilterDriverFound;
  final String? netfilterDriverPath;
  final bool netfilterServiceFound;
  final String? netfilterServiceState;
  final bool nfapiFound;
  final bool npcapFound;
  final String? npcapPath;

  KernelDriverStatus({
    required this.supported,
    this.netfilterDriverFound = false,
    this.netfilterDriverPath,
    this.netfilterServiceFound = false,
    this.netfilterServiceState,
    this.nfapiFound = false,
    this.npcapFound = false,
    this.npcapPath,
  });
}

/// WinDivert 运行库的检测与「一键放置」。
///
/// 设计原则：**不在安装包里分发第三方二进制**。运行时若检测到缺失，
/// 由用户主动点击，从官方 GitHub Releases 下载（LGPLv3）或选择本地压缩包，
/// 解压出 `WinDivert.dll` / `WinDivert64.sys` 放到 exe 同目录即可。
class WindivertDriver {
  /// 官方发布页（给用户手动下载用）。
  static const String officialReleasesPage = 'https://github.com/basil00/Divert/releases';

  /// 直连 ASCII 官网（备用说明）。
  static const String officialHome = 'https://reqrypt.org/windivert.html';

  /// 拉取 GitHub API 失败时的回退下载地址。
  static const String fallbackZipUrl =
      'https://github.com/basil00/Divert/releases/download/v2.2.2/WinDivert-2.2.2-A.zip';

  static const List<String> _sysNames = ['WinDivert64.sys', 'WinDivert.sys', 'WinDivert32.sys'];

  /// 运行库要放置的目标目录：优先 exe 同目录。
  static String targetDir() {
    try {
      final exe = Platform.resolvedExecutable;
      if (exe.isNotEmpty) return File(exe).parent.path;
    } catch (_) {}
    return Directory.current.path;
  }

  /// 探查目录（exe 同目录 → 当前目录 → System32 → PATH）。
  static List<String> searchDirs() {
    final dirs = <String>[];
    void add(String? d) {
      final v = d?.trim();
      if (v != null && v.isNotEmpty && !dirs.contains(v)) dirs.add(v);
    }

    add(targetDir());
    try {
      add(Directory.current.path);
    } catch (_) {}
    final sysRoot = Platform.environment['SystemRoot'];
    if (sysRoot != null) add('$sysRoot\\System32');
    final path = Platform.environment['PATH'];
    if (path != null) {
      for (final p in path.split(Platform.isWindows ? ';' : ':')) {
        add(p);
      }
    }
    return dirs;
  }

  /// 检测 WinDivert 运行库。
  static WindivertStatus inspect() {
    if (!Platform.isWindows) {
      return WindivertStatus(dllFound: false, sysFound: false, targetDir: targetDir(), searchedDirs: const []);
    }

    final dirs = searchDirs();
    String? dllPath;
    String? sysPath;
    for (final dir in dirs) {
      if (dllPath == null) {
        for (final name in Windivert.candidateDllNames) {
          final f = File(_join(dir, name));
          if (f.existsSync()) {
            dllPath = f.path;
            break;
          }
        }
      }
      if (sysPath == null) {
        for (final name in _sysNames) {
          final f = File(_join(dir, name));
          if (f.existsSync()) {
            sysPath = f.path;
            break;
          }
        }
      }
      if (dllPath != null && sysPath != null) break;
    }

    String? version;
    if (dllPath != null) {
      try {
        final w = Windivert.tryLoad(searchDirs: [File(dllPath).parent.path]);
        version = w?.version();
      } catch (_) {
        // 版本取不到不影响
      }
    }

    return WindivertStatus(
      dllFound: dllPath != null,
      dllPath: dllPath,
      version: version,
      sysFound: sysPath != null,
      sysPath: sysPath,
      targetDir: targetDir(),
      searchedDirs: dirs,
    );
  }

  /// 从本地压缩包（.zip）安装到 [targetDir]。
  /// 成功返回 null，失败返回错误信息。
  static Future<String?> installFromZipFile(String zipPath, {void Function(String)? log}) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      return _extractAndPlace(bytes, log);
    } catch (e) {
      return '读取压缩包失败: $e';
    }
  }

  /// 从官方 GitHub Releases 下载并安装。成功返回 null，失败返回错误信息。
  static Future<String?> installFromUrl({
    void Function(double progress)? onProgress,
    void Function(String log)? log,
  }) async {
    final url = await _resolveZipUrl();
    log?.call('下载 $url');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'proxypin');
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) {
        return '下载失败 HTTP ${resp.statusCode}';
      }
      final total = resp.contentLength;
      final chunks = <int>[];
      await for (final c in resp) {
        chunks.addAll(c);
        if (total > 0) onProgress?.call((chunks.length / total).clamp(0.0, 1.0));
      }
      return _extractAndPlace(chunks, log);
    } catch (e) {
      return '下载失败: $e';
    } finally {
      client.close(force: true);
    }
  }

  /// 解析 zip 字节，把 x64 的 dll/sys 写到目标目录。
  static Future<String?> _extractAndPlace(List<int> bytes, void Function(String)? log) async {
    if (!Platform.isWindows) return '仅支持 Windows';

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return '解析压缩包失败（不是有效 zip?）: $e';
    }

    final dir = targetDir();
    final written = <String>[];

    // WinDivert.dll：优先取 x64/amd64 目录里的那份。
    final dll = _pick(archive, 'WinDivert.dll', prefer64: true);
    if (dll != null) {
      final out = File(_join(dir, 'WinDivert.dll'));
      await out.writeAsBytes(dll, flush: true);
      written.add('WinDivert.dll');
      log?.call('已写入 ${out.path}');
    }

    final sys = _pick(archive, 'WinDivert64.sys', prefer64: false);
    if (sys != null) {
      final out = File(_join(dir, 'WinDivert64.sys'));
      await out.writeAsBytes(sys, flush: true);
      written.add('WinDivert64.sys');
      log?.call('已写入 ${out.path}');
    }

    if (!written.contains('WinDivert.dll')) {
      return '压缩包里没找到 WinDivert.dll';
    }
    if (!written.contains('WinDivert64.sys')) {
      log?.call('提示：未在包内找到 WinDivert64.sys（x64 驱动），请确认下载的是官方 WinDivert 发行包');
    }
    return null;
  }

  /// 在压缩包里按文件名挑一份；[prefer64] 时优先含 x64/amd64 的路径。
  static Uint8List? _pick(Archive archive, String name, {required bool prefer64}) {
    Uint8List? fallback;
    for (final f in archive.files) {
      final base = f.name.replaceAll('\\', '/').split('/').last;
      if (base.toLowerCase() != name.toLowerCase()) continue;
      final lower = f.name.toLowerCase().replaceAll('\\', '/');
      if (prefer64 && (lower.contains('x64') || lower.contains('amd64'))) {
        return f.content;
      }
      fallback ??= f.content;
    }
    return fallback;
  }

  static Future<String> _resolveZipUrl() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/basil00/Divert/releases/latest'));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'proxypin');
      final resp = await req.close();
      if (resp.statusCode == HttpStatus.ok) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final assets = (json['assets'] as List?) ?? const [];
        for (final a in assets) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          final url = a['browser_download_url'] as String?;
          if (url != null && name.endsWith('.zip') && name.contains('windivert')) {
            return url;
          }
        }
      }
    } catch (_) {
      // 回退到内置地址
    } finally {
      client.close(force: true);
    }
    return fallbackZipUrl;
  }

  static String _join(String dir, String name) {
    if (dir.endsWith('\\') || dir.endsWith('/')) return '$dir$name';
    return '$dir${Platform.pathSeparator}$name';
  }
}

/// 系统内其它内核抓包能力的只读探测。
class KernelDriverProbe {
  static Future<KernelDriverStatus> inspect() async {
    if (!Platform.isWindows) {
      return KernelDriverStatus(supported: false);
    }

    final sysRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final nfDriver = File('$sysRoot\\System32\\drivers\\nfdriver.sys');
    final nfFound = nfDriver.existsSync();

    var nfapi = false;
    for (final dir in WindivertDriver.searchDirs()) {
      if (File(_join(dir, 'nfapi.dll')).existsSync()) {
        nfapi = true;
        break;
      }
      if (File(_join(dir, 'nfapi64.dll')).existsSync()) {
        nfapi = true;
        break;
      }
    }

    // 服务状态（NetFilter SDK 的驱动服务通常注册为 nfdriver）。
    var serviceFound = false;
    String? serviceState;
    try {
      final r = await Process.run('sc', ['query', 'nfdriver'], runInShell: true);
      final out = '${r.stdout}${r.stderr}';
      if (out.contains('RUNNING')) {
        serviceFound = true;
        serviceState = 'RUNNING';
      } else if (out.contains('STOPPED')) {
        serviceFound = true;
        serviceState = 'STOPPED';
      } else if (out.contains('PAUSED')) {
        serviceFound = true;
        serviceState = 'PAUSED';
      }
    } catch (_) {
      // sc 不可用则忽略
    }

    final npcapPath1 = '$sysRoot\\System32\\Npcap\\wpcap.dll';
    final npcapPath2 = '$sysRoot\\System32\\wpcap.dll';
    String? npcapPath;
    if (File(npcapPath1).existsSync()) {
      npcapPath = npcapPath1;
    } else if (File(npcapPath2).existsSync()) {
      npcapPath = npcapPath2;
    }

    return KernelDriverStatus(
      supported: true,
      netfilterDriverFound: nfFound,
      netfilterDriverPath: nfFound ? nfDriver.path : null,
      netfilterServiceFound: serviceFound,
      netfilterServiceState: serviceState,
      nfapiFound: nfapi,
      npcapFound: npcapPath != null,
      npcapPath: npcapPath,
    );
  }

  static String _join(String dir, String name) {
    if (dir.endsWith('\\') || dir.endsWith('/')) return '$dir$name';
    return '$dir${Platform.pathSeparator}$name';
  }
}
