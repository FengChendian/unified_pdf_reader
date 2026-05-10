import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../constants/app_colors.dart';

class DocumentTab extends HookWidget {
  final String fileName;
  final bool isActive;
  final bool showRightDivider;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const DocumentTab({
    super.key,
    required this.fileName,
    required this.isActive,
    this.showRightDivider = false,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isHovered = useState(false);

    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.only(left: 12, right: 10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white
                        : (isHovered.value
                              ? Color.lerp(
                                  Colors.blue[50]!,
                                  Colors.grey[400]!,
                                  0.3,
                                )
                              : Colors.blue[50]),
                    border: Border(
                      bottom: BorderSide(
                        color: isActive ? accentBlue : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.picture_as_pdf,
                        size: 14,
                        color: isActive ? accentBlue : textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isActive ? accentBlue : textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // const SizedBox(width: 8),
                      isHovered.value
                          ? Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onClose,
                                borderRadius: BorderRadius.circular(2),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: textSecondary,
                                ),
                              ),
                            )
                          : const SizedBox(width: 14, height: 14),
                    ],
                  ),
                ),
              ),
            ),
            if (showRightDivider)
              Container(
                width: 1,
                height: 20,
                color: const Color.fromARGB(255, 209, 214, 221),
              ),
          ],
        ),
      ),
    );
  }
}
