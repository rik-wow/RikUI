#!/usr/bin/env python3
"""Inventory a local Forever client and bounded exact-build QuestV2 acquisition.

Reads the selected wow_classic_beta row, PE version, six WDB framing inventories,
and local RIKQ packet archives. WDB payload semantics remain explicitly unknown.
Copies packets and WDB bytes into the requested external evidence directory.
No game API is invoked, and inventory does not infer global completeness.
"""
from __future__ import annotations
import argparse
import csv
import ctypes
from ctypes import wintypes
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import urllib.error
import urllib.request
import zlib

WDB_NAMES = ('creaturecache.wdb','gameobjectcache.wdb','npccache.wdb',
             'pagetextcache.wdb','petitioncache.wdb','questcache.wdb')
SIGNATURES = {'creaturecache.wdb':b'BOMW','gameobjectcache.wdb':b'BOGW',
              'npccache.wdb':b'CPNW','pagetextcache.wdb':b'XTPW',
              'petitioncache.wdb':b'NTPW','questcache.wdb':b'TSQW'}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, value) -> None:
    data=(json.dumps(value,sort_keys=True,indent=2,ensure_ascii=False)+'\n').encode()
    temporary=path.with_name(path.name+'.tmp')
    temporary.write_bytes(data)
    os.replace(temporary,path)


def pe_version(path: Path) -> dict:
    if os.name != 'nt':
        return {'state':'unavailable','reason':'PE version resource requires Windows; SHA256 remains available'}
    library=ctypes.WinDLL('version',use_last_error=True)
    library.GetFileVersionInfoSizeW.argtypes=[wintypes.LPCWSTR,ctypes.POINTER(wintypes.DWORD)]
    library.GetFileVersionInfoSizeW.restype=wintypes.DWORD
    library.GetFileVersionInfoW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p]
    library.GetFileVersionInfoW.restype=wintypes.BOOL
    library.VerQueryValueW.argtypes=[ctypes.c_void_p,wintypes.LPCWSTR,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(wintypes.UINT)]
    library.VerQueryValueW.restype=wintypes.BOOL
    dummy=wintypes.DWORD();size=library.GetFileVersionInfoSizeW(str(path),ctypes.byref(dummy))
    if not size: return {'state':'unavailable','reason':'No readable version resource'}
    buffer=ctypes.create_string_buffer(size)
    if not library.GetFileVersionInfoW(str(path),0,size,buffer):
        return {'state':'unavailable','reason':'GetFileVersionInfoW failed'}
    pointer=ctypes.c_void_p();length=wintypes.UINT()
    if not library.VerQueryValueW(buffer,'\\',ctypes.byref(pointer),ctypes.byref(length)) or length.value<52:
        return {'state':'unavailable','reason':'No fixed file version'}
    fields=struct.unpack('<13I',ctypes.string_at(pointer,52))
    def version(ms,ls):return '.'.join(map(str,(ms>>16,ms&65535,ls>>16,ls&65535)))
    result={'state':'observed','fixedFileVersion':version(fields[2],fields[3]),
            'fixedProductVersion':version(fields[4],fields[5])}
    if library.VerQueryValueW(buffer,'\\VarFileInfo\\Translation',ctypes.byref(pointer),ctypes.byref(length)) and length.value>=4:
        translation=ctypes.string_at(pointer,length.value)
        language,codepage=struct.unpack_from('<HH',translation)
        for key in ('FileVersion','ProductVersion'):
            query=f'\\StringFileInfo\\{language:04x}{codepage:04x}\\{key}'
            if library.VerQueryValueW(buffer,query,ctypes.byref(pointer),ctypes.byref(length)):
                result[key[0].lower()+key[1:]]=ctypes.wstring_at(pointer).strip()
    return result


def wdb_inventory(path: Path, build: int, archive: Path) -> dict:
    if not path.is_file():return {'name':path.name,'state':'unavailable','reason':'File absent'}
    data=path.read_bytes();archive.write_bytes(data)
    result={'name':path.name,'bytes':len(data),'sha256':sha(data),'archive':str(archive.name),
            'semanticStatus':'unknown','semanticReason':'Version-specific payload layouts not established; no names, locations or quest rules inferred',
            'coverage':'local encountered cache only; absence is unknown'}
    if len(data)<24:
        return {**result,'state':'invalid','reason':'Truncated 24-byte framing header'}
    result.update(signature=data[:4].decode('ascii',errors='replace'),
                  signatureHex=data[:4].hex(),build=struct.unpack_from('<I',data,4)[0],
                  locale=data[8:12][::-1].decode('ascii',errors='replace'),
                  headerWords=list(struct.unpack('<6I',data[:24])))
    if data[:4]!=SIGNATURES[path.name] or result['build']!=build:
        return {**result,'state':'identity-mismatch','reason':'Unexpected signature or build; records not interpreted'}
    offset=24;records=[];terminated=False
    while offset+8<=len(data):
        record_offset=offset;record_id,length=struct.unpack_from('<II',data,offset);offset+=8
        if record_id==0 and length==0:
            terminated=True;break
        if not record_id or length>len(data)-offset:
            return {**result,'state':'framing-invalid','reason':'Record exceeds remaining bytes or has zero ID',
                    'recordOffset':record_offset,'recordsBeforeFailure':len(records)}
        payload=data[offset:offset+length]
        records.append({'id':record_id,'bytes':length,'offset':record_offset,'payloadSha256':sha(payload)})
        offset+=length
    if not terminated or offset!=len(data):
        return {**result,'state':'framing-invalid','reason':'Missing terminal zero pair or trailing bytes',
                'consumedBytes':offset,'recordsBeforeFailure':len(records)}
    return {**result,'state':'framing-valid','framing':'24-byte header; little-endian uint32 ID,length; payload bytes; terminal zero pair',
            'recordCount':len(records),'uniqueIdCount':len({r['id'] for r in records}),
            'records':records,'consumedBytes':offset}


def observations_inventory(root: Path, archive: Path) -> list[dict]:
    result=[]
    if not root.is_dir():return [{'state':'unavailable','reason':'Observation directory absent'}]
    for path in sorted(root.glob('*.rikq')):
        data=path.read_bytes();(archive/path.name).write_bytes(data)
        row={'name':path.name,'bytes':len(data),'sha256':sha(data),'authority':'imported-untrusted character observation',
             'worldCompleteness':'unknown','authentication':'none; checksums only detect byte changes'}
        match=re.fullmatch(rb'RIKQ1:([0-9a-fA-F]{8}):([0-9a-fA-F]+)\r?\n?',data)
        if match:
            try:
                payload=bytes.fromhex(match[2].decode('ascii'))
                computed=f'{zlib.adler32(payload)&0xffffffff:08x}'
                row.update(format='RIKQ1',declaredAdler32=match[1].decode().lower(),computedAdler32=computed,
                           payloadBytes=len(payload),payloadSha256=sha(payload),
                           state='checksum-valid' if computed==match[1].decode().lower() else 'checksum-mismatch')
            except ValueError:row.update(state='invalid-packet',reason='Odd-length hex payload')
        else:row.update(state='invalid-packet',reason='Unsupported packet framing')
        metadata=path.with_suffix('.json')
        if metadata.is_file():
            raw=metadata.read_bytes();(archive/metadata.name).write_bytes(raw)
            summary={'name':metadata.name,'bytes':len(raw),'sha256':sha(raw),
                     'packetHashMatches':False,'observedCount':None,'reportedCount':None,'questIds':[]}
            try:
                document=json.loads(raw.decode('utf-8-sig'))
                if not isinstance(document,dict):raise ValueError('Archive root must be an object')
                inspection=document.get('inspection',{})
                packet_source=document.get('source',{})
                if not isinstance(inspection,dict) or not isinstance(packet_source,dict):
                    raise ValueError('Archive inspection and source must be objects')
                quests=inspection.get('quests',[])
                if not isinstance(quests,list):raise ValueError('Archive quest inventory must be an array')
                declared=packet_source.get('packetSHA256') or inspection.get('packetSHA256')
                matches=declared==row['sha256']
                accepted=matches and row['state']=='checksum-valid'
                summary.update(packetHashMatches=matches,state='accepted' if accepted else 'rejected',
                               identity=document.get('identity'),format=document.get('format'))
                if accepted:
                    summary.update(observedCount=inspection.get('observedCount'),
                                   reportedCount=inspection.get('reportedCount'),
                                   questIds=[q['id'] for q in quests if isinstance(q,dict) and 'id' in q],
                                   countAuthority='existing structurally validated archive metadata; not a new live observation')
                else:
                    summary['reason']='Packet checksum invalid' if row['state']!='checksum-valid' else 'Archive packet hash mismatch'
            except (UnicodeError,ValueError,TypeError) as error:
                summary.update(state='invalid',reason=str(error))
            row['archiveMetadata']=summary
        result.append(row)
    return result


def csv_inventory(data: bytes) -> dict:
    text=data.decode('utf-8-sig')
    reader=csv.DictReader(io.StringIO(text))
    if not reader.fieldnames or 'ID' not in reader.fieldnames:raise ValueError('Response is not QuestV2 CSV with ID column')
    ids=[]
    for row in reader:
        if None in row:raise ValueError('Malformed CSV row')
        identifier=int(row['ID'])
        if identifier<=0:raise ValueError('Nonpositive QuestV2 ID')
        ids.append(identifier)
    if not ids:raise ValueError('QuestV2 returned no rows')
    return {'state':'available','bytes':len(data),'sha256':sha(data),'rowCount':len(ids),
            'uniqueIdCount':len(set(ids)),'columns':reader.fieldnames,'scope':'exact-build client table; table fields only'}


def fetch_child(url: str, target: Path, status_path: Path) -> None:
    attempts=[]
    for _ in range(2):
        try:
            request=urllib.request.Request(url,headers={'User-Agent':'RikUI-Forever-inventory/1.0','Accept':'text/csv'})
            with urllib.request.urlopen(request,timeout=12) as response:
                data=response.read(64*1024*1024+1)
                if len(data)>64*1024*1024:raise ValueError('QuestV2 response exceeds 64MiB limit')
                final_url=response.url
            info=csv_inventory(data);target.write_bytes(data)
            write_json(status_path,{**info,'url':url,'finalUrl':final_url,'attempts':attempts,'archive':target.name})
            return
        except (urllib.error.URLError,TimeoutError,ValueError,UnicodeError) as error:
            attempts.append({'errorType':type(error).__name__,'reason':str(error),
                             'httpStatus':getattr(error,'code',None)})
    write_json(status_path,{'state':'unavailable','url':url,'attempts':attempts,
                           'scope':'acquisition failed; table rows and semantic coverage remain unknown'})


def acquire_questv2(version: str, output: Path) -> dict:
    url=f'https://wago.tools/db2/QuestV2/csv?build={version}'
    target=output/f'QuestV2-{version}.csv';status=output/'questv2-acquisition.json'
    try:
        completed=subprocess.run([sys.executable,str(Path(__file__).resolve()),'--fetch-url',url,
                        '--fetch-target',str(target),'--fetch-status',str(status)],timeout=30,
                        capture_output=True,text=True)
        if completed.returncode!=0:
            result={'state':'unavailable','url':url,'reason':'Acquisition subprocess failed',
                    'stderr':completed.stderr[-1000:]};write_json(status,result);return result
        return json.loads(status.read_text())
    except subprocess.TimeoutExpired:
        result={'state':'unavailable','url':url,'reason':'30-second total acquisition deadline exceeded',
                'scope':'table availability and rows unknown'};write_json(status,result);return result


def inventory(client_root: Path, observation_root: Path, output: Path, skip_remote: bool=False) -> dict:
    client_root=client_root.resolve();output=output.resolve();observation_root=observation_root.resolve()
    if output.is_relative_to(client_root) or output.is_relative_to(observation_root):
        raise ValueError('Evidence output must be outside the client and observation inputs')
    output.mkdir(parents=True,exist_ok=True)
    (output/'wdb').mkdir(exist_ok=True);(output/'observations').mkdir(exist_ok=True)
    build_info=client_root/'.build.info';raw=build_info.read_bytes()
    reader=csv.DictReader(io.StringIO(raw.decode('utf-8-sig')),delimiter='|')
    rows=[{key.split('!')[0]:value for key,value in row.items()} for row in reader]
    selected=[row for row in rows if row.get('Product')=='wow_classic_beta' and row.get('Active')=='1']
    if len(selected)!=1:raise ValueError('Expected one active wow_classic_beta row')
    identity=selected[0];version=identity['Version'];build=int(version.rsplit('.',1)[1])
    executable=client_root/'_classic_beta_'/'WowB.exe'
    executable_info={'name':'WowB.exe','state':'unavailable'}
    if executable.is_file():
        executable_info={'name':'WowB.exe','bytes':executable.stat().st_size,
                         'sha256':sha(executable.read_bytes()),**pe_version(executable)}
    cache=client_root/'_classic_beta_'/'Cache'/'WDB'/'enUS'
    result={'schemaVersion':1,'product':'wow_classic_beta','build':version,'locale':'enUS',
            'buildInfo':{'sha256':sha(raw),'bytes':len(raw),'selectedRow':identity},
            'executable':executable_info,
            'caches':[wdb_inventory(cache/name,build,output/'wdb'/name) for name in WDB_NAMES],
            'observations':observations_inventory(observation_root,output/'observations'),
            'questV2':{'state':'not-attempted','reason':'--skip-remote'} if skip_remote else acquire_questv2(version,output),
            'semanticBoundaries':[
                'WDB payload semantics are unknown; only exact framing, IDs, sizes and hashes are inventoried.',
                'Empty encountered caches do not establish absence of world content.',
                'QuestV2, if available, supplies only its published columns; it does not establish prerequisites, locations, rewards or complete quest rules.',
                'RIKQ archives are historical character observations, not global world facts.',
                'Native APIs are session-local and were not queried by this offline inventory.',
                'Exact-build semantic quest/entity tables beyond acquired sources remain unavailable or unknown.']}
    write_json(output/'inventory.json',result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client-root',type=Path);parser.add_argument('--observations',type=Path)
    parser.add_argument('--output-dir',type=Path);parser.add_argument('--skip-remote',action='store_true')
    parser.add_argument('--fetch-url',help=argparse.SUPPRESS);parser.add_argument('--fetch-target',type=Path,help=argparse.SUPPRESS)
    parser.add_argument('--fetch-status',type=Path,help=argparse.SUPPRESS)
    args=parser.parse_args()
    if args.fetch_url:fetch_child(args.fetch_url,args.fetch_target,args.fetch_status);return
    if not all((args.client_root,args.observations,args.output_dir)):parser.error('--client-root, --observations and --output-dir are required')
    result=inventory(args.client_root,args.observations,args.output_dir,args.skip_remote)
    print(json.dumps({'build':result['build'],'cacheRecords':{x['name']:x.get('recordCount') for x in result['caches']},
                      'questV2':result['questV2']['state'],'observationPackets':len(result['observations'])},sort_keys=True))


if __name__=='__main__':main()


