<?php
$files = [];
foreach ($files as $f) {
    if (file_exists($f)) {
        echo 'ok';
    }
}
