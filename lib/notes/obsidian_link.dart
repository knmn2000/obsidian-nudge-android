/// Deep link that opens [notePath] in the named vault in the Obsidian app.
/// Obsidian wants the path without `.md`; encodeComponent gives `%20`, not `+`.
Uri obsidianLink(String notePath, {required String vault}) {
  final file = notePath.endsWith('.md')
      ? notePath.substring(0, notePath.length - 3)
      : notePath;
  return Uri.parse(
    'obsidian://open?vault=${Uri.encodeComponent(vault)}'
    '&file=${Uri.encodeComponent(file)}',
  );
}
