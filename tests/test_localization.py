import json, pathlib, re, unittest
from _localization_source import scan
ROOT=pathlib.Path(__file__).resolve().parent.parent
LANGUAGES={'en','es','pt-BR','ko','ja','fr','zh-Hant','hi'}
PLACEHOLDER=re.compile(r'%[1-9][0-9]*\$@')
class CatalogTests(unittest.TestCase):
    def load(self,path):
        def unique(pairs):
            result={}
            for key,value in pairs:
                self.assertNotIn(key,result,'duplicate translation key')
                result[key]=value
            return result
        return json.loads(path.read_text(),object_pairs_hook=unique)
    def test_complete_catalogs_and_parameters(self):
        folder=ROOT/'app/Resources/Locales'
        self.assertEqual({p.stem for p in folder.glob('*.json')},LANGUAGES)
        base=self.load(folder/'pt-BR.json')
        self.assertGreater(len(base),300)
        for code in LANGUAGES:
            data=self.load(folder/(code+'.json'))
            self.assertEqual(set(data),set(base),code)
            for key,value in data.items():
                with self.subTest(language=code,key=key):
                    self.assertIsInstance(value,str)
                    self.assertTrue(value.strip())
                    self.assertEqual(sorted(PLACEHOLDER.findall(key)),sorted(PLACEHOLDER.findall(value)))
    def test_source_messages_have_catalog_entries(self):
        available=set(self.load(ROOT/'app/Resources/Locales/pt-BR.json'))
        for path in (ROOT/'app').glob('*.swift'):
            source=path.read_text()
            for start,end,parts,expressions in scan(source):
                if not re.search(r'\bL\(\s*$',source[max(0,start-20):start]):continue
                key=parts[0]+''.join('%'+str(n+1)+'$@'+parts[n+1] for n in range(len(expressions)))
                with self.subTest(file=path.name,line=source.count('\n',0,start)+1):self.assertIn(key,available)
    def test_native_ui_literals_are_explicitly_localized(self):
        brands={'PlanMeter','Codex','Claude','Claude Code','Kimi Code','Z.ai','Grok','Grok Unified','Prime Agent','OpenCode','MCP','Free','Pro'}
        pattern=re.compile(r'(?:\b(?:Text|Button|Toggle|Section|Picker|TextField|Label)\(|\b(?:title|withTitle)\s*:)\s*"((?:\\.|[^"\\])*)"')
        for path in (ROOT/'app').glob('*.swift'):
            if path.name.endswith('Tests.swift') or path.name in ('Tests.swift','Localization.swift'):continue
            source=path.read_text()
            for match in pattern.finditer(source):
                literal=match.group(1)
                if not re.search(r'[A-Za-zÀ-ÿ]',literal) or literal in brands:continue
                self.fail('Unlocalized UI literal in '+path.name+': '+literal)
        status=(ROOT/'app/ClaudeQuota.swift').read_text()
        self.assertFalse(re.search(r'return\s+"[^"\n]+"',status),'Claude status messages must use L()')
    def test_embedded_instruction_json_keeps_protocol_fields(self):
        folder=ROOT/'app/Resources/Locales'
        for code in LANGUAGES:
            for key,value in self.load(folder/(code+'.json')).items():
                if not key.startswith('{"task":'):continue
                with self.subTest(language=code,key=key):
                    original=json.loads(key);translated=json.loads(value)
                    self.assertEqual(set(translated),set(original))
                    self.assertIsInstance(translated['task'],str)
                    if 'summary' in original['task']:self.assertIn('summary',translated['task'])
    def test_english_fallback_and_portuguese_source(self):
        folder=ROOT/'app/Resources/Locales'
        english=self.load(folder/'en.json')
        self.assertEqual(english['Atualizar'],'Refresh')
        self.assertEqual(english['Configurações'],'Settings')
        portuguese=self.load(folder/'pt-BR.json')
        self.assertTrue(all(key==value for key,value in portuguese.items()))
if __name__=='__main__':unittest.main()
