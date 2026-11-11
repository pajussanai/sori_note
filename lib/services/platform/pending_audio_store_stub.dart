import '../pending_audio_store.dart';

PendingAudioStore createPlatformPendingAudioStore() =>
    MemoryPendingAudioStore();
