<?php
declare(strict_types=1);

header('Content-Type: application/json');
header('Cache-Control: no-store');
echo json_encode([
    'service' => 'digipay-sre-lab',
    'client_ip' => $_SERVER['REMOTE_ADDR'],
], JSON_THROW_ON_ERROR) . "\n";
