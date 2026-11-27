import 'dart:math' as math;
import 'dart:ui';

/// Un-rotates a delta expressed in page coordinates into image-local coordinates.
Offset rotatePageDeltaToLocal(Offset pageDelta, double rotation) {
  if (rotation == 0.0) return pageDelta;
  final double cosR = math.cos(-rotation);
  final double sinR = math.sin(-rotation);
  return Offset(
    pageDelta.dx * cosR - pageDelta.dy * sinR,
    pageDelta.dx * sinR + pageDelta.dy * cosR,
  );
}

/// Computes Huawei Notes-style center-anchored uniform corner scaling.
///
/// The image's center `(startX + startW * 0.5, startY + startH * 0.5)` stays
/// fixed while the corner expands/contracts symmetrically, tracking the
/// pointer 1:1 along the corner's outward diagonal ray.
({double x, double y, double width, double height})
    computeCenterAnchoredCornerScale({
  required double startX,
  required double startY,
  required double startW,
  required double startH,
  required double pageDx,
  required double pageDy,
  required double signX,
  required double signY,
  double rotation = 0.0,
  double minSize = 32.0,
}) {
  final double cx = startX + startW * 0.5;
  final double cy = startY + startH * 0.5;
  final Offset localDelta =
      rotatePageDeltaToLocal(Offset(pageDx, pageDy), rotation);
  final double diagLen = math.max(
    1.0,
    math.sqrt(startW * startW + startH * startH),
  );
  final double halfDiag = diagLen * 0.5;
  final double dirX = signX * (startW / diagLen);
  final double dirY = signY * (startH / diagLen);
  final double proj = localDelta.dx * dirX + localDelta.dy * dirY;
  final double minScale = math.max(
    minSize / math.max(1.0, startW),
    minSize / math.max(1.0, startH),
  );
  final double scaleFactor = math.max(minScale, (halfDiag + proj) / halfDiag);
  final double nw = startW * scaleFactor;
  final double nh = startH * scaleFactor;
  return (
    x: cx - nw * 0.5,
    y: cy - nh * 0.5,
    width: nw,
    height: nh,
  );
}
