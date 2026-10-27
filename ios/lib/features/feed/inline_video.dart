import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/widgets/image_decode.dart';
import '../../core/widgets/loading.dart';

/// A card counts as on screen (and may play) once this much of it is visible.
const _visibleThreshold = 0.6;

/// Muted clips play alongside the user's music; one with sound takes over
/// the audio session like any player (iOS: no MixWithOthers). The session is
/// shared by every player, so whoever plays sound last sets it.
void videoSound(VideoPlayerController c, {required bool muted}) {
  c.setVolume(muted ? 0 : 1);
  VideoPlayerPlatform.instance.setMixWithOthers(muted).ignore();
}

class _Candidate {
  _Candidate(this.url, this.fraction, this.muted);
  String url;
  double fraction;
  bool muted;
}

/// One video player shared by every inline feed video. Each [InlineVideo]
/// reports how much of it is on screen; the most visible one past the
/// threshold gets the player, every other card shows its poster. One decoder
/// for the whole feed, instead of one per nearby card competing while
/// scrolling. Positions are remembered per URL, so a clip scrolled away and
/// back resumes where it was, and the full-screen viewer borrows the playing
/// clip itself (no second download, carries on from the same frame).
class InlineVideoPool extends ChangeNotifier {
  InlineVideoPool._();
  static final instance = InlineVideoPool._();

  final _candidates = <Object, _Candidate>{};
  final _positions = <String, Duration>{}; // insertion-ordered: oldest first
  VideoPlayerController? _player;
  String? _activeUrl;

  /// Media viewers open over the feed (they keep it built beneath).
  int _covers = 0;

  /// The full-screen viewer has the player (see [borrow]).
  bool _lent = false;

  /// The key of the card currently holding the player.
  Object? get active => _active;
  Object? _active;

  /// The active clip is initialised (the mute toggle shows from here).
  bool get ready => _ready;
  bool _ready = false;

  /// The active clip has drawn its first frame (until then it's blank).
  bool get firstFrame => _firstFrame;
  bool _firstFrame = false;

  VideoPlayerController? get player => _player;

  void report(Object key, String url, double fraction, bool muted) {
    final c = _candidates[key];
    if (c == null) {
      _candidates[key] = _Candidate(url, fraction, muted);
    } else {
      if (c.url == url && c.fraction == fraction) return;
      c
        ..url = url
        ..fraction = fraction;
    }
    _recompute();
  }

  // Called as a card is disposed, when the widget tree can't rebuild: the
  // other cards hear of it a moment later.
  void remove(Object key) {
    if (_candidates.remove(key) != null) scheduleMicrotask(_recompute);
  }

  void setMuted(Object key, bool muted) {
    _candidates[key]?.muted = muted;
    final p = _player;
    if (_active == key && p != null) videoSound(p, muted: muted);
  }

  /// Pauses the feed clip while a media viewer covers it; resumes after.
  void setCovered(bool covered) {
    _covers += covered ? 1 : -1;
    if (_lent) return;
    final p = _player;
    if (_covers > 0) {
      p?.pause();
    } else if (_active != null && _ready) {
      p?.play();
    }
  }

  /// Where the feed's clip for [url] is (or was left), for the full-screen
  /// viewer to continue.
  Duration? position(String url) =>
      url == _activeUrl ? _player?.value.position : _positions[url];

  /// The playing feed clip for [url], handed to the full-screen viewer until
  /// [giveBack]; null when the feed isn't playing that clip.
  VideoPlayerController? borrow(String url) {
    final p = _player;
    if (_lent || url != _activeUrl || p == null || !p.value.isInitialized) {
      return null;
    }
    _lent = true;
    return p;
  }

  void giveBack(VideoPlayerController p) {
    if (!_lent || p != _player) return;
    _lent = false;
    videoSound(p, muted: _candidates[_active]?.muted ?? true);
    // Paused while still covered: the viewer's setCovered(false) plays it.
    p.pause();
    // Cards may have come or gone meanwhile (later, as for [remove]: this
    // runs as the viewer is disposed).
    scheduleMicrotask(_recompute);
  }

  void _recompute() {
    if (_lent) return; // the viewer has it; sorted out on giveBack
    final current = _active;
    MapEntry<Object, _Candidate>? best, cur;
    for (final e in _candidates.entries) {
      if (e.value.fraction <= _visibleThreshold) continue;
      if (best == null || e.value.fraction > best.value.fraction) best = e;
      if (e.key == current) cur = e;
    }
    // Hysteresis: keep the playing card while it's (about) as visible as the
    // best.
    if (cur != null &&
        best != null &&
        cur.value.fraction >= best.value.fraction - 0.05) {
      best = cur;
    }
    if (best?.key == current && best?.value.url == _activeUrl) return;

    final old = _player;
    final oldUrl = _activeUrl;
    if (old != null && oldUrl != null && old.value.isInitialized) {
      _positions.remove(oldUrl);
      _positions[oldUrl] = old.value.position;
      if (_positions.length > 64) _positions.remove(_positions.keys.first);
    }
    if (old != null) {
      old
        ..removeListener(_watch)
        ..pause();
      // Disposed once the card showing it has rebuilt without it.
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => old.dispose())
        ..scheduleFrame();
    }
    _player = null;
    _ready = false;
    _firstFrame = false;
    if (best == null) {
      // Nothing on screen: no decoder at all.
      _active = null;
      _activeUrl = null;
      notifyListeners();
      return;
    }
    final c = best.value;
    _active = best.key;
    _activeUrl = c.url;
    final p = _player = VideoPlayerController.networkUrl(Uri.parse(c.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: c.muted));
    p.setLooping(true);
    p.setVolume(c.muted ? 0 : 1);
    p.addListener(_watch);
    p.initialize().then((_) async {
      if (_player != p) return;
      final at = _positions[c.url];
      if (at != null) await p.seekTo(at);
      if (_player != p) return;
      _ready = true;
      notifyListeners();
      if (_covers == 0) p.play();
    }).catchError((Object _) {});
    notifyListeners();
  }

  // The first frame: until then the surface is blank, so the poster stays.
  void _watch() {
    final p = _player;
    if (p == null || _firstFrame || p.value.position <= Duration.zero) return;
    _firstFrame = true;
    notifyListeners();
  }
}

/// A feed video that autoplays (muted unless Autoplay with sound, looping)
/// while it's the most visible one on screen, and shows its poster
/// otherwise. Tap opens the full-screen viewer (with sound). It gets the
/// shared player only once mostly on screen, not when it's built: the list
/// builds cards ahead of the viewport.
class InlineVideo extends StatefulWidget {
  const InlineVideo({
    super.key,
    required this.url,
    required this.height,
    required this.onTap,
    this.poster,
    this.startMuted = true,
  });

  final String url;
  final double height;
  final VoidCallback onTap;
  final String? poster;
  final bool startMuted; // Settings → Autoplay with sound turns it off

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  final _pool = InlineVideoPool.instance;
  final _key = Object();
  late bool _muted = widget.startMuted;
  // What this card last drew from the pool: it rebuilds only when that
  // changes, not for every other card's events.
  (bool, bool, bool) _seen = (false, false, false);

  (bool, bool, bool) _state() {
    final mine = _pool.active == _key;
    return (mine, mine && _pool.ready, mine && _pool.firstFrame);
  }

  void _onPool() {
    final s = _state();
    if (s != _seen && mounted) setState(() => _seen = s);
  }

  @override
  void initState() {
    super.initState();
    _pool.addListener(_onPool);
  }

  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return; // reported once more as it's removed
    // Quantized, so scrolling doesn't recompute for every pixel.
    final f = (info.visibleFraction * 20).round() / 20;
    _pool.report(_key, widget.url, f, _muted);
  }

  @override
  void dispose() {
    _pool.removeListener(_onPool);
    _pool.remove(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (mine, ready, firstFrame) = _seen;
    final c = mine ? _pool.player : null;
    return VisibilityDetector(
      key: Key('inlinevid_${widget.url}'),
      onVisibilityChanged: _onVisibility,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The poster stays underneath; the video fades in on top once
              // it has a frame to show.
              if (widget.poster != null)
                CachedNetworkImage(
                    imageUrl: widget.poster!,
                    fit: BoxFit.cover,
                    memCacheWidth: feedDecodeWidth(context))
              else
                const ColoredBox(color: Colors.black12),
              if (ready && c != null)
                AnimatedOpacity(
                  opacity: firstFrame ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  ),
                ),
              if (mine && !firstFrame)
                const Center(child: Loading(size: 40)),
              // Mute / unmute toggle.
              if (ready)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _muted = !_muted);
                      _pool.setMuted(_key, _muted);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        semanticLabel: _muted ? 'Unmute' : 'Mute',
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
