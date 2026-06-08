#!/usr/bin/env python3
"""
todo webui — 폰용 인터랙티브 todo 관리 (ai-debate A+D 권고 구현).

설계 원칙:
- CRUD는 Claude 세션 불필요. 같은 머신의 이 서버가 todoctl.py 를 직접(argv 배열, shell 미사용) 호출.
- 진실원본 = SQLite todo.db. 단일 writer = todoctl. 이 서버도 todoctl 만 거침(직접 DB 쓰기 금지).
- Tailscale 인터페이스에만 바인드(0.0.0.0 금지). Basic auth(계정 raion / 비번=.token).
- 상태변경(POST)은 커스텀 헤더 X-Todo-CSRF 필수 → 크로스사이트 폼 위조 차단(프리플라이트).
- 출력은 클라이언트에서 textContent 로만 렌더(XSS 방지).
"""
import base64
import html
import json
import os
import secrets
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
TODOCTL = "/home/gmoh/raion/todo-sync/todoctl.py"
TOKEN_PATH = os.path.join(HERE, ".token")
BIND_IP = os.environ.get("TODO_WEBUI_IP", "100.80.47.22")  # Tailscale IP
BIND_PORT = int(os.environ.get("TODO_WEBUI_PORT", "8787"))
USER = "raion"
MAX_TITLE = 300
MAX_NOTE = 1000
PRIO_OK = {"high", "med", "low"}


def load_or_make_token():
    if os.path.exists(TOKEN_PATH):
        return open(TOKEN_PATH).read().strip()
    tok = secrets.token_urlsafe(18)
    fd = os.open(TOKEN_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, (tok + "\n").encode())
    os.close(fd)
    return tok


TOKEN = load_or_make_token()


def load_vocab():
    """config.json 의 사전 정의 태그 어휘(없으면 기본값)."""
    try:
        with open(os.path.join(os.path.dirname(TODOCTL), "config.json")) as f:
            v = json.load(f).get("tags")
        if isinstance(v, list) and v:
            return v
    except Exception:
        pass
    return ["긴급", "중요", "개발", "회사", "인사", "회의", "개인", "기타"]


VOCAB = load_vocab()


def run_todoctl(args):
    """todoctl 을 argv 배열로만 호출. shell 미사용. 결과 (rc, stdout, stderr)."""
    try:
        p = subprocess.run(
            [sys.executable, TODOCTL, *args],
            capture_output=True, text=True, timeout=15,
            cwd=os.path.dirname(TODOCTL),  # todoctl 은 상대경로 todo.db → CWD 고정
        )
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 1, "", "timeout"


def slim_one(t):
    """무거운 events 배열을 떼고 note 이벤트만 notelog(최근 8)로 남김."""
    ev = t.pop("events", None) or []
    notes = [
        {"ts": e.get("ts"), "detail": e.get("detail")}
        for e in ev if e.get("event") == "note"
    ]
    t["notelog"] = notes[-8:]
    return t


PAGE = """<!DOCTYPE html>
<html lang="ko"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>업무 todo</title>
<style>
 :root{--bg:#0f1115;--card:#1b1f27;--line:#2c313c;--tx:#eef1f6;--mut:#aab3c2;--acc:#5b9dff;--ok:#7ee787;--warn:#ffb454;--danger:#ff7b72}
 *{box-sizing:border-box}
 html{-webkit-text-size-adjust:100%}
 body{margin:0;background:var(--bg);color:var(--tx);font-family:-apple-system,BlinkMacSystemFont,"Noto Sans KR",sans-serif;font-size:18px;line-height:1.55}
 .wrap{max-width:720px;margin:0 auto;padding:16px 14px 100px}
 h1{font-size:24px;margin:8px 2px 18px;font-weight:700}
 .add{display:grid;grid-template-columns:1fr;gap:10px;margin-bottom:18px}
 .addrow2{display:flex;gap:10px}
 .add input,.add select,.add button{font-size:17px}
 .add input[type=text]{width:100%;padding:14px;border-radius:12px;border:1px solid var(--line);background:#0c0e13;color:var(--tx)}
 .searchbar{display:flex;gap:8px;align-items:center;margin-bottom:10px}
 .searchbar input{flex:1;min-width:0;font-size:17px;padding:13px 14px;border-radius:12px;border:1px solid var(--line);background:#0c0e13;color:var(--tx)}
 .searchbar button{padding:0 16px;min-height:48px}
 .chips{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:6px}
 .chip{font-size:14px;padding:8px 13px;border-radius:999px;border:1px solid var(--line);background:var(--card);color:var(--mut);cursor:pointer;min-height:0}
 .chip.on{background:#22314f;color:#cfe0ff;border-color:#3a4d78}
 .picklab{font-size:13px;color:var(--mut);margin:2px 2px 2px}
 .pickchips{display:flex;flex-wrap:wrap;gap:8px}
 .pick{font-size:15px;padding:9px 14px;border-radius:999px;border:1px solid var(--line);background:#0c0e13;color:var(--mut);cursor:pointer;min-height:0}
 .pick.on{background:#1d3a2a;color:#9ff0c0;border-color:#2f6b4a}
 .tags{margin-top:7px;display:flex;flex-wrap:wrap;gap:6px}
 .tag{font-size:12.5px;padding:3px 9px;border-radius:999px;background:#1d2740;color:#9fc0ff;border:1px solid #2c3a5c}
 .add input[type=date]{flex:1;min-width:0;padding:13px;border-radius:12px;border:1px solid var(--line);background:#0c0e13;color:var(--tx)}
 select{padding:13px;border-radius:12px;border:1px solid var(--line);background:#0c0e13;color:var(--tx)}
 button{font-size:17px;padding:14px 18px;border-radius:12px;border:1px solid var(--line);background:#22314f;color:#cfe0ff;font-weight:600;min-height:50px;cursor:pointer}
 button.ghost{background:var(--card)}
 .add button{white-space:nowrap}
 .item{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:15px 16px;margin:12px 0}
 .item.high{border-left:5px solid var(--danger)}
 .row{display:flex;align-items:flex-start;gap:10px}
 .title{flex:1;font-size:19px;font-weight:600;word-break:keep-all;line-height:1.4}
 .meta{color:var(--mut);font-size:14.5px;margin-top:7px}
 .desc{font-size:15.5px;margin-top:8px;color:#d4dae6;line-height:1.5;white-space:pre-wrap;word-break:break-word}
 .desc.clip{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
 .morebtn{background:none;border:none;color:var(--acc);font-size:14px;padding:4px 0;min-height:0;font-weight:600}
 .log{margin-top:10px;border-top:1px dashed var(--line);padding-top:8px}
 .log .l{font-size:14px;color:var(--mut);margin:4px 0;display:flex;gap:8px}
 .log .l .lt{color:#7f8a9c;flex-shrink:0}
 .done .title{text-decoration:line-through;color:var(--mut)}
 .acts{display:flex;gap:10px;margin-top:13px;flex-wrap:wrap}
 .acts button{padding:11px 16px;font-size:15px;min-height:46px}
 .doneb{background:#13311f;color:var(--ok)}
 .secbar{display:flex;justify-content:space-between;align-items:center;margin:22px 2px 8px;gap:10px}
 .secbar h2{font-size:16px;color:var(--mut);margin:0}
 .secbar button{font-size:15px;padding:10px 14px;min-height:44px}
 #msg{position:fixed;left:0;right:0;bottom:0;background:#22314f;color:#cfe0ff;padding:15px;text-align:center;font-size:16px;transform:translateY(100%);transition:.2s}
 #msg.show{transform:translateY(0)}
 .note-in{width:100%;margin-top:10px;font-size:16px;padding:13px;border-radius:10px;border:1px solid var(--line);background:#0c0e13;color:var(--tx)}
 #agenda{margin-bottom:6px}
 .adate{font-size:14px;color:var(--mut);font-weight:700;margin:14px 2px 4px;border-bottom:1px solid var(--line);padding-bottom:4px}
 .adate.today{color:var(--acc)}
 .adate.over{color:var(--danger)}
 .aitem{padding:10px 12px;margin:6px 0;background:var(--card);border:1px solid var(--line);border-radius:10px;font-size:15.5px;cursor:pointer}
 .aitem.high{border-left:4px solid var(--danger)}
 .ameet{padding:10px 12px;margin:6px 0;background:#16203a;border:1px solid #33406a;border-radius:10px;font-size:15px;color:#cfe0ff}
</style></head><body>
<div class="wrap">
 <h1>업무 todo</h1>
 <div class="add">
  <input id="t" type="text" placeholder="할 일 추가…" autocomplete="off">
  <div class="picklab">태그(여러 개 선택 가능)</div>
  <div id="addtags" class="pickchips"></div>
  <div class="addrow2">
   <input id="due" type="text" inputmode="numeric" maxlength="6" placeholder="마감 yymmdd (예: 260609, 비우면 없음)">
   <button onclick="add()">추가</button>
  </div>
 </div>
 <div class="searchbar"><input id="q" type="search" placeholder="🔍 검색 — 제목·메모·태그" autocomplete="off"><button class="ghost" id="qx" onclick="clearSearch()" style="display:none">✕</button></div>
 <div id="chips" class="chips"></div>
 <div class="secbar"><button class="ghost" id="caltoggle" onclick="toggleCal()">📅 마감 일정 보기 ▾</button></div>
 <div id="agenda" style="display:none"></div>
 <div class="secbar"><h2>진행 중</h2><button class="ghost" onclick="load()">새로고침</button></div>
 <div id="active"></div>
 <div class="secbar"><button class="ghost" id="donetoggle" onclick="toggleDone()">완료 0개 ▾</button></div>
 <div id="done" style="display:none"></div>
</div>
<div id="msg"></div>
<script>
const CSRF="1";
const TAGS=__TAGVOCAB__;
function urg(t){const a=String(t.tags||'').split(',');return a.includes('긴급')?'긴급':a.includes('중요')?'중요':'';}
function buildAddTags(){
 const box=document.getElementById('addtags');box.innerHTML='';
 TAGS.forEach(tg=>{const c=el('button','pick','#'+tg);c.dataset.tag=tg;c.onclick=()=>c.classList.toggle('on');box.appendChild(c);});
}
function selectedAddTags(){return Array.from(document.querySelectorAll('#addtags .pick.on')).map(c=>c.dataset.tag);}
function clearAddTags(){document.querySelectorAll('#addtags .pick.on').forEach(c=>c.classList.remove('on'));}
function toast(s){const m=document.getElementById('msg');m.textContent=s;m.classList.add('show');setTimeout(()=>m.classList.remove('show'),1800);}
async function api(path,method,body){
 const o={method,headers:{'X-Todo-CSRF':CSRF}};
 if(body){o.headers['Content-Type']='application/json';o.body=JSON.stringify(body);}
 const r=await fetch(path,o);
 if(!r.ok){toast('오류 '+r.status);throw new Error(r.status);}
 return r.json();
}
function el(tag,cls,txt){const e=document.createElement(tag);if(cls)e.className=cls;if(txt!=null)e.textContent=txt;return e;}
function card(t){
 const u=urg(t);
 const d=el('div','item'+(u==='긴급'?' high':'')+(t.status==='done'?' done':''));
 const row=el('div','row');
 const ti=el('div','title',(u==='긴급'?'🔴 ':u==='중요'?'⭐ ':'')+t.title);
 row.appendChild(ti);d.appendChild(row);
 let meta='#'+t.task_id+' · '+t.status;
 if(t.due_at)meta+=' · 기한 '+t.due_at;
 if(t.source)meta+=' · '+t.source;
 d.appendChild(el('div','meta',meta));
 // 태그 칩(누르면 그 태그로 필터).
 if(t.tags){
  const tw=el('div','tags');
  String(t.tags).split(',').filter(Boolean).forEach(tag=>{
   const e=el('span','tag','#'+tag);e.onclick=()=>setTag(tag);tw.appendChild(e);
  });
  d.appendChild(tw);
 }
 // 설명(add 시 입력한 notes 필드) — 길면 3줄로 접고 더보기.
 if(t.notes){
  const desc=el('div','desc clip',t.notes);
  d.appendChild(desc);
  if(t.notes.length>120){
   const mb=el('button','morebtn','더보기 ▾');
   mb.onclick=()=>{const c=desc.classList.toggle('clip');mb.textContent=c?'더보기 ▾':'접기 ▴';};
   d.appendChild(mb);
  }
 }
 // 진행 로그(메모 버튼으로 쌓인 note 이벤트들).
 if(t.notelog&&t.notelog.length){
  const lg=el('div','log');
  t.notelog.forEach(n=>{
   const l=el('div','l');
   l.appendChild(el('span','lt',(n.ts||'').slice(5,10)));
   l.appendChild(el('span',null,n.detail||''));
   lg.appendChild(l);
  });
  d.appendChild(lg);
 }
 const acts=el('div','acts');
 if(t.status!=='done'){
  const b=el('button','doneb','완료');b.onclick=()=>act('done',t.task_id);acts.appendChild(b);
 }else{
  const b=el('button','ghost','되돌리기');b.onclick=()=>act('reopen',t.task_id);acts.appendChild(b);
 }
 const nb=el('button','ghost','메모');nb.onclick=()=>{
  if(d.querySelector('.note-in'))return;
  const inp=el('input','note-in');inp.placeholder='진행 로그 한 줄…';
  inp.onkeydown=(e)=>{if(e.key==='Enter'&&inp.value.trim()){note(t.task_id,inp.value.trim());}};
  d.appendChild(inp);inp.focus();
 };acts.appendChild(nb);
 d.appendChild(acts);
 return d;
}
let _todos=[];        // /api/list 전체
let _search=null;     // 검색 중이면 결과 배열, 아니면 null
let _filterTag=null;  // 선택된 태그(null=전체)
async function load(){
 _todos=await api('/api/list','GET');
 renderAll();
}
function setTag(tag){_filterTag=(_filterTag===tag?null:tag);renderAll();}
function passTag(t){
 if(!_filterTag)return true;
 return String(t.tags||'').split(',').filter(Boolean).includes(_filterTag);
}
function buildChips(){
 const box=document.getElementById('chips');box.innerHTML='';
 const cnt={};
 _todos.filter(t=>t.status!=='done').forEach(t=>
  String(t.tags||'').split(',').filter(Boolean).forEach(tg=>cnt[tg]=(cnt[tg]||0)+1));
 const tags=Object.keys(cnt).sort((a,b)=>cnt[b]-cnt[a]||(a<b?-1:1));
 if(!tags.length){return;}
 const all=el('button','chip'+(_filterTag===null?' on':''),'전체');
 all.onclick=()=>{_filterTag=null;renderAll();};box.appendChild(all);
 tags.forEach(tg=>{
  const c=el('button','chip'+(_filterTag===tg?' on':''),'#'+tg+' '+cnt[tg]);
  c.onclick=()=>setTag(tg);box.appendChild(c);
 });
}
function renderAll(){
 buildChips();
 const src=(_search!==null?_search:_todos).filter(passTag);
 const A=document.getElementById('active'),D=document.getElementById('done');
 A.innerHTML='';D.innerHTML='';
 const act=src.filter(t=>t.status!=='done'),dn=src.filter(t=>t.status==='done');
 if(!act.length)A.appendChild(el('div','meta',_search!==null?'(검색 결과 없음)':'(없음)'));
 act.forEach(t=>A.appendChild(card(t)));
 dn.slice(-15).reverse().forEach(t=>D.appendChild(card(t)));
 const tg=document.getElementById('donetoggle');
 const more=dn.length>15?' (최근 15)':'';
 tg.textContent=(_search!==null?'검색·완료 ':'완료 ')+dn.length+'개'+more+(D.style.display==='none'?' ▾':' ▴');
 if(document.getElementById('agenda').style.display!=='none')buildAgenda();
}
let _qtimer=null;
function onSearch(){
 const q=document.getElementById('q').value.trim();
 document.getElementById('qx').style.display=q?'block':'none';
 clearTimeout(_qtimer);
 _qtimer=setTimeout(async()=>{
  if(!q){_search=null;renderAll();return;}
  try{_search=await api('/api/search?q='+encodeURIComponent(q),'GET');}
  catch(e){_search=[];}
  renderAll();
 },250);
}
function clearSearch(){
 document.getElementById('q').value='';_search=null;
 document.getElementById('qx').style.display='none';renderAll();
}
// ── 마감 일정 뷰: 마감일 있는 todo 를 날짜별로(지연 + 앞으로 21일) ──
const WD=['일','월','화','수','목','금','토'];
function ymd(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');}
function toggleCal(){
 const a=document.getElementById('agenda');const show=a.style.display==='none';
 a.style.display=show?'block':'none';
 document.getElementById('caltoggle').textContent='📅 마감 일정 '+(show?'숨기기 ▴':'보기 ▾');
 if(show)buildAgenda();
}
function agItem(t){
 const u=urg(t);
 const e=el('div','aitem'+(u==='긴급'?' high':''),(u==='긴급'?'🔴 ':u==='중요'?'⭐ ':'')+'#'+t.task_id+' '+t.title);
 e.onclick=()=>{const A=document.getElementById('active');A.scrollIntoView({behavior:'smooth',block:'start'});};
 return e;
}
function buildAgenda(){
 const A=document.getElementById('agenda');A.innerHTML='';
 const todos=_todos.filter(t=>t.status!=='done'&&t.due_at);
 const base=new Date();base.setHours(0,0,0,0);
 const todayKey=ymd(base);
 const over=todos.filter(t=>String(t.due_at).slice(0,10)<todayKey).sort((a,b)=>a.due_at<b.due_at?-1:1);
 if(over.length){
  A.appendChild(el('div','adate over','⚠️ 지연'));
  over.forEach(t=>A.appendChild(agItem(t)));
 }
 for(let i=0;i<21;i++){
  const d=new Date(base);d.setDate(base.getDate()+i);const key=ymd(d);
  const items=todos.filter(t=>String(t.due_at).slice(0,10)===key);
  if(!items.length)continue;
  const lab=(i===0?'오늘 · ':'')+key.slice(5)+' ('+WD[d.getDay()]+')';
  A.appendChild(el('div','adate'+(i===0?' today':''),lab));
  items.forEach(t=>A.appendChild(agItem(t)));
 }
 if(!A.children.length)A.appendChild(el('div','meta','마감 있는 할 일 없음'));
}
function toggleDone(){
 const D=document.getElementById('done');
 D.style.display=(D.style.display==='none')?'block':'none';
 load();
}
function parseDue(v){
 v=(v||'').replace(/[^0-9]/g,'');
 if(!v)return null;            // 빈 값 = 마감 없음
 if(v.length!==6)return undefined;   // 형식 오류
 const mm=+v.slice(2,4),dd=+v.slice(4,6);
 if(mm<1||mm>12||dd<1||dd>31)return undefined;
 return '20'+v.slice(0,2)+'-'+v.slice(2,4)+'-'+v.slice(4,6);
}
async function add(){
 const t=document.getElementById('t'),due=document.getElementById('due');
 if(!t.value.trim())return;
 const dv=parseDue(due.value);
 if(dv===undefined){toast('마감은 yymmdd 6자리 (예: 260609)');return;}
 const tags=selectedAddTags();
 await api('/api/add','POST',{title:t.value.trim(),due:dv,tags:tags.length?tags.join(','):null});
 t.value='';due.value='';clearAddTags();toast('추가됨');load();
}
async function act(a,id){await api('/api/'+a,'POST',{id});toast(a==='done'?'완료':'되돌림');load();}
async function note(id,text){await api('/api/note','POST',{id,text});toast('메모 추가');load();}
document.getElementById('q').addEventListener('input',onSearch);
document.getElementById('t').addEventListener('keydown',e=>{if(e.key==='Enter')add();});
buildAddTags();
load();
</script></body></html>
"""

LOGIN_PAGE = """<!DOCTYPE html>
<html lang="ko"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>로그인 · 업무 todo</title>
<style>
 body{margin:0;background:#0f1115;color:#e7eaf0;font-family:-apple-system,BlinkMacSystemFont,"Noto Sans KR",sans-serif;font-size:17px}
 .box{max-width:420px;margin:18vh auto 0;padding:24px;background:#1b1f27;border:1px solid #2c313c;border-radius:14px}
 h1{font-size:19px;margin:0 0 16px}
 input{width:100%;font-size:16px;padding:13px;border-radius:10px;border:1px solid #2c313c;background:#0c0e13;color:#e7eaf0;margin-bottom:12px}
 button{width:100%;font-size:16px;padding:13px;border-radius:10px;border:1px solid #2c313c;background:#22314f;color:#cfe0ff;font-weight:600;min-height:48px}
 .mut{color:#9aa3b2;font-size:13px;margin-top:10px;line-height:1.5}
 .err{color:#ff7b72;font-size:14px;margin-bottom:10px}
</style></head><body>
<div class="box">
 <h1>업무 todo · 로그인</h1>
 __ERR__
 <input id="tok" type="password" placeholder="토큰" autocomplete="current-password" autofocus>
 <button onclick="go()">접속</button>
 <div class="mut">토큰은 한 번만 입력하면 이 기기에 저장됩니다(쿠키, 1년).</div>
</div>
<script>
function go(){const t=document.getElementById('tok').value.trim();if(!t)return;location.href='/login?t='+encodeURIComponent(t);}
document.getElementById('tok').addEventListener('keydown',e=>{if(e.key==='Enter')go();});
</script></body></html>
"""


class H(BaseHTTPRequestHandler):
    server_version = "todowebui/1.0"

    def _cookie_token(self):
        raw = self.headers.get("Cookie", "")
        for part in raw.split(";"):
            k, _, v = part.strip().partition("=")
            if k == "todoauth":
                return v
        return None

    def _auth_ok(self):
        # 배포정책: 공개 터널 미사용(회사/Tailscale 전용). 그래서 localhost(데스크탑)는 면제,
        # 비-localhost(Tailscale 폰·LAN)는 토큰(쿠키 또는 Basic) 요구.
        # ⚠️ 다시 공개 터널(cloudflared 등)로 노출할 거면 이 면제를 반드시 제거할 것
        #    (터널은 localhost 로 포워딩 → 면제 두면 무인증 공개됨).
        if self.client_address and self.client_address[0] in ("127.0.0.1", "::1"):
            return True
        # 쿠키 로그인(폰 브라우저용 — fetch 가 same-origin 쿠키를 자동 전송).
        ck = self._cookie_token()
        if ck and secrets.compare_digest(ck, TOKEN):
            return True
        # Basic auth(curl·기존 클라이언트 호환).
        h = self.headers.get("Authorization", "")
        if h.startswith("Basic "):
            try:
                dec = base64.b64decode(h[6:]).decode()
                u, _, p = dec.partition(":")
                if secrets.compare_digest(u, USER) and secrets.compare_digest(p, TOKEN):
                    return True
            except Exception:
                pass
        return False

    def _do_login(self):
        # GET /login?t=TOKEN → 검증 성공 시 HttpOnly 쿠키 설정 후 / 로 리다이렉트.
        q = parse_qs(urlparse(self.path).query)
        t = (q.get("t") or [""])[0]
        if t and secrets.compare_digest(t, TOKEN):
            self.send_response(303)
            # SameSite=Lax: QR 스캐너(외부 앱)에서 /login 진입 시 top-level GET 네비게이션이라
            # 리다이렉트된 / 요청에 쿠키가 실린다(Strict면 첫 요청에 누락되어 로그인폼으로 떨어짐).
            # POST 는 X-Todo-CSRF 헤더로 별도 보호 → Lax 여도 CSRF 안전.
            self.send_header(
                "Set-Cookie",
                "todoauth=%s; HttpOnly; SameSite=Lax; Path=/; Max-Age=31536000" % TOKEN,
            )
            self.send_header("Location", "/")
            self.end_headers()
            return
        # 실패 → 에러 표시한 로그인 폼.
        page = LOGIN_PAGE.replace("__ERR__", '<div class="err">토큰이 올바르지 않습니다.</div>')
        self._serve_html(page, code=401)

    def _serve_html(self, page, code=200):
        b = page.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _need_auth(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="todo"')
        self.end_headers()

    def _json(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_GET(self):
        if self.path.startswith("/login"):
            return self._do_login()
        if not self._auth_ok():
            # 폰 브라우저: 첫 페이지 요청이면 토큰 입력 폼 제공(빈 401 대신).
            if self.path == "/" or self.path.startswith("/?"):
                return self._serve_html(LOGIN_PAGE.replace("__ERR__", ""))
            return self._need_auth()
        if self.path == "/" or self.path.startswith("/?"):
            return self._serve_html(
                PAGE.replace("__TAGVOCAB__", json.dumps(VOCAB, ensure_ascii=False))
            )
        if self.path == "/api/list":
            rc, out, err = run_todoctl(["json", "--all"])
            if rc != 0:
                return self._json(500, {"error": err})
            try:
                data = json.loads(out)
            except Exception:
                return self._json(500, {"error": "json parse"})
            # 페이로드 경량화: 무거운 events 배열은 떼되, note(메모) 이벤트만 최근 8개
            # 추려 notelog 로 실어 UI에 표시. 완료는 최근 30개만 → 응답 크기 고정.
            active = [t for t in data if t.get("status") != "done"]
            done = [t for t in data if t.get("status") == "done"][-30:]
            return self._json(200, [slim_one(t) for t in active + done])
        if self.path.startswith("/api/search"):
            q = (parse_qs(urlparse(self.path).query).get("q") or [""])[0].strip()
            if not q or len(q) > 100:
                return self._json(200, [])
            rc, out, err = run_todoctl(["search", q, "--json", "--all"])
            if rc != 0:
                return self._json(500, {"error": err})
            try:
                data = json.loads(out)
            except Exception:
                return self._json(500, {"error": "json parse"})
            return self._json(200, [slim_one(t) for t in data])
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if not self._auth_ok():
            return self._need_auth()
        if self.headers.get("X-Todo-CSRF") != "1":
            return self._json(403, {"error": "csrf"})
        ln = int(self.headers.get("Content-Length", "0") or 0)
        if ln > 8192:
            return self._json(413, {"error": "too large"})
        try:
            body = json.loads(self.rfile.read(ln) or b"{}")
        except Exception:
            return self._json(400, {"error": "bad json"})

        if self.path == "/api/add":
            title = str(body.get("title", "")).strip()
            if not title or len(title) > MAX_TITLE:
                return self._json(400, {"error": "title"})
            args = ["add", title]
            due = body.get("due")
            if due:
                due = str(due)[:10]
                if len(due) == 10 and due[4] == "-" and due[7] == "-":
                    args += ["--due", due]
            prio = body.get("prio")
            if prio in PRIO_OK:
                args += ["--prio", prio]
            tags = body.get("tags")
            if tags and isinstance(tags, str) and len(tags) <= 200:
                args += ["--tags", tags]
            args += ["--source", "webui"]
            rc, out, err = run_todoctl(args)
            return self._json(200 if rc == 0 else 500, {"out": out, "err": err})

        if self.path in ("/api/done", "/api/reopen"):
            tid = body.get("id")
            if not isinstance(tid, int):
                return self._json(400, {"error": "id"})
            rc, out, err = run_todoctl([self.path.split("/")[-1], str(tid)])
            return self._json(200 if rc == 0 else 500, {"out": out, "err": err})

        if self.path == "/api/note":
            tid = body.get("id")
            text = str(body.get("text", "")).strip()
            if not isinstance(tid, int) or not text or len(text) > MAX_NOTE:
                return self._json(400, {"error": "args"})
            rc, out, err = run_todoctl(["note", str(tid), text])
            return self._json(200 if rc == 0 else 500, {"out": out, "err": err})

        self._json(404, {"error": "not found"})


def main():
    srv = ThreadingHTTPServer((BIND_IP, BIND_PORT), H)
    sys.stderr.write(f"todo webui on http://{BIND_IP}:{BIND_PORT}  (user={USER})\n")
    srv.serve_forever()


if __name__ == "__main__":
    main()
