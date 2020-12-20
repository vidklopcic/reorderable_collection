import 'package:flutter/material.dart';

import 'package:gm5_utils/gm5_utils.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

typedef ReordeableCollectionGestureDetectorBuilder = Widget Function(Widget child);
typedef ReordeableCollectionItemBuilder<T> = Widget Function(
    BuildContext context, Key key, ReordeableCollectionGestureDetectorBuilder dragDetector, int index);
typedef ReordeableCollectionItemBuilderWrapper<T> = Widget Function(BuildContext context, int index);
typedef ReordeableCollectionBuilder<T> = Widget Function(BuildContext context, Key key,
    ReordeableCollectionItemBuilderWrapper<T> itemBuilder, ScrollController scrollController);

enum ReordeableCollectionReorderType { swap, reorder }

class ReordeableCollectionController<T> extends StatefulWidget {
  final ReordeableCollectionBuilder<T> collectionBuilder;
  final ReordeableCollectionItemBuilder<T> itemBuilder;
  final ReordeableCollectionReorderType reorderType;
  final Duration duration;
  final Curve curve;

  const ReordeableCollectionController({
    Key key,
    @required this.collectionBuilder,
    @required this.itemBuilder,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOutExpo,
    this.reorderType = ReordeableCollectionReorderType.reorder,
  }) : super(key: key);

  @override
  ReordeableCollectionControllerState createState() => ReordeableCollectionControllerState<T>();
}

class ReordeableCollectionControllerState<T> extends State<ReordeableCollectionController<T>>
    with SingleTickerProviderStateMixin {
  Map<int, Rect> _intialBounds = {};
  Map<int, Rect> _futureBounds = {};
  Map<int, Offset> _currentOffsets = {};
  ReordeableCollectionItemBuilderWrapper<T> currentBuilderWrapper;
  ReordeableCollectionItemBuilderWrapper<T> futureBuilderWrapper;
  _ElementKeys futureKeys = _ElementKeys();
  _ElementKeys currentKeys = _ElementKeys();
  int _from;
  int _to;
  bool _dragging = false;
  AnimationController _rearrangeAnimationController;
  Animation<double> _rearrangeAnimation;
  Offset _dragOffset = Offset.zero;
  GlobalKey _currentTree = GlobalKey();
  GlobalKey _futureTree = GlobalKey();
  LinkedScrollControllerGroup _scrollSync = LinkedScrollControllerGroup();
  ScrollController _currentScrollController;
  ScrollController _futureScrollController;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
          opacity: 0.1,
          child: widget.collectionBuilder(context, _futureTree, futureBuilderWrapper, _futureScrollController),
        ),
        widget.collectionBuilder(context, _currentTree, currentBuilderWrapper, _currentScrollController),
      ],
    );
  }

  Offset _calcTransitionOffset(int index) {
    Offset oTo = _futureBounds[index]?.center;
    Offset oFrom = _intialBounds[index]?.center;
    Offset oCurr = _currentOffsets[index] ?? Offset.zero;
    if (oTo == null || oFrom == null) {
      oTo = Offset.zero;
      oFrom = Offset.zero;
    }
    Offset oTarg = oTo - oFrom;
    return Tween(begin: oCurr, end: oTarg).animate(_rearrangeAnimation).value;
  }

  @override
  void initState() {
    super.initState();
    _currentScrollController = _scrollSync.addAndGet();
    _futureScrollController = _scrollSync.addAndGet();
    _rearrangeAnimationController = AnimationController(vsync: this, duration: widget.duration);
    _rearrangeAnimation = CurvedAnimation(parent: _rearrangeAnimationController, curve: widget.curve);

    currentBuilderWrapper = (context, index) => AnimatedBuilder(
          animation: _rearrangeAnimation,
          builder: (ctx, child) {
            if (index == _from) {
              return Transform.translate(
                offset: _dragOffset,
                child: widget.itemBuilder(
                  context,
                  currentKeys.keyForIndex(index),
                  _gestureDetector(currentKeys.keyForIndex(index), index),
                  index,
                ),
              );
            }
            return Transform.translate(
              offset: _calcTransitionOffset(index),
              child: widget.itemBuilder(
                context,
                currentKeys.keyForIndex(index),
                _gestureDetector(currentKeys.keyForIndex(index), index),
                index,
              ),
            );
          },
        );

    futureBuilderWrapper = (context, index) {
      if (_from == null || _to == null)
        return widget.itemBuilder(context, futureKeys.keyForIndex(index), (c) => c, index);
      if (widget.reorderType == ReordeableCollectionReorderType.swap) {
        if (index == _from)
          index = _to;
        else if (index == _to) index = _from;
      } else {
        if (index == _to) {
          index = _from;
        } else if (index >= _from && index < _to)
          index += 1;
        else if (index <= _from && index >= _to) index -= 1;
      }
      return widget.itemBuilder(context, futureKeys.keyForIndex(index), (c) => c, index);
    };
  }

  ReordeableCollectionGestureDetectorBuilder _gestureDetector(GlobalKey key, int index) {
    return (Widget child) => GestureDetector(
          onPanStart: (details) {
            _updateBounds(initial: true);
            setState(() {
              _from = index;
              _dragging = true;
              _dragOffset = Offset.zero;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _dragOffset += details.delta;
            });
            gm5Utils.eventUtils.throttle(300, _updateHitObject, arguments: [key]);
          },
          onPanEnd: (details) {
            setState(() {
              print('ended drag');
              _dragging = false;
            });
          },
          child: child,
        );
  }

  Rect _renderBoxToBounds(RenderBox box) {
    if (box == null) return null;
    Offset topLeft = box.localToGlobal(Offset.zero);
    Offset bottomRight = topLeft + box.size.bottomRight(Offset.zero);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _updateHitObject(GlobalKey draggingKey) {
    if (!_dragging) return;
    Offset renderCenter = _renderBoxToBounds(draggingKey.currentContext?.findRenderObject()).center;
    if (renderCenter == null) return;
    // this is very expensive, so we must throttle calls to this function
    // is there a better option to find the object beneath?
    for (int index in _intialBounds.keys) {
      if (_intialBounds[index].contains(renderCenter)) {
        _setToIndex(index);
        return;
      }
    }
  }

  void _setToIndex(int to) {
    setState(() {
      _to = to;
    });
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      for (int index in _intialBounds.keys) {
        _currentOffsets[index] = _calcTransitionOffset(index);
      }
      _updateBounds();
      _rearrangeAnimationController.forward(from: 0);
    });
  }

  void _updateBounds({bool initial = false}) {
    for (GlobalKey key in futureKeys.keys) {
      RenderObject renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) continue;
      _futureBounds[futureKeys.indexForKey(key)] = _renderBoxToBounds(renderObject);
    }
    if (!initial) return;
    for (GlobalKey key in currentKeys.keys) {
      RenderObject renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) continue;
      _intialBounds[currentKeys.indexForKey(key)] = _renderBoxToBounds(renderObject);
    }
  }
}

class _ElementKeys {
  Map<int, GlobalKey> _indexes = {};
  Map<GlobalKey, int> _keys = {};

  GlobalKey keyForIndex(int index) {
    return _indexes.putIfAbsent(
      index,
      () {
        GlobalKey key = GlobalKey();
        _keys[key] = index;
        return key;
      },
    );
  }

  int indexForKey(GlobalKey key) => _keys[key];

  List<GlobalKey> get keys => _keys.keys.toList();
}
