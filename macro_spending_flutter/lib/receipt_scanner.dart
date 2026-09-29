import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class ReceiptDraft {
  const ReceiptDraft(this.business, this.amount, this.rawText);
  final String business;
  final String? amount;
  final String rawText;
}

ReceiptDraft parseReceipt(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  String? amount;
  final totalLabel = RegExp(
    r'\b(grand\s+total|total|amount\s+due|payment\s+amount)\b',
    caseSensitive: false,
  );
  final excluded = RegExp(
    r'\b(sub\s*total|tax|savings)\b',
    caseSensitive: false,
  );
  final price = RegExp(r'\d+(?:,\d{3})*\.\d{2}\b');
  for (var i = 0; i < lines.length; i++) {
    if (!totalLabel.hasMatch(lines[i]) || excluded.hasMatch(lines[i])) continue;
    final sameLine = price.allMatches(lines[i]).toList();
    final nextLine = i + 1 < lines.length
        ? price.allMatches(lines[i + 1]).toList()
        : <RegExpMatch>[];
    final matches = sameLine.isNotEmpty ? sameLine : nextLine;
    if (matches.isNotEmpty) amount = matches.last.group(0)!.replaceAll(',', '');
  }
  return ReceiptDraft(lines.isEmpty ? '' : lines.first, amount, text);
}

class ReceiptScanner {
  final ImagePicker _picker = ImagePicker();

  Future<ReceiptDraft?> capture(ImageSource source) async {
    final image = await _picker.pickImage(source: source, maxWidth: 2400);
    return image == null ? null : recognize(image.path);
  }

  Future<ReceiptDraft?> recover() async {
    final lost = await _picker.retrieveLostData();
    if (lost.exception != null) throw lost.exception!;
    final files = lost.files;
    return files == null || files.isEmpty ? null : recognize(files.first.path);
  }

  Future<ReceiptDraft> recognize(String path) async {
    final recognizer = TextRecognizer();
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      return parseReceipt(result.text);
    } finally {
      await recognizer.close();
    }
  }
}
