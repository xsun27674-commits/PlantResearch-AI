"""Unbuffered desktop entry point with diagnostics independent of pipe redirection."""
import argparse
import importlib
import os
from pathlib import Path
import platform
import sys
import traceback
from datetime import datetime, timezone


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='Import checks only; no server or data writes')
    parser.add_argument('--port', type=int, default=8000)
    args = parser.parse_args()
    handle = None
    try:
        diagnostic = os.environ.get('PLANT_STARTUP_LOG')
        if diagnostic:
            handle = open(diagnostic, 'a', encoding='utf-8', buffering=1)

        def report(message):
            line = f'{datetime.now(timezone.utc).isoformat()} {message}'
            print(line, flush=True)
            if handle:
                handle.write(line + '\n')

        report(f'Python bootstrap PID={os.getpid()} version={platform.python_version()} '
               f'bits={64 if sys.maxsize > 2**32 else 32} executable={sys.executable} cwd={Path.cwd()}')
        # Use the script location rather than registry/PYTHONPATH/current-directory import resolution.
        app_root = Path(__file__).resolve().parent.parent
        sys.path.insert(0, str(app_root))
        for module in ('ssl', 'sqlite3', 'numpy', 'pandas', 'scipy', 'matplotlib', 'pymupdf',
                       'openpyxl', 'httpx', 'multipart', 'fastapi', 'uvicorn'):
            report(f'Importing {module}')
            importlib.import_module(module)
            report(f'Imported {module}')
        if args.check:
            report('Runtime import checks passed (server not started)')
            return 0
        report('Importing backend.app')
        app = importlib.import_module('backend.app').app
        report(f'Starting uvicorn on 127.0.0.1:{args.port}')
        import uvicorn
        uvicorn.run(app, host='127.0.0.1', port=args.port, log_level='info', access_log=False)
        return 0
    except Exception:
        detail = traceback.format_exc()
        print(detail, file=sys.stderr, flush=True)
        if handle:
            handle.write(detail)
        return 1
    finally:
        if handle:
            handle.close()


if __name__ == '__main__':
    raise SystemExit(main())
