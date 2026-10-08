import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:xml/xml_events.dart';

import 'iptv_live_tv_source.dart' show XzUnpacked, XzTooLarge, XzUnreadable, isXzPayload, unpackXzPayload;
import 'xmltv_parser.dart';

/// What reading a guide off a stream came to.
sealed class XmltvStreamResult {
  const XmltvStreamResult();
}

final class XmltvStreamRead extends XmltvStreamResult {
  const XmltvStreamRead(this.guide, {required this.packedBytes, required this.unpackedBytes});
  final XmltvGuide guide;
  final int packedBytes;
  final int unpackedBytes;
}

/// Past the size cap, packed or unpacked: dropped before it filled memory.
final class XmltvStreamTooLarge extends XmltvStreamResult {
  const XmltvStreamTooLarge();
}

final class XmltvStreamUnreadable extends XmltvStreamResult {
  const XmltvStreamUnreadable(this.error);
  final String error;
}

/// Read an XMLTV guide off [bytes] as they arrive (Plebz): in a background
/// isolate, plain, gzip or xz, never holding the guide whole — not as bytes,
/// not as text. Only what is kept for [channelIds] and [channelNames] comes
/// back.
///
/// A whole guide used to be downloaded, unpacked, decoded into one string and
/// copied into an isolate to be parsed: four copies of tens of megabytes at
/// once, on a TV stick with 2 GB. gzip and plain guides are now read chunk by
/// chunk; xz is unpacked whole, since its decoder only takes a whole input,
/// but its packed form is small and its text is still read in pieces.
Future<XmltvStreamResult> readXmltvStream(
  Stream<List<int>> bytes, {
  Set<String>? channelIds,
  Set<String> channelNames = const {},
  required int maxBytes,
}) async {
  final fromWorker = ReceivePort();
  final replies = StreamIterator(fromWorker);
  Isolate? isolate;
  StreamSubscription<List<int>>? subscription;
  try {
    isolate = await Isolate.spawn(
      _work,
      (reply: fromWorker.sendPort, channelIds: channelIds, channelNames: channelNames, maxBytes: maxBytes),
      errorsAreFatal: true,
      onError: fromWorker.sendPort,
      onExit: fromWorker.sendPort,
    );
    if (!await replies.moveNext()) return const XmltvStreamUnreadable('the reader did not start');
    final toWorker = replies.current as SendPort;

    final done = Completer<void>();
    subscription = bytes.listen(
      (chunk) =>
          toWorker.send(TransferableTypedData.fromList([chunk is Uint8List ? chunk : Uint8List.fromList(chunk)])),
      onError: (Object error) {
        if (!done.isCompleted) done.completeError(error);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    // The reader answers once — at the end, or early when it gives up.
    final answer = replies.moveNext();
    final first = await Future.any<Object?>([done.future.then((_) => _streamEnded), answer.then((_) => _answered)]);
    if (first == _streamEnded) {
      toWorker.send(null);
      if (!await answer) return const XmltvStreamUnreadable('the reader stopped without an answer');
    } else {
      // Given up before the end: what is still arriving is not wanted.
      await subscription.cancel();
    }
    final message = replies.current;
    return switch (message) {
      XmltvStreamResult() => message,
      // An uncaught error in the reader: [error, stack] as strings.
      [final Object? error, _] => XmltvStreamUnreadable('$error'),
      null => const XmltvStreamUnreadable('the reader ended without an answer'),
      _ => XmltvStreamUnreadable('unexpected answer $message'),
    };
  } catch (error) {
    return XmltvStreamUnreadable('$error');
  } finally {
    await subscription?.cancel();
    isolate?.kill(priority: Isolate.immediate);
    await replies.cancel();
    fromWorker.close();
  }
}

const _streamEnded = #streamEnded;
const _answered = #answered;

typedef _Job = ({SendPort reply, Set<String>? channelIds, Set<String> channelNames, int maxBytes});

void _work(_Job job) {
  final inbox = ReceivePort();
  job.reply.send(inbox.sendPort);

  final reader = XmltvGuideReader(channelIds: job.channelIds, channelNames: job.channelNames);
  final text = _TextFeed(reader, job.maxBytes);
  ByteConversionSink? input;
  BytesBuilder? xzPacked;
  var packed = 0;

  void answer(XmltvStreamResult result) {
    inbox.close();
    Isolate.exit(job.reply, result);
  }

  inbox.listen((message) {
    try {
      if (message is TransferableTypedData) {
        final chunk = message.materialize().asUint8List();
        packed += chunk.length;
        if (packed > job.maxBytes) return answer(const XmltvStreamTooLarge());
        if (input == null && xzPacked == null) {
          // Told by content, as the guides name themselves whatever they like.
          if (isXzPayload(chunk)) {
            xzPacked = BytesBuilder(copy: false);
          } else if (chunk.length >= 2 && chunk[0] == 0x1f && chunk[1] == 0x8b) {
            input = gzip.decoder.startChunkedConversion(text);
          } else {
            input = text;
          }
        }
        if (xzPacked case final packedXz?) {
          packedXz.add(chunk);
        } else {
          input!.add(chunk);
        }
        if (text.tooLarge) answer(const XmltvStreamTooLarge());
        return;
      }

      // The end of the download.
      if (xzPacked case final packedXz?) {
        switch (unpackXzPayload((data: packedXz.takeBytes(), cap: job.maxBytes))) {
          case XzUnpacked(:final bytes):
            const step = 64 * 1024;
            for (var start = 0; start < bytes.length; start += step) {
              text.add(Uint8List.sublistView(bytes, start, start + step > bytes.length ? bytes.length : start + step));
            }
          case XzTooLarge():
            return answer(const XmltvStreamTooLarge());
          case XzUnreadable(:final error):
            return answer(XmltvStreamUnreadable(error));
        }
      }
      (input ?? text).close();
      if (text.tooLarge) return answer(const XmltvStreamTooLarge());
      answer(XmltvStreamRead(reader.finish(), packedBytes: packed, unpackedBytes: text.bytes));
    } catch (error) {
      answer(XmltvStreamUnreadable('$error'));
    }
  });
}

/// Unpacked bytes in, events to the reader out: UTF-8 (malformed sequences
/// kept rather than losing the guide), then XML events, piece by piece.
class _TextFeed extends ByteConversionSink {
  _TextFeed(XmltvGuideReader reader, this._cap)
    : _decode = const Utf8Decoder(
        allowMalformed: true,
      ).startChunkedConversion(XmlEventDecoder().startChunkedConversion(_Events(reader)));

  final ByteConversionSink _decode;
  final int _cap;
  int bytes = 0;
  bool tooLarge = false;

  @override
  void add(List<int> chunk) {
    if (tooLarge) return;
    bytes += chunk.length;
    if (bytes > _cap) {
      tooLarge = true;
      return;
    }
    _decode.add(chunk);
  }

  @override
  void close() {
    if (!tooLarge) _decode.close();
  }
}

class _Events implements Sink<List<XmlEvent>> {
  _Events(this._reader);

  final XmltvGuideReader _reader;

  @override
  void add(List<XmlEvent> events) {
    for (final event in events) {
      _reader.add(event);
    }
  }

  @override
  void close() {}
}
