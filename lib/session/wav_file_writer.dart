import 'dart:io';
import 'dart:typed_data';

/// Writes a PCM16 mono stream to a WAV file (design decision D5).
///
/// The 44-byte header is written up front with placeholder sizes and patched
/// on [close]. Writes are synchronous on purpose: chunks are small (~3 KB per
/// 100 ms of audio) and their order is what makes the file valid.
///
/// Moved from `lib/spike/` to `lib/session/` with the production capture
/// service (task 3.1); the spike harness imports it from here.
class WavFileWriter {
  WavFileWriter._(this._raf, this._path);

  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bitsPerSample = 16;

  final RandomAccessFile _raf;
  final String _path;
  int _dataBytes = 0;
  bool _closed = false;

  static Future<WavFileWriter> create(String path) async {
    final raf = await File(path).open(mode: FileMode.write);
    await raf.writeFrom(_header(dataBytes: 0));
    return WavFileWriter._(raf, path);
  }

  String get path => _path;

  /// Appends one chunk of PCM16 mono audio.
  void add(Uint8List pcm) {
    if (_closed) {
      return;
    }
    _dataBytes += pcm.length;
    _raf.writeFromSync(pcm);
  }

  /// Patches the header sizes and closes the file.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _raf.setPosition(4); // RIFF chunk size
    await _raf.writeFrom(_uint32(36 + _dataBytes));
    await _raf.setPosition(40); // data chunk size
    await _raf.writeFrom(_uint32(_dataBytes));
    await _raf.close();
  }

  static List<int> _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> _uint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> _header({required int dataBytes}) {
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    return [
      ...'RIFF'.codeUnits,
      ..._uint32(36 + dataBytes),
      ...'WAVE'.codeUnits,
      ...'fmt '.codeUnits,
      ..._uint32(16), // PCM sub-chunk size
      ..._uint16(1), // audio format: PCM
      ..._uint16(numChannels),
      ..._uint32(sampleRate),
      ..._uint32(byteRate),
      ..._uint16(blockAlign),
      ..._uint16(bitsPerSample),
      ...'data'.codeUnits,
      ..._uint32(dataBytes),
    ];
  }
}
