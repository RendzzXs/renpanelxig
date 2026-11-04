#!/bin/bash
# ============================================================
#   🚀 PTERODACTYL WEB PANEL v2 — FULL INSTALLER
#   Fitur: RAM pilihan (1-10GB/Unli) + Stats + TOS + Public Chat
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🚀 PTERODACTYL WEB PANEL v2 INSTALLER     ║${NC}"
echo -e "${CYAN}║  RAM Pilihan + Stats + TOS + Public Chat   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

read -p "👉 Domain panel (contoh: rendzzpanel.my.id): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Kosong!${NC}"; exit 1; }

read -p "👉 Email SSL: " EMAIL
[[ -z "$EMAIL" ]] && EMAIL="admin@$DOMAIN"

APP_PORT="3000"
WEB_ROOT="/var/www/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

DOMAIN_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | head -1)
SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
echo ""
echo -e "${CYAN}🌐 Domain IP :${NC} ${DOMAIN_IP:-'(belum resolve)'}"
echo -e "${CYAN}🖥️  Server IP:${NC} ${SERVER_IP:-'(unknown)'}"
echo ""

if [[ -n "$DOMAIN_IP" && -n "$SERVER_IP" && "$DOMAIN_IP" != "$SERVER_IP" ]]; then
  echo -e "${YELLOW}⚠️  DNS belum mengarah ke VPS!${NC}"
  read -p "Lanjut tanpa SSL? (y/n): " C
  [[ "$C" != "y" && "$C" != "Y" ]] && exit 0
  SKIP_SSL=1
fi

read -p "Lanjut install? (y/n): " C
[[ "$C" != "y" && "$C" != "Y" ]] && exit 0

# ============ 1. PACKAGES ============
echo ""
echo -e "${CYAN}[1/7] Install packages...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq 2>/dev/null
apt install -y curl wget git nginx sqlite3 ufw dnsutils certbot python3-certbot-nginx >/dev/null 2>&1

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  apt install -y nodejs >/dev/null 2>&1
fi
echo -e "${GREEN}  ✓ Node.js $(node -v)${NC}"

# ============ 2. FOLDER & MODULES ============
echo -e "${CYAN}[2/7] Setup folder & npm...${NC}"
[[ -d "$WEB_ROOT" ]] && mv "$WEB_ROOT" "/var/www/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$WEB_ROOT"/{views,public}
cd "$WEB_ROOT"
npm init -y >/dev/null 2>&1
npm install express express-session better-sqlite3 bcryptjs dotenv node-fetch@2 >/dev/null 2>&1
npm install -g pm2 >/dev/null 2>&1
echo -e "${GREEN}  ✓ NPM OK${NC}"

# ============ 3. ENV ============
echo -e "${CYAN}[3/7] Setup .env...${NC}"
cat > "$WEB_ROOT/.env" << ENVEOF
PORT=$APP_PORT
DOMAIN=$DOMAIN
SESSION_SECRET=$(openssl rand -hex 32)
ENVEOF
chmod 600 "$WEB_ROOT/.env"
echo -e "${GREEN}  ✓ .env OK${NC}"

# ============ 4. APP.JS ============
echo -e "${CYAN}[4/7] Setup backend...${NC}"

cat > "$WEB_ROOT/app.js" << 'APPJS'
require('dotenv').config();
const express = require('express');
const session = require('express-session');
const Database = require('better-sqlite3');
const bcrypt = require('bcryptjs');
const path = require('path');
const fetch = require('node-fetch');

const app = express();
const db = new Database(path.join(__dirname, 'panel.db'));

// ============ DATABASE ============
db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  role TEXT DEFAULT 'user',
  ptero_user_id INTEGER,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS servers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  ptero_server_id INTEGER,
  ptero_identifier TEXT,
  ram_gb INTEGER DEFAULT 1,
  memory INTEGER DEFAULT 1024,
  disk INTEGER DEFAULT 1024,
  cpu INTEGER DEFAULT 30,
  tos_accepted INTEGER DEFAULT 1,
  status TEXT DEFAULT 'active',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS chats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  username TEXT NOT NULL,
  message TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
`);

try { db.exec("ALTER TABLE servers ADD COLUMN ram_gb INTEGER DEFAULT 1"); } catch(e){}
try { db.exec("ALTER TABLE servers ADD COLUMN tos_accepted INTEGER DEFAULT 1"); } catch(e){}

const defaults = {
  ptero_url: '', plta: '', egg: '15', loc: '1',
  memory: '1024', disk: '1024', cpu: '30',
  site_name: 'Web Panel', panel_domain: process.env.DOMAIN || ''
};
const ins = db.prepare("INSERT OR IGNORE INTO settings (key,value) VALUES (?,?)");
for (const [k,v] of Object.entries(defaults)) ins.run(k, v);
const get = k => (db.prepare("SELECT value FROM settings WHERE key=?").get(k)||{}).value||'';

function isSetupDone() { return get('ptero_url') && get('plta'); }

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));
app.use(session({
  secret: process.env.SESSION_SECRET || 'secret',
  resave: false, saveUninitialized: false,
  cookie: { maxAge: 1000*60*60*24*7 }
}));

function auth(req,res,next){ if(!req.session.userId) return res.redirect('/login'); next(); }
function adminOnly(req,res,next){
  if(!req.session.userId) return res.redirect('/login');
  const u = db.prepare("SELECT * FROM users WHERE id=?").get(req.session.userId);
  if(!u || u.role!=='admin') return res.status(403).send('<h1>403 - Akses ditolak</h1>');
  req.user = u; next();
}

// ============ PTERODACTYL HELPERS ============
async function pteroCreateUser({email,username,password}){
  const domain = get('ptero_url').replace(/\/$/,'');
  const r = await fetch(`${domain}/api/application/users`, {
    method:'POST',
    headers:{'Accept':'application/json','Content-Type':'application/json','Authorization':`Bearer ${get('plta')}`},
    body: JSON.stringify({email,username,first_name:username,last_name:username,language:'en',password})
  });
  const d = await r.json();
  if(d.errors) throw new Error(JSON.stringify(d.errors[0]?.meta||d.errors));
  return d.attributes;
}

async function pteroCreateServer({name,userId,egg,loc,memory,disk,cpu}){
  const domain = get('ptero_url').replace(/\/$/,'');
  const spc = 'if [[ -d .git ]] && [[ {{AUTO_UPDATE}} == "1" ]]; then git pull; fi; if [[ ! -z ${NODE_PACKAGES} ]]; then /usr/local/bin/npm install ${NODE_PACKAGES}; fi; if [[ ! -z ${UNNODE_PACKAGES} ]]; then /usr/local/bin/npm uninstall ${UNNODE_PACKAGES}; fi; if [ -f /home/container/package.json ]; then /usr/local/bin/npm install; fi; /usr/local/bin/${CMD_RUN}';
  const r = await fetch(`${domain}/api/application/servers`, {
    method:'POST',
    headers:{'Accept':'application/json','Content-Type':'application/json','Authorization':`Bearer ${get('plta')}`},
    body: JSON.stringify({
      name, description:'Web Panel Auto Create',
      user: userId, egg: parseInt(egg),
      docker_image:'ghcr.io/parkervcp/yolks:nodejs_20',
      startup: spc,
      environment:{INST:'npm',USER_UPLOAD:'0',AUTO_UPDATE:'0',CMD_RUN:'npm start'},
      limits:{memory:parseInt(memory),swap:0,disk:parseInt(disk),io:500,cpu:parseInt(cpu)},
      feature_limits:{databases:5,backups:5,allocations:1},
      deploy:{locations:[parseInt(loc)],dedicated_ip:false,port_range:[]}
    })
  });
  const d = await r.json();
  if(d.errors) throw new Error(JSON.stringify(d.errors[0]?.meta||d.errors));
  return d.attributes;
}

// ============ SETUP WIZARD ============
app.get('/setup', (req,res) => {
  if (isSetupDone()) return res.redirect('/');
  res.sendFile(path.join(__dirname,'views','setup.html'));
});

app.post('/api/setup', async (req,res) => {
  try {
    if (isSetupDone()) return res.json({ok:false,msg:'Setup sudah selesai'});
    const { site_name, ptero_url, plta, egg, loc, memory, disk, cpu, admin_user, admin_email, admin_pass } = req.body;
    if (!ptero_url || !plta) return res.json({ok:false,msg:'URL Pterodactyl & PTLA wajib'});
    if (!admin_user || !admin_email || !admin_pass) return res.json({ok:false,msg:'Data admin wajib lengkap'});
    if (admin_pass.length < 6) return res.json({ok:false,msg:'Password admin min 6 karakter'});

    const upd = db.prepare("INSERT OR REPLACE INTO settings (key,value) VALUES (?,?)");
    upd.run('site_name', site_name||'Web Panel');
    upd.run('ptero_url', ptero_url.replace(/\/$/,''));
    upd.run('plta', plta);
    upd.run('egg', egg||'15');
    upd.run('loc', loc||'1');
    upd.run('memory', memory||'1024');
    upd.run('disk', disk||'1024');
    upd.run('cpu', cpu||'30');

    const h = bcrypt.hashSync(admin_pass,10);
    const ex = db.prepare("SELECT id FROM users WHERE username=? OR email=?").get(admin_user, admin_email);
    if (ex) db.prepare("UPDATE users SET password=?, role='admin' WHERE id=?").run(h, ex.id);
    else db.prepare("INSERT INTO users (username,email,password,role) VALUES (?,?,?,'admin')").run(admin_user, admin_email, h);

    res.json({ok:true,msg:'Setup selesai! Silakan login.'});
  } catch(e){ res.json({ok:false,msg:e.message}); }
});

// ============ PAGE ROUTES ============
app.get('/', (req,res) => {
  if (!isSetupDone()) return res.redirect('/setup');
  if (req.session.userId) return res.redirect('/dashboard');
  res.sendFile(path.join(__dirname,'views','landing.html'));
});
app.get('/login', (req,res) => {
  if (!isSetupDone()) return res.redirect('/setup');
  res.sendFile(path.join(__dirname,'views','login.html'));
});
app.get('/register', (req,res) => {
  if (!isSetupDone()) return res.redirect('/setup');
  res.sendFile(path.join(__dirname,'views','register.html'));
});
app.get('/dashboard', auth, (req,res) => res.sendFile(path.join(__dirname,'views','dashboard.html')));
app.get('/create', auth, (req,res) => res.sendFile(path.join(__dirname,'views','create.html')));
app.get('/admin', adminOnly, (req,res) => res.sendFile(path.join(__dirname,'views','admin.html')));

// ============ AUTH ============
app.post('/api/register', async (req,res) => {
  try {
    const { username, email, password } = req.body;
    if (!username||!email||!password) return res.json({ok:false,msg:'Lengkapi data'});
    if (password.length<6) return res.json({ok:false,msg:'Password min 6 karakter'});
    const ex = db.prepare("SELECT id FROM users WHERE email=? OR username=?").get(email,username);
    if (ex) return res.json({ok:false,msg:'Sudah dipakai'});
    const h = bcrypt.hashSync(password,10);
    const r = db.prepare("INSERT INTO users (username,email,password,role) VALUES (?,?,?,'user')").run(username,email,h);
    req.session.userId = r.lastInsertRowid;
    res.json({ok:true,msg:'Berhasil'});
  } catch(e){ res.json({ok:false,msg:e.message}); }
});

app.post('/api/login', (req,res) => {
  const { email, password } = req.body;
  const u = db.prepare("SELECT * FROM users WHERE email=?").get(email);
  if (!u || !bcrypt.compareSync(password,u.password)) return res.json({ok:false,msg:'Email/password salah'});
  req.session.userId = u.id;
  res.json({ok:true,role:u.role});
});

app.get('/api/logout', (req,res) => { req.session.destroy(() => res.redirect('/')); });

app.get('/api/me', auth, (req,res) => {
  res.json(db.prepare("SELECT id,username,email,role FROM users WHERE id=?").get(req.session.userId));
});

// ============ SERVERS ============
app.get('/api/servers', auth, (req,res) => {
  res.json(db.prepare("SELECT * FROM servers WHERE user_id=? ORDER BY id DESC").all(req.session.userId));
});

app.post('/api/create-server', auth, async (req,res) => {
  try {
    const { name, email, username, password, ram_gb, tos } = req.body;
    if (!name||!email||!username||!password) return res.json({ok:false,msg:'Lengkapi data'});
    if (password.length<6) return res.json({ok:false,msg:'Password panel min 6 karakter'});
    if (!tos) return res.json({ok:false,msg:'Kamu wajib centang TOS!'});

    const allowedRam = [1,2,3,4,5,8,10,0]; // 0 = unlimited
    const ramChoice = parseInt(ram_gb);
    if (!allowedRam.includes(ramChoice)) return res.json({ok:false,msg:'RAM tidak valid'});

    const memory = ramChoice === 0 ? 0 : ramChoice * 1024;
    const disk = ramChoice === 0 ? 0 : ramChoice * 1024;
    const cpu = ramChoice === 0 ? 0 : Math.min(ramChoice * 50, 400);

    const pUser = await pteroCreateUser({ email, username, password });
    const pServer = await pteroCreateServer({
      name, userId: pUser.id,
      egg: get('egg'), loc: get('loc'), memory, disk, cpu
    });

    db.prepare(`INSERT INTO servers (user_id,name,ptero_server_id,ptero_identifier,ram_gb,memory,disk,cpu,tos_accepted)
      VALUES (?,?,?,?,?,?,?,?,1)`).run(req.session.userId, name, pServer.id, pServer.identifier, ramChoice, memory, disk, cpu);

    res.json({ok:true,data:{
      username:pUser.username, password,
      ram: ramChoice === 0 ? 'Unlimited' : ramChoice + ' GB',
      memory: ramChoice === 0 ? 'Unlimited' : memory + ' MB',
      disk: ramChoice === 0 ? 'Unlimited' : disk + ' MB',
      cpu: ramChoice === 0 ? 'Unlimited' : cpu + '%',
      ptero_url: get('ptero_url'),
      server_id: pServer.identifier
    }});
  } catch(e){ res.json({ok:false,msg:e.message}); }
});

app.delete('/api/servers/:id', auth, (req,res) => {
  db.prepare("DELETE FROM servers WHERE id=? AND user_id=?").run(req.params.id, req.session.userId);
  res.json({ok:true});
});

// ============ PUBLIC STATS ============
app.get('/api/public/stats', (req,res) => {
  const totalUsers = db.prepare("SELECT COUNT(*) c FROM users WHERE role='user'").get().c;
  const totalServers = db.prepare("SELECT COUNT(*) c FROM servers").get().c;
  const activeServers = db.prepare("SELECT COUNT(*) c FROM servers WHERE status='active'").get().c;
  res.json({
    totalUsers,
    totalServers,
    activeServers,
    uptime: Math.floor(process.uptime()),
    site_name: get('site_name') || 'Web Panel'
  });
});

// ============ PUBLIC CHAT ============
app.get('/api/chat/messages', (req,res) => {
  const msgs = db.prepare("SELECT id,username,message,created_at FROM chats ORDER BY id DESC LIMIT 50").all().reverse();
  res.json(msgs);
});

app.post('/api/chat/send', auth, (req,res) => {
  const { message } = req.body;
  if (!message || message.trim().length === 0) return res.json({ok:false,msg:'Pesan kosong'});
  if (message.length > 500) return res.json({ok:false,msg:'Max 500 karakter'});
  const u = db.prepare("SELECT username FROM users WHERE id=?").get(req.session.userId);
  db.prepare("INSERT INTO chats (user_id,username,message) VALUES (?,?,?)")
    .run(req.session.userId, u.username, message.trim());
  res.json({ok:true});
});

// ============ ADMIN API ============
app.get('/api/admin/stats', adminOnly, (req,res) => {
  const users = db.prepare("SELECT COUNT(*) c FROM users").get().c;
  const servers = db.prepare("SELECT COUNT(*) c FROM servers").get().c;
  res.json({users,servers});
});
app.get('/api/admin/users', adminOnly, (req,res) => {
  res.json(db.prepare("SELECT id,username,email,role,created_at FROM users ORDER BY id DESC").all());
});
app.delete('/api/admin/users/:id', adminOnly, (req,res) => {
  if (parseInt(req.params.id) === req.user.id) return res.json({ok:false,msg:'Tidak bisa hapus sendiri'});
  db.prepare("DELETE FROM servers WHERE user_id=?").run(req.params.id);
  db.prepare("DELETE FROM users WHERE id=?").run(req.params.id);
  res.json({ok:true});
});
app.get('/api/admin/servers', adminOnly, (req,res) => {
  res.json(db.prepare(`SELECT s.*,u.username FROM servers s JOIN users u ON u.id=s.user_id ORDER BY s.id DESC`).all());
});
app.delete('/api/admin/servers/:id', adminOnly, (req,res) => {
  db.prepare("DELETE FROM servers WHERE id=?").run(req.params.id);
  res.json({ok:true});
});
app.get('/api/admin/settings', adminOnly, (req,res) => {
  const rows = db.prepare("SELECT * FROM settings").all();
  const out = {}; rows.forEach(r => out[r.key] = r.value);
  res.json(out);
});
app.post('/api/admin/settings', adminOnly, (req,res) => {
  const u = db.prepare("INSERT OR REPLACE INTO settings (key,value) VALUES (?,?)");
  for (const [k,v] of Object.entries(req.body)) u.run(k, String(v));
  res.json({ok:true});
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🚀 Web Panel running on port ${PORT}`));
APPJS

echo -e "${GREEN}  ✓ app.js OK${NC}"

# ============ 5. FRONTEND VIEWS ============
echo -e "${CYAN}[5/7] Setup frontend...${NC}"

# ---------- SETUP WIZARD ----------
cat > "$WEB_ROOT/views/setup.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Setup Wizard</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:'Segoe UI',sans-serif}
body{background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);color:#fff;min-height:100vh;padding:30px 15px}
.box{max-width:700px;margin:auto;background:rgba(255,255,255,.05);backdrop-filter:blur(20px);padding:40px;border-radius:20px;border:1px solid rgba(255,255,255,.1)}
h1{text-align:center;margin-bottom:10px;background:linear-gradient(135deg,#00d4ff,#a855f7);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
p.sub{text-align:center;color:#aaa;margin-bottom:30px}
h3{margin:25px 0 12px;color:#00d4ff;font-size:1em;display:flex;align-items:center;gap:8px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:15px}
@media(max-width:600px){.grid{grid-template-columns:1fr}.box{padding:25px}}
label{display:block;margin-bottom:6px;font-size:.85em;color:#aaa}
input,select{width:100%;padding:12px;background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.15);border-radius:8px;color:#fff;font-size:1em;outline:none}
input:focus{border-color:#00d4ff}
button{width:100%;padding:15px;margin-top:25px;background:linear-gradient(135deg,#667eea,#764ba2);border:none;border-radius:10px;color:#fff;font-size:1.1em;font-weight:bold;cursor:pointer}
.alert{padding:12px;border-radius:8px;margin-bottom:15px;font-size:.9em}
.alert-err{background:rgba(239,68,68,.15);color:#ef4444;border:1px solid rgba(239,68,68,.3)}
.alert-ok{background:rgba(16,185,129,.15);color:#10b981;border:1px solid rgba(16,185,129,.3)}
</style>
</head>
<body>
<div class="box">
<h1>🚀 Setup Wizard</h1>
<p class="sub">Konfigurasi pertama kali</p>
<div id="alert"></div>
<form id="form">
<h3><i class="fas fa-globe"></i> Info Situs</h3>
<label>Nama Situs</label>
<input name="site_name" placeholder="Rendzz Panel" value="Rendzz Panel">

<h3><i class="fas fa-server"></i> Pterodactyl Config</h3>
<div class="grid">
<div><label>URL Pterodactyl</label><input name="ptero_url" placeholder="https://panel.domain.com" required></div>
<div><label>PTLA Token</label><input name="plta" placeholder="ptla_xxxxxxxx" required></div>
<div><label>Egg ID</label><input name="egg" type="number" value="15" required></div>
<div><label>Location ID</label><input name="loc" type="number" value="1" required></div>
<div><label>Disk default (MB)</label><input name="disk" type="number" value="1024" required></div>
<div><label>CPU default (%)</label><input name="cpu" type="number" value="30" required></div>
</div>

<h3><i class="fas fa-user-shield"></i> Akun Admin</h3>
<div class="grid">
<div><label>Username Admin</label><input name="admin_user" required></div>
<div><label>Email Admin</label><input name="admin_email" type="email" required></div>
<div style="grid-column:1/-1"><label>Password Admin</label><input name="admin_pass" type="password" minlength="6" required></div>
</div>

<button type="submit"><i class="fas fa-check"></i> Selesaikan Setup</button>
</form>
</div>
<script>
document.getElementById('form').onsubmit = async (e) => {
  e.preventDefault();
  const btn = e.target.querySelector('button');
  btn.disabled = true; btn.textContent = 'Menyimpan...';
  const data = Object.fromEntries(new FormData(e.target));
  try {
    const r = await fetch('/api/setup', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    const j = await r.json();
    const al = document.getElementById('alert');
    if (j.ok) {
      al.innerHTML = '<div class="alert alert-ok">✅ Setup berhasil! Redirect...</div>';
      setTimeout(()=>location.href='/login', 1500);
    } else {
      al.innerHTML = '<div class="alert alert-err">❌ '+j.msg+'</div>';
      btn.disabled = false; btn.innerHTML = '<i class="fas fa-check"></i> Selesaikan Setup';
    }
  } catch(err) { al.innerHTML = '<div class="alert alert-err">❌ '+err.message+'</div>'; btn.disabled=false; }
};
</script>
</body>
</html>
HTMLEOF

# ---------- LANDING (STATS + TOS + CHAT) ----------
cat > "$WEB_ROOT/views/landing.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Web Panel - Auto Create Server</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:'Segoe UI',sans-serif}
body{background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);color:#fff;min-height:100vh}
nav{padding:18px 40px;display:flex;justify-content:space-between;align-items:center;background:rgba(0,0,0,.3);backdrop-filter:blur(10px);position:sticky;top:0;z-index:10}
.logo{font-size:1.3em;font-weight:bold;display:flex;align-items:center;gap:10px}
.logo i{color:#00d4ff}
nav a{color:#fff;text-decoration:none;margin-left:15px;padding:8px 16px;border-radius:8px;transition:.3s;display:inline-flex;align-items:center;gap:6px;font-size:.95em}
nav a:hover{background:rgba(255,255,255,.1)}
.btn-primary{background:linear-gradient(135deg,#667eea,#764ba2)}
.hero{padding:60px 20px 30px;text-align:center}
.hero h1{font-size:2.7em;margin-bottom:15px;background:linear-gradient(135deg,#00d4ff,#a855f7);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.hero p{font-size:1.1em;opacity:.8;margin-bottom:35px;max-width:600px;margin-left:auto;margin-right:auto}
.cta{display:flex;gap:15px;justify-content:center;flex-wrap:wrap}
.cta a{padding:15px 35px;border-radius:10px;text-decoration:none;color:#fff;font-weight:bold;display:inline-flex;align-items:center;gap:10px}
.btn-outline{border:2px solid #667eea;background:transparent}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:18px;padding:30px 40px;max-width:1000px;margin:auto}
.stat{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);padding:25px;border-radius:15px;text-align:center;transition:.3s}
.stat:hover{transform:translateY(-3px);background:rgba(255,255,255,.08)}
.stat i{font-size:2em;color:#00d4ff;margin-bottom:10px}
.stat .num{font-size:2em;font-weight:bold;color:#fff}
.stat .lbl{color:#aaa;font-size:.85em;margin-top:5px}
.features{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:20px;padding:30px 40px;max-width:1100px;margin:auto}
.card{background:rgba(255,255,255,.05);padding:25px;border-radius:15px;border:1px solid rgba(255,255,255,.1);transition:.3s}
.card:hover{transform:translateY(-3px);background:rgba(255,255,255,.08)}
.card i{font-size:32px;color:#00d4ff;margin-bottom:12px}
.card h3{margin-bottom:8px;font-size:1.05em}
.card p{opacity:.7;font-size:.88em;line-height:1.6}
.ram-options{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px;padding:30px 40px;max-width:900px;margin:auto}
.ram-pill{background:rgba(0,212,255,.1);border:1px solid rgba(0,212,255,.3);padding:15px;border-radius:10px;text-align:center;font-weight:bold;color:#00d4ff;font-size:1.05em}
.ram-pill.unli{background:rgba(245,158,11,.15);border-color:rgba(245,158,11,.4);color:#f59e0b}

.chat-section{max-width:800px;margin:30px auto;padding:0 20px}
.chat-box{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);border-radius:15px;overflow:hidden}
.chat-head{padding:15px 20px;background:rgba(0,0,0,.3);border-bottom:1px solid rgba(255,255,255,.1);display:flex;align-items:center;gap:10px;font-weight:bold}
.chat-head i{color:#10b981}
.chat-messages{height:320px;overflow-y:auto;padding:15px 20px}
.chat-msg{margin-bottom:12px;display:flex;gap:8px;align-items:flex-start}
.chat-msg .av{width:32px;height:32px;border-radius:50%;background:linear-gradient(135deg,#667eea,#764ba2);display:flex;align-items:center;justify-content:center;font-weight:bold;flex-shrink:0;font-size:.85em}
.chat-msg .body{background:rgba(255,255,255,.05);padding:8px 12px;border-radius:10px;max-width:80%;word-wrap:break-word}
.chat-msg .name{font-size:.8em;color:#00d4ff;margin-bottom:3px;font-weight:bold}
.chat-msg .txt{font-size:.9em;line-height:1.4}
.chat-input{display:flex;gap:8px;padding:12px;background:rgba(0,0,0,.3);border-top:1px solid rgba(255,255,255,.1)}
.chat-input input{flex:1;padding:10px 14px;background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.15);border-radius:8px;color:#fff;outline:none}
.chat-input button{padding:10px 18px;background:linear-gradient(135deg,#667eea,#764ba2);border:none;border-radius:8px;color:#fff;cursor:pointer;font-weight:bold}
.section-title{text-align:center;font-size:1.6em;margin:30px 0 10px;color:#fff}
.section-sub{text-align:center;color:#aaa;margin-bottom:20px;font-size:.95em}
footer{text-align:center;padding:30px 20px;color:#666;font-size:.85em;border-top:1px solid rgba(255,255,255,.05);margin-top:40px}
</style>
</head>
<body>
<nav>
  <div class="logo"><i class="fas fa-rocket"></i> <span id="siteName">WebPanel</span></div>
  <div>
    <a href="/login"><i class="fas fa-sign-in-alt"></i> Login</a>
    <a href="/register" class="btn-primary"><i class="fas fa-user-plus"></i> Daftar</a>
  </div>
</nav>

<div class="hero">
  <h1>Buat Server Impianmu 🚀</h1>
  <p>Platform panel hosting otomatis dengan Pterodactyl. Pilih RAM, klik create, server langsung jadi!</p>
  <div class="cta">
    <a href="/register" class="btn-primary"><i class="fas fa-rocket"></i> Mulai Sekarang</a>
    <a href="/login" class="btn-outline"><i class="fas fa-sign-in-alt"></i> Masuk</a>
  </div>
</div>

<h2 class="section-title">📊 Statistik</h2>
<p class="section-sub">Live update dari server kami</p>
<div class="stats">
  <div class="stat"><i class="fas fa-users"></i><div class="num" id="stUsers">0</div><div class="lbl">Total User</div></div>
  <div class="stat"><i class="fas fa-server"></i><div class="num" id="stServers">0</div><div class="lbl">Total Server</div></div>
  <div class="stat"><i class="fas fa-check-circle"></i><div class="num" id="stActive">0</div><div class="lbl">Server Aktif</div></div>
  <div class="stat"><i class="fas fa-clock"></i><div class="num" id="stUptime">0h</div><div class="lbl">Uptime</div></div>
</div>

<h2 class="section-title">💾 Pilihan RAM</h2>
<p class="section-sub">Bebas pilih sesuai kebutuhan</p>
<div class="ram-options">
  <div class="ram-pill">1 GB</div>
  <div class="ram-pill">2 GB</div>
  <div class="ram-pill">3 GB</div>
  <div class="ram-pill">4 GB</div>
  <div class="ram-pill">5 GB</div>
  <div class="ram-pill">8 GB</div>
  <div class="ram-pill">10 GB</div>
  <div class="ram-pill unli">♾️ Unlimited</div>
</div>

<h2 class="section-title">✨ Fitur</h2>
<div class="features">
  <div class="card"><i class="fas fa-bolt"></i><h3>Auto Create</h3><p>Server langsung dibuat otomatis setelah isi form</p></div>
  <div class="card"><i class="fas fa-memory"></i><h3>RAM Fleksibel</h3><p>Pilih RAM 1GB sampai Unlimited sesuai kebutuhan</p></div>
  <div class="card"><i class="fas fa-shield-alt"></i><h3>Aman</h3><p>Password terenkripsi bcrypt + session secure</p></div>
  <div class="card"><i class="fas fa-headset"></i><h3>Public Chat</h3><p>Bisa tanya & diskusi dengan user lain realtime</p></div>
</div>

<div class="chat-section">
  <h2 class="section-title">💬 Public Chat</h2>
  <p class="section-sub">Login dulu untuk ikut chat</p>
  <div class="chat-box">
    <div class="chat-head"><i class="fas fa-comments"></i> Live Chat</div>
    <div class="chat-messages" id="chatMessages">
      <p style="color:#aaa;text-align:center;padding:20px">Loading...</p>
    </div>
    <div class="chat-input">
      <input id="chatInput" placeholder="Login dulu untuk chat..." disabled>
      <button id="chatBtn" disabled><i class="fas fa-paper-plane"></i></button>
    </div>
  </div>
</div>

<footer>
  <p>© 2025 <span id="footSite">WebPanel</span> — All rights reserved</p>
</footer>

<script>
// Stats
async function loadStats(){
  try {
    const j = await (await fetch('/api/public/stats')).json();
    document.getElementById('stUsers').textContent = j.totalUsers;
    document.getElementById('stServers').textContent = j.totalServers;
    document.getElementById('stActive').textContent = j.activeServers;
    const h = Math.floor(j.uptime/3600);
    const m = Math.floor((j.uptime%3600)/60);
    document.getElementById('stUptime').textContent = h + 'h ' + m + 'm';
    if (j.site_name) {
      document.getElementById('siteName').textContent = j.site_name;
      document.getElementById('footSite').textContent = j.site_name;
    }
  } catch(e){}
}

// Chat
let me = null;
async function loadMe(){
  try {
    const r = await fetch('/api/me');
    if (r.ok) me = await r.json();
  } catch(e){}
}
async function loadChat(){
  try {
    const arr = await (await fetch('/api/chat/messages')).json();
    const box = document.getElementById('chatMessages');
    if (!arr.length) { box.innerHTML = '<p style="color:#aaa;text-align:center;padding:20px">Belum ada chat. Login & kirim pesan pertama!</p>'; return; }
    box.innerHTML = arr.map(m => `
      <div class="chat-msg">
        <div class="av">${m.username[0].toUpperCase()}</div>
        <div class="body">
          <div class="name">@${escapeHtml(m.username)}</div>
          <div class="txt">${escapeHtml(m.message)}</div>
        </div>
      </div>
    `).join('');
    box.scrollTop = box.scrollHeight;
  } catch(e){}
}
function escapeHtml(s){return s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}

async function sendChat(){
  const inp = document.getElementById('chatInput');
  const msg = inp.value.trim();
  if (!msg) return;
  const r = await fetch('/api/chat/send', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:msg})});
  const j = await r.json();
  if (j.ok) { inp.value=''; loadChat(); }
  else alert(j.msg);
}

(async () => {
  await loadMe();
  if (me) {
    const inp = document.getElementById('chatInput');
    const btn = document.getElementById('chatBtn');
    inp.disabled = false; inp.placeholder = 'Ketik pesan...';
    btn.disabled = false;
    btn.onclick = sendChat;
    inp.addEventListener('keydown', e => { if (e.key === 'Enter') sendChat(); });
  }
  loadStats(); loadChat();
  setInterval(loadStats, 10000);
  setInterval(loadChat, 5000);
})();
</script>
</body>
</html>
HTMLEOF

# ---------- LOGIN ----------
cat > "$WEB_ROOT/views/login.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Login</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:'Segoe UI',sans-serif}
body{background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);display:flex;align-items:center;justify-content:center;min-height:100vh;color:#fff;padding:20px}
.box{background:rgba(255,255,255,.05);backdrop-filter:blur(15px);padding:45px 40px;border-radius:20px;border:1px solid rgba(255,255,255,.1);width:400px;max-width:100%}
h2{text-align:center;margin-bottom:30px;display:flex;align-items:center;justify-content:center;gap:10px}
h2 i{color:#00d4ff}
.field{margin-bottom:18px;position:relative}
.field i{position:absolute;left:15px;top:50%;transform:translateY(-50%);color:#a855f7}
input{width:100%;padding:14px 14px 14px 45px;background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.15);border-radius:10px;color:#fff;outline:none;font-size:1em}
input:focus{border-color:#00d4ff}
button{width:100%;padding:14px;background:linear-gradient(135deg,#667eea,#764ba2);border:none;border-radius:10px;color:#fff;font-size:1.05em;font-weight:bold;cursor:pointer;margin-top:5px}
.alert{padding:12px;border-radius:8px;margin-bottom:15px;font-size:.9em}
.alert-err{background:rgba(239,68,68,.15);color:#ef4444;border:1px solid rgba(239,68,68,.3)}
.alert-ok{background:rgba(16,185,129,.15);color:#10b981;border:1px solid rgba(16,185,129,.3)}
p.reg{text-align:center;margin-top:20px;font-size:.9em;color:#aaa}
p.reg a{color:#00d4ff;text-decoration:none}
</style>
</head>
<body>
<div class="box">
<h2><i class="fas fa-sign-in-alt"></i> Login</h2>
<div id="alert"></div>
<form id="form">
<div class="field"><i class="fas fa-envelope"></i><input name="email" type="email" placeholder="Email" required></div>
<div class="field"><i class="fas fa-lock"></i><input name="password" type="password" placeholder="Password" required></div>
<button type="submit">Masuk</button>
</form>
<p class="reg">Belum punya akun? <a href="/register">Daftar</a></p>
</div>
<script>
document.getElementById('form').onsubmit = async (e) => {
  e.preventDefault();
  const data = Object.fromEntries(new FormData(e.target));
  const r = await fetch('/api/login', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
  const j = await r.json();
  const al = document.getElementById('alert');
  if (j.ok) {
    al.innerHTML = '<div class="alert alert-ok">✅ Login berhasil...</div>';
    setTimeout(()=>location.href = j.role === 'admin' ? '/admin' : '/dashboard', 800);
  } else al.innerHTML = '<div class="alert alert-err">❌ '+j.msg+'</div>';
};
</script>
</body>
</html>
HTMLEOF

# ---------- REGISTER ----------
cat > "$WEB_ROOT/views/register.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Register</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:'Segoe UI',sans-serif}
body{background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);display:flex;align-items:center;justify-content:center;min-height:100vh;color:#fff;padding:20px}
.box{background:rgba(255,255,255,.05);backdrop-filter:blur(15px);padding:45px 40px;border-radius:20px;border:1px solid rgba(255,255,255,.1);width:420px;max-width:100%}
h2{text-align:center;margin-bottom:30px;display:flex;align-items:center;justify-content:center;gap:10px}
h2 i{color:#00d4ff}
.field{margin-bottom:18px;position:relative}
.field i{position:absolute;left:15px;top:50%;transform:translateY(-50%);color:#a855f7}
input{width:100%;padding:14px 14px 14px 45px;background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.15);border-radius:10px;color:#fff;outline:none;font-size:1em}
input:focus{border-color:#00d4ff}
button{width:100%;padding:14px;background:linear-gradient(135deg,#667eea,#764ba2);border:none;border-radius:10px;color:#fff;font-size:1.05em;font-weight:bold;cursor:pointer;margin-top:5px}
.alert{padding:12px;border-radius:8px;margin-bottom:15px;font-size:.9em}
.alert-err{background:rgba(239,68,68,.15);color:#ef4444;border:1px solid rgba(239,68,68,.3)}
.alert-ok{background:rgba(16,185,129,.15);color:#10b981;border:1px solid rgba(16,185,129,.3)}
p.reg{text-align:center;margin-top:20px;font-size:.9em;color:#aaa}
p.reg a{color:#00d4ff;text-decoration:none}
</style>
</head>
<body>
<div class="box">
<h2><i class="fas fa-user-plus"></i> Daftar</h2>
<div id="alert"></div>
<form id="form">
<div class="field"><i class="fas fa-user"></i><input name="username" placeholder="Username" required></div>
<div class="field"><i class="fas fa-envelope"></i><input name="email" type="email" placeholder="Email" required></div>
<div class="field"><i class="fas fa-lock"></i><input name="password" type="password" minlength="6" placeholder="Password (min 6)" required></div>
<button type="submit">Daftar</button>
</form>
<p class="reg">Sudah punya akun? <a href="/login">Login</a></p>
</div>
<script>
document.getElementById('form').onsubmit = async (e) => {
  e.preventDefault();
  const data = Object.fromEntries(new FormData(e.target));
  const r = await fetch('/api/register', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
  const j = await r.json();
  const al = document.getElementById('alert');
  if (j.ok) {
    al.innerHTML = '<div class="alert alert-ok">✅ Daftar berhasil, redirect...</div>';
    setTimeout(()=>location.href='/dashboard', 1200);
  } else al.innerHTML = '<div class="alert alert-err">❌ '+j.msg+'</div>';
};
</script>
</body>
</html>
HTMLEOF

# ---------- DASHBOARD ----------
cat > "$WEB_ROOT/views/dashboard.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dashboard</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:'Segoe UI',sans-serif}
body{background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);color:#fff;min-height:100vh}
nav{padding:15px 30px;display:flex;justify-content:space-between;align-items:center;background:rgba(0,0,0,.3);backdrop-filter:blur(10px);position:sticky;top:0;z-index:10}
.logo{font-size:1.2em;font-weight:bold;display:flex;align-items:center;gap:10px}
.logo i{color:#00d4ff}
nav .user{display:flex;align-items:center;gap:12px;font-size:.9em}
nav a{color:#fff;text-decoration:none;padding:8px 14px;border-radius:8px;background:rgba(239,68,68,.2);display:inline-flex;align-items:center;gap:6px}
.container{max-width:900px;margin:30px auto;padding:0 20px}
.card{background:rgba(255,255,255,.05);backdrop-filter:blur(10px);border:1px solid rgba(255,255,255,.1);padding:28px;border-radius:15px;margin-bottom:20px}
.card.center{text-align:center}
h2{margin-bottom:15px;display:flex;align-items:center;gap:10px;font-size:1.3em}
h2 i{color:#00d4ff}
.btn-create{display:inline-flex;align-items:center;gap:10px;padding:18px 40px;background:linear-gradient(135deg,#10b981,#059669);color:#fff;text-decoration:none;border-radius:12px;font-weight:bold;font-size:1.1em;transition:.3s;margin-top:15px}
.btn-create:hover{transform:scale(1.05);box-shadow:0 10px 30px rgba(16,185,129,.4)}
.server-item{background:rgba(0,0,0,.2);border:1px solid rgba(255,255,255,.1);padding:15px;border-radius:10px;margin-bottom:10px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px}
.server-item .name{font-weight:bold;color:#00d4ff;font-size:1.05em}
.server-item .info{font-size:.82em;color:#aaa;line-height:1.6;margin-top:3px}
.ram-badge{display:inline-block;padding:3px 10px;border-radius:6px;background:rgba(0,212,255,.15);color:#00d4ff;font-weight:bold;font-size:.8em}
.ram-badge.unli{background:rgba(245,158,11,.15);color:#f59e0b}
.btn-del{background:rgba(239,68,68,.2);color:#ef4444;padding:8px 12px;border:none;border-radius:6px;cursor:pointer}
.empty{color:#888;text-align:center;padding:30px}
</style>
</head>
<body>
<nav>
  <div class="logo"><i class="fas fa-rocket"></i> WebPanel</div>
  <div class="user">
    <span style="color:#aaa"><i class="fas fa-user-circle"></i> <span id="me">...</span></span>
    <a href="/api/logout"><i class="fas fa-sign-out-alt"></i> Logout</a>
  </div>
</nav>
<div class="container">
  <div class="card center">
    <h2 style="justify-content:center"><i class="fas fa-plus-circle"></i> Buat Server Baru</h2>
    <p style="color:#aaa;margin-bottom:10px">Pilih RAM, centang TOS, langsung jadi!</p>
    <a href="/create" class="btn-create"><i class="fas fa-rocket"></i> Create Panel</a>
  </div>

  <div class="card">
    <h2><i class="fas fa-server"></i> Server Saya</h2>
    <div id="servers"><p class="empty">Loading...</p></div>
  </div>
</div>
<script>
async function loadMe(){
  const j = await (await fetch('/api/me')).json();
  document.getElementById('me').textContent = j.username;
}
async function loadServers(){
  const arr = await (await fetch('/api/servers')).json();
  const box = document.getElementById('servers');
  if (!arr.length) { box.innerHTML = '<p class="empty">Belum ada server. Klik Create Panel!</p>'; return; }
  box.innerHTML = arr.map(s => {
    const ramLabel = s.ram_gb === 0 ? 'Unlimited' : s.ram_gb + ' GB';
    const ramClass = s.ram_gb === 0 ? 'unli' : '';
    return `
    <div class="server-item">
      <div>
        <div class="name">${s.name}</div>
        <div class="info">ID: ${s.ptero_identifier||'-'} | <span class="ram-badge ${ramClass}">${ramLabel}</span> | Disk: ${s.disk===0?'Unlimited':s.disk+'MB'} | CPU: ${s.cpu===0?'Unlimited':s.cpu+'%'}</div>
        <div class="info">Dibuat: ${new Date(s.created_at).toLocaleString('id-ID')}</div>
      </div>
      <button class="btn-del" onclick="delServer(${s.id})"><i class="fas fa-trash"></i></button>
    </div>`;
  }).join('');
}
async function delServer(id){
  if(!confirm('Hapus data server ini dari web?')) return;
  await fetch('/api/servers/'+id, {method:'DELETE'});
  loadServers();
}
loadMe(); loadServers();
</script>
</body>
</html>
HTMLEOF

# ---------- CREATE PANEL ----------
cat > "$WEB_ROOT/views/create.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Create Panel</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:'Segoe UI',sans-serif}
body{background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);color:#fff;min-height:100vh;padding-bottom:40px}
nav{padding:15px 30px;display:flex;justify-content:space-between;align-items:center;background:rgba(0,0,0,.3);backdrop-filter:blur(10px);position:sticky;top:0;z-index:10}
.logo{font-size:1.2em;font-weight:bold;display:flex;align-items:center;gap:10px}
.logo i{color:#00d4ff}
nav a{color:#fff;text-decoration:none;padding:8px 14px;border-radius:8px;background:rgba(255,255,255,.1);display:inline-flex;align-items:center;gap:6px;font-size:.9em}
.container{max-width:750px;margin:30px auto;padding:0 20px}
.card{background:rgba(255,255,255,.05);backdrop-filter:blur(10px);border:1px solid rgba(255,255,255,.1);padding:30px;border-radius:15px;margin-bottom:20px}
h2{margin-bottom:20px;display:flex;align-items:center;gap:10px}
h2 i{color:#00d4ff}
label{display:block;margin-bottom:8px;font-size:.9em;color:#ccc;font-weight:600;margin-top:15px}
input{width:100%;padding:13px;background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.15);border-radius:10px;color:#fff;font-size:1em;outline:none}
input:focus{border-color:#00d4ff}
.ram-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-top:8px}
@media(max-width:600px){.ram-grid{grid-template-columns:repeat(2,1fr)}}
.ram-opt{padding:15px;background:rgba(0,0,0,.3);border:2px solid rgba(255,255,255,.1);border-radius:10px;cursor:pointer;text-align:center;transition:.2s;font-weight:bold}
.ram-opt:hover{border-color:#667eea;background:rgba(102,126,234,.1)}
.ram-opt.selected{border-color:#00d4ff;background:rgba(0,212,255,.15);color:#00d4ff}
.ram-opt.unli.selected{border-color:#f59e0b;background:rgba(245,158,11,.15);color:#f59e0b}
.ram-opt small{display:block;font-size:.75em;color:#888;margin-top:4px;font-weight:normal}
.tos-box{background:rgba(245,158,11,.08);border:1px solid rgba(245,158,11,.3);padding:20px;border-radius:10px;margin-top:20px}
.tos-box h3{color:#f59e0b;margin-bottom:12px;font-size:1em;display:flex;align-items:center;gap:8px}
.tos-box ul{list-style:none;font-size:.9em;color:#ccc;line-height:1.9}
.tos-box ul li::before{content:'⚠️ ';margin-right:6px}
.tos-check{display:flex;align-items:flex-start;gap:10px;margin-top:15px;padding:12px;background:rgba(0,0,0,.2);border-radius:8px;cursor:pointer}
.tos-check input{width:auto;margin-top:2px;transform:scale(1.3);cursor:pointer}
.tos-check label{margin:0;cursor:pointer;font-size:.9em;color:#fff;font-weight:normal}
button.submit{width:100%;padding:16px;background:linear-gradient(135deg,#10b981,#059669);border:none;border-radius:12px;color:#fff;font-size:1.1em;font-weight:bold;cursor:pointer;margin-top:20px;display:flex;align-items:center;justify-content:center;gap:10px;transition:.3s}
button.submit:hover{transform:translateY(-2px);box-shadow:0 10px 25px rgba(16,185,129,.4)}
button.submit:disabled{opacity:.5;cursor:not-allowed;transform:none}
.alert{padding:12px;border-radius:8px;margin-bottom:15px;font-size:.9em}
.alert-err{background:rgba(239,68,68,.15);color:#ef4444;border:1px solid rgba(239,68,68,.3)}
.alert-ok{background:rgba(16,185,129,.15);color:#10b981;border:1px solid rgba(16,185,129,.3)}
.cred-box{background:rgba(0,0,0,.4);padding:20px;border-radius:10px;margin-top:15px;font-family:monospace;font-size:.9em;line-height:1.9;border-left:4px solid #10b981}
</style>
</head>
<body>
<nav>
  <div class="logo"><i class="fas fa-rocket"></i> Create Panel</div>
  <a href="/dashboard"><i class="fas fa-arrow-left"></i> Kembali</a>
</nav>
<div class="container">
  <div class="card">
    <h2><i class="fas fa-plus-circle"></i> Buat Server Baru</h2>
    <div id="alert"></div>
    <form id="form">
      <label>Nama Server</label>
      <input name="name" placeholder="Server Saya" required>

      <label>Email Panel</label>
      <input name="email" type="email" placeholder="email@domain.com" required>

      <label>Username Panel</label>
      <input name="username" placeholder="username" required>

      <label>Password Panel</label>
      <input name="password" type="password" minlength="6" placeholder="min 6 karakter" required>

      <label>Pilih RAM Server</label>
      <div class="ram-grid" id="ramGrid">
        <div class="ram-opt" data-ram="1">1 GB</div>
        <div class="ram-opt" data-ram="2">2 GB</div>
        <div class="ram-opt" data-ram="3">3 GB</div>
        <div class="ram-opt" data-ram="4">4 GB</div>
        <div class="ram-opt" data-ram="5">5 GB</div>
        <div class="ram-opt" data-ram="8">8 GB</div>
        <div class="ram-opt" data-ram="10">10 GB</div>
        <div class="ram-opt unli" data-ram="0">♾️ Unli<small>Tanpa batas</small></div>
      </div>
      <input type="hidden" name="ram_gb" id="ramVal" value="1" required>

      <div class="tos-box">
        <h3><i class="fas fa-exclamation-triangle"></i> Syarat & Ketentuan (WAJIB)</h3>
        <ul>
          <li>Dilarang menggunakan server untuk DDOS / attack</li>
          <li>Dilarang membuat script mining crypto</li>
          <li>Dilarang menyebar link panel ke orang lain</li>
          <li>Dilarang menggunakan server untuk aktivitas ilegal</li>
          <li>Jaga kerahasiaan akun panel Anda</li>
          <li>Masa berlaku panel 1 bulan (bisa diperpanjang)</li>
          <li>Pelanggaran = banned permanen tanpa refund</li>
        </ul>
        <div class="tos-check">
          <input type="checkbox" id="tosChk" required>
          <label for="tosChk">Saya sudah membaca dan menyetujui semua syarat & ketentuan di atas</label>
        </div>
      </div>

      <button type="submit" class="submit" id="btnSubmit">
        <i class="fas fa-rocket"></i> Create Panel Sekarang
      </button>
    </form>
    <div id="result"></div>
  </div>
</div>
<script>
let selectedRam = 1;
document.querySelectorAll('.ram-opt').forEach(el => {
  el.onclick = () => {
    document.querySelectorAll('.ram-opt').forEach(x => x.classList.remove('selected'));
    el.classList.add('selected');
    selectedRam = parseInt(el.dataset.ram);
    document.getElementById('ramVal').value = selectedRam;
  };
});
document.querySelector('.ram-opt[data-ram="1"]').click();

document.getElementById('form').onsubmit = async (e) => {
  e.preventDefault();
  const btn = document.getElementById('btnSubmit');
  btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Membuat server...';
  const data = Object.fromEntries(new FormData(e.target));
  data.ram_gb = selectedRam;
  data.tos = document.getElementById('tosChk').checked ? 1 : 0;
  const al = document.getElementById('alert');
  al.innerHTML = '';
  try {
    const r = await fetch('/api/create-server', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    const j = await r.json();
    if (j.ok) {
      al.innerHTML = '<div class="alert alert-ok">✅ Server berhasil dibuat!</div>';
      document.getElementById('result').innerHTML = `
        <div class="cred-box">
          <div style="color:#10b981;font-weight:bold;margin-bottom:8px">✅ DATA AKUN PANEL ANDA</div>
          <div>👤 Username : ${j.data.username}</div>
          <div>🔑 Password : ${j.data.password}</div>
          <div>💾 RAM      : ${j.data.ram}</div>
          <div>🌐 Panel URL: <a href="${j.data.ptero_url}" target="_blank" style="color:#00d4ff">${j.data.ptero_url}</a></div>
          <div>📦 Server ID: ${j.data.server_id}</div>
          <div style="margin-top:12px;color:#f59e0b;font-size:.85em">Simpan data ini baik-baik!</div>
        </div>
        <a href="/dashboard" style="display:block;text-align:center;margin-top:15px;padding:12px;background:rgba(255,255,255,.1);border-radius:10px;color:#fff;text-decoration:none">← Kembali ke Dashboard</a>`;
      document.getElementById('form').style.display = 'none';
    } else {
      al.innerHTML = '<div class="alert alert-err">❌ '+j.msg+'</div>';
      btn.disabled = false; btn.innerHTML = '<i class="fas fa-rocket"></i> Create Panel Sekarang';
    }
  } catch(err) {
    al.innerHTML = '<div class="alert alert-err">❌ '+err.message+'</div>';
    btn.disabled = false; btn.innerHTML = '<i class="fas fa-rocket"></i> Create Panel Sekarang';
  }
};
</script>
</body>
</html>
HTMLEOF

# ---------- ADMIN ----------
cat > "$WEB_ROOT/views/admin.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Admin Panel</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:'Segoe UI',sans-serif}
body{background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);color:#fff;min-height:100vh}
nav{padding:15px 30px;display:flex;justify-content:space-between;align-items:center;background:rgba(0,0,0,.4);backdrop-filter:blur(10px);position:sticky;top:0;z-index:10}
.logo{font-size:1.3em;font-weight:bold;display:flex;align-items:center;gap:10px}
.logo i{color:#f59e0b}
nav a{color:#fff;text-decoration:none;padding:8px 14px;border-radius:8px;background:rgba(239,68,68,.2);display:inline-flex;align-items:center;gap:6px;font-size:.9em}
.container{max-width:1100px;margin:30px auto;padding:0 20px}
.tabs{display:flex;gap:8px;margin-bottom:20px;overflow-x:auto;flex-wrap:wrap}
.tab-btn{padding:10px 20px;border-radius:8px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);color:#fff;cursor:pointer;white-space:nowrap;font-size:.9em}
.tab-btn.active{background:linear-gradient(135deg,#667eea,#764ba2);border-color:transparent}
.tab-content{display:none}
.tab-content.active{display:block}
.card{background:rgba(255,255,255,.05);backdrop-filter:blur(10px);border:1px solid rgba(255,255,255,.1);padding:25px;border-radius:15px;margin-bottom:20px}
h2{margin-bottom:20px;display:flex;align-items:center;gap:10px}
h2 i{color:#f59e0b}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:15px;margin-bottom:20px}
.stat{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);padding:20px;border-radius:12px;text-align:center}
.stat .num{font-size:2em;font-weight:bold;color:#00d4ff}
.stat .lbl{color:#aaa;font-size:.85em;margin-top:5px}
table{width:100%;border-collapse:collapse;font-size:.9em}
th,td{padding:12px;text-align:left;border-bottom:1px solid rgba(255,255,255,.1)}
th{color:#aaa;font-size:.8em;text-transform:uppercase}
.btn-sm{padding:6px 12px;border-radius:6px;border:none;cursor:pointer;font-size:.85em;color:#fff}
.btn-del{background:rgba(239,68,68,.3);color:#ef4444}
label{display:block;margin-bottom:6px;font-size:.85em;color:#aaa;margin-top:10px}
input,select{width:100%;padding:11px;background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.15);border-radius:8px;color:#fff;font-size:1em;outline:none}
input:focus{border-color:#00d4ff}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:15px}
@media(max-width:600px){.grid{grid-template-columns:1fr}}
button.primary{padding:13px 25px;background:linear-gradient(135deg,#667eea,#764ba2);border:none;border-radius:10px;color:#fff;font-weight:bold;cursor:pointer;font-size:1em;margin-top:15px;display:inline-flex;align-items:center;gap:8px}
.alert{padding:12px;border-radius:8px;margin-bottom:15px;font-size:.9em}
.alert-ok{background:rgba(16,185,129,.15);color:#10b981;border:1px solid rgba(16,185,129,.3)}
.alert-err{background:rgba(239,68,68,.15);color:#ef4444;border:1px solid rgba(239,68,68,.3)}
</style>
</head>
<body>
<nav>
  <div class="logo"><i class="fas fa-shield-alt"></i> Admin Panel</div>
  <div style="display:flex;gap:10px;align-items:center">
    <span style="color:#aaa;font-size:.9em"><i class="fas fa-user-shield"></i> <span id="me">...</span></span>
    <a href="/api/logout"><i class="fas fa-sign-out-alt"></i> Logout</a>
  </div>
</nav>
<div class="container">
  <div id="alert"></div>
  <div class="tabs">
    <button class="tab-btn active" data-tab="overview"><i class="fas fa-chart-line"></i> Overview</button>
    <button class="tab-btn" data-tab="settings"><i class="fas fa-cog"></i> Pengaturan</button>
    <button class="tab-btn" data-tab="users"><i class="fas fa-users"></i> Users</button>
    <button class="tab-btn" data-tab="servers"><i class="fas fa-server"></i> Servers</button>
  </div>

  <div class="tab-content active" id="overview">
    <div class="stats">
      <div class="stat"><div class="num" id="st-users">0</div><div class="lbl">Total Users</div></div>
      <div class="stat"><div class="num" id="st-servers">0</div><div class="lbl">Total Servers</div></div>
    </div>
    <div class="card">
      <h2><i class="fas fa-info-circle"></i> Info</h2>
      <p style="color:#aaa;line-height:1.9">
        <b style="color:#00d4ff">Pengaturan</b> → atur URL Pterodactyl, PLTA Token, Egg, Location, Disk, CPU default<br>
        <b style="color:#00d4ff">Users</b> → kelola user terdaftar<br>
        <b style="color:#00d4ff">Servers</b> → lihat & hapus semua server<br><br>
        🎯 <b style="color:#f59e0b">RAM otomatis</b>: user pilih 1GB → Pterodactyl dapat 1024MB, dst.<br>
        🎯 <b style="color:#f59e0b">Unlimited</b> = 0 (tanpa limit di Pterodactyl)
      </p>
    </div>
  </div>

  <div class="tab-content" id="settings">
    <div class="card">
      <h2><i class="fas fa-cog"></i> Pengaturan</h2>
      <form id="form-settings">
        <label>Nama Situs</label>
        <input name="site_name">
        <label>URL Pterodactyl Panel</label>
        <input name="ptero_url" placeholder="https://panel.domain.com" required>
        <label>PTLA Token</label>
        <input name="plta" placeholder="ptla_xxxxxxxx" required>
        <div class="grid">
          <div><label>Egg ID</label><input name="egg" type="number" required></div>
          <div><label>Location ID</label><input name="loc" type="number" required></div>
          <div><label>Disk default (MB)</label><input name="disk" type="number" required></div>
          <div><label>CPU default (%)</label><input name="cpu" type="number" required></div>
        </div>
        <button type="submit" class="primary"><i class="fas fa-save"></i> Simpan</button>
      </form>
    </div>
  </div>

  <div class="tab-content" id="users">
    <div class="card">
      <h2><i class="fas fa-users"></i> Users</h2>
      <table>
        <thead><tr><th>ID</th><th>Username</th><th>Email</th><th>Role</th><th>Dibuat</th><th>Aksi</th></tr></thead>
        <tbody id="tbl-users"></tbody>
      </table>
    </div>
  </div>

  <div class="tab-content" id="servers">
    <div class="card">
      <h2><i class="fas fa-server"></i> Servers</h2>
      <table>
        <thead><tr><th>ID</th><th>Nama</th><th>User</th><th>RAM</th><th>Disk</th><th>CPU</th><th>Aksi</th></tr></thead>
        <tbody id="tbl-servers"></tbody>
      </table>
    </div>
  </div>
</div>
<script>
function alertBox(msg, ok=true){
  const el = document.getElementById('alert');
  el.innerHTML = `<div class="alert ${ok?'alert-ok':'alert-err'}">${ok?'✅':'❌'} ${msg}</div>`;
  setTimeout(()=>el.innerHTML='', 4000);
}
async function loadMe(){
  const j = await (await fetch('/api/me')).json();
  document.getElementById('me').textContent = j.username;
}
async function loadStats(){
  const j = await (await fetch('/api/admin/stats')).json();
  document.getElementById('st-users').textContent = j.users;
  document.getElementById('st-servers').textContent = j.servers;
}
async function loadSettings(){
  const j = await (await fetch('/api/admin/settings')).json();
  const f = document.getElementById('form-settings');
  for (const [k,v] of Object.entries(j)) if (f.elements[k]) f.elements[k].value = v;
}
async function loadUsers(){
  const arr = await (await fetch('/api/admin/users')).json();
  document.getElementById('tbl-users').innerHTML = arr.map(u => `
    <tr>
      <td>${u.id}</td>
      <td><b style="color:#00d4ff">${u.username}</b></td>
      <td>${u.email}</td>
      <td><span style="padding:3px 8px;border-radius:6px;font-size:.8em;background:${u.role==='admin'?'rgba(245,158,11,.2);color:#f59e0b':'rgba(0,212,255,.2);color:#00d4ff'}">${u.role}</span></td>
      <td>${new Date(u.created_at).toLocaleDateString('id-ID')}</td>
      <td>${u.role!=='admin'?`<button class="btn-sm btn-del" onclick="delUser(${u.id})"><i class="fas fa-trash"></i></button>`:'-'}</td>
    </tr>
  `).join('');
}
async function loadServers(){
  const arr = await (await fetch('/api/admin/servers')).json();
  document.getElementById('tbl-servers').innerHTML = arr.length ? arr.map(s => `
    <tr>
      <td>${s.id}</td>
      <td><b style="color:#00d4ff">${s.name}</b></td>
      <td>${s.username}</td>
      <td>${s.ram_gb===0?'♾️ Unli':s.ram_gb+' GB'}</td>
      <td>${s.disk===0?'♾️':s.disk+'MB'}</td>
      <td>${s.cpu===0?'♾️':s.cpu+'%'}</td>
      <td><button class="btn-sm btn-del" onclick="delServer(${s.id})"><i class="fas fa-trash"></i></button></td>
    </tr>
  `).join('') : '<tr><td colspan="7" style="text-align:center;color:#aaa">Belum ada</td></tr>';
}
async function delUser(id){
  if(!confirm('Hapus user?')) return;
  await fetch('/api/admin/users/'+id,{method:'DELETE'});
  loadUsers(); loadStats();
}
async function delServer(id){
  if(!confirm('Hapus server?')) return;
  await fetch('/api/admin/servers/'+id,{method:'DELETE'});
  loadServers(); loadStats();
}
document.getElementById('form-settings').onsubmit = async (e) => {
  e.preventDefault();
  const data = Object.fromEntries(new FormData(e.target));
  const r = await fetch('/api/admin/settings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
  const j = await r.json();
  if(j.ok) alertBox('Tersimpan!'); else alertBox(j.msg||'Gagal', false);
};
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.onclick = () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById(btn.dataset.tab).classList.add('active');
  };
});
loadMe(); loadStats(); loadSettings(); loadUsers(); loadServers();
</script>
</body>
</html>
HTMLEOF

echo -e "${GREEN}  ✓ Views OK${NC}"

# ============ 6. NGINX + PM2 ============
echo -e "${CYAN}[6/7] Setup Nginx & PM2...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
[[ -f /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 && systemctl reload nginx || { nginx -t; exit 1; }

cd "$WEB_ROOT"
pm2 delete webpanel >/dev/null 2>&1
pm2 start app.js --name webpanel >/dev/null 2>&1
pm2 save >/dev/null 2>&1
pm2 startup systemd -u root --hp /root >/dev/null 2>&1

ufw allow 22/tcp >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
echo "y" | ufw enable >/dev/null 2>&1

if [[ -z "$SKIP_SSL" ]]; then
  echo -e "${CYAN}[7/7] Setup SSL...${NC}"
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1
  if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    PROTO="https"
    echo -e "${GREEN}  ✓ SSL OK${NC}"
  else
    PROTO="http"
    echo -e "${YELLOW}  ⚠️ SSL gagal${NC}"
  fi
else
  PROTO="http"
fi

clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ INSTALL BERHASIL!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🌐 Panel   :${NC} $PROTO://$DOMAIN"
echo -e "${CYAN}⚙️  Setup   :${NC} $PROTO://$DOMAIN/setup"
echo -e "${CYAN}👤 Admin   :${NC} $PROTO://$DOMAIN/admin"
echo ""
echo -e "${YELLOW}📌 LANGKAH:${NC}"
echo -e "  1. Buka $PROTO://$DOMAIN/setup → isi PTLA, egg, location, admin"
echo -e "  2. Login → /admin → atur semua"
echo -e "  3. User daftar → /register → pilih RAM → centang TOS → create"
echo ""
echo -e "${MAGENTA}Cek status :${NC} pm2 status"
echo -e "${MAGENTA}Log        :${NC} pm2 logs webpanel"
echo -e "${GREEN}🎉 Selesai!${NC}"
