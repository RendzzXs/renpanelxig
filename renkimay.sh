#!/bin/bash
# ============================================
#   👑 RENDZZ RESELLER v6.0 (ADMIN SUPER)
#   Ban User • Hapus Server • Broadcast
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  👑 RENDZZ ADMIN SUPER UPDATE v6.0         ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

read -p "👉 Subdomain Web (contoh: panel.domain.com): " DOMAIN
WEB_ROOT="/var/www/$DOMAIN"

[[ ! -d "$WEB_ROOT" ]] && { echo -e "${RED}❌ Folder web tidak ditemukan!${NC}"; exit 1; }

# ============ 1. UPDATE DATABASE ============
echo -e "${CYAN}[1/3] Update Database (Kolom Status & Announcement)...${NC}"
DB_NAME=$(grep "DB_NAME" "$WEB_ROOT/includes/config.php" | grep -oP "'\K[^']+" | tail -1)

# Cek kolom status di tabel users
mysql "$DB_NAME" -e "SHOW COLUMNS FROM users LIKE 'status';" 2>/dev/null | grep -q status || \
    mysql "$DB_NAME" -e "ALTER TABLE users ADD COLUMN status ENUM('active','banned') DEFAULT 'active';"

# Tabel Announcement
mysql "$DB_NAME" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS announcements (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
SQLEOF

echo -e "${GREEN}  ✓ Database siap${NC}"

# ============ 2. UPDATE DASHBOARD ADMIN ============
echo -e "${CYAN}[2/3] Update Admin Dashboard Full Control...${NC}"

cat > "$WEB_ROOT/admin/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';

// --- SIMPAN PENGATURAN API ---
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['save_api'])) {
    $keys = ['ptero_domain', 'ptla', 'ptlc', 'location_id', 'egg_id'];
    foreach ($keys as $k) {
        if (isset($_POST[$k])) $pdo->prepare("UPDATE settings SET v=? WHERE k=?")->execute([trim($_POST[$k]), $k]);
    }
    $msg = '✅ Pengaturan API disimpan!';
}

// --- BANNED / UNBAN USER ---
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['toggle_ban'])) {
    $uid = (int)$_POST['uid'];
    $current = $_POST['current_status'];
    $new = ($current === 'active') ? 'banned' : 'active';
    $pdo->prepare("UPDATE users SET status=? WHERE id=?")->execute([$new, $uid]);
    $msg = "✅ User berhasil di-" . ($new === 'active' ? 'aktifkan' : 'banned') . "!";
}

// --- HAPUS SERVER DARI PTERODACTYL ---
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete_server'])) {
    $srvId = (int)$_POST['srv_id'];
    $pteroId = (int)$_POST['ptero_id'];
    
    $pteroDomain = rtrim(getSetting($pdo, 'ptero_domain'), '/');
    $ptla = getSetting($pdo, 'ptla');
    
    // Tembak API Delete Pterodactyl
    $ch = curl_init("$pteroDomain/api/application/servers/$pteroId");
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => "DELETE",
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ["Authorization: Bearer $ptla", "Accept: application/json"]
    ]);
    curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    // Hapus dari DB Lokal
    $pdo->prepare("DELETE FROM servers WHERE id=?")->execute([$srvId]);
    $msg = ($httpCode == 204 || $httpCode == 200) ? '✅ Server berhasil dihapus!' : '⚠️ Server dihapus dari DB lokal (gagal hapus dari Ptero).';
}

// --- KIRIM BROADCAST ---
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['broadcast'])) {
    $bc = trim($_POST['message']);
    if ($bc) {
        $pdo->prepare("INSERT INTO announcements (message) VALUES (?)")->execute([$bc]);
        $msg = '✅ Broadcast terkirim ke semua user!';
    }
}

// --- AMBIL DATA STATISTIK ---
$totalUsers = $pdo->query("SELECT COUNT(*) FROM users WHERE role='user'")->fetchColumn();
$totalServers = $pdo->query("SELECT COUNT(*) FROM servers")->fetchColumn();
$totalRam = $pdo->query("SELECT SUM(ram) FROM servers")->fetchColumn() ?: 0;
$users = $pdo->query("SELECT * FROM users WHERE role='user' ORDER BY id DESC")->fetchAll();
$servers = $pdo->query("SELECT s.*, u.username FROM servers s JOIN users u ON s.user_id=u.id ORDER BY s.id DESC")->fetchAll();

$pageTitle = 'X-Admin Dashboard'; include __DIR__ . '/../includes/header.php';
?>

<div class="container">
    <?php if ($msg): ?><div class="alert alert-success" style="background:rgba(16,185,129,0.1); border:1px solid var(--success); color:var(--success); padding:15px; border-radius:10px; margin-bottom:20px;"><?= $msg ?></div><?php endif; ?>

    <h1 style="margin-bottom:20px; font-size:1.8em;"><i class="fas fa-shield-alt" style="color:var(--warning)"></i> Admin Control Center</h1>

    <!-- Statistik -->
    <div style="display:grid; grid-template-columns:repeat(3, 1fr); gap:15px; margin-bottom:20px;">
        <div class="card" style="text-align:center; padding:15px;">
            <div style="font-size:0.8em; color:var(--muted); font-weight:700;">Total User</div>
            <div style="font-size:1.8em; font-weight:800; color:var(--primary);"><?= $totalUsers ?></div>
        </div>
        <div class="card" style="text-align:center; padding:15px;">
            <div style="font-size:0.8em; color:var(--muted); font-weight:700;">Total Server</div>
            <div style="font-size:1.8em; font-weight:800; color:var(--success);"><?= $totalServers ?></div>
        </div>
        <div class="card" style="text-align:center; padding:15px;">
            <div style="font-size:0.8em; color:var(--muted); font-weight:700;">RAM Terpakai</div>
            <div style="font-size:1.8em; font-weight:800; color:var(--warning);"><?= $totalRam ?> MB</div>
        </div>
    </div>

    <!-- Tab Navigation -->
    <div style="display:flex; gap:10px; margin-bottom:20px; overflow-x:auto;">
        <button onclick="showTab('api')" id="btn-api" class="btn btn-primary" style="padding:8px 15px; font-size:0.9em; opacity:1;">API Setting</button>
        <button onclick="showTab('users')" id="btn-users" class="btn" style="padding:8px 15px; font-size:0.9em; background:var(--card); color:var(--text);">Kelola User</button>
        <button onclick="showTab('servers')" id="btn-servers" class="btn" style="padding:8px 15px; font-size:0.9em; background:var(--card); color:var(--text);">Kelola Server</button>
        <button onclick="showTab('broadcast')" id="btn-broadcast" class="btn" style="padding:8px 15px; font-size:0.9em; background:var(--card); color:var(--text);">Broadcast</button>
    </div>

    <!-- TAB: API SETTING -->
    <div id="tab-api" class="tab-content card">
        <h2 style="margin-bottom:15px; font-size:1.1em;"><i class="fas fa-cog"></i> Pterodactyl API</h2>
        <form method="POST">
            <input type="hidden" name="save_api" value="1">
            <div class="form-group"><label>Domain Pterodactyl</label><input type="text" name="ptero_domain" value="<?= htmlspecialchars(getSetting($pdo, 'ptero_domain')) ?>" placeholder="https://panel.domainmu.com" required></div>
            <div class="form-group"><label>Application API Key (ptla)</label><input type="text" name="ptla" value="<?= htmlspecialchars(getSetting($pdo, 'ptla')) ?>" placeholder="ptla_xxx" required></div>
            <div style="display:grid; grid-template-columns:1fr 1fr; gap:15px;">
                <div class="form-group"><label>Location ID</label><input type="number" name="location_id" value="<?= htmlspecialchars(getSetting($pdo, 'location_id', '1')) ?>"></div>
                <div class="form-group"><label>Egg ID</label><input type="number" name="egg_id" value="<?= htmlspecialchars(getSetting($pdo, 'egg_id', '15')) ?>"></div>
            </div>
            <button class="btn btn-primary"><i class="fas fa-save"></i> Simpan API</button>
        </form>
    </div>

    <!-- TAB: KELOLA USER -->
    <div id="tab-users" class="tab-content card" style="display:none;">
        <h2 style="margin-bottom:15px; font-size:1.1em;"><i class="fas fa-users"></i> Daftar User</h2>
        <div style="overflow-x:auto;">
            <table class="table">
                <thead><tr><th>User</th><th>Email</th><th>Status</th><th>Aksi</th></tr></thead>
                <tbody>
                    <?php foreach ($users as $u): ?>
                    <tr>
                        <td><b>@<?= htmlspecialchars($u['username']) ?></b></td>
                        <td><small><?= htmlspecialchars($u['email']) ?></small></td>
                        <td>
                            <span class="badge" style="background:<?= $u['status'] == 'active' ? 'rgba(16,185,129,0.2);color:var(--success)' : 'rgba(239,68,68,0.2);color:var(--danger)' ?>;">
                                <?= strtoupper($u['status']) ?>
                            </span>
                        </td>
                        <td>
                            <form method="POST" style="display:inline;">
                                <input type="hidden" name="uid" value="<?= $u['id'] ?>">
                                <input type="hidden" name="current_status" value="<?= $u['status'] ?>">
                                <button name="toggle_ban" class="btn btn-sm" style="background:<?= $u['status']=='active'?'var(--danger)':'var(--success)' ?>;color:#fff; padding:6px 12px; font-size:0.8em;" onclick="return confirm('Yakin ubah status user ini?')">
                                    <?= $u['status'] == 'active' ? 'Banned' : 'Unban' ?>
                                </button>
                            </form>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>

    <!-- TAB: KELOLA SERVER -->
    <div id="tab-servers" class="tab-content card" style="display:none;">
        <h2 style="margin-bottom:15px; font-size:1.1em;"><i class="fas fa-server"></i> Semua Server</h2>
        <?php foreach ($servers as $s): ?>
            <div style="background:var(--bg); padding:15px; border-radius:12px; margin-bottom:10px; border:1px solid var(--border); display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;">
                <div>
                    <div style="font-weight:800;"><?= htmlspecialchars($s['server_name']) ?></div>
                    <div style="font-size:0.85em; color:var(--muted);">Owner: @<?= htmlspecialchars($s['username']) ?> • RAM: <?= $s['ram']==0?'∞':$s['ram'].'MB' ?></div>
                </div>
                <form method="POST" onsubmit="return confirm('Hapus server ini dari Pterodactyl?')">
                    <input type="hidden" name="srv_id" value="<?= $s['id'] ?>">
                    <input type="hidden" name="ptero_id" value="<?= $s['ptero_id'] ?>">
                    <button name="delete_server" class="btn" style="background:rgba(239,68,68,0.1); color:var(--danger); padding:8px 16px; border:1px solid var(--danger);">
                        <i class="fas fa-trash"></i> Hapus
                    </button>
                </form>
            </div>
        <?php endforeach; ?>
        <?php if (empty($servers)): ?><p style="color:var(--muted); text-align:center;">Belum ada server.</p><?php endif; ?>
    </div>

    <!-- TAB: BROADCAST -->
    <div id="tab-broadcast" class="tab-content card" style="display:none;">
        <h2 style="margin-bottom:15px; font-size:1.1em;"><i class="fas fa-bullhorn"></i> Broadcast Announcement</h2>
        <p style="color:var(--muted); font-size:0.9em; margin-bottom:15px;">Pesan ini bakal muncul di Dashboard semua user.</p>
        <form method="POST">
            <input type="hidden" name="broadcast" value="1">
            <div class="form-group"><textarea name="message" rows="4" style="width:100%; padding:12px; border-radius:10px; background:var(--bg); border:1px solid var(--border); color:var(--text); font-family:inherit;" placeholder="Contoh: Server akan maintenance jam 12 malam..." required></textarea></div>
            <button class="btn btn-primary"><i class="fas fa-paper-plane"></i> Kirim Pesan</button>
        </form>
    </div>
</div>

<script>
function showTab(tab) {
    document.querySelectorAll('.tab-content').forEach(el => el.style.display = 'none');
    document.querySelectorAll('button[id^="btn-"]').forEach(el => {
        el.style.background = 'var(--card)';
        el.style.color = 'var(--text)';
        el.style.opacity = '1';
    });
    
    document.getElementById('tab-' + tab).style.display = 'block';
    const activeBtn = document.getElementById('btn-' + tab);
    activeBtn.style.background = 'var(--primary)';
    activeBtn.style.color = '#fff';
}
</script>

<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

echo -e "${GREEN}  ✓ Admin Dashboard Super OK${NC}"

# ============ 3. UPDATE DASHBOARD USER (TAMPILIN BROADCAST) ============
echo -e "${CYAN}[3/3] Update User Dashboard (Announcement)...${NC}"

# Cari file dashboard.php
DASHBOARD="$WEB_ROOT/dashboard.php"

if [ -f "$DASHBOARD" ]; then
    # Cek apakah belum ada kode broadcast
    if ! grep -q "announcement" "$DASHBOARD"; then
        # Inject kode PHP buat ambil broadcast
        sed -i "s|requireLogin();|requireLogin();\n\$ann = \$pdo->query(\"SELECT * FROM announcements ORDER BY id DESC LIMIT 1\")->fetch();|" "$DASHBOARD"
        
        # Inject HTML broadcast setelah <div class="container">
        sed -i "s|<div class=\"container\">|<div class=\"container\">\n<?php if (\$ann): ?><div style=\"background:rgba(245,158,11,0.15); border:1px solid var(--warning); color:var(--warning); padding:15px; border-radius:12px; margin-bottom:20px; font-size:0.9em; font-weight:600;\"><i class=\"fas fa-bullhorn\"></i> <b>Pengumuman:</b> <?= htmlspecialchars(\$ann['message']) ?></div><?php endif; ?>|" "$DASHBOARD"
    fi
fi

# Fix permission
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
systemctl restart php8.3-fpm

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ ADMIN SUPER BERHASIL DI-UPDATE!        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📌 Fitur Admin Baru:${NC}"
echo -e "  1. 🔒 Kelola User (Banned / Unban)"
echo -e "  2. 🗑️  Kelola Server (Hapus paksa dari Pterodactyl)"
echo -e "  3. 📢 Broadcast Announcement (Muncul di Dashboard User)"
echo ""
echo -e "${GREEN}🚀 Login sebagai admin, buka menu X-Admin, dan coba fitur barunya!${NC}"
