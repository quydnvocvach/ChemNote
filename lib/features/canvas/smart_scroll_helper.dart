import 'dart:math' as math;
import 'dart:ui' show Offset;

enum SmartScrollAxis { none, vertical, free }

typedef _MoveSample = ({int timeUs, double dx, double dy});

/// Stateless/reusable tracker for Smart Vertical Scroll (`dy >= 1.2 * dx`),
/// progressive acceleration, and ballistic fling velocity estimation without
/// 0-seeded EMA underestimation on quick flicks.
class SmartScrollTracker {
  static const double verticalLockRatio = 1.2;
  static const double activateDistancePx = 2.5;
  static const double axisLockDistancePx = 5.0;
  static const int velocityWindowUs = 110000;
  static const int flingStaleThresholdUs = 150000;
  static const double flingLaunchMinSpeed = 110.0;
  static const int _maxSamples = 12;

  SmartScrollAxis _axisLock = SmartScrollAxis.none;
  Offset _accumDelta = Offset.zero;
  bool _activated = false;
  int _downTimeUs = 0;
  int _lastSampleTimeUs = 0;
  double _lastVx = 0.0;
  double _lastVy = 0.0;
  final List<_MoveSample> _samples = <_MoveSample>[];

  SmartScrollAxis get axisLock => _axisLock;
  Offset get accumDelta => _accumDelta;
  bool get isActivated => _activated;

  void reset() {
    _axisLock = SmartScrollAxis.none;
    _accumDelta = Offset.zero;
    _activated = false;
    _downTimeUs = 0;
    _lastSampleTimeUs = 0;
    _lastVx = 0.0;
    _lastVy = 0.0;
    _samples.clear();
  }

  void start(int timeUs) {
    reset();
    _downTimeUs = timeUs > 0 ? timeUs : 0;
    _lastSampleTimeUs = _downTimeUs;
  }

  ({
    bool active,
    double dx,
    double dy,
    double vx,
    double vy,
    double accelBoost,
  }) addMove({
    required Offset delta,
    required int timeUs,
    required double scrollMult,
    required bool canPanHorizontal,
    required bool requireActivationThreshold,
  }) {
    _accumDelta += delta;
    bool justActivated = false;
    if (requireActivationThreshold && !_activated) {
      if (_accumDelta.distance < activateDistancePx) {
        return const (
          active: false,
          dx: 0.0,
          dy: 0.0,
          vx: 0.0,
          vy: 0.0,
          accelBoost: 1.0,
        );
      }
      _activated = true;
      justActivated = true;
    }

    final Offset effectiveDelta = justActivated ? _accumDelta : delta;

    if (_axisLock == SmartScrollAxis.none &&
        _accumDelta.distance >= axisLockDistancePx) {
      _axisLock =
          _accumDelta.dy.abs() >= _accumDelta.dx.abs() * verticalLockRatio
              ? SmartScrollAxis.vertical
              : SmartScrollAxis.free;
    }

    // Use cumulative displacement before lock settles so early frames don't
    // leak horizontal jitter on vertical swipes.
    final bool lockHorizontal = _axisLock == SmartScrollAxis.vertical ||
        (_axisLock == SmartScrollAxis.none &&
            _accumDelta.dy.abs() >= _accumDelta.dx.abs() * verticalLockRatio);

    final double rawDx = lockHorizontal
        ? 0.0
        : (canPanHorizontal ? effectiveDelta.dx : 0.0);

    final int effectiveTimeUs = timeUs > 0
        ? (timeUs > _lastSampleTimeUs ? timeUs : _lastSampleTimeUs + 8000)
        : (_lastSampleTimeUs > 0 ? _lastSampleTimeUs + 8000 : 8000);

    final int prevTimeUs =
        _lastSampleTimeUs > 0 ? _lastSampleTimeUs : _downTimeUs;
    _lastSampleTimeUs = effectiveTimeUs;

    _samples.add((timeUs: effectiveTimeUs, dx: rawDx, dy: effectiveDelta.dy));
    if (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
    final int cutoffUs = effectiveTimeUs - velocityWindowUs;
    while (_samples.length > 2 && _samples.first.timeUs < cutoffUs) {
      _samples.removeAt(0);
    }

    final vel = _estimateVelocity(
      samples: _samples,
      anchorTimeUs: _downTimeUs,
      prevTimeUs: prevTimeUs,
      newestTimeUs: effectiveTimeUs,
      instDx: rawDx,
      instDy: effectiveDelta.dy,
    );
    _lastVx = lockHorizontal ? 0.0 : vel.vx;
    _lastVy = vel.vy;

    final double speedY = _lastVy.abs();
    final double t = ((speedY - 360.0) / 2400.0).clamp(0.0, 1.0).toDouble();
    final double accelBoost = 1.0 + (t * t) * 2.6;
    final double outDy = effectiveDelta.dy * scrollMult * accelBoost;

    return (
      active: true,
      dx: rawDx,
      dy: outDy,
      vx: _lastVx,
      vy: _lastVy,
      accelBoost: accelBoost,
    );
  }

  ({bool shouldFling, double vx, double vy}) computeFlingLaunch({
    required int upTimeUs,
    required double scrollMult,
  }) {
    if (_accumDelta.distance < 8.0 || _samples.isEmpty) {
      return const (shouldFling: false, vx: 0.0, vy: 0.0);
    }
    if (upTimeUs > 0 &&
        _lastSampleTimeUs > 0 &&
        (upTimeUs - _lastSampleTimeUs) > flingStaleThresholdUs) {
      return const (shouldFling: false, vx: 0.0, vy: 0.0);
    }

    // Ignore a single tiny trailing deceleration/micro-jitter sample (< 0.5 px)
    // right before fingertip lift-off so fast flicks never lose inertia.
    int endIndex = _samples.length;
    if (endIndex >= 2) {
      final last = _samples[endIndex - 1];
      final prev = _samples[endIndex - 2];
      final double lastDistSq = last.dx * last.dx + last.dy * last.dy;
      final int tailDtUs = last.timeUs - prev.timeUs;
      if (lastDistSq < 0.25 && tailDtUs <= 14000) {
        endIndex--;
      }
    }

    final int newestUs = _samples[endIndex - 1].timeUs;
    final int cutoffUs = newestUs - velocityWindowUs;
    int startIndex = 0;
    while (startIndex < endIndex - 1 && _samples[startIndex].timeUs < cutoffUs) {
      startIndex++;
    }

    double sumDx = 0.0;
    double sumDy = 0.0;
    for (int i = startIndex; i < endIndex; i++) {
      sumDx += _samples[i].dx;
      sumDy += _samples[i].dy;
    }

    final int anchorUs = startIndex > 0
        ? _samples[startIndex - 1].timeUs
        : (_downTimeUs > 0 && _downTimeUs < _samples[startIndex].timeUs
            ? _downTimeUs
            : math.max(0, _samples[startIndex].timeUs - 8000));
    final double windowDt =
        ((newestUs - anchorUs) / 1e6).clamp(0.006, 0.14).toDouble();

    final double windowVx = sumDx / windowDt;
    final double windowVy = sumDy / windowDt;
    final double estVx = _lastVx == 0.0
        ? windowVx
        : (windowVx * 0.72 + _lastVx * 0.28);
    final double estVy = _lastVy == 0.0
        ? windowVy
        : (windowVy * 0.72 + _lastVy * 0.28);

    final double speedY = estVy.abs();
    final double t = ((speedY - 360.0) / 2400.0).clamp(0.0, 1.0).toDouble();
    final double accelBoost = 1.0 + (t * t) * 2.6;

    final double launchVy = (estVy * scrollMult * (0.98 + accelBoost * 0.58))
        .clamp(-28000.0, 28000.0)
        .toDouble();
    final double launchVx = _axisLock == SmartScrollAxis.vertical
        ? 0.0
        : (estVx * 0.85).clamp(-6000.0, 6000.0).toDouble();

    final bool shouldFling = launchVy.abs() >= flingLaunchMinSpeed ||
        launchVx.abs() >= flingLaunchMinSpeed;
    return (
      shouldFling: shouldFling,
      vx: launchVx,
      vy: launchVy,
    );
  }

  static ({double vx, double vy}) _estimateVelocity({
    required List<_MoveSample> samples,
    required int anchorTimeUs,
    required int prevTimeUs,
    required int newestTimeUs,
    required double instDx,
    required double instDy,
  }) {
    double sumDx = 0.0;
    double sumDy = 0.0;
    for (final s in samples) {
      sumDx += s.dx;
      sumDy += s.dy;
    }

    final int spanStartUs = (anchorTimeUs > 0 && anchorTimeUs < samples.first.timeUs)
        ? anchorTimeUs
        : (samples.length >= 2
            ? samples.first.timeUs
            : math.max(0, newestTimeUs - 8000));
    final double windowDt =
        ((newestTimeUs - spanStartUs) / 1e6).clamp(0.006, 0.14).toDouble();
    final double windowVx = sumDx / windowDt;
    final double windowVy = sumDy / windowDt;

    final double instDt = prevTimeUs > 0 && newestTimeUs > prevTimeUs
        ? ((newestTimeUs - prevTimeUs) / 1e6).clamp(0.003, 0.08).toDouble()
        : windowDt;
    final double instVx = instDx / instDt;
    final double instVy = instDy / instDt;

    return (
      vx: windowVx * 0.65 + instVx * 0.35,
      vy: windowVy * 0.65 + instVy * 0.35,
    );
  }
}

/// Identifies zombie pointer IDs left behind by OS interruptions, shade pulls,
/// edge-back gestures, or overlay teardowns.
class StalePointerReconciler {
  static List<int> findStalePointers(
    Map<int, int> lastSeenMs,
    int nowMs, {
    int maxIdleMs = 4500,
    int? excludePointer,
  }) {
    if (lastSeenMs.isEmpty) return const [];
    final stale = <int>[];
    lastSeenMs.forEach((pointer, seenAtMs) {
      if (excludePointer != null && pointer == excludePointer) return;
      if ((nowMs - seenAtMs) >= maxIdleMs) {
        stale.add(pointer);
      }
    });
    return stale;
  }
}
