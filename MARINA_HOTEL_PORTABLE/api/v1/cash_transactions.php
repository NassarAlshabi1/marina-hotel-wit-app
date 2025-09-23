<?php
require_once __DIR__ . '/bootstrap.php';

handle_entity([
    'table' => 'cash_transactions',
    'pk' => 'id',
    'select' => '*',
    'filter_columns' => ['transaction_type','reference_type','description'],
    'writable' => [
        'register_id' => 'i',
        'transaction_type' => 's',
        'amount' => 'd',
        'reference_type' => 's',
        'reference_id' => 'i',
        'description' => 's',
        'transaction_time' => 's'
    ],
    'write_perm' => ['manage_cash']
]);
