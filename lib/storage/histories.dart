/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:date_format/date_format.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/utils/files.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/saz.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:share_plus/share_plus.dart';

///历史存储
///@Author WangHongEn
class HistoryStorage {
  static HistoryStorage? _instance;
  final File _storageFile;
  static final StreamController<HistoryItem> _remoteImportedController = StreamController<HistoryItem>.broadcast();

  /// 串行写队列：所有 refresh() 按顺序执行，避免并发全量重写导致文件交错/截断
  Future<void> _writeQueue = Future.value();

  HistoryStorage._internal(this._storageFile);

  static final ListenableList<HistoryItem> _histories = ListenableList();

  ///单例
  static Future<HistoryStorage> get instance async {
    if (_instance == null) {
      var file = await Paths.getPath("histories.json");
      _instance = HistoryStorage._internal(file);
      await _instance!._init();
    }
    return _instance!;
  }

  //初始化
  Future<void> _init() async {
    if (await _storageFile.exists()) {
      var content = await _storageFile.readAsString();
      if (content.trim().isEmpty) {
        return;
      }
      try {
        var list = jsonDecode(content) as List<dynamic>;
        for (var entry in list) {
          _histories.add(HistoryItem.formJson(entry));
        }
      } catch (e) {
        logger.e("历史记录解析错误", error: e);
      }
    }
  }

  static Future<String> _homePath() async {
    // 便携模式下历史同样跟随程序目录（上游 #285）
    final home = await Paths.homePath();
    return '$home${Platform.pathSeparator}history';
  }

  /// 获取历史记录
  List<HistoryItem> get histories {
    return _histories.source;
  }

  static Stream<HistoryItem> get onRemoteImported => _remoteImportedController.stream;

  static const String remoteHistoryPrefix = '[Remote] ';

  void addListener(ListenerListEvent<HistoryItem> listener) {
    _histories.addListener(listener);
  }

  void removeListener(ListenerListEvent<HistoryItem> listener) {
    _histories.removeListener(listener);
  }

  ///打开文件
  static Future<File> openFile(String name) async {
    final homePath = await _homePath();
    var file = File('$homePath${Platform.pathSeparator}$name');
    return file.create(recursive: true);
  }

  /// 添加历史记录
  Future<HistoryItem> addHistory(String name, File file, int requestLength) async {
    var historyItem = HistoryItem(name, file.path, requestLength, await file.length());
    _histories.add(historyItem);
    await refresh();
    return historyItem;
  }

  int getIndex(HistoryItem item) {
    return _histories.indexOf(item);
  }

  //更新
  Future<void> updateHistory(int index, HistoryItem item) async {
    _histories.update(index, item);
    await refresh();
  }

  //获取
  HistoryItem getHistory(int index) {
    return _histories.source[index];
  }

  /// 刷新持久化文件：串行执行，避免并发写同一文件
  Future<void> refresh() {
    // 队列一旦因一次写失败进入 error 状态，后续所有 .then 都不再执行：
    // 本次运行内新增/删除历史全部只在内存里，重启后消失，且日志一条没有。
    // 每次写入前吃掉上一次的错误。
    _writeQueue = _writeQueue.catchError((Object e, StackTrace s) {
      logger.e('保存历史列表失败', error: e, stackTrace: s);
    }).then((_) async {
      try {
        await _storageFile.writeAsString(jsonEncode(_histories.source));
      } catch (e, s) {
        logger.e('保存历史列表失败', error: e, stackTrace: s);
      }
    });
    return _writeQueue;
  }

  ///删除
  Future<void> removeHistory(int index) async {
    var history = _histories.removeAt(index);
    logger.i('删除历史记录 $history');
    final homePath = await _homePath();
    var file = File('$homePath${Platform.pathSeparator}${Files.getName(history.path)}');
    // 文件可能已被外部清理（用户清 history 目录 / 便携模式切换路径）。
    // 旧实现这里抛异常就跳过 refresh，histories.json 仍留着这一项，
    // 下次启动「删掉的历史」又出现。
    try {
      if (await file.exists()) await file.delete();
    } catch (e, s) {
      logger.w('删除历史文件失败 ${file.path}', error: e, stackTrace: s);
    }
    await refresh();
  }

  //获取请求列表
  Future<List<HttpRequest>> getRequests(HistoryItem history) async {
    history.requests ??= await readRequests(history);

    return history.requests!;
  }

  /// 从历史文件读取请求列表，不写入 [HistoryItem.requests] 永久缓存。
  ///
  /// 供 MCP 等按需分析的调用方使用：返回的列表只由调用方做有界缓存，
  /// 淘汰后即可被回收，避免大历史会话长期常驻内存。同时刷新数量/大小元数据。
  Future<List<HttpRequest>> readRequests(HistoryItem history) async {
    final homePath = await _homePath();
    String path = '$homePath${Platform.pathSeparator}${Files.getName(history.path)}';
    var file = File(path);
    var requests = await Har.readFile(file);
    history.requestLength = requests.length;
    file.length().then((size) => history.fileSize = size);
    return requests;
  }

  ///刷新requests
  Future<void> flushRequests(HistoryItem history, List<HttpRequest> requests) async {
    logger.i("刷新历史记录 $history");
    final homePath = await _homePath();
    String path = '$homePath${Platform.pathSeparator}${Files.getName(history.path)}';
    var file = File(path);
    for (int i = 0; i < requests.length; i++) {
      var request = requests[i];
      var har = Har.toHar(request);
      await file.writeAsString("${jsonEncode(har)},\n", mode: i == 0 ? FileMode.write : FileMode.append);
    }

    history.requestLength = requests.length;
    await file.length().then((size) => history.fileSize = size);
    await refresh();
  }

  Future<HistoryItem> addRequests(Iterable<HttpRequest> requests,
      {String? name, bool notifyRemoteImported = false}) async {
    final list = requests.toList();
    final historyFile = await HistoryStorage.openFile("${DateTime.now().millisecondsSinceEpoch}.txt");
    final open = await historyFile.open(mode: FileMode.append);
    try {
      for (var request in list) {
        await open.writeString(jsonEncode(Har.toHar(request)));
        await open.writeString(",\n");
      }
    } finally {
      await open.close();
    }

    var historyName = (name == null || name.trim().isEmpty)
        ? formatDate(DateTime.now(), [mm, '-', d, ' ', HH, ':', nn, ':', ss])
        : name;
    if (notifyRemoteImported) {
      final hasRemotePrefix = historyName.startsWith(remoteHistoryPrefix) || historyName.startsWith('【远程】');
      if (!hasRemotePrefix) {
        historyName = '$remoteHistoryPrefix$historyName';
      }
    }
    final historyItem = await addHistory(historyName, historyFile, list.length);
    if (notifyRemoteImported) {
      _remoteImportedController.add(historyItem);
    }
    return historyItem;
  }

  //添加历史
  Future<HistoryItem> addHarFile(XFile file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content);
    // 标准 HAR 必须有 log.entries。缺字段时给出明确错误，
    // 而不是在 log['pages'] / log['entries'] 上抛 NoSuchMethodError，
    // 让用户只看到「导入失败: NoSuchMethodError」。
    final log = json is Map ? json['log'] : null;
    if (log is! Map || log['entries'] is! List) {
      throw const FormatException('不是有效的 HAR 文件（缺少 log.entries）');
    }

    String name = formatDate(DateTime.now(), [mm, '-', d, ' ', HH, ':', nn, ':', ss]);
    final pages = log['pages'];
    if (pages is List && pages.isNotEmpty && pages.first is Map) {
      final title = (pages.first as Map)['title']?.toString();
      if (title != null && title.trim().isNotEmpty) name = title;
    }

    // 逐条容错：单条坏 entry 不再让整份历史导入失败
    return addRequests(Har.readEntries(log['entries'] as List), name: name);
  }

  /// 从 Fiddler SAZ 文件导入历史（解成 HAR entry 后复用 Har.toRequest）。
  Future<HistoryItem> addSazFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final entries = SazParser.parse(bytes);
    final list = entries.map((e) => Har.toRequest(e)).toList();

    var base = file.name.split(RegExp(r'[\\/]')).last;
    if (base.toLowerCase().endsWith('.saz')) base = base.substring(0, base.length - 4);
    final name = base.trim().isEmpty
        ? formatDate(DateTime.now(), [mm, '-', d, ' ', HH, ':', nn, ':', ss])
        : base;

    return addRequests(list, name: name);
  }
}

class HistoryTask extends ListenerListEvent<HttpRequest> {
  HistoryItem? history;
  Timer? timer;
  final Queue writeList = Queue();

  RandomAccessFile? open;
  bool locked = false;
  int _idleTicks = 0;

  /// 写入串行化标记。
  ///
  /// `Timer.periodic` 不会等待上一次 async 回调结束：数据量大或磁盘慢时上一轮
  /// 还没写完下一轮就进来了，两个 while 循环同时 `removeFirst` 并写同一个文件，
  /// 行会交错甚至半行截断。这里用标记跳过重叠轮次。
  bool _writing = false;

  static HistoryTask? _instance;

  final Configuration configuration;
  final ListenableList<HttpRequest> sourceList;

  HistoryTask(this.configuration, this.sourceList) {
    logger.d("start history task");
    if (configuration.historyCacheTime != 0) {
      sourceList.addListener(this);
      Future.delayed(const Duration(seconds: 3), () => cleanHistory());
    }
  }

  static HistoryTask ensureInstance(Configuration configuration, ListenableList<HttpRequest> sourceList) {
    return _instance ??= HistoryTask(configuration, sourceList);
  }

  //清理历史数据
  Future<void> cleanHistory() async {
    if (configuration.historyCacheTime == 0) {
      return;
    }
    var overdueTime = DateTime.now().subtract(Duration(days: configuration.historyCacheTime));
    var historyStorage = await HistoryStorage.instance;
    var histories = historyStorage.histories;
    for (int i = 0; i < histories.length; i++) {
      if (histories.elementAt(i).createTime.isBefore(overdueTime)) {
        await historyStorage.removeHistory(i);
        i--;
      }
    }
  }

  @override
  void onAdd(HttpRequest item) {
    if (history == null) {
      startTask();
      return;
    }
    // 空闲暂停后恢复写入
    if (timer == null) startTask();
    writeList.add(item);
  }

  @override
  void onRemove(HttpRequest item) => resetList();

  @override
  void onBatchRemove(List<HttpRequest> items) => resetList();

  @override
  void clear(List<HttpRequest> items) => resetList();

  Future<void> resetList() async {
    locked = true;
    await open?.lock().timeout(Duration(seconds: 3), onTimeout: () => open!.unlock());
    open = await open?.truncate(0);
    await open?.setPosition(0);
    history?.requestLength = 0;
    history?.requests = null;
    writeList.clear();
    writeList.addAll(sourceList.source);
    locked = false;
    open?.unlock();
  }

  void cancelTask() {
    timer?.cancel();
    timer = null;
    open?.close();
    open = null;
    history = null;
    sourceList.removeListener(this);
    writeList.clear();
  }

  //写入任务
  Future<void> startTask() async {
    if (history != null && timer != null) return;
    if (locked) return;
    locked = true;

    if (history == null) {
      HistoryStorage storage = await HistoryStorage.instance;
      var name = formatDate(DateTime.now(), [mm, '-', d, ' ', HH, ':', nn, ':', ss]);
      File file = await HistoryStorage.openFile("${DateTime.now().millisecondsSinceEpoch}.txt");
      history = await storage.addHistory(name, file, 0);
      writeList.clear();
      writeList.addAll(sourceList.source);
    } else if (open == null) {
      // 空闲暂停后恢复：重新打开已有历史文件，继续追加
      open = await File(history!.path).open(mode: FileMode.append);
    }

    locked = false;

    timer ??= Timer.periodic(const Duration(seconds: 5), (it) => writeTask());
  }

  //写入任务
  Future<void> writeTask() async {
    if (_writing) return;
    _writing = true;
    try {
      await _writeTaskBody();
    } finally {
      _writing = false;
    }
  }

  Future<void> _writeTaskBody() async {
    if (writeList.isEmpty) {
      // 空闲自动暂停：连续 6 次（约 30 秒）无新数据时释放定时器与文件句柄，
      // 避免代理停止后 timer/句柄长期驻留（资源泄漏）。有数据时 onAdd 自动恢复。
      _idleTicks++;
      if (_idleTicks >= 6 && timer != null) {
        timer?.cancel();
        timer = null;
        open?.close();
        open = null;
        _idleTicks = 0;
        logger.d('history task idle, paused');
      }
      return;
    }

    _idleTicks = 0;
    bool changed = false;
    while (writeList.isNotEmpty && !locked) {
      // cancelTask() 可能在 await 期间把 open/history 置空（停止抓包），
      // 之前这里用 `open?.` 静默跳过写入、却继续 `history!` 强解包 → 空指针。
      final writer = open;
      final current = history;
      if (writer == null || current == null) {
        return;
      }

      var request = writeList.removeFirst();
      var har = Har.toHar(request);

      await writer.writeString("${jsonEncode(har)},\n");

      current.requestLength++;
      changed = true;
    }

    if (!changed) return;
    final writer = open;
    final current = history;
    if (writer == null || current == null) {
      return;
    }
    current.fileSize = await writer.length();
    current.requests = null;
    var historyStorage = await HistoryStorage.instance;
    historyStorage.updateHistory(historyStorage.getIndex(current), current);
  }
}

/// 历史记录
class HistoryItem {
  String name;
  final String path; // 文件路径
  int requestLength = 0; // 请求数量
  int? fileSize; // 文件大小
  DateTime createTime = DateTime.now();

  List<HttpRequest>? requests;

  HistoryItem(this.name, this.path, this.requestLength, this.fileSize, {DateTime? createTime})
      : createTime = createTime ?? DateTime.now();

  /// 稳定会话 id：历史文件名里的时间戳（{epochMs}.txt）。
  ///
  /// 不随列表增删改变，可作为 MCP history_id；删除中间某条历史后旧 id 也不会
  /// 错位指向别的会话。极旧/异常命名解析不出时退化为路径 hash（同进程内稳定）。
  int get stableId {
    var fileName = Files.getName(path);
    if (fileName.endsWith('.txt')) {
      fileName = fileName.substring(0, fileName.length - '.txt'.length);
    }
    return int.tryParse(fileName) ?? path.hashCode;
  }

  //json反序列化
  factory HistoryItem.formJson(Map<String, dynamic> map) {
    return HistoryItem(map['name'], map['path'], map['requestLength'], map['fileSize'],
        createTime: map['createTime'] == null ? null : DateTime.fromMillisecondsSinceEpoch(map['createTime']));
  }

  //json序列化
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'requestLength': requestLength,
      'fileSize': fileSize,
      'createTime': createTime.millisecondsSinceEpoch,
    };
  }

  //获取文件大小
  String get size {
    if (this.fileSize == null) {
      return "";
    }

    int fileSize = this.fileSize!;
    if (fileSize > 1024 * 1024) {
      return "${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB";
    }

    return "${(fileSize / 1024).toStringAsFixed(1)}KB";
  }

  @override
  String toString() {
    return "$path $requestLength $fileSize";
  }
}
