#!/bin/bash
# ============================================================
#   🔧 WEB PANEL AUTO FIX SCRIPT
#   Deteksi & perbaiki error PM2 otomatis
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Jalankan sebagai root!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🔧 WEB PANEL AUTO FIX                     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

# === CARI FOLDER WEBPANEL ===
FOUND=""
for d in /var/www/*/; do
  if [[ -f "$d/app.js" && -f "$d/.env" ]]; then
    FOUND="$d"
    break
  fi
done

if [[ -z "$FOUND" ]]; then
  echo -e "${YELLOW}⚠️  Folder webpanel tidak auto-detect${NC}"
  read -p "👉 Masukkan path folder webpanel (contoh /var/www/panel.domain.com): " FOUND
  FOUND="${FOUND%/}"
  [[ ! -f "$FOUND/app.js" ]] && { echo -e "${RED}❌ app.js tidak ditemukan di $FOUND${NC}"; exit 1; }
fi

WEB_ROOT="$FOUND"
cd "$WEB_ROOT" || { echo -e "${RED}❌ Tidak bisa masuk folder${NC}"; exit 1; }

echo -e "${GREEN}📁 Folder :${NC} $WEB_ROOT"
echo ""

# === 1. CEK NODE.JS ===
echo -e "${CYAN}[1/8] Cek Node.js...${NC}"
if ! command -v node >/dev/null 2>&1; then
  echo -e "${YELLOW}  ⚠️ Node.js tidak ada, install...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  apt install -y nodejs >/dev/null 2>&1
fi
echo -e "${GREEN}  ✓ Node.js $(node -v)${NC}"

# === 2. CEK PM2 ===
echo -e "${CYAN}[2/8] Cek PM2...${NC}"
if ! command -v pm2 >/dev/null 2>&1; then
  echo -e "${YELLOW}  ⚠️ Install PM2...${NC}"
  npm install -g pm2 >/dev/null 2>&1
fi
echo -e "${GREEN}  ✓ PM2 $(pm2 -v)${NC}"

# === 3. CEK .ENV ===
echo -e "${CYAN}[3/8] Cek .env...${NC}"
if [[ ! -f .env ]]; then
  echo -e "${YELLOW}  ⚠️ .env hilang, buat baru...${NC}"
  DOMAIN_NAME=$(basename "$WEB_ROOT")
  cat > .env << EOF
PORT=3000
DOMAIN=$DOMAIN_NAME
SESSION_SECRET=$(openssl rand -hex 32)
EOF
  chmod 600 .env
  echo -e "${GREEN}  ✓ .env dibuat${NC}"
else
  # pastikan ada PORT & SESSION_SECRET
  if ! grep -q "^PORT=" .env; then
    echo "PORT=3000" >> .env
  fi
  if ! grep -q "^SESSION_SECRET=" .env; then
    echo "SESSION_SECRET=$(openssl rand -hex 32)" >> .env
  fi
  if ! grep -q "^DOMAIN=" .env; then
    DOMAIN_NAME=$(basename "$WEB_ROOT")
    echo "DOMAIN=$DOMAIN_NAME" >> .env
  fi
  echo -e "${GREEN}  ✓ .env OK${NC}"
fi

# === 4. CEK VIEWS ===
echo -e "${CYAN}[4/8] Cek views...${NC}"
mkdir -p views public
REQUIRED_VIEWS=("setup.html" "landing.html" "login.html" "register.html" "dashboard.html" "create.html" "admin.html")
MISSING=""
for v in "${REQUIRED_VIEWS[@]}"; do
  [[ ! -f "views/$v" ]] && MISSING="$MISSING $v"
done
if [[ -n "$MISSING" ]]; then
  echo -e "${YELLOW}  ⚠️ View hilang:$MISSING${NC}"
  echo -e "${YELLOW}  → Akan dibuat placeholder. Install ulang script untuk tampilan lengkap.${NC}"
  for v in $MISSING; do
    cat > "views/$v" << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>Loading...</title></head>
<body style="background:#0f0c29;color:#fff;font-family:sans-serif;text-align:center;padding:50px">
<h1>⚠️ Halaman Belum Tersedia</h1>
<p>Jalankan installer ulang untuk mendapat tampilan lengkap.</p>
<a href="/setup" style="color:#00d4ff">Setup</a>
</body></html>
HTMLEOF
  done
  echo -e "${GREEN}  ✓ Placeholder dibuat${NC}"
else
  echo -e "${GREEN}  ✓ Semua view OK${NC}"
fi

# === 5. CEK PORT 3000 ===
echo -e "${CYAN}[5/8] Cek port 3000...${NC}"
PORT_USED=$(ss -tlnp 2>/dev/null | grep ':3000 ' | awk '{print $NF}' | head -1)
if [[ -n "$PORT_USED" ]]; then
  echo -e "${YELLOW}  ⚠️ Port 3000 dipakai: $PORT_USED${NC}"
  echo -e "${YELLOW}  → Mencoba bebaskan port...${NC}"
  pm2 delete webpanel >/dev/null 2>&1
  fuser -k 3000/tcp >/dev/null 2>&1
  sleep 2
  PORT_USED=$(ss -tlnp 2>/dev/null | grep ':3000 ' | awk '{print $NF}' | head -1)
  if [[ -n "$PORT_USED" ]]; then
    # ganti port ke 3001
    echo -e "${YELLOW}  → Port 3000 masih sibuk, ganti ke 3001${NC}"
    sed -i 's/^PORT=.*/PORT=3001/' .env
    NEW_PORT=3001
  else
    NEW_PORT=3000
    echo -e "${GREEN}  ✓ Port 3000 dibebaskan${NC}"
  fi
else
  NEW_PORT=3000
  echo -e "${GREEN}  ✓ Port 3000 kosong${NC}"
fi

# === 6. REINSTALL NODE_MODULES ===
echo -e "${CYAN}[6/8] Reinstall npm modules...${NC}"
rm -rf node_modules package-lock.json
npm init -y >/dev/null 2>&1
npm install express express-session better-sqlite3 bcryptjs dotenv node-fetch@2 2>&1 | tail -3
if [[ -d "node_modules/express" ]]; then
  echo -e "${GREEN}  ✓ Modules OK${NC}"
else
  echo -e "${RED}  ✗ Install gagal! Coba manual: npm install${NC}"
  exit 1
fi

# === 7. TEST RUN ===
echo -e "${CYAN}[7/8] Test jalankan app.js...${NC}"
TEST_OUT=$(timeout 6 node app.js 2>&1)
EXIT_CODE=$?
if [[ "$TEST_OUT" == *"running on port"* ]]; then
  echo -e "${GREEN}  ✓ app.js berjalan normal${NC}"
else
  echo -e "${RED}  ✗ app.js error:${NC}"
  echo "$TEST_OUT" | head -20
  echo ""
  echo -e "${YELLOW}  → Coba detect & fix error umum...${NC}"

  # Fix: node-fetch versi salah
  if echo "$TEST_OUT" | grep -q "Cannot use import statement\|ERR_REQUIRE_ESM"; then
    echo -e "${YELLOW}  → node-fetch versi salah, install v2...${NC}"
    npm uninstall node-fetch >/dev/null 2>&1
    npm install node-fetch@2 >/dev/null 2>&1
  fi

  # Fix: better-sqlite3 native build error
  if echo "$TEST_OUT" | grep -q "better-sqlite3\|NODE_MODULE_VERSION"; then
    echo -e "${YELLOW}  → Rebuild better-sqlite3...${NC}"
    npm rebuild better-sqlite3 >/dev/null 2>&1
    apt install -y build-essential python3 >/dev/null 2>&1
    npm rebuild better-sqlite3 >/dev/null 2>&1
  fi

  # Fix: sqlite can't open
  if echo "$TEST_OUT" | grep -q "SQLITE_CANTOPEN\|SQLITE_READONLY"; then
    echo -e "${YELLOW}  → Fix permission database...${NC}"
    chmod 755 "$WEB_ROOT"
    touch panel.db 2>/dev/null
    chmod 666 panel.db 2>/dev/null
  fi

  # Fix: module missing
  MISSING_MOD=$(echo "$TEST_OUT" | grep -oP "Cannot find module '\K[^']+" | head -1)
  if [[ -n "$MISSING_MOD" ]]; then
    echo -e "${YELLOW}  → Install module: $MISSING_MOD${NC}"
    npm install "$MISSING_MOD" >/dev/null 2>&1
  fi

  # Coba test lagi
  echo -e "${CYAN}  → Test ulang...${NC}"
  TEST_OUT2=$(timeout 6 node app.js 2>&1)
  if [[ "$TEST_OUT2" == *"running on port"* ]]; then
    echo -e "${GREEN}  ✓ Sekarang OK!${NC}"
  else
    echo -e "${RED}  ✗ Masih error:${NC}"
    echo "$TEST_OUT2" | head -15
    echo ""
    echo -e "${YELLOW}Kirim log di atas untuk bantuan lanjut.${NC}"
    exit 1
  fi
fi

# === 8. RESTART PM2 ===
echo -e "${CYAN}[8/8] Restart PM2...${NC}"
pm2 delete webpanel >/dev/null 2>&1
pm2 start app.js --name webpanel >/dev/null 2>&1
pm2 save >/dev/null 2>&1
pm2 startup systemd -u root --hp /root >/dev/null 2>&1

sleep 2
STATUS=$(pm2 jlist 2>/dev/null | grep -oP '"name":"webpanel","pm2_env":\{[^}]*"status":"\K[^"]+' | head -1)
if [[ "$STATUS" == "online" ]]; then
  echo -e "${GREEN}  ✓ PM2 online${NC}"
else
  echo -e "${RED}  ✗ PM2 status: $STATUS${NC}"
  echo -e "${YELLOW}  Cek log:${NC} pm2 logs webpanel --lines 30"
  exit 1
fi

# === CEK NGINX ===
echo -e "${CYAN}[+] Cek Nginx...${NC}"
NGINX_DOMAIN=$(basename "$WEB_ROOT")
NGINX_CONF="/etc/nginx/sites-available/$NGINX_DOMAIN"
if [[ -f "$NGINX_CONF" ]]; then
  # pastikan port proxy sesuai
  CURRENT_PROXY=$(grep -oP 'proxy_pass http://127.0.0.1:\K[0-9]+' "$NGINX_CONF" | head -1)
  if [[ "$CURRENT_PROXY" != "$NEW_PORT" ]]; then
    echo -e "${YELLOW}  → Update nginx proxy ke port $NEW_PORT${NC}"
    sed -i "s|proxy_pass http://127.0.0.1:[0-9]*|proxy_pass http://127.0.0.1:$NEW_PORT|g" "$NGINX_CONF"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx
  fi
  echo -e "${GREEN}  ✓ Nginx OK${NC}"
else
  echo -e "${YELLOW}  ⚠️ Nginx config tidak ditemukan: $NGINX_CONF${NC}"
fi

# === SELESAI ===
clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ AUTO FIX SELESAI!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📁 Folder     :${NC} $WEB_ROOT"
echo -e "${CYAN}🔌 Port app   :${NC} $NEW_PORT"
echo -e "${CYAN}📊 PM2 status :${NC} $(pm2 jlist 2>/dev/null | grep -oP '"name":"webpanel","pm2_env":\{[^}]*"status":"\K[^"]+' | head -1)"
echo ""
echo -e "${YELLOW}📌 Kalau masih error, cek:${NC}"
echo -e "   ${MAGENTA}pm2 logs webpanel --lines 50${NC}"
echo ""
echo -e "${GREEN}🎉 Buka domain di browser sekarang!${NC}"
