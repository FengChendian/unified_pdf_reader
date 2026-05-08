import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/pdf_reader_provider.dart';

class PageIndicator extends HookConsumerWidget {
  const PageIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalPages = ref.watch(
      pdfReaderProvider.select((state) => state.totalPages),
    );
    final isPageIndicatorVisible = ref.watch(
      pdfReaderProvider.select((state) => state.isPageIndicatorVisible),
    );
    final displayedPage = ref.watch(
      pdfReaderProvider.select((state) => state.displayedPage),
    );
    return AnimatedOpacity(
      opacity: isPageIndicatorVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '$displayedPage / $totalPages',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
