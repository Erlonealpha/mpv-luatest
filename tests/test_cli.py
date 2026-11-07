"""Run a relocated copy of the framework against independent project trees."""
import os
from pathlib import Path
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def suite(tmp_path):
    executable = os.environ.get('MPV_LUATEST_LUAJIT') or shutil.which('luajit')
    if not executable:
        pytest.skip('LuaJIT is unavailable; set MPV_LUATEST_LUAJIT')
    framework = tmp_path / 'framework with spaces'
    framework.mkdir()
    shutil.copy2(ROOT / 'run.lua', framework / 'run.lua')
    shutil.copytree(ROOT / 'src', framework / 'src')
    project = tmp_path / 'unrelated project with spaces'
    (project / 'test').mkdir(parents=True)
    # Compatibility imports must use the extracted modules even when a project
    # has old helpers. No consumer project checkout is used by these tests.
    for name in ('framework', 'runner', 'mp_stub', 'support'):
        (project / 'test' / f'{name}.lua').write_text(
            "error('project helper was loaded')\n", encoding='utf-8')
    return executable, framework, project


def write_test(project, name, body, directory='test'):
    path = project / directory / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("local F = require 'framework'\nF.section('fixture')\n" + body + '\n',
                    encoding='utf-8')


def run(suite, *args, cwd=None):
    executable, framework, project = suite
    return subprocess.run([executable, str(framework / 'run.lua'), '--root', str(project),
                           *args], cwd=cwd or framework, capture_output=True, text=True,
                          timeout=30)


@pytest.mark.parametrize('selector', ['player/layout', 'test_player/test_layout.lua',
                                     'player', 'layout', 'player\\layout'])
def test_recursive_selection(suite, selector):
    _, _, project = suite
    write_test(project, 'test_outer/test_player/test_layout.lua', "F.ok(true, 'nested')")
    write_test(project, 'test_unrelated.lua', "F.fail('unselected')")
    write_test(project, 'fixtures/test_player/test_layout.lua', "F.fail('fixture')")
    result = run(suite, selector)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'ALL GOOD: 1 checks passed' in result.stdout
    assert '== fixture ==' not in result.stdout


def test_default_discovery_and_verbose(suite):
    _, _, project = suite
    write_test(project, 'test_z.lua', "F.test('last', function() F.ok(true, 'z') end)")
    write_test(project, 'test_player/test_layout.lua',
               "F.test('nested', function() F.ok(true, 'layout') end)")
    write_test(project, 'real_host/test_ignored.lua', "F.fail('host fixture')")
    result = run(suite, '-v')
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'ALL GOOD: 2 checks passed' in result.stdout
    assert 'ok    nested' in result.stdout
    assert result.stdout.index('test_player/test_layout.lua') < result.stdout.index('test_z.lua')
    assert '== fixture ==' in result.stdout
    assert run(suite, 'player/layout', '-v').returncode == 0


@pytest.mark.parametrize('verbose', [False, True])
def test_assertion_failure_is_never_reported_as_success(suite, verbose):
    _, _, project = suite
    write_test(project, 'test_bad.lua', "F.test('broken', function() F.eq(1, 2, 'value') end)")
    write_test(project, 'test_next.lua', "F.ok(true, 'still runs')")
    result = run(suite, *(['-v'] if verbose else []))
    assert result.returncode == 1
    assert 'test_bad.lua / fixture / broken' in result.stdout
    assert 'ok    broken' not in result.stdout
    assert 'FAILED: 1 failure(s), 1 check(s) passed' in result.stdout


def test_file_errors_keep_the_path_and_continue(suite):
    _, _, project = suite
    write_test(project, 'test_bad.lua', 'this is not lua!')
    write_test(project, 'test_next.lua', "F.ok(true, 'still runs')")
    result = run(suite)
    assert result.returncode == 1
    assert 'test_bad.lua crashed' in result.stdout
    assert '1 check(s) passed' in result.stdout


@pytest.mark.parametrize('args, message', [(['missing'], 'no test file matched'),
                                         (['--unknown'], 'unknown option'),
                                         (['one', 'two'], 'at most one'),
                                         ([''], 'must not be empty'),
                                         (['--root'], 'nonempty path'),
                                         (['--test-dir', ''], 'nonempty path'),
                                         (['--path', '-v'], 'nonempty path'),
                                         (['--bootstrap'], 'nonempty path'),
                                         (['--test-dir', 'absent'], 'test directory')])
def test_invalid_invocations_fail(suite, args, message):
    _, _, project = suite
    write_test(project, 'test_ok.lua', "F.ok(true, 'ok')")
    result = run(suite, *args)
    assert result.returncode == 1
    assert message in result.stdout


def test_help_does_not_load_bootstrap(suite):
    result = run(suite, '--help', '--bootstrap', 'missing.lua')
    assert result.returncode == 0
    assert 'Usage:' in result.stdout
    assert '--root' in result.stdout


def test_relative_paths_bootstrap_and_compatibility_identity(suite):
    _, _, project = suite
    (project / 'src').mkdir()
    (project / 'vendor' / 'dependency').mkdir(parents=True)
    (project / 'src' / 'application.lua').write_text(
        "return { value = require 'dependency.value' }\n", encoding='utf-8')
    (project / 'vendor' / 'dependency' / 'value.lua').write_text('return 17\n', encoding='utf-8')
    (project / 'setup.lua').write_text(
        "local root, test_dir = ...\n"
        "assert(root == '.' and test_dir == 'checks')\n"
        "local stub = require 'mpv_luatest.mp_stub'\n"
        "stub.install()\n"
        "stub.fake.time = 7\n", encoding='utf-8')
    write_test(project, 'test_project.lua', """
local application = require 'application'
local namespaced = require 'mpv_luatest.framework'
local stub = require 'mp_stub'
F.eq(F, namespaced, 'framework identity')
F.eq(stub, require 'mpv_luatest.mp_stub', 'stub identity')
F.eq(require 'runner', require 'mpv_luatest.runner', 'runner identity')
F.eq(application.value, 17, 'repeated module paths resolved from project')
F.eq(require('mp').get_time(), 7, 'bootstrap ran before tests')
""", directory='checks')
    result = run(suite, '--root', '.', '--test-dir', 'checks', '--path', 'src',
                 '--path', 'vendor', '--bootstrap', 'setup.lua', cwd=project)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'ALL GOOD: 5 checks passed' in result.stdout


@pytest.mark.parametrize('body', [None, 'this is not lua!', "error('setup exploded')"])
def test_bootstrap_failures_do_not_execute_tests(suite, body):
    _, _, project = suite
    if body is not None:
        (project / 'setup.lua').write_text(body, encoding='utf-8')
    write_test(project, 'test_should_not_run.lua', "F.fail('TEST EXECUTED')")
    result = run(suite, '--bootstrap', 'setup.lua')
    assert result.returncode == 1
    assert 'bootstrap failed' in result.stdout
    assert 'TEST EXECUTED' not in result.stdout


def test_stub_self_suite_in_relocated_repository(suite):
    _, framework, _ = suite
    shutil.copytree(ROOT / 'tests', framework / 'tests', ignore=shutil.ignore_patterns('__pycache__'))
    result = run(suite, '--root', str(framework), '--test-dir', 'tests')
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'ALL GOOD:' in result.stdout


@pytest.mark.skipif(os.name != 'nt', reason='Windows cmd directory quoting boundary')
@pytest.mark.parametrize('path', ['bad%path', 'bad!path', 'bad"path', 'bad\npath'])
def test_windows_directory_expansion_is_rejected(suite, path):
    result = run(suite, '--test-dir', path)
    assert result.returncode == 1
    assert 'unsupported characters in Windows test directory' in result.stdout


def test_embedded_api_returns_status_and_resets_reports(suite):
    executable, framework, project = suite
    write_test(project, 'test_bad.lua', "F.fail('expected failure')")
    write_test(project, 'test_good.lua', "F.ok(true, 'next suite')")
    script = project / 'embedded.lua'
    script.write_text("""
local framework_root = arg[1]
package.path = framework_root .. '/src/?.lua;' .. framework_root .. '/src/?/init.lua;' .. package.path
local api = require 'mpv_luatest'
assert(api.framework == require 'mpv_luatest.framework')
assert(api.runner == require 'mpv_luatest.runner')
assert(api.support == require 'mpv_luatest.support')
assert(api.mp_stub == require 'mpv_luatest.mp_stub')
assert(api.suite == require 'mpv_luatest.suite')
local defaults = { verbose = false, root = '.', test_dir = 'test', paths = { 'vendor' } }
local options = assert(api.runner.parse_args({ '--path', 'src' }, defaults))
assert(#defaults.paths == 1 and #options.paths == 2)
assert(api.suite.main({ 'bad' }, defaults) == 1)
assert(api.suite.main({ 'good' }, defaults) == 0)
local failed, passed = api.framework.results()
assert(failed == 0 and passed == 1)
assert(package.loaded.framework == api.framework)
assert(package.loaded.mp_stub == api.mp_stub)
assert(package.loaded.runner == api.runner)
""", encoding='utf-8')
    result = subprocess.run([executable, str(script), str(framework)], cwd=project,
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'FAILED: 1 failure(s), 0 check(s) passed' in result.stdout
    assert 'ALL GOOD: 1 checks passed' in result.stdout


def test_documented_example_runs_with_only_the_relocated_framework(suite):
    _, framework, project = suite
    shutil.copytree(ROOT / 'examples', framework / 'examples')
    result = run(suite, '--root', str(framework / 'examples' / 'project'))
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'ALL GOOD: 2 checks passed' in result.stdout
