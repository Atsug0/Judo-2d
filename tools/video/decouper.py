#!/usr/bin/env python3
"""Découpe visuelle des vidéos : on repère le passage à l'écran, ffmpeg exporte le clip.

    python3 tools/video/decouper.py

Ouvre une page dans le navigateur avec la liste des vidéos de `rushes/efficientjudo/`.
On lit, on avance image par image, on pose les marqueurs début et fin, on exporte : le
clip part dans `clips/` (versionné).

Pourquoi une application locale plutôt qu'une simple page web : un navigateur ne sait
exporter que du WebM ré-encodé à la volée, que les services de mocap en ligne refusent
souvent. Ici c'est **ffmpeg** qui coupe, au cadre près et en H.264.

Le serveur n'écoute que sur la machine locale et ne sert que le dossier des rushes.
"""
import json
import os
import re
import subprocess
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import unquote

RACINE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SOURCES = os.path.join(RACINE, "rushes", "efficientjudo")
CLIPS = os.path.join(RACINE, "clips")
PORT = 8733

PAGE = """<!doctype html><meta charset="utf-8"><title>Découpe — Judo 2D</title>
<style>
 :root{--or:#e9b62c}
 *{box-sizing:border-box}
 body{margin:0;background:#120e26;color:#e9e6f5;font:14px/1.6 system-ui,sans-serif}
 header{display:flex;gap:14px;align-items:center;padding:10px 16px;background:#1c1540;
        border-bottom:2px solid #000;flex-wrap:wrap}
 h1{font-size:15px;margin:0;letter-spacing:.07em}
 main{display:flex;gap:16px;padding:16px;align-items:flex-start;flex-wrap:wrap}
 video{background:#000;width:720px;max-width:100%;display:block;border-radius:6px}
 aside{flex:1;min-width:300px;max-width:420px}
 .bloc{background:#1c1540;border:1px solid #000;border-radius:6px;padding:12px;margin-bottom:12px}
 .bloc h2{font-size:12px;margin:0 0 8px;color:var(--or);letter-spacing:.08em}
 .ligne{display:flex;gap:8px;align-items:center;margin:6px 0;flex-wrap:wrap}
 button,select,input{background:#2a1f5e;color:#e9e6f5;border:1px solid #000;border-radius:4px;
        padding:6px 10px;font:inherit;cursor:pointer}
 button:hover{background:#3b2d80}
 button.fort{background:var(--or);color:#120e26;font-weight:700}
 kbd{background:#000;border-radius:3px;padding:1px 5px;font-size:12px}
 small{color:#9a92c0}
 #duree{font-weight:700}
 #journal div{font-size:12px;padding:3px 0;border-bottom:1px solid #2a1f5e}
 .barre{position:relative;height:26px;background:#2a1f5e;border-radius:4px;margin:8px 0;cursor:pointer}
 .zone{position:absolute;top:0;bottom:0;background:rgba(233,182,44,.35)}
 .tete{position:absolute;top:-3px;bottom:-3px;width:2px;background:#fff}
</style>
<header>
  <h1>DÉCOUPE</h1>
  <select id="liste"></select>
  <span id="etat">choisis une vidéo</span>
</header>
<main>
  <div>
    <video id="v" controls></video>
    <div class="barre" id="barre"><div class="zone" id="zone"></div><div class="tete" id="tete"></div></div>
  </div>
  <aside>
    <div class="bloc">
      <h2>PASSAGE</h2>
      <div class="ligne">
        <button id="a">◀ début ici</button>
        <button id="b">fin ici ▶</button>
        <button id="va">voir le passage</button>
      </div>
      <div class="ligne">début <input id="ta" size="6" value="0"> s
                        fin <input id="tb" size="6" value="2"> s</div>
      <div class="ligne">durée <span id="duree">2.00 s</span></div>
      <small>Une projection dure <b>1,5 à 2,5 s</b>. <kbd>,</kbd> et <kbd>.</kbd> avancent
      image par image, <kbd>espace</kbd> lit ou met en pause.</small>
    </div>
    <div class="bloc">
      <h2>EXPORT</h2>
      <div class="ligne"><input id="nom" size="24" placeholder="nom du clip"></div>
      <div class="ligne"><button id="exp" class="fort">exporter le clip</button></div>
      <small>Écrit dans <code>clips/</code>, en H.264 coupé au cadre près.</small>
    </div>
    <div class="bloc"><h2>CLIPS</h2><div id="journal"></div></div>
  </aside>
</main>
<script>
const v=document.getElementById("v"), $=i=>document.getElementById(i);
let tA=0,tB=2;
fetch("/videos").then(r=>r.json()).then(l=>{
  $("liste").innerHTML=l.map(n=>`<option>${n}</option>`).join("");
  if(l.length) charge(l[0]);
});
$("liste").onchange=e=>charge(e.target.value);
function charge(n){ v.src="/video/"+encodeURIComponent(n); $("nom").value=n.replace(/\\.[^.]+$/,"");
  $("etat").textContent=n; v.onloadedmetadata=()=>{tA=0;tB=Math.min(2,v.duration);maj();}; }
function maj(){ $("ta").value=tA.toFixed(2); $("tb").value=tB.toFixed(2);
  const d=Math.max(0,tB-tA); $("duree").textContent=d.toFixed(2)+" s";
  $("duree").style.color=(d>0.5&&d<6)?"var(--or)":"#ff6b6b";
  if(v.duration){ $("zone").style.left=(100*tA/v.duration)+"%";
                  $("zone").style.width=(100*d/v.duration)+"%"; } }
v.ontimeupdate=()=>{ if(v.duration) $("tete").style.left=(100*v.currentTime/v.duration)+"%"; };
$("barre").onclick=e=>{ const r=e.currentTarget.getBoundingClientRect();
  v.currentTime=v.duration*(e.clientX-r.left)/r.width; };
$("a").onclick=()=>{tA=v.currentTime; if(tB<=tA)tB=Math.min(v.duration,tA+2); maj();};
$("b").onclick=()=>{tB=v.currentTime; maj();};
$("ta").onchange=e=>{tA=+e.target.value;maj();};
$("tb").onchange=e=>{tB=+e.target.value;maj();};
$("va").onclick=()=>{ v.currentTime=tA; v.play();
  const s=setInterval(()=>{ if(v.currentTime>=tB){v.pause();clearInterval(s);} },30); };
addEventListener("keydown",e=>{ if(e.target.tagName==="INPUT")return;
  if(e.key===",")  {v.currentTime-=1/25; e.preventDefault();}
  if(e.key===".")  {v.currentTime+=1/25; e.preventDefault();}
  if(e.key===" ")  {v.paused?v.play():v.pause(); e.preventDefault();} });
$("exp").onclick=()=>{
  if(tB-tA<0.2){alert("Passage trop court.");return;}
  $("etat").textContent="export…";
  fetch("/couper",{method:"POST",body:JSON.stringify(
    {source:$("liste").value,debut:tA,fin:tB,nom:$("nom").value})})
   .then(r=>r.json()).then(o=>{
     $("etat").textContent=o.erreur?("échec : "+o.erreur):("écrit : "+o.fichier);
     if(!o.erreur){ const d=document.createElement("div");
       d.textContent=o.fichier+"  ("+(tB-tA).toFixed(2)+" s)";
       $("journal").prepend(d); } });
};
</script>
"""


class Serveur(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _env(self, code, typ, n=0, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", typ)
        if n:
            self.send_header("Content-Length", str(n))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()

    def do_GET(self):
        if self.path == "/":
            b = PAGE.encode()
            self._env(200, "text/html; charset=utf-8", len(b))
            self.wfile.write(b)
        elif self.path == "/videos":
            noms = sorted(f for f in os.listdir(SOURCES) if f.endswith((".mp4", ".mov", ".webm")))
            b = json.dumps(noms).encode()
            self._env(200, "application/json", len(b))
            self.wfile.write(b)
        elif self.path.startswith("/video/"):
            self._video(unquote(self.path[7:]))
        else:
            self._env(404, "text/plain")

    def _video(self, nom):
        """Sert la vidéo avec les requêtes partielles : sans ça, pas de déplacement
        dans le lecteur."""
        f = os.path.join(SOURCES, os.path.basename(nom))
        if not os.path.exists(f):
            self._env(404, "text/plain")
            return
        taille = os.path.getsize(f)
        plage = self.headers.get("Range")
        a, b = 0, taille - 1
        if plage:
            m = re.match(r"bytes=(\d*)-(\d*)", plage)
            if m:
                a = int(m.group(1) or 0)
                b = int(m.group(2) or taille - 1)
        n = b - a + 1
        self._env(206 if plage else 200, "video/mp4", n,
                  {"Accept-Ranges": "bytes",
                   "Content-Range": f"bytes {a}-{b}/{taille}"} if plage else
                  {"Accept-Ranges": "bytes"})
        with open(f, "rb") as h:
            h.seek(a)
            reste = n
            while reste > 0:
                bloc = h.read(min(1 << 16, reste))
                if not bloc:
                    break
                try:
                    self.wfile.write(bloc)
                except (BrokenPipeError, ConnectionResetError):
                    return               # le lecteur a changé de position
                reste -= len(bloc)

    def do_POST(self):
        if self.path != "/couper":
            self._env(404, "text/plain")
            return
        d = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        src = os.path.join(SOURCES, os.path.basename(d["source"]))
        a, b = float(d["debut"]), float(d["fin"])
        nom = re.sub(r"[^A-Za-z0-9_\-]", "_", d.get("nom") or "clip")
        os.makedirs(CLIPS, exist_ok=True)
        dst = os.path.join(CLIPS, f"{nom}_{a:.1f}-{b:.1f}.mp4".replace(".", "_", 0))
        # ré-encodage : la copie de flux ne coupe qu'aux images clés, donc à la demi-seconde près
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{a:.3f}", "-to", f"{b:.3f}",
                            "-i", src, "-c:v", "libx264", "-crf", "18", "-preset", "veryfast",
                            "-pix_fmt", "yuv420p", "-an", dst], capture_output=True, text=True)
        out = ({"erreur": r.stderr.strip()[:200]} if r.returncode
               else {"fichier": os.path.relpath(dst, RACINE)})
        bs = json.dumps(out).encode()
        self._env(200, "application/json", len(bs))
        self.wfile.write(bs)


if __name__ == "__main__":
    if not os.path.isdir(SOURCES):
        sys.exit(f"dossier introuvable : {SOURCES}")
    srv = HTTPServer(("127.0.0.1", PORT), Serveur)
    url = f"http://127.0.0.1:{PORT}/"
    print(f"découpe ouverte sur {url}  (Ctrl+C pour arrêter)")
    threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\narrêt")
