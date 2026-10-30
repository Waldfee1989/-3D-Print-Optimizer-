"""Build the separately executed CuraEngine component from pinned upstream source.
No shell command strings or credentials. Source trees/patches remain distributable.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

ENGINE='ebb53015413c568ccf20c050ef0d68c3072da9f9'
STB='d5d052c806eee2ca1f858cb58b2f062d9fa25b90'
CURA='97d20bff1b1a2cc2c13f11ec35997c2fa2f61063'

def unpack(repo, revision, target):
    if target.is_dir(): return
    archive=target.parent/(target.name+'.tar.gz')
    target.parent.mkdir(parents=True,exist_ok=True)
    with urllib.request.urlopen(f'https://github.com/{repo}/archive/{revision}.tar.gz',timeout=90) as response, archive.open('wb') as stream:
        shutil.copyfileobj(response,stream)
    staging=target.parent/(target.name+'-unpack')
    staging.mkdir(exist_ok=True)
    with tarfile.open(archive) as package: package.extractall(staging,filter='data')
    entries=list(staging.iterdir())
    if len(entries)!=1 or not entries[0].is_dir(): raise ValueError('Unexpected source archive')
    entries[0].rename(target);staging.rmdir()

def build(output, android=False, abi='arm64-v8a', jobs=2):
    output=output.resolve();source=output/'source';deps=output/'deps'
    unpack('Ultimaker/CuraEngine',ENGINE,source)
    unpack('nothings/stb',STB,deps/'stb')
    # Only platform/build adaptation; keep a machine-readable, published patch.
    header=source/'src/utils/math.h'
    if '#include <cstdint>' not in header.read_text(): header.write_text('#include <cstdint>\n'+header.read_text())
    path_source=source/'src/utils/getpath.cpp'
    path_text=path_source.read_text()
    if 'char buffer[filePath.size()];' in path_text:
        path_text=path_text.replace('#include <iostream>','#include <iostream>\n#include <vector>')
        path_text=path_text.replace('char buffer[filePath.size()];','std::vector<char> buffer(filePath.size()+1);')
        path_text=path_text.replace('std::strcpy(buffer, filePath.c_str())','std::strcpy(buffer.data(), filePath.c_str())').replace('dirname(buffer)','dirname(buffer.data())')
        path_source.write_text('// Print Optimizer adaptation, 2026-10-30: sized path buffer.\n'+path_text)
    main=source/'src/main.cpp';main_text=main.read_text()
    if 'PR_SET_PDEATHSIG' not in main_text:
        main_text=main_text.replace('#include <iostream>','#if defined(__ANDROID__)\n#include <sys/prctl.h>\n#include <unistd.h>\n#endif\n#include <iostream>')
        main_text=main_text.replace('int main(int argc, char **argv)\n{','int main(int argc, char **argv)\n{\n#if defined(__ANDROID__)\n    prctl(PR_SET_PDEATHSIG, SIGTERM);\n    if (getppid() == 1) return 1;\n#endif')
        main.write_text('// Print Optimizer adaptation, 2026-10-30: stop with parent app.\n'+main_text)
    cmake=source/'CMakeLists.txt';original=cmake.read_text()
    text=original.replace('if (UNIX)\n','if (UNIX AND NOT ANDROID)\n').replace('if(NOT APPLE AND NOT WIN32)\n','if(NOT APPLE AND NOT WIN32 AND NOT ANDROID)\n')
    cmake.write_text(text)
    (output/'platform-patch.json').write_text(json.dumps({'upstream':ENGINE,'replacements':[
      ['src/utils/math.h','include cstdint'],['src/utils/getpath.cpp','size buffer including terminator'],['if (UNIX)','if (UNIX AND NOT ANDROID)'],['if(NOT APPLE AND NOT WIN32)','if(NOT APPLE AND NOT WIN32 AND NOT ANDROID)']]}))
    flags=['cmake','-S',str(source),'-B',str(output/'build'),'-DCMAKE_BUILD_TYPE=Release','-DENABLE_ARCUS=OFF','-DENABLE_OPENMP=OFF','-DBUILD_TESTS=OFF',
      '-DENABLE_MORE_COMPILER_OPTIMIZATION_FLAGS=OFF','-DCMAKE_POSITION_INDEPENDENT_CODE=ON','-DCURA_ENGINE_VERSION=4.13.1-optimizer','-DStb_INCLUDE_DIRS='+str(deps)]
    if android:
        ndk=os.environ.get('ANDROID_NDK_LATEST_HOME') or os.environ.get('ANDROID_NDK_HOME')
        if not ndk:
            root=Path(os.environ.get('ANDROID_HOME','/usr/local/lib/android/sdk'))/'ndk'
            choices=sorted(root.glob('*'),key=lambda p:tuple(int(n) for n in p.name.split('.') if n.isdigit()))
            if choices: ndk=str(choices[-1])
        if not ndk: raise RuntimeError('Android NDK missing')
        flags+=['-DCMAKE_TOOLCHAIN_FILE='+str(Path(ndk)/'build/cmake/android.toolchain.cmake'),'-DANDROID_ABI='+abi,'-DANDROID_PLATFORM=android-23','-DANDROID_STL=c++_static',
          '-DCMAKE_EXE_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384']
    subprocess.run(flags,check=True)
    subprocess.run(['cmake','--build',str(output/'build'),'--target','CuraEngine','--parallel',str(jobs)],check=True)
    destination=output/('liboptimizer_slicer.so' if android else 'optimizer_slicer')
    shutil.copy2(output/'build/CuraEngine',destination)
    print('SLICER_BINARY='+str(destination))
    print('SLICER_SHA256='+hashlib.sha256(destination.read_bytes()).hexdigest())
    return destination

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--android',action='store_true');parser.add_argument('--abi',default='arm64-v8a');parser.add_argument('--jobs',type=int,default=2)
    args=parser.parse_args();build(args.output,args.android,args.abi,args.jobs)
