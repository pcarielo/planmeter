import Foundation

struct ProviderRefreshState {
    let provider:String
    let message:String?
    let busy:Bool
    static func summary(_ states:[Self],selected:Set<String>)->String {
        let active=states.filter {selected.contains($0.provider)}
        if active.contains(where:{$0.busy}) {return "Atualizando dados…"}
        return active.compactMap(\.message).filter{!$0.isEmpty}.joined(separator:" · ")
    }
}
func runProviderRefreshTests() {
    let states=[ProviderRefreshState(provider:"kimi",message:"Kimi: acesso não autorizado",busy:true),ProviderRefreshState(provider:"claude",message:"Claude: leitura concluída",busy:false),ProviderRefreshState(provider:"grok",message:"Grok: coleta concluída",busy:false)]
    guard ProviderRefreshState.summary(states,selected:["codex","grok"])=="Grok: coleta concluída",
          ProviderRefreshState.summary(states,selected:[]).isEmpty,
          ProviderRefreshState.summary(states,selected:["kimi"])=="Atualizando dados…" else{fatalError("FAIL selected provider status")}
    print("PASS provider status: inactive errors, inactive busy and empty selection ignored")
}
