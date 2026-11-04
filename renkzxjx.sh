#!/bin/bash
# ============================================
#   👑 RENDZZ MASTER INSTALLER
#   Reset • Install • Update (All-in-One)
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  👑 RENDZZ MASTER INSTALLER v7.0           ║${NC}"
    echo -e "${CYAN}║  Reset • Install • Update Web Panel        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================
# FUNGSI: TOTAL RESET
# ============================================
do_reset() {
    echo -e "${RED}⚠️  PERINGATAN: Ini bakal hapus SEMUA web, database, & Pterodactyl!${NC}"
    read -p "Ketik 'HAPUS' untuk lanjut: " CONFIRM
    [[ "$CONFIRM" != "HAPUS" ]] && { echo -e "${YELLOW}Dibatalkan.${NC}"; return; }

    echo -e "\n${CYAN}[1/4] Berhenti & hapus service...${NC}"
    systemctl stop nginx php8.3-fpm mariadb redis-server 2>/dev/null
    apt purge -y nginx nginx-common php* mariadb-server mariadb-client mysql-server mysql-client nodejs npm redis-server certbot python3-certbot-nginx >/dev/null 2>&1
    apt autoremove -y >/dev/null 2>&1

    echo -e "${CYAN}[2/4] Hapus folder & config...${NC}"
    rm -rf /var/www/* /etc/nginx/sites-enabled/* /etc/nginx/sites-available/* /etc/nginx/conf.d/* /etc/mysql /var/lib/mysql/* /etc/php/8.3 /root/*.sh 2>/dev/null

    echo -e "${CYAN}[3/4] Install ulang FRESH...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt update -qq 2>/dev/null
    apt install -y software-properties-common curl wget git unzip >/dev/null 2>&1
    add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt update -qq 2>/dev/null
    apt install -y nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl php8.3-xml php8.3-zip php8.3-gd php8.3-intl php8.3-bcmath php8.3-redis mariadb-server nodejs redis-server certbot python3-certbot-nginx >/dev/null 2>&1

    # Fix MariaDB prompt
    export DEBIAN_FRONTEND=noninteractive
    apt install -y -o Dpkg::Options::="--force-confnew" mariadb-server >/dev/null 2>&1
    systemctl enable --now nginx php8.3-fpm mariadb redis-server >/dev/null 2>&1

    echo -e "${CYAN}[4/4] Bikin default page...${NC}"
    mkdir -p /var/www/html
    echo "<h1>🚀 VPS Fresh!</h1>" > /var/www/html/index.html
    cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html index.php;
    location / { try_files $uri $uri/ =404; }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    nginx -t >/dev/null 2>&1 && systemctl reload nginx

    echo -e "\n${GREEN}✅ VPS BERHASIL DI-RESET & FRESH INSTALL!${NC}"
}

# ============================================
# FUNGSI: INSTALL WEB RESELLER
# ============================================
do_install() {
    read -p "👉 Masukkan Subdomain Web (contoh: panel.domain.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Kosong!${NC}"; return; }
    read -p "👉 Email SSL (enter=skip): " EMAIL
    [[ -z "$EMAIL" ]] && EMAIL="admin@$DOMAIN"

    WEB_ROOT="/var/www/$DOMAIN"
    DB_NAME="reseller_$(echo $DOMAIN | tr '.' '_' | cut -c1-20)"
    DB_PASS=$(openssl rand -hex 12)
    NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

    # 1. Setup Nginx & PHP kalau belum
    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}⚠️ Nginx/PHP belum ada. Install dulu...${NC}"
        export DEBIAN_FRONTEND=noninteractive
        apt update -qq 2>/dev/null
        apt install -y nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl php8.3-xml php8.3-zip mariadb-server curl unzip >/dev/null 2>&1
        systemctl enable --now nginx php8.3-fpm mariadb >/dev/null 2>&1
    fi

    # 2. Setup Database
    echo -e "${CYAN}[1/4] Setup Database...${NC}"
    mysql -u root << SQLEOF 2>/dev/null
DROP DATABASE IF EXISTS \`$DB_NAME\`;
CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'reseller'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'reseller'@'localhost';
FLUSH PRIVILEGES;

USE \`$DB_NAME\`;

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin','user') DEFAULT 'user',
    status ENUM('active','banned') DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE servers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    server_name VARCHAR(100),
    ptero_id INT,
    ram INT,
    email VARCHAR(100) DEFAULT NULL,
    password VARCHAR(100) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE settings (
    k VARCHAR(50) PRIMARY KEY,
    v TEXT
);
CREATE TABLE chats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    username VARCHAR(50),
    message TEXT,
    is_admin TINYINT(1) DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE announcements (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO settings VALUES 
('ptero_domain', 'https://pterodactyl-anda.com'),
('ptla', 'ptla_xxx'),
('ptlc', 'ptlc_xxx'),
('location_id', '1'),
('egg_id', '15');
SQLEOF

    ADMIN_HASH=$(php -r "echo password_hash('admin123', PASSWORD_BCRYPT);")
    mysql -u root "$DB_NAME" -e "INSERT INTO users (username, email, password, role) VALUES ('admin', 'admin@$DOMAIN', '$ADMIN_HASH', 'admin');" 2>/dev/null

    echo -e "${GREEN}  ✓ Database OK${NC}"

    # 3. Bikin folder & file
    echo -e "${CYAN}[2/4] Setup File Web...${NC}"
    rm -rf "$WEB_ROOT"
    mkdir -p "$WEB_ROOT"/{includes,assets/css,api,admin}

    # --- CONFIG ---
    cat > "$WEB_ROOT/includes/config.php" << PHPEOF
<?php
session_start();
date_default_timezone_set('Asia/Jakarta');
define('DB_HOST', 'localhost');
define('DB_NAME', '$DB_NAME');
define('DB_USER', 'reseller');
define('DB_PASS', '$DB_PASS');
define('SITE_NAME', 'Rendzz Reseller');
try {
    \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException \$e) { die("DB Error: " . \$e->getMessage()); }
function isLoggedIn() { return isset(\$_SESSION['user_id']); }
function isAdmin() { return isLoggedIn() && \$_SESSION['role'] === 'admin'; }
function requireLogin() { if (!isLoggedIn()) { header('Location: /login.php'); exit; } }
function requireAdmin() { if (!isAdmin()) { header('Location: /'); exit; } }
function getSetting(\$pdo, \$k, \$default = '') {
    \$s = \$pdo->prepare("SELECT v FROM settings WHERE k=?"); \$s->execute([\$k]);
    \$r = \$s->fetch(); return \$r ? \$r['v'] : \$default;
}
function csrf() { if (empty(\$_SESSION['csrf'])) \$_SESSION['csrf'] = bin2hex(random_bytes(32)); return \$_SESSION['csrf']; }
function checkCsrf(\$t) { return isset(\$_SESSION['csrf']) && hash_equals(\$_SESSION['csrf'], \$t); }
PHPEOF

    # --- CSS ---
    cat > "$WEB_ROOT/assets/css/style.css" << 'CSSEOF'
:root { --bg: #09090b; --card: #18181b; --text: #fafafa; --muted: #a1a1aa; --border: #27272a; --primary: #6366f1; --success: #10b981; --danger: #ef4444; --warning: #f59e0b; }
* { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Inter', sans-serif; }
body { background: var(--bg); color: var(--text); min-height: 100vh; padding-bottom: 70px; }
a { color: inherit; text-decoration: none; }
.container { max-width: 800px; margin: 0 auto; padding: 20px; }
.card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 20px; margin-bottom: 15px; transition: all 0.3s; }
.card:hover { transform: translateY(-3px); border-color: rgba(99,102,241,0.4); box-shadow: 0 10px 30px rgba(99,102,241,0.1); }
.grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
@media(max-width: 600px) { .grid-2 { grid-template-columns: 1fr; } }
.btn { padding: 12px 20px; border-radius: 10px; border: none; font-weight: 700; font-family: inherit; cursor: pointer; display: inline-flex; align-items: center; justify-content: center; gap: 8px; transition: 0.2s; text-decoration: none; font-size: 0.95em; }
.btn-primary { background: var(--primary); color: #fff; }
.btn-primary:hover { transform: translateY(-2px); box-shadow: 0 8px 20px rgba(99,102,241,0.4); }
.btn-danger { background: var(--danger); color: #fff; }
.btn-block { width: 100%; }
.btn-sm { padding: 6px 12px; font-size: 0.85em; }
.form-group { margin-bottom: 15px; }
.form-group label { display: block; margin-bottom: 6px; font-size: 0.85em; color: var(--muted); font-weight: 600; }
.form-group input, .form-group select { width: 100%; padding: 12px 15px; border: 1px solid var(--border); border-radius: 10px; background: var(--bg); color: var(--text); font-family: inherit; font-size: 0.95em; outline: none; }
.form-group input:focus, .form-group select:focus { border-color: var(--primary); }
.alert { padding: 12px 16px; border-radius: 10px; margin-bottom: 15px; font-size: 0.9em; }
.alert-error { background: rgba(239,68,68,0.1); color: var(--danger); border: 1px solid rgba(239,68,68,0.2); }
.alert-success { background: rgba(16,185,129,0.1); color: var(--success); border: 1px solid rgba(16,185,129,0.2); }
.badge { padding: 4px 10px; border-radius: 6px; font-size: 0.75em; font-weight: 800; text-transform: uppercase; }
.badge-active { background: rgba(16,185,129,0.15); color: var(--success); }
.badge-banned { background: rgba(239,68,68,0.15); color: var(--danger); }
.table { width: 100%; border-collapse: collapse; font-size: 0.9em; }
.table th, .table td { padding: 12px; text-align: left; border-bottom: 1px solid var(--border); }
.table th { color: var(--muted); font-size: 0.8em; text-transform: uppercase; }
.bottom-nav { position: fixed; bottom: 0; left: 0; right: 0; background: rgba(24,24,27,0.95); backdrop-filter: blur(10px); border-top: 1px solid var(--border); display: flex; justify-content: space-around; padding: 10px 0; z-index: 9999; max-width: 800px; margin: 0 auto; }
.nav-item { display: flex; flex-direction: column; align-items: center; gap: 4px; color: var(--muted); font-size: 0.75em; font-weight: 600; padding: 5px 15px; border-radius: 12px; transition: 0.2s; }
.nav-item i { font-size: 1.4em; }
.nav-item:hover, .nav-item.active { color: var(--primary); background: rgba(99,102,241,0.1); }
.copyright { text-align: center; padding: 20px; font-size: 0.8em; color: var(--muted); margin-top: 30px; border-top: 1px solid var(--border); }
.copyright span { color: var(--primary); }
CSSEOF

    # --- HEADER ---
    cat > "$WEB_ROOT/includes/header.php" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?= $pageTitle ?? 'Home' ?> — <?= SITE_NAME ?></title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link rel="stylesheet" href="/assets/css/style.css">
</head>
<body>
HTMLEOF

    # --- FOOTER ---
    cat > "$WEB_ROOT/includes/footer.php" << 'HTMLEOF'
<?php if (isLoggedIn()): ?>
<div class="bottom-nav">
    <a href="/dashboard.php" class="nav-item <?= basename($_SERVER['PHP_SELF']) == 'dashboard.php' ? 'active' : '' ?>"><i class="fas fa-home"></i><span>Home</span></a>
    <a href="/chat.php" class="nav-item <?= basename($_SERVER['PHP_SELF']) == 'chat.php' ? 'active' : '' ?>"><i class="fas fa-comments"></i><span>Chat</span></a>
    <?php if (isAdmin()): ?><a href="/admin/" class="nav-item <?= strpos($_SERVER['PHP_SELF'], '/admin/') !== false ? 'active' : '' ?>"><i class="fas fa-crown" style="color:var(--warning)"></i><span>Admin</span></a><?php endif; ?>
    <a href="/profile.php" class="nav-item <?= basename($_SERVER['PHP_SELF']) == 'profile.php' ? 'active' : '' ?>"><i class="fas fa-user"></i><span>Profile</span></a>
</div>
<?php endif; ?>
<div class="copyright">&copy; <?= date('Y') ?> By <span>Rendzz Official</span></div>
</body>
</html>
HTMLEOF

    # --- INDEX ---
    cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
$pageTitle = 'Home';
include __DIR__ . '/includes/header.php';
?>
<div class="container" style="text-align:center; padding-top:80px;">
    <h1 style="font-size:2.5em; font-weight:800; margin-bottom:15px;">Buat Server <span style="color:var(--primary)">Otomatis</span></h1>
    <p style="color:var(--muted); font-size:1.1em; margin-bottom:30px;">Daftar sekarang, pilih RAM, dan server kamu langsung jadi!</p>
    <div style="display:flex; gap:10px; justify-content:center;">
        <a href="/register.php" class="btn btn-primary" style="font-size:1.1em; padding:15px 30px;">Mulai Sekarang</a>
        <a href="/login.php" class="btn" style="font-size:1.1em; padding:15px 30px; background:var(--card); color:var(--text);">Login</a>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

    # --- LOGIN ---
    cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /dashboard.php'); exit; }
$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $u = trim($_POST['username']); $p = $_POST['password'];
    $s = $pdo->prepare("SELECT * FROM users WHERE username=?"); $s->execute([$u]); $user = $s->fetch();
    if ($user && password_verify($p, $user['password'])) {
        if ($user['status'] === 'banned') { $err = 'Akun kamu dibanned!'; }
        else {
            $_SESSION['user_id'] = $user['id']; $_SESSION['username'] = $user['username']; $_SESSION['role'] = $user['role'];
            header('Location: /dashboard.php'); exit;
        }
    } else { $err = 'Login gagal!'; }
}
$pageTitle = 'Login'; include __DIR__ . '/includes/header.php';
?>
<div class="container" style="max-width:400px; margin-top:50px">
    <div class="card">
        <h2 style="text-align:center; margin-bottom:20px;">Login</h2>
        <?php if ($err): ?><div class="alert alert-error"><?= $err ?></div><?php endif; ?>
        <form method="POST">
            <div class="form-group"><label>Username</label><input type="text" name="username" required autofocus></div>
            <div class="form-group"><label>Password</label><input type="password" name="password" required></div>
            <button class="btn btn-primary btn-block">Masuk</button>
        </form>
        <p style="text-align:center; margin-top:15px; font-size:0.9em; color:var(--muted);">Belum punya akun? <a href="/register.php" style="color:var(--primary);">Daftar</a></p>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

    # --- REGISTER ---
    cat > "$WEB_ROOT/register.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /dashboard.php'); exit; }
$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $u = trim($_POST['username']); $e = trim($_POST['email']); $p = $_POST['password'];
    if (strlen($p) < 6) $err = 'Password min 6 karakter';
    else {
        $s = $pdo->prepare("SELECT id FROM users WHERE username=? OR email=?"); $s->execute([$u, $e]);
        if ($s->fetch()) $err = 'Username/Email sudah dipakai!';
        else {
            $pdo->prepare("INSERT INTO users (username, email, password) VALUES (?,?,?)")->execute([$u, $e, password_hash($p, PASSWORD_BCRYPT)]);
            header('Location: /login.php'); exit;
        }
    }
}
$pageTitle = 'Register'; include __DIR__ . '/includes/header.php';
?>
<div class="container" style="max-width:400px; margin-top:50px">
    <div class="card">
        <h2 style="text-align:center; margin-bottom:20px;">Daftar Akun</h2>
        <?php if ($err): ?><div class="alert alert-error"><?= $err ?></div><?php endif; ?>
        <form method="POST">
            <div class="form-group"><label>Username</label><input type="text" name="username" required></div>
            <div class="form-group"><label>Email</label><input type="email" name="email" required></div>
            <div class="form-group"><label>Password</label><input type="password" name="password" required></div>
            <button class="btn btn-primary btn-block">Daftar</button>
        </form>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

    # --- DASHBOARD ---
    cat > "$WEB_ROOT/dashboard.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
requireLogin();
$uid = $_SESSION['user_id'];
$s = $pdo->prepare("SELECT * FROM users WHERE id=?"); $s->execute([$uid]); $me = $s->fetch();
$ann = $pdo->query("SELECT * FROM announcements ORDER BY id DESC LIMIT 1")->fetch();
$msg = ''; $err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['create'])) {
    $serverName = trim($_POST['server_name']);
    $ram = (int)$_POST['ram'];
    if (!$serverName || !$ram) $err = 'Isi semua data!';
    else {
        $pteroDomain = rtrim(getSetting($pdo, 'ptero_domain'), '/');
        $ptla = getSetting($pdo, 'ptla');
        $loc = getSetting($pdo, 'location_id');
        $egg = getSetting($pdo, 'egg_id');
        $email = $me['username'] . rand(10,99) . "@rendzz.com";
        $password = "Pass" . rand(1000,9999) . "!";
        $headers = ["Accept: application/json", "Content-Type: application/json", "Authorization: Bearer $ptla"];
        
        $ch = curl_init("$pteroDomain/api/application/users");
        curl_setopt_array($ch, [CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $headers, CURLOPT_POSTFIELDS => json_encode(["email" => $email, "username" => $me['username'] . rand(100,999), "first_name" => $me['username'], "last_name" => "User", "password" => $password])]);
        $res = json_decode(curl_exec($ch), true); curl_close($ch);

        if (isset($res['errors'])) $err = 'Gagal buat user: ' . $res['errors'][0]['detail'];
        else {
            $pteroUserId = $res['attributes']['id'];
            $startup = 'if [[ -d .git ]] && [[ {{AUTO_UPDATE}} == "1" ]]; then git pull; fi; if [[ ! -z ${NODE_PACKAGES} ]]; then /usr/local/bin/npm install ${NODE_PACKAGES}; fi; if [[ ! -z ${UNNODE_PACKAGES} ]]; then /usr/local/bin/npm uninstall ${UNNODE_PACKAGES}; fi; if [ -f /home/container/package.json ]; then /usr/local/bin/npm install; fi; /usr/local/bin/${CMD_RUN}';
            $ch = curl_init("$pteroDomain/api/application/servers");
            curl_setopt_array($ch, [CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $headers, CURLOPT_POSTFIELDS => json_encode(["name" => $serverName, "description" => "Rendzz", "user" => $pteroUserId, "egg" => (int)$egg, "docker_image" => "ghcr.io/parkervcp/yolks:nodejs_20", "startup" => $startup, "environment" => ["INST" => "npm", "USER_UPLOAD" => "0", "AUTO_UPDATE" => "0", "CMD_RUN" => "npm start"], "limits" => ["memory" => $ram, "swap" => 0, "disk" => $ram * 2, "io" => 500, "cpu" => 100], "feature_limits" => ["databases" => 5, "backups" => 5, "allocations" => 1], "deploy" => ["locations" => [(int)$loc], "dedicated_ip" => false, "port_range" => []]])]);
            $res2 = json_decode(curl_exec($ch), true); curl_close($ch);

            if (isset($res2['errors'])) $err = 'Gagal buat server: ' . $res2['errors'][0]['detail'];
            else {
                $pteroServerId = $res2['attributes']['id'];
                $pdo->prepare("INSERT INTO servers (user_id, server_name, ptero_id, ram, email, password) VALUES (?,?,?,?,?,?)")->execute([$uid, $serverName, $pteroServerId, $ram, $email, $password]);
                $msg = "Server <b>$serverName</b> berhasil dibuat!";
            }
        }
    }
}
$pageTitle = 'Dashboard'; include __DIR__ . '/includes/header.php';
?>
<div class="container">
    <?php if ($ann): ?><div style="background:rgba(245,158,11,0.15); border:1px solid var(--warning); color:var(--warning); padding:15px; border-radius:12px; margin-bottom:20px; font-size:0.9em; font-weight:600;"><i class="fas fa-bullhorn"></i> <b>Pengumuman:</b> <?= htmlspecialchars($ann['message']) ?></div><?php endif; ?>
    <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
    <?php if ($err): ?><div class="alert alert-error"><?= $err ?></div><?php endif; ?>

    <div class="card" style="background:linear-gradient(135deg, rgba(99,102,241,0.15), transparent);">
        <h1 style="font-size:1.5em; margin-bottom:5px;">Halo, <?= htmlspecialchars($me['username']) ?>! 👋</h1>
        <p style="color:var(--muted); font-size:0.9em;">Siap deploy server baru hari ini?</p>
    </div>

    <div class="card">
        <h2 style="margin-bottom:15px; font-size:1.2em;"><i class="fas fa-rocket" style="color:var(--primary)"></i> Deploy Server</h2>
        <form method="POST">
            <input type="hidden" name="create" value="1">
            <div class="form-group"><label>Nama Server</label><input type="text" name="server_name" placeholder="Contoh: Bot WhatsApp" required></div>
            <div class="form-group">
                <label>Pilih RAM</label>
                <select name="ram" required>
                    <option value="1024">1 GB</option>
                    <option value="2048">2 GB</option>
                    <option value="3072">3 GB</option>
                    <option value="4096">4 GB</option>
                    <option value="8192">8 GB</option>
                    <option value="0">Unlimited (∞)</option>
                </select>
            </div>
            <button class="btn btn-primary btn-block"><i class="fas fa-bolt"></i> Deploy Sekarang</button>
        </form>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

    # --- PROFILE ---
    cat > "$WEB_ROOT/profile.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
requireLogin();
$uid = $_SESSION['user_id'];
$s = $pdo->prepare("SELECT * FROM users WHERE id=?"); $s->execute([$uid]); $me = $s->fetch();
$servers = $pdo->prepare("SELECT * FROM servers WHERE user_id=? ORDER BY id DESC"); $servers->execute([$uid]); $servers = $servers->fetchAll();
$pageTitle = 'Profile'; include __DIR__ . '/includes/header.php';
?>
<div class="container">
    <div class="card" style="text-align:center; background:linear-gradient(135deg, rgba(99,102,241,0.1), transparent);">
        <div style="width:80px;height:80px;border-radius:50%;background:linear-gradient(135deg,var(--primary),#8b5cf6);display:flex;align-items:center;justify-content:center;font-size:2em;font-weight:800;color:#fff;margin:0 auto 15px;"><?= strtoupper(substr($me['username'],0,1)) ?></div>
        <h1 style="font-size:1.5em;">@<?= htmlspecialchars($me['username']) ?></h1>
        <p style="color:var(--muted); font-size:0.9em;"><?= htmlspecialchars($me['email']) ?></p>
    </div>

    <h2 style="font-size:1.2em; margin-bottom:15px;"><i class="fas fa-server" style="color:var(--primary)"></i> My Servers (<?= count($servers) ?>)</h2>
    <?php if (empty($servers)): ?>
        <div class="card" style="text-align:center; padding:40px; color:var(--muted);"><p>Belum ada server.</p></div>
    <?php else: foreach ($servers as $srv): ?>
        <div class="card">
            <div style="display:flex; justify-content:space-between; margin-bottom:10px;">
                <div><div style="font-weight:800;"><?= htmlspecialchars($srv['server_name']) ?></div><div style="font-size:0.85em; color:var(--muted);">RAM: <?= $srv['ram']==0?'∞':$srv['ram'].'MB' ?></div></div>
                <span class="badge badge-active">Active</span>
            </div>
            <div style="background:var(--bg); padding:12px; border-radius:10px; border:1px solid var(--border); font-size:0.85em; margin-bottom:10px;">
                <div><i class="fas fa-envelope" style="color:var(--muted);"></i> <?= htmlspecialchars($srv['email'] ?? '-') ?></div>
                <div><i class="fas fa-key" style="color:var(--muted);"></i> <?= htmlspecialchars($srv['password'] ?? '-') ?></div>
            </div>
            <a href="<?= htmlspecialchars(rtrim(getSetting($pdo, 'ptero_domain'), '/')) ?>" target="_blank" class="btn btn-primary btn-block" style="font-size:0.9em; padding:10px;"><i class="fas fa-external-link-alt"></i> Buka Panel</a>
        </div>
    <?php endforeach; endif; ?>

    <a href="/logout.php" class="btn btn-block" style="background:rgba(239,68,68,0.1); color:var(--danger); margin-top:20px;">Logout</a>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

    # --- LOGOUT ---
    cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); header('Location: /login.php'); exit;
PHPEOF

    # --- CHAT API ---
    cat > "$WEB_ROOT/api/chat.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
header('Content-Type: application/json');
if (!isLoggedIn()) { echo json_encode(['ok'=>false, 'error'=>'Login']); exit; }
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $s = $pdo->query("SELECT * FROM chats ORDER BY id ASC LIMIT 50");
    echo json_encode(['ok' => true, 'chats' => $s->fetchAll()]);
    exit;
}
$input = json_decode(file_get_contents('php://input'), true);
$msg = trim($input['message'] ?? '');
if ($msg) {
    $u = $pdo->prepare("SELECT username FROM users WHERE id=?"); $u->execute([$_SESSION['user_id']]); $user = $u->fetch();
    $pdo->prepare("INSERT INTO chats (user_id, username, message, is_admin) VALUES (?,?,?,?)")->execute([$_SESSION['user_id'], $user['username'], $msg, isAdmin() ? 1 : 0]);
    echo json_encode(['ok' => true]);
} else { echo json_encode(['ok' => false]); }
PHPEOF

    # --- CHAT PAGE ---
    cat > "$WEB_ROOT/chat.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
requireLogin();
$pageTitle = 'Global Chat'; include __DIR__ . '/includes/header.php';
?>
<div class="container" style="max-width:700px;">
    <div class="card" style="padding:0; overflow:hidden; height:75vh; display:flex; flex-direction:column;">
        <div style="padding:15px; border-bottom:1px solid var(--border); background:var(--bg-card); display:flex; align-items:center; gap:10px;">
            <div style="width:40px;height:40px;border-radius:50%;background:var(--primary);display:flex;align-items:center;justify-content:center;color:#fff;">💬</div>
            <div><div style="font-weight:700;">Global Chat</div><div style="font-size:0.8em; color:var(--success);">● Live</div></div>
        </div>
        <div id="chatBox" style="flex:1; overflow-y:auto; padding:20px; display:flex; flex-direction:column; gap:10px; background:rgba(0,0,0,0.2);"></div>
        <div style="padding:15px; border-top:1px solid var(--border); display:flex; gap:10px; background:var(--bg-card);">
            <input type="text" id="chatInput" placeholder="Ketik pesan..." style="flex:1; padding:12px; border-radius:10px; border:1px solid var(--border); background:var(--bg); color:var(--text); outline:none;">
            <button class="btn btn-primary" onclick="sendMsg()"><i class="fas fa-paper-plane"></i></button>
        </div>
    </div>
</div>
<script>
const chatBox = document.getElementById('chatBox'), chatInput = document.getElementById('chatInput');
const myUser = "<?= htmlspecialchars($_SESSION['username']) ?>";
async function loadChat() {
    const res = await fetch('/api/chat.php'); const data = await res.json();
    if (!data.ok) return;
    const isBottom = chatBox.scrollHeight - chatBox.scrollTop <= chatBox.clientHeight + 50;
    chatBox.innerHTML = data.chats.map(c => {
        const isMe = c.username === myUser;
        const isAdmin = c.is_admin == 1;
        const badge = isAdmin ? '<i class="fas fa-circle-check" style="color:#3b82f6;"></i>' : '';
        const bg = isMe ? 'var(--primary)' : (isAdmin ? 'rgba(245,158,11,0.2)' : 'var(--bg)');
        const color = isMe ? '#fff' : 'var(--text)';
        const align = isMe ? 'flex-end' : 'flex-start';
        return `<div style="display:flex; flex-direction:column; align-items:${align};"><div style="font-size:0.75em; color:var(--muted); margin-bottom:2px;"><b style="color:${isAdmin?'var(--warning)':'var(--muted)'}">${c.username}</b> ${badge}</div><div style="background:${bg}; color:${color}; padding:10px 15px; border-radius:16px; max-width:80%; border:${isAdmin?'1px solid rgba(245,158,11,0.4)':'none'};">${c.message}</div></div>`;
    }).join('');
    if (isBottom) chatBox.scrollTop = chatBox.scrollHeight;
}
async function sendMsg() {
    const msg = chatInput.value.trim(); if (!msg) return;
    chatInput.value = '';
    await fetch('/api/chat.php', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ message: msg }) });
    loadChat(); chatBox.scrollTop = chatBox.scrollHeight;
}
chatInput.addEventListener('keypress', e => { if (e.key === 'Enter') sendMsg(); });
loadChat(); setInterval(loadChat, 2000);
</script>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

    # --- ADMIN DASHBOARD ---
    cat > "$WEB_ROOT/admin/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['save_api'])) {
    foreach (['ptero_domain', 'ptla', 'location_id', 'egg_id'] as $k) {
        if (isset($_POST[$k])) $pdo->prepare("UPDATE settings SET v=? WHERE k=?")->execute([trim($_POST[$k]), $k]);
    }
    $msg = '✅ API Disimpan!';
}
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['toggle_ban'])) {
    $uid = (int)$_POST['uid']; $new = $_POST['current_status'] === 'active' ? 'banned' : 'active';
    $pdo->prepare("UPDATE users SET status=? WHERE id=?")->execute([$new, $uid]);
    $msg = '✅ Status user diubah!';
}
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete_server'])) {
    $srvId = (int)$_POST['srv_id']; $pteroId = (int)$_POST['ptero_id'];
    $pteroDomain = rtrim(getSetting($pdo, 'ptero_domain'), '/'); $ptla = getSetting($pdo, 'ptla');
    $ch = curl_init("$pteroDomain/api/application/servers/$pteroId");
    curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST => "DELETE", CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => ["Authorization: Bearer $ptla"]]);
    curl_exec($ch); curl_close($ch);
    $pdo->prepare("DELETE FROM servers WHERE id=?")->execute([$srvId]);
    $msg = '✅ Server dihapus!';
}
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['broadcast'])) {
    $bc = trim($_POST['message']);
    if ($bc) { $pdo->prepare("INSERT INTO announcements (message) VALUES (?)")->execute([$bc]); $msg = '✅ Broadcast terkirim!'; }
}

$totalUsers = $pdo->query("SELECT COUNT(*) FROM users WHERE role='user'")->fetchColumn();
$totalServers = $pdo->query("SELECT COUNT(*) FROM servers")->fetchColumn();
$users = $pdo->query("SELECT * FROM users WHERE role='user' ORDER BY id DESC")->fetchAll();
$servers = $pdo->query("SELECT s.*, u.username FROM servers s JOIN users u ON s.user_id=u.id ORDER BY s.id DESC")->fetchAll();

$pageTitle = 'X-Admin'; include __DIR__ . '/../includes/header.php';
?>
<div class="container">
    <?php if ($msg): ?><div class="alert alert-success"><?= $msg ?></div><?php endif; ?>
    <h1 style="margin-bottom:20px;"><i class="fas fa-shield-alt" style="color:var(--warning)"></i> Admin Panel</h1>
    
    <div style="display:grid; grid-template-columns:1fr 1fr; gap:15px; margin-bottom:20px;">
        <div class="card" style="text-align:center;"><div style="font-size:0.85em; color:var(--muted);">Total User</div><div style="font-size:2em; font-weight:800; color:var(--primary);"><?= $totalUsers ?></div></div>
        <div class="card" style="text-align:center;"><div style="font-size:0.85em; color:var(--muted);">Total Server</div><div style="font-size:2em; font-weight:800; color:var(--success);"><?= $totalServers ?></div></div>
    </div>

    <div style="display:flex; gap:10px; margin-bottom:20px; overflow-x:auto;">
        <button onclick="tab('api')" id="btn-api" class="btn btn-primary btn-sm">API</button>
        <button onclick="tab('users')" id="btn-users" class="btn btn-sm" style="background:var(--card); color:var(--text);">Users</button>
        <button onclick="tab('servers')" id="btn-servers" class="btn btn-sm" style="background:var(--card); color:var(--text);">Servers</button>
        <button onclick="tab('bc')" id="btn-bc" class="btn btn-sm" style="background:var(--card); color:var(--text);">Broadcast</button>
    </div>

    <div id="tab-api" class="tab-content card">
        <h2 style="margin-bottom:15px;">Setting Pterodactyl API</h2>
        <form method="POST">
            <input type="hidden" name="save_api" value="1">
            <div class="form-group"><label>Domain Pterodactyl</label><input type="text" name="ptero_domain" value="<?= htmlspecialchars(getSetting($pdo, 'ptero_domain')) ?>" required></div>
            <div class="form-group"><label>PTLA (Application API Key)</label><input type="text" name="ptla" value="<?= htmlspecialchars(getSetting($pdo, 'ptla')) ?>" required></div>
            <div class="grid-2"><div class="form-group"><label>Location ID</label><input type="number" name="location_id" value="<?= htmlspecialchars(getSetting($pdo, 'location_id', '1')) ?>"></div><div class="form-group"><label>Egg ID</label><input type="number" name="egg_id" value="<?= htmlspecialchars(getSetting($pdo, 'egg_id', '15')) ?>"></div></div>
            <button class="btn btn-primary">Simpan</button>
        </form>
    </div>

    <div id="tab-users" class="tab-content card" style="display:none;">
        <h2 style="margin-bottom:15px;">Kelola User</h2>
        <table class="table"><thead><tr><th>User</th><th>Email</th><th>Status</th><th>Aksi</th></tr></thead>
        <tbody><?php foreach ($users as $u): ?>
            <tr><td><b>@<?= htmlspecialchars($u['username']) ?></b></td><td><small><?= htmlspecialchars($u['email']) ?></small></td><td><span class="badge badge-<?= $u['status'] ?>"><?= $u['status'] ?></span></td><td>
            <form method="POST" style="display:inline;"><input type="hidden" name="uid" value="<?= $u['id'] ?>"><input type="hidden" name="current_status" value="<?= $u['status'] ?>"><button name="toggle_ban" class="btn btn-sm" style="background:<?= $u['status']=='active'?'var(--danger)':'var(--success)' ?>;color:#fff;"><?= $u['status']=='active'?'Ban':'Unban' ?></button></form>
            </td></tr>
        <?php endforeach; ?></tbody></table>
    </div>

    <div id="tab-servers" class="tab-content card" style="display:none;">
        <h2 style="margin-bottom:15px;">Semua Server</h2>
        <?php foreach ($servers as $s): ?>
            <div style="background:var(--bg); padding:15px; border-radius:10px; margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;">
                <div><div style="font-weight:800;"><?= htmlspecialchars($s['server_name']) ?></div><div style="font-size:0.85em; color:var(--muted);">@<?= htmlspecialchars($s['username']) ?> • RAM: <?= $s['ram']==0?'∞':$s['ram'].'MB' ?></div></div>
                <form method="POST" onsubmit="return confirm('Hapus server?')"><input type="hidden" name="srv_id" value="<?= $s['id'] ?>"><input type="hidden" name="ptero_id" value="<?= $s['ptero_id'] ?>"><button name="delete_server" class="btn btn-sm" style="background:var(--danger); color:#fff;"><i class="fas fa-trash"></i></button></form>
            </div>
        <?php endforeach; ?>
    </div>

    <div id="tab-bc" class="tab-content card" style="display:none;">
        <h2 style="margin-bottom:15px;">Broadcast</h2>
        <form method="POST"><input type="hidden" name="broadcast" value="1"><div class="form-group"><textarea name="message" rows="4" style="width:100%; padding:12px; border-radius:10px; background:var(--bg); border:1px solid var(--border); color:var(--text);" required></textarea></div><button class="btn btn-primary">Kirim ke Semua User</button></form>
    </div>
</div>
<script>
function tab(name) {
    document.querySelectorAll('.tab-content').forEach(el => el.style.display = 'none');
    document.querySelectorAll('button[id^="btn-"]').forEach(el => { el.style.background = 'var(--card)'; el.style.color = 'var(--text)'; });
    document.getElementById('tab-' + name).style.display = 'block';
    document.getElementById('btn-' + name).style.background = 'var(--primary)';
    document.getElementById('btn-' + name).style.color = '#fff';
}
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

    # --- NGINX ---
    cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;
    location / { try_files \$uri \$uri/ =404; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
}
NGINXEOF

    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null
    [[ -f /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default
    nginx -t >/dev/null 2>&1 && systemctl reload nginx

    echo -e "${GREEN}  ✓ File Web OK${NC}"

    echo -e "${CYAN}[3/4] Fix Permission...${NC}"
    chown -R www-data:www-data "$WEB_ROOT"
    chmod -R 755 "$WEB_ROOT"
    systemctl restart php8.3-fpm

    echo -e "${CYAN}[4/4] Setup SSL...${NC}"
    SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
    DOMAIN_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | head -1)
    if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1
    fi

    PROTO="https"; [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] && PROTO="http"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ WEB PANEL BERHASIL DI-INSTALL!         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}🔗 URL:${NC} $PROTO://$DOMAIN"
    echo -e "${MAGENTA}🔒 Admin:${NC} $PROTO://$DOMAIN/admin/"
    echo -e "  Username: admin"
    echo -e "  Password: admin123"
    echo ""
}

# ============================================
# MENU UTAMA
# ============================================
while true; do
    show_header
    echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║           👑 PILIH MENU 👑                 ║${NC}"
    echo -e "${WHITE}╠════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║  ${RED}[1]${NC} 💥 RESET TOTAL & INSTALL FRESH     ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${GREEN}[2]${NC} 🚀 INSTALL / UPDATE WEB PANEL       ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${BLUE}[x]${NC} ❌ KELUAR                          ${WHITE}║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "${YELLOW}➤ Pilih menu [1/2/x]: ${NC}"
    read MENU

    case $MENU in
        1) do_reset; echo -e "\n${CYAN}Tekan Enter...${NC}"; read ;;
        2) do_install; echo -e "\n${CYAN}Tekan Enter...${NC}"; read ;;
        x) echo -e "\n${GREEN}👋 Bye!${NC}\n"; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
    esac
done
