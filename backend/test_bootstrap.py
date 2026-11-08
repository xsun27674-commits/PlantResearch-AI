"""Exercise real subprocess startup with only disposable data and loopback sockets."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
from urllib.request import urlopen

BOOTSTRAP = Path(__file__).with_name('bootstrap.py').resolve()


def test_runtime_checks_from_unrelated_working_directory(tmp_path):
    env = {**os.environ, 'PLANT_STARTUP_LOG': str(tmp_path/'startup.log')}
    r = subprocess.run([sys.executable, '-u', str(BOOTSTRAP), '--check'], cwd=tmp_path,
                       env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    assert 'Runtime import checks passed' in r.stdout
    assert 'Python bootstrap PID=' in (tmp_path/'startup.log').read_text()
    assert not (tmp_path/'tasks.sqlite').exists()


def test_missing_dependency_writes_traceback_and_nonzero_exit(tmp_path):
    directory = tmp_path/'路径 with spaces'
    (directory/'backend').mkdir(parents=True)
    shutil.copy2(BOOTSTRAP, directory/'backend/bootstrap.py')
    (directory/'numpy.py').write_text("raise ImportError('simulated native dependency failure')")
    log = tmp_path/'failure.log'
    r = subprocess.run([sys.executable, '-u', str(directory/'backend/bootstrap.py'), '--check'],
                       cwd=tmp_path, env={**os.environ, 'PLANT_STARTUP_LOG': str(log)},
                       capture_output=True, text=True, timeout=30)
    assert r.returncode == 1
    assert 'Importing numpy' in r.stdout
    assert 'simulated native dependency failure' in r.stderr
    assert 'Traceback' in log.read_text()


def test_real_server_health_from_unrelated_directory(tmp_path):
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    env = {**os.environ, 'PLANT_DATA_DIR': str(tmp_path/'data'),
           'PLANT_STARTUP_LOG': str(tmp_path/'startup.log'), 'MPLCONFIGDIR': str(tmp_path/'mpl')}
    with (tmp_path/'out').open('w') as out, (tmp_path/'err').open('w') as err:
        p = subprocess.Popen([sys.executable, '-u', str(BOOTSTRAP), '--port', str(port)],
                             cwd=tmp_path, env=env, stdout=out, stderr=err)
        try:
            deadline = time.monotonic()+60
            while time.monotonic() < deadline:
                assert p.poll() is None, (tmp_path/'err').read_text()
                try:
                    with urlopen(f'http://127.0.0.1:{port}/api/health', timeout=1) as r:
                        assert json.load(r)['status'] == 'ok'
                    break
                except OSError:
                    time.sleep(0.1)
            else:
                raise AssertionError('Backend did not become healthy')
            assert 'Starting uvicorn' in (tmp_path/'startup.log').read_text()
        finally:
            p.terminate()
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(timeout=5)
