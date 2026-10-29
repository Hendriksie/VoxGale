// Unit tests for the pure semver helpers and the `UpdateInfo` model (change
// 2026-10-29-update-tracker, task 3.1). No network, no dio — these cover
// the version comparison the update check runs against the installed app.

import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/update/update_check_client.dart';

void main() {
  group('parseVersionTag', () {
    test('parses a v-prefixed MAJOR.MINOR.PATCH tag', () {
      expect(parseVersionTag('v1.2.0'), [1, 2, 0]);
      expect(parseVersionTag('v1.3.0'), [1, 3, 0]);
      expect(parseVersionTag('v10.20.30'), [10, 20, 30]);
    });

    test('rejects non-semver tags', () {
      expect(parseVersionTag('nightly'), isNull);
      expect(parseVersionTag('v1.2'), isNull);
      expect(parseVersionTag('v1.2.3-beta'), isNull);
      expect(parseVersionTag('v1.2.3.4'), isNull);
      expect(parseVersionTag('1.2.3'), isNull); // no v prefix
      expect(parseVersionTag('v'), isNull);
      expect(parseVersionTag(''), isNull);
      expect(parseVersionTag('v1.2.x'), isNull);
      expect(parseVersionTag('v1.2.'), isNull);
      expect(parseVersionTag('v 1.2.3'), isNull);
    });
  });

  group('parseVersion', () {
    test('parses a bare versionName', () {
      expect(parseVersion('1.2.0'), [1, 2, 0]);
      expect(parseVersion('0.0.1'), [0, 0, 1]);
      expect(parseVersion('10.20.30'), [10, 20, 30]);
    });

    test('rejects malformed versions', () {
      expect(parseVersion('1.2'), isNull);
      expect(parseVersion('1.2.3.4'), isNull);
      expect(parseVersion('v1.2.3'), isNull); // tag prefix not allowed
      expect(parseVersion('1.2.3-beta'), isNull);
      expect(parseVersion(''), isNull);
      expect(parseVersion('1.2.x'), isNull);
      expect(parseVersion('1.2.'), isNull);
      expect(parseVersion('1.2.3 '), isNull);
    });
  });

  group('isNewerVersion', () {
    test('a newer minor release is newer', () {
      expect(isNewerVersion('1.3.0', '1.2.0'), isTrue);
    });

    test('a newer patch release is newer', () {
      expect(isNewerVersion('1.2.1', '1.2.0'), isTrue);
    });

    test('a newer major release is newer', () {
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('the same version is not newer', () {
      expect(isNewerVersion('1.2.0', '1.2.0'), isFalse);
    });

    test('an older release is not newer', () {
      expect(isNewerVersion('1.1.9', '1.2.0'), isFalse);
      expect(isNewerVersion('1.2.0', '1.2.1'), isFalse);
      expect(isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('malformed input is never newer', () {
      expect(isNewerVersion('nightly', '1.2.0'), isFalse);
      expect(isNewerVersion('1.3', '1.2.0'), isFalse);
      expect(isNewerVersion('1.3.0', 'nightly'), isFalse);
      expect(isNewerVersion('1.3.0-beta', '1.2.0'), isFalse);
      expect(isNewerVersion('', ''), isFalse);
    });

    test('compares component-wise, not lexically', () {
      // '1.10.0' > '1.9.0' numerically even though '10' < '9' as text.
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
    });
  });

  group('UpdateInfo', () {
    final pageUrl = Uri.parse(
      'https://github.com/Hendriksie/VoxGale/releases/tag/v1.3.0',
    );
    final otherPageUrl = Uri.parse(
      'https://github.com/Hendriksie/VoxGale/releases/tag/v1.4.0',
    );

    test('equality and hashCode cover both fields', () {
      final a = UpdateInfo(version: '1.3.0', releasePageUrl: pageUrl);
      final b = UpdateInfo(version: '1.3.0', releasePageUrl: pageUrl);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(UpdateInfo(version: '1.4.0', releasePageUrl: pageUrl)));
      expect(
        a,
        isNot(UpdateInfo(version: '1.3.0', releasePageUrl: otherPageUrl)),
      );
      expect(a, isNot('not an UpdateInfo'));
    });
  });
}
