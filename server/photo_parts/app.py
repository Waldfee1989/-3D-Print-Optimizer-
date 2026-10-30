import hmac
import json
import multiprocessing
import os
import threading
import time
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from .geometry import build_stl
from .vision import analyze, validate_plan

MAX_BODY=32*1024*1024
gate=threading.BoundedSemaphore(1)
recent=[]
rate_lock=threading.Lock()


def mesh_worker(pipe, plan, answers, approved):
    try:
        if os.name=='posix':
            import resource
            resource.setrlimit(resource.RLIMIT_AS,(1024*1024*1024,1024*1024*1024))
            resource.setrlimit(resource.RLIMIT_CPU,(40,40))
        pipe.send((True,build_stl(plan,answers,approved)))
    except Exception as e:
        pipe.send((False,str(e) if isinstance(e,ValueError) else 'Modell konnte nicht erzeugt werden.'))
    finally: pipe.close()


def generate(plan, answers, approved):
    # Own process: no geometry job can block the service indefinitely.
    context=multiprocessing.get_context('spawn')
    reader,writer=context.Pipe(duplex=False)
    process=context.Process(target=mesh_worker,args=(writer,plan,answers,approved))
    process.start();writer.close()
    try:
        if not reader.poll(45): raise ValueError('Die Geometrieberechnung dauerte zu lange.')
        success,result=reader.recv()
        if not success: raise ValueError(result)
        return result
    finally:
        reader.close()
        if process.is_alive(): process.terminate()
        process.join(timeout=3)


class Handler(BaseHTTPRequestHandler):
    server_version='PhotoParts/1'
    def log_message(self,*args): pass  # Never log photos, answers, auth or keys.
    def reply(self,status,payload,mime='application/json'):
        data=json.dumps(payload,ensure_ascii=False).encode() if mime=='application/json' else payload
        self.send_response(status);self.send_header('Content-Type',mime);self.send_header('Content-Length',str(len(data)))
        self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(data)
    def do_POST(self):
        token=os.environ.get('PHOTO_PART_ACCESS_TOKEN','')
        if len(token)<32:
            self.reply(503,{'error':'Der Fotodienst ist noch nicht eingerichtet.'});return
        if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+token):
            self.reply(401,{'error':'Zugangscode des Fotodienstes ist ungültig.'});return
        if self.path not in ['/v1/analyze','/v1/generate']:
            self.reply(404,{'error':'Unbekannte Anfrage.'});return
        try:
            size=int(self.headers.get('Content-Length','0'))
            if not 0<size<=MAX_BODY: raise ValueError('Die Fotos überschreiten die zulässige Anfragegröße.')
            if self.headers.get('Transfer-Encoding'): raise ValueError('Nicht unterstützte Übertragung.')
            self.connection.settimeout(45)
            raw=self.rfile.read(size)
            if len(raw)!=size: raise ValueError('Die Übertragung ist unvollständig.')
            data=json.loads(raw)
            answers=data.get('answers',{})
            if not isinstance(answers,dict) or len(answers)>32 or any(not isinstance(k,str) or len(k)>48 or type(v) not in (str,int,float) or isinstance(v,str) and len(v)>500 for k,v in answers.items()): raise ValueError('Ungültige Maßantworten.')
        except (ValueError,TypeError,KeyError,TimeoutError):
            self.reply(400,{'error':'Ungültige oder zu große Anfrage.'});return
        if not gate.acquire(blocking=False):
            self.reply(429,{'error':'Der Fotodienst arbeitet bereits. Bitte kurz warten.'});return
        try:
            if self.path=='/v1/analyze':
                key=os.environ.get('OPENAI_API_KEY','');model=os.environ.get('PHOTO_PART_MODEL','')
                if not key or not model:
                    self.reply(503,{'error':'Die Bilderkennung ist noch nicht eingerichtet.'});return
                with rate_lock:
                    now=time.monotonic();recent[:]=[v for v in recent if now-v<3600]
                    if len(recent)>=int(os.environ.get('PHOTO_PART_HOURLY_LIMIT','30')):
                        self.reply(429,{'error':'Das Stundenlimit des Fotodienstes ist erreicht.'});return
                    recent.append(now)
                images=data['images'];previous=data.get('previous')
                if previous is not None: validate_plan(previous,len(images))
                plan=analyze(images,answers,previous,key,model)
                self.reply(200,plan)
            else:
                plan=validate_plan(data['plan'],int(data['image_count']))
                # Every numeric answer, including the initial scale, must be
                # represented in the model's dimension contract.
                known={d['id'] for d in plan['dimensions']}
                if any(k not in known for k in answers): raise ValueError('Bestätigte Angaben fehlen im Modell.')
                stl=generate(plan,answers,data.get('assumptions_accepted') is True)
                self.reply(200,stl,'model/stl')
        except urllib.error.HTTPError:
            self.reply(502,{'error':'Die Bilderkennung hat die Anfrage abgewiesen. Bitte die Diensteinstellung prüfen.'})
        except (ValueError,KeyError,TypeError,SyntaxError):
            self.reply(422,{'error':'Die Analyse oder Geometrie ist nicht eindeutig gültig. Angaben prüfen oder weitere Ansichten verwenden.'})
        except Exception:
            self.reply(502,{'error':'Der Fotodienst konnte die Anfrage nicht beenden. Bitte erneut versuchen.'})
        finally: gate.release()


def main():
    # Production: put behind HTTPS; only expose an authenticated private service.
    ThreadingHTTPServer((os.environ.get('BIND','127.0.0.1'),int(os.environ.get('PORT','8080'))),Handler).serve_forever()


if __name__=='__main__': main()
