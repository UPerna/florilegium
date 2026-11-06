"""Bind native CI artifacts to the current checkout, then test real browser consumers."""
import argparse,functools,hashlib,http.server,json,pathlib,subprocess,sys,tempfile,threading,zipfile
from clicheck import fingerprint
from webpackage import package as webpackage
from package import package
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--native',type=pathlib.Path,required=True);parser.add_argument('--playwright',required=True);parser.add_argument('--executable');args=parser.parse_args()
 digest=fingerprint();candidates=[]
 for p in args.native.rglob('receipt.json'):
  if 'cli' not in p.parts:continue
  data=json.loads(p.read_text(encoding='utf8'))
  if data.get('source_digest')==digest and len(data.get('families',{}))==22:candidates.append(p)
 assert len(candidates)==1,('Current-checkout native CLI evidence not uniquely found',digest,candidates)
 native=candidates[0];web=webpackage();out=ROOT/'build/browser-check';out.mkdir(parents=True,exist_ok=True)
 # Independently enumerate and hash precisely the CLI consumer's source inputs.
 paths=[*ROOT.glob('*.lua'),*ROOT.glob('examples/cli/*.recipe'),*ROOT.glob('examples/cli/*.json')]
 paths.extend(ROOT/'tools'/name for name in('pattern.py','pattern-driver.lua','clicheck.py','cli_failcheck.py'))
 files={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()for p in sorted(paths)}
 assert hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()==digest
 guard=out/'native-source-guard.json';guard.write_text(json.dumps({'source_digest':digest,'files':files},indent=2)+'\n',encoding='utf8')
 canonical={p.relative_to(web).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()for p in web.rglob('*')if p.is_file()}
 archive=package();archive_hash=hashlib.sha256(archive.read_bytes()).hexdigest();assert hashlib.sha256(package().read_bytes()).hexdigest()==archive_hash
 with tempfile.TemporaryDirectory(prefix='florilegium-browser-kit-')as temporary:
  base=pathlib.Path(temporary)
  with zipfile.ZipFile(archive)as z:
   for member in z.infolist():assert(base/member.filename).resolve().is_relative_to(base.resolve())
   z.extractall(base)
  kit=base/'florilegium'
  for row in(kit/'SHA256SUMS').read_text(encoding='utf8').splitlines():
   sha,name=row.split('  ',1);assert hashlib.sha256((kit/name).read_bytes()).hexdigest()==sha,name
  subprocess.run([sys.executable,str(kit/'tools/webpackage.py')],check=True,capture_output=True)
  extracted={p.relative_to(kit/'build/web').as_posix():hashlib.sha256(p.read_bytes()).hexdigest()for p in(kit/'build/web').rglob('*')if p.is_file()}
  assert extracted==canonical,'Extracted source kit browser assets differ'
 binding={'status':'passed','native_cli_source_digest':digest,'native_receipt_sha256':hashlib.sha256(native.read_bytes()).hexdigest(),'source_kit_sha256':archive_hash,'source_kit_browser_files_equal':canonical}
 (out/'native-and-kit-binding.json').write_text(json.dumps(binding,indent=2)+'\n',encoding='utf8')
 handler=functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(web))
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 try:
  common=['--url',f'http://127.0.0.1:{server.server_port}/runtime.html','--playwright',args.playwright]
  if args.executable:common+=['--executable',args.executable]
  subprocess.run(['node',str(ROOT/'tools/browsercheck.cjs'),*common,'--reference',str(native),'--native-sources',str(guard),'--python',sys.executable],cwd=ROOT,check=True,timeout=1800)
  subprocess.run(['node',str(ROOT/'tools/browser-adversarial.cjs'),*common],cwd=ROOT,check=True,timeout=300)
  editor_common=['--url',f'http://127.0.0.1:{server.server_port}/','--playwright',args.playwright]
  if args.executable:editor_common+=['--executable',args.executable]
  subprocess.run(['node',str(ROOT/'tools/editorcheck.cjs'),*editor_common],cwd=ROOT,check=True,timeout=2400)
  subprocess.run([sys.executable,str(ROOT/'tools/editor_vectors.py'),str(ROOT/'build/editor-check')],cwd=ROOT,check=True,timeout=120)
 finally:server.shutdown();server.server_close()
 print('Native-bound browser family/adversarial/sourcekit gates passed',digest)
if __name__=='__main__':main()
