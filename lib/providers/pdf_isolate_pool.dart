import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi_pkg;
import 'package:pdfium_flutter/pdfium_flutter.dart';

class _IsolateWorker {
  final Isolate isolate;
  final SendPort sendPort;
  final ReceivePort receivePort;

  _IsolateWorker({
    required this.isolate,
    required this.sendPort,
    required this.receivePort,
  });

  void dispose() {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

class PdfIsolatePool {
  final int poolSize;
  final List<_IsolateWorker> _workers = [];
  bool _initialized = false;

  Map<int, List<double>>? _pageOriginalSizes;
  double _originalMaxWidth = 0.0;
  int _pageCount = 0;

  PdfIsolatePool({this.poolSize = 4});

  bool get isInitialized => _initialized;
  int? get pageCount => _initialized ? _pageCount : null;
  Map<int, List<double>>? get pageOriginalSizes =>
      _initialized ? _pageOriginalSizes : null;
  double? get originalMaxWidth => _initialized ? _originalMaxWidth : null;



  Future<void> initialize(Uint8List fileBytes) async {
    if (_initialized) {
      await dispose();
    }
    _workers.clear();

    final initFutures = <Future<_IsolateWorker>>[];
    for (int i = 0; i < poolSize; i++) {
      initFutures.add(_spawnWorker(fileBytes));
    }

    final workers = await Future.wait(initFutures);
    _workers.addAll(workers);

    final metaPort = ReceivePort();
    workers.first.sendPort.send({
      'type': 'getMeta',
      'replyPort': metaPort.sendPort,
    });
    final meta = await metaPort.first as Map<String, dynamic>;
    metaPort.close();

    _pageCount = meta['pageCount'] as int;
    _originalMaxWidth = meta['originalMaxWidth'] as double;
    _pageOriginalSizes =
        (meta['pageOriginalSizes'] as Map<dynamic, dynamic>).map(
      (k, v) => MapEntry(
        k as int,
        (v as List<dynamic>).cast<double>(),
      ),
    );

    _initialized = true;
  }

  Future<_IsolateWorker> _spawnWorker(Uint8List fileBytes) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _pdfWorkerEntry,
      [receivePort.sendPort, fileBytes],
    );

    final initData = await receivePort.first as List<dynamic>;
    final sendPort = initData[0] as SendPort;

    return _IsolateWorker(
      isolate: isolate,
      sendPort: sendPort,
      receivePort: receivePort,
    );
  }

  SendPort _sendPortForPage(int pageIndex) {
    return _workers[pageIndex % _workers.length].sendPort;
  }

  Future<Map<String, dynamic>?> renderPage(
    int pageIndex, {
    double scale = 1.0,
  }) async {
    if (!_initialized || _workers.isEmpty) return null;

    final sendPort = _sendPortForPage(pageIndex);
    final responsePort = ReceivePort();

    sendPort.send({
      'type': 'render',
      'pageIndex': pageIndex,
      'scale': scale,
      'replyPort': responsePort.sendPort,
    });

    final result = await responsePort.first;
    responsePort.close();
    return result as Map<String, dynamic>?;
  }

  Future<List<Map<String, dynamic>?>> renderPages(
    List<int> pageIndices, {
    double scale = 1.0,
  }) async {
    if (!_initialized || _workers.isEmpty) {
      return List.filled(pageIndices.length, null);
    }

    final responsePorts = <ReceivePort>[];
    final futures = <Future<dynamic>>[];

    for (final pageIndex in pageIndices) {
      final sendPort = _sendPortForPage(pageIndex);
      final responsePort = ReceivePort();
      responsePorts.add(responsePort);
      futures.add(responsePort.first);

      sendPort.send({
        'type': 'render',
        'pageIndex': pageIndex,
        'scale': scale,
        'replyPort': responsePort.sendPort,
      });
    }

    final results = await Future.wait(futures);

    for (final port in responsePorts) {
      port.close();
    }

    return results.cast<Map<String, dynamic>?>();
  }

  Future<List<Map<String, dynamic>?>> renderAllPages({
    double scale = 1.0,
  }) async {
    if (!_initialized || _workers.isEmpty) return [];

    final pageIndices = List<int>.generate(_pageCount, (i) => i);
    return renderPages(pageIndices, scale: scale);
  }

  Future<void> dispose() async {
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();
    _pageOriginalSizes = null;
    _originalMaxWidth = 0.0;
    _pageCount = 0;
    _initialized = false;
  }

  static void _pdfWorkerEntry(List<dynamic> args) {
    final SendPort mainSendPort = args[0];
    final Uint8List fileBytes = args[1];

    final childReceivePort = ReceivePort();
    mainSendPort.send([childReceivePort.sendPort]);

    pdfiumBindings.FPDF_InitLibrary();
    FPDF_DOCUMENT? doc;
    ffi.Pointer<ffi.Uint8>? fileBuffer;
    Map<int, List<double>>? pageOriginalSizes;
    double originalMaxWidth = 0.0;
    int pageCount = 0;

    fileBuffer = ffi_pkg.calloc<ffi.Uint8>(fileBytes.length);
    fileBuffer.asTypedList(fileBytes.length).setAll(0, fileBytes);
    doc = pdfiumBindings.FPDF_LoadMemDocument(
      fileBuffer.cast<ffi.Void>(),
      fileBytes.length,
      ffi.nullptr,
    );

    if (doc != ffi.nullptr) {
      pageCount = pdfiumBindings.FPDF_GetPageCount(doc);
      pageOriginalSizes = <int, List<double>>{};
      for (int i = 0; i < pageCount; i++) {
        final page = pdfiumBindings.FPDF_LoadPage(doc, i);
        pageOriginalSizes[i] = [
          pdfiumBindings.FPDF_GetPageWidthF(page),
          pdfiumBindings.FPDF_GetPageHeightF(page),
        ];
        originalMaxWidth = max(
          originalMaxWidth,
          pageOriginalSizes[i]?[0] ?? 0.0,
        );
        pdfiumBindings.FPDF_ClosePage(page);
      }
    }

    childReceivePort.listen((message) {
      final String type = message['type'];
      final SendPort replyPort = message['replyPort'];

      if (type == 'getMeta') {
        replyPort.send({
          'pageCount': pageCount,
          'pageOriginalSizes': pageOriginalSizes,
          'originalMaxWidth': originalMaxWidth,
        });
      } else if (type == 'render') {
        if (doc == null || pageOriginalSizes == null) {
          replyPort.send({'success': false, 'error': 'PDF not loaded'});
          return;
        }
        final int index = message['pageIndex'];
        final double scale = (message['scale'] ?? 1.0);
        final sizes = pageOriginalSizes;

        final page = pdfiumBindings.FPDF_LoadPage(doc, index);
        final pageSize = sizes[index];
        final double originalWidth = pageSize![0];
        final double originalHeight = pageSize[1];

        final int width = (originalWidth * scale).ceil();
        final int height = (originalHeight * scale).ceil();

        final bitmap = pdfiumBindings.FPDFBitmap_Create(width, height, 4);
        pdfiumBindings.FPDFBitmap_FillRect(
          bitmap,
          0,
          0,
          width,
          height,
          0xFFFFFFFF,
        );
        pdfiumBindings.FPDF_RenderPageBitmap(
          bitmap,
          page,
          0,
          0,
          width,
          height,
          0,
          FPDF_ANNOT | FPDF_LCD_TEXT,
        );

        final buffer = pdfiumBindings.FPDFBitmap_GetBuffer(bitmap);
        final stride = pdfiumBindings.FPDFBitmap_GetStride(bitmap);
        final rawBytes = buffer.cast<ffi.Uint8>().asTypedList(stride * height);

        final u32list = rawBytes.buffer.asUint32List();
        for (int i = 0; i < u32list.length; i++) {
          final u32 = u32list[i];
          u32list[i] =
              (u32 & 0xFF00FF00) |
              ((u32 & 0x00FF0000) >> 16) |
              ((u32 & 0x000000FF) << 16);
        }

        replyPort.send({
          'success': true,
          'data': Uint8List.fromList(rawBytes),
          'width': width,
          'height': height,
        });

        pdfiumBindings.FPDFBitmap_Destroy(bitmap);
        pdfiumBindings.FPDF_ClosePage(page);
      }
    });
  }
}
