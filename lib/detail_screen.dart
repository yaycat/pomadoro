import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import 'app_styles.dart';

enum _Phase { idle, work, rest, done }

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _workCtrl = TextEditingController(text: '25');
  final _restCtrl = TextEditingController(text: '5');
  final _repeatCtrl = TextEditingController(text: '4');

  static const _metronomeAsset = 'lib/assets/metronome_60bpm.mp4';
  final _player = AudioPlayer();
  bool _isMuted = true;
  Timer? _timer;
  int _currentWorkTotalSeconds = 0;
  _Phase _phase = _Phase.idle;
  int _remainingSeconds = 0;
  int _currentCycle = 0;
  int _totalCycles = 0;

  bool get _isRunning => _timer != null;
  bool get _hideInputs => _phase != _Phase.idle;

  @override
  void initState() {
    super.initState();
    _player.audioCache = AudioCache(prefix: '');
  }

  Future<void> _startMetronomeFromBeginning() async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(
      AssetSource(_metronomeAsset),
      volume: _isMuted ? 0.0 : 1.0,
    );
  }

  Future<void> _syncMetronomePlayback() async {
    try {
      final inWork = _phase == _Phase.work;

      if (!inWork) {
        if (_player.state != PlayerState.stopped) {
          await _player.stop();
        }
        return;
      }

      if (!_isRunning) {
        if (_player.state != PlayerState.stopped) {
          await _player.stop();
        }
        return;
      }

      if (_player.state != PlayerState.playing) {
        await _startMetronomeFromBeginning();
        return;
      }

      await _player.setVolume(_isMuted ? 0.0 : 1.0);
    } catch (e) {
      debugPrint('Metronome sync failed: $e');
    }
  }

  Future<void> _toggleMute() async {
    setState(() {
      _isMuted = !_isMuted;
    });
    if (_player.state == PlayerState.playing) {
      await _player.setVolume(_isMuted ? 0.0 : 1.0);
      return;
    }
    unawaited(_syncMetronomePlayback());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _workCtrl.dispose();
    _restCtrl.dispose();
    _repeatCtrl.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  void _start() {
    final work = int.tryParse(_workCtrl.text);
    final rest = int.tryParse(_restCtrl.text);
    final cycles = int.tryParse(_repeatCtrl.text);
    if (work == null || rest == null || cycles == null) return;
    if (work <= 0 || rest <= 0 || cycles <= 0) return;

    _totalCycles = cycles;
    _currentCycle = 1;
    _beginPhase(_Phase.work, work * 60);
  }

  void _beginPhase(_Phase phase, int seconds) {
    _timer?.cancel();
    if (phase == _Phase.work) {
      _currentWorkTotalSeconds = seconds;
    }
    setState(() {
      _phase = phase;
      _remainingSeconds = seconds;
    });
    if (phase == _Phase.done) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remainingSeconds <= 1) {
        _handlePhaseEnd();
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
    unawaited(_syncMetronomePlayback());
  }

  Future<void> _handlePhaseEnd() async {
    _timer?.cancel();
    if (_phase == _Phase.work) {
      await _addMinutes(int.parse(_workCtrl.text));
      _beginPhase(_Phase.rest, int.parse(_restCtrl.text) * 60);
    } else if (_phase == _Phase.rest) {
      if (_currentCycle >= _totalCycles) {
        setState(() {
          _phase = _Phase.done;
          _remainingSeconds = 0;
        });
      } else {
        _currentCycle++;
        _beginPhase(_Phase.work, int.parse(_workCtrl.text) * 60);
      }
    }
  }

  void _pauseResume() {
    if (_phase == _Phase.idle || _phase == _Phase.done) return;
    if (_isRunning) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_remainingSeconds <= 1) {
          _handlePhaseEnd();
        } else {
          setState(() {
            _remainingSeconds--;
          });
        }
      });
    }
    unawaited(_syncMetronomePlayback());
    setState(() {});
  }

  Future<void> _reset() async {
    _timer?.cancel();
    await _player.stop();
    await _flushWorkProgress();
    setState(() {
      _phase = _Phase.idle;
      _currentWorkTotalSeconds = 0;
      _remainingSeconds = 0;
      _currentCycle = 0;
      _totalCycles = 0;
    });
  }

  String get _timerText {
    if (_phase == _Phase.done) return 'Done';
    if (_phase == _Phase.idle) return '00:00';
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _phaseLabel {
    switch (_phase) {
      case _Phase.work:
        return 'Work ($_currentCycle/$_totalCycles)';
      case _Phase.rest:
        return 'Break ($_currentCycle/$_totalCycles)';
      case _Phase.done:
        return 'Done';
      case _Phase.idle:
        return 'Go?';
    }
  }

  int _workElapsedMinutes() {
    if (_phase != _Phase.work || _currentWorkTotalSeconds == 0) return 0;
    final elapsed = _currentWorkTotalSeconds - _remainingSeconds;
    return (elapsed / 60).floor();
  }

  Future<void> _addMinutes(int minutes) async {
    if (minutes <= 0) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = FirebaseDatabase.instance.ref('users/${user.uid}/minutes');
    await ref.runTransaction((current) {
      final currentVal = (current as num?)?.toInt() ?? 0;
      return Transaction.success(currentVal + minutes);
    });
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit?'),
        content: const Text('The timer will reset upon exit. Confirm?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _flushWorkProgress() async {
    if (_phase == _Phase.work) {
      final minutes = _workElapsedMinutes();
      await _addMinutes(minutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    const buttonHeight = 70.0;
    const buttonStartHeight = 140.0;
    final textTheme = Theme.of(context).textTheme;

    return WillPopScope(
      onWillPop: () async {
        if (_phase == _Phase.idle || _phase == _Phase.done) return true;
        final shouldExit = await _confirmExit();
        if (shouldExit) {
          await _flushWorkProgress();
          await _reset();
        }
        return shouldExit;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (_phase == _Phase.idle || _phase == _Phase.done) {
                Navigator.of(context).pop();
                return;
              }
              final shouldExit = await _confirmExit();
              if (!shouldExit || !mounted) return;
              await _flushWorkProgress();
              await _reset();
              Navigator.of(context).pop();
            },
          ),
          title: const Text('Timer'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    final offsetAnimation = Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(animation);
                    return SizeTransition(
                      sizeFactor: animation,
                      axisAlignment: -1,
                      child: SlideTransition(
                        position: offsetAnimation,
                        child: child,
                      ),
                    );
                  },
                  child: _hideInputs
                      ? Align(
                          key: ValueKey('hidden'),
                          alignment: Alignment.topCenter,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Text(
                                _timerText,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.timer(textTheme),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _phaseLabel,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.phase(textTheme),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        )
                      : Align(
                          key: const ValueKey('inputs'),
                          alignment: Alignment.topCenter,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Work time',
                                style: AppTextStyles.label,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _workCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'For example, 25',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'minutes',
                                    style: AppTextStyles.label,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Break time',
                                style: AppTextStyles.label,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _restCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'For example, 5',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'minutes',
                                    style: AppTextStyles.label,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Number of repetitions',
                                style: AppTextStyles.label,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _repeatCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'For example, 4',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'times',
                                    style: AppTextStyles.label,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _toggleMute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 45, 164, 207),
                  disabledBackgroundColor: Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  iconAlignment: IconAlignment.end,
                  iconSize: 25,
                ),
                icon: Icon(_isMuted ? Icons.volume_mute : Icons.volume_up),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: 200,
                height: buttonStartHeight,
                child: ElevatedButton(
                  onPressed: () {
                    final isStartPhase =
                        _phase == _Phase.idle || _phase == _Phase.done;
                    if (isStartPhase) {
                      _start();
                    } else {
                      _pauseResume();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        (_phase == _Phase.idle || _phase == _Phase.done)
                        ? AppColors.start
                        : (_isRunning ? AppColors.pause : AppColors.cont),
                    foregroundColor:
                        (_phase == _Phase.idle || _phase == _Phase.done)
                        ? Colors.white
                        : Colors.black,
                  ),
                  child: Text(
                    (_phase == _Phase.idle || _phase == _Phase.done)
                        ? 'Start'
                        : (_isRunning ? 'Pause' : 'Continue'),
                  ),
                ),
              ),
              const SizedBox(width: 40, height: 20),
              SizedBox(
                width: 86,
                height: buttonHeight,
                child: ElevatedButton(
                  onPressed: _phase == _Phase.idle ? null : () => _reset(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.reset,
                    disabledBackgroundColor: Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white70,
                  ),
                  child: const Text('Reset'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
