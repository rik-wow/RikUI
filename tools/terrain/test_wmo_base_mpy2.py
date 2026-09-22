"""Focused source-format tests; this does not establish native traversal."""
import argparse,collections,hashlib,importlib.util,json,pathlib,struct,sys,types,unittest
P=pathlib.Path(__file__).parent

def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec)
 sys.modules[name]=value;spec.loader.exec_module(value);return value
import terrain_probe as t
import wmo_probe as w
old=None

def chunk(tag,body):return tag.encode()[::-1]+struct.pack('<I',len(body))+body

def root_fixture(groups=(100,),lod=0,extras=b'',n=None):
 n=len(groups) if n is None else n;h=bytearray(64);struct.pack_into('<I',h,4,n)
 struct.pack_into('<I',h,24,1);struct.pack_into('<HH',h,60,4,lod)
 return (chunk('MVER',struct.pack('<I',17))+chunk('MOHD',h)+
  chunk('GFID',struct.pack('<'+'I'*len(groups),*groups))+chunk('MOGI',bytes(32*n))+
  chunk('MODS',struct.pack('<20sIII',b'Set_$DefaultGlobal',0,0,0))+chunk('MODD',b'')+extras)

def group_fixture(rows=((8,255),(32,3),(36,4),(0,0)),metadata='MOPY',extras=b'',flags=0,flags2=0,liquid=0,rawmeta=None):
 h=bytearray(68);struct.pack_into('<I',h,8,flags);struct.pack_into('<I',h,52,liquid);struct.pack_into('<I',h,60,flags2)
 meta=b''.join(struct.pack('<HH' if metadata=='MPY2' else '<BB',*r) for r in rows) if rawmeta is None else rawmeta
 subs=chunk('MOVT',struct.pack('<9f',0,0,0,1,0,0,0,1,0))+chunk('MOVI',struct.pack('<'+'H'*len(rows)*3,*([0,1,2]*len(rows))))+chunk(metadata,meta)+extras
 return chunk('MVER',struct.pack('<I',17))+chunk('MOGP',h+subs)

class WMOTests(unittest.TestCase):
 def test_old_mopy_result_preserved(self):
  after=w.group(group_fixture(),4)
  self.assertEqual(after['faceFlags'],{8:1,32:1,36:1,0:1})
  self.assertEqual(after['sourceTriangles'],4)
  self.assertEqual(after['collisionTriangles'],2)
  self.assertEqual(after['indices'],[0,1,2,0,1,2]);self.assertEqual(after['triangleMetadata'],'MOPY')
 def test_mpy2_same_collision_selection_without_field_truncation(self):
  rows=((8,65535),(32,500),(36,300),(0,0),(0x108,600))
  g=w.group(group_fixture(rows,'MPY2'),4)
  self.assertEqual(g['collisionTriangles'],3);self.assertEqual(g['sourceTriangles'],5)
  self.assertEqual(g['faceFlags'][0x108],1);self.assertEqual(g['materialCounts'][65535],1)
  self.assertEqual(g['materialCounts'][500],1);self.assertEqual(g['triangleMetadata'],'MPY2')
 def test_base_slice_and_null_tail_selection(self):
  r=w.root(root_fixture((100,200,300,0,0,0),3,n=2))
  self.assertEqual(r['groups'],[100,200]);self.assertEqual(r['lodGroupSlots'],[300,0,0,0])
  self.assertEqual(r['groupSlots'],[100,200,300,0,0,0]);self.assertEqual(r['groupSelection'],'first-groupCount-base-slots')
 def test_invalid_base_slots_and_layout_rejected(self):
  for args in [((0,200),0,None),((100,100),0,None),((100,100),2,1),((100,200,300),2,2),((100,),9,1)]:
   with self.subTest(args=args):
    with self.assertRaises(ValueError):w.root(root_fixture(args[0],args[1],n=args[2]))
 def test_mpy2_framing_both_and_missing_metadata_rejected(self):
  with self.assertRaisesRegex(ValueError,'WMO-stride:MPY2'):w.group(group_fixture(metadata='MPY2',rawmeta=b'123'),4)
  with self.assertRaisesRegex(ValueError,'WMO-geometry-count'):w.group(group_fixture(metadata='MPY2',rawmeta=b'1234'),4)
  with self.assertRaisesRegex(ValueError,'WMO-triangle-metadata-choice'):
   w.group(group_fixture(extras=chunk('MPY2',bytes(16))),4)
  with self.assertRaisesRegex(ValueError,'WMO-triangle-metadata-choice'):
   w.group(group_fixture(metadata='XXXX'),4)
 def test_tail_group_not_usable_as_base_collision(self):
  with self.assertRaisesRegex(ValueError,'WMO-LOD-group-not-base-collision'):
   w.group(group_fixture(flags=1024),4)
 def test_unsupported_liquid_flags_and_opaque_chunks_preserved(self):
  extra=chunk('MOGX',bytes(256))+chunk('MLIQ',bytes(30))
  r=w.group(group_fixture(metadata='MPY2',extras=extra,flags2=512),4)
  self.assertIn('secondary-group-flags-or-split-group',r['unsupported'])
  self.assertIn('WMO-liquid-not-modeled',r['unsupported'])
  self.assertIn('unknown-group-chunk:MOGX',r['unsupported'])
  root=w.root(root_fixture(extras=chunk('MDDL',b'opaque')+chunk('MGI2',bytes(8))))
  self.assertIn('MDDL',root['unknownChunks']);self.assertIn('MGI2',root['unknownChunks'])
 def test_root_appearance_metadata_is_framed_and_detail_unknown_preserved(self):
  extras=(chunk('MDDI',b'')+chunk('MAVG',bytes(48))+chunk('MFOG',b'')+
          chunk('MFED',b'')+chunk('MNLD',bytes(184))+chunk('MOLV',bytes(100))+chunk('MOSI',bytes(4)))
  result=w.root(root_fixture(extras=extras))
  self.assertEqual(result['unknownChunks'],[])
  self.assertEqual(result['renderMetadata']['MNLD']['records'],1)
  empty=w.root(root_fixture(extras=chunk('MFOG',bytes(48))+chunk('MFED',b'')))
  self.assertEqual(empty['renderMetadata']['MFED']['records'],0)
  for tag,body in [('MDDI',bytes(4)),('MAVG',bytes(47)),('MNLD',bytes(183)),('MOLV',bytes(99)),('MOSI',bytes(8))]:
   with self.subTest(tag=tag):
    with self.assertRaises(ValueError):w.root(root_fixture(extras=chunk(tag,body)))
  for tag in ['MDDL','MOMX','MOPE','MGI2']:
   self.assertIn(tag,w.root(root_fixture(extras=chunk(tag,bytes(16))))['unknownChunks'])
 def test_duplicate_collision_arrays_rejected(self):
  with self.assertRaisesRegex(ValueError,'WMO-duplicate-chunk:MOVT'):
   w.group(group_fixture(extras=chunk('MOVT',bytes(12))),4)
 def test_repeated_render_arrays_preserve_collision(self):
  uv=chunk('MOTV',bytes(24));color=chunk('MOCV',bytes(12))
  before=w.group(group_fixture(),4);after=w.group(group_fixture(extras=uv+uv+color+color),4)
  self.assertEqual(before['positions'],after['positions']);self.assertEqual(before['indices'],after['indices'])
  self.assertEqual(after['renderLayers'],{'MOTV':2,'MOCV':2})
  with self.assertRaisesRegex(ValueError,'WMO-render-array-count'):
   w.group(group_fixture(extras=uv+chunk('MOTV',bytes(8))),4)
  with self.assertRaisesRegex(ValueError,'WMO-render-layer-cap'):
   w.group(group_fixture(extras=uv*5),4)
 def test_proven_render_metadata_framed_without_collision_change(self):
  before=w.group(group_fixture(),4)
  for tag,payload in [('MDAL',bytes(4)),('MFVR',bytes(2)),('MNLR',bytes(2)),('MOLP',bytes(44))]:
   with self.subTest(tag=tag):
    after=w.group(group_fixture(extras=chunk(tag,payload)),4)
    self.assertEqual(before['indices'],after['indices']);self.assertEqual(after['unsupported'],[])
    with self.assertRaises(ValueError):w.group(group_fixture(extras=chunk(tag,payload+b'!')),4)

def actual_source_audit(profile_path,output):
 raw=pathlib.Path(profile_path).read_bytes()
 if hashlib.sha256(raw).hexdigest()!='de8b30b38337373f951a4a1570dd720554cfd14aa2fb52b94f0aed966ab1abf8':raise ValueError('pinned acquisition profile differs')
 profile=json.loads(raw)
 sources={int(r['fileDataID']):r for r in profile['files']}
 counts=collections.Counter();failures=[];rootFailures=[];parsed=0;unsupported=collections.Counter();rootUnsupported=collections.Counter()
 def read(row):
  b=pathlib.Path(row['path']).read_bytes()
  if len(b)!=row['bytes'] or hashlib.sha256(b).hexdigest()!=row['sha256']:raise ValueError('source hash differs')
  return b
 for source in profile['files']:
  if source['kind']!='WMO':continue
  data=read(source);parts,_=w.table(data);h=parts['MOHD'];n=struct.unpack_from('<I',h,4)[0];lod=struct.unpack_from('<H',h,62)[0]
  ids=list(struct.unpack('<'+'I'*(len(parts['GFID'])//4),parts['GFID']))
  if len(ids)!=n*max(1,lod):raise ValueError('actual GFID framing differs')
  counts['roots']+=1;counts['baseSlots']+=n
  try:
   result=w.root(data)
   if result['groups']!=ids[:n]:raise ValueError('production base selection differs')
   rootUnsupported.update(result['unknownChunks'])
  except ValueError as exc:rootFailures.append({'fileDataID':source['fileDataID'],'reason':str(exc)})
  for index,fd in enumerate(ids):
   part='base' if index<n else 'tail'
   if not fd:
    if part=='base':raise ValueError('null actual base group')
    counts['tailZero']+=1;continue
   b=read(sources[fd]);groupParts,_=w.table(b);gp=groupParts['MOGP'];flags=struct.unpack_from('<I',gp,8)[0]
   # Inventory every occurrence, including independently framed render layers.
   tags=collections.Counter(tag for tag,a,z in t.chunks(gp,68))
   isbase=not(flags&1024) and bool(tags['MOPY'])!=bool(tags['MPY2']) and not tags['MOPB']
   istail=bool(flags&1024) and not tags['MOPY'] and not tags['MPY2'] and bool(tags['MOPB'])
   if not (isbase if part=='base' else istail):raise ValueError('actual base/tail consistency differs')
   counts[part+'Groups']+=1
   if part=='base':
    counts['baseMPY2' if tags['MPY2'] else 'baseMOPY']+=1
    try:
     result=w.group(b,struct.unpack_from('<H',h,60)[0]);parsed+=1;unsupported.update(result['unsupported'])
     if old is not None and result['triangleMetadata']=='MOPY':
      try:before=old.group(b,struct.unpack_from('<H',h,60)[0])
      except ValueError as exc:
       if str(exc) not in ('WMO-duplicate-chunk:MOTV','WMO-duplicate-chunk:MOCV'):raise
      else:
       for field in ('positions','indices','faceFlags','sourceTriangles','collisionTriangles'):
        if result[field]!=before[field]:raise ValueError('MOPY geometry regression:'+field)
    except ValueError as exc:failures.append({'fileDataID':fd,'reason':str(exc)})
 result={'format':'rikui-wmo-base-mpy2-source-audit-v1','profileSHA256':hashlib.sha256(raw).hexdigest(),
  'counts':dict(counts),'productionGroupsParsed':parsed,'productionRootFailures':rootFailures,
  'productionGroupFailures':failures,'unsupportedReasons':dict(unsupported),'rootUnsupportedChunks':dict(rootUnsupported),'nativeVerified':False}
 pathlib.Path(output).write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
 print(json.dumps({'counts':dict(counts),'productionGroupsParsed':parsed,'rootFailureReasons':dict(collections.Counter(r['reason'] for r in rootFailures)),'groupFailureReasons':dict(collections.Counter(r['reason'] for r in failures)),'unsupportedReasons':dict(unsupported),'rootUnsupportedChunks':dict(rootUnsupported)},sort_keys=True))
 if rootFailures or failures:raise ValueError('production source parser failures')
 if counts!={'roots':866,'baseSlots':4101,'baseGroups':4101,'baseMOPY':2628,'baseMPY2':1473,'tailGroups':1224,'tailZero':3255}:
  raise ValueError('pinned corpus audit counts differ')

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--source-profile');parser.add_argument('--audit-output');parser.add_argument('--baseline-parser')
 args,rest=parser.parse_known_args()
 if args.baseline_parser:old=module('baseline_wmo_probe',pathlib.Path(args.baseline_parser))
 if args.source_profile:
  if not args.audit_output:parser.error('--audit-output required')
  actual_source_audit(args.source_profile,args.audit_output)
 else:unittest.main(argv=[sys.argv[0]]+rest,verbosity=2)
