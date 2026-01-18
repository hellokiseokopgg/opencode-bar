import Foundation

struct CopilotUsage: Codable {
    let netBilledAmount: Double
    let netQuantity: Double
    let discountQuantity: Double
    let userPremiumRequestEntitlement: Int
    let filteredUserPremiumRequestEntitlement: Int
    
    var usedRequests: Int {
        return Int(discountQuantity)
    }
    
    var limitRequests: Int {
        return userPremiumRequestEntitlement
    }
    
    var usagePercentage: Double {
        guard limitRequests > 0 else { return 0 }
        return (Double(usedRequests) / Double(limitRequests)) * 100
    }
}

struct CachedUsage: Codable {
    let usage: CopilotUsage
    let timestamp: Date
}
