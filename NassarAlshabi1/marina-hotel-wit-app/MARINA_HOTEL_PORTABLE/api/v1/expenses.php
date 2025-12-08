<?php
require_once __DIR__ . '/bootstrap.php';

handle_entity([
    'table' => 'expenses',
    'pk' => 'id',
    'select' => '*',
    'filter_columns' => ['expense_type','description','date'],
    'writable' => [
        'expense_type' => 's',
        'related_id' => 'i',
        'description' => 's',
        'amount' => 'd',
        'date' => 's'
    ],
    'write_perm' => ['manage_expenses']
]);
