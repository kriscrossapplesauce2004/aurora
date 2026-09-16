import copy
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import Cancelled, Engine, Failure, KINDS, LXC_TOOLS, REQUIRED, digest, save_json, select_artifacts, validate_archive, validate_manifest


def device():
    return {'serial': 'usb-123', 'device': 'testphone', 'devices': ['testphone'], 'abis': ['arm64-v8a'],
            'fingerprint': 'vendor/product/device:16/build/id:user/release-keys', 'slot': '_a',
            'part': '/dev/block/bootdevice/by-name/boot_a', 'boot_size': 4096,
            'display': 'Physical size: 1080x2400', 'kernel': '4.14.0-test',
            'config': 'CONFIG_ARM64=y\n' + '\n'.join('CONFIG_' + key + '=y' for key in REQUIRED)}


def bundle(directory):
    directory = Path(directory)
    files = {}
    for kind in ('module', 'companion'):
        files[kind] = directory / (kind + '.zip')
        with zipfile.ZipFile(files[kind], 'w') as archive:
            if kind == 'module':
                archive.writestr('module.prop', 'id=aurora\nversionCode=12\n')
                for name in ('customize.sh', 'tools/guest-distro', 'tools/desktop-on',
                             'tools/env-install', 'tools/session-catalog', 'tools/session-select',
                             'guest-tools/aurora-platform', 'sessions/phosh.session',
                             'sessions/plasma-mobile.session',
                             'zygisk/arm64-v8a.so', 'zygisk/armeabi-v7a.so'):
                    archive.writestr(name, 'fixture')
            else:
                archive.writestr('AndroidManifest.xml', 'fixture')
    for kind in ('runtime', 'rootfs'):
        files[kind] = directory / (kind + '.tar.gz')
        with tarfile.open(files[kind], 'w:gz') as archive:
            names = {name: b'ELF fixture' for name in LXC_TOOLS} if kind == 'runtime' else {
                'etc/os-release': b'ID=debian\n', 'sbin/init': b'init fixture'}
            for name, content in names.items():
                member = tarfile.TarInfo(name)
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
    files['boot'] = directory / 'boot.img'
    files['boot'].write_bytes(b'ANDROID!' + b'kernel' * 10)
    manifest = {'schema': 2, 'version': 'test', 'versionCode': 12, 'artifacts': []}
    for kind in KINDS:
        path = files[kind]
        item = dict(type=kind, name=path.name, size=path.stat().st_size, sha256=digest(path),
                    url='https://example.invalid/' + path.name, support='qualified', abis=['arm64-v8a'])
        if kind == 'boot':
            item.update(devices=['testphone'], androidBuilds=[device()['fingerprint']])
        if kind == 'rootfs':
            item['distro'] = 'debian'
        manifest['artifacts'].append(item)
    save_json(directory / 'manifest.json', manifest)
    return manifest, files


class CoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manifest, self.files = bundle(self.root)
        self.engine = Engine(self.root / 'work')
        self.engine.serial = device()['serial']

    def test_complete_manifest_selects_all_artifacts(self):
        self.assertEqual(set(select_artifacts(validate_manifest(self.manifest), device(), 'debian')), set(KINDS))

    def test_wrong_build_never_selects_boot(self):
        changed = device()
        changed['fingerprint'] += '-ota'
        with self.assertRaisesRegex(Failure, 'boot'):
            select_artifacts(self.manifest, changed, 'debian')

    def test_duplicate_compatible_artifacts_are_not_guessed(self):
        self.manifest['artifacts'].append(copy.deepcopy(self.manifest['artifacts'][0]))
        with self.assertRaises(Failure):
            select_artifacts(self.manifest, device(), 'debian')

    def test_experimental_is_available_by_default(self):
        self.manifest['artifacts'][0]['support'] = 'experimental'
        with self.assertRaises(Failure):
            select_artifacts(self.manifest, device(), 'debian', False)
        self.assertEqual(len(select_artifacts(self.manifest, device(), 'debian')), 5)

    def test_manifest_rejects_unsafe_metadata(self):
        for key, value in [('name', '../escape'), ('size', True), ('sha256', 'a' * 63), ('url', 'http://bad'), ('devices', 'phone')]:
            with self.subTest(key=key):
                manifest = copy.deepcopy(self.manifest)
                manifest['artifacts'][0][key] = value
                with self.assertRaises(Failure):
                    validate_manifest(manifest)

    def test_boot_requires_exact_build_pin(self):
        self.manifest['artifacts'][3].pop('androidBuilds')
        with self.assertRaises(Failure):
            validate_manifest(self.manifest)

    def test_local_cache_is_reverified(self):
        artifact = self.manifest['artifacts'][0]
        cached = self.engine.download(artifact, self.root)
        cached.write_bytes(b'corrupted')
        cached = self.engine.download(artifact, self.root)
        self.assertEqual(digest(cached), artifact['sha256'])

    def test_bad_download_is_not_promoted(self):
        artifact = dict(self.manifest['artifacts'][0], sha256='0' * 64)
        with self.assertRaises(Failure):
            self.engine.download(artifact, self.root)
        self.assertFalse(list((self.root / 'work/cache').rglob('*.partial')))
        self.assertFalse((self.root / 'work/cache' / artifact['sha256'] / artifact['name']).exists())

    def test_valid_archives(self):
        for kind, path in self.files.items():
            validate_archive(path, kind)

    def bad_tar(self, members):
        path = self.root / 'bad.tar.gz'
        with tarfile.open(path, 'w:gz') as archive:
            for name, link in members:
                member = tarfile.TarInfo(name)
                if link is not None:
                    member.type = tarfile.SYMTYPE
                    member.linkname = link
                archive.addfile(member)
        return path

    def test_archive_escape_and_link_writes_rejected(self):
        for members in [[('../escape', None)], [('/escape', None)], [('etc', '/tmp'), ('etc/config', None)],
                        [('etc/link', '../../escape')], [('same', None), ('same', None)]]:
            with self.subTest(members=members), self.assertRaises(Failure):
                validate_archive(self.bad_tar(members), 'rootfs')

    def test_runtime_rejects_links(self):
        with self.assertRaises(Failure):
            validate_archive(self.bad_tar([('lxc-start', 'other')]), 'runtime')

    def test_arch_init_resolves_through_usrmerge_and_rejects_dangling_link(self):
        path = self.root / 'arch.tar.gz'
        for with_binary in (True, False):
            with tarfile.open(path, 'w:gz') as archive:
                for name, target in [('sbin', 'usr/bin'), ('usr/bin/init', '../lib/systemd/systemd')]:
                    entry = tarfile.TarInfo(name)
                    entry.type = tarfile.SYMTYPE
                    entry.linkname = target
                    archive.addfile(entry)
                files = {'etc/aurora-profile': b'ID=arch\n',
                         r'usr/lib/systemd/system/system-systemd\x2dveritysetup.slice': b'[Unit]\n'}
                if with_binary:
                    files['usr/lib/systemd/systemd'] = b'init fixture'
                for name, data in files.items():
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    archive.addfile(entry, io.BytesIO(data))
            if with_binary:
                validate_archive(path, 'rootfs', 'arch')
            else:
                with self.assertRaisesRegex(Failure, 'no init'):
                    validate_archive(path, 'rootfs', 'arch')

    def test_subprocess_output_and_nonzero_status(self):
        output, status = self.engine.run([sys.executable, '-c', 'print("first"); print("second")'])
        self.assertEqual(output, 'first\nsecond')
        self.assertEqual(status, 0)
        with self.assertRaises(Failure):
            self.engine.run([sys.executable, '-c', 'raise SystemExit(7)'])

    def test_cancel_stops_long_running_process(self):
        timer = threading.Timer(0.2, self.engine.cancel.set)
        timer.start()
        try:
            with self.assertRaises(Cancelled):
                self.engine.run([sys.executable, '-c', 'import time; time.sleep(30)'])
        finally:
            timer.cancel()

    def test_workspace_lock_is_exclusive_and_released(self):
        with self.engine.transaction():
            with self.assertRaises(Failure), self.engine.transaction():
                pass
        with self.engine.transaction():
            pass

    def test_profile_uses_detected_dimensions_and_vendor_graphics(self):
        profile = self.engine.device_profile(device()).read_text()
        self.assertIn('AURORA_PANEL_HEIGHT=2400', profile)
        self.assertIn('AURORA_GRAPHICS_RENDERER=libhybris', profile)

    def test_preparation_does_not_install_or_flash(self):
        backup = self.root / 'backup.img'
        backup.write_bytes(b'ANDROID!' + b'backup')
        with patch.object(self.engine, 'assert_device'), patch.object(self.engine, 'backup', return_value=backup), \
             patch.object(self.engine, 'repack', return_value=self.files['boot']), \
             patch.object(self.engine, 'shell') as shell, patch.object(self.engine, 'flash') as flash:
            plan = self.engine.install(device(), str(self.root / 'manifest.json'), 'debian', 'test', prepare_only=True)
        self.assertEqual(plan['status'], 'prepared')
        shell.assert_not_called()
        flash.assert_not_called()

    def test_wrong_hostname_stops_before_device_io(self):
        with patch.object(self.engine, 'assert_device') as inspect, self.assertRaises(Failure):
            self.engine.install(device(), '', 'debian', 'x;reboot')
        inspect.assert_not_called()

    def test_wrong_display_name_stops_before_device_io(self):
        with patch.object(self.engine, 'assert_device') as inspect, self.assertRaises(Failure):
            self.engine.install(device(), '', 'debian', 'test', display_name='root:admin')
        inspect.assert_not_called()

    def test_wrong_device_backup_stops_restore(self):
        backup = self.root / 'backup.img'
        backup.write_bytes(b'ANDROID!backup')
        metadata = dict(device(), sha256=digest(backup), serial='another-device')
        save_json(backup.with_name('backup.json'), metadata)
        with patch.object(self.engine, 'flash') as flash, self.assertRaises(Failure):
            self.engine.restore(device(), backup)
        flash.assert_not_called()

    def test_flash_script_restores_after_write_failure(self):
        backup = self.root / 'backup.img'
        backup.write_bytes(b'ANDROID!' + b'x' * 4088)
        metadata = dict(device(), sha256=digest(backup))
        save_json(backup.with_name('backup.json'), metadata)
        scripts = []
        with patch.object(self.engine, 'assert_device'), patch.object(self.engine, 'stage'), \
             patch.object(self.engine, 'shell', side_effect=lambda script, **kw: scripts.append(script) or ''):
            self.engine.flash(device(), self.files['boot'], backup)
        flash_script = next(script for script in scripts if 'restore()' in script)
        self.assertIn('Original boot restored and verified.', flash_script)
        self.assertIn('if dd ', flash_script)
        subprocess.run(['sh', '-n'], input=flash_script, text=True, check=True)

    def test_failed_flash_really_restores_fixture_partition(self):
        original = b'ANDROID!' + b'x' * 4088
        partition = self.root / 'partition.img'
        partition.write_bytes(original)
        target = dict(device(), part=str(partition))
        backup = self.root / 'backup.img'
        backup.write_bytes(original)
        save_json(backup.with_name('backup.json'), dict(target, sha256=digest(backup)))
        scripts = []
        with patch.object(self.engine, 'assert_device'), patch.object(self.engine, 'stage'), \
             patch.object(self.engine, 'shell', side_effect=lambda script, **kw: scripts.append(script) or ''):
            self.engine.flash(target, self.files['boot'], backup)
        script = next(value for value in scripts if 'restore()' in value)
        remote = self.root / 'staging'
        remote.mkdir()
        (remote / 'new.img').write_bytes(self.files['boot'].read_bytes())
        (remote / 'backup.img').write_bytes(original)
        import re
        import shlex
        script = re.sub(r'/data/local/tmp/aurora-flash-[a-f0-9]+', str(remote), script)
        functions = f'''getprop() {{
            case "$1" in
                ro.boot.slot_suffix) printf '%s' '_a';;
                ro.build.fingerprint) printf '%s' {shlex.quote(target['fingerprint'])};;
            esac
        }}
        dd() {{
            case "$*" in
                *new.img*) printf 'partial write' > {shlex.quote(str(partition))}; return 1;;
                *) command dd "$@";;
            esac
        }}
        '''
        result = subprocess.run(['sh'], input=functions + script, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Original boot restored and verified.', result.stdout)
        self.assertEqual(partition.read_bytes(), original)

    def test_port_build_assembles_a_device_bound_bundle(self):
        source = self.root / 'source'
        (source / 'scripts/kconfig').mkdir(parents=True)
        (source / 'Makefile').write_text('fixture')
        (source / 'scripts/kconfig/merge_config.sh').write_text('fixture')
        def build(args, **kwargs):
            args = [str(arg) for arg in args]
            if args[-1] == 'HEAD':
                return 'a' * 40, 0
            if args[-1] == 'Image.gz-dtb':
                output = next(arg[2:] for arg in args if arg.startswith('O='))
                kernel = Path(output) / 'arch/arm64/boot/Image.gz-dtb'
                kernel.parent.mkdir(parents=True)
                kernel.write_bytes(b'compiled-kernel-fixture')
            return '', 0
        with patch.object(self.engine, 'assert_device'), patch.object(self.engine, 'run', side_effect=build) as runner, \
             patch.object(self.engine, 'backup', return_value=self.files['boot']), \
             patch.object(self.engine, 'repack', return_value=self.files['boot']):
            path = self.engine.port(device(), source, 'Image.gz-dtb', 2, str(self.root / 'manifest.json'), 'debian')
        manifest = validate_manifest(json.loads(Path(path).read_text()))
        selected = select_artifacts(manifest, device(), 'debian', True)
        with zipfile.ZipFile(Path(path).parent / selected['module']['name']) as archive:
            profile = archive.read('device-profiles/testphone.conf').decode()
            self.assertIn('AURORA_GRAPHICS_RENDERER=libhybris', profile)
            self.assertIn('AURORA_PANEL_WIDTH=1080', profile)
        for artifact in selected.values():
            self.assertEqual(digest(Path(path).parent / artifact['name']), artifact['sha256'])
        self.assertTrue(any(call.args[0][-1] == 'olddefconfig' for call in runner.call_args_list))
        self.assertTrue(any(call.args[0][-1] == 'Image.gz-dtb' for call in runner.call_args_list))
        self.assertTrue(any('CROSS_COMPILE=aarch64-linux-gnu-' in call.args[0] for call in runner.call_args_list))

    def test_local_base_bundle_is_generated_from_verified_build_outputs(self):
        repo = self.root / 'repo'
        (repo / 'magisk-module').mkdir(parents=True)
        (repo / 'companion/app/build/outputs/apk/debug').mkdir(parents=True)
        (repo / 'guest').mkdir()
        (repo / 'dist/lxc-bin').mkdir(parents=True)
        (repo / 'version.properties').write_text('version=1.2.3\nversionCode=12\ncodename=Test\n')
        shutil.copyfile(self.files['module'], repo / 'magisk-module/aurora-magisk-v1.2.3.zip')
        shutil.copyfile(self.files['companion'], repo / 'companion/app/build/outputs/apk/debug/app-debug.apk')
        shutil.copyfile(self.files['rootfs'], repo / 'guest/rootfs.tar.gz')
        with tarfile.open(self.files['runtime'], 'r:gz') as archive:
            archive.extractall(repo / 'dist/lxc-bin', filter='data')
        for path in (repo / 'dist/lxc-bin').iterdir():
            path.chmod(0o755)
        (repo / 'magisk-module/aurora-magisk-v1.2.3.zip').touch()
        (repo / 'companion/app/build/outputs/apk/debug/app-debug.apk').touch()
        with patch.object(self.engine, 'run') as run:
            path = self.engine.build_local_base_bundle(repo, device(), 'debian')
        run.assert_not_called()
        manifest = validate_manifest(json.loads(Path(path).read_text()))
        self.assertEqual({item['type'] for item in manifest['artifacts']},
                         {'module', 'runtime', 'rootfs', 'companion'})
        for item in manifest['artifacts']:
            artifact = Path(path).parent / item['name']
            self.assertEqual(digest(artifact), item['sha256'])
            validate_archive(artifact, item['type'], 'debian')


if __name__ == '__main__':
    unittest.main()
