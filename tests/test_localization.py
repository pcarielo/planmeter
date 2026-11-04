import json, pathlib, re, unittest
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
    def test_english_fallback_and_portuguese_source(self):
        folder=ROOT/'app/Resources/Locales'
        english=self.load(folder/'en.json')
        self.assertEqual(english['Atualizar'],'Refresh')
        self.assertEqual(english['Configurações'],'Settings')
        portuguese=self.load(folder/'pt-BR.json')
        self.assertTrue(all(key==value for key,value in portuguese.items()))
if __name__=='__main__':unittest.main()
