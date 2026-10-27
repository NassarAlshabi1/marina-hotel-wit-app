# PHP tools

Root-level PHP entry points remain in the repository root because deployed site routes, scheduled sync and the shared PDF library depend on those paths. Auxiliary scripts are grouped here:

- [`diagnostics/`](diagnostics/) — test and diagnostic pages.
- [`maintenance/`](maintenance/) — setup, repair and migration utilities.
- [`bootstrap.php`](bootstrap.php) — preserves root-relative includes and paths after relocation.

Run database-changing maintenance tools only with an appropriate backup and authorized environment. The Windows builders copy `maintenance/setup_exe_database.php` into the generated package web root, where it continues to run as a root-level script.
