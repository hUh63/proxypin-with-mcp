/*
 * HTTPS MITM 全链路端到端测试（真实 socket + 真实证书，不含任何 mock 代理）。
 *
 * 覆盖：
 *   1) 环境前置：Paths.homePath() 可用（CA 配置落盘依赖它）
 *   2) 证书签发：CertificateManager 按 host 签发叶子证书（SAN/CN/issuer 正确）+ 缓存语义
 *   3) SNI 分流：用一次**真实 TLS 握手**产生的 ClientHello，验证 TLS.getDomain 解析 SNI，
 *      并用该 SNI 签发对应叶子证书
 *   4) MITM 全链路：本地 HTTPS 服务（自签证书）<- CONNECT <- proxypin 代理 <-
 *      dart:io HttpClient(findProxy)。断言代理侧拿到**明文** method/url/headers/body
 *      与明文响应体，客户端拿到正确状态码与 body。
 *
 * 注意：不打 @Tags(['integration'])，因此 `flutter test --exclude-tags integration` 会真实执行。
 *
 * 说明：CA 初始化走 Paths.homePath()（内部为 path_provider）。测试里对
 * plugins.flutter.io/path_provider 做了 mock 兜底（Linux 上若 Dart 版 path_provider
 * 实现已注册则该 mock 不会被使用），并把 assets/certs 下的 CA 预置进临时 home，
 * 这样 CertificateManager 无需读 rootBundle。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/crypto.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/tls.dart';
import 'package:proxypin/storage/path.dart';

// 兜底超时：任何一环（TLS 握手 / 转发）死锁时宁可让用例失败，也不要挂死 CI。
@Timeout(Duration(seconds: 90))

/// 捕获代理侧明文事件的监听器。
class _Capture extends EventListener {
  final List<HttpRequest> requests = [];
  final List<HttpResponse> responses = [];

  @override
  void onRequest(Channel channel, HttpRequest request) => requests.add(request);

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) => responses.add(response);
}

/// 轮询等待「代理侧看到带 body 的响应」——响应体可能比 onResponse 回调晚一步就绪。
Future<HttpResponse> _waitResponseWithBody(_Capture capture,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final r in capture.responses) {
      if (r.body != null && r.body!.isNotEmpty) return r;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('代理侧超时未拿到响应体：'
      '${capture.responses.map((r) => '${r.status.code}/body=${r.body?.length}').toList()}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory work;
  late io.ServerSocket sniProbe;
  final sniProbeBytes = <int>[];
  var sniProbeCaptured = Completer<void>();

  setUpAll(() async {
    // 临时 home：CA 文件写到这里，避免污染真实用户目录。
    work = await io.Directory.systemTemp.createTemp('proxypin-mitm-');
    FileRead.userHome = work.path;

    // path_provider 兜底：Linux CI 上若原生/Dart 实现已注册，此 mock 不会被触发。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => work.path,
    );

    // 预置 CA（CertificateManager.certificateFile()/privateKeyFile() 存在则不读 assets）
    for (final name in ['ca.crt', 'ca_key.pem']) {
      final src = io.File('assets/certs/$name');
      if (await src.exists()) {
        await src.copy('${work.path}${io.Platform.pathSeparator}$name');
      }
    }
  });

  tearDownAll(() async {
    FileRead.userHome = null;
    try {
      await work.delete(recursive: true);
    } catch (_) {}
  });

  group('前置与证书签发', () {
    test('Paths.homePath() 可用且可写（否则 MITM 无法签发证书）', () async {
      final home = await Paths.homePath();
      expect(io.Directory(home).existsSync(), isTrue, reason: 'home 目录必须真实存在：$home');
      expect(await CertificateManager.generateLeafCertificatePem('example.com'), contains('BEGIN CERTIFICATE'));
    });

    test('按 host 签发叶子证书：SAN 命中、issuer 来自 CA、同 host 命中缓存', () async {
      final caCert = CertificateManager.caCert ?? (await CertificateManager.getCertificateDetails());
      final leafPem = await CertificateManager.generateLeafCertificatePem('leaf.example.com');
      final leaf = X509Utils.x509CertificateFromPem(leafPem);

      expect(leaf.subjectAlternativNames, contains('leaf.example.com'));
      expect(leaf.subject.values.whereType<String>().any((v) => v.contains('leaf.example.com')), isTrue,
          reason: 'subject CN 应指向目标域名：${leaf.subject}');

      final caValues = caCert.subject.values.whereType<String>().toSet();
      final issuerValues = leaf.issuer.values.whereType<String>().toSet();
      expect(issuerValues.intersection(caValues), isNotEmpty,
          reason: '叶子证书 issuer 必须来自仓库 CA 的 subject DN：issuer=$issuerValues ca=$caValues');

      // 同 host 复用同一个 SecurityContext（ExpiringCache），不同 host 必须重签。
      final ctxA = await CertificateManager.getCertificateContext('leaf.example.com');
      final ctxB = await CertificateManager.getCertificateContext('leaf.example.com');
      expect(identical(ctxA, ctxB), isTrue);

      final otherPem = await CertificateManager.generateLeafCertificatePem('other.example.com');
      expect(otherPem, isNot(leafPem));
      expect(X509Utils.x509CertificateFromPem(otherPem).subjectAlternativNames, contains('other.example.com'));
    });

    test('SNI 分流：真实 ClientHello 的 SNI 被解析并用于签发对应叶子证书', () async {
      final sniHost = 'mitm-sni-probe.test';
      sniProbeBytes.clear();
      sniProbeCaptured = Completer<void>();

      sniProbe = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
      sniProbe.listen((socket) {
        socket.listen((data) {
          sniProbeBytes.addAll(data);
          // ClientHello 可能被 TCP 分片，攒到能解析出 SNI 为止。
          if (!sniProbeCaptured.isCompleted && TLS.getDomain(Uint8List.fromList(sniProbeBytes)) != null) {
            sniProbeCaptured.complete();
          }
        }, onError: (_) {}, onDone: () {});
      });

      // 先裸 TCP 连上，再用 SecureSocket.secure 指定 SNI（避免依赖 DNS 解析假域名）。
      final raw = await io.Socket.connect(io.InternetAddress.loopbackIPv4, sniProbe.port);
      unawaited(() async {
        try {
          final s = await io.SecureSocket.secure(raw, host: sniHost, onBadCertificate: (_) => true);
          s.destroy();
        } catch (_) {
          raw.destroy();
        }
      }());

      await sniProbeCaptured.future.timeout(const Duration(seconds: 15),
          onTimeout: () => fail('未在超时前从真实 ClientHello 中解析出 SNI（收到 ${sniProbeBytes.length} 字节）'));

      final data = Uint8List.fromList(sniProbeBytes);
      expect(TLS.isTLSClientHello(data), isTrue, reason: '第一个报文必须是 TLS ClientHello');
      expect(TLS.getDomain(data), sniHost);

      // SNI -> 叶子证书：SAN 必须命中 SNI 域名（这正是 MITM 分流的核心）
      final ctx = await CertificateManager.getCertificateContext(TLS.getDomain(data)!);
      expect(ctx, isNotNull);
      final ctxCacheHit = identical(ctx, await CertificateManager.getCertificateContext(sniHost));
      expect(ctxCacheHit, isTrue, reason: '同一 SNI 必须命中同一 SecurityContext');

      final pem = await CertificateManager.generateLeafCertificatePem(sniHost);
      expect(X509Utils.x509CertificateFromPem(pem).subjectAlternativNames, contains(sniHost));

      await sniProbe.close();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('HTTPS MITM 全链路', () {
    late Server proxy;
    late io.HttpServer origin;
    late _Capture capture;
    late int proxyPort;
    late int originPort;
    late io.HttpClient client;

    setUp(() async {
      capture = _Capture();

      // 1) 上游：真实 HTTPS 服务，证书由仓库 CA 签发（所以代理侧 outbound 校验也能过）
      final caPem = await io.File('assets/certs/ca.crt').readAsString();
      final caRoot = X509Utils.x509CertificateFromPem(caPem);
      final caKey = CryptoUtils.rsaPrivateKeyFromPem(await io.File('assets/certs/ca_key.pem').readAsString());
      final keyPair = CryptoUtils.generateRSAKeyPair();
      final certPem = X509Utils.generateSelfSignedCertificate(
        caRoot,
        keyPair.publicKey as RSAPublicKey,
        caKey,
        30,
        sans: ['127.0.0.1', 'localhost'],
        serialNumber: '9001',
      );
      final context = io.SecurityContext()
        ..useCertificateChainBytes(utf8.encode(certPem))
        ..usePrivateKeyBytes(utf8.encode(CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(keyPair.privateKey as RSAPrivateKey)));

      origin = await io.HttpServer.bindSecure(io.InternetAddress.loopbackIPv4, 0, context);
      originPort = origin.port;
      origin.listen((req) async {
        final chunks = <int>[];
        await for (final chunk in req) {
          chunks.addAll(chunk);
        }
        final text = utf8.decode(chunks, allowMalformed: true);
        req.response.headers.contentType = io.ContentType.text;
        req.response.write(text.isEmpty ? 'hello-from-https-origin' : 'echo:$text');
        await req.response.close();
      });

      // 2) 代理：真实 Server，开启 HTTPS 抓包（enableSsl）
      final config = Configuration.fromJson({
        'enableSsl': true,
        'enableSocks5': false,
        'enableSystemProxy': false,
        'enabledHttp2': false,
      });
      proxy = Server(config, listener: capture);
      proxy.initChannel((channel) {
        channel.dispatcher.handle(
          HttpRequestCodec(),
          HttpResponseCodec(),
          HttpProxyChannelHandler(listener: capture, interceptors: []),
        );
      });
      proxyPort = (await proxy.bind(0)).port;

      // 3) 客户端：HttpClient 走代理；不校验证书（代理是自签 CA）
      client = io.HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';
    });

    tearDown(() async {
      client.close(force: true);
      await proxy.stop();
      await origin.close(force: true);
    });

    test('GET https：代理侧可见明文 method/url/headers，客户端拿到 200', () async {
      final request = await client.getUrl(Uri.parse('https://127.0.0.1:$originPort/hello?x=1'));
      request.headers.set('X-Mitm-Probe', 'plaintext-header');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(response.statusCode, 200);
      expect(body, 'hello-from-https-origin');

      // 代理侧：必须看到解密后的明文请求
      expect(capture.requests, isNotEmpty, reason: 'MITM 未把明文请求交给 listener');
      final seen = capture.requests.single;
      expect(seen.method, HttpMethod.get);
      expect(seen.requestUrl, 'https://127.0.0.1:$originPort/hello?x=1');
      expect(seen.headers.get('X-Mitm-Probe'), 'plaintext-header');
      expect(seen.headers.host, '127.0.0.1:$originPort');
      expect(seen.protocolVersion, 'HTTP/1.1');

      // 代理侧：必须看到明文响应体
      final seenResp = await _waitResponseWithBody(capture);
      expect(seenResp.status.code, 200);
      expect(utf8.decode(seenResp.body!, allowMalformed: true), 'hello-from-https-origin');
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('POST https：请求体（明文）与响应体都可被代理捕获', () async {
      const payload = '{"user":"明文 body","n":42}';
      final request = await client.postUrl(Uri.parse('https://127.0.0.1:$originPort/api/echo'));
      request.headers.contentType = io.ContentType.json;
      request.write(payload);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(response.statusCode, 200);
      expect(body, 'echo:$payload');

      expect(capture.requests, isNotEmpty);
      final seen = capture.requests.single;
      expect(seen.method, HttpMethod.post);
      expect(seen.requestUrl, 'https://127.0.0.1:$originPort/api/echo');
      expect(seen.body, isNotNull);
      expect(utf8.decode(seen.body!, allowMalformed: true), payload);

      final seenResp = await _waitResponseWithBody(capture);
      expect(utf8.decode(seenResp.body!, allowMalformed: true), 'echo:$payload');
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
