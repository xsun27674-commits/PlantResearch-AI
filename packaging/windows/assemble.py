"""Assemble offline Windows bundle from verified runtimes and cross-installed stage.
Run with system Python from repository root; no protected application files changed.
Build inputs in /workspace/plant-build: payload/runtime and frontend/node_modules.
"""
from pathlib import Path
import hashlib, json, shutil, zipfile
repo=Path(__file__).resolve().parents[2]
build=Path('/workspace/plant-build')
stage=build/'payload'
app=stage/'app'
excluded={'.git','.venv','node_modules','.next','__pycache__','.pytest_cache','private_data'}
for src in repo.rglob('*'):
    rel=src.relative_to(repo)
    if not src.is_file() or excluded.intersection(rel.parts) or src.name.startswith('.env') or src.suffix in {'.log','.tsbuildinfo'}: continue
    dest=app/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
shutil.copytree(build/'frontend/node_modules',app/'frontend/node_modules',dirs_exist_ok=True)
for src in (repo/'frontend/.next').rglob('*'):
    rel=src.relative_to(repo/'frontend/.next')
    if not src.is_file() or any(p in {'dev','cache','diagnostics'} for p in rel.parts):continue
    dest=app/'frontend/.next'/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
shutil.copy2(repo/'packaging/windows/Launcher.ps1',stage/'Launcher.ps1')
shutil.copy2(repo/'packaging/windows/ServiceProcess.cs',stage/'ServiceProcess.cs')
# Keep a reusable wheel archive and exact wheels manifest for future maintenance.
wheel_info=[]
for p in sorted((build/'wheels').glob('*.whl')):
    wheel_info.append({'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(stage/'WINDOWS-WHEELS.json').write_text(json.dumps(wheel_info,indent=2))
assert (stage/'runtime/python/python.exe').read_bytes()[:2]==b'MZ'
assert (stage/'runtime/node/node.exe').read_bytes()[:2]==b'MZ'
assert (app/'frontend/node_modules/@next/swc-win32-x64-msvc/next-swc.win32-x64-msvc.node').read_bytes()[:2]==b'MZ'
assert (app/'frontend/.next/BUILD_ID').is_file()
for p in stage.rglob('*'):
    if p.is_file() and p.suffix in {'.node','.pyd','.dll','.exe','.so'}:
        assert p.suffix!='.so' and p.read_bytes()[:2]!=b'\x7fE',f'Unexpected Linux binary: {p}'
manifest=[]
for p in sorted(stage.rglob('*')):
    if p.is_file(): manifest.append({'path':p.relative_to(stage).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size})
(stage/'FILES.json').write_text(json.dumps(manifest,indent=2))
output=Path('/workspace/artifacts');output.mkdir(exist_ok=True)
payload=build/'payload.zip'
with zipfile.ZipFile(payload,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(stage.rglob('*')):
        if p.is_file(): z.write(p,p.relative_to(stage))
with zipfile.ZipFile(payload) as z: assert z.testzip() is None
payload_hash=hashlib.sha256(payload.read_bytes()).hexdigest()
package=output/'PlantResearch-AI-Windows-x64.zip'
with zipfile.ZipFile(package,'w',zipfile.ZIP_STORED) as z:
    z.write(payload,'PlantResearch-AI-Setup/payload.zip')
    z.writestr('PlantResearch-AI-Setup/payload.sha256',payload_hash)
    for name in ('Install.cmd','Install.ps1','使用说明.txt'):
        content=(repo/'packaging/windows'/name).read_text()
        # UTF-8 BOM supports Chinese paths/text in Windows PowerShell 5.1.
        if name.endswith('.ps1'):content='\ufeff'+content
        z.writestr('PlantResearch-AI-Setup/'+name,content.replace('\n','\r\n').encode('utf-8'))
with zipfile.ZipFile(package) as z:assert z.testzip() is None
(output/(package.name+'.sha256')).write_text(hashlib.sha256(package.read_bytes()).hexdigest()+'  '+package.name+'\n')
print(f'Verified offline package: {package}, {package.stat().st_size/1024**2:.1f} MiB; {len(manifest)} payload files',flush=True)
