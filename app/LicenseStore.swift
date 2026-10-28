import Foundation
import StoreKit

struct LicenseEntitlement {
    static func grantsPro(verified:Bool,productID:String,nonConsumable:Bool,revoked:Bool,upgraded:Bool)->Bool {
        verified && productID==LicenseStore.productID && nonConsumable && !revoked && !upgraded
    }
}
func runLicenseTests() {
    func allowed(_ verified:Bool=true,_ id:String=LicenseStore.productID,_ type:Bool=true,_ revoked:Bool=false,_ upgraded:Bool=false)->Bool {LicenseEntitlement.grantsPro(verified:verified,productID:id,nonConsumable:type,revoked:revoked,upgraded:upgraded)}
    guard allowed(),!allowed(false),!allowed(true,"other"),!allowed(true,LicenseStore.productID,false),!allowed(true,LicenseStore.productID,true,true),!allowed(true,LicenseStore.productID,true,false,true) else{fatalError("FAIL verified entitlement policy")}
    print("PASS License entitlement: verified product/type, revocation and upgrade gates; no Apple purchase")
}

// Entitlement is reconstructed from verified StoreKit transactions, never from preferences.
final class LicenseStore {
    static let productID=Bundle.main.object(forInfoDictionaryKey:"PlanMeterProProductID") as? String ?? "io.github.pcarielo.planmeter.pro"
    private(set) var isPro=false
    private(set) var busy=false
    private(set) var message="Free: até dois planos. Pro libera todos os planos e insights."
    private(set) var price:String?
    private var product:Product?
    private var listener:Task<Void,Never>?
    var onChange:()->Void={}
    func start() {
        guard !Runtime.isTest,listener==nil else{return}
        listener=Task { @MainActor [weak self] in
            await self?.reload()
            for await result in Transaction.updates {
                guard !Task.isCancelled else{return}
                guard case .verified(let transaction)=result,transaction.productID==Self.productID else{continue}
                await transaction.finish();await self?.reload()
            }
        }
    }
    func stop(){listener?.cancel();listener=nil}
    @MainActor private func reload() async {
        var entitled=false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction)=result,LicenseEntitlement.grantsPro(verified:true,productID:transaction.productID,nonConsumable:transaction.productType == .nonConsumable,revoked:transaction.revocationDate != nil,upgraded:transaction.isUpgraded) {entitled=true}
        }
        self.isPro=entitled;self.message=entitled ? "Pro ativo: todos os planos e insights." : "Free: até dois planos.";self.onChange()
        let available=try? await Product.products(for:[Self.productID]).first(where:{$0.type == .nonConsumable})
        await MainActor.run {
            self.isPro=entitled;self.product=available;self.price=available?.displayPrice
            self.message=entitled ? "Pro ativo: todos os planos e insights." : available == nil ? "Free: até dois planos. A compra Pro ainda não está disponível nesta distribuição." : "Free: até dois planos. Pro libera todos os planos e insights."
            self.onChange()
        }
    }
    func purchase() {
        guard !Runtime.isTest,!busy else{return}
        guard let product=product else{message="A compra Pro ainda não está disponível nesta distribuição.";onChange();return}
        busy=true;onChange()
        Task { @MainActor [weak self] in
            guard let self=self else{return}
            var text="Compra não concluída."
            do {
                switch try await product.purchase() {
                case .success(.verified(let transaction)):
                    await transaction.finish();await reload();text=isPro ? "Pro ativo." : "A compra não concedeu acesso Pro."
                case .success(.unverified):text="Não foi possível verificar a compra."
                case .pending:text="Compra aguardando aprovação."
                case .userCancelled:text="Compra cancelada."
                @unknown default:text="Compra não concluída."
                }
            } catch {text="Não foi possível concluir a compra. Tente novamente."}
            await MainActor.run {self.busy=false;self.message=text;self.onChange()}
        }
    }
    func restore() {
        guard !Runtime.isTest,!busy else{return}
        busy=true;onChange()
        Task { @MainActor [weak self] in
            guard let self=self else{return}
            do {try await AppStore.sync();await reload()}
            catch {await MainActor.run {self.message="Não foi possível restaurar as compras."}}
            await MainActor.run {self.busy=false;self.onChange()}
        }
    }
    deinit {listener?.cancel()}
}
