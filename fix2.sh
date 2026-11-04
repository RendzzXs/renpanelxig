#!/bin/bash
# ============================================================
#   🔧 FIX v2 — Auto detect folder + build tools + reinstall
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

# === AUTO DETECT FOLDER ===
FOUND=""
for d in /var/www/*/; do
  if [[ -f "$d/app.js" ]]; then
    FOUND="$d"
    break
  fi
done

if [[ -z "$FOUND" ]]; then
  echo -e "${YELLOW}⚠️  Folder tidak auto-detect${NC}"
  read -p "👉 Path folder webpanel: " FOUND
fi

WEB_ROOT="${FOUND%/}"
cd "$WEB_ROOT" || { echo -e "${RED}❌ Tidak bisa masuk $WEB_ROOT${NC}"; exit 1; }

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🔧 WEB PANEL FIX v2                       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo -e "${GREEN}📁 Folder :${NC} $WEB_ROOT"
echo ""

# === 1. INSTALL BUILD TOOLS ===
echo -e "${CYAN}[1/7] Install build tools...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq 2>/dev/null
apt install -y build-essential python3 make g++ libsqlite3-dev 2>&1 | tail -2
echo -e "${GREEN}  ✓ Build tools OK${NC}"

# === 2. CEK NODE.JS ===
echo -e "${CYAN}[2/7] Cek Node.js...${NC}"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  apt install -y nodejs >/dev/null 2>&1
fi
echo -e "${GREEN}  ✓ Node.js $(node -v)${NC}"

# === 3. CLEANUP ===
echo -e "${CYAN}[3/7] Bersihkan modules lama...${NC}"
rm -rf node_modules package-lock.json
npm cache clean --force >/dev/null 2>&1
echo -e "${GREEN}  ✓ Clean OK${NC}"

# === 4. INIT PACKAGE.JSON ===
echo -e "${CYAN}[4/7] Init package.json...${NC}"
npm init -y >/dev/null 2>&1
echo -e "${GREEN}  ✓ package.json OK${NC}"

# === 5. INSTALL DEPENDENCIES ===
echo -e "${CYAN}[5/7] Install dependencies (bisa makan 1-3 menit)...${NC}"
npm install express express-session better-sqlite3 bcryptjs dotenv node-fetch@2 2>&1 | tail -5

if [[ ! -d "node_modules/express" ]]; then
  echo -e "${RED}❌ express gagal install!${NC}"
  exit 1
fi
if [[ ! -d "node_modules/better-sqlite3" ]]; then
  echo -e "${RED}❌ better-sqlite3 gagal install!${NC}"
  echo -e "${YELLOW}  → Coba rebuild...${NC}"
  npm rebuild better-sqlite3 2>&1 | tail -5
fi

# Cek native build
if [[ -f "node_modules/better-sqlite3/build/Release/better_sqlite3.node" ]]; then
  echo -e "${GREEN}  ✓ better-sqlite3 native OK${NC}"
else
  echo -e "${YELLOW}  ⚠️ Native build belum ada, coba rebuild ulang...${NC}"
  npm rebuild better-sqlite3 --build-from-source 2>&1 | tail -8
fi

# === 6. TEST RUN ===
echo -e "${CYAN}[6/7] Test jalankan app.js...${NC}"
TEST_OUT=$(timeout 6 node app.js 2>&1)
if echo "$TEST_OUT" | grep -q "running on port"; then
  echo -e "${GREEN}  ✓ app.js OK${NC}"
else
  echo -e "${RED}  ✗ Error:${NC}"
  echo "$TEST_OUT" | head -20

  # Auto-fix umum
  if echo "$TEST_OUT" | grep -q "ERR_REQUIRE_ESM\|Cannot use import"; then
    npm uninstall node-fetch >/dev/null 2>&1
    npm install node-fetch@2 >/dev/null 2>&1
  fi
  if echo "$TEST_OUT" | grep -q "better-sqlite3\|NODE_MODULE_VERSION"; then
    npm rebuild better-sqlite3 >/dev/null 2>&1
  fi
  if echo "$TEST_OUT" | grep -q "SQLITE_CANTOPEN"; then
    chmod 755 "$WEB_ROOT"
    touch panel.db 2>/dev/null
    chmod 666 panel.db 2>/dev/null
  fi

  TEST_OUT2=$(timeout 6 node app.js 2>&1)
  if ! echo "$TEST_OUT2" | grep -q "running on port"; then
    echo -e "${RED}  ✗ Masih error:${NC}"
    echo "$TEST_OUT2" | head -20
    exit 1
  fi
fi

# === 7. PM2 RESTART ===
echo -e "${CYAN}[7/7] Restart PM2...${NC}"
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
  echo -e "${YELLOW}  Cek: pm2 logs webpanel --lines 30${NC}"
  exit 1
fi

# === NGINX RELOAD ===
NGINX_DOMAIN=$(basename "$WEB_ROOT")
if [[ -f "/etc/nginx/sites-available/$NGINX_DOMAIN" ]]; then
  nginx -t >/dev/null 2>&1 && systemctl reload nginx
  echo -e "${GREEN}  ✓ Nginx OK${NC}"
fi

clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ FIX SELESAI!                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📁 Folder :${NC} $WEB_ROOT"
echo -e "${CYAN}📊 Status :${NC} $(pm2 jlist 2>/dev/null | grep -oP '"name":"webpanel","pm2_env":\{[^}]*"status":"\K[^"]+' | head -1)"
echo -e "${CYAN}🌐 Domain :${NC} http://$NGINX_DOMAIN"
echo ""
echo -e "${GREEN}🎉 Buka domain di browser sekarang!${NC}"
