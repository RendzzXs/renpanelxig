#!/bin/bash
# ==========================================
# 🏫 SISTEM SEKOLAH PRO v3.0 (WOW EDITION)
# Full Fix • UI/UX Premium • Dark Mode
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

read -p "👉 Masukkan Domain Web (contoh: sekolah.domain.com): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Domain tidak boleh kosong!${NC}"; exit 1; }
read -p "👉 Email SSL (buat Let's Encrypt): " EMAIL
[[ -z "$EMAIL" ]] && EMAIL="admin@$DOMAIN"

WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="school_db_$(echo $DOMAIN | tr '.' '_' | cut -c1-10)"
DB_USER="school_user"
DB_PASS=$(openssl rand -hex 12)
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo -e "${CYAN}[1/5] Install Dependency...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq
apt install -y nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl php8.3-xml php8.3-zip php8.3-gd mariadb-server mariadb-client certbot python3-certbot-nginx >/dev/null 2>&1
systemctl enable --now nginx php8.3-fpm mariadb >/dev/null 2>&1

echo -e "${CYAN}[2/5] Setup Database & Tables...${NC}"
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql "$DB_NAME" << SQLEOF
CREATE TABLE admins (id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL, password VARCHAR(255) NOT NULL);
INSERT INTO admins (username, password) VALUES ('admin', 'admin123');

CREATE TABLE students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nama VARCHAR(100) NOT NULL,
    nisn VARCHAR(20) UNIQUE NOT NULL,
    nik VARCHAR(20),
    alamat TEXT,
    tempat_lahir VARCHAR(50),
    tanggal_lahir DATE,
    nama_ortu VARCHAR(100),
    no_hp VARCHAR(20),
    golongan_darah VARCHAR(5),
    foto VARCHAR(255),
    jurusan VARCHAR(50),
    kelas VARCHAR(20),
    nilai_matematika INT DEFAULT 0,
    nilai_indo INT DEFAULT 0,
    nilai_inggris INT DEFAULT 0,
    nilai_pilihan INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE school_info (id INT PRIMARY KEY, nama_sekolah VARCHAR(100), alamat_sekolah TEXT, nama_kepsek VARCHAR(100), nisn_kepsek VARCHAR(20), logo VARCHAR(255), ttd VARCHAR(255));
INSERT INTO school_info (id, nama_sekolah, alamat_sekolah, nama_kepsek, nisn_kepsek) VALUES (1, 'SMA NEGERI 1 RENDZZ', 'Jl. Pendidikan No. 1, Indonesia', 'Dr. H. Ahmad, M.Pd', '12345678');
SQLEOF

echo -e "${CYAN}[3/5] Generate File Web (Pro UI/UX)...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{uploads,foto,assets}

# --- CONFIG.PHP ---
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
} catch (PDOException \$e) { die("DB Error"); }
function getSchool(\$pdo) { return \$pdo->query("SELECT * FROM school_info WHERE id=1")->fetch(); }
function isAdmin() { return isset(\$_SESSION['admin']); }
function requireAdmin() { if(!isAdmin()) { header('Location: login.php'); exit; } }
PHPEOF

# --- STYLE.CSS (PREMIUM DARK SCHOOL THEME) ---
cat > "$WEB_ROOT/style.css" << 'CSSEOF'
@import url('https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&display=swap');
@import url('https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css');

:root {
    --bg: #0b1120; --bg-gradient: radial-gradient(circle at 0% 0%, #172554 0%, #0b1120 50%);
    --card: rgba(30, 41, 59, 0.7); --glass-border: rgba(255,255,255,0.1);
    --text: #f8fafc; --text-muted: #94a3b8;
    --primary: #3b82f6; --primary-glow: rgba(59, 130, 246, 0.5);
    --success: #10b981; --danger: #ef4444; --warning: #f59e0b;
    --gradient: linear-gradient(135deg, #2563eb, #7c3aed);
}

* { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Outfit', sans-serif; }
body { background: var(--bg); background-image: var(--bg-gradient); background-attachment: fixed; color: var(--text); min-height: 100vh; padding: 20px; -webkit-font-smoothing: antialiased; }
.container { max-width: 1000px; margin: 0 auto; }

/* CARD & FORM */
.card { background: var(--card); backdrop-filter: blur(16px); border: 1px solid var(--glass-border); border-radius: 20px; padding: 30px; margin-bottom: 25px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); animation: fadeIn 0.5s ease-out; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
h1, h2, h3 { color: var(--text); margin-bottom: 20px; font-weight: 700; }
h1 { font-size: 2.2em; background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }

.form-group { margin-bottom: 20px; }
label { display: block; margin-bottom: 8px; font-size: 0.9em; color: var(--text-muted); font-weight: 500; }
input, select, textarea { width: 100%; padding: 14px; border-radius: 12px; border: 1px solid var(--glass-border); background: rgba(0,0,0,0.3); color: var(--text); outline: none; font-size: 1em; transition: 0.3s; }
input:focus, select:focus, textarea:focus { border-color: var(--primary); box-shadow: 0 0 0 3px var(--primary-glow); }

.btn { padding: 14px 24px; border-radius: 12px; border: none; font-weight: 600; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; justify-content: center; gap: 10px; transition: all 0.3s ease; font-size: 1em; }
.btn-primary { background: var(--gradient); color: white; box-shadow: 0 4px 15px rgba(37,99,235,0.4); }
.btn-primary:hover { transform: translateY(-3px); box-shadow: 0 8px 25px rgba(37,99,235,0.6); }
.btn-success { background: var(--success); color: white; }
.btn-danger { background: var(--danger); color: white; }
.btn-warning { background: var(--warning); color: white; }
.btn-block { width: 100%; }

/* NAVBAR & DASHBOARD (LANDING PAGE) */
.navbar { display: flex; justify-content: space-between; align-items: center; padding: 20px 0; margin-bottom: 40px; }
.navbar-brand { font-size: 1.5em; font-weight: 800; display: flex; align-items: center; gap: 10px; color: white; text-decoration: none; }
.hero-section { text-align: center; padding: 50px 0; }
.hero-title { font-size: 3em; font-weight: 800; line-height: 1.1; margin-bottom: 20px; }
.hero-sub { color: var(--text-muted); font-size: 1.2em; max-width: 600px; margin: 0 auto 40px; }

.menu-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 25px; max-width: 800px; margin: 0 auto; }
.menu-card { background: var(--card); backdrop-filter: blur(16px); border: 1px solid var(--glass-border); border-radius: 24px; padding: 40px 30px; text-align: center; text-decoration: none; transition: all 0.4s; position: relative; overflow: hidden; }
.menu-card:hover { transform: translateY(-10px); border-color: var(--primary); box-shadow: 0 20px 40px var(--primary-glow); }
.menu-icon { font-size: 3.5em; margin-bottom: 20px; background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
.menu-card h3 { color: var(--text); font-size: 1.5em; margin-bottom: 10px; }
.menu-card p { color: var(--text-muted); font-size: 0.95em; }

/* KARTU PELAJAR (SMART CARD STYLE) */
.kartu-wrapper { display: flex; justify-content: center; margin-top: 30px; perspective: 1000px; }
.kartu-container { width: 100%; max-width: 500px; background: linear-gradient(135deg, #1e3a8a, #3b82f6, #1e3a8a); border-radius: 24px; padding: 30px; color: white; position: relative; overflow: hidden; box-shadow: 0 25px 50px rgba(0,0,0,0.5); border: 1px solid rgba(255,255,255,0.2); transition: transform 0.5s; }
.kartu-container:hover { transform: rotateY(5deg) rotateX(5deg); }
.kartu-container::before { content: ''; position: absolute; top: -50%; left: -50%; width: 200%; height: 200%; background: linear-gradient(45deg, transparent, rgba(255,255,255,0.1), transparent); transform: rotate(45deg); animation: shine 3s infinite; }
@keyframes shine { 0% { transform: translateX(-100%) rotate(45deg); } 100% { transform: translateX(100%) rotate(45deg); } }

.kartu-header { display: flex; align-items: center; border-bottom: 2px solid rgba(255,255,255,0.2); padding-bottom: 15px; margin-bottom: 20px; z-index: 2; position: relative; }
.kartu-header i { font-size: 2.5em; margin-right: 15px; color: #fbbf24; }
.kartu-header h3 { color: white; margin: 0; font-size: 1.3em; }
.kartu-header p { font-size: 0.75em; opacity: 0.8; }

.kartu-body { display: flex; gap: 25px; z-index: 2; position: relative; }
.kartu-foto { width: 110px; height: 150px; background: #1e293b; border-radius: 12px; object-fit: cover; border: 3px solid rgba(255,255,255,0.8); box-shadow: 0 5px 15px rgba(0,0,0,0.3); }
.kartu-info { flex: 1; }
.kartu-info h4 { font-size: 1.4em; margin-bottom: 10px; color: #fbbf24; }
.kartu-info p { margin-bottom: 6px; font-size: 0.9em; display: flex; gap: 8px; }
.kartu-info b { color: #60a5fa; width: 100px; display: inline-block; }

.kartu-footer { display: flex; justify-content: space-between; align-items: flex-end; margin-top: 25px; border-top: 1px solid rgba(255,255,255,0.2); padding-top: 15px; font-size: 0.8em; z-index: 2; position: relative; }
.ttd { text-align: center; }
.ttd p:last-child { font-weight: 700; margin-top: 5px; border-bottom: 1px solid white; display: inline-block; padding-bottom: 2px; }

/* KELULUSAN (TABLE STYLE) */
.result-card { background: var(--card); border-radius: 20px; padding: 30px; border: 1px solid var(--glass-border); }
.table { width: 100%; border-collapse: separate; border-spacing: 0; margin-top: 20px; border-radius: 12px; overflow: hidden; }
.table th { background: rgba(0,0,0,0.4); color: var(--primary); padding: 15px; text-align: left; font-weight: 600; border-bottom: 2px solid var(--glass-border); }
.table td { padding: 15px; border-bottom: 1px solid var(--glass-border); color: var(--text); }
.table tr:last-child td { border-bottom: none; }
.status-box { text-align: center; margin-top: 30px; padding: 30px; border-radius: 16px; border: 2px solid; animation: pulse 2s infinite; }
.status-lulus { background: rgba(16,185,129,0.1); border-color: var(--success); color: var(--success); }
.status-gagal { background: rgba(239,68,68,0.1); border-color: var(--danger); color: var(--danger); }
.status-box h1 { font-size: 3em; margin: 0; letter-spacing: 2px; }
@keyframes pulse { 0% { box-shadow: 0 0 0 0 rgba(16,185,129,0.4); } 70% { box-shadow: 0 0 0 20px rgba(16,185,129,0); } 100% { box-shadow: 0 0 0 0 rgba(16,185,129,0); } }

/* RESPONSIVE */
@media (max-width: 768px) {
    .menu-grid { grid-template-columns: 1fr; }
    .hero-title { font-size: 2em; }
    .kartu-body { flex-direction: column; align-items: center; text-align: center; }
    .kartu-info p { justify-content: center; }
    .kartu-info b { width: auto; }
}
@media print {
    body { background: white; padding: 0; }
    .navbar, .no-print, .btn { display: none !important; }
    .kartu-container { box-shadow: none; border: 1px solid #000; margin: 0 auto; color: black; background: white; }
    .kartu-header, .kartu-footer { border-color: #000; }
    .kartu-info h4, .kartu-info b { color: #000; }
}
CSSEOF

# --- INDEX.PHP ---
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php require 'config.php'; $school = getSchool($pdo); ?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= $school['nama_sekolah'] ?> - Portal</title><link rel="stylesheet" href="style.css">
</head>
<body>
<div class="container">
    <nav class="navbar">
        <a href="index.php" class="navbar-brand"><i class="fas fa-school" style="color:var(--primary)"></i> <?= $school['nama_sekolah'] ?></a>
        <a href="login.php" class="btn btn-primary" style="padding: 10px 20px; font-size: 0.9em;"><i class="fas fa-user-shield"></i> Admin</a>
    </nav>

    <section class="hero-section">
        <h1 class="hero-title">Selamat Datang di <br><span style="background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent;">Portal Akademik</span></h1>
        <p class="hero-sub">Akses layanan kartu pelajar dan pengumuman kelulusan secara digital dengan mudah dan cepat.</p>
        
        <div class="menu-grid">
            <a href="kartu.php" class="menu-card">
                <i class="fas fa-id-card menu-icon"></i>
                <h3>Cetak Kartu Pelajar</h3>
                <p>Buat dan cetak kartu identitas siswa resmi.</p>
            </a>
            <a href="kelulusan.php" class="menu-card">
                <i class="fas fa-graduation-cap menu-icon" style="background: linear-gradient(135deg, #10b981, #059669); -webkit-background-clip: text; -webkit-text-fill-color: transparent;"></i>
                <h3>Cek Kelulusan</h3>
                <p>Lihat hasil pengumuman nilai akhir kelulusan.</p>
            </a>
        </div>
    </section>
</div>
</body>
</html>
PHPEOF

# --- KARTU.PHP (FIXED QUERY) ---
cat > "$WEB_ROOT/kartu.php" << 'PHPEOF'
<?php 
require 'config.php'; $school = getSchool($pdo);
$msg = ''; $error = '';
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $nama = $_POST['nama']; $nisn = $_POST['nisn']; $nik = $_POST['nik']; $alamat = $_POST['alamat'];
    $tempat = $_POST['tempat_lahir']; $tgl = $_POST['tanggal_lahir']; $ortu = $_POST['nama_ortu'];
    $hp = $_POST['no_hp']; $gol = $_POST['golongan_darah']; $jurusan = $_POST['jurusan'];
    
    $foto = 'default.png';
    if ($_FILES['foto']['error'] == 0) {
        $ext = pathinfo($_FILES['foto']['name'], PATHINFO_EXTENSION);
        $foto = 'foto_' . $nisn . '.' . $ext;
        move_uploaded_file($_FILES['foto']['tmp_name'], 'foto/' . $foto);
    }
    
    // FIXED QUERY LOGIC
    $check = $pdo->prepare("SELECT id FROM students WHERE nisn=?");
    $check->execute([$nisn]);
    
    if ($check->rowCount() > 0) {
        $stmt = $pdo->prepare("UPDATE students SET nama=?, nik=?, alamat=?, tempat_lahir=?, tanggal_lahir=?, nama_ortu=?, no_hp=?, golongan_darah=?, foto=?, jurusan=? WHERE nisn=?");
        $stmt->execute([$nama, $nik, $alamat, $tempat, $tgl, $ortu, $hp, $gol, $foto, $jurusan, $nisn]);
        $msg = "Data kartu berhasil diperbarui!";
    } else {
        $stmt = $pdo->prepare("INSERT INTO students (nama, nisn, nik, alamat, tempat_lahir, tanggal_lahir, nama_ortu, no_hp, golongan_darah, foto, jurusan) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
        $stmt->execute([$nama, $nisn, $nik, $alamat, $tempat, $tgl, $ortu, $hp, $gol, $foto, $jurusan]);
        $msg = "Kartu berhasil dibuat!";
    }
    header("Location: kartu.php?nisn=$nisn&success=1");
    exit;
}
?>
<!DOCTYPE html>
<html lang="id"><head><meta charset="UTF-8"><title>Cetak Kartu</title><link rel="stylesheet" href="style.css"></head>
<body>
<div class="container">
    <nav class="navbar no-print">
        <a href="index.php" class="navbar-brand" style="font-size:1.2em"><i class="fas fa-arrow-left"></i> Kembali</a>
    </nav>
    <div class="card no-print">
        <h1>Pembuatan Kartu Pelajar</h1>
        <?php if(isset($_GET['success'])): ?><div style="background: rgba(16,185,129,0.2); padding: 15px; border-radius: 12px; margin-bottom: 20px; color: var(--success);"><i class="fas fa-check-circle"></i> Data berhasil disimpan!</div><?php endif; ?>
        
        <form method="POST" enctype="multipart/form-data">
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                <div class="form-group"><label>Nama Lengkap</label><input type="text" name="nama" required></div>
                <div class="form-group"><label>NISN</label><input type="text" name="nisn" required></div>
                <div class="form-group"><label>NIK</label><input type="text" name="nik" required></div>
                <div class="form-group"><label>Jurusan</label><select name="jurusan"><option value="IPA">IPA</option><option value="IPS">IPS</option><option value="Bahasa">Bahasa</option><option value="TKJ">TKJ</option><option value="RPL">RPL</option></select></div>
                <div class="form-group"><label>Tempat Lahir</label><input type="text" name="tempat_lahir" required></div>
                <div class="form-group"><label>Tanggal Lahir</label><input type="date" name="tanggal_lahir" required></div>
                <div class="form-group"><label>Nama Orang Tua</label><input type="text" name="nama_ortu" required></div>
                <div class="form-group"><label>No HP</label><input type="text" name="no_hp" required></div>
                <div class="form-group"><label>Golongan Darah</label><input type="text" name="golongan_darah" placeholder="A/B/AB/O"></div>
                <div class="form-group"><label>Foto (JPG/PNG)</label><input type="file" name="foto" accept="image/*"></div>
            </div>
            <div class="form-group"><label>Alamat Lengkap</label><textarea name="alamat" rows="2" required></textarea></div>
            <button type="submit" class="btn btn-primary"><i class="fas fa-save"></i> Simpan & Buat Kartu</button>
        </form>
    </div>

    <?php 
    if(isset($_GET['nisn'])) {
        $s = $pdo->prepare("SELECT * FROM students WHERE nisn=?"); $s->execute([$_GET['nisn']]); $siswa = $s->fetch();
        if($siswa): ?>
        <div class="kartu-wrapper">
            <div class="kartu-container" id="kartu">
                <div class="kartu-header">
                    <i class="fas fa-school"></i>
                    <div><h3><?= $school['nama_sekolah'] ?></h3><p><?= $school['alamat_sekolah'] ?></p></div>
                </div>
                <div class="kartu-body">
                    <img src="foto/<?= $siswa['foto'] ?>" class="kartu-foto" onerror="this.src='https://via.placeholder.com/110x150?text=Foto'">
                    <div class="kartu-info">
                        <h4><?= $siswa['nama'] ?></h4>
                        <p><b>NISN</b> <span>: <?= $siswa['nisn'] ?></span></p>
                        <p><b>Jurusan</b> <span>: <?= $siswa['jurusan'] ?></span></p>
                        <p><b>TTL</b> <span>: <?= $siswa['tempat_lahir'] ?>, <?= date('d-m-Y', strtotime($siswa['tanggal_lahir'])) ?></span></p>
                        <p><b>Alamat</b> <span>: <?= $siswa['alamat'] ?></span></p>
                    </div>
                </div>
                <div class="kartu-footer">
                    <div style="text-align:center;"><p>Tanda Tangan Siswa,</p><br><br><p><?= $siswa['nama'] ?></p></div>
                    <div class="ttd"><p>Kepala Sekolah,</p><br><br><p><?= $school['nama_kepsek'] ?></p><p style="font-size:0.8em">NISN: <?= $school['nisn_kepsek'] ?></p></div>
                </div>
            </div>
        </div>
        <div class="no-print" style="text-align:center; margin-top: 30px;">
            <button onclick="window.print()" class="btn btn-success"><i class="fas fa-print"></i> Cetak Kartu Sekarang</button>
        </div>
        <?php endif; 
    } ?>
</div>
</body></html>
PHPEOF

# --- KELULUSAN.PHP ---
cat > "$WEB_ROOT/kelulusan.php" << 'PHPEOF'
<?php require 'config.php'; $school = getSchool($pdo); $msg = '';
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $nama = $_POST['nama']; $nisn = $_POST['nisn']; $kelas = $_POST['kelas']; $jurusan = $_POST['jurusan'];
    $tempat = $_POST['tempat_lahir']; $tgl = $_POST['tanggal_lahir'];
    $n1 = $_POST['nilai_matematika']; $n2 = $_POST['nilai_indo']; $n3 = $_POST['nilai_inggris']; $n4 = $_POST['nilai_pilihan'];
    
    $check = $pdo->prepare("SELECT id FROM students WHERE nisn=?"); $check->execute([$nisn]);
    if ($check->rowCount() > 0) {
        $stmt = $pdo->prepare("UPDATE students SET nama=?, kelas=?, jurusan=?, tempat_lahir=?, tanggal_lahir=?, nilai_matematika=?, nilai_indo=?, nilai_inggris=?, nilai_pilihan=? WHERE nisn=?");
        $stmt->execute([$nama, $kelas, $jurusan, $tempat, $tgl, $n1, $n2, $n3, $n4, $nisn]);
    } else {
        $stmt = $pdo->prepare("INSERT INTO students (nama, nisn, kelas, jurusan, tempat_lahir, tanggal_lahir, nilai_matematika, nilai_indo, nilai_inggris, nilai_pilihan) VALUES (?,?,?,?,?,?,?,?,?,?)");
        $stmt->execute([$nama, $nisn, $kelas, $jurusan, $tempat, $tgl, $n1, $n2, $n3, $n4]);
    }
    header("Location: kelulusan.php?nisn=$nisn&success=1");
    exit;
}
?>
<!DOCTYPE html>
<html lang="id"><head><meta charset="UTF-8"><title>Cek Kelulusan</title><link rel="stylesheet" href="style.css"></head>
<body>
<div class="container">
    <nav class="navbar no-print">
        <a href="index.php" class="navbar-brand" style="font-size:1.2em"><i class="fas fa-arrow-left"></i> Kembali</a>
    </nav>
    <div class="card no-print">
        <h1>Input Nilai Kelulusan</h1>
        <form method="POST">
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                <div class="form-group"><label>Nama Lengkap</label><input type="text" name="nama" required></div>
                <div class="form-group"><label>NISN</label><input type="text" name="nisn" required></div>
                <div class="form-group"><label>Kelas</label><input type="text" name="kelas" placeholder="XII IPA 1" required></div>
                <div class="form-group"><label>Jurusan</label><select name="jurusan"><option value="IPA">IPA</option><option value="IPS">IPS</option><option value="Bahasa">Bahasa</option><option value="TKJ">TKJ</option><option value="RPL">RPL</option></select></div>
                <div class="form-group"><label>Tempat Lahir</label><input type="text" name="tempat_lahir" required></div>
                <div class="form-group"><label>Tanggal Lahir</label><input type="date" name="tanggal_lahir" required></div>
            </div>
            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 25px;">
                <div class="form-group"><label>Matematika</label><input type="number" name="nilai_matematika" min="0" max="100" required></div>
                <div class="form-group"><label>B. Indo</label><input type="number" name="nilai_indo" min="0" max="100" required></div>
                <div class="form-group"><label>B. Inggris</label><input type="number" name="nilai_inggris" min="0" max="100" required></div>
                <div class="form-group"><label>Pilihan</label><input type="number" name="nilai_pilihan" min="0" max="100" required></div>
            </div>
            <button type="submit" class="btn btn-primary"><i class="fas fa-save"></i> Cek Hasil Kelulusan</button>
        </form>
    </div>

    <?php 
    if(isset($_GET['nisn'])) {
        $s = $pdo->prepare("SELECT * FROM students WHERE nisn=?"); $s->execute([$_GET['nisn']]); $siswa = $s->fetch();
        if($siswa): 
            $rata = ($siswa['nilai_matematika'] + $siswa['nilai_indo'] + $siswa['nilai_inggris'] + $siswa['nilai_pilihan']) / 4;
            $lulus = $rata >= 70;
        ?>
        <div class="result-card">
            <h2 style="text-align: center;"><i class="fas fa-graduation-cap" style="color:var(--primary)"></i> Hasil Pengumuman</h2>
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-top: 30px; padding-bottom: 20px; border-bottom: 1px solid var(--glass-border);">
                <p><b>Nama:</b> <?= $siswa['nama'] ?></p>
                <p><b>NISN:</b> <?= $siswa['nisn'] ?></p>
                <p><b>TTL:</b> <?= $siswa['tempat_lahir'] ?>, <?= date('d-m-Y', strtotime($siswa['tanggal_lahir'])) ?></p>
                <p><b>Kelas:</b> <?= $siswa['kelas'] ?> - <?= $siswa['jurusan'] ?></p>
            </div>
            <table class="table">
                <thead><tr><th>Mata Pelajaran</th><th>Nilai</th></tr></thead>
                <tbody>
                    <tr><td>Matematika</td><td><?= $siswa['nilai_matematika'] ?></td></tr>
                    <tr><td>Bahasa Indonesia</td><td><?= $siswa['nilai_indo'] ?></td></tr>
                    <tr><td>Bahasa Inggris</td><td><?= $siswa['nilai_inggris'] ?></td></tr>
                    <tr><td>Mapel Pilihan</td><td><?= $siswa['nilai_pilihan'] ?></td></tr>
                    <tr style="background: rgba(59,130,246,0.1);"><td><b>Rata-Rata</b></td><td><b style="color:var(--primary); font-size:1.2em;"><?= round($rata, 2) ?></b></td></tr>
                </tbody>
            </table>
            <div class="status-box <?= $lulus ? 'status-lulus' : 'status-gagal' ?>">
                <p style="font-size: 1.1em; margin-bottom: 10px; color: var(--text-muted);">Berdasarkan nilai yang diinput, siswa dinyatakan:</p>
                <h1><?= $lulus ? 'LULUS' : 'TIDAK LULUS' ?></h1>
            </div>
        </div>
        <?php endif; 
    } ?>
</div>
</body></html>
PHPEOF

# --- LOGIN & ADMIN (SAMA KAYAK SEBELUMNYA) ---
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php require 'config.php';
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $u = $_POST['username']; $p = $_POST['password'];
    $stmt = $pdo->prepare("SELECT * FROM admins WHERE username=? AND password=?"); $stmt->execute([$u, $p]);
    if ($stmt->fetch()) { $_SESSION['admin'] = $u; header('Location: admin.php'); exit; }
    else { $err = "Username atau Password salah!"; }
}
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Login Admin</title><link rel="stylesheet" href="style.css"></head>
<body><div class="container" style="max-width: 400px; margin-top: 100px;">
    <div class="card"><h2 style="text-align: center;"><i class="fas fa-lock"></i> Login Admin</h2>
        <?php if(isset($err)) echo "<p style='color:var(--danger); text-align:center; margin-bottom:15px;'>$err</p>"; ?>
        <form method="POST"><div class="form-group"><label>Username</label><input type="text" name="username" required></div><div class="form-group"><label>Password</label><input type="password" name="password" required></div><button type="submit" class="btn btn-primary btn-block"><i class="fas fa-sign-in-alt"></i> Masuk</button></form>
        <div style="text-align: center; margin-top: 20px;"><a href="index.php" style="color: var(--text-muted); text-decoration: none; font-size: 0.9em;"><i class="fas fa-arrow-left"></i> Kembali</a></div>
    </div>
</div></body></html>
PHPEOF

cat > "$WEB_ROOT/admin.php" << 'PHPEOF'
<?php require 'config.php'; requireAdmin(); $school = getSchool($pdo); $msg = '';
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['update_school'])) {
    $stmt = $pdo->prepare("UPDATE school_info SET nama_sekolah=?, alamat_sekolah=?, nama_kepsek=?, nisn_kepsek=? WHERE id=1");
    $stmt->execute([$_POST['nama_sekolah'], $_POST['alamat_sekolah'], $_POST['nama_kepsek'], $_POST['nisn_kepsek']]);
    $msg = "Info sekolah berhasil diupdate!"; $school = getSchool($pdo);
}
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Admin Dashboard</title><link rel="stylesheet" href="style.css"></head>
<body><div class="container">
    <nav class="navbar"><a href="#" class="navbar-brand"><i class="fas fa-user-shield"></i> Admin Panel</a><a href="logout.php" class="btn btn-danger"><i class="fas fa-sign-out-alt"></i> Logout</a></nav>
    <?php if($msg): ?><div style="background: rgba(16,185,129,0.2); padding: 15px; border-radius: 12px; margin-bottom: 20px; color: var(--success);"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?>
    <div class="card"><h2><i class="fas fa-cog"></i> Pengaturan Sekolah</h2>
        <form method="POST"><input type="hidden" name="update_school" value="1">
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                <div class="form-group"><label>Nama Sekolah</label><input type="text" name="nama_sekolah" value="<?= $school['nama_sekolah'] ?>" required></div>
                <div class="form-group"><label>Nama Kepala Sekolah</label><input type="text" name="nama_kepsek" value="<?= $school['nama_kepsek'] ?>" required></div>
                <div class="form-group"><label>NISN Kepsek</label><input type="text" name="nisn_kepsek" value="<?= $school['nisn_kepsek'] ?>" required></div>
                <div class="form-group"><label>Alamat Sekolah</label><input type="text" name="alamat_sekolah" value="<?= $school['alamat_sekolah'] ?>" required></div>
            </div>
            <button type="submit" class="btn btn-primary"><i class="fas fa-save"></i> Simpan Perubahan</button>
        </form>
    </div>
    <div class="card" style="text-align: center;"><h2><i class="fas fa-bolt"></i> Akses Cepat</h2>
        <div style="display: flex; gap: 15px; justify-content: center;">
            <a href="kartu.php" class="btn btn-warning"><i class="fas fa-id-card"></i> Halaman Kartu</a>
            <a href="kelulusan.php" class="btn btn-success"><i class="fas fa-graduation-cap"></i> Halaman Kelulusan</a>
        </div>
    </div>
</div></body></html>
PHPEOF

cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); header('Location: login.php'); exit;
PHPEOF

echo -e "${CYAN}[4/5] Setup Nginx & SSL...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT; index index.php index.html;
    location ~ /\.ht { deny all; }
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.3-fpm.sock; }
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null
nginx -t >/dev/null 2>&1 && systemctl reload nginx
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
chmod -R 775 "$WEB_ROOT/foto"
systemctl restart php8.3-fpm

SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
DOMAIN_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | head -1)
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1; fi
PROTO="https"; [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] && PROTO="http"

echo -e "${GREEN}[5/5] Selesai!${NC}"
clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ INSTALASI PRO BERHASIL!                ║${NC}"
echo -e "${GREEN}║  🏫 Sistem Kartu & Kelulusan (WOW)         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 URL Web:${NC} $PROTO://$DOMAIN"
echo -e "${MAGENTA}🔒 Admin Panel:${NC} $PROTO://$DOMAIN/login.php"
echo ""
echo -e "${WHITE}🔑 Login Admin:${NC}"
echo -e "   Username : ${WHITE}admin${NC}"
echo -e "   Password : ${WHITE}admin123${NC}"
echo ""
echo -e "${GREEN}🚀 Buka webnya, desainnya udah kayak web kampus luar negeri!${NC}"
