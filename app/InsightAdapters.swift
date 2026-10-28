import Foundation

struct InsightAdapter {
    let preferences:InsightPreferences
    let executable:String
    let inheritedEnvironment:[String:String]
    private var environment:[String:String] {
        var env=InsightRunner.environment(inheritedEnvironment,binary:executable)
        if preferences.harness == .kimi {env["KIMI_DISABLE_TELEMETRY"]="1";env["KIMI_CODE_BACKGROUND_KEEP_ALIVE_ON_EXIT"]="false";env["KIMI_CODE_BACKGROUND_PRINT_BACKGROUND_MODE"]="exit";env["KIMI_LOOP_MAX_STEPS_PER_TURN"]="1"}
        if preferences.harness == .opencode {
            env["XDG_CONFIG_HOME"]="@planmeter:config"
            env["OPENCODE_DISABLE_PROJECT_CONFIG"]="true";env["OPENCODE_DISABLE_AUTOUPDATE"]="true"
            env["OPENCODE_DISABLE_LSP_DOWNLOAD"]="true";env["OPENCODE_DISABLE_PRUNE"]="true"
            env["OPENCODE_CONFIG_CONTENT"]="{\"permission\":{\"*\":\"deny\"},\"instructions\":[],\"plugin\":[],\"mcp\":{},\"share\":\"disabled\"}"
        }
        if preferences.harness == .primeAgent {
            env["PRIME_AGENT_CODING_AGENT_DIR"]=(env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path)+"/.prime/agent"
            env["PRIME_AGENT_TELEMETRY"]="0"
        }
        return env
    }
    var openCodeProvider:String? {switch preferences.provider {case "codex":return "openai";case "claude":return nil;case "kimi":return "kimi-code-plan-global";case "zai":return "zai-coding-plan";default:return nil}}
    private func validOpenCodeModel()->Bool {openCodeProvider.map{preferences.model.hasPrefix($0+"/")} ?? false}

    var piProvider:String? {switch preferences.provider {case "kimi":return "kimi-coding";case "codex":return "openai-codex";case "claude":return nil;case "zai":return "zai";default:return nil}}
    func metadataRequest(arguments:[String])->InsightRequest {
        if preferences.harness == .primeAgent {
            return InsightRequest(executable:executable,arguments:arguments,environment:environment,input:Data(),blockChildExecution:true,writableDirectories:[environment["PRIME_AGENT_CODING_AGENT_DIR"]!])
        }
        return InsightRequest(executable:executable,arguments:arguments,environment:environment,input:Data(),resourceDirectories:preferences.harness == .opencode ? ["config"] : [])
    }
    func validate()throws {
        if [.pi,.primeAgent].contains(preferences.harness),preferences.model.contains("/") {throw InsightFailure.invalidConfiguration}
        guard !preferences.model.isEmpty,preferences.model.count<=120,
              preferences.model.range(of:"^[A-Za-z0-9][A-Za-z0-9._:/-]*$",options:.regularExpression) != nil else{throw InsightFailure.invalidConfiguration}
    }
    func connectionRequest()throws->InsightRequest {
        try validate()
        let arguments:[String]
        switch preferences.harness {
        case .pi:
            guard let provider=piProvider else{throw InsightFailure.invalidConfiguration}
            arguments=["auth","check","--provider",provider,"--model",preferences.model,"--json","--no-refresh"]
        case .claude:
            guard preferences.provider=="claude" else{throw InsightFailure.invalidConfiguration}
            arguments=["auth","status","--json"]
        case .kimi:
            guard preferences.provider=="kimi",preferences.model.hasPrefix("kimi-code/") else{throw InsightFailure.invalidConfiguration}
            arguments=["provider","list"]
        case .primeAgent:
            guard ["kimi","zai"].contains(preferences.provider),piProvider != nil else{throw InsightFailure.invalidConfiguration}
            return metadataRequest(arguments:["--offline","model","list"])
        case .codex:
            guard preferences.provider=="codex" else{throw InsightFailure.invalidConfiguration}
            return InsightRequest(executable:executable,arguments:["login","status"],environment:environment,input:Data(),captureDiagnosticOutput:true)
        case .opencode:
            guard validOpenCodeModel() else{throw InsightFailure.invalidConfiguration}
            return InsightRequest(executable:executable,arguments:["--pure","providers","list"],environment:environment,input:Data(),resourceDirectories:["config"])
        }
        return InsightRequest(executable:executable,arguments:arguments,environment:environment,input:Data())
    }
    func connected(_ data:Data)->Bool {
        if preferences.harness == .primeAgent,let provider=piProvider,let text=String(data:data,encoding:.utf8) {
            return text.components(separatedBy:.newlines).contains {line in
                let parts=line.split(whereSeparator:{$0.isWhitespace}).map(String.init)
                return parts.count>=2 && parts[0]==provider && parts[1]==preferences.model
            }
        }
        if preferences.harness == .codex {
            return String(data:data,encoding:.utf8)?.components(separatedBy:.newlines).contains{$0.trimmingCharacters(in:.whitespaces)=="Logged in using ChatGPT"} == true
        }
        if preferences.harness == .opencode {
            guard let text=String(data:data,encoding:.utf8) else{return false}
            let clean=text.replacingOccurrences(of:"\u{1b}\\[[0-9;]*[A-Za-z]",with:"",options:.regularExpression)
            let label:String
            switch preferences.provider {case "codex":label="OpenAI oauth";case "claude":label="Anthropic oauth";case "kimi":label="Kimi For Coding (kimi.ai) api";case "zai":label="Z.AI Coding Plan api";default:return false}
            return clean.components(separatedBy:.newlines).contains{$0.trimmingCharacters(in:.whitespaces).hasSuffix(label)}
        }
        if preferences.harness == .kimi {
            guard let text=String(data:data,encoding:.utf8) else{return false}
            return text.components(separatedBy:.newlines).contains{$0.hasPrefix("managed:kimi-code ") && $0.contains("source=oauth")}
        }
        guard let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{return false}
        switch preferences.harness {
        case .pi:
            guard value["status"] as? String == "ready",value["provider"] as? String == piProvider,let auth=value["authType"] as? String else{return false}
            if ["claude","codex"].contains(preferences.provider) {return auth=="oauth"}
            return ["oauth","api_key","apiKey"].contains(auth)
        case .claude:
            return value["loggedIn"] as? Bool == true && value["authMethod"] as? String == "claude.ai"
        default:return false
        }
    }
    func generationRequest(prompt:Data)throws->InsightRequest {
        try validate()
        let arguments:[String]
        switch preferences.harness {
        case .pi:
            guard let provider=piProvider else{throw InsightFailure.invalidConfiguration}
            arguments=["--system-prompt","{\"task\":\"Explique o consumo para uma pessoa em português comum, em uma ou duas linhas. Não cite nomes de campos, JSON ou código. Não use ferramentas.\"}","--print","--mode","text","--provider",provider,"--model",preferences.model,"--no-tools","--no-extensions","--no-mcp","--no-skills","--no-context-files","--no-prompt-templates","--no-themes","--no-session","--no-approve","--offline","--thinking","off"]
        case .claude:
            guard preferences.provider=="claude" else{throw InsightFailure.invalidConfiguration}
            arguments=["--system-prompt","{\"task\":\"Explique o consumo em português comum, sem termos internos ou ferramentas, em uma ou duas linhas curtas.\"}","--print","--model",preferences.model,"--output-format","json","--tools","","--permission-mode","dontAsk","--permission-prompts","none","--strict-mcp-config","--mcp-config","{\"mcpServers\":{}}","--setting-sources","","--settings","{\"disableAllHooks\":true}","--no-chrome","--disable-slash-commands","--no-session-persistence"]
        case .kimi:
            guard preferences.provider=="kimi",preferences.model.hasPrefix("kimi-code/"),let json=String(data:prompt,encoding:.utf8) else{throw InsightFailure.invalidConfiguration}
            let agent="---\nname: planmeter-insight\ndescription: Explain aggregate coding plan usage\ntools: []\nsubagents: []\n---\n"+json
            arguments=["--model",preferences.model,"--agent-file","@planmeter:insight-agent.md","--skills-dir","@planmeter:skills","--prompt","{\"task\":\"Execute somente a tarefa JSON definida no sistema; responda sem ferramentas.\"}","--output-format","text"]
            return InsightRequest(executable:executable,arguments:arguments,environment:environment,input:Data(),resources:["insight-agent.md":Data(agent.utf8)],resourceDirectories:["skills"])
        case .primeAgent:
            guard ["kimi","zai"].contains(preferences.provider),let provider=piProvider,let state=environment["PRIME_AGENT_CODING_AGENT_DIR"] else{throw InsightFailure.invalidConfiguration}
            let instruction="{\"task\":\"Interprete somente os sinais analíticos enviados, em uma ou duas linhas curtas em português. Não execute Python, ferramentas ou comandos; não inclua rodapés.\"}"
            arguments=["--print","--mode","text","--no-session","--no-skills","--no-prompt-templates","--no-themes","--no-context-files","--offline","--provider",provider,"--model",preferences.model,"--thinking","off","--system-prompt",instruction]
            return InsightRequest(executable:executable,arguments:arguments,environment:environment,input:prompt,blockChildExecution:true,writableDirectories:[state],proxyHosts:InsightProxy.hosts(for:preferences.provider))
        case .codex:
            guard preferences.provider=="codex" else{throw InsightFailure.invalidConfiguration}
            var args=["exec","--ignore-user-config","--ignore-rules","--ephemeral","--skip-git-repo-check","--json","--color","never","--model",preferences.model]
            for config in ["approval_policy=\"never\"","default_permissions=\"planmeter\"","permissions.planmeter.filesystem={\":minimal\"=\"read\",\":workspace_roots\"=\"read\"}","permissions.planmeter.network.enabled=false","web_search=\"disabled\"","features.shell_tool=false","features.hooks=false","features.multi_agent=false","features.goals=false","features.memories=false","features.remote_plugin=false","features.apps=false","features.skill_mcp_dependency_install=false","apps._default.enabled=false","tools.view_image=false","project_doc_max_bytes=0","analytics.enabled=false"] {args += ["-c",config]}
            let instruction=String(data:try JSONEncoder().encode("{\"task\":\"Retorne somente um objeto JSON com summary: uma ou duas linhas curtas interpretando os sinais analíticos fornecidos. Não inclua rodapé de status, assinatura, data de execução ou informações pessoais. Não use ferramentas.\"}"),encoding:.utf8)!
            args += ["-c","developer_instructions="+instruction,"--output-schema","@planmeter:insight-schema.json","-"]
            let schema=Data(#"{"type":"object","properties":{"summary":{"type":"string","maxLength":440}},"required":["summary"],"additionalProperties":false}"#.utf8)
            return InsightRequest(executable:executable,arguments:args,environment:environment,input:prompt,resources:["insight-schema.json":schema])
        case .opencode:
            guard validOpenCodeModel() else{throw InsightFailure.invalidConfiguration}
            return InsightRequest(executable:executable,arguments:["--pure","run","--model",preferences.model,"--format","json","--title","PlanMeter Insight"],environment:environment,input:prompt,resourceDirectories:["config"])
        }
        return InsightRequest(executable:executable,arguments:arguments,environment:environment,input:prompt)
    }
    func response(_ data:Data)throws->String {
        switch preferences.harness {
        case .pi,.kimi,.primeAgent:
            guard let text=String(data:data,encoding:.utf8) else{throw InsightFailure.invalidResponse}
            return try InsightText.validate(text)
        case .claude:
            guard let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],object["is_error"] as? Bool != true,let text=object["result"] as? String else{throw InsightFailure.invalidResponse}
            return try InsightText.validate(text)
        case .codex:
            guard let output=String(data:data,encoding:.utf8) else{throw InsightFailure.invalidResponse}
            var texts:[String]=[]
            for line in output.components(separatedBy:.newlines) where !line.isEmpty {
                guard let event=(try? JSONSerialization.jsonObject(with:Data(line.utf8))) as? [String:Any] else{throw InsightFailure.invalidResponse}
                let kind=event["type"] as? String
                if kind=="error" || kind=="turn.failed" {throw InsightFailure.failed}
                if let item=event["item"] as? [String:Any],let type=item["type"] as? String {
                    if ["command_execution","file_change","mcp_tool_call","web_search"].contains(type) {throw InsightFailure.failed}
                    if kind=="item.completed",type=="agent_message",let text=item["text"] as? String {texts.append(text)}
                }
            }
            guard texts.count==1,let object=(try? JSONSerialization.jsonObject(with:Data(texts[0].utf8))) as? [String:Any],let summary=object["summary"] as? String else{throw InsightFailure.invalidResponse}
            return try InsightText.validate(summary)
        case .opencode:
            guard let output=String(data:data,encoding:.utf8) else{throw InsightFailure.invalidResponse}
            var texts:[String]=[]
            for line in output.components(separatedBy:.newlines) where !line.isEmpty {
                guard let event=(try? JSONSerialization.jsonObject(with:Data(line.utf8))) as? [String:Any],let kind=event["type"] as? String else{throw InsightFailure.invalidResponse}
                if ["error","tool_use"].contains(kind) {throw InsightFailure.failed}
                if kind=="text",let part=event["part"] as? [String:Any],let text=part["text"] as? String {texts.append(text)}
            }
            return try InsightText.validate(texts.joined(separator:"\n"))
        }
    }
}
func runInsightAdapterTests() {
    var count=0
    func check(_ value:Bool,_ label:String){if !value {fatalError("FAIL insight adapter: \(label)")};count += 1}
    var preferences=InsightPreferences();preferences.provider="kimi";preferences.harness = .pi;preferences.model="k3"
    let pi=InsightAdapter(preferences:preferences,executable:"/fixture/pi",inheritedEnvironment:[:])
    check(pi.connected(Data(#"{"status":"ready","provider":"kimi-coding","authType":"oauth"}"#.utf8)),"actual pi readiness contract")
    check(!pi.connected(Data(#"{"status":"ready","provider":"moonshotai"}"#.utf8)),"API platform cannot substitute coding plan")
    let request=try! pi.generationRequest(prompt:Data("aggregate".utf8))
    check(request.arguments.contains("--no-tools") && request.arguments.contains("--no-extensions") && request.arguments.contains("--no-session"),"pi tools and persistence disabled")
    check(request.input==Data("aggregate".utf8) && !request.arguments.contains("aggregate"),"prompt is not in arguments")
    preferences.provider="claude";preferences.harness = .claude;preferences.model="sonnet"
    let claude=InsightAdapter(preferences:preferences,executable:"/fixture/claude",inheritedEnvironment:[:])
    check(!claude.connected(Data(#"{"loggedIn":true,"authMethod":"api_key"}"#.utf8)),"no silent API billing fallback")
    let cc=try! claude.generationRequest(prompt:Data())
    check(cc.arguments.contains("--strict-mcp-config") && cc.arguments.contains("{\"disableAllHooks\":true}"),"Claude tools hooks and MCP restricted")
    check((try? claude.response(Data(#"{"result":"Uso estável nas janelas observadas.","is_error":false}"#.utf8))) != nil,"Claude response decoded")
    preferences.provider="kimi";preferences.harness = .kimi;preferences.model="kimi-code/k3.1-pro"
    let native=InsightAdapter(preferences:preferences,executable:"/fixture/kimi",inheritedEnvironment:[:])
    check(native.connected(Data("managed:kimi-code  type=kimi  models=6  source=oauth\n".utf8)),"native Kimi managed OAuth metadata")
    let nativeRequest=try! native.generationRequest(prompt:Data("{}".utf8))
    check(String(data:nativeRequest.resources["insight-agent.md"]!,encoding:.utf8)!.contains("tools: []"),"native Kimi profile disables every tool")
    preferences.harness = .opencode;preferences.model="kimi-code-plan-global/k3"
    let open=InsightAdapter(preferences:preferences,executable:"/fixture/opencode",inheritedEnvironment:[:])
    check(open.connected(Data("●  Kimi For Coding (kimi.ai) api\n".utf8)),"OpenCode Coding Plan credential metadata")
    let openRequest=try! open.generationRequest(prompt:Data("{}".utf8))
    check(openRequest.arguments.contains("--pure") && openRequest.resourceDirectories==["config"] && openRequest.environment["OPENCODE_CONFIG_CONTENT"]!.contains("deny"),"OpenCode plugins configuration and tools isolated")
    check((try? open.response(Data(#"{"type":"text","part":{"text":"Ainda faltam observações suficientes."}}"#.utf8))) != nil,"OpenCode JSON text events")
    check((try? open.response(Data(#"{"type":"tool_use","part":{}}"#.utf8)))==nil,"tool event never treated as successful insight")
    preferences.provider="codex";preferences.harness = .codex;preferences.model="fixture-model"
    let codex=InsightAdapter(preferences:preferences,executable:"/fixture/codex",inheritedEnvironment:[:])
    check(codex.connected(Data("Logged in using ChatGPT\n".utf8)),"Codex requires ChatGPT login")
    check(!codex.connected(Data("Logged in using an API key\n".utf8)),"Codex API fallback rejected")
    let codexRequest=try! codex.generationRequest(prompt:Data("{}".utf8))
    check(codexRequest.arguments.contains("features.shell_tool=false") && codexRequest.arguments.contains("--ignore-user-config") && codexRequest.resources["insight-schema.json"] != nil,"Codex constrained runtime and response schema")
    preferences.provider="claude";preferences.harness = .pi;preferences.model="sonnet"
    let piClaude=InsightAdapter(preferences:preferences,executable:"/fixture/pi",inheritedEnvironment:[:])
    check(!piClaude.connected(Data(#"{"status":"ready","provider":"anthropic","authType":"api_key"}"#.utf8)),"pi cannot substitute paid Anthropic API for Claude subscription")
    check(!piClaude.connected(Data(#"{"status":"ready","provider":"anthropic","authType":"oauth"}"#.utf8)),"Claude subscription is restricted to the official client")
    check((try? piClaude.connectionRequest())==nil,"pi cannot route a Claude subscription")
    preferences.harness = .opencode;preferences.model="anthropic/sonnet"
    let openClaude=InsightAdapter(preferences:preferences,executable:"/fixture/opencode",inheritedEnvironment:[:])
    check((try? openClaude.connectionRequest())==nil,"OpenCode cannot route a Claude subscription")
    print("PASS Insight adapters: \(count) checks; no model calls")
}
