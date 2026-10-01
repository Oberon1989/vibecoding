<?php

//declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

$root = realpath(getcwd());

function out(array $data, int $code = 200): never
{
    http_response_code($code);

    echo json_encode(
        $data,
        JSON_UNESCAPED_UNICODE |
        JSON_UNESCAPED_SLASHES |
        JSON_PRETTY_PRINT
    );

    exit;
}

$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

/*
 * /files/foo/bar
 *       ↓
 * foo/bar
 */
$path = str_starts_with($uri, '/files')
    ? substr($uri, 6)
    : $uri;

$path = trim($path, '/');

/*
 * Защита от ../
 */
$parts = [];

foreach (explode('/', $path) as $part) {
    $part = rawurldecode($part);

    if ($part === '' || $part === '.' || $part === '..') {
        continue;
    }

    $parts[] = $part;
}

$target = $root . DIRECTORY_SEPARATOR . implode(
    DIRECTORY_SEPARATOR,
    $parts
);

$target = realpath($target);

if ($target === false || (
    $target !== $root &&
    !str_starts_with(
        $target,
        rtrim($root, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR
    )
)) {
    out([
        'error' => 'Not found',
        'path' => '/' . $path
    ], 404);
}


/*
 * DIRECTORY
 */
if (is_dir($target)) {

    $items = [];

    foreach (scandir($target) ?: [] as $name) {

        if ($name === '.' || $name === '..') {
            continue;
        }

        $item = $target . DIRECTORY_SEPARATOR . $name;

        $relative = trim(
            ($path ? $path . '/' : '') . $name,
            '/'
        );

        $items[] = [
            'name' => $name,
            'type' => is_dir($item)
                ? 'directory'
                : 'file',
            'url' => '/files/' . $relative
        ];
    }

    out([
        'type' => 'directory',
        'path' => $path,
        'items' => $items
    ]);
}


/*
 * FILE
 */
if (is_file($target)) {

    $content = file_get_contents($target);

    if ($content === false) {
        out([
            'error' => 'Cannot read file'
        ], 500);
    }

    out([
        'type' => 'file',
        'name' => basename($target),
        'path' => $path,
        'content' => $content
    ]);
}


out([
    'error' => 'Unsupported object'
], 400);

