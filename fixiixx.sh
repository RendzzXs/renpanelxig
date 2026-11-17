#!/bin/bash
# ==========================================
# 🛠️ FIX DB ERROR - SISTEM SEKOLAH
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

read -p "👉 Masukkan Domain Web yang error (contoh: sekolahku.rendzzclouds.my.id): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Domain tidak boleh kosong!${NC}"; exit 1; }

WEB_ROOT="/var/www/$DOMAIN"
# Ini nama database yang dibuat oleh script installer lu sebelumnya
DB_NAME="school_db_$(echo $DOMAIN | tr '.' '_' | cut -c1-10)"
DB_USER="school_user"
DB_PASS=$(openssl rand -hex 12)

if [ ! -d "$WEB_ROOT" ]; then
    echo -e "${RED}❌ Folder web tidak ditemukan di $WEB_ROOT${NC}"; exit 1
fi

echo -e "${CYAN}[1/3] Bikin ulang / Ngecek User Database...${NC}"
# Kadang user database suka ilang pas restart, kita bikin ulang aja (kalo udah ada diabaikan)
mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"
echo -e "${GREEN}  ✅ Database OK${NC}"

echo -e "${CYAN}[2/3] Inject Config Baru ke Web...${NC}"
cat > "$WEB_ROOT/config.php" << PHPEOF
<?php
session_start();
define('DB_HOST', '127.0.0.1');
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASS', '$DB_PASS');
try {
    \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException \$e) { die("DB Error: " . \$e->getMessage()); }
function getSchool(\$pdo) { return \$pdo->query("SELECT * FROM school_info WHERE id=1")->fetch(); }
function isAdmin() { return isset(\$_SESSION['admin']); }
function requireAdmin() { if(!isAdmin()) { header('Location: login.php'); exit; } }
PHPEOF

echo -e "${CYAN}[3/3] Restart PHP & Nginx...${NC}"
chown -R www-data:www-data "$WEB_ROOT"
systemctl restart php8.3-fpm
systemctl reload nginx

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ DATABASE BERHASIL DIPERBAIKI!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠️  Silakan buka webnya lagi & tekan Ctrl+F5 (Clear Cache)${NC}"
echo -e "${GREEN}🚀 Error 'DB Error' harusnya udah hilang!${NC}"
