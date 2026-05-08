import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../constants/app_colors.dart';

class SidebarButton extends HookWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onTap;

  const SidebarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isHovered = useState(false);

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => isHovered.value = true,
        onExit: (_) => isHovered.value = false,
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive
                  ? accentBlueLight
                  : isHovered.value
                  ? const Color(0xFFF1F5F9)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isActive
                  ? accentBlue
                  : isHovered.value
                  ? const Color(0xFF475569)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}
