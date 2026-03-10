<?php
if (!function_exists('get_magic_quotes_runtime')) {
    function get_magic_quotes_runtime()
    {
        return false;
    }
}

if (!function_exists('set_magic_quotes_runtime')) {
    function set_magic_quotes_runtime($value)
    {
        // noop for PHP 7/8
    }
}

require __DIR__.'/../includes/fpdf/makefont/makefont.php';

$fontFile = $argv[1] ?? null;
$encoding = $argv[2] ?? 'cp1256';
if ($fontFile === null) {
    fwrite(STDERR, "Usage: php scripts/generate_font.php /path/to/font.ttf [encoding]\n");
    exit(1);
}
MakeFont($fontFile, $encoding, true);
