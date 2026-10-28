import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxgale/mistral/api_key_store.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test('read, save, and delete go through secure storage under one key name',
      () async {
    final storage = MockFlutterSecureStorage();
    when(
      () => storage.read(key: any(named: 'key'), aOptions: any(named: 'aOptions')),
    ).thenAnswer((_) async => 'sk-test');
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
        aOptions: any(named: 'aOptions'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => storage.delete(key: any(named: 'key'), aOptions: any(named: 'aOptions')),
    ).thenAnswer((_) async {});

    final store = SecureStorageApiKeyStore(storage: storage);

    expect(await store.readKey(), 'sk-test');
    await store.saveKey('sk-new');
    await store.deleteKey();

    verify(
      () => storage.write(
        key: 'mistral_api_key',
        value: 'sk-new',
        aOptions: any(named: 'aOptions'),
      ),
    ).called(1);
    verify(
      () => storage.delete(key: 'mistral_api_key', aOptions: any(named: 'aOptions')),
    ).called(1);
  });

  test('a missing key reads as null', () async {
    final storage = MockFlutterSecureStorage();
    when(
      () => storage.read(key: any(named: 'key'), aOptions: any(named: 'aOptions')),
    ).thenAnswer((_) async => null);

    final store = SecureStorageApiKeyStore(storage: storage);

    expect(await store.readKey(), isNull);
  });
}
