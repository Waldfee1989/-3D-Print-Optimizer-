"""Bundle a pinned offline OCCT module. Never download code on users' phones."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request
import zipfile

ROOT=Path(__file__).resolve().parents[1]
VERSION='0.0.23'
INTEGRITY='RFfYQXYFX5C1mB1Aywm0ShcUKzXOr/VzTnlzhBSDJOR6YCAPt1HYCzeXWg1vwwjn/cUxwqRNhhtf1dlewoZYCQ=='
OCCT_COMMIT='d2abb6d844231cb8f29be6894440874a4700e4a5'

def download(url,limit):
    with urllib.request.urlopen(url,timeout=60) as response:
        data=response.read(limit+1)
    if len(data)>limit:raise ValueError('Dependency archive exceeds limit')
    return data

def prepare(package=None,sources=False):
    raw=Path(package).read_bytes() if package else download(f'https://registry.npmjs.org/occt-import-js/-/occt-import-js-{VERSION}.tgz',8*1024*1024)
    if base64.b64encode(hashlib.sha512(raw).digest()).decode()!=INTEGRITY:raise ValueError('OCCT package integrity mismatch')
    with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
        def read(name):
            member=archive.getmember('package/'+name)
            if not member.isfile() or member.size>12*1024*1024:raise ValueError('Unexpected package member')
            return archive.extractfile(member).read()
        script=read('dist/occt-import-js.js').decode()
        binary=read('dist/occt-import-js.wasm')
        licenses={name:read('dist/license.'+name+'.txt') for name in ['occt-import-js','occt']}
    assets=ROOT/'assets/step';assets.mkdir(parents=True,exist_ok=True)
    source=script+'\nconst STEP_WASM_BASE64='+json.dumps(base64.b64encode(binary).decode())+';\n'+(assets/'mesh_to_stl.js').read_text()+'\n'+(assets/'worker_runtime.js').read_text()
    (assets/'worker_bundle.js').write_text('window.stepWorkerSource='+json.dumps(source)+';\n')
    for name,data in licenses.items():(ROOT/f'assets/licenses/{name}.txt').write_bytes(data)
    out=ROOT/'build/step-importer';out.mkdir(parents=True,exist_ok=True)
    # Only exact allowlisted files are written; archive paths are never extracted.
    (out/'occt-import-js.js').write_text(script);(out/'occt-import-js.wasm').write_bytes(binary)
    with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
        for name in ['cube-units/cube-mm.step','cube-units/cube-in.step','cube-units/cube-m.step','simple-basic-cube/cube.stp','cax-if/as1_pe_203.stp']:
            source_name='package/test/testfiles/'+name
            data=archive.extractfile(source_name).read()
            destination=out/'fixtures'/name;destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(data)
    if sources:
        occt=download(f'https://codeload.github.com/Open-Cascade-SAS/OCCT/tar.gz/{OCCT_COMMIT}',120*1024*1024)
        with zipfile.ZipFile(out/'STEP-importer-source.zip','w',compression=zipfile.ZIP_STORED) as z:
            z.writestr(f'occt-import-js-{VERSION}.tgz',raw)
            z.writestr(f'OCCT-{OCCT_COMMIT}.tar.gz',occt)
            z.writestr('BUILD.txt',f'occt-import-js {VERSION}, npm SHA512: {INTEGRITY}\nOCCT commit {OCCT_COMMIT}\nUnpack the npm archive; unpack OCCT into its occt/ directory.\nBuild with Emscripten 3.1.69 using included tools and CMakeLists.txt.\nThe prebuilt npm module is unmodified; the app adapter and bundling script\nare in the app repository. Run python3 scripts/prepare_step_importer.py\nto repackage an engine; replace the wasm/script inputs to use your own build.\nLicenses are in the npm dist directory and OCCT root.\n')
    print(f'Offline STEP importer {VERSION} prepared ({len(binary)} WASM bytes).')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--package');parser.add_argument('--sources',action='store_true');args=parser.parse_args();prepare(args.package,args.sources)
