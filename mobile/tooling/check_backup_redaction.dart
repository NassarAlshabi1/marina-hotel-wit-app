import 'dart:convert';
import 'dart:io';

void main() async {
  final bannedKeys = ['password', 'secret', 'token'];
  final backupDir = Directory('backups');
  if (!backupDir.existsSync()) {
    stdout.writeln('No backups directory; skipping redaction check');
    return;
  }

  final violations = <String>[];

  for (final entity in backupDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final content = await entity.readAsString();
    final data = jsonDecode(content);

    void scan(dynamic node, String path) {
      if (node is Map) {
        for (final entry in node.entries) {
          final key = entry.key.toString().toLowerCase();
          if (bannedKeys.contains(key)) {
            violations.add('$path/$key in ${entity.path}');
          }
          scan(entry.value, '$path/$key');
        }
      } else if (node is List) {
        for (var i = 0; i < node.length; i++) {
          scan(node[i], '$path[$i]');
        }
      }
    }

    scan(data, '');
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Found sensitive fields: ${violations.join(', ')}');
    exit(1);
  }

  stdout.writeln('Backup redaction check passed');
}
