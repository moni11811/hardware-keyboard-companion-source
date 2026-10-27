import Foundation

enum HWCStorePurchaseSelection {
    static func isRepeatableProduct(_ productID: String?, productIDs: [String], unlockProductIDs: [String]) -> Bool {
        guard let productID else { return false }
        return productIDs.contains(productID) && !unlockProductIDs.contains(productID)
    }

    static func bypassesPurchase(usesBetaUnlock: Bool, requestedID: String?, productIDs: [String], unlockProductIDs: [String]) -> Bool {
        usesBetaUnlock && !isRepeatableProduct(requestedID, productIDs: productIDs, unlockProductIDs: unlockProductIDs)
    }

    static func loadsProducts(usesBetaUnlock: Bool, productIDs: [String], unlockProductIDs: [String]) -> Bool {
        !usesBetaUnlock || productIDs.contains {
            isRepeatableProduct($0, productIDs: productIDs, unlockProductIDs: unlockProductIDs)
        }
    }

    static func allowsPurchase(isUnlocked: Bool, requestedProductID: String?) -> Bool {
        requestedProductID != nil || !isUnlocked
    }

    static func product<Value>(requestedID: String?, defaultProduct: Value?, availableProducts: [String: Value]) -> Value? {
        if let requestedID {
            return availableProducts[requestedID]
        }
        return defaultProduct
    }
}

struct HWCSubscriptionEntitlementRecord: Equatable, Sendable {
    let productID: String
    let expirationDate: Date?
    let revocationDate: Date?
}

enum HWCSubscriptionEntitlementPolicy {
    static func isActive(
        records: [HWCSubscriptionEntitlementRecord],
        productIDs: Set<String>,
        now: Date = Date()
    ) -> Bool {
        records.contains { record in
            productIDs.contains(record.productID)
                && record.revocationDate == nil
                && (record.expirationDate.map { $0 > now } ?? false)
        }
    }
}

/// Keeps the first tap on a locked additional-layer control informational, so
/// the following tap is the explicit StoreKit purchase action.
enum HWCAdditionalLayerPurchasePromptAction: Equatable {
    case showPrice
    case purchase
    case add
    case none
}

struct HWCAdditionalLayerPurchasePromptState: Equatable {
    private(set) var isPriceVisible = false

    mutating func tap(
        requiresPurchase: Bool,
        isBusy: Bool
    ) -> HWCAdditionalLayerPurchasePromptAction {
        guard !isBusy else { return .none }
        guard requiresPurchase else {
            isPriceVisible = false
            return .add
        }
        guard isPriceVisible else {
            isPriceVisible = true
            return .showPrice
        }
        return .purchase
    }

    mutating func reset() {
        isPriceVisible = false
    }
}

/// Purchase authority for creating another Additional Layer.
///
/// Restored layer content is deliberately not an input. Cloud snapshots can
/// restore paid content, but only StoreKit-derived credits or unlimited access
/// can authorize creating more paid layers.
enum HWCAdditionalLayerEntitlementPolicy {
    static let purchasedCreditCountKey = "companion.purchase.additionalLayersCreditCount"
    static let unlimitedAccessKey = "companion.purchase.supportDeveloperUnlocked"
    static let layerPurchaseTestingResetEnabledKey = "companion.purchase.additionalLayersTestingResetEnabled"
    static let layerPurchaseTestingResetEnvironmentKey = "HWC_RESET_ADDITIONAL_LAYER_PURCHASES"

    /// This is a debug-only, device-local testing mode. It never changes the
    /// StoreKit ledger and is intentionally stored in the app-group defaults
    /// so the keyboard extension applies the same temporary access gate.
    static var isLayerPurchaseTestingResetActive: Bool {
        #if DEBUG
        return KeyboardSharedPreferences.defaults.bool(
            forKey: layerPurchaseTestingResetEnabledKey
        )
        #else
        return false
        #endif
    }

    @discardableResult
    static func activateLayerPurchaseTestingResetIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = KeyboardSharedPreferences.defaults
    ) -> Bool {
        #if DEBUG
        if environment[layerPurchaseTestingResetEnvironmentKey] == "0" {
            defaults.removeObject(forKey: layerPurchaseTestingResetEnabledKey)
            return false
        }
        guard environment[layerPurchaseTestingResetEnvironmentKey] == "1" else {
            return defaults.bool(forKey: layerPurchaseTestingResetEnabledKey)
        }
        defaults.set(true, forKey: layerPurchaseTestingResetEnabledKey)
        return true
        #else
        return false
        #endif
    }

    static func testingResetBaseline(
        currentCreditsByTransaction: [String: Int],
        existingBaseline: [String: Int]?
    ) -> [String: Int] {
        existingBaseline ?? currentCreditsByTransaction
    }

    static func effectivePurchasedCredits(
        creditsByTransaction: [String: Int],
        baseline: [String: Int]?,
        isTestingResetActive: Bool
    ) -> Int {
        let sanitizedCredits = creditsByTransaction.mapValues { max(0, $0) }
        guard isTestingResetActive else {
            return sanitizedCredits.values.reduce(0, +)
        }
        let baseline = baseline ?? sanitizedCredits
        return sanitizedCredits.reduce(into: 0) { total, entry in
            total += max(0, entry.value - (baseline[entry.key] ?? 0))
        }
    }

    static func canCreateLayer(
        existingLayerCount: Int,
        purchasedCredits: Int,
        hasUnlimitedAccess: Bool
    ) -> Bool {
        (!isLayerPurchaseTestingResetActive && hasUnlimitedAccess)
            || max(0, purchasedCredits) > max(0, existingLayerCount)
    }

    static func canAccessLayer(
        at index: Int,
        purchasedCredits: Int,
        hasUnlimitedAccess: Bool
    ) -> Bool {
        guard index >= 0 else { return false }
        return (!isLayerPurchaseTestingResetActive && hasUnlimitedAccess)
            || index < max(0, purchasedCredits)
    }

    static func canAccessLayer(
        id: UUID,
        in keymap: KeyboardKeymap,
        purchasedCredits: Int,
        hasUnlimitedAccess: Bool
    ) -> Bool {
        guard let index = keymap.customLayers.firstIndex(where: { $0.id == id }) else {
            return false
        }
        return canAccessLayer(
            at: index,
            purchasedCredits: purchasedCredits,
            hasUnlimitedAccess: hasUnlimitedAccess
        )
    }

    static func canAccessLayer(
        id: UUID,
        in keymap: KeyboardKeymap,
        defaults: UserDefaults = KeyboardSharedPreferences.defaults
    ) -> Bool {
        canAccessLayer(
            id: id,
            in: keymap,
            purchasedCredits: defaults.integer(forKey: purchasedCreditCountKey),
            hasUnlimitedAccess: defaults.bool(forKey: unlimitedAccessKey)
        )
    }

    static func publishPurchasedCredits(
        _ count: Int,
        defaults: UserDefaults = KeyboardSharedPreferences.defaults
    ) {
        defaults.set(max(0, count), forKey: purchasedCreditCountKey)
        KeyboardSharedPreferences.postSettingsDidChangeNotification()
    }

    static func publishUnlimitedAccess(
        _ enabled: Bool,
        defaults: UserDefaults = KeyboardSharedPreferences.defaults
    ) {
        defaults.set(enabled, forKey: unlimitedAccessKey)
        KeyboardSharedPreferences.postSettingsDidChangeNotification()
    }
}
