import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../constants/app_colors.dart';
import '../constants/mock_data.dart';
import '../providers/pdf_reader_provider.dart';

class HistoryDocumentCard extends HookWidget {
  final PdfReaderNotifier notifier;
  final HistoryItem doc;

  const HistoryDocumentCard({super.key, required this.notifier, required this.doc});

  @override
  Widget build(BuildContext context) {
    final isHovered = useState(false);

    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        onTap: () async =>
            await notifier.pickPdf(View.of(context).devicePixelRatio),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 260,
          height: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHovered.value
                  ? const Color(0xFF93C5FD)
                  :  Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: accentBlue.withAlpha(20),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.picture_as_pdf,
                        size: 48,
                        color: const Color(0xFFE2E8F0),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'PDF',
                          style: TextStyle(
                            color: white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                doc.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    doc.size,
                    style: const TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  Text(
                    doc.date,
                    style: const TextStyle(fontSize: 12, color: textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
