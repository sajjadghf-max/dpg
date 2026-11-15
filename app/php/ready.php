<?php
declare(strict_types=1);

// Ask the local FastCGI pool to handle its ping, without running application code.
function record(int $type, string $body): string {
    return pack('CCnnCC', 1, $type, 1, strlen($body), 0, 0) . $body;
}
function readExactly($socket, int $length): string {
    $data = '';
    while (strlen($data) < $length) {
        $chunk = fread($socket, $length - strlen($data));
        if ($chunk === false || $chunk === '') {
            throw new RuntimeException('FastCGI read failed or timed out');
        }
        $data .= $chunk;
    }
    return $data;
}
try {
    $socket = stream_socket_client('tcp://127.0.0.1:9000', $errno, $error, 2);
    if ($socket === false) { exit(1); }
    stream_set_timeout($socket, 2);
    $params = '';
    foreach (['REQUEST_METHOD' => 'GET', 'SCRIPT_FILENAME' => '/readyz',
              'SCRIPT_NAME' => '/readyz', 'REQUEST_URI' => '/readyz'] as $key => $value) {
        $params .= chr(strlen($key)) . chr(strlen($value)) . $key . $value;
    }
    fwrite($socket, record(1, pack('nCxxxxx', 1, 0)) . record(4, $params)
        . record(4, '') . record(5, ''));
    $output = '';
    do {
        $header = unpack('Cversion/Ctype/nid/nlength/Cpadding/Creserved', readExactly($socket, 8));
        $body = readExactly($socket, $header['length']);
        readExactly($socket, $header['padding']);
        if ($header['type'] === 6) { $output .= $body; }
    } while ($header['type'] !== 3);
    fclose($socket);
    exit(preg_match('/\r?\n\r?\nready$/', $output) === 1 ? 0 : 1);
} catch (Throwable $error) {
    fwrite(STDERR, $error->getMessage() . "\n");
    exit(1);
}
