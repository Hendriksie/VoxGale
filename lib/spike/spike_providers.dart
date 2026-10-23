import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';

/// Pinned model IDs and rates (single source, design D3/D7).
final mistralConfigProvider =
    Provider<MistralConfig>((ref) => MistralConfig.defaults);

/// Secure-storage-backed API key store.
final apiKeyStoreProvider =
    Provider<ApiKeyStore>((ref) => SecureStorageApiKeyStore());

/// The user's saved API key, or null when none is saved.
final apiKeyProvider =
    FutureProvider<String?>((ref) => ref.watch(apiKeyStoreProvider).readKey());
