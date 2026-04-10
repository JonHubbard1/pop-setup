<?php
/**
 * Renders the team message as a styled HTML page.
 * Opened by Chrome on each kiosk laptop at login.
 */

// Prevent Chrome from caching stale messages
header('Cache-Control: no-cache, no-store, must-revalidate');
header('Pragma: no-cache');
header('Expires: 0');

$file = __DIR__ . '/data/team-message.txt';
$message = file_exists($file) ? trim(file_get_contents($file)) : '';

if (empty($message)) {
    // No message — show nothing, auto-close
    header('Content-Type: text/html');
    echo '<html><body><script>window.close();</script></body></html>';
    exit;
}

$escaped = nl2br(htmlspecialchars($message, ENT_QUOTES, 'UTF-8'));
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>4Youth — Team Message</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1DA1D4;
            color: white;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            padding: 2rem;
        }
        .card {
            background: rgba(255,255,255,0.15);
            backdrop-filter: blur(10px);
            border-radius: 16px;
            padding: 2.5rem;
            max-width: 600px;
            width: 100%;
            text-align: center;
        }
        h1 { font-size: 1.3rem; margin-bottom: 1.5rem; font-weight: 600; }
        .message { font-size: 1.1rem; line-height: 1.6; }
        .close-hint {
            margin-top: 2rem;
            font-size: 0.85rem;
            opacity: 0.7;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>Team Message</h1>
        <div class="message"><?= $escaped ?></div>
        <div class="close-hint">Close this window to continue</div>
    </div>
</body>
</html>
