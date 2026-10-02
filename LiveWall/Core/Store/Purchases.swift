import Observation
import StoreKit
import SwiftUI

/// In-app purchases through StoreKit 2. Apple keeps the record, so a purchase comes back on any device
/// signed in to the same Apple Account, with no account of our own.
@Observable
final class Purchases {
    static let unlimitedConversionsID = "dev.distinction.livewall.convert.unlimited"

    private(set) var unlimitedConversions: Product?
    private(set) var ownsUnlimitedConversions = false
    private(set) var isPurchasing = false
    var message: String?

    @ObservationIgnored private let conversions: ConversionAllowance
    @ObservationIgnored private var updates: Task<Void, Never>?

    init(conversions: ConversionAllowance) {
        self.conversions = conversions
        // Purchases that finish outside the app (Ask to Buy, another device, a refund) arrive here.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
    }

    /// "Unlock Unlimited · ₹199", or without the price until the App Store has answered.
    var unlockTitle: String {
        unlimitedConversions.map { "Unlock Unlimited · \($0.displayPrice)" } ?? "Unlock Unlimited"
    }

    func load() async {
        await refreshEntitlements()
        unlimitedConversions = try? await Product.products(for: [Self.unlimitedConversionsID]).first
    }

    /// Returns whether Convert is now unlocked; false when the person cancelled or the purchase awaits approval.
    func buyUnlimitedConversions() async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        if unlimitedConversions == nil { await load() }
        guard let product = unlimitedConversions else {
            message = "The App Store isn't available right now. Try again in a moment."
            return false
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "The App Store couldn't confirm this purchase."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return ownsUnlimitedConversions
            case .pending:
                message = "Your purchase is waiting for approval. Convert unlocks as soon as it's approved."
                return false
            default:
                return false
            }
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = ownsUnlimitedConversions
                ? "Unlimited conversions are unlocked."
                : "No purchases were found for this Apple Account."
        } catch StoreKitError.userCancelled {
            return
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var owns = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.productID == Self.unlimitedConversionsID {
                owns = true
            }
        }
        ownsUnlimitedConversions = owns
        conversions.isUnlocked = owns
    }
}

extension View {
    /// What a purchase or restore needs the person to know. A sheet needs its own, since an alert can't show above one.
    func purchaseMessages(_ purchases: Purchases) -> some View {
        alert("App Store", isPresented: .constant(purchases.message != nil)) {
            Button("OK") { purchases.message = nil }
        } message: {
            Text(purchases.message ?? "")
        }
    }
}
