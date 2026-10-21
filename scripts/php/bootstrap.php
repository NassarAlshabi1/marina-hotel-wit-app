<?php
if (!defined('MARINA_REPO_ROOT')) {
    define('MARINA_REPO_ROOT', dirname(__DIR__, 2));
}
$__scriptPath = parse_url($_SERVER['SCRIPT_NAME'] ?? '', PHP_URL_PATH) ?: '';
$__webRoot = preg_replace('#/scripts/php/(?:diagnostics|maintenance)/[^/]+$#', '/', $__scriptPath);
if (!is_string($__webRoot) || $__webRoot === $__scriptPath) {
    $__webRoot = '/';
}
$__isRelocatedTool = preg_match('#/scripts/php/(?:diagnostics|maintenance)/[^/]+$#', $__scriptPath) === 1;
if (!defined('MARINA_RELOCATED_TOOL')) {
    define('MARINA_RELOCATED_TOOL', $__isRelocatedTool);
}
if (!defined('MARINA_WEB_ROOT')) {
    define('MARINA_WEB_ROOT', $__webRoot);
}
set_include_path(MARINA_REPO_ROOT . PATH_SEPARATOR . get_include_path());
chdir(MARINA_REPO_ROOT);

// These legacy diagnostic/setup pages assume root-relative asset and admin URLs.
// Preserve that behavior when they are opened from their new nested URLs.
if (PHP_SAPI !== 'cli' && $__isRelocatedTool) {
    ob_start(static function (string $html): string {
        if (preg_match('/<base\b/i', $html)) {
            return $html;
        }
        return preg_replace_callback(
            '/<head\b[^>]*>/i',
            static fn (array $match): string => $match[0] . '<base href="' . htmlspecialchars(MARINA_WEB_ROOT, ENT_QUOTES, 'UTF-8') . '">',
            $html,
            1
        ) ?? $html;
    });
}
