<?php
declare(strict_types=1);
header('Content-Type: application/json');
if ($_SERVER['REQUEST_METHOD'] === 'GET' && $_SERVER['REQUEST_URI'] === '/healthz') {
    echo '{"ok":true}';
    return;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST' || $_SERVER['REQUEST_URI'] !== '/alerts') {
    http_response_code(404);
    echo '{"error":"not found"}';
    return;
}
$payload = json_decode(file_get_contents('php://input', false, null, 0, 1048576), true);
if (!is_array($payload) || !isset($payload['alerts']) || !is_array($payload['alerts'])) {
    http_response_code(400);
    echo '{"error":"invalid alert payload"}';
    return;
}
foreach ($payload['alerts'] as $alert) {
    // Log only routing fields; annotations may contain sensitive diagnostic details.
    error_log(json_encode([
        'event' => 'alert_received',
        'time' => gmdate('c'),
        'status' => $alert['status'] ?? 'unknown',
        'alertname' => $alert['labels']['alertname'] ?? 'unknown',
        'severity' => $alert['labels']['severity'] ?? 'unknown',
    ], JSON_UNESCAPED_SLASHES));
}
echo '{"accepted":true}';
