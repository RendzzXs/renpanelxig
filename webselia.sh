#!/bin/bash
# ==========================================
# 🏫 SISTEM SEKOLAH (KARTU & KELULUSAN) v2.0
# Icons Only • Admin Login • Dark Mode
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

echo -e "${CYAN}[1/5] Install Nginx, PHP, MariaDB...${NC}"
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
CREATE TABLE admins (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL
);
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

CREATE TABLE school_info (
    id INT PRIMARY KEY,
    nama_sekolah VARCHAR(100),
    alamat_sekolah TEXT,
    nama_kepsek VARCHAR(100),
    nisn_kepsek VARCHAR(20),
    logo VARCHAR(255),
    ttd VARCHAR(255)
);
INSERT INTO school_info (id, nama_sekolah, alamat_sekolah, nama_kepsek, nisn_kepsek) VALUES (1, 'SMA NEGERI 1 RENDZZ', 'Jl. Pendidikan No. 1, Indonesia', 'Dr. H. Ahmad, M.Pd', '12345678');
SQLEOF
echo -e "${GREEN}  ✅ Database Siap${NC}"

echo -e "${CYAN}[3/5] Generate File Web...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{uploads,foto,assets}

# --- CONFIG & SESSION ---
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

# --- STYLE.CSS (DARK THEME + FONTAWESOME) ---
cat > "$WEB_ROOT/style.css" << 'CSSEOF'
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
@import url('https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css');
:root {
    --bg: #0f172a; --card: #1e293b; --text: #f8fafc; --text-muted: #94a3b8;
    --primary: #3b82f6; --success: #10b981; --danger: #ef4444; --border: #334155; --warning: #f59e0b;
}
* { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Inter', sans-serif; }
body { background: var(--bg); color: var(--text); padding: 20px; }
.container { max-width: 900px; margin: 0 auto; }
.card { background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 25px; margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
h1, h2, h3 { margin-bottom: 15px; color: var(--primary); }
.form-group { margin-bottom: 15px; }
label { display: block; margin-bottom: 5px; font-size: 0.9em; color: var(--text-muted); }
input, select, textarea { width: 100%; padding: 10px; border-radius: 8px; border: 1px solid var(--border); background: #0b1120; color: var(--text); outline: none; }
input:focus, select:focus { border-color: var(--primary); }
.btn { padding: 10px 20px; border-radius: 8px; border: none; font-weight: 600; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; gap: 8px; justify-content: center; transition: 0.3s; font-size: 0.9em; }
.btn-primary { background: var(--primary); color: white; }
.btn-primary:hover { background: #2563eb; }
.btn-success { background: var(--success); color: white; }
.btn-danger { background: var(--danger); color: white; }
.btn-warning { background: var(--warning); color: white; }
.btn-block { width: 100%; }

/* KARTU PELAJAR */
.kartu-container { background: linear-gradient(135deg, #1e3a8a, #3b82f6); border-radius: 15px; padding: 20px; color: white; position: relative; overflow: hidden; border: 2px solid #60a5fa; }
.kartu-header { display: flex; align-items: center; border-bottom: 2px solid rgba(255,255,255,0.3); padding-bottom: 10px; margin-bottom: 15px; }
.kartu-header i { font-size: 2em; margin-right: 15px; }
.kartu-body { display: flex; gap: 20px; }
.kartu-foto { width: 100px; height: 130px; background: #ccc; border-radius: 8px; object-fit: cover; border: 2px solid white; }
.kartu-info p { margin-bottom: 5px; font-size: 0.9em; }
.kartu-info b { color: #fbbf24; }
.kartu-footer { display: flex; justify-content: space-between; align-items: flex-end; margin-top: 20px; border-top: 1px solid rgba(255,255,255,0.3); padding-top: 10px; font-size: 0.8em; }
.ttd { text-align: center; }

/* PENGUMUMAN KELULUSAN */
.table { width: 100%; border-collapse: collapse; margin-top: 15px; }
.table th, .table td { padding: 12px; text-align: left; border-bottom: 1px solid var(--border); }
.table th { background: #0b1120; color: var(--primary); }
.status-lulus { color: var(--success); font-weight: bold; font-size: 1.2em; text-transform: uppercase; }
.status-gagal { color: var(--danger); font-weight: bold; font-size: 1.2em; text-transform: uppercase; }

@media (max-width: 600px) { .kartu-body { flex-direction: column; align-items: center; text-align: center; } .kartu-footer { flex-direction: column; gap: 10px; } }
@media print { body { background: white; color: black; } .no-print { display: none; } .kartu-container { border: 1px solid #000; color: black; background: #fff; } .kartu-info b { color: #000; } }
CSSEOF

# --- LOGIN.PHP ---
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php require 'config.php';
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $u = $_POST['username']; $p = $_POST['password'];
    $stmt = $pdo->prepare("SELECT * FROM admins WHERE username=? AND password=?"); $stmt->execute([$u, $p]);
    if ($stmt->fetch()) { $_SESSION['admin'] = $u; header('Location: admin.php'); exit; }
    else { $err = "Username atau Password salah!"; }
}
?>
<!DOCTYPE html>
<html lang="id"><head><meta charset="UTF-8"><title>Login Admin</title><link rel="stylesheet" href="style.css"></head>
<body>
<div class="container" style="max-width: 400px; margin-top: 100px;">
    <div class="card">
        <h2 style="text-align: center;"><i class="fas fa-lock"></i> Login Admin</h2>
        <?php if(isset($err)) echo "<p style='color:var(--danger); text-align:center; margin-bottom:10px;'>$err</p>"; ?>
        <form method="POST">
            <div class="form-group"><label>Username</label><input type="text" name="username" required></div>
            <div class="form-group"><label>Password</label><input type="password" name="password" required></div>
            <button type="submit" class="btn btn-primary btn-block"><i class="fas fa-sign-in-alt"></i> Masuk</button>
        </form>
        <div style="text-align: center; margin-top: 15px;"><a href="index.php" style="color: var(--text-muted); text-decoration: none; font-size: 0.9em;"><i class="fas fa-arrow-left"></i> Kembali</a></div>
    </div>
</div>
</body></html>
PHPEOF

# --- INDEX.PHP ---
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php require 'config.php'; $school = getSchool($pdo); ?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sistem Informasi Sekolah</title><link rel="stylesheet" href="style.css">
</head>
<body>
<div class="container" style="text-align: center; margin-top: 50px;">
    <i class="fas fa-school" style="font-size: 4em; color: var(--primary); margin-bottom: 20px;"></i>
    <h1 style="font-size: 2.5em; margin-bottom: 10px;"><?= $school['nama_sekolah'] ?></h1>
    <p style="color: var(--text-muted); margin-bottom: 40px;"><?= $school['alamat_sekolah'] ?></p>
    
    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px; max-width: 600px; margin: 0 auto;">
        <a href="kartu.php" class="card" style="text-decoration: none; transition: 0.3s;" onmouseover="this.style.borderColor='var(--primary)'" onmouseout="this.style.borderColor='var(--border)'">
            <i class="fas fa-id-card" style="font-size: 3em; color: var(--warning); margin-bottom: 15px;"></i>
            <h3>Cetak Kartu</h3><p style="color: var(--text-muted); font-size: 0.9em;">Buat & Cetak Kartu Pelajar</p>
        </a>
        <a href="kelulusan.php" class="card" style="text-decoration: none; transition: 0.3s;" onmouseover="this.style.borderColor='var(--primary)'" onmouseout="this.style.borderColor='var(--border)'">
            <i class="fas fa-graduation-cap" style="font-size: 3em; color: var(--success); margin-bottom: 15px;"></i>
            <h3>Cek Kelulusan</h3><p style="color: var(--text-muted); font-size: 0.9em;">Pengumuman Hasil Kelulusan</p>
        </a>
    </div>
    <div style="margin-top: 40px;">
        <a href="login.php" class="btn" style="background: var(--border); color: var(--text);"><i class="fas fa-user-shield"></i> Login Admin</a>
    </div>
</div>
</body>
</html>
PHPEOF

# --- KARTU.PHP ---
cat > "$WEB_ROOT/kartu.php" << 'PHPEOF'
<?php 
require 'config.php'; $school = getSchool($pdo);
$msg = '';
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
    
    $stmt = $pdo->prepare("INSERT INTO students (nama, nisn, nik, alamat, tempat_lahir, tanggal_lahir, nama_ortu, no_hp, golongan_darah, foto, jurusan) VALUES (?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE nama=?, alamat=?, foto=?");
    $stmt->execute([$nama, $nisn, $nik, $alamat, $tempat, $tgl, $ortu, $hp, $gol, $foto, $jurusan, $nama, $alamat, $foto]);
    $msg = "Kartu berhasil dibuat!";
}
?>
<!DOCTYPE html>
<html lang="id"><head><meta charset="UTF-8"><title>Cetak Kartu</title><link rel="stylesheet" href="style.css"></head>
<body>
<div class="container">
    <a href="index.php" class="no-print" style="color: var(--text-muted); text-decoration: none; margin-bottom: 20px; display: inline-block;"><i class="fas fa-arrow-left"></i> Kembali</a>
    <h1 class="no-print">Buat Kartu Pelajar</h1>
    <?php if($msg): ?><div class="no-print" style="background: rgba(16,185,129,0.2); padding: 15px; border-radius: 8px; margin-bottom: 20px; color: var(--success);"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?>
    
    <form method="POST" enctype="multipart/form-data" class="card no-print">
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
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
        <button type="submit" class="btn btn-primary"><i class="fas fa-save"></i> Buat Kartu</button>
    </form>

    <?php 
    if(isset($_GET['nisn'])) {
        $s = $pdo->prepare("SELECT * FROM students WHERE nisn=?"); $s->execute([$_GET['nisn']]); $siswa = $s->fetch();
        if($siswa): ?>
        <div class="kartu-container" id="kartu" style="margin-top: 30px;">
            <div class="kartu-header">
                <i class="fas fa-school"></i>
                <div><h3 style="color: white; margin: 0; font-size: 1.2em;"><?= $school['nama_sekolah'] ?></h3><p style="font-size: 0.7em; opacity: 0.8;"><?= $school['alamat_sekolah'] ?></p></div>
            </div>
            <div class="kartu-body">
                <img src="foto/<?= $siswa['foto'] ?>" class="kartu-foto" onerror="this.src='https://via.placeholder.com/100x130?text=Foto'">
                <div class="kartu-info">
                    <h3 style="color: white; margin-bottom: 10px; font-size: 1.2em;"><?= $siswa['nama'] ?></h3>
                    <p><b>NISN:</b> <?= $siswa['nisn'] ?></p>
                    <p><b>Jurusan:</b> <?= $siswa['jurusan'] ?></p>
                    <p><b>TTL:</b> <?= $siswa['tempat_lahir'] ?>, <?= date('d-m-Y', strtotime($siswa['tanggal_lahir'])) ?></p>
                    <p><b>Alamat:</b> <?= $siswa['alamat'] ?></p>
                </div>
            </div>
            <div class="kartu-footer">
                <div><p>Tanda Tangan Siswa,</p><br><br><p><?= $siswa['nama'] ?></p></div>
                <div class="ttd"><p>Kepala Sekolah,</p><br><br><p><b><?= $school['nama_kepsek'] ?></b></p><p>NISN: <?= $school['nisn_kepsek'] ?></p></div>
            </div>
        </div>
        <button onclick="window.print()" class="btn btn-success no-print" style="margin-top: 20px; width: 100%;"><i class="fas fa-print"></i> Cetak Kartu</button>
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
    
    $stmt = $pdo->prepare("INSERT INTO students (nama, nisn, kelas, jurusan, tempat_lahir, tanggal_lahir, nilai_matematika, nilai_indo, nilai_inggris, nilai_pilihan) VALUES (?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE kelas=?, nilai_matematika=?, nilai_indo=?, nilai_inggris=?, nilai_pilihan=?");
    $stmt->execute([$nama, $nisn, $kelas, $jurusan, $tempat, $tgl, $n1, $n2, $n3, $n4, $kelas, $n1, $n2, $n3, $n4]);
    $msg = "Data nilai berhasil disimpan!";
}
?>
<!DOCTYPE html>
<html lang="id"><head><meta charset="UTF-8"><title>Cek Kelulusan</title><link rel="stylesheet" href="style.css"></head>
<body>
<div class="container">
    <a href="index.php" class="no-print" style="color: var(--text-muted); text-decoration: none; margin-bottom: 20px; display: inline-block;"><i class="fas fa-arrow-left"></i> Kembali</a>
    <h1 class="no-print">Input Nilai Kelulusan</h1>
    <?php if($msg): ?><div class="no-print" style="background: rgba(16,185,129,0.2); padding: 15px; border-radius: 8px; margin-bottom: 20px; color: var(--success);"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?>
    
    <form method="POST" class="card no-print">
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
            <div class="form-group"><label>Nama Lengkap</label><input type="text" name="nama" required></div>
            <div class="form-group"><label>NISN</label><input type="text" name="nisn" required></div>
            <div class="form-group"><label>Kelas</label><input type="text" name="kelas" placeholder="XII IPA 1" required></div>
            <div class="form-group"><label>Jurusan</label><select name="jurusan"><option value="IPA">IPA</option><option value="IPS">IPS</option><option value="Bahasa">Bahasa</option><option value="TKJ">TKJ</option><option value="RPL">RPL</option></select></div>
            <div class="form-group"><label>Tempat Lahir</label><input type="text" name="tempat_lahir" required></div>
            <div class="form-group"><label>Tanggal Lahir</label><input type="date" name="tanggal_lahir" required></div>
        </div>
        <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-bottom: 15px;">
            <div class="form-group"><label>Matematika</label><input type="number" name="nilai_matematika" min="0" max="100" required></div>
            <div class="form-group"><label>B. Indo</label><input type="number" name="nilai_indo" min="0" max="100" required></div>
            <div class="form-group"><label>B. Inggris</label><input type="number" name="nilai_inggris" min="0" max="100" required></div>
            <div class="form-group"><label>Pilihan</label><input type="number" name="nilai_pilihan" min="0" max="100" required></div>
        </div>
        <button type="submit" class="btn btn-primary"><i class="fas fa-save"></i> Simpan Nilai</button>
    </form>

    <?php 
    if(isset($_GET['nisn'])) {
        $s = $pdo->prepare("SELECT * FROM students WHERE nisn=?"); $s->execute([$_GET['nisn']]); $siswa = $s->fetch();
        if($siswa): 
            $rata = ($siswa['nilai_matematika'] + $siswa['nilai_indo'] + $siswa['nilai_inggris'] + $siswa['nilai_pilihan']) / 4;
            $lulus = $rata >= 70;
        ?>
        <div class="card" style="margin-top: 30px;">
            <h2 style="text-align: center; margin-bottom: 20px;"><i class="fas fa-graduation-cap"></i> Hasil Kelulusan</h2>
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 20px;">
                <p><b>Nama:</b> <?= $siswa['nama'] ?></p>
                <p><b>NISN:</b> <?= $siswa['nisn'] ?></p>
                <p><b>TTL:</b> <?= $siswa['tempat_lahir'] ?>, <?= date('d-m-Y', strtotime($siswa['tanggal_lahir'])) ?></p>
                <p><b>Kelas:</b> <?= $siswa['kelas'] ?></p>
                <p><b>Jurusan:</b> <?= $siswa['jurusan'] ?></p>
            </div>
            <table class="table">
                <thead><tr><th>Mata Pelajaran</th><th>Nilai</th></tr></thead>
                <tbody>
                    <tr><td>Matematika</td><td><?= $siswa['nilai_matematika'] ?></td></tr>
                    <tr><td>Bahasa Indonesia</td><td><?= $siswa['nilai_indo'] ?></td></tr>
                    <tr><td>Bahasa Inggris</td><td><?= $siswa['nilai_inggris'] ?></td></tr>
                    <tr><td>Mapel Pilihan</td><td><?= $siswa['nilai_pilihan'] ?></td></tr>
                    <tr style="background: rgba(0,0,0,0.2);"><td><b>Rata-Rata</b></td><td><b><?= round($rata, 2) ?></b></td></tr>
                </tbody>
            </table>
            <div style="text-align: center; margin-top: 30px; padding: 20px; border-radius: 12px; background: <?= $lulus ? 'rgba(16,185,129,0.2)' : 'rgba(239,68,68,0.2)' ?>;">
                <p style="font-size: 0.9em; color: var(--text-muted);">Berdasarkan nilai yang diinput, siswa dinyatakan:</p>
                <h1 class="<?= $lulus ? 'status-lulus' : 'status-gagal' ?>" style="margin-top: 10px;"><?= $lulus ? 'LULUS' : 'TIDAK LULUS' ?></h1>
            </div>
        </div>
        <?php endif; 
    } ?>
</div>
</body></html>
PHPEOF

# --- ADMIN.PHP (DASHBOARD & EDIT SEKOLAH) ---
cat > "$WEB_ROOT/admin.php" << 'PHPEOF'
<?php 
require 'config.php'; requireAdmin(); 
$school = getSchool($pdo); $msg = '';

// Update Info Sekolah
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['update_school'])) {
    $nama = $_POST['nama_sekolah']; $alamat = $_POST['alamat_sekolah'];
    $kepsek = $_POST['nama_kepsek']; $nisn_kepsek = $_POST['nisn_kepsek'];
    
    $stmt = $pdo->prepare("UPDATE school_info SET nama_sekolah=?, alamat_sekolah=?, nama_kepsek=?, nisn_kepsek=? WHERE id=1");
    $stmt->execute([$nama, $alamat, $kepsek, $nisn_kepsek]);
    $msg = "Info sekolah berhasil diupdate!";
    $school = getSchool($pdo); // refresh
}
?>
<!DOCTYPE html>
<html lang="id"><head><meta charset="UTF-8"><title>Admin Dashboard</title><link rel="stylesheet" href="style.css"></head>
<body>
<div class="container">
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
        <h1 style="margin: 0;"><i class="fas fa-user-shield"></i> Dashboard Admin</h1>
        <a href="logout.php" class="btn btn-danger"><i class="fas fa-sign-out-alt"></i> Logout</a>
    </div>
    
    <?php if($msg): ?><div style="background: rgba(16,185,129,0.2); padding: 15px; border-radius: 8px; margin-bottom: 20px; color: var(--success);"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?>

    <div class="card">
        <h2><i class="fas fa-cog"></i> Pengaturan Sekolah</h2>
        <form method="POST">
            <input type="hidden" name="update_school" value="1">
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                <div class="form-group"><label>Nama Sekolah</label><input type="text" name="nama_sekolah" value="<?= $school['nama_sekolah'] ?>" required></div>
                <div class="form-group"><label>Nama Kepala Sekolah</label><input type="text" name="nama_kepsek" value="<?= $school['nama_kepsek'] ?>" required></div>
                <div class="form-group"><label>NISN Kepsek</label><input type="text" name="nisn_kepsek" value="<?= $school['nisn_kepsek'] ?>" required></div>
                <div class="form-group"><label>Alamat Sekolah</label><input type="text" name="alamat_sekolah" value="<?= $school['alamat_sekolah'] ?>" required></div>
            </div>
            <button type="submit" class="btn btn-primary"><i class="fas fa-save"></i> Simpan Perubahan</button>
        </form>
    </div>
    
    <div class="card" style="text-align: center;">
        <h2><i class="fas fa-database"></i> Akses Cepat</h2>
        <div style="display: flex; gap: 10px; justify-content: center;">
            <a href="kartu.php" class="btn btn-warning"><i class="fas fa-id-card"></i> Halaman Kartu</a>
            <a href="kelulusan.php" class="btn btn-success"><i class="fas fa-graduation-cap"></i> Halaman Kelulusan</a>
        </div>
    </div>
</div>
</body></html>
PHPEOF

# --- LOGOUT.PHP ---
cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); header('Location: login.php'); exit;
PHPEOF

echo -e "${CYAN}[4/5] Setup Nginx & SSL...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;

    location ~ /\.ht { deny all; }
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
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
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1
fi
PROTO="https"; [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] && PROTO="http"

echo -e "${GREEN}[5/5] Selesai!${NC}"
clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ INSTALASI BERHASIL!                    ║${NC}"
echo -e "${GREEN}║  🏫 Sistem Kartu & Kelulusan Sekolah       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 URL Web:${NC} $PROTO://$DOMAIN"
echo -e "${MAGENTA}🔒 Admin Panel:${NC} $PROTO://$DOMAIN/login.php"
echo ""
echo -e "${WHITE}🔑 Login Admin:${NC}"
echo -e "   Username : ${WHITE}admin${NC}"
echo -e "   Password : ${WHITE}admin123${NC}"
echo ""
echo -e "${YELLOW}💡 Tips: Halaman /kartu.php dan /kelulusan.php bisa langsung diakses siswa.${NC}"
echo -e "${GREEN}🚀 Semua fitur siap digunakan!${NC}"
