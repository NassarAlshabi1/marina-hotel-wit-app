<?php
require_once __DIR__ . '/bootstrap.php';

handle_entity([
    'table' => 'booking_notes',
    'pk' => 'note_id',
    'select' => '*',
    'filter_columns' => ['note_text','created_by'],
    'writable' => [
        'booking_id' => 'i',
        'note_text' => 's',
        'alert_type' => 's',
        'alert_until' => 's',
        'is_active' => 'i',
        'created_at' => 's',
        'created_by' => 's'
    ],
    'write_perm' => ['manage_bookings']
]);
