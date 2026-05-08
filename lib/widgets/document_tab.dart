import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../constants/app_colors.dart';
import '../providers/pdf_reader_provider.dart';

class DocumentTab extends HookWidget {
  final String filePath;
  final PdfReaderNotifier notifier;

  const DocumentTab({super.key, required this.filePath, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final fileName = filePath.split('\\').last;
    final isHovered = useState(false);

    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 241, 245, 249),
              border: Border(
                bottom: BorderSide(color: accentBlue, width: 2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.picture_as_pdf, size: 14, color: accentBlue),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: accentBlue,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isHovered.value) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => notifier.closePdf(),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
