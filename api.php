<?php
/**
 * 4Youth Kiosk Device Tracking API
 *
 * POST /api.php?action=register  — Register/update a device and log a boot
 * GET  /api.php?action=devices   — List all registered devices
 * GET  /api.php?action=device&id=xxx — Get a single device with boot history
 * GET  /api.php?action=get-message — Get the current team message (raw text)
 * POST /api.php?action=save-message — Save team message (requires admin_password)
 */

header('Content-Type: application/json');

// Simple shared secret to prevent random internet submissions
define('API_SECRET', '4youth-kiosk-2026');

$dbPath = __DIR__ . '/data/devices.sqlite';

// Ensure data directory exists
if (!is_dir(__DIR__ . '/data')) {
    mkdir(__DIR__ . '/data', 0750, true);
}

function getDb(): PDO {
    global $dbPath;
    $db = new PDO('sqlite:' . $dbPath);
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // Create tables if needed
    $db->exec("CREATE TABLE IF NOT EXISTS devices (
        machine_id TEXT PRIMARY KEY,
        hostname TEXT,
        cpu TEXT,
        ram_gb REAL,
        disk_gb REAL,
        mac_address TEXT,
        serial TEXT,
        os_version TEXT,
        first_seen TEXT DEFAULT (datetime('now')),
        last_seen TEXT DEFAULT (datetime('now'))
    )");

    $db->exec("CREATE TABLE IF NOT EXISTS boots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        machine_id TEXT NOT NULL,
        timestamp TEXT DEFAULT (datetime('now')),
        shutdown_time TEXT,
        ip TEXT,
        FOREIGN KEY (machine_id) REFERENCES devices(machine_id)
    )");

    // Add shutdown_time column if upgrading from older schema
    $cols = $db->query("PRAGMA table_info(boots)")->fetchAll(PDO::FETCH_COLUMN, 1);
    if (!in_array('shutdown_time', $cols)) {
        $db->exec("ALTER TABLE boots ADD COLUMN shutdown_time TEXT");
    }

    $db->exec("CREATE INDEX IF NOT EXISTS idx_boots_machine ON boots(machine_id, timestamp DESC)");

    return $db;
}

$action = $_GET['action'] ?? '';

try {
    switch ($action) {
        case 'register':
            handleRegister();
            break;
        case 'devices':
            handleDevices();
            break;
        case 'device':
            handleDevice();
            break;
        case 'get-message':
            handleGetMessage();
            break;
        case 'save-message':
            handleSaveMessage();
            break;
        case 'shutdown':
            handleShutdown();
            break;
        case 'upload-wallpaper':
            handleUploadWallpaper();
            break;
        case 'list-wallpapers':
            handleListWallpapers();
            break;
        case 'delete-wallpaper':
            handleDeleteWallpaper();
            break;
        case 'wallpaper-image':
            handleWallpaperImage();
            break;
        default:
            http_response_code(400);
            echo json_encode(['error' => 'Unknown action']);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Server error']);
}

function handleRegister(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        echo json_encode(['error' => 'POST required']);
        return;
    }

    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid JSON']);
        return;
    }

    // Check shared secret
    if (($input['secret'] ?? '') !== API_SECRET) {
        http_response_code(403);
        echo json_encode(['error' => 'Invalid secret']);
        return;
    }

    $machineId = $input['machine_id'] ?? '';
    if (empty($machineId)) {
        http_response_code(400);
        echo json_encode(['error' => 'machine_id required']);
        return;
    }

    $db = getDb();

    // Upsert device
    $stmt = $db->prepare("INSERT INTO devices (machine_id, hostname, cpu, ram_gb, disk_gb, mac_address, serial, os_version, last_seen)
        VALUES (:mid, :hostname, :cpu, :ram, :disk, :mac, :serial, :os, datetime('now'))
        ON CONFLICT(machine_id) DO UPDATE SET
            hostname = :hostname,
            cpu = :cpu,
            ram_gb = :ram,
            disk_gb = :disk,
            mac_address = :mac,
            serial = :serial,
            os_version = :os,
            last_seen = datetime('now')");

    $stmt->execute([
        ':mid'      => $machineId,
        ':hostname' => $input['hostname'] ?? '',
        ':cpu'      => $input['cpu'] ?? '',
        ':ram'      => $input['ram_gb'] ?? 0,
        ':disk'     => $input['disk_gb'] ?? 0,
        ':mac'      => $input['mac_address'] ?? '',
        ':serial'   => $input['serial'] ?? '',
        ':os'       => $input['os_version'] ?? '',
    ]);

    // Log boot
    $ip = $_SERVER['REMOTE_ADDR'] ?? $input['ip'] ?? '';
    $stmt = $db->prepare("INSERT INTO boots (machine_id, ip) VALUES (:mid, :ip)");
    $stmt->execute([':mid' => $machineId, ':ip' => $ip]);

    // Keep only last 200 boots per device
    $db->prepare("DELETE FROM boots WHERE machine_id = :mid AND id NOT IN (
        SELECT id FROM boots WHERE machine_id = :mid2 ORDER BY timestamp DESC LIMIT 200
    )")->execute([':mid' => $machineId, ':mid2' => $machineId]);

    echo json_encode(['status' => 'ok']);
}

function handleShutdown(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        echo json_encode(['error' => 'POST required']);
        return;
    }

    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid JSON']);
        return;
    }

    if (($input['secret'] ?? '') !== API_SECRET) {
        http_response_code(403);
        echo json_encode(['error' => 'Invalid secret']);
        return;
    }

    $machineId = $input['machine_id'] ?? '';
    if (empty($machineId)) {
        http_response_code(400);
        echo json_encode(['error' => 'machine_id required']);
        return;
    }

    $db = getDb();

    // Set shutdown_time on the most recent boot for this device
    $stmt = $db->prepare("UPDATE boots SET shutdown_time = datetime('now')
        WHERE id = (SELECT id FROM boots WHERE machine_id = :mid ORDER BY timestamp DESC LIMIT 1)
        AND shutdown_time IS NULL");
    $stmt->execute([':mid' => $machineId]);

    echo json_encode(['status' => 'ok']);
}

function handleDevices(): void {
    $db = getDb();

    $devices = $db->query("
        SELECT d.*,
            (SELECT COUNT(*) FROM boots b WHERE b.machine_id = d.machine_id) as boot_count,
            (SELECT b.ip FROM boots b WHERE b.machine_id = d.machine_id ORDER BY b.timestamp DESC LIMIT 1) as last_ip,
            (SELECT b.timestamp FROM boots b WHERE b.machine_id = d.machine_id ORDER BY b.timestamp DESC LIMIT 1) as last_boot,
            (SELECT b.shutdown_time FROM boots b WHERE b.machine_id = d.machine_id ORDER BY b.timestamp DESC LIMIT 1) as last_shutdown
        FROM devices d
        ORDER BY last_seen DESC
    ")->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode($devices);
}

function handleDevice(): void {
    $machineId = $_GET['id'] ?? '';
    if (empty($machineId)) {
        http_response_code(400);
        echo json_encode(['error' => 'id required']);
        return;
    }

    $db = getDb();

    $stmt = $db->prepare("SELECT * FROM devices WHERE machine_id = :mid");
    $stmt->execute([':mid' => $machineId]);
    $device = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$device) {
        http_response_code(404);
        echo json_encode(['error' => 'Device not found']);
        return;
    }

    $stmt = $db->prepare("SELECT timestamp, shutdown_time, ip FROM boots WHERE machine_id = :mid ORDER BY timestamp DESC LIMIT 100");
    $stmt->execute([':mid' => $machineId]);
    $device['boots'] = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode($device);
}

function getMessageFile(): string {
    return __DIR__ . '/data/team-message.txt';
}

function handleGetMessage(): void {
    $file = getMessageFile();
    $message = file_exists($file) ? file_get_contents($file) : '';
    echo json_encode(['message' => $message]);
}

function getWallpaperDir(): string {
    $dir = __DIR__ . '/data/wallpapers';
    if (!is_dir($dir)) {
        mkdir($dir, 0750, true);
    }
    return $dir;
}

function authenticateAdmin(): bool {
    $input = json_decode(file_get_contents('php://input'), true);
    $password = $input['password'] ?? ($_POST['password'] ?? '');

    $configPath = __DIR__ . '/config.json';
    $config = json_decode(file_get_contents($configPath), true);
    $adminPassword = $config['admin_password'] ?? '';

    return !empty($adminPassword) && $password === $adminPassword;
}

function handleUploadWallpaper(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        echo json_encode(['error' => 'POST required']);
        return;
    }

    // Authenticate using password from POST field
    $configPath = __DIR__ . '/config.json';
    $config = json_decode(file_get_contents($configPath), true);
    $adminPassword = $config['admin_password'] ?? '';

    if (empty($adminPassword) || ($_POST['password'] ?? '') !== $adminPassword) {
        http_response_code(403);
        echo json_encode(['error' => 'Invalid password']);
        return;
    }

    if (!isset($_FILES['wallpaper']) || $_FILES['wallpaper']['error'] !== UPLOAD_ERR_OK) {
        http_response_code(400);
        echo json_encode(['error' => 'No file uploaded']);
        return;
    }

    $file = $_FILES['wallpaper'];

    // Validate file type
    $allowedTypes = ['image/png', 'image/jpeg', 'image/webp'];
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mimeType = finfo_file($finfo, $file['tmp_name']);
    finfo_close($finfo);

    if (!in_array($mimeType, $allowedTypes)) {
        http_response_code(400);
        echo json_encode(['error' => 'Only PNG, JPEG, and WebP images are allowed']);
        return;
    }

    // Limit file size to 10MB
    if ($file['size'] > 10 * 1024 * 1024) {
        http_response_code(400);
        echo json_encode(['error' => 'File too large (max 10MB)']);
        return;
    }

    // Sanitise filename
    $originalName = pathinfo($file['name'], PATHINFO_FILENAME);
    $extension = pathinfo($file['name'], PATHINFO_EXTENSION);
    $safeName = preg_replace('/[^a-zA-Z0-9_-]/', '-', $originalName);
    $safeName = trim($safeName, '-');
    if (empty($safeName)) $safeName = 'wallpaper';
    $filename = $safeName . '.' . strtolower($extension);

    $dir = getWallpaperDir();

    // Avoid overwriting — append number if needed
    $dest = $dir . '/' . $filename;
    $counter = 1;
    while (file_exists($dest)) {
        $filename = $safeName . '-' . $counter . '.' . strtolower($extension);
        $dest = $dir . '/' . $filename;
        $counter++;
    }

    if (!move_uploaded_file($file['tmp_name'], $dest)) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to save file']);
        return;
    }

    echo json_encode(['status' => 'ok', 'filename' => $filename]);
}

function handleListWallpapers(): void {
    $dir = getWallpaperDir();
    $files = [];

    foreach (glob($dir . '/*.{png,jpg,jpeg,webp}', GLOB_BRACE) as $path) {
        $files[] = basename($path);
    }

    sort($files);
    echo json_encode($files);
}

function handleDeleteWallpaper(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        echo json_encode(['error' => 'POST required']);
        return;
    }

    $input = json_decode(file_get_contents('php://input'), true);

    // Authenticate
    $configPath = __DIR__ . '/config.json';
    $config = json_decode(file_get_contents($configPath), true);
    $adminPassword = $config['admin_password'] ?? '';

    if (empty($adminPassword) || ($input['password'] ?? '') !== $adminPassword) {
        http_response_code(403);
        echo json_encode(['error' => 'Invalid password']);
        return;
    }

    $filename = $input['filename'] ?? '';
    if (empty($filename) || str_contains($filename, '/') || str_contains($filename, '..')) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid filename']);
        return;
    }

    $path = getWallpaperDir() . '/' . $filename;
    if (!file_exists($path)) {
        http_response_code(404);
        echo json_encode(['error' => 'File not found']);
        return;
    }

    unlink($path);
    echo json_encode(['status' => 'ok']);
}

function handleWallpaperImage(): void {
    $filename = $_GET['file'] ?? '';
    if (empty($filename) || str_contains($filename, '/') || str_contains($filename, '..')) {
        http_response_code(400);
        echo 'Invalid filename';
        return;
    }

    $path = getWallpaperDir() . '/' . $filename;
    if (!file_exists($path)) {
        http_response_code(404);
        echo 'Not found';
        return;
    }

    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime = finfo_file($finfo, $path);
    finfo_close($finfo);

    header('Content-Type: ' . $mime);
    header('Content-Length: ' . filesize($path));
    readfile($path);
}

function handleSaveMessage(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        echo json_encode(['error' => 'POST required']);
        return;
    }

    $input = json_decode(file_get_contents('php://input'), true);
    if ($input === null) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid JSON']);
        return;
    }

    // Authenticate using the admin password from config.json
    $configPath = __DIR__ . '/config.json';
    $config = json_decode(file_get_contents($configPath), true);
    $adminPassword = $config['admin_password'] ?? '';

    if (empty($adminPassword) || ($input['password'] ?? '') !== $adminPassword) {
        http_response_code(403);
        echo json_encode(['error' => 'Invalid password']);
        return;
    }

    $message = $input['message'] ?? '';
    file_put_contents(getMessageFile(), $message);

    echo json_encode(['status' => 'ok']);
}
