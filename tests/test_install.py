import os, pathlib, plistlib, shutil, subprocess, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='PlanMeter test & ')
        self.home = pathlib.Path(self.tmp.name)
        self.repo = self.home / 'source with spaces'
        shutil.copytree(ROOT / 'scripts', self.repo / 'scripts')
        self.bundle = self.repo / 'build/PlanMeter.app'
        executable = self.bundle / 'Contents/MacOS/PlanMeter'
        executable.parent.mkdir(parents=True)
        executable.write_text('#!/bin/sh\nexit 0\n'); executable.chmod(0o755)
        (self.bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'io.github.pcarielo.planmeter','CFBundleExecutable':'PlanMeter'}))
        self.bin = self.home / 'bin'; self.bin.mkdir()
        for command, body in {'codesign':'exit 0','open':'exit 0','launchctl':'printf \"%s\\n\" \"$*\" >> \"$HOME/launchctl-calls\"; exit 0','ps':'printf "%s\\n" "$FAKE_PS"'}.items():
            p=self.bin / command; p.write_text('#!/bin/sh\n'+body+'\n'); p.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin)+':'+os.environ['PATH'])
        self.destination = self.home / 'Applications/PlanMeter.app'
    def tearDown(self): self.tmp.cleanup()
    def run_script(self, name, *args, ok=True, input=None):
        p=subprocess.run(['bash',str(self.repo/'scripts'/name),*args],env=self.env,text=True,capture_output=True,input=input)
        if ok: self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        else: self.assertNotEqual(p.returncode,0,p.stdout+p.stderr)
        return p
    def install(self,*args): return self.run_script('install.sh','--no-build','--no-launch',*args)
    def test_install_defaults_without_login(self):
        self.install(); self.assertTrue(self.destination.exists())
        self.assertFalse((self.home/'Library/LaunchAgents/io.github.pcarielo.planmeter.plist').exists())
    def test_login_roundtrip_escaped_path(self):
        dest=self.home/'Apps & things/PlanMeter.app'
        self.install('--destination',str(dest),'--login')
        p=self.home/'Library/LaunchAgents/io.github.pcarielo.planmeter.plist'
        data=plistlib.loads(p.read_bytes()); self.assertEqual(data['ProgramArguments'],[str(dest/'Contents/MacOS/PlanMeter')]); self.assertTrue(data['RunAtLoad'])
        self.run_script('login-item.sh','disable','--destination',str(dest)); self.assertFalse(p.exists())
    def test_running_install_is_preserved(self):
        self.install(); marker=self.destination/'marker'; marker.write_text('keep')
        self.env['FAKE_PS']='123 '+str(self.destination/'Contents/MacOS/PlanMeter')
        self.run_script('install.sh','--no-build','--no-launch',ok=False)
        self.assertEqual(marker.read_text(),'keep')
    def test_reject_wrong_destination(self):
        self.run_script('install.sh','--no-build','--no-launch','--destination',str(self.home),ok=False)
        self.assertTrue(self.home.exists())
    def test_signature_failure_preserves_installed_app(self):
        self.install(); marker=self.destination/'marker'; marker.write_text('keep')
        (self.bin/'codesign').write_text('#!/bin/sh\nexit 1\n')
        self.run_script('install.sh','--no-build','--no-launch',ok=False)
        self.assertEqual(marker.read_text(),'keep')
    def test_foreign_bundle_is_not_replaced(self):
        self.install()
        (self.destination/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'foreign'}))
        self.run_script('install.sh','--no-build','--no-launch',ok=False)
        self.assertEqual(plistlib.loads((self.destination/'Contents/Info.plist').read_bytes())['CFBundleIdentifier'],'foreign')
    def test_symlink_destination_is_not_replaced(self):
        target=self.home/'other'; target.mkdir()
        self.destination.parent.mkdir(); self.destination.symlink_to(target)
        self.run_script('install.sh','--no-build','--no-launch',ok=False)
        self.assertTrue(self.destination.is_symlink()); self.assertTrue(target.exists())
    def test_default_uninstall_removes_matching_login_item(self):
        self.install('--login')
        agent=self.home/'Library/LaunchAgents/io.github.pcarielo.planmeter.plist'
        keychain=self.home/'Library/Keychains/fixture.keychain'; keychain.parent.mkdir(parents=True); keychain.write_text('keep')
        self.run_script('uninstall.sh',input=str(self.destination)+'\n')
        self.assertFalse(agent.exists()); self.assertEqual(keychain.read_text(),'keep')
    def test_foreign_login_item_is_preserved(self):
        self.install()
        agent=self.home/'Library/LaunchAgents/io.github.pcarielo.planmeter.plist'; agent.parent.mkdir(parents=True)
        for label, arguments in [('foreign',[str(self.destination/'Contents/MacOS/PlanMeter')]),('io.github.pcarielo.planmeter',[str(self.destination/'Contents/MacOS/PlanMeter'),'--extra']),('io.github.pcarielo.planmeter',['/another/PlanMeter.app/Contents/MacOS/PlanMeter'])]:
            original=plistlib.dumps({'Label':label,'ProgramArguments':arguments})
            agent.write_bytes(original)
            for action in ('enable','disable'):
                self.run_script('login-item.sh',action,ok=False); self.assertEqual(agent.read_bytes(),original)
            self.run_script('login-item.sh','status'); self.assertEqual(agent.read_bytes(),original)
            self.assertFalse((self.home/'launchctl-calls').exists())
        self.run_script('uninstall.sh',input=str(self.destination)+'\n'); self.assertEqual(agent.read_bytes(),original)
    def test_symlink_login_item_is_preserved(self):
        self.install()
        agent=self.home/'Library/LaunchAgents/io.github.pcarielo.planmeter.plist'; agent.parent.mkdir(parents=True)
        target=self.home/'foreign.plist'; target.write_bytes(plistlib.dumps({'Label':'io.github.pcarielo.planmeter','ProgramArguments':[str(self.destination/'Contents/MacOS/PlanMeter')]})); agent.symlink_to(target)
        for action in ('enable','disable'):
            self.run_script('login-item.sh',action,ok=False); self.assertTrue(agent.is_symlink())
        self.run_script('uninstall.sh',input=str(self.destination)+'\n'); self.assertTrue(agent.is_symlink()); self.assertTrue(target.exists())
    def test_malformed_login_item_is_preserved(self):
        self.install()
        agent=self.home/'Library/LaunchAgents/io.github.pcarielo.planmeter.plist'; agent.parent.mkdir(parents=True); agent.write_bytes(b'not plist')
        for action in ('enable','disable'):
            self.run_script('login-item.sh',action,ok=False); self.assertEqual(agent.read_bytes(),b'not plist')
        self.run_script('uninstall.sh',input=str(self.destination)+'\n'); self.assertEqual(agent.read_bytes(),b'not plist')
    def test_uninstall_requires_exact_confirmation_preserves_cache(self):
        self.install(); cache=self.home/'Library/Caches/PlanMeter/keep'; cache.parent.mkdir(parents=True); cache.write_text('keep')
        self.run_script('uninstall.sh',input='yes\n',ok=False); self.assertTrue(self.destination.exists())
        self.run_script('uninstall.sh',input=str(self.destination)+'\n'); self.assertFalse(self.destination.exists()); self.assertEqual(cache.read_text(),'keep')
if __name__=='__main__': unittest.main()
