<?php
require_once __DIR__ . '/bootstrap.php';

handle_entity([
    'table' => 'users',
    'pk' => 'user_id',
    'select' => '`user_id`,`username`,`full_name`,`email`,`phone`,`user_type`,`is_active`,`last_login`,`created_at`,`updated_at`,`deleted_at`',
    'filter_columns' => ['username','full_name','email','phone','user_type'],
    'writable' => [
        'username' => 's',
        'full_name' => 's',
        'email' => 's',
        'phone' => 's',
        'user_type' => 's',
        'is_active' => 'i'
    ],
    'write_perm' => ['manage_users']
]);
