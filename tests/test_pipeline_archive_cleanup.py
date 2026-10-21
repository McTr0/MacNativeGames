"""The archive writer must never clean another process's shared Metal cache."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NVN = ROOT/'games/totk/third_party/d2r_gfx/gfx/nvn'


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun') and shutil.which('unifdef'),
                     'requires macOS Foundation, Metal headers and unifdef')
class PipelineArchiveCleanup(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.work.cleanup)
        cls.root = Path(cls.work.name)
        cls.probes = {}
        for private in (0, 1):
            folder = cls.root/str(private)
            folder.mkdir()
            selected = subprocess.run(['unifdef', '-DTARGET_OS_IPHONE='+str(private),
                                       str(NVN/'totk_pipeline_archive.h')], capture_output=True, text=True)
            if selected.returncode not in (0, 1):
                raise RuntimeError(selected.stderr)
            (folder/'fixture_pipeline_archive.h').write_text(selected.stdout)
            executable = folder/'probe'
            built = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-O2', '-Wall', '-Wextra', '-Werror',
                                    '-Wno-unused-function', '-Wno-deprecated-declarations',
                                    '-DTEST_PRIVATE_POLICY='+str(private), '-I'+str(folder), '-I'+str(NVN),
                                    str(ROOT/'tests/pipeline_archive_cleanup_probe.m'),
                                    '-framework', 'Foundation', '-framework', 'Metal', '-o', str(executable)],
                                   capture_output=True, text=True)
            if built.returncode:
                raise RuntimeError(built.stdout+built.stderr)
            cls.probes[private] = executable

    def run_writer(self, private=0, fail=False):
        # Selecting the iOS branch on the Mac tests the private-directory policy,
        # not an iOS SDK build or device behavior. All filesystem paths are fixtures.
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run([str(self.probes[private]), folder, 'fail' if fail else 'success'],
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            report = json.loads(result.stdout)
        self.assertTrue(report['existing_preserved'], report)
        self.assertTrue(report['foreign_existing_preserved'], report)
        self.assertTrue(report['foreign_new_preserved'], report)
        self.assertTrue(report['partial_absent'], report)
        return report

    def test_mac_publishes_archive_without_accessing_shared_builder_cache(self):
        report = self.run_writer()
        self.assertTrue(report['archive_published'], report)
        self.assertTrue(report['archive_indexed'], report)
        self.assertTrue(report['builder_new_preserved'], report)
        self.assertEqual((report['cache_queries'], report['removed'], report['written']), (0, 0, 1))

    def test_mac_failed_write_removes_own_partial_but_preserves_shared_cache(self):
        report = self.run_writer(fail=True)
        self.assertFalse(report['archive_published'], report)
        self.assertFalse(report['archive_indexed'], report)
        self.assertTrue(report['builder_new_preserved'], report)
        self.assertEqual((report['cache_queries'], report['removed'], report['write_failures']), (0, 0, 1))

    def test_private_cache_policy_still_removes_its_new_builder_directory(self):
        report = self.run_writer(private=1)
        self.assertTrue(report['archive_published'], report)
        self.assertTrue(report['archive_indexed'], report)
        self.assertFalse(report['builder_new_preserved'], report)
        self.assertEqual((report['cache_queries'], report['removed'], report['written']), (1, 1, 1))


if __name__ == '__main__':
    unittest.main()
