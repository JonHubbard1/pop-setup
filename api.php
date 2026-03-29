<?php
/**
 * 4Youth Kiosk Device Tracking API
 *
 * POST /api.php?action=register  — Register/update a device and log a boot
 * GET  /api.php?action=devices   — List all registered devices
 * GET  /api.php?action=device&id=xxx — Get a single device with boot history
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
        ip TEXT,
        FOREIGN KEY (machine_id) REFERENCES devices(machine_id)
    )");

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

function handleDevices(): void {
    $db = getDb();

    $devices = $db->query("
        SELECT d.*,
            (SELECT COUNT(*) FROM boots b WHERE b.machine_id = d.machine_id) as boot_count,
            (SELECT b.ip FROM boots b WHERE b.machine_id = d.machine_id ORDER BY b.timestamp DESC LIMIT 1) as last_ip,
            (SELECT b.timestamp FROM boots b WHERE b.machine_id = d.machine_id ORDER BY b.timestamp DESC LIMIT 1) as last_boot
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

    $stmt = $db->prepare("SELECT timestamp, ip FROM boots WHERE machine_id = :mid ORDER BY timestamp DESC LIMIT 100");
    $stmt->execute([':mid' => $machineId]);
    $device['boots'] = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode($device);
}
