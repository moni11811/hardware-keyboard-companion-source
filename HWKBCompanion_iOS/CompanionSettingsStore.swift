import Combine
import Foundation
import StoreKit
import SwiftUI
import UIKit

private struct CompanionUnlockConfiguration {
    let purchasedKey: String
    let productIDs: [String]
    let unlockProductIDs: [String]
    let purchaseTitle: String
    let loadingErrorMessage: String
    let pendingProductMessage: String
    let purchasedStatusMessage: String
    let restoredStatusMessage: String
    let restoreMissMessage: String
    let betaUnlockedMessage: String
    let marksUnlockedOnPurchase: Bool
    let requiresActiveEntitlement: Bool
    let permitsLayerPurchaseTestingReset: Bool
}

private extension CompanionUnlockConfiguration {
    static let abc = CompanionUnlockConfiguration(
        purchasedKey: "companion.purchase.abcUnlockPurchased",
        productIDs: ["dev.moni11811.hwkbcompanion.unlock_abc_v3"],
        unlockProductIDs: ["dev.moni11811.hwkbcompanion.unlock_abc_v3"],
        purchaseTitle: "Unlock ABC",
        loadingErrorMessage: "ABC unlock could not be loaded from the App Store.",
        pendingProductMessage: "ABC unlock is still loading. Try again in a moment.",
        purchasedStatusMessage: "ABC customization is now unlocked.",
        restoredStatusMessage: "Your ABC unlock purchase was restored.",
        restoreMissMessage: "No previous ABC unlock purchase was found for this Apple ID.",
        betaUnlockedMessage: "ABC customization is already available in this build.",
        marksUnlockedOnPurchase: true,
        requiresActiveEntitlement: false,
        permitsLayerPurchaseTestingReset: false
    )

    static let hardwarePremium = CompanionUnlockConfiguration(
        purchasedKey: "companion.purchase.hardwarePremiumUnlocked",
        productIDs: ["dev.moni11811.hwkbcompanion.unlock_hardware_keyboard_premium_v4"],
        unlockProductIDs: ["dev.moni11811.hwkbcompanion.unlock_hardware_keyboard_premium_v4"],
        purchaseTitle: HWCBuildFlavor.hardwareKeypressPaidPurchaseTitle,
        loadingErrorMessage: "Hardware Keyboard Premium Features could not be loaded from the App Store.",
        pendingProductMessage: "Hardware Keyboard Premium Features are still loading. Try again in a moment.",
        purchasedStatusMessage: "Your previous Reader purchase is recognized. Reader has been removed; please contact HWC Support about your purchase.",
        restoredStatusMessage: "Your previous Reader purchase was restored. Reader remains unavailable; please contact HWC Support about your purchase.",
        restoreMissMessage: "No previous Hardware Keyboard Premium purchase was found for this Apple ID.",
        betaUnlockedMessage: "Hardware Keypress beta is already available in this build.",
        marksUnlockedOnPurchase: true,
        requiresActiveEntitlement: false,
        permitsLayerPurchaseTestingReset: false
    )

    static let additionalLayers = CompanionUnlockConfiguration(
        purchasedKey: "companion.purchase.additionalLayersUnlocked",
        productIDs: ["dev.moni11811.hwkbcompanion.additional_layer_credit_v3"],
        unlockProductIDs: [],
        purchaseTitle: "Buy Additional Layer",
        loadingErrorMessage: "Additional Layers could not be loaded from the App Store.",
        pendingProductMessage: "Additional Layers is still loading. Try again in a moment.",
        purchasedStatusMessage: "Additional Layer added.",
        restoredStatusMessage: "Your Additional Layer purchases were restored.",
        restoreMissMessage: "No previous Additional Layer purchases were found for this Apple ID.",
        betaUnlockedMessage: "Additional Layers are already available in this build.",
        marksUnlockedOnPurchase: false,
        requiresActiveEntitlement: false,
        permitsLayerPurchaseTestingReset: true
    )

    static let supportDeveloper = CompanionUnlockConfiguration(
        purchasedKey: "companion.purchase.supportDeveloperUnlocked",
        productIDs: [
            "dev.moni11811.hwkbcompanion.buyburger_v3",
            "dev.moni11811.hwkbcompanion.buycoffee_v3",
            "dev.moni11811.hwkbcompanion.support_developer_yearly_v4"
        ],
        unlockProductIDs: ["dev.moni11811.hwkbcompanion.support_developer_yearly_v4"],
        purchaseTitle: "Support the Developer",
        loadingErrorMessage: "Support Developer could not be loaded from the App Store.",
        pendingProductMessage: "Support Developer is still loading. Try again in a moment.",
        purchasedStatusMessage: "Yearly support is active.",
        restoredStatusMessage: "Your Support Developer purchase was restored.",
        restoreMissMessage: "No active Support Developer purchase was found for this Apple ID.",
        betaUnlockedMessage: "Support Developer is already active in this build.",
        marksUnlockedOnPurchase: true,
        requiresActiveEntitlement: true,
        permitsLayerPurchaseTestingReset: false
    )
}

enum SupportDeveloperThankYouKind {
    case coffee
    case burger
    case yearly
}

struct SupportDeveloperThankYouPrompt {
    let kind: SupportDeveloperThankYouKind
    let title: String
    let message: String
    let steps: [String]
}

struct CompanionReleaseNotesSnapshot {
    let version: String
    let build: String
    let recordedAt: Date
    let latestChanges: [String]
}

private struct CompanionReleaseNotesBatch {
    let build: Int
    let recordedAt: Date
    let changes: [String]
}

enum CompanionReleaseNotesStore {
    // Update this snapshot and add or edit the matching file in Changelog/build-<build>.md when release notes change.
    static let current = CompanionReleaseNotesSnapshot(
        version: appVersion,
        build: appBuild,
        recordedAt: visibleBatches.first?.recordedAt ?? Date(timeIntervalSince1970: 1776796712),
        latestChanges: visibleBatches.flatMap(\.changes)
    )

    private static let allBatches: [CompanionReleaseNotesBatch] = [
        CompanionReleaseNotesBatch(
            build: 191,
            recordedAt: Date(timeIntervalSince1970: 1793059200),
            changes: [
                "Refresh visible suggestion chips during continued on-screen typing",
                "Keep suggestions selection-only, with no automatic text replacement"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 190,
            recordedAt: Date(timeIntervalSince1970: 1793049614),
            changes: [
                "Improved live suggestions during on-screen typing and host text updates",
                "Reduced repeated prediction-model loading during typing"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 189,
            recordedAt: Date(timeIntervalSince1970: 1793030400),
            changes: [
                "Improved live suggestions during continuous typing",
                "Reduced typing-path work from unused model checks",
                "Updated globe key visibility when input-mode requirements change"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 188,
            recordedAt: Date(timeIntervalSince1970: 1792785274),
            changes: [
                "Fixed TestFlight delivery of the version 3 app and keyboard update"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 187,
            recordedAt: Date(timeIntervalSince1970: 1790104113),
            changes: [
                "Import and export selected Live Keyboard Editor layers as private .hwclayer files without replacing existing layers or presets",
                "Edit or clone keyboard templates while keeping built-in originals available alongside saved copies",
                "Backup History now shows loading, slow, and failure states with a safe refresh path",
                "Clipboard snippets now fail closed if their encryption key cannot be stored securely",
                "Upward Lane Word swipes commit the visible lane where the gesture finishes, while quick released or cancelled presses avoid stale feedback",
                "Hardware Keyboard Reading has been removed. We’re sorry for the disruption to people who relied on it; your saved layouts, settings, and purchase records are preserved"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 170,
            recordedAt: Date(timeIntervalSince1970: 1784691298),
            changes: [
                "First-time setup is now one compact screen with Hardware-only guidance and live Full Access status",
                "Suggestions anchor near likely next letters across 3, 6, or 9 slots, while Lane swipe selects its word directly",
                "Typing is faster and more accurate; Main Row selections stay in Main Row and Send restarts suggestions cleanly",
                "Rolodex gestures, hold selection, visual feedback, dismissal, and the empty Dark suggestion rail are more reliable",
                "Keymap Editor adds cross-layer scrubbing plus compact Additional Layer and complete Key Blocks editors",
                "Settings now uses a compact Mode selector and unified Autobot, Text Behaviour, Hold Behaviour, and Hardware Keyboard sections"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 169,
            recordedAt: Date(timeIntervalSince1970: 1784499701),
            changes: [
                "Rapid typing immediately after keyboard startup no longer capitalizes the first two letters",
                "Startup key handling now consumes one-shot capitalization before processing the next tap"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 166,
            recordedAt: Date(timeIntervalSince1970: 1783425600),
            changes: [
                "The swipe-right Clipboard panel keeps snippet saves explicit and local",
                "Autocorrect outcome learning stays local and uses aggregate signals only"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 163,
            recordedAt: Date(timeIntervalSince1970: 1783391532),
            changes: [
                "Hardware autocorrect selector now moves from left or right back through the middle suggestion",
                "The unsupported Ctrl + arrows selector option has been removed; Option + arrows remains the selector shortcut"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 162,
            recordedAt: Date(timeIntervalSince1970: 1783388911),
            changes: [
                "Suggestions now use the previous word for context, so the bar offers the word you meant mid-sentence",
                "Typos with a missing or doubled letter now show the right correction in the suggestion bar",
                "The keyboard no longer replaces a typed word on its own — corrections only appear as suggestions you tap",
                "Control Mode stays on Custom until you explicitly pick Hardware or Software"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 158,
            recordedAt: Date(timeIntervalSince1970: 1782884532),
            changes: [
                "Plain-English rule maker now builds specific saved rules for unquoted word corrections and sentence edits",
                "Saved generated rules can be added to the left, middle, or right suggestion lane and jump Advanced to that lane",
                "Custom generated rule chips only appear in lanes that own that exact rule"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 157,
            recordedAt: Date(timeIntervalSince1970: 1782601200),
            changes: [
                "Reply/Reaction/Edit in Messages App caused the keyboard to collapse the view but stay expanded",
                "Hardware key relay could stall typing by rewriting the shared event ring per key",
                "Encrypted clipboard could slow launch by decrypting/sorting too many saved snippets",
                "Large clipboard paste could hang keyboard; paste is now capped and chunked",
                "Glide typing rebuilt the full lexicon on each gesture; lexicon is now cached and capped",
                "Oversized custom keymap could block launch before decode; now rejected before decode",
                "Missed hardware key-up could leave repeat running; repeat now has a max runtime",
                "Delete hold/Delete Forward could loop too many deletes on the main path; now capped",
                "Unicode Delete Forward replay used scalar counts with complex scripts; now plans deletes safely",
                "Custom dictionary/adaptive autocomplete could scan oversized stores; now trimmed on read",
                "Autocorrect V2 model/spell-check path removed from synchronous keypress flow",
                "Icon updated to fill (wip on new icon has started)"
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 156,
            recordedAt: Date(timeIntervalSince1970: 1782597600),
            changes: [
                "Updates the app icon asset so the keyboard artwork fills the icon frame instead of appearing shrunken.",
                "Keeps the Messages keyboard relaunch height fix, iOS 27 CoreML autocorrect ranking, Hardware Reader, Rolodex, Lane Word, and Keymap behavior from the current release."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 155,
            recordedAt: Date(timeIntervalSince1970: 1782586800),
            changes: [
                "Fixes a Messages keyboard relaunch issue where editing or reacting to a message could restore the keyboard at a clipped height.",
                "Keeps the iOS 27 CoreML autocorrect ranking, Hardware Reader, Rolodex, Lane Word, and Keymap behavior from the current lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 154,
            recordedAt: Date(timeIntervalSince1970: 1782504000),
            changes: [
                "Re-cuts the corrected App Review StoreKit product set (ABC V3, Hardware Keyboard Reader V4, Additional Layer V3, coffee V3, burger V3, yearly support V4) as a fresh App Store submission build.",
                "Keeps the iOS 27 CoreML autocorrect ranking, Hardware Reader, Rolodex, Lane Word, and Keymap behavior from the current lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 153,
            recordedAt: Date(timeIntervalSince1970: 1782417600),
            changes: [
                "Moves Hardware Keyboard Reader from V3 to V4 for App Review.",
                "Keeps the other fresh App Review StoreKit requests on their current V3/V4 product IDs."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 150,
            recordedAt: Date(timeIntervalSince1970: 1782408600),
            changes: [
                "Keeps all App Review StoreKit requests on the fresh V2/V3 product IDs.",
                "Allows version-tag archives to use the committed build number when hosted build-number environment variables are absent.",
                "Adds the missing About release notes metadata required by the pre-archive release guard."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 147,
            recordedAt: Date(timeIntervalSince1970: 1782333000),
            changes: [
                "Rebuilds the review upload so App Store processing uses Apple's current Xcode RC toolchain.",
                "Blocks stale Xcode 26.5 SDK archives before App Store Connect export."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 146,
            recordedAt: Date(timeIntervalSince1970: 1782328200),
            changes: [
                "Rebuilds the review upload from the public release channel so paid gates remain locked until StoreKit purchase or restore.",
                "Adds an App Store Connect upload guard that blocks development archives before export."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 145,
            recordedAt: Date(timeIntervalSince1970: 1782321000),
            changes: [
                "Renames the About navigation title and tightens the About hero copy around desktop-style row typing.",
                "Reorganizes the Support the Developer card into active status, included unlocks, subscription terms, and legal links.",
                "Keeps yearly support legal links readable above the floating tab bar."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 144,
            recordedAt: Date(timeIntervalSince1970: 1782312000),
            changes: [
                "Regenerates the app icon set with centered safe-area padding so the keyboard artwork is not edge-crammed in TestFlight or on device.",
                "Adds an app icon regression test that fails when the marketing icon artwork exceeds the safe visual bounds."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 143,
            recordedAt: Date(timeIntervalSince1970: 1782307200),
            changes: [
                "Hides the yearly Support purchase and restore controls once yearly support is active.",
                "Stops the Support thank-you modal from replaying when StoreKit restores or replays transactions on app launch.",
                "Adds ABC Unlock to the yearly Support thank-you modal and keeps ABC Unlock, unlimited Additional Layers, and Hardware Keyboard Reading under yearly support."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 142,
            recordedAt: Date(timeIntervalSince1970: 1782303600),
            changes: [
                "Keeps ABC customization behind its own ABC Unlock purchase instead of yearly support.",
                "Yearly support now unlocks only unlimited Additional Layers and Hardware Keyboard Reading.",
                "Preserves the required subscription length, App Store price line, Privacy Policy link, and Apple Terms of Use link in the purchase flow."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 141,
            recordedAt: Date(timeIntervalSince1970: 1782300000),
            changes: [
                "Adds the required yearly support subscription length, App Store price line, Privacy Policy link, and Apple Terms of Use link to the in-app purchase flow.",
                "Shows the yearly support unlocks explicitly: unlimited Additional Layers and Hardware Keyboard Reading.",
                "Keeps the yearly product ID on the public release path and adds a retry control for App Store product loading."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 137,
            recordedAt: Date(timeIntervalSince1970: 1782200000),
            changes: [
                "Removes hard-coded prices from the purchase copy so every price shown comes straight from the App Store.",
                "Redesigns the coffee, burger, and yearly support thank-you screens as a polished animated card with tailored artwork and a celebratory finish.",
                "Cleans up the ABC customization unlock wording.",
                "Keeps the iOS 27 CoreML autocorrect ranking, Hardware Reader, Rolodex, Lane Word, and Keymap behavior from the current lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 136,
            recordedAt: Date(timeIntervalSince1970: 1782100000),
            changes: [
                "Lists ABC customization and Hardware Reading on the yearly Support the Developer card so the features yearly support unlocks are all shown.",
                "Polishes the Finish Setup splash with a cleaner restart step card and a themed keyboard activation field that no longer looks cut off.",
                "Rewrites a confusing About page line into a plain note about customizing your keymap.",
                "Keeps the iOS 27 CoreML autocorrect ranking, Hardware Reader, Rolodex, Lane Word, and Keymap behavior from the current lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 135,
            recordedAt: Date(timeIntervalSince1970: 1782000000),
            changes: [
                "Fixes the Additional Layers card so yearly Support the Developer shows as unlimited: it now shows an Unlimited Layers unlocked status and hides the purchased-layer count and the Restore and Buy buttons while the subscription is active.",
                "Leaves the layer count and purchase flow unchanged for supporters without yearly who still rely on individually purchased layer credits.",
                "Keeps the iOS 27 CoreML autocorrect ranking, Hardware Reader, Rolodex, Lane Word, and Keymap behavior from the current lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 134,
            recordedAt: Date(timeIntervalSince1970: 1781913600),
            changes: [
                "Fixes the keyboard layout becoming malformed when editing or reacting to a message by forcing the full keyboard height on host re-presentation.",
                "Keeps the Hardware Reading setup and troubleshooting steps visible after unlocking so the guidance no longer disappears once purchased.",
                "Corrects the yearly Support the Developer product identifier so the App Store can load the subscription.",
                "Keeps the iOS 27 CoreML autocorrect ranking, Hardware Reader, Rolodex, Lane Word, and Keymap behavior from the current lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 133,
            recordedAt: Date(timeIntervalSince1970: 1781395200),
            changes: [
                "Adds iOS 27 CoreML autocorrect ranking so likely corrections outrank typed echoes while staying suggestion-only until explicit accept.",
                "Adds an iOS 27 typing-quality Evaluations harness for autocorrect regressions outside the shipping keyboard target.",
                "Restores the Hardware Reader AssistiveTouch shortcut directly under the Keymap test field.",
                "Keeps the Rolodex, Lane Word, and Keymap behavior from the current tester lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 132,
            recordedAt: Date(timeIntervalSince1970: 1781223943),
            changes: [
                "Keeps autocorrect, punctuation, and hardware-observed corrections suggestion-only until explicit accept.",
                "Preserves the iOS 26.6 hardware reader while keeping the iOS 27 shadow-context fallback additive.",
                "Keeps the Rolodex, Lane Word, and Keymap behavior from the current tester lane.",
                "Records the no-auto simulator proof before EddyPhone testing."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 130,
            recordedAt: Date(timeIntervalSince1970: 1781308800),
            changes: [
                "Restores in-app purchase gates so paid features and support purchases require a purchase instead of unlocking automatically on this build.",
                "Removes the extra one-time app purchase so the store shows only the supported products.",
                "Keeps the Rolodex, Lane Word, and Keymap behavior from the current tester lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 124,
            recordedAt: Date(timeIntervalSince1970: 1780697092),
            changes: [
                "Restores Hardware Keyboard Reading across every tester and App Store lane so the app and keyboard extension both include the reader.",
                "Keeps Hardware Keyboard Reading available after the user enables the feature and has entitlement.",
                "Keeps Hardware Keyboard Reading off by default on fresh installs while ensuring the paid feature is present and functional."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 123,
            recordedAt: Date(timeIntervalSince1970: 1780686424),
            changes: [
                "Restores the build 111 Hardware Keyboard Reading path so hardware keypresses are handled correctly.",
                "Corrects external TestFlight release channels so public tester lanes use the App Store release channel with their tester audience.",
                "Keeps Hardware Keyboard Reading off by default and purchase-gated on fresh installs while preserving public availability."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 111,
            recordedAt: Date(timeIntervalSince1970: 1780437953),
            changes: [
                "About restores quick links for HWC app settings and AssistiveTouch settings.",
                "About keeps the latest Testflight hardware-reading notes while preserving developer-only tools."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 110,
            recordedAt: Date(timeIntervalSince1970: 1780429500),
            changes: [
                "Testflight keeps Hardware Keyboard Reading enabled for the trusted TestFlight path.",
                "Testflight keeps Hardware Keyboard Reading settings visible without exposing developer-only tools."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 109,
            recordedAt: Date(timeIntervalSince1970: 1779927708),
            changes: [
                "Testflight disables keyboard gestures while the Clipboard panel is open.",
                "Rolodex Lane Word swipe now applies the selected lane word in the same motion.",
                "Rolodex selection now clears after a fresh key tap or another lane starts.",
                "Testflight keeps the Lane Word and Keymap behavior from the current tester lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 108,
            recordedAt: Date(timeIntervalSince1970: 1779839817),
            changes: [
                "Testflight autocorrect now rejects ambiguous apostrophe-only replacements such as `were` to `we're`.",
                "Testflight keeps unambiguous contractions such as `cant` to `can't`.",
                "Testflight keeps the Rolodex, Lane Word, and Keymap behavior from the current tester lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 105,
            recordedAt: Date(timeIntervalSince1970: 1779604063),
            changes: [
                "Testflight removes the duplicate Minimize Onscreen Keyboard control from Hardware Keyboard Reading.",
                "Hardware Keyboard Reading now tells users to restart the device when Shift or Caps Lock stops reading.",
                "Keyboard extensions now launch with a self-sizing `UIInputView` so the first frame owns its final height before host normalization.",
                "Rolodex suggestions keep one-word and down-only commit behavior through repeated suggestion cycles.",
                "Lane Word gestures separate top-chip commits from lower-lane word swipe gestures.",
                "Keymap editing saves row edits, swaps, resize changes, presets, and custom layers through iCloud Settings Sync.",
                "Symbols hold previews show the held key above the key, and swiping up selects it.",
                "Paste and Clipboard keys now use separate actions, with a compact clipboard panel.",
                "Settings ownership is cleaner: Hardware Keyboard Reading stays in Settings, hardware monitor stays in Premium, and layout sizing stays in Keymap."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 104,
            recordedAt: Date(timeIntervalSince1970: 1778340848),
            changes: [
                "Testflight restores Hardware Keyboard Reading settings in the companion app.",
                "Testflight keeps trusted hardware input active in the keyboard while preserving the settings controls."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 103,
            recordedAt: Date(timeIntervalSince1970: 1778335377),
            changes: [
                "Easter egg movement now faces the correct direction and tracks score more clearly.",
                "Height sliders keep endpoint minus and plus controls for steadier tuning."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 102,
            recordedAt: Date(timeIntervalSince1970: 1778330961),
            changes: [
                "Keymap changes now save to iCloud Settings Sync immediately.",
                "Testflight carries the current keyboard test lane."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 101,
            recordedAt: Date(timeIntervalSince1970: 1777768448),
            changes: [
                "Version notes use less revealing hardware-key language.",
                "Testflight keeps the existing Shift, Caps Lock, and shortcut-letter recovery."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 100,
            recordedAt: Date(timeIntervalSince1970: 1777766412),
            changes: [
                "Testflight restores hardware key reading for existing installs with older settings.",
                "Hardware Shift, Caps Lock, and modifier-letter paths recover on existing TestFlight installs."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 99,
            recordedAt: Date(timeIntervalSince1970: 1777764577),
            changes: [
                "Testflight restores hardware Shift and Caps Lock in the trusted path.",
                "Testflight update repair re-arms hardware keyboard reading when older settings disabled it.",
                "Modifier tracking stays live whenever trusted hardware input is enabled."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 98,
            recordedAt: Date(timeIntervalSince1970: 1777748024),
            changes: [
                "Idle keyboard polling no longer refreshes suggestions when text is unchanged.",
                "Prediction reuse now works in Testflight release builds.",
                "Hardware calibration choices stay intact after app foregrounding.",
                "Calibration timer redraws only while timed calibration is active."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 97,
            recordedAt: Date(timeIntervalSince1970: 1777499904),
            changes: [
                "Shift and Caps Lock control is restored for hardware letter keys.",
                "Premium stays visible and uses the payment gate in Testflight.",
                "Default ABC touch layer protects only actual letter keys.",
                "Setup now links to HWC app settings and AssistiveTouch settings."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 85,
            recordedAt: Date(timeIntervalSince1970: 1777134069),
            changes: [
                "Premium wording is cleaner for tester builds.",
                "Hardware Keyboard Calibration now uses App Check and Keyboard Check language.",
                "Settings can restore after reinstall when iCloud Settings Sync is enabled.",
                "Glide typing handles rougher paths more reliably.",
                "TestFlight feedback guidance is clearer."
            ]
        ),
        CompanionReleaseNotesBatch(
            build: 83,
            recordedAt: Date(timeIntervalSince1970: 1777039200),
            changes: [
                "Version notes now match the installed build.",
                "TestFlight readiness checks are stricter.",
                "Invalid update data keeps the last good settings.",
                "Saved clip labels get stronger privacy protection.",
                "Damaged saved clips are ignored safely."
            ]
        )
    ]

    private static var visibleBatches: [CompanionReleaseNotesBatch] {
        let minimumBuild = max(appBuildNumber - 1, 0)
        return allBatches
            .filter { $0.build >= minimumBuild }
            .sorted { $0.build > $1.build }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private static var appBuildNumber: Int {
        Int(appBuild) ?? 0
    }
}

@MainActor
class CompanionUnlockStore: NSObject, ObservableObject {
    private static let localPurchaseResetBuildKey = "companion.purchase.localResetBuild"
    private let maxInvalidProductLoadRetries = 3
    private let invalidProductRetryDelay: TimeInterval = 2
    private let configuration: CompanionUnlockConfiguration
    private let storeInteractionEnabled: Bool
    private let allowsNewPurchases: Bool
    private var usesBetaUnlockBypass: Bool
    @Published fileprivate(set) var isUnlocked: Bool {
        didSet { unlockStateDidChange() }
    }
    @Published private(set) var priceLabel = ""
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPurchasing = false
    @Published fileprivate(set) var isRestoring = false
    @Published fileprivate(set) var statusMessage: String?
    @Published fileprivate(set) var errorMessage: String?

    private var product: Product?
    private var productsByIdentifier: [String: Product] = [:]
    private var invalidProductLoadRetryCount = 0
    private var productLoadingTask: Task<Void, Never>?
    private var productRetryTask: Task<Void, Never>?
    private var purchaseTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var transactionUpdatesTask: Task<Void, Never>?
    private var entitlementExpirationTimer: Timer?
    private var appActiveObserver: NSObjectProtocol?

    fileprivate init(configuration: CompanionUnlockConfiguration, storeInteractionEnabled: Bool = true, allowsNewPurchases: Bool = true) {
        self.configuration = configuration
        self.storeInteractionEnabled = storeInteractionEnabled
        self.allowsNewPurchases = allowsNewPurchases
        let suppressesBetaUnlockForLayerPurchaseTesting =
            configuration.permitsLayerPurchaseTestingReset
            && HWCAdditionalLayerEntitlementPolicy.activateLayerPurchaseTestingResetIfRequested()
        let usesBetaUnlockBypass = storeInteractionEnabled && allowsNewPurchases &&
            Self.shouldAutoUnlockInBeta &&
            !Self.isLocalPurchaseResetForCurrentBuild &&
            !suppressesBetaUnlockForLayerPurchaseTesting
        self.usesBetaUnlockBypass = usesBetaUnlockBypass
        isUnlocked = usesBetaUnlockBypass || (
            storeInteractionEnabled &&
            configuration.marksUnlockedOnPurchase &&
            !configuration.requiresActiveEntitlement &&
            UserDefaults.standard.bool(forKey: configuration.purchasedKey)
        )
        super.init()
        guard storeInteractionEnabled else { return }
        startTransactionMonitoring()
        refreshProduct()
    }

    deinit {
        productLoadingTask?.cancel()
        productRetryTask?.cancel()
        purchaseTask?.cancel()
        restoreTask?.cancel()
        transactionUpdatesTask?.cancel()
        entitlementExpirationTimer?.invalidate()
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }

    var purchaseButtonTitle: String {
        if usesBetaUnlockBypass {
            return "Included in This Build"
        }
        if isPurchasing {
            return "Purchasing..."
        }
        return priceLabel.isEmpty ? "Unlock" : "Unlock (\(priceLabel))"
    }

    func purchaseButtonTitle(for productIdentifier: String, displayTitle: String) -> String {
        if HWCStorePurchaseSelection.bypassesPurchase(
            usesBetaUnlock: usesBetaUnlockBypass,
            requestedID: productIdentifier,
            productIDs: configuration.productIDs,
            unlockProductIDs: configuration.unlockProductIDs
        ) {
            return displayTitle
        }
        if isPurchasing {
            return "Purchasing..."
        }
        let productPrice = priceLabel(for: productIdentifier)
        return productPrice.isEmpty ? displayTitle : "\(displayTitle) (\(productPrice))"
    }

    var isBusy: Bool {
        isLoadingProduct || isPurchasing || isRestoring
    }

    func refreshProduct() {
        guard storeInteractionEnabled && allowsNewPurchases else { return }
        guard HWCStorePurchaseSelection.loadsProducts(
            usesBetaUnlock: usesBetaUnlockBypass,
            productIDs: configuration.productIDs,
            unlockProductIDs: configuration.unlockProductIDs
        ) else { return }
        productLoadingTask?.cancel()
        productRetryTask?.cancel()
        invalidProductLoadRetryCount = 0
        startProductRequest()
    }

    private func startProductRequest() {
        productLoadingTask?.cancel()
        isLoadingProduct = true
        errorMessage = nil
        let productIDs = configuration.productIDs
        productLoadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let products = try await Product.products(for: productIDs)
                guard !Task.isCancelled else { return }
                self.receiveProducts(products)
            } catch {
                guard !Task.isCancelled else { return }
                self.productLoadingTask = nil
                self.isLoadingProduct = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func priceLabel(for productIdentifier: String) -> String {
        if let product = productsByIdentifier[productIdentifier] {
            return product.displayPrice
        }
        if let selectedProduct = product, selectedProduct.id == productIdentifier {
            return selectedProduct.displayPrice
        }
        return ""
    }

    func purchaseUnlock() {
        purchaseUnlock(productIdentifier: nil)
    }

    func purchaseUnlock(productIdentifier: String?) {
        guard storeInteractionEnabled && allowsNewPurchases else { return }
        guard !HWCStorePurchaseSelection.bypassesPurchase(
            usesBetaUnlock: usesBetaUnlockBypass,
            requestedID: productIdentifier,
            productIDs: configuration.productIDs,
            unlockProductIDs: configuration.unlockProductIDs
        ) else {
            activateBetaUnlock(statusMessage: configuration.betaUnlockedMessage)
            return
        }
        guard HWCStorePurchaseSelection.allowsPurchase(
            isUnlocked: isUnlocked,
            requestedProductID: productIdentifier
        ) else { return }
        guard AppStore.canMakePayments else {
            errorMessage = "This Apple ID cannot make purchases on this device right now."
            return
        }

        let selectedProduct = HWCStorePurchaseSelection.product(
            requestedID: productIdentifier,
            defaultProduct: product,
            availableProducts: productsByIdentifier
        )
        guard let selectedProduct else {
            refreshProduct()
            errorMessage = configuration.pendingProductMessage
            return
        }

        isPurchasing = true
        errorMessage = nil
        statusMessage = nil
        purchaseTask?.cancel()
        purchaseTask = Task { [weak self] in
            guard let self else { return }
            do {
                switch try await selectedProduct.purchase() {
                case .success(let result):
                    guard case .verified(let transaction) = result else {
                        self.isPurchasing = false
                        self.errorMessage = "The App Store could not verify this purchase."
                        return
                    }
                    await self.handleVerifiedTransaction(
                        transaction,
                        statusMessage: self.statusMessage(for: transaction.productID),
                        showCompletionPrompt: true
                    )
                case .pending:
                    self.isPurchasing = false
                    self.statusMessage = "This purchase is pending approval."
                case .userCancelled:
                    self.isPurchasing = false
                @unknown default:
                    self.isPurchasing = false
                    self.errorMessage = "The purchase returned an unknown App Store result."
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isPurchasing = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func restorePurchases() {
        guard storeInteractionEnabled else { return }
        guard !usesBetaUnlockBypass else {
            activateBetaUnlock(statusMessage: configuration.betaUnlockedMessage)
            return
        }
        isRestoring = true
        errorMessage = nil
        statusMessage = nil
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await AppStore.sync()
                await self.restoreCurrentEntitlements()
            } catch {
                guard !Task.isCancelled else { return }
                self.isRestoring = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func resetLocalPurchaseForCurrentBuild(statusMessage: String) {
        UserDefaults.standard.set(Self.appBuild, forKey: Self.localPurchaseResetBuildKey)
        UserDefaults.standard.removeObject(forKey: configuration.purchasedKey)
        usesBetaUnlockBypass = false
        isUnlocked = false
        isPurchasing = false
        isRestoring = false
        self.statusMessage = statusMessage
        errorMessage = nil
    }

    private func receiveProducts(_ products: [Product]) {
        let productsByIdentifier = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let resolvedProduct = configuration.productIDs.compactMap { identifier in
            products.first { $0.id == identifier }
        }.first ?? products.first
        productLoadingTask = nil
        self.productsByIdentifier = productsByIdentifier
        product = resolvedProduct
        isLoadingProduct = false

        #if DEBUG
        if ProcessInfo.processInfo.environment["HWC_TIP_PURCHASE_DIAGNOSTICS"] == "1" {
            for loadedProduct in products where HWCStorePurchaseSelection.isRepeatableProduct(
                loadedProduct.id, productIDs: configuration.productIDs, unlockProductIDs: configuration.unlockProductIDs
            ) {
                let bypassed = HWCStorePurchaseSelection.bypassesPurchase(
                    usesBetaUnlock: usesBetaUnlockBypass, requestedID: loadedProduct.id,
                    productIDs: configuration.productIDs, unlockProductIDs: configuration.unlockProductIDs
                )
                print("HWC repeatable purchase: product=\(loadedProduct.id), price=\(loadedProduct.displayPrice), supportUnlocked=\(isUnlocked), interceptedByUnlock=\(bypassed)")
            }
        }
        #endif

        if let resolvedProduct {
            invalidProductLoadRetryCount = 0
            priceLabel = resolvedProduct.displayPrice
            errorMessage = nil
            #if DEBUG
            if configuration.permitsLayerPurchaseTestingReset,
               HWCAdditionalLayerEntitlementPolicy.isLayerPurchaseTestingResetActive {
                print("HWC Additional Layer purchase testing reset loaded price: \(resolvedProduct.displayPrice)")
            }
            #endif
        } else {
            errorMessage = loadingErrorMessage()
            retryInvalidProductLoadIfNeeded()
        }
    }

    private func loadingErrorMessage() -> String {
        if invalidProductLoadRetryCount >= maxInvalidProductLoadRetries {
            return "App Store still has not returned this product. Wait for App Store Connect processing, then tap Retry."
        }
        return "\(configuration.loadingErrorMessage) Retrying App Store..."
    }

    private func retryInvalidProductLoadIfNeeded() {
        guard invalidProductLoadRetryCount < maxInvalidProductLoadRetries else { return }
        invalidProductLoadRetryCount += 1
        productRetryTask?.cancel()
        productRetryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.invalidProductRetryDelay))
            guard !Task.isCancelled else { return }
            guard self.product == nil else { return }
            guard self.productLoadingTask == nil else { return }
            self.startProductRequest()
        }
    }

    private func handlesTransaction(_ transaction: StoreKit.Transaction) -> Bool {
        configuration.productIDs.contains(transaction.productID)
    }

    private func statusMessage(for productID: String) -> String {
        if configuration.marksUnlockedOnPurchase &&
            !configuration.unlockProductIDs.contains(productID) {
            return "Thanks for supporting HWC."
        }
        return configuration.purchasedStatusMessage
    }

    private func handleVerifiedTransaction(
        _ transaction: StoreKit.Transaction,
        statusMessage: String,
        showCompletionPrompt: Bool
    ) async {
        guard handlesTransaction(transaction) else { return }
        if showCompletionPrompt {
            didCompletePurchase(
                productID: transaction.productID,
                transactionID: String(transaction.id)
            )
        }
        let transactionUnlocksFeatures = configuration.unlockProductIDs.contains(transaction.productID)
        if configuration.marksUnlockedOnPurchase &&
            transactionUnlocksFeatures &&
            !configuration.requiresActiveEntitlement {
            isUnlocked = true
            UserDefaults.standard.set(true, forKey: configuration.purchasedKey)
            UserDefaults.standard.removeObject(forKey: Self.localPurchaseResetBuildKey)
        }
        isPurchasing = false
        isRestoring = false
        self.statusMessage = statusMessage
        errorMessage = nil
        await transaction.finish()
        if configuration.requiresActiveEntitlement && transactionUnlocksFeatures {
            await refreshSubscriptionEntitlement()
        }
    }

    func didCompletePurchase(productID: String, transactionID: String) {}

    private func activateBetaUnlock(statusMessage: String) {
        isUnlocked = true
        isLoadingProduct = false
        isPurchasing = false
        isRestoring = false
        self.statusMessage = statusMessage
        errorMessage = nil
    }

    fileprivate func updateStateOnMain(_ updates: () -> Void) {
        updates()
    }

    fileprivate func unlockStateDidChange() {}

    private func startTransactionMonitoring() {
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshOwnedEntitlements()
            }
        }
        transactionUpdatesTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshOwnedEntitlements()
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                await self.processTransactionUpdate(result)
            }
        }
    }

    private func processTransactionUpdate(
        _ result: VerificationResult<StoreKit.Transaction>
    ) async {
        guard case .verified(let transaction) = result else { return }
        guard handlesTransaction(transaction) else { return }
        await handleVerifiedTransaction(
            transaction,
            statusMessage: statusMessage(for: transaction.productID),
            showCompletionPrompt: false
        )
    }

    private func scheduleSubscriptionEntitlementRefresh() {
        Task { [weak self] in
            await self?.refreshOwnedEntitlements()
        }
    }

    private func restoreCurrentEntitlements() async {
        let restored = await applyCurrentEntitlements()
        if configuration.requiresActiveEntitlement {
            await refreshSubscriptionEntitlement()
        }
        isRestoring = false
        statusMessage = (restored || isUnlocked)
            ? configuration.restoredStatusMessage
            : configuration.restoreMissMessage
    }

    private func refreshOwnedEntitlements() async {
        _ = await applyCurrentEntitlements()
        if configuration.requiresActiveEntitlement {
            await refreshSubscriptionEntitlement()
        }
    }

    private func applyCurrentEntitlements() async -> Bool {
        var restored = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard handlesTransaction(transaction) else { continue }
            restored = true
            let unlocksFeatures = configuration.unlockProductIDs.contains(transaction.productID)
            if configuration.marksUnlockedOnPurchase &&
                unlocksFeatures &&
                !configuration.requiresActiveEntitlement {
                isUnlocked = true
                UserDefaults.standard.set(true, forKey: configuration.purchasedKey)
                UserDefaults.standard.removeObject(forKey: Self.localPurchaseResetBuildKey)
            }
        }
        return restored
    }

    private func refreshSubscriptionEntitlement() async {
        guard !usesBetaUnlockBypass else { return }
        var records: [HWCSubscriptionEntitlementRecord] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            records.append(
                HWCSubscriptionEntitlementRecord(
                    productID: transaction.productID,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate
                )
            )
        }

        let now = Date()
        let active = HWCSubscriptionEntitlementPolicy.isActive(
            records: records,
            productIDs: Set(configuration.unlockProductIDs),
            now: now
        )
        let nextExpiration = records
            .filter { configuration.unlockProductIDs.contains($0.productID) && $0.revocationDate == nil }
            .compactMap(\.expirationDate)
            .filter { $0 > now }
            .min()
        setSubscriptionEntitlementActive(active)
        scheduleSubscriptionExpirationRefresh(at: nextExpiration)
    }

    private func setSubscriptionEntitlementActive(_ active: Bool) {
        isUnlocked = active
        UserDefaults.standard.set(active, forKey: configuration.purchasedKey)
        if !active {
            statusMessage = nil
        }
    }

    private func scheduleSubscriptionExpirationRefresh(at expirationDate: Date?) {
        entitlementExpirationTimer?.invalidate()
        guard let expirationDate else {
            entitlementExpirationTimer = nil
            return
        }
        entitlementExpirationTimer = Timer.scheduledTimer(
            withTimeInterval: max(1, expirationDate.timeIntervalSinceNow + 1),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleSubscriptionEntitlementRefresh()
            }
        }
    }

    private static var shouldAutoUnlockInBeta: Bool {
        HWCBuildFlavor.autoUnlockPaidFeatures
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private static var isLocalPurchaseResetForCurrentBuild: Bool {
        UserDefaults.standard.string(forKey: localPurchaseResetBuildKey) == appBuild
    }
}

final class ABCUnlockStore: CompanionUnlockStore {
    init() {
        super.init(configuration: .abc)
    }
}

final class HardwarePremiumUnlockStore: CompanionUnlockStore {
    init() {
        super.init(configuration: .hardwarePremium, allowsNewPurchases: HWCBuildFlavor.hardwareKeypressPaidStoreEnabled)
    }
}

final class AdditionalLayersUnlockStore: CompanionUnlockStore {
    private static let layerCreditKey = "companion.purchase.additionalLayersCreditCount"
    private static let iCloudLayerCreditKey = "companion.purchase.additionalLayersCreditCount"
    private static let layerCreditLedgerKey = "companion.purchase.additionalLayersCreditLedger.v1"
    private static let layerPurchaseTestingBaselineKey = "companion.purchase.additionalLayersTestingResetBaseline.v1"

    private struct LayerCreditRecord: Codable {
        var credits: Int
        var revoked: Bool
    }

    @Published private(set) var purchasedLayerCount: Int {
        didSet {
            HWCAdditionalLayerEntitlementPolicy.publishPurchasedCredits(
                purchasedLayerCount
            )
        }
    }
    private var cloudObserver: NSObjectProtocol?

    var isLayerPurchaseTestingResetActive: Bool {
        HWCAdditionalLayerEntitlementPolicy.isLayerPurchaseTestingResetActive
    }

    init() {
        _ = HWCAdditionalLayerEntitlementPolicy.activateLayerPurchaseTestingResetIfRequested()
        let ledger = Self.restoredLayerCreditLedger()
        purchasedLayerCount = Self.effectiveLayerCreditCount(in: ledger)
        super.init(configuration: .additionalLayers)
        HWCAdditionalLayerEntitlementPolicy.publishPurchasedCredits(
            purchasedLayerCount
        )
        registerForCloudChanges()
        restoreLayerCredits()
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
    }

    func canUseLayerCount(_ layerCount: Int) -> Bool {
        HWCAdditionalLayerEntitlementPolicy.canCreateLayer(
            existingLayerCount: layerCount,
            purchasedCredits: purchasedLayerCount,
            hasUnlimitedAccess: isUnlocked
        )
    }

    override func restorePurchases() {
        restoreLayerCredits()
    }

    func restoreLayerCredits() {
        let restoredCount = Self.effectiveLayerCreditCount(
            in: Self.restoredLayerCreditLedger()
        )
        updateStateOnMain {
            self.purchasedLayerCount = restoredCount
            self.isRestoring = false
            self.statusMessage = restoredCount > 0
                ? "Restored \(restoredCount) Additional Layer purchase\(restoredCount == 1 ? "" : "s")."
                : "No Additional Layer purchases found in iCloud yet."
        }
    }

    @discardableResult
    static func grantLayerCredits(_ count: Int, transactionID: String) -> Int {
        guard count > 0, !transactionID.isEmpty else {
            return effectiveLayerCreditCount(in: restoredLayerCreditLedger())
        }
        var ledger = restoredLayerCreditLedger()
        let current = ledger[transactionID]
        ledger[transactionID] = LayerCreditRecord(
            credits: max(current?.credits ?? 0, count),
            revoked: current?.revoked ?? false
        )
        persistLayerCreditLedger(ledger)
        return effectiveLayerCreditCount(in: ledger)
    }

    @discardableResult
    static func revokeLayerCredits(transactionID: String) -> Int {
        guard !transactionID.isEmpty else {
            return effectiveLayerCreditCount(in: restoredLayerCreditLedger())
        }
        var ledger = restoredLayerCreditLedger()
        ledger[transactionID] = LayerCreditRecord(
            credits: max(ledger[transactionID]?.credits ?? 0, 1),
            revoked: true
        )
        persistLayerCreditLedger(ledger)
        return effectiveLayerCreditCount(in: ledger)
    }

    override func didCompletePurchase(productID: String, transactionID: String) {
        let nextCount = Self.grantLayerCredits(
            1,
            transactionID: transactionID
        )
        updateStateOnMain {
            self.purchasedLayerCount = nextCount
        }
    }

    private static func restoredLayerCreditLedger() -> [String: LayerCreditRecord] {
        let localCount = UserDefaults.standard.integer(forKey: layerCreditKey)
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.synchronize()
        let cloudCount = Int(cloudStore.longLong(forKey: iCloudLayerCreditKey))
        let localLedger = decodeCreditLedger(UserDefaults.standard.data(forKey: layerCreditLedgerKey))
        let cloudLedger = decodeCreditLedger(cloudStore.data(forKey: layerCreditLedgerKey))
        var ledger = mergeCreditLedgers(localLedger, cloudLedger)
        if ledger.isEmpty {
            let legacyCount = max(localCount, cloudCount)
            if legacyCount > 0 {
                ledger["legacy.aggregate"] = LayerCreditRecord(credits: legacyCount, revoked: false)
            }
        }
        persistLayerCreditLedger(ledger)
        return ledger
    }

    private static func decodeCreditLedger(_ data: Data?) -> [String: LayerCreditRecord] {
        guard let data, data.count <= 256 * 1_024 else { return [:] }
        return (try? JSONDecoder().decode([String: LayerCreditRecord].self, from: data)) ?? [:]
    }

    private static func mergeCreditLedgers(
        _ lhs: [String: LayerCreditRecord],
        _ rhs: [String: LayerCreditRecord]
    ) -> [String: LayerCreditRecord] {
        var merged = lhs
        for (transactionID, incoming) in rhs {
            guard let current = merged[transactionID] else {
                merged[transactionID] = incoming
                continue
            }
            merged[transactionID] = LayerCreditRecord(
                credits: max(current.credits, incoming.credits),
                revoked: current.revoked || incoming.revoked
            )
        }
        return merged
    }

    private static func activeCreditCount(in ledger: [String: LayerCreditRecord]) -> Int {
        ledger.values.reduce(into: 0) { total, record in
            guard !record.revoked else { return }
            total += max(0, record.credits)
        }
    }

    private static func effectiveLayerCreditCount(in ledger: [String: LayerCreditRecord]) -> Int {
        guard HWCAdditionalLayerEntitlementPolicy.isLayerPurchaseTestingResetActive else {
            return activeCreditCount(in: ledger)
        }

        let activeCredits = Dictionary(uniqueKeysWithValues: ledger.compactMap { transactionID, record -> (String, Int)? in
            guard !record.revoked, record.credits > 0 else { return nil }
            return (transactionID, record.credits)
        })
        let existingBaseline = testingResetBaseline()
        let baseline = HWCAdditionalLayerEntitlementPolicy.testingResetBaseline(
            currentCreditsByTransaction: activeCredits,
            existingBaseline: existingBaseline
        )
        if existingBaseline == nil {
            persistTestingResetBaseline(baseline)
            emitLayerPurchaseTestingProof(effectiveCredits: 0, baselineCount: activeCredits.values.reduce(0, +))
            return 0
        }
        let effectiveCredits = HWCAdditionalLayerEntitlementPolicy.effectivePurchasedCredits(
            creditsByTransaction: activeCredits,
            baseline: baseline,
            isTestingResetActive: true
        )
        emitLayerPurchaseTestingProof(
            effectiveCredits: effectiveCredits,
            baselineCount: baseline.values.reduce(0, +)
        )
        return effectiveCredits
    }

    private static func testingResetBaseline() -> [String: Int]? {
        guard let data = UserDefaults.standard.data(forKey: layerPurchaseTestingBaselineKey) else {
            return nil
        }
        return try? JSONDecoder().decode([String: Int].self, from: data)
    }

    private static func persistTestingResetBaseline(_ credits: [String: Int]) {
        guard let data = try? JSONEncoder().encode(credits) else { return }
        UserDefaults.standard.set(data, forKey: layerPurchaseTestingBaselineKey)
    }

    private static func emitLayerPurchaseTestingProof(effectiveCredits: Int, baselineCount: Int) {
        #if DEBUG
        guard HWCAdditionalLayerEntitlementPolicy.isLayerPurchaseTestingResetActive else { return }
        print("HWC Additional Layer purchase testing reset active: effectiveCredits=\(effectiveCredits), baselineCredits=\(baselineCount)")
        #endif
    }

    private static func persistLayerCreditLedger(_ ledger: [String: LayerCreditRecord]) {
        guard let data = try? JSONEncoder().encode(ledger), data.count <= 256 * 1_024 else { return }
        let count = activeCreditCount(in: ledger)
        UserDefaults.standard.set(data, forKey: layerCreditLedgerKey)
        UserDefaults.standard.set(count, forKey: layerCreditKey)
        HWCAdditionalLayerEntitlementPolicy.publishPurchasedCredits(
            effectiveLayerCreditCount(in: ledger)
        )
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(data, forKey: layerCreditLedgerKey)
        cloudStore.set(count, forKey: iCloudLayerCreditKey)
        cloudStore.synchronize()
    }

    private func registerForCloudChanges() {
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreLayerCredits()
            }
        }
    }
}

final class SupportDeveloperUnlockStore: CompanionUnlockStore {
    private static let coffeeEasterEggSequence = "Left, Right, Left, Right, Slash, Backslash, Space"
    @Published private(set) var thankYouPrompt: SupportDeveloperThankYouPrompt?
    @Published private(set) var thankYouPulse = 0

    init() {
        super.init(configuration: .supportDeveloper)
        HWCAdditionalLayerEntitlementPolicy.publishUnlimitedAccess(isUnlocked)
    }

    override fileprivate func unlockStateDidChange() {
        HWCAdditionalLayerEntitlementPolicy.publishUnlimitedAccess(isUnlocked)
    }

    override func didCompletePurchase(productID: String, transactionID: String) {
        switch productID {
        case "dev.moni11811.hwkbcompanion.buycoffee_v3":
            showThankYouPrompt(
                SupportDeveloperThankYouPrompt(
                    kind: .coffee,
                    title: "Coffee, received",
                    message: "Pure tip — no features attached, and that genuinely means a lot. If you're curious, there's a hidden mini-game. On the HWC keyboard, press \(Self.coffeeEasterEggSequence).",
                    steps: ["Left", "Right", "Left", "Right", "Slash", "Backslash", "Space"]
                )
            )
        case "dev.moni11811.hwkbcompanion.buyburger_v3":
            _ = AdditionalLayersUnlockStore.grantLayerCredits(
                2,
                transactionID: transactionID
            )
            showThankYouPrompt(
                SupportDeveloperThankYouPrompt(
                    kind: .burger,
                    title: "Burger, secured",
                    message: "Thanks for the boost — it helps more than you'd think. I dropped 2 Additional Layer credits into your account, so go build two more custom layers on the house.",
                    steps: ["+2 Layers", "On the house"]
                )
            )
        default:
            showThankYouPrompt(
                SupportDeveloperThankYouPrompt(
                    kind: .yearly,
                    title: "You're in. Thank you.",
                    message: "Your yearly support keeps HWC independent and moving. ABC Unlock and Unlimited Layers are unlocked.",
                    steps: ["ABC Unlock", "Unlimited Layers"]
                )
            )
        }
    }

    func dismissThankYouPrompt() {
        thankYouPrompt = nil
    }

    private func showThankYouPrompt(_ prompt: SupportDeveloperThankYouPrompt) {
        updateStateOnMain {
            self.thankYouPrompt = prompt
            self.thankYouPulse += 1
        }
    }

}

struct KeyboardSavedPreset: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var keymap: KeyboardKeymap
    var transferLayer: HWKKeymapTransferDocument?
    var builtInTemplateSource: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        keymap: KeyboardKeymap,
        transferLayer: HWKKeymapTransferDocument? = nil,
        builtInTemplateSource: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = Self.normalizedTitle(title)
        self.keymap = keymap
        self.transferLayer = transferLayer
        self.builtInTemplateSource = builtInTemplateSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func normalizedTitle(_ title: String) -> String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((value.isEmpty ? "Preset" : value).prefix(40))
    }
}

enum KeyboardSavedPresetStore {
    static let storageKey = "keyboard.savedKeymapPresets"
    static let maximumPresetCount = 20
    static let maximumDataSize = 768 * 1_024

    static func load(
        defaults: UserDefaults = KeyboardSharedPreferences.defaults,
        cloud: NSUbiquitousKeyValueStore = .default
    ) -> [KeyboardSavedPreset] {
        let cloudData = defaults.bool(forKey: KeyboardSharedPreferences.Key.settingsiCloudSyncEnabled)
            ? cloud.data(forKey: storageKey)
            : nil
        let localData = defaults.data(forKey: storageKey)
        let data = preferredPresetData(localData: localData, cloudData: cloudData)
        guard let data, data.count <= maximumDataSize,
              let decoded = try? JSONDecoder().decode([KeyboardSavedPreset].self, from: data) else {
            return []
        }
        return normalized(decoded)
    }

    static func preferredPresetData(localData: Data?, cloudData: Data?) -> Data? {
        func decoded(_ data: Data?) -> [KeyboardSavedPreset]? {
            guard let data, data.count <= maximumDataSize else { return nil }
            return try? JSONDecoder().decode([KeyboardSavedPreset].self, from: data)
        }

        let local = decoded(localData)
        let cloud = decoded(cloudData)
        switch (local, cloud) {
        case (.none, .none):
            return nil
        case (.some, .none):
            return localData
        case (.none, .some):
            return cloudData
        case (.some(let localPresets), .some(let cloudPresets)):
            let localUpdatedAt = localPresets.map(\.updatedAt).max() ?? .distantPast
            let cloudUpdatedAt = cloudPresets.map(\.updatedAt).max() ?? .distantPast
            return cloudUpdatedAt > localUpdatedAt ? cloudData : localData
        }
    }

    @discardableResult
    static func save(
        _ presets: [KeyboardSavedPreset],
        defaults: UserDefaults = KeyboardSharedPreferences.defaults,
        cloud: NSUbiquitousKeyValueStore = .default
    ) -> Bool {
        _ = cloud // Legacy injection retained for source compatibility; CloudKit owns new snapshots.
        let normalizedPresets = normalized(presets)
        guard let data = try? JSONEncoder().encode(normalizedPresets), data.count <= maximumDataSize else { return false }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(
            name: .hwcCloudSnapshotSourceDidChange,
            object: nil
        )
        return true
    }

    static func normalized(_ presets: [KeyboardSavedPreset]) -> [KeyboardSavedPreset] {
        var seen = Set<UUID>()
        return presets.compactMap { preset in
            guard seen.insert(preset.id).inserted else { return nil }
            return KeyboardSavedPreset(
                id: preset.id,
                title: preset.title,
                keymap: preset.keymap,
                transferLayer: preset.transferLayer,
                builtInTemplateSource: preset.builtInTemplateSource,
                createdAt: preset.createdAt,
                updatedAt: preset.updatedAt
            )
        }
        .prefix(maximumPresetCount)
        .map { $0 }
    }
}

/// Owns the Darwin callback context for the lifetime of the companion process.
/// Store subscriptions stay weak and are delivered only on main.
private final class CompanionSharedSettingsDarwinRelay: @unchecked Sendable {
    static let shared = CompanionSharedSettingsDarwinRelay()
    static let localNotification = Notification.Name(
        "dev.moni11811.hwc.companion-shared-settings-relay"
    )

    private init() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let relay = Unmanaged<CompanionSharedSettingsDarwinRelay>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                relay.deliver()
            },
            KeyboardSharedPreferences.settingsDidChangeNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func deliver() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.localNotification,
                object: nil
            )
        }
    }
}

private final class CompanionSharedSettingsRefreshToken: @unchecked Sendable {
    weak var store: CompanionSettingsStore?

    init(store: CompanionSettingsStore) {
        self.store = store
    }
}

final class CompanionSettingsStore: ObservableObject {
    private enum LocalKey {
        static let migrationNoticeDismissedAt = "companion.migrationNoticeDismissedAt"
        static let setupSplashDismissedAt = "companion.setupSplashDismissedAt"
        static let setupGateStartedAt = "companion.setupGateStartedAt"
        static let setupSelectedMode = "companion.setupSelectedMode"
        static let setupKeyboardActivationText = "companion.setupKeyboardActivationText"
        static let setupGateCompletedAt = "companion.setupGateCompletedAt"
    }

    private var isApplyingSnapshot = false
    private let saveSavedPresets: ([KeyboardSavedPreset]) -> Bool
    private let canCreateCustomKeymapLayer: (Int) -> Bool
    private var sharedSettingsObserverToken: NSObjectProtocol?
    private lazy var sharedSettingsRefreshToken =
        CompanionSharedSettingsRefreshToken(store: self)
    private var preservedRuntimeSettings = KeyboardSettingsSnapshot.default
    private var runtimeLayoutRoute: KeyboardRuntimeLayoutRoute = .runtimeLocale
    private var keyDimensionOverrides: [String: KeyboardLayoutKeyDimensions] = [:]
    @Published private var keymapRows: [KeyboardLayoutRow] = []
    @Published private(set) var customKeymapLayers: [KeyboardCustomLayer] = []
    @Published private(set) var savedKeymapPresets: [KeyboardSavedPreset]

    @Published var appTheme: CompanionAppTheme { didSet { save() } }
    @Published var accentPalette: KeyboardAccentPalette { didSet { save() } }
    @Published var customKeyStyle: KeyboardCustomKeyStyle { didSet { save() } }
    @Published var vibrationEnabled: Bool { didSet { save() } }
    @Published var feedbackLevel: KeyboardFeedbackLevel { didSet { save() } }
    @Published var autoPairEnabled: Bool { didSet { save() } }
    @Published var startExpanded: Bool { didSet { save() } }
    @Published var defaultSymbolLayer: Bool { didSet { save() } }
    @Published var showQuickInsertRow: Bool { didSet { save() } }
    @Published var hideKeyboardEnabled: Bool { didSet { save() } }
    @Published var highContrastKeys: Bool { didSet { save() } }
    @Published var largeLegends: Bool { didSet { save() } }
    @Published var showControlLabels: Bool { didSet { save() } }
    @Published var capitalizeFirstLetterEnabled: Bool { didSet { save() } }
    @Published var doubleSpacePeriodEnabled: Bool { didSet { save() } }
    @Published var autocorrectEnabled: Bool { didSet { save() } }
    @Published var autocompleteEnabled: Bool { didSet { save() } }
    @Published var clickToFixEnabled: Bool { didSet { save() } }
    @Published var autocorrectRankingMethod: KeyboardAutocorrectRankingMethod { didSet { save() } }
    @Published var autocorrectLogicRecipe: KeyboardAutocorrectLogicRecipe { didSet { save() } }
    @Published var autocorrectLogicBlocks: [KeyboardAutocorrectLogicBlock] { didSet { save() } }
    @Published var autocorrectLogicLanes: [KeyboardAutocorrectLogicLane] { didSet { save() } }
    @Published var customTextRules: [HWKCustomTextRule] { didSet { save() } }
    @Published var edgeSwipeConfiguration: KeyboardEdgeSwipeConfiguration { didSet { save() } }
    @Published var semiFoldEnabled: Bool { didSet { save() } }
    @Published var suggestionSwipeUpAction: KeyboardSuggestionSwipeUpAction { didSet { save() } }
    @Published var suggestionSwipeDownAction: KeyboardSuggestionSwipeDownAction { didSet { save() } }
    @Published var suggestionSwipeLeftDeleteEnabled: Bool { didSet { save() } }
    @Published var suggestionSwipeRightSpaceEnabled: Bool { didSet { save() } }
    @Published var suggestionHoldForRolodexEnabled: Bool { didSet { save() } }
    @Published var hardwareAutocorrectSelectorEnabled: Bool { didSet { save() } }
    @Published var hardwareAutocorrectSelectorInitiationKey: KeyboardHardwareAutocorrectSelectorInitiationKey { didSet { save() } }
    @Published var hardwareAutocorrectSelectorSelectionKey: KeyboardHardwareAutocorrectSelectorSelectionKey { didSet { save() } }
    @Published var physicalReturnBehavior: KeyboardPhysicalReturnBehavior { didSet { save() } }
    @Published var clipboardDisabled: Bool { didSet { save() } }
    @Published var saveClipboardSettingsWithLiveKeyboard: Bool { didSet { save() } }
    @Published var showQuickInsertHandle: Bool { didSet { save() } }
    #if HWC_HARDWARE_CAPTURE || HWC_INTERNAL_BUILD
    @Published var signalRelayEnabled: Bool { didSet { save() } }
    @Published var signalRelayEmitKeyUp: Bool { didSet { save() } }
    @Published var signalRelayPriorityMode: Bool { didSet { save() } }
    @Published var signalRelaySessionPersist: Bool { didSet { save() } }
    @Published var signalRelayHoldTriggerMs: Int { didSet { save() } }
    @Published private(set) var hardwarePremiumAccessUnlocked: Bool { didSet { save() } }
    #endif
    @Published var capsHoldToLockEnabled: Bool { didSet { save() } }
    @Published var capsHoldDurationMs: Int { didSet { save() } }
    @Published var menuHoldToLatchEnabled: Bool { didSet { save() } }
    @Published var menuHoldDurationMs: Int { didSet { save() } }
    @Published var keyHoldDurationMs: Int { didSet { save() } }
    @Published var rolodexSelectHoldDurationMs: Int { didSet { save() } }
    @Published var menuTapLockWindowMs: Int { didSet { save() } }
    @Published var deleteHoldEnabled: Bool { didSet { save() } }
    @Published var deleteHoldWordsBeforeSentence: Int { didSet { save() } }
    @Published var layoutPreset: KeyboardLayoutPreset { didSet { save() } }
    @Published var layoutLocale: KeyboardLayoutLocale { didSet { save() } }
    @Published var toolbarHeight: Int { didSet { save() } }
    @Published var expandedKeyHeight: Int { didSet { save() } }
    @Published var suggestionVisibleWordCount: Int { didSet { save() } }
    @Published var suggestionRowHeight: Int { didSet { save() } }
    @Published var toolbarKeyCount: Int { didSet { resizeRowsForCountChange() } }
    @Published var symbolTopRowKeyCount: Int { didSet { resizeRowsForCountChange() } }
    @Published var symbolMiddleRowKeyCount: Int { didSet { resizeRowsForCountChange() } }
    @Published var symbolBottomRowKeyCount: Int { didSet { resizeRowsForCountChange() } }
    @Published var letterTopRowKeyCount: Int { didSet { resizeRowsForCountChange() } }
    @Published var letterMiddleRowKeyCount: Int { didSet { resizeRowsForCountChange() } }
    @Published var letterBottomRowKeyCount: Int { didSet { resizeRowsForCountChange() } }
    @Published var quickInsertRow: [String] { didSet { saveKeymap() } }
    @Published var holdQuickInsertRow: [String] { didSet { saveKeymap() } }
    @Published var toolbarRow: [String] { didSet { saveKeymap() } }
    @Published var holdToolbarRow: [String] { didSet { saveKeymap() } }
    @Published var symbolTopRow: [String] { didSet { saveKeymap() } }
    @Published var holdSymbolTopRow: [String] { didSet { saveKeymap() } }
    @Published var symbolMiddleRow: [String] { didSet { saveKeymap() } }
    @Published var holdSymbolMiddleRow: [String] { didSet { saveKeymap() } }
    @Published var symbolBottomRow: [String] { didSet { saveKeymap() } }
    @Published var holdSymbolBottomRow: [String] { didSet { saveKeymap() } }
    @Published var symbolUtilityRow: [String] { didSet { saveKeymap() } }
    @Published var trailingUtilityRow: [String] { didSet { saveKeymap() } }
    @Published var expandedTrailingUtilityRow: [String] { didSet { saveKeymap() } }
    @Published var expandedLetterTrailingUtilityRow: [String] { didSet { saveKeymap() } }
    @Published var letterUtilityRow: [String] { didSet { saveKeymap() } }
    @Published var letterBottomLeadingRow: [String] { didSet { saveKeymap() } }
    @Published var letterTopRow: [String] { didSet { saveKeymap() } }
    @Published var holdLetterTopRow: [String] { didSet { saveKeymap() } }
    @Published var letterMiddleRow: [String] { didSet { saveKeymap() } }
    @Published var holdLetterMiddleRow: [String] { didSet { saveKeymap() } }
    @Published var letterBottomRow: [String] { didSet { saveKeymap() } }
    @Published var holdLetterBottomRow: [String] { didSet { saveKeymap() } }
    @Published private(set) var keyboardLastSeenAt: Date?
    @Published private(set) var sharedContainerAvailable: Bool
    @Published private(set) var settingsMigratedAt: Date?
    @Published private(set) var migrationNoticeDismissedAt: Date?
    @Published private(set) var setupSplashDismissedAt: Date?
    @Published private(set) var setupGateStartedAt: Date?
    @Published private(set) var setupRequiredRestartBootedAt: Date
    @Published private(set) var setupAssistiveTouchRunning: Bool
    @Published var setupSelectedMode: String { didSet { UserDefaults.standard.set(setupSelectedMode, forKey: LocalKey.setupSelectedMode) } }
    @Published var setupKeyboardActivationText: String { didSet { UserDefaults.standard.set(setupKeyboardActivationText, forKey: LocalKey.setupKeyboardActivationText) } }
    @Published private(set) var setupGateCompletedAt: Date?

    init(
        snapshot providedSnapshot: KeyboardSettingsSnapshot? = nil,
        savedKeymapPresets providedSavedPresets: [KeyboardSavedPreset]? = nil,
        saveSavedPresets: @escaping ([KeyboardSavedPreset]) -> Bool = {
            KeyboardSavedPresetStore.save($0)
        },
        canCreateCustomKeymapLayer: @escaping (Int) -> Bool = { existingLayerCount in
            HWCAdditionalLayerEntitlementPolicy.canCreateLayer(
                existingLayerCount: existingLayerCount,
                purchasedCredits: KeyboardSharedPreferences.defaults.integer(
                    forKey: HWCAdditionalLayerEntitlementPolicy.purchasedCreditCountKey
                ),
                hasUnlimitedAccess: KeyboardSharedPreferences.defaults.bool(
                    forKey: HWCAdditionalLayerEntitlementPolicy.unlimitedAccessKey
                )
            )
        }
    ) {
        self.saveSavedPresets = saveSavedPresets
        self.canCreateCustomKeymapLayer = canCreateCustomKeymapLayer
        savedKeymapPresets = KeyboardSavedPresetStore.normalized(
            providedSavedPresets ?? KeyboardSavedPresetStore.load()
        )
        let settingsSync = HWKSettingsiCloudSync()
        let snapshot: KeyboardSettingsSnapshot
        if let providedSnapshot {
            snapshot = providedSnapshot
        } else {
            settingsSync.restoreToSharedSettingsIfNeeded()
            snapshot = .load()
        }
        preservedRuntimeSettings = snapshot

        appTheme = snapshot.appTheme
        accentPalette = snapshot.accentPalette
        customKeyStyle = snapshot.customKeyStyle
        vibrationEnabled = snapshot.vibrationEnabled
        feedbackLevel = snapshot.feedbackLevel
        autoPairEnabled = snapshot.autoPairEnabled
        startExpanded = snapshot.startExpanded
        defaultSymbolLayer = snapshot.defaultSymbolLayer
        showQuickInsertRow = snapshot.showQuickInsertRow
        hideKeyboardEnabled = snapshot.hideKeyboardEnabled
        highContrastKeys = snapshot.highContrastKeys
        largeLegends = snapshot.largeLegends
        showControlLabels = snapshot.showControlLabels
        capitalizeFirstLetterEnabled = snapshot.capitalizeFirstLetterEnabled
        doubleSpacePeriodEnabled = snapshot.doubleSpacePeriodEnabled
        autocorrectEnabled = snapshot.autocorrectEnabled
        autocompleteEnabled = snapshot.autocompleteEnabled
        clickToFixEnabled = snapshot.clickToFixEnabled
        autocorrectRankingMethod = snapshot.autocorrectRankingMethod
        autocorrectLogicRecipe = snapshot.autocorrectLogicRecipe
        autocorrectLogicBlocks = snapshot.autocorrectLogicBlocks
        autocorrectLogicLanes = snapshot.autocorrectLogicLanes
        customTextRules = snapshot.customTextRules
        edgeSwipeConfiguration = snapshot.edgeSwipeConfiguration.normalized(for: snapshot.keymap)
        semiFoldEnabled = snapshot.semiFoldEnabled
        suggestionSwipeUpAction = snapshot.suggestionSwipeUpAction
        suggestionSwipeDownAction = snapshot.suggestionSwipeDownAction
        suggestionSwipeLeftDeleteEnabled = snapshot.suggestionSwipeLeftDeleteEnabled
        suggestionSwipeRightSpaceEnabled = snapshot.suggestionSwipeRightSpaceEnabled
        suggestionHoldForRolodexEnabled = true
        hardwareAutocorrectSelectorEnabled = snapshot.hardwareAutocorrectSelectorEnabled
        hardwareAutocorrectSelectorInitiationKey = snapshot.hardwareAutocorrectSelectorInitiationKey
        hardwareAutocorrectSelectorSelectionKey = snapshot.hardwareAutocorrectSelectorSelectionKey
        physicalReturnBehavior = snapshot.physicalReturnBehavior
        clipboardDisabled = snapshot.clipboardDisabled
        saveClipboardSettingsWithLiveKeyboard = snapshot.saveClipboardSettingsWithLiveKeyboard
        showQuickInsertHandle = snapshot.showQuickInsertHandle
        #if HWC_HARDWARE_CAPTURE || HWC_INTERNAL_BUILD
        signalRelayEnabled = snapshot.signalRelayEnabled
        signalRelayEmitKeyUp = snapshot.signalRelayEmitKeyUp
        signalRelayPriorityMode = snapshot.signalRelayPriorityMode
        signalRelaySessionPersist = snapshot.signalRelaySessionPersist
        signalRelayHoldTriggerMs = snapshot.signalRelayHoldTriggerMs
        hardwarePremiumAccessUnlocked = snapshot.hardwarePremiumAccessUnlocked
        #endif
        capsHoldToLockEnabled = snapshot.capsHoldToLockEnabled
        capsHoldDurationMs = snapshot.capsHoldDurationMs
        menuHoldToLatchEnabled = snapshot.menuHoldToLatchEnabled
        menuHoldDurationMs = snapshot.menuHoldDurationMs
        keyHoldDurationMs = snapshot.keyHoldDurationMs
        rolodexSelectHoldDurationMs = snapshot.rolodexSelectHoldDurationMs
        menuTapLockWindowMs = snapshot.menuTapLockWindowMs
        deleteHoldEnabled = snapshot.deleteHoldEnabled
        deleteHoldWordsBeforeSentence = snapshot.deleteHoldWordsBeforeSentence
        layoutPreset = snapshot.layoutPreset
        layoutLocale = snapshot.layoutLocale
        runtimeLayoutRoute = snapshot.runtimeLayoutRoute
        toolbarHeight = snapshot.toolbarHeight
        expandedKeyHeight = snapshot.expandedKeyHeight
        suggestionVisibleWordCount = snapshot.suggestionVisibleWordCount
        suggestionRowHeight = snapshot.suggestionRowHeight
        toolbarKeyCount = snapshot.toolbarKeyCount
        symbolTopRowKeyCount = snapshot.symbolTopRowKeyCount
        symbolMiddleRowKeyCount = snapshot.symbolMiddleRowKeyCount
        symbolBottomRowKeyCount = snapshot.symbolBottomRowKeyCount
        letterTopRowKeyCount = snapshot.letterTopRowKeyCount
        letterMiddleRowKeyCount = snapshot.letterMiddleRowKeyCount
        letterBottomRowKeyCount = snapshot.letterBottomRowKeyCount
        quickInsertRow = snapshot.keymap.quickInsertRow
        holdQuickInsertRow = snapshot.keymap.holdQuickInsertRow
        toolbarRow = snapshot.keymap.toolbarRow
        holdToolbarRow = snapshot.keymap.holdToolbarRow
        symbolTopRow = snapshot.keymap.symbolTopRow
        holdSymbolTopRow = snapshot.keymap.holdSymbolTopRow
        symbolMiddleRow = snapshot.keymap.symbolMiddleRow
        holdSymbolMiddleRow = snapshot.keymap.holdSymbolMiddleRow
        symbolBottomRow = snapshot.keymap.symbolBottomRow
        holdSymbolBottomRow = snapshot.keymap.holdSymbolBottomRow
        symbolUtilityRow = snapshot.keymap.symbolUtilityRow
        trailingUtilityRow = snapshot.keymap.trailingUtilityRow
        expandedTrailingUtilityRow = snapshot.keymap.expandedTrailingUtilityRow
        expandedLetterTrailingUtilityRow = snapshot.keymap.expandedLetterTrailingUtilityRow
        letterUtilityRow = snapshot.keymap.letterUtilityRow
        letterBottomLeadingRow = snapshot.keymap.letterBottomLeadingRow
        letterTopRow = snapshot.keymap.letterTopRow
        holdLetterTopRow = snapshot.keymap.holdLetterTopRow
        letterMiddleRow = snapshot.keymap.letterMiddleRow
        holdLetterMiddleRow = snapshot.keymap.holdLetterMiddleRow
        letterBottomRow = snapshot.keymap.letterBottomRow
        holdLetterBottomRow = snapshot.keymap.holdLetterBottomRow
        keyDimensionOverrides = snapshot.keymap.keyDimensionOverrides
        customKeymapLayers = snapshot.keymap.customLayers
        keymapRows = snapshot.keymap.rows
        keyboardLastSeenAt = KeyboardSharedPreferences.lastKeyboardSeenAt()
        sharedContainerAvailable = KeyboardSharedPreferences.isSharedContainerAvailable
        settingsMigratedAt = KeyboardSharedPreferences.lastMigrationAt()
        migrationNoticeDismissedAt = Self.localDate(for: LocalKey.migrationNoticeDismissedAt)
        setupSplashDismissedAt = Self.localDate(for: LocalKey.setupSplashDismissedAt)
        setupGateStartedAt = Self.localDate(for: LocalKey.setupGateStartedAt)
        setupRequiredRestartBootedAt = Self.currentDeviceBootDate()
        setupAssistiveTouchRunning = UIAccessibility.isAssistiveTouchRunning
        setupSelectedMode = UserDefaults.standard.string(forKey: LocalKey.setupSelectedMode) ?? ""
        setupKeyboardActivationText = UserDefaults.standard.string(forKey: LocalKey.setupKeyboardActivationText) ?? ""
        setupGateCompletedAt = Self.localDate(for: LocalKey.setupGateCompletedAt)
        if setupGateStartedAt == nil && setupGateCompletedAt == nil {
            let referenceDate = Date()
            UserDefaults.standard.set(referenceDate.timeIntervalSince1970, forKey: LocalKey.setupGateStartedAt)
            setupGateStartedAt = referenceDate
        }
        if providedSnapshot == nil {
            registerForSharedSettingsChanges()
        }
    }

    deinit {
        unregisterForSharedSettingsChanges()
    }

    var snapshot: KeyboardSettingsSnapshot {
        var snapshot = KeyboardSettingsSnapshot(
            appTheme: appTheme,
            accentPalette: accentPalette,
            customKeyStyle: customKeyStyle,
            vibrationEnabled: vibrationEnabled,
            feedbackLevel: feedbackLevel,
            autoPairEnabled: autoPairEnabled,
            startExpanded: startExpanded,
            defaultSymbolLayer: defaultSymbolLayer,
            showQuickInsertRow: showQuickInsertRow,
            hideKeyboardEnabled: hideKeyboardEnabled,
            highContrastKeys: highContrastKeys,
            largeLegends: largeLegends,
            showControlLabels: showControlLabels,
            capitalizeFirstLetterEnabled: capitalizeFirstLetterEnabled,
            doubleSpacePeriodEnabled: doubleSpacePeriodEnabled,
            autocorrectEnabled: autocorrectEnabled,
            autocompleteEnabled: autocompleteEnabled,
            clickToFixEnabled: clickToFixEnabled,
            autocorrectRankingMethod: autocorrectRankingMethod,
            autocorrectLogicRecipe: autocorrectLogicRecipe,
            autocorrectLogicBlocks: autocorrectLogicBlocks,
            autocorrectLogicLanes: autocorrectLogicLanes,
            customTextRules: customTextRules,
            edgeSwipeConfiguration: edgeSwipeConfiguration.normalized(for: keymap),
            semiFoldEnabled: semiFoldEnabled,
            suggestionSwipeUpAction: suggestionSwipeUpAction,
            suggestionSwipeDownAction: suggestionSwipeDownAction,
            suggestionSwipeLeftDeleteEnabled: suggestionSwipeLeftDeleteEnabled,
            suggestionSwipeRightSpaceEnabled: suggestionSwipeRightSpaceEnabled,
            suggestionHoldForRolodexEnabled: true,
            hardwareAutocorrectSelectorEnabled: hardwareAutocorrectSelectorEnabled,
            hardwareAutocorrectSelectorInitiationKey: hardwareAutocorrectSelectorInitiationKey,
            hardwareAutocorrectSelectorSelectionKey: hardwareAutocorrectSelectorSelectionKey,
            physicalReturnBehavior: physicalReturnBehavior,
            showQuickInsertHandle: showQuickInsertHandle,
            capsHoldToLockEnabled: capsHoldToLockEnabled,
            capsHoldDurationMs: KeyboardLayoutBounds.clampedHoldActivationDurationMs(capsHoldDurationMs),
            menuHoldToLatchEnabled: menuHoldToLatchEnabled,
            menuHoldDurationMs: KeyboardLayoutBounds.clampedHoldActivationDurationMs(menuHoldDurationMs),
            keyHoldDurationMs: KeyboardLayoutBounds.clampedHoldActivationDurationMs(keyHoldDurationMs),
            rolodexSelectHoldDurationMs: KeyboardLayoutBounds.clampedRolodexSelectHoldDurationMs(
                rolodexSelectHoldDurationMs
            ),
            menuTapLockWindowMs: KeyboardLayoutBounds.clampedMenuTapLockWindowMs(menuTapLockWindowMs),
            deleteHoldEnabled: deleteHoldEnabled,
            deleteHoldWordsBeforeSentence: KeyboardLayoutBounds.clampedDeleteHoldWordCount(
                deleteHoldWordsBeforeSentence
            ),
            layoutPreset: layoutPreset,
            layoutLocale: layoutLocale,
            runtimeLayoutRoute: runtimeLayoutRoute,
            toolbarHeight: KeyboardLayoutBounds.clampedToolbarHeight(toolbarHeight),
            expandedKeyHeight: KeyboardLayoutBounds.clampedExpandedKeyHeight(expandedKeyHeight),
            suggestionVisibleWordCount: KeyboardLayoutBounds.clampedSuggestionVisibleWordCount(suggestionVisibleWordCount),
            suggestionRowHeight: min(max(suggestionRowHeight, KeyboardLayoutBounds.suggestionRowHeightRange.lowerBound), KeyboardLayoutBounds.suggestionRowHeightRange.upperBound),
            toolbarKeyCount: KeyboardLayoutBounds.clampedToolbarCount(toolbarKeyCount),
            symbolTopRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount),
            symbolMiddleRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(symbolMiddleRowKeyCount),
            symbolBottomRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(symbolBottomRowKeyCount),
            letterTopRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount),
            letterMiddleRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(letterMiddleRowKeyCount),
            letterBottomRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(letterBottomRowKeyCount),
            keymap: keymap
        )
        snapshot.stableUserBucket = preservedRuntimeSettings.stableUserBucket
        snapshot.remoteConfig = preservedRuntimeSettings.remoteConfig
        snapshot.remoteConfigFetchedAt = preservedRuntimeSettings.remoteConfigFetchedAt
        snapshot.inputKernelFallbackDisabled = preservedRuntimeSettings.inputKernelFallbackDisabled
        snapshot.predictionDisabled = preservedRuntimeSettings.predictionDisabled
        snapshot.glideDisabled = preservedRuntimeSettings.glideDisabled
        snapshot.clipboardDisabled = clipboardDisabled
        snapshot.saveClipboardSettingsWithLiveKeyboard = saveClipboardSettingsWithLiveKeyboard
        #if HWC_HARDWARE_CAPTURE || HWC_INTERNAL_BUILD
        snapshot.signalRelayEnabled = signalRelayEnabled
        snapshot.signalRelayEmitKeyUp = signalRelayEmitKeyUp
        snapshot.signalRelayPriorityMode = signalRelayPriorityMode
        snapshot.signalRelaySessionPersist = signalRelaySessionPersist
        snapshot.signalRelayHoldTriggerMs = KeyboardLayoutBounds.clampedHardwareHoldTriggerMs(signalRelayHoldTriggerMs)
        snapshot.hardwarePremiumAccessUnlocked = hardwarePremiumAccessUnlocked
        #endif
        return snapshot
    }

    var keymap: KeyboardKeymap {
        KeyboardKeymap(
            quickInsertRow: normalizedRow(quickInsertRow, row: .quickInsert),
            holdQuickInsertRow: normalizedRow(holdQuickInsertRow, row: .holdQuickInsert),
            toolbarRow: normalizedRow(toolbarRow, row: .toolbar),
            holdToolbarRow: normalizedRow(holdToolbarRow, row: .holdToolbar),
            symbolTopRow: normalizedRow(symbolTopRow, row: .symbolTop),
            holdSymbolTopRow: normalizedRow(holdSymbolTopRow, row: .holdSymbolTop),
            symbolMiddleRow: normalizedRow(symbolMiddleRow, row: .symbolMiddle),
            holdSymbolMiddleRow: normalizedRow(holdSymbolMiddleRow, row: .holdSymbolMiddle),
            symbolBottomRow: normalizedRow(symbolBottomRow, row: .symbolBottom),
            holdSymbolBottomRow: normalizedRow(holdSymbolBottomRow, row: .holdSymbolBottom),
            letterTopRow: normalizedRow(letterTopRow, row: .letterTop),
            holdLetterTopRow: normalizedRow(holdLetterTopRow, row: .holdLetterTop),
            letterMiddleRow: normalizedRow(letterMiddleRow, row: .letterMiddle),
            holdLetterMiddleRow: normalizedRow(holdLetterMiddleRow, row: .holdLetterMiddle),
            letterBottomRow: normalizedRow(letterBottomRow, row: .letterBottom),
            holdLetterBottomRow: normalizedRow(holdLetterBottomRow, row: .holdLetterBottom),
            symbolUtilityRow: normalizedRow(symbolUtilityRow, row: .symbolUtility),
            letterUtilityRow: normalizedRow(letterUtilityRow, row: .letterUtility),
            trailingUtilityRow: normalizedRow(trailingUtilityRow, row: .trailingUtility),
            expandedTrailingUtilityRow: normalizedRow(
                expandedTrailingUtilityRow,
                row: .expandedTrailingUtility
            ),
            expandedLetterTrailingUtilityRow: normalizedRow(
                expandedLetterTrailingUtilityRow,
                row: .expandedLetterTrailingUtility
            ),
            letterBottomLeadingRow: normalizedRow(letterBottomLeadingRow, row: .letterBottomLeading),
            customLayers: customKeymapLayers,
            keyDimensionOverrides: keyDimensionOverrides,
            rows: keymapRows.isEmpty ? nil : keymapRows
        )
    }

    var activePresetTitle: String {
        layoutPreset.title
    }

    var activeLayoutTitle: String {
        layoutLocale.shortTitle
    }

    var keyboardStatusTitle: String {
        guard sharedContainerAvailable else {
            return "Limited Mode"
        }

        guard let keyboardLastSeenAt else {
            return "Keyboard Not Verified"
        }

        if Date().timeIntervalSince(keyboardLastSeenAt) < 600 {
            return "Keyboard Linked"
        }

        return "Keyboard Seen Earlier"
    }

    var keyboardStatusDetail: String {
        guard sharedContainerAvailable else {
            return "HWC cannot open the keyboard settings container on this device right now."
        }

        guard let keyboardLastSeenAt else {
            return "Open any text field with HWC Keyboard to confirm install, full access, and local settings."
        }

        if Date().timeIntervalSince(keyboardLastSeenAt) < 600 {
            return "HWC Keyboard checked in recently, so keyboard settings are available."
        }

        return "HWC Keyboard was seen before, but not recently. Open a text field with the keyboard active to refresh status."
    }

    var sharedSyncTitle: String {
        guard sharedContainerAvailable else {
            return "Keyboard Settings Unavailable"
        }

        if isKeyboardRecentlySeen {
            return "Keyboard Settings Active"
        }

        return "Keyboard Settings Pending"
    }

    var sharedSyncDetail: String {
        guard sharedContainerAvailable else {
            return "The keyboard settings container is unavailable here, so companion edits may stay local."
        }

        if isKeyboardRecentlySeen {
            return "The keyboard checked in recently, so theme, keymap, sizing, and haptic settings are available."
        }

        return "Keyboard settings are ready, but the keyboard has not checked in recently. Open a text field with HWC Keyboard after enabling Allow Full Access."
    }

    var fullAccessStatusTitle: String {
        isKeyboardFullAccessRecentlyConfirmed ? "Full Access Verified" : "Needs Verification"
    }

    var fullAccessStatusDetail: String {
        if isKeyboardFullAccessRecentlyConfirmed {
            return "HWC Keyboard confirmed Full Access when it became active. No keypress was required."
        }

        return "Switch to HWC Keyboard in any text field. It reports Full Access as soon as it opens; no typing is required."
    }

    var limitedModeTitle: String {
        isLiveSyncVerified ? "Keyboard Settings Ready" : "Limited Mode"
    }

    var limitedModeDetail: String {
        if isLiveSyncVerified {
            return "Companion edits can move into the live keyboard right away."
        }

        return "Until keyboard settings are verified, the companion can still edit locally, but the keyboard may keep using its last-known configuration."
    }

    var limitedModeFeatures: [String] {
        [
            "Custom keymaps edited here may not reach the live keyboard until keyboard settings are verified.",
            "Theme, row sizing, and shortcut changes may stay local to the app instead of the keyboard.",
            "Vibration settings can remain local because keyboard haptics rely on the same open-access path.",
            "Future online features remain off in this build."
        ]
    }

    var dataUseTitle: String {
        "Local First, Encrypted Backup"
    }

    var dataUseDetail: String {
        #if HWC_HARDWARE_CAPTURE || HWC_INTERNAL_BUILD
        return "HWC keeps working data locally. When iOS allows HWC to use iCloud, the app also writes a client-side encrypted private snapshot of settings, keymaps and Additional Layers, Autobot and typing-learning state, custom words and rules, and saved clipboard snippets. StoreKit entitlement authority and optional tester diagnostics are not copied into the snapshot."
        #else
        return "HWC keeps working data locally. When iOS allows HWC to use iCloud, the app also writes a client-side encrypted private snapshot of settings, keymaps and Additional Layers, Autobot and typing-learning state, custom words and rules, and saved clipboard snippets. StoreKit entitlement authority and diagnostics are not copied into the snapshot."
        #endif
    }

    var shouldShowMigrationNotice: Bool {
        guard let settingsMigratedAt else {
            return false
        }

        guard let migrationNoticeDismissedAt else {
            return true
        }

        return migrationNoticeDismissedAt < settingsMigratedAt
    }

    var migrationNoticeTitle: String {
        "Settings Migrated For Keyboard Sync"
    }

    var migrationNoticeDetail: String {
        guard let settingsMigratedAt else {
            return ""
        }

        return "Earlier local settings were copied into the shared keyboard container \(relativeTimestamp(settingsMigratedAt)) so the app and keyboard can use the same on-device configuration."
    }

    func refreshKeyboardStatus() {
        keyboardLastSeenAt = KeyboardSharedPreferences.lastKeyboardSeenAt()
        sharedContainerAvailable = KeyboardSharedPreferences.isSharedContainerAvailable
        settingsMigratedAt = KeyboardSharedPreferences.lastMigrationAt()
        migrationNoticeDismissedAt = Self.localDate(for: LocalKey.migrationNoticeDismissedAt)
        setupSplashDismissedAt = Self.localDate(for: LocalKey.setupSplashDismissedAt)
        setupGateStartedAt = Self.localDate(for: LocalKey.setupGateStartedAt)
        setupRequiredRestartBootedAt = Self.currentDeviceBootDate()
        setupAssistiveTouchRunning = UIAccessibility.isAssistiveTouchRunning
        setupGateCompletedAt = Self.localDate(for: LocalKey.setupGateCompletedAt)
    }

    var isSetupGateComplete: Bool {
        setupGateCompletedAt != nil
    }

    var isSetupRestartComplete: Bool {
        guard let setupGateStartedAt else { return false }
        return setupRequiredRestartBootedAt > setupGateStartedAt
    }

    var isSetupFullAccessComplete: Bool {
        sharedContainerAvailable && isKeyboardFullAccessRecentlyConfirmed
    }

    var isSetupAssistiveTouchComplete: Bool {
        setupAssistiveTouchRunning
    }

    func dismissMigrationNotice() {
        let referenceDate = settingsMigratedAt ?? Date()
        UserDefaults.standard.set(referenceDate.timeIntervalSince1970, forKey: LocalKey.migrationNoticeDismissedAt)
        migrationNoticeDismissedAt = referenceDate
    }

    func dismissSetupSplash() {
        KeyboardSharedPreferences.markCompanionSetupCompleted()
        let referenceDate = Date()
        UserDefaults.standard.set(referenceDate.timeIntervalSince1970, forKey: LocalKey.setupSplashDismissedAt)
        setupSplashDismissedAt = referenceDate
    }

    func completeSetupGateIfReady() {
        guard isSetupFullAccessComplete else { return }
        KeyboardSharedPreferences.markCompanionSetupCompleted()
        let referenceDate = Date()
        UserDefaults.standard.set(referenceDate.timeIntervalSince1970, forKey: LocalKey.setupGateCompletedAt)
        UserDefaults.standard.set(referenceDate.timeIntervalSince1970, forKey: LocalKey.setupSplashDismissedAt)
        setupGateCompletedAt = referenceDate
        setupSplashDismissedAt = referenceDate
    }

    private static func currentDeviceBootDate(now: Date = Date()) -> Date {
        now.addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
    }

    func resetToDefaults() {
        KeyboardSharedPreferences.clearSuggestionLearningData(notify: false)
        apply(snapshot: .default)
    }

    func resetAutocorrectLearning() {
        KeyboardSharedPreferences.clearSuggestionLearningData()
    }

    func resetKeymapToDefaults() {
        let fallbackPreset = layoutPreset == .custom ? KeyboardLayoutPreset.compact : layoutPreset
        let fallbackKeymap = KeyboardKeymap.preset(fallbackPreset)
        let protectedABC = KeyboardSettingsSnapshot.protectedABCLayerSignature

        let restoredKeymap = KeyboardKeymap(
            quickInsertRow: normalizedRow(fallbackKeymap.quickInsertRow, row: .quickInsert),
            holdQuickInsertRow: normalizedRow(fallbackKeymap.holdQuickInsertRow, row: .holdQuickInsert),
            toolbarRow: normalizedRow(fallbackKeymap.toolbarRow, row: .toolbar),
            holdToolbarRow: normalizedRow(fallbackKeymap.holdToolbarRow, row: .holdToolbar),
            symbolTopRow: normalizedRow(fallbackKeymap.symbolTopRow, row: .symbolTop),
            holdSymbolTopRow: normalizedRow(fallbackKeymap.holdSymbolTopRow, row: .holdSymbolTop),
            symbolMiddleRow: normalizedRow(fallbackKeymap.symbolMiddleRow, row: .symbolMiddle),
            holdSymbolMiddleRow: normalizedRow(fallbackKeymap.holdSymbolMiddleRow, row: .holdSymbolMiddle),
            symbolBottomRow: normalizedRow(fallbackKeymap.symbolBottomRow, row: .symbolBottom),
            holdSymbolBottomRow: normalizedRow(fallbackKeymap.holdSymbolBottomRow, row: .holdSymbolBottom),
            letterTopRow: protectedABC.topRow,
            holdLetterTopRow: normalizedRow(fallbackKeymap.holdLetterTopRow, row: .holdLetterTop),
            letterMiddleRow: protectedABC.middleRow,
            holdLetterMiddleRow: normalizedRow(fallbackKeymap.holdLetterMiddleRow, row: .holdLetterMiddle),
            letterBottomRow: protectedABC.bottomRow,
            holdLetterBottomRow: normalizedRow(fallbackKeymap.holdLetterBottomRow, row: .holdLetterBottom),
            symbolUtilityRow: normalizedRow(fallbackKeymap.symbolUtilityRow, row: .symbolUtility),
            letterUtilityRow: normalizedRow(fallbackKeymap.letterUtilityRow, row: .letterUtility),
            trailingUtilityRow: normalizedRow(fallbackKeymap.trailingUtilityRow, row: .trailingUtility),
            expandedTrailingUtilityRow: normalizedRow(
                fallbackKeymap.expandedTrailingUtilityRow,
                row: .expandedTrailingUtility
            ),
            expandedLetterTrailingUtilityRow: normalizedRow(
                fallbackKeymap.expandedLetterTrailingUtilityRow,
                row: .expandedLetterTrailingUtility
            ),
            letterBottomLeadingRow: normalizedRow(
                fallbackKeymap.letterBottomLeadingRow,
                row: .letterBottomLeading
            )
        )

        var nextSnapshot = snapshot
        nextSnapshot.layoutPreset = fallbackPreset
        nextSnapshot.toolbarKeyCount = fallbackKeymap.toolbarRow.count
        nextSnapshot.symbolTopRowKeyCount = fallbackKeymap.symbolTopRow.count
        nextSnapshot.symbolMiddleRowKeyCount = fallbackKeymap.symbolMiddleRow.count
        nextSnapshot.symbolBottomRowKeyCount = fallbackKeymap.symbolBottomRow.count
        nextSnapshot.letterTopRowKeyCount = protectedABC.topRow.count
        nextSnapshot.letterMiddleRowKeyCount = protectedABC.middleRow.count
        nextSnapshot.letterBottomRowKeyCount = protectedABC.bottomRow.count
        nextSnapshot.keymap = restoredKeymap
        apply(snapshot: nextSnapshot)
    }

    func applyLayoutLocale(_ locale: KeyboardLayoutLocale) {
        var nextSnapshot = snapshot
        let fallbackKeymap = KeyboardKeymap.preset(.compact)

        nextSnapshot.layoutLocale = locale
        nextSnapshot.layoutPreset = .compact
        nextSnapshot.toolbarKeyCount = fallbackKeymap.toolbarRow.count
        nextSnapshot.symbolTopRowKeyCount = fallbackKeymap.symbolTopRow.count
        nextSnapshot.symbolMiddleRowKeyCount = fallbackKeymap.symbolMiddleRow.count
        nextSnapshot.symbolBottomRowKeyCount = fallbackKeymap.symbolBottomRow.count
        nextSnapshot.letterTopRowKeyCount = fallbackKeymap.letterTopRow.count
        nextSnapshot.letterMiddleRowKeyCount = fallbackKeymap.letterMiddleRow.count
        nextSnapshot.letterBottomRowKeyCount = fallbackKeymap.letterBottomRow.count
        nextSnapshot.keymap = fallbackKeymap
        apply(snapshot: nextSnapshot)
    }

    func restoreABCDefaults() {
        let protectedABC = KeyboardSettingsSnapshot.protectedABCLayerSignature
        let fallbackPreset = layoutPreset == .custom ? KeyboardLayoutPreset.compact : layoutPreset
        let fallbackKeymap = KeyboardKeymap.preset(fallbackPreset)

        var nextSnapshot = snapshot
        nextSnapshot.letterTopRowKeyCount = protectedABC.topRow.count
        nextSnapshot.letterMiddleRowKeyCount = protectedABC.middleRow.count
        nextSnapshot.letterBottomRowKeyCount = protectedABC.bottomRow.count
        nextSnapshot.keymap.letterTopRow = protectedABC.topRow
        nextSnapshot.keymap.holdLetterTopRow = normalizedRow(fallbackKeymap.holdLetterTopRow, row: .holdLetterTop)
        nextSnapshot.keymap.letterMiddleRow = protectedABC.middleRow
        nextSnapshot.keymap.letterUtilityRow = normalizedRow(
            fallbackKeymap.letterUtilityRow,
            row: .letterUtility
        )
        nextSnapshot.keymap.expandedLetterTrailingUtilityRow = normalizedRow(
            fallbackKeymap.expandedLetterTrailingUtilityRow,
            row: .expandedLetterTrailingUtility
        )
        nextSnapshot.keymap.letterBottomLeadingRow = normalizedRow(
            fallbackKeymap.letterBottomLeadingRow,
            row: .letterBottomLeading
        )
        nextSnapshot.keymap.holdLetterMiddleRow = normalizedRow(
            fallbackKeymap.holdLetterMiddleRow,
            row: .holdLetterMiddle
        )
        nextSnapshot.keymap.letterBottomRow = protectedABC.bottomRow
        nextSnapshot.keymap.holdLetterBottomRow = normalizedRow(
            fallbackKeymap.holdLetterBottomRow,
            row: .holdLetterBottom
        )
        apply(snapshot: nextSnapshot)
    }

    #if HWC_HARDWARE_CAPTURE || HWC_INTERNAL_BUILD
    func setHardwarePremiumAccessUnlocked(_ unlocked: Bool, clearSession: Bool = true) {
        guard hardwarePremiumAccessUnlocked != unlocked else { return }
        hardwarePremiumAccessUnlocked = unlocked
        #if HWC_INTERNAL_BUILD
        if clearSession && !unlocked {
            KeyEventRing.clear()
        }
        #endif
    }

    func applyHardwareKeypressReadingDefaults(clearSession: Bool = true) {
        guard signalRelayEnabled else { return }

        var nextSnapshot = snapshot
        nextSnapshot.signalRelayEmitKeyUp = true
        nextSnapshot.signalRelayPriorityMode = true
        nextSnapshot.signalRelaySessionPersist = true

        if nextSnapshot != snapshot {
            apply(snapshot: nextSnapshot)
        }
        #if HWC_INTERNAL_BUILD
        if clearSession {
            KeyEventRing.clear()
        }
        #endif
    }

    func disableHardwareKeypressReading(clearSession: Bool = true) {
        var nextSnapshot = snapshot
        nextSnapshot.signalRelayEnabled = false
        nextSnapshot.signalRelayEmitKeyUp = false
        nextSnapshot.signalRelayPriorityMode = false
        nextSnapshot.signalRelaySessionPersist = false

        if nextSnapshot != snapshot {
            apply(snapshot: nextSnapshot)
        }
        #if HWC_INTERNAL_BUILD
        if clearSession {
            KeyEventRing.clear()
        }
        #endif
    }
    #else
    func applyHardwareKeypressReadingDefaults(clearSession: Bool = true) {}
    func disableHardwareKeypressReading(clearSession: Bool = true) {}
    #endif

    func previewFeedback() {
        KeyboardFeedbackEngine.play(using: snapshot)
    }

    func applyPreset(_ preset: KeyboardLayoutPreset) {
        guard preset != .custom else { return }
        applyLayoutPreset(preset)
    }

    func applyPreset(_ preset: KeyboardLayoutPreset, to surface: KeyboardRowSurface, customLayerID: UUID?) {
        guard preset != .custom else { return }
        var nextKeymap = keymap
        let template = KeyboardKeymap.preset(preset)
        nextKeymap.applyPresetLayer(from: template, to: surface, customLayerID: customLayerID)
        applyDynamicKeymap(nextKeymap)
    }

    @discardableResult
    func createSavedPreset(title: String) -> KeyboardSavedPreset {
        let preset = KeyboardSavedPreset(title: title, keymap: keymap)
        _ = commitSavedPresets(savedKeymapPresets + [preset])
        return preset
    }

    @discardableResult
    func beginBuiltInTemplateEdit(_ preset: KeyboardLayoutPreset) throws -> KeyboardSavedPreset {
        guard preset != .custom,
              savedKeymapPresets.count < KeyboardSavedPresetStore.maximumPresetCount else {
            throw HWKKeymapTransferError.importFailed
        }
        let saved = KeyboardSavedPreset(
            title: uniqueImportedPresetTitle(preset.title),
            keymap: KeyboardKeymap.preset(preset),
            builtInTemplateSource: preset.rawValue
        )
        guard commitSavedPresets(savedKeymapPresets + [saved]) else {
            throw HWKKeymapTransferError.importFailed
        }
        return saved
    }

    @discardableResult
    func cloneBuiltInTemplate(_ preset: KeyboardLayoutPreset) throws -> KeyboardSavedPreset {
        guard preset != .custom,
              savedKeymapPresets.count < KeyboardSavedPresetStore.maximumPresetCount else {
            throw HWKKeymapTransferError.importFailed
        }
        let clone = KeyboardSavedPreset(
            title: uniqueImportedPresetTitle("\(preset.title) Copy"),
            keymap: KeyboardKeymap.preset(preset)
        )
        guard commitSavedPresets(savedKeymapPresets + [clone]) else {
            throw HWKKeymapTransferError.importFailed
        }
        return clone
    }

    @discardableResult
    func cloneSavedPreset(id: UUID) throws -> KeyboardSavedPreset {
        guard let source = savedKeymapPresets.first(where: { $0.id == id }),
              savedKeymapPresets.count < KeyboardSavedPresetStore.maximumPresetCount else {
            throw HWKKeymapTransferError.importFailed
        }
        let title = uniqueImportedPresetTitle("\(source.title) Copy")
        var transfer = source.transferLayer
        transfer?.title = title
        let clone = KeyboardSavedPreset(
            title: title,
            keymap: source.keymap,
            transferLayer: transfer
        )
        guard commitSavedPresets(savedKeymapPresets + [clone]) else {
            throw HWKKeymapTransferError.importFailed
        }
        return clone
    }

    func saveEditedPreset(
        id: UUID,
        from surface: KeyboardRowSurface,
        customLayerID: UUID?
    ) throws {
        guard let index = savedKeymapPresets.firstIndex(where: { $0.id == id }) else {
            throw HWKKeymapTransferError.importFailed
        }
        var next = savedKeymapPresets
        var edited = next[index]
        var transfer = try customLayerID.map {
            try keymap.transferDocument(forCustomLayerID: $0)
        } ?? keymap.transferDocument(surface: surface, title: edited.title)
        transfer.format = HWKKeymapTransferDocument.formatIdentifier
        transfer.title = edited.title
        edited.transferLayer = transfer
        edited.keymap = keymap
        edited.updatedAt = Date()
        next[index] = edited
        guard commitSavedPresets(next) else {
            throw HWKKeymapTransferError.importFailed
        }
    }

    func applySavedPreset(id: UUID) {
        guard let preset = savedKeymapPresets.first(where: { $0.id == id }) else { return }
        apply(keymap: preset.keymap, preset: .custom)
    }

    func applySavedPreset(id: UUID, to surface: KeyboardRowSurface, customLayerID: UUID?) {
        guard let preset = savedKeymapPresets.first(where: { $0.id == id }) else { return }
        var nextKeymap = keymap
        if let transferLayer = preset.transferLayer {
            var targetSurface = surface
            if let customLayerID,
               let targetLayer = nextKeymap.customLayer(for: customLayerID) {
                let targetStyle: KeyboardCustomLayerStyle = transferLayer.kind == .mainRow
                    ? .row
                    : .expanded
                if targetLayer.style != targetStyle {
                    nextKeymap.convertCustomLayer(id: customLayerID, to: targetStyle)
                }
                targetSurface = targetStyle == .row ? .mainRow : .symbols1
            } else {
                let targetIsMainRow = surface == .mainRow
                guard targetIsMainRow == (transferLayer.kind == .mainRow) else { return }
            }
            guard (try? nextKeymap.applyTransferDocument(
                transferLayer,
                to: targetSurface,
                customLayerID: customLayerID
            )) != nil else { return }
            applyDynamicKeymap(nextKeymap)
            return
        }
        nextKeymap.applyPresetLayer(from: preset.keymap, to: surface, customLayerID: customLayerID)
        applyDynamicKeymap(nextKeymap)
    }

    func updateSavedPreset(id: UUID) {
        guard let index = savedKeymapPresets.firstIndex(where: { $0.id == id }) else { return }
        var next = savedKeymapPresets
        next[index].keymap = keymap
        next[index].updatedAt = Date()
        _ = commitSavedPresets(next)
    }

    func updateSavedPreset(
        id: UUID,
        from surface: KeyboardRowSurface,
        customLayerID: UUID?
    ) {
        guard let index = savedKeymapPresets.firstIndex(where: { $0.id == id }) else { return }
        var next = savedKeymapPresets
        next[index].keymap = keymap
        if next[index].transferLayer != nil {
            next[index].transferLayer = try? customLayerID.map {
                try keymap.transferDocument(forCustomLayerID: $0)
            } ?? keymap.transferDocument(surface: surface, title: next[index].title)
        }
        next[index].updatedAt = Date()
        _ = commitSavedPresets(next)
    }

    func renameSavedPreset(id: UUID, title: String) {
        guard let index = savedKeymapPresets.firstIndex(where: { $0.id == id }) else { return }
        var next = savedKeymapPresets
        next[index].title = KeyboardSavedPreset.normalizedTitle(title)
        next[index].updatedAt = Date()
        _ = commitSavedPresets(next)
    }

    func deleteSavedPreset(id: UUID) {
        _ = commitSavedPresets(savedKeymapPresets.filter { $0.id != id })
    }

    @discardableResult
    private func commitSavedPresets(_ presets: [KeyboardSavedPreset]) -> Bool {
        let normalized = KeyboardSavedPresetStore.normalized(presets)
        guard saveSavedPresets(normalized) else { return false }
        savedKeymapPresets = normalized
        return true
    }

    func applyThemeProfile(_ theme: CompanionAppTheme) {
        var nextSnapshot = snapshot
        nextSnapshot.appTheme = theme
        apply(snapshot: nextSnapshot)
    }

    func restoreRow(_ row: KeyboardRowKind) {
        let restored: [String]

        if row.tapVariant.isABCLetterRow,
           !row.isHoldRow,
           let protectedABCRow = ProtectedABCLayerMap.defaultRow(for: row) {
            restored = protectedABCRow
        } else {
            let fallbackPreset = layoutPreset == .custom ? KeyboardLayoutPreset.compact : layoutPreset
            restored = values(for: row, from: KeyboardKeymap.preset(fallbackPreset))
        }

        setRow(row, values: restored, markCustom: true)
    }

    func values(for row: KeyboardRowKind) -> [String] {
        switch row {
        case .quickInsert:
            return quickInsertRow
        case .holdQuickInsert:
            return holdQuickInsertRow
        case .toolbar:
            return toolbarRow
        case .holdToolbar:
            return holdToolbarRow
        case .symbolUtility:
            return symbolUtilityRow
        case .symbolTop:
            return symbolTopRow
        case .holdSymbolTop:
            return holdSymbolTopRow
        case .symbolMiddle:
            return symbolMiddleRow
        case .holdSymbolMiddle:
            return holdSymbolMiddleRow
        case .symbolBottom:
            return symbolBottomRow
        case .holdSymbolBottom:
            return holdSymbolBottomRow
        case .symbolMain:
            return symbolTopRow
        case .symbolHold:
            return holdSymbolTopRow
        case .trailingUtility:
            return trailingUtilityRow
        case .expandedTrailingUtility:
            return expandedTrailingUtilityRow
        case .expandedLetterTrailingUtility:
            return expandedLetterTrailingUtilityRow
        case .letterUtility:
            return letterUtilityRow
        case .letterBottomLeading:
            return letterBottomLeadingRow
        case .letterTop:
            return letterTopRow
        case .holdLetterTop:
            return holdLetterTopRow
        case .letterMiddle:
            return letterMiddleRow
        case .holdLetterMiddle:
            return holdLetterMiddleRow
        case .letterBottom:
            return letterBottomRow
        case .holdLetterBottom:
            return holdLetterBottomRow
        case .letterMain:
            return letterTopRow
        case .letterHold:
            return holdLetterTopRow
        }
    }

    func keyBinding(for row: KeyboardRowKind, index: Int) -> Binding<String> {
        Binding(
            get: {
                let values = self.values(for: row)
                guard values.indices.contains(index) else { return "" }
                return values[index]
            },
            set: { newValue in
                self.updateValue(newValue, for: row, index: index)
            }
        )
    }

    func updateValue(_ newValue: String, for row: KeyboardRowKind, index: Int) {
        let normalized = normalizedKey(newValue)
        if let mirrorRows = modeMirrorRows(for: row) {
            var tapValues = normalizedRow(values(for: mirrorRows.tap), row: mirrorRows.tap, trimmingToVisibleCount: true)
            var holdValues = normalizedRow(values(for: mirrorRows.hold), row: mirrorRows.hold, trimmingToVisibleCount: true)
            let targetValues = row.isHoldRow ? holdValues : tapValues
            let mirrorValues = row.isHoldRow ? tapValues : holdValues
            guard targetValues.indices.contains(index) else { return }

            let currentValue = targetValues[index]
            let mirroredValue = mirrorValues.indices.contains(index) ? mirrorValues[index] : ""
            if mirrorsModeKey(normalized) || mirrorsModeKey(currentValue) || mirrorsModeKey(mirroredValue) {
                if mirrorsModeKey(normalized) {
                    tapValues[index] = normalized
                    holdValues[index] = normalized
                } else if row.isHoldRow {
                    tapValues[index] = ""
                    holdValues[index] = normalized
                } else {
                    tapValues[index] = normalized
                    holdValues[index] = ""
                }
                setRows(
                    [
                        (mirrorRows.tap, tapValues),
                        (mirrorRows.hold, holdValues),
                    ],
                    markCustom: true
                )
                return
            }
        }

        var values = normalizedRow(values(for: row), row: row, trimmingToVisibleCount: true)
        guard values.indices.contains(index) else { return }
        values[index] = normalized
        setRow(row, values: values, markCustom: true)
    }

    @discardableResult
    func removeVisibleKey(at index: Int, from row: KeyboardRowKind) -> Bool {
        let baseRow = row.tapVariant
        guard canRemoveVisibleKey(at: index, from: baseRow) else { return false }

        let nextTapValues = rowValuesRemovingVisibleSlot(index, row: baseRow)
        let nextHoldValues = baseRow.supportsHoldCustomization
            ? rowValuesRemovingVisibleSlot(index, row: baseRow.holdVariant)
            : nil

        isApplyingSnapshot = true
        assignNormalizedRow(nextTapValues, to: baseRow)
        if let nextHoldValues {
            assignNormalizedRow(nextHoldValues, to: baseRow.holdVariant)
        }
        decrementVisibleKeyCount(for: baseRow)
        layoutPreset = .custom
        runtimeLayoutRoute = .storedKeymap

        var nextKeymap = KeyboardKeymap(
            quickInsertRow: quickInsertRow,
            holdQuickInsertRow: holdQuickInsertRow,
            toolbarRow: toolbarRow,
            holdToolbarRow: holdToolbarRow,
            symbolTopRow: symbolTopRow,
            holdSymbolTopRow: holdSymbolTopRow,
            symbolMiddleRow: symbolMiddleRow,
            holdSymbolMiddleRow: holdSymbolMiddleRow,
            symbolBottomRow: symbolBottomRow,
            holdSymbolBottomRow: holdSymbolBottomRow,
            letterTopRow: letterTopRow,
            holdLetterTopRow: holdLetterTopRow,
            letterMiddleRow: letterMiddleRow,
            holdLetterMiddleRow: holdLetterMiddleRow,
            letterBottomRow: letterBottomRow,
            holdLetterBottomRow: holdLetterBottomRow,
            symbolUtilityRow: symbolUtilityRow,
            letterUtilityRow: letterUtilityRow,
            trailingUtilityRow: trailingUtilityRow,
            expandedTrailingUtilityRow: expandedTrailingUtilityRow,
            expandedLetterTrailingUtilityRow: expandedLetterTrailingUtilityRow,
            letterBottomLeadingRow: letterBottomLeadingRow,
            customAddedRows: customRowsForLegacyRebuild,
            customLayers: customKeymapLayers,
            keyDimensionOverrides: keyDimensionOverrides
        )
        nextKeymap.replaceRows(rowsResizedForCurrentCounts(nextKeymap.rows))
        keymapRows = nextKeymap.rows

        isApplyingSnapshot = false
        persistCurrentSnapshot()
        return true
    }

    private var customRowsForLegacyRebuild: [KeyboardLayoutRow] {
        keymapRows.filter {
            ($0.customLayerID == nil && ($0.kind == .symbolMain || $0.kind == .letterMain)) ||
            $0.customLayerID != nil
        }
    }

    func keyDimensions(for row: KeyboardRowKind, index: Int) -> KeyboardLayoutKeyDimensions {
        let surface = dimensionSurface(for: row)
        let kind = dimensionKind(for: row)
        if let key = keymapRows.first(where: {
            $0.surface == surface && $0.kind == kind && !$0.holdLayer
        }).flatMap({ $0.keys.indices.contains(index) ? $0.keys[index] : nil }) {
            return KeyboardLayoutKeyDimensions(widthWeight: key.widthWeight, heightOverride: key.heightOverride)
        }

        return keymap.keyDimensions(
            surface: surface,
            kind: kind,
            holdLayer: false,
            slotIndex: index
        )
    }

    func updateKeyWidth(_ widthWeight: CGFloat, for row: KeyboardRowKind, index: Int) {
        let current = keyDimensions(for: row, index: index)
        setKeyDimensions(
            KeyboardLayoutKeyDimensions(widthWeight: widthWeight, heightOverride: current.heightOverride),
            for: row,
            index: index
        )
    }

    func updateKeyHeight(_ height: CGFloat, for row: KeyboardRowKind, index: Int) {
        let current = keyDimensions(for: row, index: index)
        setKeyDimensions(
            KeyboardLayoutKeyDimensions(widthWeight: current.widthWeight, heightOverride: height),
            for: row,
            index: index
        )
    }

    func resetKeyDimensions(for row: KeyboardRowKind, index: Int) {
        setKeyDimensions(.identity, for: row, index: index)
    }

    func keymapTableRows(surface: KeyboardRowSurface) -> [KeyboardLayoutRow] {
        keymapRows.filter { row in
            row.customLayerID == nil &&
                row.surface == surface &&
                !row.holdLayer &&
                Self.isEditableTableRow(row.kind, surface: surface)
        }
    }

    func keymapTableKeyValue(rowID: UUID, keyID: UUID) -> String {
        keymapTableKeyValue(rowID: rowID, keyID: keyID, holdLayer: false)
    }

    func keymapTableKeyValue(rowID: UUID, keyID: UUID, holdLayer: Bool) -> String {
        guard let key = keymapRows.first(where: { $0.id == rowID })?.keys.first(where: { $0.id == keyID }) else {
            return ""
        }
        return holdLayer ? (key.hold ?? "") : key.tap
    }

    func keymapTableKeyDimensions(rowID: UUID, keyID: UUID) -> KeyboardLayoutKeyDimensions {
        guard let key = keymapRows.first(where: { $0.id == rowID })?.keys.first(where: { $0.id == keyID }) else {
            return .identity
        }
        return KeyboardLayoutKeyDimensions(widthWeight: key.widthWeight, heightOverride: key.heightOverride)
    }

    @discardableResult
    func addCustomKeymapLayer(surface: KeyboardRowSurface) -> KeyboardCustomLayer {
        var nextKeymap = keymap
        let layer = nextKeymap.addCustomLayer(surface: surface)
        applyDynamicKeymap(nextKeymap, syncICloud: true)
        return layer
    }

    func renameCustomKeymapLayer(id: UUID, title: String) {
        var nextKeymap = keymap
        nextKeymap.renameCustomLayer(id: id, title: title)
        applyDynamicKeymap(nextKeymap)
    }

    func updateCustomKeymapLayerIcon(id: UUID, systemName: String) {
        var nextKeymap = keymap
        nextKeymap.updateCustomLayerIcon(id: id, systemName: systemName)
        applyDynamicKeymap(nextKeymap)
    }

    func convertCustomKeymapLayer(id: UUID, to style: KeyboardCustomLayerStyle) {
        var nextKeymap = keymap
        nextKeymap.convertCustomLayer(id: id, to: style)
        applyDynamicKeymap(nextKeymap)
    }

    func deleteCustomKeymapLayer(id: UUID) {
        var nextKeymap = keymap
        nextKeymap.deleteCustomLayer(id: id)
        applyDynamicKeymap(nextKeymap)
    }

    func customKeymapLayerRows(id: UUID) -> [KeyboardLayoutRow] {
        keymap.customLayerRows(for: id)
    }

    @discardableResult
    func importKeymapTransferData(_ data: Data) throws -> KeyboardCustomLayer {
        let document = try HWKKeymapTransferDocument.decodeFileData(data)
        guard canCreateCustomKeymapLayer(customKeymapLayers.count) else {
            throw HWKKeymapTransferError.importFailed
        }
        var nextKeymap = keymap
        let importedLayer = try nextKeymap.importTransferDocument(document)
        applyDynamicKeymap(nextKeymap, syncICloud: true)
        return importedLayer
    }

    private func uniqueImportedPresetTitle(_ requestedTitle: String) -> String {
        let base = KeyboardSavedPreset.normalizedTitle(requestedTitle)
        let existing = Set(savedKeymapPresets.map { $0.title.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        for number in 2...(KeyboardSavedPresetStore.maximumPresetCount + 1) {
            let suffix = " \(number)"
            let prefixCount = max(1, 40 - suffix.count)
            let candidate = String(base.prefix(prefixCount)) + suffix
            if !existing.contains(candidate.lowercased()) { return candidate }
        }
        return String(base.prefix(35)) + " Copy"
    }

    func exportKeymapTransferData(forCustomLayerID id: UUID) throws -> Data {
        let document = try keymap.transferDocument(forCustomLayerID: id)
        return try document.encodeFileData()
    }

    func exportKeymapTransferData(
        surface: KeyboardRowSurface,
        title: String
    ) throws -> Data {
        let document = try keymap.transferDocument(surface: surface, title: title)
        return try document.encodeFileData()
    }

    func insertKeymapTableRow(after rowID: UUID?, surface: KeyboardRowSurface) {
        guard surface != .mainRow else { return }
        let sourceRows = keymapTableRows(surface: surface)
        let source = rowID.flatMap { id in sourceRows.first { $0.id == id } } ?? sourceRows.last
        let keyCount = min(source?.keys.count ?? KeyboardLayoutBounds.expandedCountRange.lowerBound, KeyboardLayoutBounds.maxKeysPerRow)
        let rowKind: KeyboardRowKind = surface == .letters ? .letterMain : .symbolMain
        let row = KeyboardLayoutRow(
            kind: rowKind,
            surface: surface,
            holdLayer: false,
            keys: (0..<max(1, keyCount)).map { _ in KeyboardLayoutKey(tap: "") },
            height: source?.height
        )
        var nextKeymap = keymap
        nextKeymap.insertRow(row, after: rowID)
        applyDynamicKeymap(nextKeymap)
    }

    func removeKeymapTableRow(id: UUID) {
        guard let row = keymapRows.first(where: { $0.id == id }) else { return }
        guard keymapTableRows(surface: row.surface).count > 1 else { return }
        var nextKeymap = keymap
        nextKeymap.removeRow(id: id)
        nextKeymap.removeCustomRowDimensions(rowID: id)
        applyDynamicKeymap(nextKeymap)
    }

    func insertKeymapTableColumn(after keyID: UUID?, rowID: UUID) {
        guard let rowIndex = keymapRows.firstIndex(where: { $0.id == rowID }) else { return }
        let maxKeyCount = keymapRows[rowIndex].customLayerID == nil
            ? KeyboardLayoutBounds.maxKeysPerRow
            : KeyboardLayoutBounds.expandedCountRange.upperBound
        guard keymapRows[rowIndex].keys.count < maxKeyCount else { return }

        var nextRows = keymapRows
        let insertIndex: Int
        if let keyID, let currentIndex = nextRows[rowIndex].keys.firstIndex(where: { $0.id == keyID }) {
            insertIndex = nextRows[rowIndex].keys.index(after: currentIndex)
        } else {
            insertIndex = nextRows[rowIndex].keys.count
        }
        nextRows[rowIndex].keys.insert(KeyboardLayoutKey(tap: ""), at: insertIndex)
        applyDynamicRows(nextRows)
    }

    func removeKeymapTableColumn(keyID: UUID, rowID: UUID) {
        guard let rowIndex = keymapRows.firstIndex(where: { $0.id == rowID }) else { return }
        let minKeyCount = keymapRows[rowIndex].customLayerID == nil
            ? 1
            : KeyboardLayoutBounds.expandedCountRange.lowerBound
        guard keymapRows[rowIndex].keys.count > minKeyCount else { return }
        guard let keyIndex = keymapRows[rowIndex].keys.firstIndex(where: { $0.id == keyID }) else { return }

        var nextRows = keymapRows
        nextRows[rowIndex].keys.remove(at: keyIndex)
        var nextKeymap = keymap
        nextKeymap.replaceRows(nextRows)
        nextKeymap.removeCustomKeyDimensions(rowID: rowID, keyID: keyID)
        applyDynamicKeymap(nextKeymap)
    }

    func updateKeymapTableKey(rowID: UUID, keyID: UUID, tap: String) {
        updateKeymapTableKey(rowID: rowID, keyID: keyID, value: tap, holdLayer: false)
    }

    func updateKeymapTableKey(rowID: UUID, keyID: UUID, value: String, holdLayer: Bool) {
        guard let rowIndex = keymapRows.firstIndex(where: { $0.id == rowID }),
              let keyIndex = keymapRows[rowIndex].keys.firstIndex(where: { $0.id == keyID }) else {
            return
        }

        var nextRows = keymapRows
        let normalized = normalizedKey(value)
        let currentValue = holdLayer
            ? (nextRows[rowIndex].keys[keyIndex].hold ?? "")
            : nextRows[rowIndex].keys[keyIndex].tap
        let mirroredValue = holdLayer
            ? nextRows[rowIndex].keys[keyIndex].tap
            : (nextRows[rowIndex].keys[keyIndex].hold ?? "")
        if mirrorsModeKey(normalized) || mirrorsModeKey(currentValue) || mirrorsModeKey(mirroredValue) {
            if mirrorsModeKey(normalized) {
                nextRows[rowIndex].keys[keyIndex].tap = normalized
                nextRows[rowIndex].keys[keyIndex].setHoldInput(normalized)
            } else if holdLayer {
                nextRows[rowIndex].keys[keyIndex].tap = ""
                nextRows[rowIndex].keys[keyIndex].setHoldInput(normalized)
            } else {
                nextRows[rowIndex].keys[keyIndex].tap = normalized
                nextRows[rowIndex].keys[keyIndex].setHoldInput(nil)
            }
        } else if holdLayer {
            nextRows[rowIndex].keys[keyIndex].setHoldInput(normalized)
        } else {
            nextRows[rowIndex].keys[keyIndex].tap = normalized
        }
        applyDynamicRows(nextRows)
    }

    func updateKeymapTableKeyWidth(_ widthWeight: CGFloat, rowID: UUID, keyID: UUID) {
        let current = keymapTableKeyDimensions(rowID: rowID, keyID: keyID)
        updateKeymapTableKeyDimensions(
            rowID: rowID,
            keyID: keyID,
            dimensions: KeyboardLayoutKeyDimensions(widthWeight: widthWeight, heightOverride: current.heightOverride)
        )
    }

    func updateKeymapTableKeyHeight(_ height: CGFloat, rowID: UUID, keyID: UUID) {
        let current = keymapTableKeyDimensions(rowID: rowID, keyID: keyID)
        updateKeymapTableKeyDimensions(
            rowID: rowID,
            keyID: keyID,
            dimensions: KeyboardLayoutKeyDimensions(widthWeight: current.widthWeight, heightOverride: height)
        )
    }

    func resetKeymapTableKeyDimensions(rowID: UUID, keyID: UUID) {
        updateKeymapTableKeyDimensions(rowID: rowID, keyID: keyID, dimensions: .identity)
    }

    func swapKeys(
        from sourceRow: KeyboardRowKind,
        sourceIndex: Int,
        to destinationRow: KeyboardRowKind,
        destinationIndex: Int
    ) {
        guard sourceRow != destinationRow || sourceIndex != destinationIndex else { return }

        var sourceValues = values(for: sourceRow)
        var destinationValues = values(for: destinationRow)

        guard sourceValues.indices.contains(sourceIndex),
              destinationValues.indices.contains(destinationIndex) else {
            return
        }

        let sourceValue = sourceValues[sourceIndex]
        let destinationValue = destinationValues[destinationIndex]

        sourceValues[sourceIndex] = normalizedKey(destinationValue)
        destinationValues[destinationIndex] = normalizedKey(sourceValue)

        isApplyingSnapshot = true
        assignNormalizedRow(normalizedRow(sourceValues, row: sourceRow), to: sourceRow)
        assignNormalizedRow(normalizedRow(destinationValues, row: destinationRow), to: destinationRow)
        layoutPreset = .custom
        runtimeLayoutRoute = .storedKeymap
        isApplyingSnapshot = false
        persistCurrentSnapshot()
    }

    func slotCount(for row: KeyboardRowKind) -> Int {
        switch row {
        case .quickInsert:
            return KeyboardKeymap.defaultQuickInsertRow.count
        case .holdQuickInsert:
            return KeyboardKeymap.defaultQuickInsertRow.count
        case .toolbar:
            return KeyboardLayoutBounds.clampedToolbarCount(toolbarKeyCount)
        case .holdToolbar:
            return KeyboardLayoutBounds.clampedToolbarCount(toolbarKeyCount)
        case .symbolUtility:
            return KeyboardKeymap.defaultSymbolUtilityRow.count
        case .symbolTop:
            return KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount)
        case .holdSymbolTop:
            return KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount)
        case .symbolMiddle:
            return KeyboardLayoutBounds.clampedExpandedCount(symbolMiddleRowKeyCount)
        case .holdSymbolMiddle:
            return KeyboardLayoutBounds.clampedExpandedCount(symbolMiddleRowKeyCount)
        case .symbolBottom:
            return KeyboardLayoutBounds.clampedExpandedCount(symbolBottomRowKeyCount)
        case .holdSymbolBottom:
            return KeyboardLayoutBounds.clampedExpandedCount(symbolBottomRowKeyCount)
        case .symbolMain, .symbolHold:
            return KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount)
        case .trailingUtility:
            return KeyboardKeymap.defaultTrailingUtilityRow.count
        case .expandedTrailingUtility:
            return KeyboardKeymap.defaultTrailingUtilityRow.count
        case .expandedLetterTrailingUtility:
            return KeyboardKeymap.defaultTrailingUtilityRow.count
        case .letterUtility:
            return KeyboardKeymap.defaultLetterUtilityRow.count
        case .letterBottomLeading:
            return KeyboardKeymap.defaultLetterBottomLeadingRow.count
        case .letterTop:
            return KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount)
        case .holdLetterTop:
            return KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount)
        case .letterMiddle:
            return KeyboardLayoutBounds.clampedExpandedCount(letterMiddleRowKeyCount)
        case .holdLetterMiddle:
            return KeyboardLayoutBounds.clampedExpandedCount(letterMiddleRowKeyCount)
        case .letterBottom:
            return KeyboardLayoutBounds.clampedExpandedCount(letterBottomRowKeyCount)
        case .holdLetterBottom:
            return KeyboardLayoutBounds.clampedExpandedCount(letterBottomRowKeyCount)
        case .letterMain, .letterHold:
            return KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount)
        }
    }

    private func canRemoveVisibleKey(at index: Int, from row: KeyboardRowKind) -> Bool {
        guard let count = visibleKeyCount(for: row),
              let range = visibleKeyCountRange(for: row) else {
            return false
        }

        return range.contains(count - 1) && (0..<count).contains(index)
    }

    private func visibleKeyCount(for row: KeyboardRowKind) -> Int? {
        switch row.tapVariant {
        case .toolbar:
            return toolbarKeyCount
        case .symbolTop:
            return symbolTopRowKeyCount
        case .symbolMiddle:
            return symbolMiddleRowKeyCount
        case .symbolBottom:
            return symbolBottomRowKeyCount
        case .letterTop:
            return letterTopRowKeyCount
        case .letterMiddle:
            return letterMiddleRowKeyCount
        case .letterBottom:
            return letterBottomRowKeyCount
        default:
            return nil
        }
    }

    private func visibleKeyCountRange(for row: KeyboardRowKind) -> ClosedRange<Int>? {
        switch row.tapVariant {
        case .toolbar:
            return KeyboardLayoutBounds.toolbarCountRange
        case .symbolTop, .symbolMiddle, .symbolBottom, .letterTop, .letterMiddle, .letterBottom:
            return KeyboardLayoutBounds.expandedCountRange
        default:
            return nil
        }
    }

    private func rowValuesRemovingVisibleSlot(_ index: Int, row: KeyboardRowKind) -> [String] {
        var values = normalizedRow(values(for: row), row: row)
        guard values.indices.contains(index) else { return values }

        values.remove(at: index)
        while values.count < maxSlotCount(for: row) {
            values.append("")
        }
        return Array(values.prefix(maxSlotCount(for: row)))
    }

    private func decrementVisibleKeyCount(for row: KeyboardRowKind) {
        switch row.tapVariant {
        case .toolbar:
            toolbarKeyCount = KeyboardLayoutBounds.clampedToolbarCount(toolbarKeyCount - 1)
        case .symbolTop:
            symbolTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount - 1)
        case .symbolMiddle:
            symbolMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolMiddleRowKeyCount - 1)
        case .symbolBottom:
            symbolBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolBottomRowKeyCount - 1)
        case .letterTop:
            letterTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount - 1)
        case .letterMiddle:
            letterMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterMiddleRowKeyCount - 1)
        case .letterBottom:
            letterBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterBottomRowKeyCount - 1)
        default:
            return
        }
    }

    private func apply(snapshot: KeyboardSettingsSnapshot, persist: Bool = true) {
        isApplyingSnapshot = true
        preservedRuntimeSettings = snapshot

        appTheme = snapshot.appTheme
        accentPalette = snapshot.accentPalette
        customKeyStyle = snapshot.customKeyStyle
        vibrationEnabled = snapshot.vibrationEnabled
        feedbackLevel = snapshot.feedbackLevel
        autoPairEnabled = snapshot.autoPairEnabled
        startExpanded = snapshot.startExpanded
        defaultSymbolLayer = snapshot.defaultSymbolLayer
        showQuickInsertRow = snapshot.showQuickInsertRow
        hideKeyboardEnabled = snapshot.hideKeyboardEnabled
        highContrastKeys = snapshot.highContrastKeys
        largeLegends = snapshot.largeLegends
        showControlLabels = snapshot.showControlLabels
        capitalizeFirstLetterEnabled = snapshot.capitalizeFirstLetterEnabled
        doubleSpacePeriodEnabled = snapshot.doubleSpacePeriodEnabled
        autocorrectEnabled = snapshot.autocorrectEnabled
        autocompleteEnabled = snapshot.autocompleteEnabled
        clickToFixEnabled = snapshot.clickToFixEnabled
        autocorrectRankingMethod = snapshot.autocorrectRankingMethod
        autocorrectLogicRecipe = snapshot.autocorrectLogicRecipe
        autocorrectLogicBlocks = snapshot.autocorrectLogicBlocks
        autocorrectLogicLanes = snapshot.autocorrectLogicLanes
        edgeSwipeConfiguration = snapshot.edgeSwipeConfiguration.normalized(for: snapshot.keymap)
        semiFoldEnabled = snapshot.semiFoldEnabled
        suggestionSwipeUpAction = snapshot.suggestionSwipeUpAction
        suggestionSwipeDownAction = snapshot.suggestionSwipeDownAction
        suggestionSwipeLeftDeleteEnabled = snapshot.suggestionSwipeLeftDeleteEnabled
        suggestionSwipeRightSpaceEnabled = snapshot.suggestionSwipeRightSpaceEnabled
        suggestionHoldForRolodexEnabled = true
        hardwareAutocorrectSelectorEnabled = snapshot.hardwareAutocorrectSelectorEnabled
        hardwareAutocorrectSelectorInitiationKey = snapshot.hardwareAutocorrectSelectorInitiationKey
        hardwareAutocorrectSelectorSelectionKey = snapshot.hardwareAutocorrectSelectorSelectionKey
        physicalReturnBehavior = snapshot.physicalReturnBehavior
        clipboardDisabled = snapshot.clipboardDisabled
        saveClipboardSettingsWithLiveKeyboard = snapshot.saveClipboardSettingsWithLiveKeyboard
        showQuickInsertHandle = snapshot.showQuickInsertHandle
        #if HWC_HARDWARE_CAPTURE || HWC_INTERNAL_BUILD
        signalRelayEnabled = snapshot.signalRelayEnabled
        signalRelayEmitKeyUp = snapshot.signalRelayEmitKeyUp
        signalRelayPriorityMode = snapshot.signalRelayPriorityMode
        signalRelaySessionPersist = snapshot.signalRelaySessionPersist
        signalRelayHoldTriggerMs = snapshot.signalRelayHoldTriggerMs
        hardwarePremiumAccessUnlocked = snapshot.hardwarePremiumAccessUnlocked
        #endif
        capsHoldToLockEnabled = snapshot.capsHoldToLockEnabled
        capsHoldDurationMs = snapshot.capsHoldDurationMs
        menuHoldToLatchEnabled = snapshot.menuHoldToLatchEnabled
        menuHoldDurationMs = snapshot.menuHoldDurationMs
        keyHoldDurationMs = snapshot.keyHoldDurationMs
        rolodexSelectHoldDurationMs = snapshot.rolodexSelectHoldDurationMs
        menuTapLockWindowMs = snapshot.menuTapLockWindowMs
        deleteHoldEnabled = snapshot.deleteHoldEnabled
        deleteHoldWordsBeforeSentence = snapshot.deleteHoldWordsBeforeSentence
        layoutPreset = snapshot.layoutPreset
        layoutLocale = snapshot.layoutLocale
        runtimeLayoutRoute = snapshot.runtimeLayoutRoute
        toolbarHeight = snapshot.toolbarHeight
        expandedKeyHeight = snapshot.expandedKeyHeight
        suggestionVisibleWordCount = snapshot.suggestionVisibleWordCount
        suggestionRowHeight = snapshot.suggestionRowHeight
        toolbarKeyCount = snapshot.toolbarKeyCount
        symbolTopRowKeyCount = snapshot.symbolTopRowKeyCount
        symbolMiddleRowKeyCount = snapshot.symbolMiddleRowKeyCount
        symbolBottomRowKeyCount = snapshot.symbolBottomRowKeyCount
        letterTopRowKeyCount = snapshot.letterTopRowKeyCount
        letterMiddleRowKeyCount = snapshot.letterMiddleRowKeyCount
        letterBottomRowKeyCount = snapshot.letterBottomRowKeyCount
        quickInsertRow = normalizedRow(snapshot.keymap.quickInsertRow, row: .quickInsert)
        holdQuickInsertRow = normalizedRow(snapshot.keymap.holdQuickInsertRow, row: .holdQuickInsert)
        toolbarRow = normalizedRow(snapshot.keymap.toolbarRow, row: .toolbar)
        holdToolbarRow = normalizedRow(snapshot.keymap.holdToolbarRow, row: .holdToolbar)
        symbolUtilityRow = normalizedRow(snapshot.keymap.symbolUtilityRow, row: .symbolUtility)
        symbolTopRow = normalizedRow(snapshot.keymap.symbolTopRow, row: .symbolTop)
        holdSymbolTopRow = normalizedRow(snapshot.keymap.holdSymbolTopRow, row: .holdSymbolTop)
        symbolMiddleRow = normalizedRow(snapshot.keymap.symbolMiddleRow, row: .symbolMiddle)
        holdSymbolMiddleRow = normalizedRow(snapshot.keymap.holdSymbolMiddleRow, row: .holdSymbolMiddle)
        symbolBottomRow = normalizedRow(snapshot.keymap.symbolBottomRow, row: .symbolBottom)
        holdSymbolBottomRow = normalizedRow(snapshot.keymap.holdSymbolBottomRow, row: .holdSymbolBottom)
        trailingUtilityRow = normalizedRow(snapshot.keymap.trailingUtilityRow, row: .trailingUtility)
        expandedTrailingUtilityRow = normalizedRow(
            snapshot.keymap.expandedTrailingUtilityRow,
            row: .expandedTrailingUtility
        )
        expandedLetterTrailingUtilityRow = normalizedRow(
            snapshot.keymap.expandedLetterTrailingUtilityRow,
            row: .expandedLetterTrailingUtility
        )
        letterUtilityRow = normalizedRow(snapshot.keymap.letterUtilityRow, row: .letterUtility)
        letterBottomLeadingRow = normalizedRow(snapshot.keymap.letterBottomLeadingRow, row: .letterBottomLeading)
        letterTopRow = normalizedRow(snapshot.keymap.letterTopRow, row: .letterTop)
        holdLetterTopRow = normalizedRow(snapshot.keymap.holdLetterTopRow, row: .holdLetterTop)
        letterMiddleRow = normalizedRow(snapshot.keymap.letterMiddleRow, row: .letterMiddle)
        holdLetterMiddleRow = normalizedRow(snapshot.keymap.holdLetterMiddleRow, row: .holdLetterMiddle)
        letterBottomRow = normalizedRow(snapshot.keymap.letterBottomRow, row: .letterBottom)
        holdLetterBottomRow = normalizedRow(snapshot.keymap.holdLetterBottomRow, row: .holdLetterBottom)
        keyDimensionOverrides = snapshot.keymap.keyDimensionOverrides
        customKeymapLayers = snapshot.keymap.customLayers
        keymapRows = snapshot.keymap.rows

        isApplyingSnapshot = false
        if persist {
            persistCurrentSnapshot()
        }
    }

    private func registerForSharedSettingsChanges() {
        guard sharedSettingsObserverToken == nil else { return }

        let refreshToken = sharedSettingsRefreshToken
        sharedSettingsObserverToken = NotificationCenter.default.addObserver(
            forName: CompanionSharedSettingsDarwinRelay.localNotification,
            object: nil,
            queue: .main
        ) { _ in
            refreshToken.store?.reloadSharedSettingsFromSharedDefaults()
        }
        // Force the process-lifetime Darwin registration after the local
        // subscriber exists, so an immediate relay cannot miss this store.
        _ = CompanionSharedSettingsDarwinRelay.shared
    }

    private func unregisterForSharedSettingsChanges() {
        guard let observer = sharedSettingsObserverToken else { return }
        NotificationCenter.default.removeObserver(
            observer,
            name: CompanionSharedSettingsDarwinRelay.localNotification,
            object: nil
        )
        sharedSettingsObserverToken = nil
    }

    private func reloadSharedSettingsFromSharedDefaults() {
        KeyboardSharedPreferences.sync()
        let snapshot = KeyboardSettingsSnapshot.load()
        apply(snapshot: snapshot, persist: false)
    }

    private func apply(keymap: KeyboardKeymap, preset: KeyboardLayoutPreset) {
        isApplyingSnapshot = true

        layoutPreset = preset
        layoutLocale = .enUS
        runtimeLayoutRoute = preset == .custom ? .storedKeymap : .runtimeLocale
        keyDimensionOverrides = keymap.keyDimensionOverrides
        keymapRows = keymap.rows
        quickInsertRow = normalizedRow(keymap.quickInsertRow, row: .quickInsert)
        holdQuickInsertRow = normalizedRow(keymap.holdQuickInsertRow, row: .holdQuickInsert)
        toolbarRow = normalizedRow(keymap.toolbarRow, row: .toolbar)
        holdToolbarRow = normalizedRow(keymap.holdToolbarRow, row: .holdToolbar)
        symbolUtilityRow = normalizedRow(keymap.symbolUtilityRow, row: .symbolUtility)
        symbolTopRow = normalizedRow(keymap.symbolTopRow, row: .symbolTop)
        holdSymbolTopRow = normalizedRow(keymap.holdSymbolTopRow, row: .holdSymbolTop)
        symbolMiddleRow = normalizedRow(keymap.symbolMiddleRow, row: .symbolMiddle)
        holdSymbolMiddleRow = normalizedRow(keymap.holdSymbolMiddleRow, row: .holdSymbolMiddle)
        symbolBottomRow = normalizedRow(keymap.symbolBottomRow, row: .symbolBottom)
        holdSymbolBottomRow = normalizedRow(keymap.holdSymbolBottomRow, row: .holdSymbolBottom)
        trailingUtilityRow = normalizedRow(keymap.trailingUtilityRow, row: .trailingUtility)
        expandedTrailingUtilityRow = normalizedRow(
            keymap.expandedTrailingUtilityRow,
            row: .expandedTrailingUtility
        )
        expandedLetterTrailingUtilityRow = normalizedRow(
            keymap.expandedLetterTrailingUtilityRow,
            row: .expandedLetterTrailingUtility
        )
        letterUtilityRow = normalizedRow(keymap.letterUtilityRow, row: .letterUtility)
        letterBottomLeadingRow = normalizedRow(keymap.letterBottomLeadingRow, row: .letterBottomLeading)
        letterTopRow = normalizedRow(keymap.letterTopRow, row: .letterTop)
        holdLetterTopRow = normalizedRow(keymap.holdLetterTopRow, row: .holdLetterTop)
        letterMiddleRow = normalizedRow(keymap.letterMiddleRow, row: .letterMiddle)
        holdLetterMiddleRow = normalizedRow(keymap.holdLetterMiddleRow, row: .holdLetterMiddle)
        letterBottomRow = normalizedRow(keymap.letterBottomRow, row: .letterBottom)
        holdLetterBottomRow = normalizedRow(keymap.holdLetterBottomRow, row: .holdLetterBottom)
        customKeymapLayers = keymap.customLayers

        isApplyingSnapshot = false
        persistCurrentSnapshot()
    }

    private func applyLayoutPreset(_ preset: KeyboardLayoutPreset) {
        let presetKeymap = KeyboardKeymap.preset(preset)
        var nextSnapshot = snapshot

        nextSnapshot.layoutPreset = preset
        nextSnapshot.layoutLocale = .enUS
        nextSnapshot.runtimeLayoutRoute = .runtimeLocale
        nextSnapshot.keymap = KeyboardKeymap(
            quickInsertRow: normalizedRow(nextSnapshot.keymap.quickInsertRow, row: .quickInsert),
            holdQuickInsertRow: normalizedRow(nextSnapshot.keymap.holdQuickInsertRow, row: .holdQuickInsert),
            toolbarRow: normalizedRow(presetKeymap.toolbarRow, row: .toolbar),
            holdToolbarRow: normalizedRow(nextSnapshot.keymap.holdToolbarRow, row: .holdToolbar),
            symbolTopRow: normalizedRow(presetKeymap.symbolTopRow, row: .symbolTop),
            holdSymbolTopRow: normalizedRow(presetKeymap.holdSymbolTopRow, row: .holdSymbolTop),
            symbolMiddleRow: normalizedRow(presetKeymap.symbolMiddleRow, row: .symbolMiddle),
            holdSymbolMiddleRow: normalizedRow(presetKeymap.holdSymbolMiddleRow, row: .holdSymbolMiddle),
            symbolBottomRow: normalizedRow(presetKeymap.symbolBottomRow, row: .symbolBottom),
            holdSymbolBottomRow: normalizedRow(presetKeymap.holdSymbolBottomRow, row: .holdSymbolBottom),
            letterTopRow: normalizedRow(presetKeymap.letterTopRow, row: .letterTop),
            holdLetterTopRow: normalizedRow(nextSnapshot.keymap.holdLetterTopRow, row: .holdLetterTop),
            letterMiddleRow: normalizedRow(presetKeymap.letterMiddleRow, row: .letterMiddle),
            holdLetterMiddleRow: normalizedRow(
                nextSnapshot.keymap.holdLetterMiddleRow,
                row: .holdLetterMiddle
            ),
            letterBottomRow: normalizedRow(presetKeymap.letterBottomRow, row: .letterBottom),
            holdLetterBottomRow: normalizedRow(
                nextSnapshot.keymap.holdLetterBottomRow,
                row: .holdLetterBottom
            ),
            symbolUtilityRow: normalizedRow(presetKeymap.symbolUtilityRow, row: .symbolUtility),
            letterUtilityRow: normalizedRow(nextSnapshot.keymap.letterUtilityRow, row: .letterUtility),
            trailingUtilityRow: normalizedRow(nextSnapshot.keymap.trailingUtilityRow, row: .trailingUtility),
            expandedTrailingUtilityRow: normalizedRow(
                nextSnapshot.keymap.expandedTrailingUtilityRow,
                row: .expandedTrailingUtility
            ),
            expandedLetterTrailingUtilityRow: normalizedRow(
                nextSnapshot.keymap.expandedLetterTrailingUtilityRow,
                row: .expandedLetterTrailingUtility
            ),
            letterBottomLeadingRow: normalizedRow(
                nextSnapshot.keymap.letterBottomLeadingRow,
                row: .letterBottomLeading
            ),
            customLayers: nextSnapshot.keymap.customLayers
        )

        apply(snapshot: nextSnapshot)
    }

    private func resizeRowsForCountChange() {
        guard !isApplyingSnapshot else { return }

        isApplyingSnapshot = true
        toolbarKeyCount = KeyboardLayoutBounds.clampedToolbarCount(toolbarKeyCount)
        capsHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(capsHoldDurationMs)
        menuHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(menuHoldDurationMs)
        keyHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(keyHoldDurationMs)
        rolodexSelectHoldDurationMs = KeyboardLayoutBounds.clampedRolodexSelectHoldDurationMs(
            rolodexSelectHoldDurationMs
        )
        menuTapLockWindowMs = KeyboardLayoutBounds.clampedMenuTapLockWindowMs(menuTapLockWindowMs)
        deleteHoldWordsBeforeSentence = KeyboardLayoutBounds.clampedDeleteHoldWordCount(
            deleteHoldWordsBeforeSentence
        )
        symbolTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount)
        symbolMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolMiddleRowKeyCount)
        symbolBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolBottomRowKeyCount)
        letterTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount)
        letterMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterMiddleRowKeyCount)
        letterBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterBottomRowKeyCount)
        quickInsertRow = normalizedRow(quickInsertRow, row: .quickInsert, trimmingToVisibleCount: true)
        holdQuickInsertRow = normalizedRow(holdQuickInsertRow, row: .holdQuickInsert, trimmingToVisibleCount: true)
        toolbarRow = normalizedRow(toolbarRow, row: .toolbar, trimmingToVisibleCount: true)
        holdToolbarRow = normalizedRow(holdToolbarRow, row: .holdToolbar, trimmingToVisibleCount: true)
        symbolTopRow = normalizedRow(symbolTopRow, row: .symbolTop, trimmingToVisibleCount: true)
        holdSymbolTopRow = normalizedRow(holdSymbolTopRow, row: .holdSymbolTop, trimmingToVisibleCount: true)
        symbolMiddleRow = normalizedRow(symbolMiddleRow, row: .symbolMiddle, trimmingToVisibleCount: true)
        holdSymbolMiddleRow = normalizedRow(holdSymbolMiddleRow, row: .holdSymbolMiddle, trimmingToVisibleCount: true)
        symbolBottomRow = normalizedRow(symbolBottomRow, row: .symbolBottom, trimmingToVisibleCount: true)
        holdSymbolBottomRow = normalizedRow(holdSymbolBottomRow, row: .holdSymbolBottom, trimmingToVisibleCount: true)
        symbolUtilityRow = normalizedRow(symbolUtilityRow, row: .symbolUtility, trimmingToVisibleCount: true)
        trailingUtilityRow = normalizedRow(trailingUtilityRow, row: .trailingUtility, trimmingToVisibleCount: true)
        expandedTrailingUtilityRow = normalizedRow(
            expandedTrailingUtilityRow,
            row: .expandedTrailingUtility,
            trimmingToVisibleCount: true
        )
        expandedLetterTrailingUtilityRow = normalizedRow(
            expandedLetterTrailingUtilityRow,
            row: .expandedLetterTrailingUtility,
            trimmingToVisibleCount: true
        )
        letterUtilityRow = normalizedRow(letterUtilityRow, row: .letterUtility, trimmingToVisibleCount: true)
        letterBottomLeadingRow = normalizedRow(letterBottomLeadingRow, row: .letterBottomLeading, trimmingToVisibleCount: true)
        letterTopRow = normalizedRow(letterTopRow, row: .letterTop, trimmingToVisibleCount: true)
        holdLetterTopRow = normalizedRow(holdLetterTopRow, row: .holdLetterTop, trimmingToVisibleCount: true)
        letterMiddleRow = normalizedRow(letterMiddleRow, row: .letterMiddle, trimmingToVisibleCount: true)
        holdLetterMiddleRow = normalizedRow(holdLetterMiddleRow, row: .holdLetterMiddle, trimmingToVisibleCount: true)
        letterBottomRow = normalizedRow(letterBottomRow, row: .letterBottom, trimmingToVisibleCount: true)
        holdLetterBottomRow = normalizedRow(holdLetterBottomRow, row: .holdLetterBottom, trimmingToVisibleCount: true)
        var resizedKeymap = KeyboardKeymap(
            quickInsertRow: quickInsertRow,
            holdQuickInsertRow: holdQuickInsertRow,
            toolbarRow: toolbarRow,
            holdToolbarRow: holdToolbarRow,
            symbolTopRow: symbolTopRow,
            holdSymbolTopRow: holdSymbolTopRow,
            symbolMiddleRow: symbolMiddleRow,
            holdSymbolMiddleRow: holdSymbolMiddleRow,
            symbolBottomRow: symbolBottomRow,
            holdSymbolBottomRow: holdSymbolBottomRow,
            letterTopRow: letterTopRow,
            holdLetterTopRow: holdLetterTopRow,
            letterMiddleRow: letterMiddleRow,
            holdLetterMiddleRow: holdLetterMiddleRow,
            letterBottomRow: letterBottomRow,
            holdLetterBottomRow: holdLetterBottomRow,
            symbolUtilityRow: symbolUtilityRow,
            letterUtilityRow: letterUtilityRow,
            trailingUtilityRow: trailingUtilityRow,
            expandedTrailingUtilityRow: expandedTrailingUtilityRow,
            expandedLetterTrailingUtilityRow: expandedLetterTrailingUtilityRow,
            letterBottomLeadingRow: letterBottomLeadingRow,
            customAddedRows: customRowsForLegacyRebuild,
            customLayers: customKeymapLayers,
            keyDimensionOverrides: keyDimensionOverrides
        )
        resizedKeymap.replaceRows(rowsResizedForCurrentCounts(resizedKeymap.rows))
        keymapRows = resizedKeymap.rows
        layoutPreset = .custom
        runtimeLayoutRoute = .storedKeymap
        isApplyingSnapshot = false
        persistCurrentSnapshot()
    }

    private struct MainRowKey: Hashable {
        let surface: KeyboardRowSurface
        let holdLayer: Bool
        let kind: KeyboardRowKind
    }

    private func rowsResizedForCurrentCounts(_ rows: [KeyboardLayoutRow]) -> [KeyboardLayoutRow] {
        var mainRowIndexes: [MainRowKey: Int] = [:]
        return rows.map { row in
            let targetCount = max(1, slotCount(for: row, mainRowIndex: mainRowIndex(for: row, indexes: &mainRowIndexes)))
            guard row.keys.count != targetCount else { return row }

            var nextRow = row
            if row.keys.count > targetCount {
                for key in row.keys.suffix(from: targetCount) {
                    keyDimensionOverrides.removeValue(
                        forKey: KeyboardLayoutDimensionKey.customKey(rowID: row.id, keyID: key.id)
                    )
                }
                nextRow.keys.removeLast(row.keys.count - targetCount)
            } else {
                nextRow.keys.reserveCapacity(targetCount)
                for _ in row.keys.count..<targetCount {
                    nextRow.keys.append(KeyboardLayoutKey(tap: ""))
                }
            }
            return nextRow
        }
    }

    private func mainRowIndex(for row: KeyboardLayoutRow, indexes: inout [MainRowKey: Int]) -> Int? {
        switch row.kind {
        case .symbolMain, .symbolHold, .letterMain, .letterHold:
            let key = MainRowKey(surface: row.surface, holdLayer: row.holdLayer, kind: row.kind)
            let index = indexes[key, default: 0]
            indexes[key] = index + 1
            return index
        default:
            return nil
        }
    }

    private func slotCount(for row: KeyboardLayoutRow, mainRowIndex: Int?) -> Int {
        switch row.kind {
        case .symbolMain, .symbolHold:
            switch mainRowIndex {
            case 1:
                return KeyboardLayoutBounds.clampedExpandedCount(symbolMiddleRowKeyCount)
            case 2:
                return KeyboardLayoutBounds.clampedExpandedCount(symbolBottomRowKeyCount)
            default:
                return KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount)
            }
        case .letterMain, .letterHold:
            switch mainRowIndex {
            case 1:
                return KeyboardLayoutBounds.clampedExpandedCount(letterMiddleRowKeyCount)
            case 2:
                return KeyboardLayoutBounds.clampedExpandedCount(letterBottomRowKeyCount)
            default:
                return KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount)
            }
        default:
            return slotCount(for: row.kind)
        }
    }

    private func setRow(_ row: KeyboardRowKind, values: [String], markCustom: Bool) {
        setRows([(row, values)], markCustom: markCustom)
    }

    private func setRows(_ rowUpdates: [(KeyboardRowKind, [String])], markCustom: Bool) {
        isApplyingSnapshot = true
        for (row, values) in rowUpdates {
            assignNormalizedRow(normalizedRow(values, row: row), to: row)
        }
        if markCustom {
            layoutPreset = .custom
            runtimeLayoutRoute = .storedKeymap
        }
        keymapRows = KeyboardKeymap(
            quickInsertRow: quickInsertRow,
            holdQuickInsertRow: holdQuickInsertRow,
            toolbarRow: toolbarRow,
            holdToolbarRow: holdToolbarRow,
            symbolTopRow: symbolTopRow,
            holdSymbolTopRow: holdSymbolTopRow,
            symbolMiddleRow: symbolMiddleRow,
            holdSymbolMiddleRow: holdSymbolMiddleRow,
            symbolBottomRow: symbolBottomRow,
            holdSymbolBottomRow: holdSymbolBottomRow,
            letterTopRow: letterTopRow,
            holdLetterTopRow: holdLetterTopRow,
            letterMiddleRow: letterMiddleRow,
            holdLetterMiddleRow: holdLetterMiddleRow,
            letterBottomRow: letterBottomRow,
            holdLetterBottomRow: holdLetterBottomRow,
            symbolUtilityRow: symbolUtilityRow,
            letterUtilityRow: letterUtilityRow,
            trailingUtilityRow: trailingUtilityRow,
            expandedTrailingUtilityRow: expandedTrailingUtilityRow,
            expandedLetterTrailingUtilityRow: expandedLetterTrailingUtilityRow,
            letterBottomLeadingRow: letterBottomLeadingRow,
            customAddedRows: customRowsForLegacyRebuild,
            customLayers: customKeymapLayers,
            keyDimensionOverrides: keyDimensionOverrides
        ).rows
        isApplyingSnapshot = false
        persistCurrentSnapshot()
    }

    private func modeMirrorRows(for row: KeyboardRowKind) -> (tap: KeyboardRowKind, hold: KeyboardRowKind)? {
        let tapRow = row.tapVariant
        let holdRow = tapRow.holdVariant
        guard tapRow.supportsHoldCustomization, holdRow != tapRow else { return nil }
        return (tapRow, holdRow)
    }

    private func mirrorsModeKey(_ value: String) -> Bool {
        let normalized = normalizedKey(value)
        if normalized.hasPrefix(KeyboardCustomLayer.storageTokenPrefix) {
            return true
        }

        switch KeyboardSpecialKeyAction.resolved(from: normalized) {
        case .some(.menu), .some(.toggleLayer):
            return true
        default:
            return false
        }
    }

    private func setKeyDimensions(
        _ dimensions: KeyboardLayoutKeyDimensions,
        for row: KeyboardRowKind,
        index: Int
    ) {
        let surface = dimensionSurface(for: row)
        let kind = dimensionKind(for: row)
        var nextKeymap = keymap
        nextKeymap.setLegacyKeyDimensions(
            surface: surface,
            kind: kind,
            holdLayer: false,
            slotIndex: index,
            dimensions: dimensions
        )
        if let layoutRow = nextKeymap.rows.first(where: {
            $0.surface == surface && $0.kind == kind && !$0.holdLayer
        }), layoutRow.keys.indices.contains(index) {
            let key = layoutRow.keys[index]
            nextKeymap.setKeyDimensions(
                rowID: layoutRow.id,
                keyID: key.id,
                widthWeight: dimensions.widthWeight,
                heightOverride: dimensions.heightOverride
            )
        }

        applyDynamicKeymap(nextKeymap)
    }

    private func updateKeymapTableKeyDimensions(
        rowID: UUID,
        keyID: UUID,
        dimensions: KeyboardLayoutKeyDimensions
    ) {
        var nextKeymap = keymap
        guard nextKeymap.rows.contains(where: { row in
            row.id == rowID && row.keys.contains(where: { $0.id == keyID })
        }) else {
            return
        }
        nextKeymap.setKeyDimensions(
            rowID: rowID,
            keyID: keyID,
            widthWeight: dimensions.widthWeight,
            heightOverride: dimensions.heightOverride
        )
        nextKeymap.setCustomKeyDimensions(rowID: rowID, keyID: keyID, dimensions: dimensions)
        applyDynamicKeymap(nextKeymap)
    }

    private static func isEditableTableRow(_ kind: KeyboardRowKind, surface: KeyboardRowSurface) -> Bool {
        switch (surface, kind.tapVariant) {
        case (.mainRow, .toolbar), (.mainRow, .trailingUtility):
            return true
        case (.symbols1, .symbolTop), (.symbols1, .symbolMiddle), (.symbols1, .symbolBottom), (.symbols1, .symbolMain),
             (.symbols2, .symbolTop), (.symbols2, .symbolMiddle), (.symbols2, .symbolBottom), (.symbols2, .symbolMain):
            return true
        case (.letters, .letterTop), (.letters, .letterMiddle), (.letters, .letterBottom), (.letters, .letterMain):
            return true
        default:
            return false
        }
    }

    private func applyDynamicRows(_ rows: [KeyboardLayoutRow]) {
        var nextKeymap = keymap
        nextKeymap.replaceRows(rows)
        applyDynamicKeymap(nextKeymap)
    }

    private func applyDynamicKeymap(_ nextKeymap: KeyboardKeymap, syncICloud: Bool = true) {
        isApplyingSnapshot = true

        layoutPreset = .custom
        runtimeLayoutRoute = .storedKeymap
        keyDimensionOverrides = nextKeymap.keyDimensionOverrides
        customKeymapLayers = nextKeymap.customLayers
        keymapRows = nextKeymap.rows
        quickInsertRow = normalizedRow(nextKeymap.quickInsertRow, row: .quickInsert)
        holdQuickInsertRow = normalizedRow(nextKeymap.holdQuickInsertRow, row: .holdQuickInsert)
        toolbarRow = normalizedRow(nextKeymap.toolbarRow, row: .toolbar)
        holdToolbarRow = normalizedRow(nextKeymap.holdToolbarRow, row: .holdToolbar)
        symbolUtilityRow = normalizedRow(nextKeymap.symbolUtilityRow, row: .symbolUtility)
        symbolTopRow = normalizedRow(nextKeymap.symbolTopRow, row: .symbolTop)
        holdSymbolTopRow = normalizedRow(nextKeymap.holdSymbolTopRow, row: .holdSymbolTop)
        symbolMiddleRow = normalizedRow(nextKeymap.symbolMiddleRow, row: .symbolMiddle)
        holdSymbolMiddleRow = normalizedRow(nextKeymap.holdSymbolMiddleRow, row: .holdSymbolMiddle)
        symbolBottomRow = normalizedRow(nextKeymap.symbolBottomRow, row: .symbolBottom)
        holdSymbolBottomRow = normalizedRow(nextKeymap.holdSymbolBottomRow, row: .holdSymbolBottom)
        trailingUtilityRow = normalizedRow(nextKeymap.trailingUtilityRow, row: .trailingUtility)
        expandedTrailingUtilityRow = normalizedRow(
            nextKeymap.expandedTrailingUtilityRow,
            row: .expandedTrailingUtility
        )
        expandedLetterTrailingUtilityRow = normalizedRow(
            nextKeymap.expandedLetterTrailingUtilityRow,
            row: .expandedLetterTrailingUtility
        )
        letterUtilityRow = normalizedRow(nextKeymap.letterUtilityRow, row: .letterUtility)
        letterBottomLeadingRow = normalizedRow(nextKeymap.letterBottomLeadingRow, row: .letterBottomLeading)
        letterTopRow = normalizedRow(nextKeymap.letterTopRow, row: .letterTop)
        holdLetterTopRow = normalizedRow(nextKeymap.holdLetterTopRow, row: .holdLetterTop)
        letterMiddleRow = normalizedRow(nextKeymap.letterMiddleRow, row: .letterMiddle)
        holdLetterMiddleRow = normalizedRow(nextKeymap.holdLetterMiddleRow, row: .holdLetterMiddle)
        letterBottomRow = normalizedRow(nextKeymap.letterBottomRow, row: .letterBottom)
        holdLetterBottomRow = normalizedRow(nextKeymap.holdLetterBottomRow, row: .holdLetterBottom)

        isApplyingSnapshot = false
        persistCurrentSnapshot(syncICloud: syncICloud)
    }

    private func dimensionSurface(for row: KeyboardRowKind) -> KeyboardRowSurface {
        switch row {
        case .quickInsert, .toolbar, .trailingUtility:
            return .mainRow
        case .symbolUtility, .symbolTop, .symbolMiddle, .symbolBottom,
             .expandedTrailingUtility, .symbolMain:
            return .symbols1
        case .letterUtility, .letterBottomLeading, .letterTop, .letterMiddle, .letterBottom,
             .expandedLetterTrailingUtility, .letterMain:
            return .letters
        case .holdQuickInsert, .holdToolbar, .holdSymbolTop, .holdSymbolMiddle, .holdSymbolBottom,
             .holdLetterTop, .holdLetterMiddle, .holdLetterBottom, .symbolHold, .letterHold:
            return dimensionSurface(for: row.tapVariant)
        }
    }

    private func dimensionKind(for row: KeyboardRowKind) -> KeyboardRowKind {
        switch row {
        case .expandedTrailingUtility, .expandedLetterTrailingUtility:
            return row
        default:
            return row.tapVariant
        }
    }

    private func assignNormalizedRow(_ normalized: [String], to row: KeyboardRowKind) {
        switch row {
        case .quickInsert:
            quickInsertRow = normalized
        case .holdQuickInsert:
            holdQuickInsertRow = normalized
        case .toolbar:
            toolbarRow = normalized
        case .holdToolbar:
            holdToolbarRow = normalized
        case .symbolUtility:
            symbolUtilityRow = normalized
        case .symbolTop:
            symbolTopRow = normalized
        case .holdSymbolTop:
            holdSymbolTopRow = normalized
        case .symbolMiddle:
            symbolMiddleRow = normalized
        case .holdSymbolMiddle:
            holdSymbolMiddleRow = normalized
        case .symbolBottom:
            symbolBottomRow = normalized
        case .holdSymbolBottom:
            holdSymbolBottomRow = normalized
        case .symbolMain:
            symbolTopRow = normalized
        case .symbolHold:
            holdSymbolTopRow = normalized
        case .trailingUtility:
            trailingUtilityRow = normalized
        case .expandedTrailingUtility:
            expandedTrailingUtilityRow = normalized
        case .expandedLetterTrailingUtility:
            expandedLetterTrailingUtilityRow = normalized
        case .letterUtility:
            letterUtilityRow = normalized
        case .letterBottomLeading:
            letterBottomLeadingRow = normalized
        case .letterTop:
            letterTopRow = normalized
        case .holdLetterTop:
            holdLetterTopRow = normalized
        case .letterMiddle:
            letterMiddleRow = normalized
        case .holdLetterMiddle:
            holdLetterMiddleRow = normalized
        case .letterBottom:
            letterBottomRow = normalized
        case .holdLetterBottom:
            holdLetterBottomRow = normalized
        case .letterMain:
            letterTopRow = normalized
        case .letterHold:
            holdLetterTopRow = normalized
        }
    }

    private func save() {
        guard !isApplyingSnapshot else { return }
        persistCurrentSnapshot()
    }

    func applyTransaction(_ update: (CompanionSettingsStore) -> Void) {
        if isApplyingSnapshot {
            update(self)
            return
        }

        isApplyingSnapshot = true
        update(self)
        isApplyingSnapshot = false
        persistCurrentSnapshot()
    }

    private func saveKeymap() {
        guard !isApplyingSnapshot else { return }
        if layoutPreset != .custom {
            isApplyingSnapshot = true
            layoutPreset = .custom
            runtimeLayoutRoute = .storedKeymap
            isApplyingSnapshot = false
        }
        persistCurrentSnapshot()
    }

    private func persistCurrentSnapshot(syncICloud: Bool = true) {
        let currentSnapshot = snapshot
        currentSnapshot.persist()
        if syncICloud {
            NotificationCenter.default.post(
                name: .hwcCloudSnapshotSourceDidChange,
                object: nil
            )
        }
    }

    private func normalizedRow(
        _ values: [String],
        row: KeyboardRowKind,
        trimmingToVisibleCount: Bool = false
    ) -> [String] {
        var normalized = values.map(normalizedKey)
        let visibleCount = slotCount(for: row)
        let maxCount = maxSlotCount(for: row)
        let retainedCount = trimmingToVisibleCount ? min(visibleCount, maxCount) : maxCount

        if normalized.count > retainedCount {
            normalized = Array(normalized.prefix(retainedCount))
        }

        while normalized.count < visibleCount {
            normalized.append("")
        }
        return normalized
    }

    private func maxSlotCount(for row: KeyboardRowKind) -> Int {
        switch row {
        case .quickInsert, .holdQuickInsert:
            return KeyboardKeymap.defaultQuickInsertRow.count
        case .toolbar, .holdToolbar:
            return KeyboardLayoutBounds.toolbarCountRange.upperBound
        case .symbolUtility:
            return KeyboardKeymap.defaultSymbolUtilityRow.count
        case .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility:
            return KeyboardKeymap.defaultTrailingUtilityRow.count
        case .letterUtility:
            return KeyboardKeymap.defaultLetterUtilityRow.count
        case .letterBottomLeading:
            return KeyboardKeymap.defaultLetterBottomLeadingRow.count
        case .symbolTop, .holdSymbolTop, .symbolMiddle, .holdSymbolMiddle, .symbolBottom, .holdSymbolBottom,
             .symbolMain, .symbolHold,
             .letterTop, .holdLetterTop, .letterMiddle, .holdLetterMiddle, .letterBottom, .holdLetterBottom,
             .letterMain, .letterHold:
            return KeyboardLayoutBounds.expandedCountRange.upperBound
        }
    }

    private func normalizedKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(KeyboardCustomLayer.storageTokenPrefix) {
            return trimmed
        }
        if let specialAction = KeyboardSpecialKeyAction.resolved(from: trimmed) {
            return specialAction.storageToken
        }
        return String(trimmed.prefix(KeyboardLayoutBounds.maximumCustomKeyTextLength))
    }

    private func values(for row: KeyboardRowKind, from keymap: KeyboardKeymap) -> [String] {
        switch row {
        case .quickInsert:
            return keymap.quickInsertRow
        case .holdQuickInsert:
            return keymap.holdQuickInsertRow
        case .toolbar:
            return keymap.toolbarRow
        case .holdToolbar:
            return keymap.holdToolbarRow
        case .symbolUtility:
            return keymap.symbolUtilityRow
        case .symbolTop:
            return keymap.symbolTopRow
        case .holdSymbolTop:
            return keymap.holdSymbolTopRow
        case .symbolMiddle:
            return keymap.symbolMiddleRow
        case .holdSymbolMiddle:
            return keymap.holdSymbolMiddleRow
        case .symbolBottom:
            return keymap.symbolBottomRow
        case .holdSymbolBottom:
            return keymap.holdSymbolBottomRow
        case .symbolMain:
            return keymap.symbolTopRow
        case .symbolHold:
            return keymap.holdSymbolTopRow
        case .trailingUtility:
            return keymap.trailingUtilityRow
        case .expandedTrailingUtility:
            return keymap.expandedTrailingUtilityRow
        case .expandedLetterTrailingUtility:
            return keymap.expandedLetterTrailingUtilityRow
        case .letterUtility:
            return keymap.letterUtilityRow
        case .letterBottomLeading:
            return keymap.letterBottomLeadingRow
        case .letterTop:
            return keymap.letterTopRow
        case .holdLetterTop:
            return keymap.holdLetterTopRow
        case .letterMiddle:
            return keymap.letterMiddleRow
        case .holdLetterMiddle:
            return keymap.holdLetterMiddleRow
        case .letterBottom:
            return keymap.letterBottomRow
        case .holdLetterBottom:
            return keymap.holdLetterBottomRow
        case .letterMain:
            return keymap.letterTopRow
        case .letterHold:
            return keymap.holdLetterTopRow
        }
    }

    private var isKeyboardRecentlySeen: Bool {
        guard let keyboardLastSeenAt else {
            return false
        }

        return Date().timeIntervalSince(keyboardLastSeenAt) < 600
    }

    private var isLiveSyncVerified: Bool {
        sharedContainerAvailable && isKeyboardRecentlySeen
    }

    private var isKeyboardFullAccessRecentlyConfirmed: Bool {
        guard let state = KeyboardSharedPreferences.keyboardFullAccessState(),
              state.isEnabled else {
            return false
        }
        return Date().timeIntervalSince(state.checkedAt) < 600
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func localDate(for key: String) -> Date? {
        guard let timestamp = UserDefaults.standard.object(forKey: key) as? Double else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }
}
