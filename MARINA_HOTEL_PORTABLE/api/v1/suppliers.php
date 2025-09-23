<?php
require_once __DIR__ . '/bootstrap.php';

handle_entity([
    'table' => 'suppliers',
    'pk' => 'id',
    'select' => '*',
    'filter_columns' => ['name'],
    'writable' => [
        'name' => 's'
    ],
    'write_perm' => ['manage_settings']
]);
