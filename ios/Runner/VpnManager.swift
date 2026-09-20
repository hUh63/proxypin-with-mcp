let kProxyServiceVPNStatusNotification = "kProxyServiceVPNStatusNotification"

import Foundation
import NetworkExtension

enum VPNStatus {
    case off
    case connecting
    case on
    case disconnecting
}


class VpnManager{
    var activeVPN: NETunnelProviderManager?;
    
    public var proxyHost: String = "127.0.0.1"
    public var proxyPort: Int = 9099
    public var ipProxy: Bool = false
    public var proxyPassDomains: [String]?

    static let shared = VpnManager()
    var observerAdded: Bool = false


    fileprivate(set) var vpnStatus = VPNStatus.off {
        didSet {
            NotificationCenter.default.post(name: Notification.Name(rawValue: kProxyServiceVPNStatusNotification), object: nil)
        }
    }

    init() {
        loadProviderManager{
            guard let manager = $0 else{return}
            self.updateVPNStatus(manager)
        }
        addVPNStatusObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func addVPNStatusObserver() {
        guard !observerAdded else{
            return
        }
        loadProviderManager { [unowned self] (manager) -> Void in
            if let manager = manager {
                self.observerAdded = true
                NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: manager.connection, queue: OperationQueue.main, using: { [unowned self] (notification) -> Void in
                    
                    self.updateVPNStatus(manager)
                    
                    if (manager.connection.status == .invalid || manager.connection.status == .disconnected){
                       
                        print("VPN断开: \(String(describing: manager.debugDescription))")
                    }
                })
            }
        }
    }


    func updateVPNStatus(_ manager: NEVPNManager) {
        switch manager.connection.status {
        case .connected:
            self.vpnStatus = .on
        case .connecting, .reasserting:
            self.vpnStatus = .connecting
        case .disconnecting:
            self.vpnStatus = .disconnecting
        case .disconnected, .invalid:
            self.vpnStatus = .off
        @unknown default: break

        }
    }
}

// load VPN Profiles
extension VpnManager{

    fileprivate func createProviderManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let conf = NETunnelProviderProtocol()
        conf.serverAddress = "ProxyPin"
        manager.protocolConfiguration = conf
        manager.localizedDescription = "ProxyPin"
        return manager
    }

    func loadAndCreatePrividerManager(_ complete: @escaping (NETunnelProviderManager?) -> Void ){
        NETunnelProviderManager.loadAllFromPreferences{ [self] (managers, error) in
            guard let managers = managers else{return}
            let manager: NETunnelProviderManager
            if managers.count > 0 {
                manager = managers[0]
            }else{
                manager = self.createProviderManager()
            }
   
            var conf = [String:AnyObject]()
            conf["proxyHost"] = self.proxyHost as AnyObject
            conf["proxyPort"] = self.proxyPort as AnyObject
            conf["ipProxy"] = self.ipProxy as AnyObject
            // Bridge Swift [String] to NSArray (Objective-C) before inserting into AnyObject dictionary
            if let passDomains = self.proxyPassDomains {
                conf["proxyPassDomains"] = passDomains as NSArray
            }

            // protocolConfiguration 正常一定是本 App 写入的 NETunnelProviderProtocol，
            // 但已有配置缺失/类型不符时强转会直接崩溃——这里退化成重建一份配置
            let orignConf: NETunnelProviderProtocol
            if let exist = manager.protocolConfiguration as? NETunnelProviderProtocol {
                orignConf = exist
            } else {
                print("VPN 配置缺失或类型不符，重建 provider protocol")
                let fresh = NETunnelProviderProtocol()
                fresh.serverAddress = "ProxyPin"
                manager.protocolConfiguration = fresh
                orignConf = fresh
            }
 
            orignConf.providerConfiguration = conf
            manager.protocolConfiguration = orignConf
            
            print(orignConf)
            manager.isEnabled = true
            manager.saveToPreferences{
                if ($0 != nil){
//                    complete(nil);
//                    return;
                }
                manager.loadFromPreferences{
                    if $0 != nil{
                        print("loadFromPreferences",$0.debugDescription)
                        complete(nil);return;
                    }
                    self.addVPNStatusObserver()
                    complete(manager)
                }
            }

        }
    }

    func loadProviderManager(_ complete: @escaping (NETunnelProviderManager?) -> Void){
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let managers = managers {
                if managers.count > 0 {
                    let manager = managers[0]
                    complete(manager)
                    return
                }
            }
            complete(nil)
        }
    }

}

// Actions
extension VpnManager{
    
    func connect(host: String?, port: Int?, ipProxy: Bool? = false, proxyPassDomains: [String]? = nil) {
        self.proxyHost = host ?? self.proxyHost
        self.proxyPort = port ?? self.proxyPort
        self.ipProxy = ipProxy ?? false
        self.proxyPassDomains = proxyPassDomains ?? self.proxyPassDomains

        self.loadAndCreatePrividerManager { (manager) in
            guard let manager = manager else{return}
            do{
                self.activeVPN = manager
                try manager.connection.startVPNTunnel()
            }catch let err{
                print("connect: ", err)
            }
        }
    }
    
    func restartConnect(host: String?, port: Int?, ipProxy: Bool? = false, proxyPassDomains: [String]? = nil) {
        self.proxyHost = host ?? self.proxyHost
        self.proxyPort = port ?? self.proxyPort
        self.ipProxy = ipProxy ?? false

        if (activeVPN != nil) {
            activeVPN?.connection.stopVPNTunnel()
            activeVPN = nil
        }
        
        self.connect(host: host, port: port, ipProxy: ipProxy, proxyPassDomains: proxyPassDomains)
    }

    func disconnect() {
        if (activeVPN != nil) {
            activeVPN?.connection.stopVPNTunnel()
            activeVPN = nil
            return
        }
        
        loadProviderManager{
            $0?.connection.stopVPNTunnel()
        }
    }
    
    func isRunning() -> Bool {
        return vpnStatus == VPNStatus.on
    }

    /// 向扩展拉取内存水位快照（上游 #903）。扩展未运行或拿不到数据时回调 nil。
    ///
    /// 扩展（NEPacketTunnelProvider）与 App 是两个进程，只能通过 sendProviderMessage 通信；
    /// 扩展侧在 handleAppMessage 里识别 "memory" 并回 JSON。
    func memorySnapshot(_ complete: @escaping ([String: Any]?) -> Void) {
        guard let session = activeVPN?.connection as? NETunnelProviderSession else {
            complete(nil)
            return
        }
        guard let request = "memory".data(using: .utf8) else {
            complete(nil)
            return
        }

        do {
            try session.sendProviderMessage(request) { response in
                var snapshot: [String: Any]?
                if let response = response,
                   let object = try? JSONSerialization.jsonObject(with: response) {
                    snapshot = object as? [String: Any]
                }
                // 该回调线程不确定，统一回主线程再交给 Flutter，避免 result 在非主线程回调
                DispatchQueue.main.async {
                    complete(snapshot)
                }
            }
        } catch {
            print("memorySnapshot failed: \(error)")
            complete(nil)
        }
    }

}
