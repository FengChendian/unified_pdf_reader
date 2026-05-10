// FFI 绑定文件：字段名和函数名必须与 C 层保持一致，不使用 lowerCamelCase
// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// ==========================================
// 1. FFI 数据结构定义
// ==========================================

/// 不透明句柄：MuPdfContext
final class MuPdfContextOpaque extends Opaque {}

/// 不透明句柄：MuPdfDocument
final class MuPdfDocumentOpaque extends Opaque {}

/// 渲染结果结构体映射
final class MuPdfImage extends Struct {
  @Int32()
  external int width;

  @Int32()
  external int height;

  @Int32()
  external int stride;

  @Int32()
  external int components;

  external Pointer<Uint8> buffer;
}

/// 目录 JSON 结果结构体映射
final class MuPdfOutlineJson extends Struct {
  external Pointer<Utf8> json;

  @Int32()
  external int length;
}

/// 矩形结构体映射
final class MuPdfRect extends Struct {
  @Float()
  external double x0;

  @Float()
  external double y0;

  @Float()
  external double x1;

  @Float()
  external double y1;
}

/// 单个字符结构体映射
final class MuPdfTextChar extends Struct {
  external MuPdfRect bbox;

  @Array(5)
  external Array<Uint8> utf8;
}

/// 文本行结构体映射
final class MuPdfTextLine extends Struct {
  external MuPdfRect bbox;

  @Int32()
  external int chars_count;

  external Pointer<MuPdfTextChar> chars;

  external Pointer<Utf8> text;
}

/// 文本块结构体映射
final class MuPdfTextBlock extends Struct {
  external MuPdfRect bbox;

  @Int32()
  external int lines_count;

  external Pointer<MuPdfTextLine> lines;
}

/// 结构化文本页结构体映射
final class MuPdfTextPage extends Struct {
  @Int32()
  external int blocks_count;

  external Pointer<MuPdfTextBlock> blocks;
}

// ==========================================
// 2. DLL 加载与 API 绑定类
// ==========================================

/// 负责加载 DLL 并映射所有 MUPDF API，避免全局变量。
class MuPdfLibrary {
  late final DynamicLibrary _dylib;

  // --- API 函数指针 ---
  late final Pointer<MuPdfContextOpaque> Function() ctxCreate;
  late final Pointer<MuPdfDocumentOpaque> Function(
    Pointer<MuPdfContextOpaque>,
    Pointer<Utf8>,
  )
  docOpen;
  late final int Function(
    Pointer<MuPdfContextOpaque>,
    Pointer<MuPdfDocumentOpaque>,
  )
  docPageCount;
  late final Pointer<MuPdfImage> Function(
    Pointer<MuPdfContextOpaque>,
    Pointer<MuPdfDocumentOpaque>,
    int,
    double,
    double,
    int,
  )
  pageRender;
  late final void Function(
    Pointer<MuPdfContextOpaque>,
    Pointer<MuPdfDocumentOpaque>,
  )
  docClose;
  late final void Function(Pointer<MuPdfContextOpaque>) ctxDestroy;
  late final void Function(Pointer<MuPdfImage>) imageFree;
  late final Pointer<Utf8> Function(Pointer<MuPdfContextOpaque>) lastError;
  late final Pointer<MuPdfOutlineJson> Function(
    Pointer<MuPdfContextOpaque>,
    Pointer<MuPdfDocumentOpaque>,
  )
  docGetOutline;
  late final void Function(Pointer<MuPdfOutlineJson>) outlineFree;
  late final Pointer<MuPdfTextPage> Function(
    Pointer<MuPdfContextOpaque>,
    Pointer<MuPdfDocumentOpaque>,
    int,
  )
  pageGetStext;
  late final void Function(Pointer<MuPdfTextPage>) stextPageFree;

  /// 初始化并加载 DLL。默认从当前 exe 所在根目录加载
  MuPdfLibrary({String dllName = 'mupdf.dll'}) {
    // 获取 flutter 生成的 exe 所在的真实路径
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final dllPath = p.join(exeDir, dllName);

    _dylib = DynamicLibrary.open(dllPath);

    // 绑定所有的 API 函数[cite: 2]
    ctxCreate = _dylib
        .lookupFunction<
          Pointer<MuPdfContextOpaque> Function(),
          Pointer<MuPdfContextOpaque> Function()
        >('mupdf_ctx_create');

    docOpen = _dylib
        .lookupFunction<
          Pointer<MuPdfDocumentOpaque> Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<Utf8>,
          ),
          Pointer<MuPdfDocumentOpaque> Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<Utf8>,
          )
        >('mupdf_doc_open');

    docPageCount = _dylib
        .lookupFunction<
          Int32 Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
          ),
          int Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
          )
        >('mupdf_doc_page_count');

    pageRender = _dylib
        .lookupFunction<
          Pointer<MuPdfImage> Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
            Int32,
            Float,
            Float,
            Int32,
          ),
          Pointer<MuPdfImage> Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
            int,
            double,
            double,
            int,
          )
        >('mupdf_page_render');

    docClose = _dylib
        .lookupFunction<
          Void Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
          ),
          void Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
          )
        >('mupdf_doc_close');

    ctxDestroy = _dylib
        .lookupFunction<
          Void Function(Pointer<MuPdfContextOpaque>),
          void Function(Pointer<MuPdfContextOpaque>)
        >('mupdf_ctx_destroy');

    imageFree = _dylib
        .lookupFunction<
          Void Function(Pointer<MuPdfImage>),
          void Function(Pointer<MuPdfImage>)
        >('mupdf_image_free');

    lastError = _dylib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<MuPdfContextOpaque>),
          Pointer<Utf8> Function(Pointer<MuPdfContextOpaque>)
        >('mupdf_last_error');

    docGetOutline = _dylib
        .lookupFunction<
          Pointer<MuPdfOutlineJson> Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
          ),
          Pointer<MuPdfOutlineJson> Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
          )
        >('mupdf_doc_get_outline');

    outlineFree = _dylib
        .lookupFunction<
          Void Function(Pointer<MuPdfOutlineJson>),
          void Function(Pointer<MuPdfOutlineJson>)
        >('mupdf_outline_free');

    pageGetStext = _dylib
        .lookupFunction<
          Pointer<MuPdfTextPage> Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
            Int32,
          ),
          Pointer<MuPdfTextPage> Function(
            Pointer<MuPdfContextOpaque>,
            Pointer<MuPdfDocumentOpaque>,
            int,
          )
        >('mupdf_page_get_stext');

    stextPageFree = _dylib
        .lookupFunction<
          Void Function(Pointer<MuPdfTextPage>),
          void Function(Pointer<MuPdfTextPage>)
        >('mupdf_stext_page_free');
  }
}

// ==========================================
// 3. 高层多实例 PDF 文档管理类
// ==========================================

/// Dart 层渲染结果的载体，摆脱 C 内存生命周期约束
class RenderedPage {
  final int width;
  final int height;
  final int stride;
  final int components;
  final Uint8List pixels; // 复制到 Dart 层的像素数据

  RenderedPage({
    required this.width,
    required this.height,
    required this.stride,
    required this.components,
    required this.pixels,
  });
}

/// PDF 目录项（大纲项）数据结构
class OutlineItem {
  final String title;
  final String uri;
  final int page;      // 页码 (-1 表示外部链接或无目标)
  final bool isOpen;   // 是否展开
  final int flags;     // 1=粗体，2=斜体
  final List<OutlineItem> children;

  bool get isBold => (flags & 1) != 0;
  bool get isItalic => (flags & 2) != 0;

  OutlineItem({
    required this.title,
    required this.uri,
    required this.page,
    required this.isOpen,
    required this.flags,
    required this.children,
  });

  /// 从 JSON 解析内部方法
  static OutlineItem _parse(Map json) {
    return OutlineItem(
      title: json['title'] as String? ?? '',
      uri: json['uri'] as String? ?? '',
      page: json['page'] as int? ?? -1,
      isOpen: json['isOpen'] as bool? ?? false,
      flags: json['flags'] as int? ?? 0,
      children: (json['children'] as List?)
              ?.map((c) => _parse(c as Map))
              .toList() ??
          [],
    );
  }

  /// 从 JSON 对象创建 OutlineItem
  factory OutlineItem.fromJson(Map<String, dynamic> json) => _parse(json);
}

/// 矩形
class PdfRect {
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  const PdfRect({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });
}

/// 单个字符
class TextChar {
  final PdfRect bbox;
  final String character;

  const TextChar({required this.bbox, required this.character});
}

/// 文本行
class TextLine {
  final PdfRect bbox;
  final String text;
  final List<TextChar> chars;

  const TextLine({
    required this.bbox,
    required this.text,
    required this.chars,
  });
}

/// 文本块
class TextBlock {
  final PdfRect bbox;
  final List<TextLine> lines;

  const TextBlock({required this.bbox, required this.lines});
}

/// 结构化文本页
class StructuredTextPage {
  final List<TextBlock> blocks;

  const StructuredTextPage({required this.blocks});
}

/// 独立的 PDF 文档实例，支持多文档同时操作
class PdfDocument {
  final MuPdfLibrary _lib;

  // 维护独立的 ctx 和 doc，实现完美分离[cite: 1]
  Pointer<MuPdfContextOpaque> _ctx = nullptr;
  Pointer<MuPdfDocumentOpaque> _doc = nullptr;

  bool get isOpen => _doc != nullptr;

  PdfDocument({MuPdfLibrary? lib}) : _lib = lib ?? MuPdfLibrary() {
    // 每个文档创建自己独立的上下文[cite: 1]
    _ctx = _lib.ctxCreate();
    if (_ctx == nullptr) {
      throw Exception("Failed to create MuPDF context.");
    }
  }

  /// 抛出当前上下文的错误信息
  void _throwLastError(String prefix) {
    final errorPtr = _lib.lastError(_ctx);
    final errorMsg = errorPtr != nullptr
        ? errorPtr.toDartString()
        : "Unknown error";
    throw Exception("$prefix: $errorMsg");
  }

  /// 打开文档
  void open(String filepath) {
    if (isOpen) {
      throw Exception("Document is already open. Close it first.");
    }

    final pathPtr = filepath.toNativeUtf8();
    try {
      _doc = _lib.docOpen(_ctx, pathPtr);
      if (_doc == nullptr) {
        _throwLastError("Failed to open document");
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 获取文档总页数
  int get pageCount {
    if (!isOpen) return 0;

    final count = _lib.docPageCount(_ctx, _doc);
    if (count < 0) {
      _throwLastError("Failed to get page count");
    }
    return count;
  }

  /// 获取文档目录（大纲/TOC）
  /// 返回 OutlineItem 列表，支持嵌套子项
  List<OutlineItem> getOutline() {
    if (!isOpen) throw Exception("Document is not open.");

    final outlinePtr = _lib.docGetOutline(_ctx, _doc);
    if (outlinePtr == nullptr) {
      _throwLastError("Failed to get outline");
    }

    try {
      final outline = outlinePtr.ref;

      // 获取 JSON 字符串
      final jsonString = outline.json.toDartString();

      // 解析 JSON 为 List<OutlineItem>
      final parsed = jsonDecode(jsonString) as List;
      return parsed.map((e) => OutlineItem._parse(e as Map)).toList();
    } finally {
      // 释放 C 层的 outline 结构
      _lib.outlineFree(outlinePtr);
    }
  }

  /// 提取页面结构化文本
  /// 返回 StructuredTextPage，包含文本块、行和字符信息
  StructuredTextPage getStructuredText(int pageNumber) {
    if (!isOpen) throw Exception("Document is not open.");

    final textPagePtr = _lib.pageGetStext(_ctx, _doc, pageNumber);
    if (textPagePtr == nullptr) {
      _throwLastError("Failed to extract text from page $pageNumber");
    }

    try {
      final tp = textPagePtr.ref;
      final blocks = <TextBlock>[];

      for (int bi = 0; bi < tp.blocks_count; bi++) {
        final cBlock = (tp.blocks + bi).ref;
        final lines = <TextLine>[];

        for (int li = 0; li < cBlock.lines_count; li++) {
          final cLine = (cBlock.lines + li).ref;
          final chars = <TextChar>[];

          for (int ci = 0; ci < cLine.chars_count; ci++) {
            final cChar = (cLine.chars + ci).ref;
            final bytes = <int>[];
            for (int i = 0; i < 5; i++) {
              final byte = cChar.utf8[i];
              if (byte == 0) break;
              bytes.add(byte);
            }
            chars.add(TextChar(
              bbox: PdfRect(
                x0: cChar.bbox.x0,
                y0: cChar.bbox.y0,
                x1: cChar.bbox.x1,
                y1: cChar.bbox.y1,
              ),
              character: utf8.decode(bytes),
            ));
          }

          lines.add(TextLine(
            bbox: PdfRect(
              x0: cLine.bbox.x0,
              y0: cLine.bbox.y0,
              x1: cLine.bbox.x1,
              y1: cLine.bbox.y1,
            ),
            text: cLine.text.toDartString(),
            chars: chars,
          ));
        }

        blocks.add(TextBlock(
          bbox: PdfRect(
            x0: cBlock.bbox.x0,
            y0: cBlock.bbox.y0,
            x1: cBlock.bbox.x1,
            y1: cBlock.bbox.y1,
          ),
          lines: lines,
        ));
      }

      return StructuredTextPage(blocks: blocks);
    } finally {
      _lib.stextPageFree(textPagePtr);
    }
  }

  /// 渲染指定页面并获取独立的图像数据
  RenderedPage renderPage({
    required int pageNumber,
    double zoom = 100.0,
    double rotate = 0.0,
    bool includeAlpha = false,
  }) {
    if (!isOpen) throw Exception("Document is not open.");

    final imagePtr = _lib.pageRender(
      _ctx,
      _doc,
      pageNumber,
      zoom,
      rotate,
      includeAlpha ? 1 : 0,
    );

    if (imagePtr == nullptr) {
      _throwLastError("Failed to render page $pageNumber");
    }

    try {
      final img = imagePtr.ref;

      // MuPDF 输出 BGRA 格式，需要转换为 RGBA 格式供 Flutter 使用
      final width = img.width;
      final height = img.height;
      final stride = img.stride;
      final components = img.components;

      // 计算每行实际字节数和总字节数
      final bytesPerPixel = components; // 通常是 3 (BGR) 或 4 (BGRA)
      final dataSize = stride * height;

      // 分配 RGBA 输出 buffer（确保每行 4 字节对齐）
      final outputStride = width * 4;
      final outputSize = outputStride * height;
      final rgbaPixels = Uint8List(outputSize);

      // 访问 C 层原始数据
      final cPixels = img.buffer.asTypedList(dataSize);

      // RGB/BGR to RGBA - direct copy
      final Uint32List rgbaUint32 = rgbaPixels.buffer.asUint32List();
      final int uint32OutputStride =
          outputStride >> 2; // 如果 outputStride 是字节数，则除以 4

      if (components == 4) {
        final Uint32List srcUint32 = cPixels.buffer.asUint32List();
        final int uint32SrcStride = stride >> 2;

        for (int y = 0; y < height; y++) {
          // 如果 stride 对齐，甚至可以用 setRange 批量拷贝
          rgbaUint32.setRange(
            y * uint32OutputStride,
            y * uint32OutputStride + width,
            srcUint32,
            y * uint32SrcStride,
          );
        }
      } else {
        // RGB 情况：手动拼装 32 位整数 (假设小端序 ABGR)
        for (int y = 0; y < height; y++) {
          int srcRowBase = y * stride;
          int dstRowBase = y * uint32OutputStride;
          for (int x = 0; x < width; x++) {
            final int src = srcRowBase + x * bytesPerPixel;
            // 拼装 0xFF (Alpha) + R + G + B
            rgbaUint32[dstRowBase + x] =
                0xFF000000 |
                (cPixels[src + 2] << 16) |
                (cPixels[src + 1] << 8) |
                cPixels[src];
          }
        }
      }

      return RenderedPage(
        width: width,
        height: height,
        stride: outputStride,
        components: 4, // 现在是 RGBA
        pixels: rgbaPixels,
      );
    } finally {
      // 释放 C 层的 MuPdfImage 和其内部的独立 buffer[cite: 1]
      _lib.imageFree(imagePtr);
    }
  }

  /// 关闭文档并清理释放 C 层资源
  void dispose() {
    if (_doc != nullptr) {
      _lib.docClose(_ctx, _doc); // 关闭文档资源[cite: 1]
      _doc = nullptr;
    }

    if (_ctx != nullptr) {
      _lib.ctxDestroy(_ctx); // 销毁独立上下文[cite: 1]
      _ctx = nullptr;
    }
  }
}
