// Shared long-press picker used by feed and group post reactions.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/social_reaction.dart';

class SocialReactionPicker {
  SocialReactionPicker._();

  static const _itemSize = 40.0;
  static const _horizontalPadding = 8.0;
  static const _height = 54.0;
  static const _gap = 8.0;

  /// Opens the reaction palette above the pressed control and returns the
  /// selected reaction ID, or null when the user dismisses it.
  static Future<String?> show(BuildContext anchorContext) {
    final overlay = Overlay.of(anchorContext);
    final overlayObject = overlay.context.findRenderObject();
    final anchorObject = anchorContext.findRenderObject();
    if (overlayObject is! RenderBox || anchorObject is! RenderBox) {
      return Future<String?>.value();
    }

    final overlayOrigin = overlayObject.localToGlobal(Offset.zero);
    final anchorOrigin = anchorObject.localToGlobal(Offset.zero);
    final anchorRect = Rect.fromLTWH(
      anchorOrigin.dx - overlayOrigin.dx,
      anchorOrigin.dy - overlayOrigin.dy,
      anchorObject.size.width,
      anchorObject.size.height,
    );
    final options = SocialReaction.options
        .where((reaction) => reaction.id != 'dislike')
        .toList(growable: false);
    final overlaySize = overlayObject.size;
    final popupWidth = math.min(
      options.length * _itemSize + _horizontalPadding * 2,
      math.max(0.0, overlaySize.width - 16),
    );
    final desiredLeft = anchorRect.center.dx - popupWidth / 2;
    final maxLeft = math.max(8.0, overlaySize.width - popupWidth - 8.0);
    final left = desiredLeft.clamp(8.0, maxLeft).toDouble();
    final aboveTop = anchorRect.top - _height - _gap;
    final belowTop = anchorRect.bottom + _gap;
    final top = aboveTop >= 8
        ? aboveTop
        : belowTop
              .clamp(8.0, math.max(8.0, overlaySize.height - _height - 8.0))
              .toDouble();

    // A route owns the palette so Android Back, navigation and outside taps
    // all dismiss it and complete the returned future exactly once.
    return showGeneralDialog<String>(
      context: anchorContext,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(anchorContext)
          .modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (overlayContext, animation, secondaryAnimation) {
        final colors = Theme.of(overlayContext).colorScheme;
        return SizedBox.expand(
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(overlayContext).pop(),
                  ),
                ),
                Positioned(
                  left: left,
                  top: top,
                  width: popupWidth,
                  child: Material(
                    color: colors.surface,
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(28),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _horizontalPadding,
                        vertical: 7,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: options
                              .map((reaction) {
                                return Tooltip(
                                  message: reaction.label,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () =>
                                        Navigator.of(overlayContext)
                                            .pop(reaction.id),
                                    child: SizedBox(
                                      width: _itemSize,
                                      height: _itemSize,
                                      child: Center(
                                        child: Text(
                                          reaction.emoji,
                                          style: const TextStyle(fontSize: 27),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
