import UIKit
import Flutter
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {

    var backgroundAudioEnable: Bool = true

    override func application(_ application: UIApplication,
                              didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let vpnChannel = FlutterMethodChannel.init(name: "com.proxy/proxyVpn", binaryMessenger: controller as! FlutterBinaryMessenger);
        // 注意：这里**不能**给闭包写显式类型标注 `(FlutterMethodCall, FlutterResult) -> Void`——
        // 那会把 result 变成非逃逸参数，任何异步回调（如 getVpnMemory）都会编译失败：
        // "Escaping closure captures non-escaping parameter 'result'"。
        // 交给编译器按 setMethodCallHandler 的签名推断，result 才是 @escaping。
        vpnChannel.setMethodCallHandler({ (call, result) in
            // 每个分支都必须回调 result：漏掉的话 Flutter 侧 `await invokeMethod` 永远不完成。
            // 另外不能把"未知方法"兜底成一次 connect——那样任何新增的通道方法
            // （例如 getQuicBlockedCount）都会意外拉起一次 VPN 连接。
            let arguments = call.arguments as? Dictionary<String, AnyObject>
            switch call.method {
            case "isRunning":
                result(Bool(VpnManager.shared.isRunning()))
            case "startVpn":
                VpnManager.shared.connect(host: arguments?["proxyHost"] as? String,
                                          port: arguments?["proxyPort"] as? Int,
                                          ipProxy: arguments?["ipProxy"] as? Bool,
                                          proxyPassDomains: arguments?["proxyPassDomains"] as? [String])
                result(nil)
            case "stopVpn":
                VpnManager.shared.disconnect()
                result(nil)
            case "restartVpn":
                VpnManager.shared.restartConnect(host: arguments?["proxyHost"] as? String,
                                                 port: arguments?["proxyPort"] as? Int,
                                                 ipProxy: arguments?["ipProxy"] as? Bool,
                                                 proxyPassDomains: arguments?["proxyPassDomains"] as? [String])
                result(nil)
            case "getQuicBlockedCount":
                // iOS 不做 QUIC 拦截计数，明确返回 0
                result(0)
            case "getVpnMemory":
                // 扩展的内存水位（上游 #903）。VPN 未启动 / 拿不到数据时回调 nil，
                // Dart 侧按"不可读"处理，不当作错误。
                // 注意：memorySnapshot 是异步的，其回调是 escaping 闭包；而本 handler 里的
                // result 因显式标注了闭包类型而是非逃逸参数，直接捕获会报
                // "Escaping closure captures non-escaping parameter 'result'"，
                // 因此统一走一个以 @escaping 接收 result 的中转方法。
                self.replyVpnMemory(result)
            default:
                result(FlutterMethodNotImplemented)
            }
        })

        if #available(iOS 13.0.0, *) {
            PictureInPictureManager.regirst(flutter: controller as! FlutterBinaryMessenger)
            MethodHandler.register(with: self.registrar(forPlugin: MethodHandler.name)!)
        }

        if let window = self.window {
            window.rootViewController = controller
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
   }

    override func applicationWillTerminate(_ application: UIApplication) {
        VpnManager.shared.disconnect()
    }

    /// 把扩展内存快照回给 Flutter。
    ///
    /// `result` 必须以 `@escaping` 接收：memorySnapshot 的回调是异步 escaping 闭包，
    /// 而 handler 内联的 result 参数是非逃逸的，直接捕获会编译报错。
    private func replyVpnMemory(_ result: @escaping FlutterResult) {
        VpnManager.shared.memorySnapshot { snapshot in
            result(snapshot)
        }
    }

    var timer: Timer?
    var bgTask: UIBackgroundTaskIdentifier?

    override func applicationDidEnterBackground(_ application: UIApplication) {
        if (!VpnManager.shared.isRunning()) {
            return
        }
    
        timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(timerAction), userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: RunLoop.Mode.common)
               bgTask = application.beginBackgroundTask(expirationHandler: nil)
    }

    @objc func timerAction() {
        print(UIApplication.shared.backgroundTimeRemaining)
        let application = UIApplication.shared
        
        if (bgTask != nil) {
            application.endBackgroundTask(bgTask!);
            bgTask = nil;
        }
        
        if (UIApplication.shared.backgroundTimeRemaining < 60 && VpnManager.shared.isRunning()) {
            bgTask = application.beginBackgroundTask(expirationHandler: nil)
        }
            
        if (application.backgroundTimeRemaining <= 0 || application.applicationState == .active || AudioManager.shared.openBackgroundAudioAutoplay) {
            timer?.invalidate();
            timer = nil;
        }
        
        if (application.backgroundTimeRemaining <= 10) {
            self.backgroundAudio()
        }

    }

    override func applicationWillResignActive(_ application: UIApplication) {
        self.backgroundAudio();
    }
    override  func applicationDidBecomeActive(_ application: UIApplication) {
        self.endBackgroundUpdateTask()
    }
    
    private func backgroundAudio() {
        if (!VpnManager.shared.isRunning() || !self.backgroundAudioEnable) {
            return
        }
        if (AudioManager.shared.openBackgroundAudioAutoplay) {
            return;
        }
        
        AudioManager.shared.openBackgroundAudioAutoplay = true
        self.backgroundUpdateTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            self.endBackgroundUpdateTask()
        })
    }
    
    var backgroundUpdateTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier(rawValue: 0)
    
    func endBackgroundUpdateTask() {
        if (!VpnManager.shared.isRunning() || !AudioManager.shared.openBackgroundAudioAutoplay) {
            return
        }

        AudioManager.shared.openBackgroundAudioAutoplay = false
        UIApplication.shared.endBackgroundTask(self.backgroundUpdateTask)
        self.backgroundUpdateTask = UIBackgroundTaskIdentifier.invalid
    }

}
