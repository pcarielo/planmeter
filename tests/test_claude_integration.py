import json, os, pathlib, shlex, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ClaudeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='PlanMeter Claude & ')
        self.home=pathlib.Path(self.temp.name); self.env=dict(os.environ,HOME=str(self.home))
        self.bin=self.home/'bin'; self.bin.mkdir()
        fake=self.bin/'claude'; fake.write_text('#!/bin/sh\necho unexpected > "$HOME/provider-called"\nexit 1\n'); fake.chmod(0o755)
        self.env['PATH']=str(self.bin)+':'+self.env['PATH']
        self.settings=self.home/'.claude/settings.json'; self.settings.parent.mkdir()
        self.marker=self.home/'executions'
        self.original=self.home/'original.py'
        self.original.write_text('import pathlib,sys\np=pathlib.Path('+repr(str(self.marker))+')\np.write_text(p.read_text()+"1" if p.exists() else "1")\ndata=sys.stdin.buffer.read()\nsys.stdout.buffer.write(data)\nsys.stderr.write("original error")\nsys.exit(7)\n')
        self.data={'unrelated':{'keep':[1,True]},'statusLine':{'type':'command','command':'python3 '+shlex.quote(str(self.original)),'padding':2}}
        self.settings.write_text(json.dumps(self.data))
    def tearDown(self): self.temp.cleanup()
    def configure(self,flag,ok=True):
        p=subprocess.run(['python3',str(ROOT/'scripts/configure-claude.py'),flag],env=self.env,capture_output=True,text=True)
        self.assertEqual(p.returncode==0,ok,p.stdout+p.stderr); return p
    def test_check_never_changes_files_or_leaks_command(self):
        before={str(p):p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        out=self.configure('--check'); self.assertNotIn(str(self.original),out.stdout)
        self.assertEqual(before,{str(p):p.read_bytes() for p in self.home.rglob('*') if p.is_file()})
    def test_apply_preserves_settings_and_runs_original_once(self):
        self.configure('--apply'); first=self.settings.read_bytes(); self.configure('--apply'); self.assertEqual(first,self.settings.read_bytes())
        data=json.loads(first); self.assertEqual(data['unrelated'],self.data['unrelated']); self.assertEqual(data['statusLine']['padding'],2)
        payload=json.dumps({'session_id':'private-session','secret':'never cache','rate_limits':{'five_hour':{'used_percentage':30,'resets_at':1900000000}}}).encode()
        p=subprocess.run(data['statusLine']['command'],shell=True,input=payload,capture_output=True,env=self.env)
        self.assertEqual(p.stdout,payload); self.assertEqual(p.stderr,b'original error'); self.assertEqual(p.returncode,7); self.assertEqual(self.marker.read_text(),'1')
        cache=self.home/'Library/Application Support/PlanMeter/claude-statusline.json'
        self.assertEqual(json.loads(cache.read_text())['rateLimits']['five_hour']['used_percentage'],30)
        self.assertFalse((self.home/'provider-called').exists())
        self.assertNotIn('private-session',cache.read_text()); self.assertNotIn('never cache',cache.read_text())
        backups=list(self.settings.parent.glob('settings.json.planmeter-backup-*')); self.assertEqual(len(backups),1)
        self.assertEqual(json.loads(backups[0].read_text()),self.data); self.assertEqual(backups[0].stat().st_mode & 0o777,0o600)
    def test_replayed_payload_does_not_refresh_observation(self):
        self.configure('--apply')
        helper=self.home/'Library/Application Support/PlanMeter/integration/claude-statusline-cache.py'
        payload=b'{"session_id":"synthetic","rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1900000000}}}'
        cache=helper.parent.parent/'claude-statusline.json'
        subprocess.run(['python3',str(helper)],input=payload,env=self.env,check=True)
        first=json.loads(cache.read_text())
        subprocess.run(['python3',str(helper)],input=payload,env=self.env,check=True)
        second=json.loads(cache.read_text())
        self.assertEqual(first['providerObservedAt'],second['providerObservedAt'])
        self.assertGreaterEqual(second['capturedAt'],first['capturedAt'])
        self.assertIsNone(second['identityFingerprint'])
        self.assertEqual(cache.stat().st_mode & 0o777,0o600)
        self.assertFalse((self.home/'provider-called').exists())
    def test_bundled_setup_works_from_unrelated_directory(self):
        helper=ROOT/'build/PlanMeter.app/Contents/Resources/Integration/configure-claude.py'
        self.assertTrue(helper.is_file())
        unrelated=self.home/'unrelated folder'; unrelated.mkdir()
        result=subprocess.run(['python3',str(helper),'--apply'],cwd=unrelated,env=self.env,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr.decode())
        configured=json.loads(self.settings.read_text())
        self.assertIn('claude-statusline-wrapper.py',configured['statusLine']['command'])
        self.assertFalse((self.home/'provider-called').exists())
    def test_invalid_settings_are_not_overwritten(self):
        self.settings.write_text('{broken'); self.configure('--apply',ok=False); self.assertEqual(self.settings.read_text(),'{broken')
    def test_unsupported_statusline_is_not_overwritten(self):
        self.settings.write_text(json.dumps({'statusLine':'unsupported'})); before=self.settings.read_bytes()
        self.configure('--apply',ok=False); self.assertEqual(self.settings.read_bytes(),before)
    def test_symlink_settings_are_rejected(self):
        target=self.home/'target'; self.settings.rename(target); self.settings.symlink_to(target)
        before=target.read_bytes(); self.configure('--apply',ok=False); self.assertEqual(target.read_bytes(),before)
if __name__=='__main__': unittest.main()
