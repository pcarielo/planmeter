import Foundation

final class InsightController {
    var onChange:()->Void={}
    private(set) var preferences=InsightPreferences()
    private(set) var executable:String?
    private(set) var models:[String]=[]
    private(set) var connected=false
    private(set) var busy=false
    private(set) var message="Escolha um modelo e verifique a conexão em Configurações."
    private(set) var text:String?
    private(set) var generatedAt:Date?
    private var basis:[UsageProjection]=[]
    private var modelClient:AppServerClient?
    private var worker:InsightRunner?
    private var generation=0
    private var nextGeneration=Date.distantPast
    func configure(_ value:InsightPreferences,discovery:HarnessDiscovery) {
        let path=discovery.resolve(value.harness,override:value.executablePath)
        guard value != preferences || path != executable else{return}
        let catalogChanged=value.provider != preferences.provider || value.harness != preferences.harness || path != executable
        cancel();preferences=value;executable=path;connected=false;text=nil;generatedAt=nil;basis=[]
        if catalogChanged {models=InsightModelCatalog.environmentModels(provider:value.provider,environment:ProcessInfo.processInfo.environment)
        if value.harness == .claude && value.provider == "claude" {models += ["sonnet","opus"]}}
        message=path==nil ? "Harness não encontrado. Informe o caminho nas Configurações." : "Verifique a conexão do modelo escolhido.";onChange()
    }
    func cancel(){let wasBusy=busy;generation += 1;modelClient?.cancel();modelClient=nil;worker?.cancel();worker=nil;busy=false;if wasBusy {message="Geração cancelada.";onChange()}}
    func isStale(current:[UsageProjection],now:Date=Date())->Bool {
        guard let date=generatedAt else{return false}
        return InsightBasis.isStale(generatedAt:date,basis:basis,current:current,now:now)
    }
    func status(current:[UsageProjection],now:Date=Date())->String {
        guard let date=generatedAt else{return message}
        let source="Gerado em "+localDate(date)+" · "+preferences.harness.title+" / "+preferences.model
        return source+"\n"+(isStale(current:current,now:now) ? "Dados mudaram; gere um novo insight. " : "")+message
    }
    func checkConnection(){execute(projections:nil)}
    func discoverModels() {
        guard !Runtime.isTest,!busy else{return}
        guard let path=executable else{message="Harness não encontrado. Confira o caminho nas Configurações.";onChange();return}
        if preferences.harness == .codex {
            guard preferences.provider=="codex" else{message="Use o plano Codex com este harness.";onChange();return}
            busy=true;generation += 1;let token=generation
            let client=AppServerClient(binary:path,purpose:.models);modelClient=client;message="Buscando modelos no Codex…";onChange()
            DispatchQueue.global(qos:.utility).async {[weak self] in
                let result=Result{try client.readModels()}
                DispatchQueue.main.async {
                    guard let self=self,self.generation==token else{return};self.busy=false;self.modelClient=nil
                    switch result {case .success(let models):self.models=models;self.message="Selecione um modelo e verifique a conexão."
                    case .failure:self.message="Não foi possível consultar o catálogo Codex. Confira o login no cliente oficial."}
                    self.onChange()
                }
            }
            return
        }
        guard let request=InsightModelCatalog.request(harness:preferences.harness,executable:path) else{onChange();return}
        let selectedHarness=preferences.harness
        let adapter=InsightAdapter(preferences:preferences,executable:path,inheritedEnvironment:[:])
        guard let provider=(selectedHarness == .opencode ? adapter.openCodeProvider : adapter.piProvider) else{return}
        busy=true;generation += 1;let token=generation;let runner=InsightRunner(timeout:15);worker=runner;message="Buscando modelos no harness…";onChange()
        DispatchQueue.global(qos:.utility).async {[weak self] in
            let result=Result{try runner.run(request)}
            DispatchQueue.main.async {
                guard let self=self,self.generation==token else{return}
                self.busy=false;self.worker=nil
                switch result {
                case .success(let data):self.models=selectedHarness == .kimi ? InsightModelCatalog.kimiModels(data) : selectedHarness == .opencode ? InsightModelCatalog.openCodeModels(data,provider:provider) : InsightModelCatalog.piModels(data,provider:provider);self.message=self.models.isEmpty ? "Nenhum modelo desse plano encontrado no harness." : "Selecione um modelo e verifique a conexão."
                case .failure:self.message="Não foi possível consultar o catálogo local."
                }
                self.onChange()
            }
        }
    }

    func generate(_ projections:[UsageProjection],permitted:Bool) {
        guard !busy else{return}
        guard permitted else{message="Insights estão disponíveis no Pro com um plano conectado.";onChange();return}
        guard !projections.isEmpty else{message="Atualize as quotas para gerar o insight.";onChange();return}
        guard Date()>=nextGeneration else{message="Aguarde um minuto entre gerações.";onChange();return}
        execute(projections:projections)
    }
    private func execute(projections:[UsageProjection]?) {
        guard !Runtime.isTest,!busy else{return}
        guard let path=executable else{message="Harness não encontrado. Confira o caminho nas Configurações.";onChange();return}
        let adapter=InsightAdapter(preferences:preferences,executable:path,inheritedEnvironment:ProcessInfo.processInfo.environment)
        do {_ = try adapter.connectionRequest()}catch{message="A integração escolhida ainda não está disponível ou o modelo não foi informado.";connected=false;onChange();return}
        if projections != nil {nextGeneration=Date().addingTimeInterval(60)}
        busy=true;generation += 1;let token=generation
        let runner=InsightRunner();worker=runner;message=projections==nil ? "Verificando conexão…" : "Gerando insight…";onChange()
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let result:Result<String?,Error>=Result {
                let data=try runner.run(adapter.connectionRequest())
                guard adapter.connected(data) else{throw InsightFailure.unavailable}
                guard let projections=projections else{return nil}
                let response=try runner.run(adapter.generationRequest(prompt:InsightText.prompt(projections)))
                return try adapter.response(response)
            }
            DispatchQueue.main.async {
                guard let self=self,self.generation==token else{return}
                self.busy=false;self.worker=nil
                switch result {
                case .success(let answer):
                    self.connected=true
                    if let answer=answer {self.text=answer;self.generatedAt=Date();self.basis=projections ?? [];self.message="Estimativa baseada nas observações disponíveis dos últimos 7 dias."}
                    else {self.message=[InsightHarness.kimi,.primeAgent,.opencode].contains(adapter.preferences.harness) ? "Configuração encontrada no cliente; a conexão será confirmada na geração." : "Conexão verificada pelo harness."}
                case .failure(let error):self.connected=false;self.message=(error as? InsightFailure)?.message ?? "Não foi possível gerar o insight."
                }
                self.onChange()
            }
        }
    }
}

struct InsightBasis {
    static func isStale(generatedAt:Date,basis:[UsageProjection],current:[UsageProjection],now:Date)->Bool {
        if now.timeIntervalSince(generatedAt)>3600 || basis.contains(where:{$0.resetAt.map{$0<=now.timeIntervalSince1970} ?? false}) {return true}
        return signature(basis) != signature(current)
    }
    static func signature(_ values:[UsageProjection])->[String] {
        values.map {value in
            [value.provider,value.window,String(value.remaining),value.resetAt.map{String($0)} ?? "none",value.percentPerHour.map{String($0)} ?? "none",value.riskBeforeReset.map{String($0)} ?? "none",value.reason ?? "valid",value.periodFirstObservedRemainingPercent.map{String($0)} ?? "none"].joined(separator:"|")
        }.sorted()
    }
}
