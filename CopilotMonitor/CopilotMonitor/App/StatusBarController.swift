import AppKit
import SwiftUI
import ServiceManagement
import WebKit
import os.log

private let logger = Logger(subsystem: "com.copilotmonitor", category: "StatusBarController")

struct CopilotUsage: Codable {
    let table: UsageTable?
    var limitRequestsValue: Int = 0
    
    struct UsageTable: Codable {
        let rows: [UsageRow]?
    }
    
    struct UsageRow: Codable {
        let id: String?
        let cells: [UsageCell]?
    }
    
    struct UsageCell: Codable {
        let value: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case table
    }
    
    var usedRequests: Int {
        guard let rows = table?.rows else { return 0 }
        return rows.reduce(0) { total, row in
            guard let cells = row.cells else { return total }
            
            let includedStr = cells.indices.contains(1) ? cells[1].value?.replacingOccurrences(of: ",", with: "") ?? "0" : "0"
            let billedStr = cells.indices.contains(2) ? cells[2].value?.replacingOccurrences(of: ",", with: "") ?? "0" : "0"
            
            let included = Double(includedStr) ?? 0
            let billed = Double(billedStr) ?? 0
            return total + Int(included + billed)
        }
    }
    
    var limitRequests: Int { return limitRequestsValue }
    
    var usagePercentage: Double {
        guard limitRequests > 0 else { return 0 }
        return (Double(usedRequests) / Double(limitRequests)) * 100
    }
}

struct CopilotCardResponse: Codable {
    let userPremiumRequestEntitlement: Int?
}

struct CachedUsage: Codable {
    let usage: CopilotUsage
    let timestamp: Date
}

enum UsageFetcherError: LocalizedError {
    case noCustomerId
    case noUsageData
    case invalidJSResult
    
    var errorDescription: String? {
        switch self {
        case .noCustomerId: return "Customer ID를 찾을 수 없습니다"
        case .noUsageData: return "사용량 데이터를 찾을 수 없습니다"
        case .invalidJSResult: return "JS 결과가 올바르지 않습니다"
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var usageItem: NSMenuItem!
    private var signInItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var refreshTimer: Timer?
    
    private var currentUsage: CopilotUsage?
    private var lastFetchTime: Date?
    private var isFetching = false
    
    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
        setupNotificationObservers()
        startRefreshTimer()
        logger.info("init 완료")
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "..."
    }
    
    private func setupMenu() {
        menu = NSMenu()
        usageItem = NSMenuItem(title: "Used: -/-", action: nil, keyEquivalent: "")
        usageItem.isEnabled = false
        menu.addItem(usageItem)
        menu.addItem(NSMenuItem.separator())
        signInItem = NSMenuItem(title: "Sign In", action: #selector(signInClicked), keyEquivalent: "")
        signInItem.target = self
        menu.addItem(signInItem)
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let openBillingItem = NSMenuItem(title: "Open Billing", action: #selector(openBillingClicked), keyEquivalent: "b")
        openBillingItem.target = self
        menu.addItem(openBillingItem)
        menu.addItem(NSMenuItem.separator())
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(launchAtLoginClicked), keyEquivalent: "")
        launchAtLoginItem.target = self
        updateLaunchAtLoginState()
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(forName: Notification.Name("billingPageLoaded"), object: nil, queue: .main) { [weak self] _ in
            logger.info("노티 수신: billingPageLoaded")
            Task { @MainActor in
                self?.fetchUsage()
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("sessionExpired"), object: nil, queue: .main) { [weak self] _ in
            logger.info("노티 수신: sessionExpired")
            Task { @MainActor in
                self?.updateUIForLoggedOut()
            }
        }
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            logger.info("타이머 트리거")
            Task { @MainActor in
                self?.triggerRefresh()
            }
        }
        triggerRefresh()
    }
    
    func triggerRefresh() {
        logger.info("triggerRefresh 시작")
        AuthManager.shared.loadBillingPage()
    }
    
    private func fetchUsage() {
        logger.info("fetchUsage 시작, isFetching: \(self.isFetching)")
        guard !isFetching else { return }
        isFetching = true
        statusItem.button?.title = "..."
        
        Task {
            let webView = AuthManager.shared.webView
            
            var customerId: String? = nil
            var fetchSuccess = false
            
            logger.info("fetchUsage: [Step 1] API(/api/v3/user)를 통한 ID 확보 시도")
            let userApiJS = """
            return await (async function() {
                try {
                    const response = await fetch('/api/v3/user', {
                        headers: { 'Accept': 'application/json' }
                    });
                    if (!response.ok) return JSON.stringify({ error: 'HTTP ' + response.status });
                    const data = await response.json();
                    return JSON.stringify(data);
                } catch (e) {
                    return JSON.stringify({ error: e.toString() });
                }
            })()
            """
            
            do {
                let result = try await webView.callAsyncJavaScript(userApiJS, arguments: [:], in: nil, contentWorld: .defaultClient)
                
                if let jsonString = result as? String,
                   let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? Int {
                    customerId = String(id)
                    logger.info("fetchUsage: API ID 확보 성공 - \(id)")
                } else {
                    logger.error("fetchUsage: API ID 확보 실패 (Result: \(String(describing: result)))")
                }
            } catch {
                logger.error("fetchUsage: API 호출 중 에러 - \(error.localizedDescription)")
            }
            
            if customerId == nil {
                logger.info("fetchUsage: [Step 2] DOM 추출 시도")
                let extractionJS = """
                return (function() {
                    const el = document.querySelector('script[data-target="react-app.embeddedData"]');
                    if (el) {
                        try {
                            const data = JSON.parse(el.textContent);
                            if (data && data.payload && data.payload.customer && data.payload.customer.customerId) {
                                return data.payload.customer.customerId.toString();
                            }
                        } catch(e) {}
                    }
                    return null;
                })()
                """
                if let extracted: String = try? await evalJSONString(extractionJS, in: webView) {
                    customerId = extracted
                    logger.info("fetchUsage: DOM에서 customerId 추출 성공 - \(extracted)")
                }
            }
            
            if customerId == nil {
                logger.info("fetchUsage: [Step 3] HTML Regex 시도")
                do {
                    let htmlJS = "return document.documentElement.outerHTML"
                    if let html = try? await webView.callAsyncJavaScript(htmlJS, arguments: [:], in: nil, contentWorld: .defaultClient) as? String {
                        let patterns = [
                            #"customerId":(\d+)"#,
                            #"customerId&quot;:(\d+)"#,
                            #"customer_id=(\d+)"#,
                            #"data-customer-id="(\d+)""#
                        ]
                        for pattern in patterns {
                            if let regex = try? NSRegularExpression(pattern: pattern),
                               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                               let range = Range(match.range(at: 1), in: html) {
                                customerId = String(html[range])
                                logger.info("fetchUsage: HTML에서 ID 발견 - \(customerId!)")
                                break
                            }
                        }
                    }
                }
            }
            
            if let validCustomerId = customerId {
                logger.info("fetchUsage: [Step 4] API(copilot_usage_table) 데이터 조회 시도")
                let fetchJS = """
                return await (await fetch('/settings/billing/copilot_usage_table?customer_id=\(validCustomerId)&group=7&period=3&query=&page=1', {
                    headers: {
                        'accept': 'application/json',
                        'content-type': 'application/json',
                        'x-requested-with': 'XMLHttpRequest'
                    }
                })).json()
                """
                
                do {
                    var usage: CopilotUsage = try await evalJSON(fetchJS, in: webView)
                    logger.info("fetchUsage: Table 데이터 조회 성공")
                    
                    logger.info("fetchUsage: [Step 4.5] API(copilot_usage_card) 한도 정보 조회 시도")
                    let cardJS = """
                    return await (async function() {
                        try {
                            const res = await fetch('/settings/billing/copilot_usage_card?customer_id=\(validCustomerId)&period=3', {
                                headers: { 'Accept': 'application/json', 'x-requested-with': 'XMLHttpRequest' }
                            });
                            return await res.json();
                        } catch(e) { return null; }
                    })()
                    """
                    
                    if let cardResult = try? await webView.callAsyncJavaScript(cardJS, arguments: [:], in: nil, contentWorld: .defaultClient) {
                        if let cardDict = cardResult as? [String: Any] {
                            if let limit = cardDict["user_premium_request_entitlement"] as? Int {
                                usage.limitRequestsValue = limit
                                logger.info("fetchUsage: 한도 정보 확보 성공 (Snake) - \(limit)")
                            } else if let limit = cardDict["userPremiumRequestEntitlement"] as? Int {
                                usage.limitRequestsValue = limit
                                logger.info("fetchUsage: 한도 정보 확보 성공 (Camel) - \(limit)")
                            }
                        }
                    }
                    
                    self.currentUsage = usage
                    self.lastFetchTime = Date()
                    self.updateUIForSuccess(usage: usage)
                    self.saveCache(usage: usage)
                    fetchSuccess = true
                } catch {
                    logger.error("fetchUsage: API 데이터 조회 실패 - \(error.localizedDescription)")
                }
            }
            
            if !fetchSuccess {
                logger.error("fetchUsage: 모든 시도 실패.")
                await MainActor.run {
                    self.statusItem.button?.title = "Err"
                    self.usageItem.title = "데이터 갱신 실패"
                }
                self.handleFetchError(UsageFetcherError.noUsageData)
            }
            
            self.isFetching = false
            logger.info("fetchUsage Task 완료")
        }
    }
    
    private func evalJSONString(_ js: String, in webView: WKWebView) async throws -> String {
        let result = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .defaultClient)
        
        if let json = result as? String {
            return json
        } else if let dict = result as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let json = String(data: data, encoding: .utf8) {
            return json
        } else {
            throw UsageFetcherError.invalidJSResult
        }
    }
    
    private func evalJSON<T: Decodable>(_ js: String, in webView: WKWebView) async throws -> T {
        logger.info("evalJSON 시작")
        
        do {
            logger.info("evalJSON: callAsyncJavaScript 호출 직전")
            let result = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .defaultClient)
            
            let typeName = String(describing: type(of: result))
            logger.info("evalJSON: callAsyncJavaScript 완료, type=\(typeName, privacy: .public)")
            
            if let str = result as? String {
                NSLog("Raw JSON (String): %@", str)
                let decoded = try JSONDecoder().decode(T.self, from: Data(str.utf8))
                logger.info("evalJSON: 파싱 완료 (String)")
                return decoded
            } else if let dict = result as? [String: Any] {
                if let data = try? JSONSerialization.data(withJSONObject: dict),
                   let str = String(data: data, encoding: .utf8) {
                    NSLog("Raw JSON (Dict): %@", str)
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    logger.info("evalJSON: 파싱 완료 (Dictionary)")
                    return decoded
                }
            }
            
            let resultDesc = String(describing: result)
            logger.error("evalJSON: result가 유효하지 않음 - result=\(resultDesc, privacy: .public)")
            throw UsageFetcherError.invalidJSResult
            
        } catch {
            logger.error("evalJSON 실패: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    private func updateUIForSuccess(usage: CopilotUsage) {
        if usage.limitRequests > 0 {
            statusItem.button?.title = "\(Int(usage.usagePercentage))%"
            usageItem.title = "Used: \(usage.usedRequests) / \(usage.limitRequests)"
        } else {
            statusItem.button?.title = "\(usage.usedRequests)"
            usageItem.title = "Used: \(usage.usedRequests) (No Limit Info)"
        }
        signInItem.isHidden = true
    }
    
    private func updateUIForLoggedOut() {
        statusItem.button?.title = "?"
        usageItem.title = "로그인 필요"
        signInItem.isHidden = false
    }
    
    private func handleFetchError(_ error: Error) {
        if let cached = loadCache() {
            statusItem.button?.title = "\(Int(cached.usage.usagePercentage))% (Old)"
            usageItem.title = "Used: \(cached.usage.usedRequests) / \(cached.usage.limitRequests) (Cached)"
        } else {
            statusItem.button?.title = "Err"
            usageItem.title = "Update Failed"
            NSLog("Fetch Error: %@", error.localizedDescription)
        }
    }
    
    @objc private func signInClicked() {
        NotificationCenter.default.post(name: Notification.Name("sessionExpired"), object: nil)
    }
    
    @objc private func refreshClicked() {
        triggerRefresh()
    }
    
    @objc private func openBillingClicked() {
        if let url = URL(string: "https://github.com/settings/billing/premium_requests_usage") { NSWorkspace.shared.open(url) }
    }
    
    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
    
    @objc private func launchAtLoginClicked() {
        let service = SMAppService.mainApp
        try? (service.status == .enabled ? service.unregister() : service.register())
        updateLaunchAtLoginState()
    }
    
    private func updateLaunchAtLoginState() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    
    private func saveCache(usage: CopilotUsage) {
        if let data = try? JSONEncoder().encode(CachedUsage(usage: usage, timestamp: Date())) {
            UserDefaults.standard.set(data, forKey: "copilot.usage.cache")
        }
    }
    
    private func loadCache() -> CachedUsage? {
        guard let data = UserDefaults.standard.data(forKey: "copilot.usage.cache") else { return nil }
        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }
}
