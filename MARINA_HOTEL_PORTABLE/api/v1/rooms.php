<?php
require_once __DIR__ . '/bootstrap.php';

handle_entity([
    'table' => 'rooms',
    'pk' => 'room_number',
    'select' => '`room_number`,`type`,`price`,`status`,`created_at`,`updated_at`,`deleted_at`',
    'filter_columns' => ['room_number','type','status'],
    'writable' => [
        'room_number' => 's',
        'type' => 's',
        'price' => 'd',
        'status' => 's'
    ],
    'write_perm' => ['manage_rooms']
]);
