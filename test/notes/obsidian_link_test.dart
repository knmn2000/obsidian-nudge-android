import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_nudge/notes/obsidian_link.dart';

void main() {
  test('strips .md and percent-encodes spaces and slashes', () {
    expect(
      obsidianLink(
        'Study Notes/Big O & friends.md',
        vault: 'My Vault',
      ).toString(),
      'obsidian://open?vault=My%20Vault&file=Study%20Notes%2FBig%20O%20%26%20friends',
    );
  });

  test('leaves a path without .md alone', () {
    expect(
      obsidianLink('a/b', vault: 'Vault').toString(),
      contains('file=a%2Fb'),
    );
  });
}
