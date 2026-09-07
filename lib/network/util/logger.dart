import 'package:logger/logger.dart';
export 'package:logger/logger.dart' show Logger, PrettyPrinter, Level;

/// 由 UI 层注册（LogManager），把每次运行日志同步进内存队列，
/// 供「日志管理」页实时查看。
void Function(Level level, String message, Object? error, StackTrace? stackTrace)? logBridge;

/// 桥接打印机：格式化输出交给 PrettyPrinter（控制台），同时把原始日志转发到内存队列。
/// 在 Printer(log(LogEvent)) 层桥接：logger 2.x 的 OutputEvent 已不含
/// message/error 字段，而 LogEvent 各版本字段稳定（level/message/error/stackTrace）。
class _BridgingPrinter extends LogPrinter {
  final PrettyPrinter _inner;

  _BridgingPrinter()
      : _inner = PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 15,
          lineLength: 120,
          colors: true,
          printEmojis: false,
          excludeBox: {Level.info: true, Level.debug: true},
        );

  @override
  List<String> log(LogEvent event) {
    try {
      final msg = switch (event.message) {
        String s => s,
        null => '',
        dynamic other => other.toString(),
      };
      logBridge?.call(event.level, msg, event.error, event.stackTrace);
    } catch (_) {/* 桥接失败不影响控制台输出 */}
    return _inner.log(event);
  }
}

final logger = Logger(
  // 关键：默认 DevelopmentFilter 的 shouldLog 整段包在 assert 里，
  // release 构建断言被剥离后恒为 false，所有日志被静默过滤（日志页空白）。
  // 显式使用 ProductionFilter 并放开到 debug 级，release 同样记录。
  filter: ProductionFilter()..level = Level.debug,
  printer: _BridgingPrinter(),
);
