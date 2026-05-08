import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../constants/app_colors.dart';
import '../providers/pdf_reader_provider.dart';

class NewDocumentCard extends HookWidget {
  final WorkspaceNotifier notifier;

  const NewDocumentCard({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final isHovered = useState(false);

    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async =>
            await notifier.openPdf(View.of(context).devicePixelRatio),
        
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 260,
          height: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHovered.value ? const Color(0xFF93C5FD) : Colors.white,
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
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accentBlueLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, size: 32, color: accentBlue),
                ),
              ),
              SizedBox(height: 14),
              Text(
                '打开新文档',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 6),
              Text(
                '点击选择 PDF 文件',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
