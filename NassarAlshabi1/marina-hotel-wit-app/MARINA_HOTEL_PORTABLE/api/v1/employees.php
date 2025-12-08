<?php
require_once __DIR__ . '/bootstrap.php';

handle_entity([
    'table' => 'employees',
    'pk' => 'id',
    'select' => '*',
    'filter_columns' => ['name','status'],
    'writable' => [
        'name' => 's',
        'basic_salary' => 'd',
        'status' => 's'
    ],
    'write_perm' => ['manage_settings']
]);
