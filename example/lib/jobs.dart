import 'dart:convert';
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:image/image.dart' as img;

/// Byte builders for the example app: ESC/POS receipts, TSPL / ESC/POS labels,
/// barcode/QR rendering to 1-bit raster images.

enum CodeType { qr, code128, ean13 }

extension CodeTypeLabel on CodeType {
  String get label => switch (this) {
        CodeType.qr => 'QR',
        CodeType.code128 => 'Code128',
        CodeType.ean13 => 'EAN-13',
      };

  Barcode get barcode => switch (this) {
        CodeType.qr => Barcode.qrCode(),
        CodeType.code128 => Barcode.code128(),
        CodeType.ean13 => Barcode.ean13(),
      };
}

enum LabelLanguage { tspl, escpos }

/// Paper width for receipts.
class PaperWidth {
  const PaperWidth(this.name, this.dots, this.chars);
  final String name;
  final int dots;
  final int chars;

  static const mm58 = PaperWidth('58mm', 384, 32);
  static const mm80 = PaperWidth('80mm', 576, 48);
}

const int dotsPerMm = 8; // 203 dpi

final statusQueryEscPos = Uint8List.fromList([0x10, 0x04, 0x04]);
final statusQueryTspl = Uint8List.fromList([0x1B, 0x21, 0x3F]);

/// Latin-1 safe encoding (unknown chars become '?').
List<int> _text(String s) =>
    s.codeUnits.map((c) => c < 256 ? c : 0x3F).toList(growable: false);

// ---------------------------------------------------------------------------
// ESC/POS primitives
// ---------------------------------------------------------------------------
class EscPos {
  final _b = BytesBuilder();

  Uint8List get bytes => _b.toBytes();

  EscPos init() => raw([0x1B, 0x40]);
  EscPos raw(List<int> b) {
    _b.add(b);
    return this;
  }

  EscPos align(int a) => raw([0x1B, 0x61, a]); // 0 left 1 centre 2 right
  EscPos bold(bool on) => raw([0x1B, 0x45, on ? 1 : 0]);
  EscPos size(int w, int h) => raw([0x1D, 0x21, ((w - 1) << 4) | (h - 1)]);
  EscPos text(String s) => raw(_text(s));
  EscPos line([String s = '']) => raw([..._text(s), 0x0A]);
  EscPos feed(int n) => raw([0x1B, 0x64, n]);
  EscPos cut() => raw([0x1D, 0x56, 0x42, 0x00]);

  /// GS v 0 raster image from packed 1-bit rows.
  EscPos raster(PackedImage p) {
    raw([
      0x1D, 0x76, 0x30, 0x00, //
      p.bytesPerRow & 0xFF, p.bytesPerRow >> 8,
      p.height & 0xFF, p.height >> 8,
    ]);
    return raw(p.data);
  }

  /// Native QR via GS ( k.
  EscPos qr(String data, {int module = 6}) {
    final d = utf8.encode(data);
    final len = d.length + 3;
    raw([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]); // model 2
    raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, module]); // module size
    raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]); // EC level M
    raw([0x1D, 0x28, 0x6B, len & 0xFF, len >> 8, 0x31, 0x50, 0x30, ...d]);
    return raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]); // print
  }

  /// Native 1D barcode via GS k (function B).
  EscPos barcode1d(CodeType type, String data) {
    raw([0x1D, 0x68, 80, 0x1D, 0x77, 2, 0x1D, 0x48, 2]); // h, w, HRI below
    if (type == CodeType.ean13) {
      final d = _text(data);
      return raw([0x1D, 0x6B, 67, d.length, ...d]);
    }
    final d = [0x7B, 0x42, ..._text(data)]; // {B code set B
    return raw([0x1D, 0x6B, 73, d.length, ...d]);
  }
}

// ---------------------------------------------------------------------------
// Image rendering
// ---------------------------------------------------------------------------
class PackedImage {
  PackedImage(this.bytesPerRow, this.height, this.data);
  final int bytesPerRow;
  final int height;
  final Uint8List data;
}

final _white = img.ColorRgb8(255, 255, 255);
final _black = img.ColorRgb8(0, 0, 0);

img.Image blankImage(int w, int h) =>
    img.fill(img.Image(width: w, height: h), color: _white);

/// Draws [type]/[data] into [canvas] at (x, y) sized w x h. Throws
/// [BarcodeException] on invalid data (e.g. bad EAN-13).
void drawCode(img.Image canvas, CodeType type, String data,
    {required int x, required int y, required int w, required int h}) {
  final elements = type.barcode
      .make(data, width: w.toDouble(), height: h.toDouble(), drawText: false);
  for (final e in elements) {
    if (e is BarcodeBar && e.black) {
      img.fillRect(canvas,
          x1: x + e.left.round(),
          y1: y + e.top.round(),
          x2: x + (e.left + e.width).round() - 1,
          y2: y + (e.top + e.height).round() - 1,
          color: _black);
    }
  }
}

/// Packs [image] to 1-bit rows, MSB first, 1 = black.
PackedImage packImage(img.Image image) {
  final bpr = (image.width + 7) ~/ 8;
  final out = Uint8List(bpr * image.height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).luminance < 128) {
        out[y * bpr + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return PackedImage(bpr, image.height, out);
}

/// Code rendered as a centred image [width] dots wide, with caption text.
img.Image codeImage(CodeType type, String data, int width) {
  final isQr = type == CodeType.qr;
  final cw = isQr ? (width * 0.6).round() : (width * 0.9).round();
  final ch = isQr ? cw : 120;
  final canvas = blankImage(width, ch + 40);
  drawCode(canvas, type, data, x: (width - cw) ~/ 2, y: 8, w: cw, h: ch);
  img.drawString(canvas, data,
      font: img.arial14, x: (width - cw) ~/ 2, y: ch + 16, color: _black);
  return canvas;
}

// ---------------------------------------------------------------------------
// Receipt jobs
// ---------------------------------------------------------------------------
Uint8List receiptTestPage(PaperWidth paper) {
  final ruler = List.generate(paper.chars, (i) => '${(i + 1) % 10}').join();
  return (EscPos()
        ..init()
        ..align(1)
        ..bold(true)
        ..size(2, 2)
        ..line('TEST PAGE')
        ..size(1, 1)
        ..bold(false)
        ..line('${paper.name} / ${paper.dots} dots / ${paper.chars} chars')
        ..align(0)
        ..line(ruler)
        ..line('Left aligned')
        ..align(1)
        ..line('Centre aligned')
        ..align(2)
        ..line('Right aligned')
        ..align(0)
        ..bold(true)
        ..line('Bold text')
        ..bold(false)
        ..size(2, 1)
        ..line('Double width')
        ..size(1, 2)
        ..line('Double height')
        ..size(2, 2)
        ..line('2x both')
        ..size(1, 1)
        ..line(ruler)
        ..feed(3)
        ..cut())
      .bytes;
}

Uint8List receiptCode(PaperWidth paper, CodeType type, String data,
    {required bool asImage}) {
  final p = EscPos()
    ..init()
    ..align(1);
  if (asImage) {
    p.raster(packImage(codeImage(type, data, paper.dots)));
  } else if (type == CodeType.qr) {
    p
      ..qr(data)
      ..line()
      ..line(data);
  } else {
    p.barcode1d(type, data);
  }
  return (p
        ..line()
        ..align(0)
        ..feed(3)
        ..cut())
      .bytes;
}

// ---------------------------------------------------------------------------
// Label jobs
// ---------------------------------------------------------------------------
class LabelSize {
  const LabelSize(this.width, this.height, this.gap);
  final double width; // mm
  final double height; // mm
  final double gap; // mm

  int get wDots => (width * dotsPerMm).round();
  int get hDots => (height * dotsPerMm).round();
}

const labelPresets = <(double, double)>[
  (25, 15),
  (38, 25),
  (40, 30),
  (50, 25),
  (50, 30),
  (75, 50),
  (100, 50),
];

String tsplEscape(String s) => s.replaceAll('"', r'\["]');

String _n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

String _tsplHeader(LabelSize s) =>
    'SIZE ${_n(s.width)} mm,${_n(s.height)} mm\r\n'
    'GAP ${_n(s.gap)} mm,0 mm\r\n'
    'DIRECTION 1\r\n'
    'CLS\r\n';

String _tsplCode(CodeType type, String data, int x, int y, int h) {
  final d = tsplEscape(data);
  return switch (type) {
    CodeType.qr => 'QRCODE $x,$y,M,4,A,0,"$d"\r\n',
    CodeType.code128 => 'BARCODE $x,$y,"128",$h,1,0,2,2,"$d"\r\n',
    CodeType.ean13 => 'BARCODE $x,$y,"EAN13",$h,1,0,2,2,"$d"\r\n',
  };
}

Uint8List _tsplBytes(String s) => Uint8List.fromList(_text(s));

Uint8List _escPosLabel(img.Image image) => (EscPos()
      ..init()
      ..raster(packImage(image))
      ..raw([0x1D, 0x0C]))
    .bytes;

Uint8List sampleLabel(LabelLanguage lang, LabelSize s, String data) {
  final m = 2 * dotsPerMm; // 2mm border inset
  if (lang == LabelLanguage.tspl) {
    final codeH = (s.hDots * 0.3).round().clamp(16, 200);
    return _tsplBytes('${_tsplHeader(s)}'
        'BOX $m,$m,${s.wDots - m},${s.hDots - m},2\r\n'
        'TEXT ${m + 8},${m + 8},"2",0,1,1,"${tsplEscape('Drago "Label"')}"\r\n'
        'TEXT ${m + 8},${m + 36},"1",0,1,1,"${_n(s.width)}x${_n(s.height)} mm"\r\n'
        '${_tsplCode(CodeType.code128, data, m + 8, s.hDots - m - codeH - 30, codeH)}'
        'PRINT 1,1\r\n');
  }
  final canvas = blankImage(s.wDots, s.hDots);
  img.drawRect(canvas,
      x1: m,
      y1: m,
      x2: s.wDots - m,
      y2: s.hDots - m,
      color: _black,
      thickness: 2);
  img.drawString(canvas, 'Drago Label',
      font: img.arial24, x: m + 8, y: m + 6, color: _black);
  img.drawString(canvas, '${_n(s.width)}x${_n(s.height)} mm',
      font: img.arial14, x: m + 8, y: m + 36, color: _black);
  final codeH = (s.hDots * 0.3).round();
  final top = s.hDots - m - codeH - 8;
  if (top > m + 56) {
    drawCode(canvas, CodeType.code128, data,
        x: m + 8, y: top, w: s.wDots - 2 * m - 16, h: codeH);
  }
  return _escPosLabel(canvas);
}

Uint8List codeLabel(
    LabelLanguage lang, LabelSize s, CodeType type, String data) {
  final m = 2 * dotsPerMm;
  if (lang == LabelLanguage.tspl) {
    final codeH = (s.hDots - 2 * m - 30).clamp(16, 400);
    return _tsplBytes('${_tsplHeader(s)}'
        '${_tsplCode(type, data, m, m, codeH)}'
        'PRINT 1,1\r\n');
  }
  final canvas = blankImage(s.wDots, s.hDots);
  final avail = s.hDots - 2 * m;
  final w = type == CodeType.qr ? avail : s.wDots - 2 * m;
  drawCode(canvas, type, data,
      x: (s.wDots - w) ~/ 2,
      y: m,
      w: w,
      h: type == CodeType.qr ? avail : avail - 20);
  if (type != CodeType.qr) {
    img.drawString(canvas, data,
        font: img.arial14, x: m, y: s.hDots - m - 16, color: _black);
  }
  return _escPosLabel(canvas);
}

Uint8List tsplCalibrate() => _tsplBytes('GAPDETECT\r\n');
Uint8List tsplSelfTest() => _tsplBytes('SELFTEST\r\n');
