import 'dart:async';
import 'dart:math' as math;

/// Calls [onTick] at a steady rate. Each tick is timed from the start (not from the previous tick),
/// so small delays never add up into drift - the same approach as Scales Academy's Metronome.
/// Records how late each tick fired, to check timing on each device.
class TempoClock {
  final _stopwatch = Stopwatch();
  Timer? _timer;
  void Function(int tick)? _onTick;
  int _tickMicros = 0;
  int _nextTick = 0;

  // Timing statistics (ticks after the first)
  int _measured = 0;
  double _totalLateMs = 0;
  double _worstLateMs = 0;

  bool get isRunning => _onTick != null;
  double get averageLateMs => _measured == 0 ? 0 : _totalLateMs / _measured;
  double get worstLateMs => _worstLateMs;
  int get ticksMeasured => _measured;

  void start(Duration tickLength, void Function(int tick) onTick) {
    stop();
    _tickMicros = tickLength.inMicroseconds;
    _onTick = onTick;
    _nextTick = 0;
    _measured = 0;
    _totalLateMs = 0;
    _worstLateMs = 0;
    _stopwatch
      ..reset()
      ..start();
    _fire();
  }

  void _fire() {
    final callback = _onTick;
    if (callback == null) return;
    final tick = _nextTick++;
    if (tick > 0) {
      final lateMs = (_stopwatch.elapsedMicroseconds - tick * _tickMicros) / 1000.0;
      _measured++;
      _totalLateMs += lateMs;
      _worstLateMs = math.max(_worstLateMs, lateMs);
    }
    callback(tick);
    if (_onTick == null) return; // stopped during the tick
    final waitMicros = _nextTick * _tickMicros - _stopwatch.elapsedMicroseconds;
    _timer = Timer(Duration(microseconds: math.max(0, waitMicros)), _fire);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _onTick = null;
    _stopwatch.stop();
  }
}
