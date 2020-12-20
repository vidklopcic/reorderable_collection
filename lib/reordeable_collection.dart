import 'package:flutter/material.dart';

import 'package:gm5_utils/gm5_utils.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

typedef ReordeableCollectionGestureDetectorBuilder = Widget Function(Widget child);
typedef ReordeableCollectionItemBuilder<T> = Widget Function(
    BuildContext context, Key key, ReordeableCollectionGestureDetectorBuilder dragDetector, int index);
typedef ReordeableCollectionItemBuilderWrapper<T> = Widget Function(BuildContext context, int index);
typedef ReordeableCollectionBuilder<T> = Widget Function(BuildContext context, Key key,
    ReordeableCollectionItemBuilderWrapper<T> itemBuilder, ScrollController scrollController);
typedef ReorderableCollectionOnReorder = void Function(int from, int to);

enum ReordeableCollectionReorderType { swap, reorder }

class ReordeableCollectionController<T> extends StatefulWidget {
  final ReordeableCollectionBuilder<T> collectionBuilder;
  final ReordeableCollectionItemBuilder<T> itemBuilder;
  final ReordeableCollectionReorderType reorderType;
  final Duration duration;
  final Curve curve;
  final Axis limitToAxis;
  final ReorderableCollectionOnReorder onReorder;

  const ReordeableCollectionController({
    Key key,
    @required this.collectionBuilder,
    @required this.itemBuilder,
    @required this.onReorder,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOutExpo,
    this.reorderType = ReordeableCollectionReorderType.reorder,
    this.limitToAxis = Axis.vertical,
  }) : super(key: key);

  @override
  ReordeableCollectionControllerState createState() => ReordeableCollectionControllerState<T>();
}

class ReordeableCollectionControllerState<T> extends State<ReordeableCollectionController<T>>
    with SingleTickerProviderStateMixin {
  Map<int, Rect> _initialBounds = {};
  Map<int, Offset> _targetOffsets = {};
  Map<int, Offset> _currentOffsets = {};
  ReordeableCollectionItemBuilderWrapper<T> currentBuilderWrapper;
  ReordeableCollectionItemBuilderWrapper<T> futureBuilderWrapper;
  _ElementKeys currentKeys = _ElementKeys();
  int _from;
  int _to;
  AnimationController _rearrangeAnimationController;
  Animation<double> _rearrangeAnimation;
  Offset _dragOffset = Offset.zero;
  GlobalKey _currentTree = GlobalKey();
  ScrollController _currentScrollController = ScrollController();
  OverlayEntry _overlay;

  @override
  Widget build(BuildContext context) {
    return widget.collectionBuilder(context, _currentTree, currentBuilderWrapper, _currentScrollController);
  }

  Offset _calcTransitionOffset(int index) {
    Offset oTo = _targetOffsets[index];
    Offset oFrom = _initialBounds[index]?.center;
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
    _rearrangeAnimationController = AnimationController(vsync: this, duration: widget.duration);
    _rearrangeAnimation = CurvedAnimation(parent: _rearrangeAnimationController, curve: widget.curve);
    currentBuilderWrapper = (context, index) => AnimatedBuilder(
      animation: _rearrangeAnimation,
      builder: (ctx, child) {
        if (_from == index) return Transform.translate(
          offset: Offset(double.infinity, 0),
          child: widget.itemBuilder(
            context,
            currentKeys.keyForIndex(index),
            _gestureDetector(currentKeys.keyForIndex(index), index),
            index,
          ),
        );
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
  }

  int toFutureIndex(int index) {
    int oi = index;
    if (_from == null || _to == null) return index;
    if (widget.reorderType == ReordeableCollectionReorderType.swap) {
      if (index == _from)
        index = _to;
      else if (index == _to) index = _from;
    } else {
      if (index > _from && index <= _to) {
        index -= 1;
      } else if (index < _from && index >= _to) {
        index += 1;
      }
    }
    return index;
  }

  ReordeableCollectionGestureDetectorBuilder _gestureDetector(GlobalKey key, int index) {
    return (Widget child) => GestureDetector(
          onPanStart: (details) {
            _updateBounds();
            _overlay = OverlayEntry(
              builder: (ctx) => Material(type: MaterialType.transparency, child: _draggableChild(index)),
            );
            Overlay.of(context).insert(_overlay);
            setState(() {
              _from = index;
              _dragOffset = Offset.zero;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _dragOffset += details.delta.scale(
                widget.limitToAxis == Axis.vertical ? 0 : 1,
                widget.limitToAxis == Axis.horizontal ? 0 : 1,
              );
            });
            _overlay?.markNeedsBuild();
            gm5Utils.eventUtils.throttle(widget.duration.inMilliseconds, _updateHitObject, arguments: [key]);
          },
          onPanEnd: (details) {
            _endDrag();
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
    if (_from == null) return;
    Offset renderCenter = _dragOffset + _initialBounds[_from].center;
    for (int index in _initialBounds.keys) {
      if (_initialBounds[index].contains(renderCenter)) {
        _setToIndex(index);
        return;
      }
    }
  }

  void _setToIndex(int to) {
    if (to == _to) return;
    _to = to;
    for (int index in _initialBounds.keys) {
      _currentOffsets[index] = _calcTransitionOffset(index);
    }
    for (int index in _initialBounds.keys) {
      int futureIndex = toFutureIndex(index);
      _targetOffsets[index] = _initialBounds[futureIndex].center;
    }
    _rearrangeAnimationController.forward(from: 0);
  }

  void _updateBounds() {
    for (GlobalKey key in currentKeys.keys) {
      RenderObject renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) continue;
      _initialBounds[currentKeys.indexForKey(key)] = _renderBoxToBounds(renderObject);
    }
  }

  void _endDrag() async {
    for (int index in _initialBounds.keys) {
      _currentOffsets[index] = _calcTransitionOffset(index);
    }
    if (_to == null) {
      _to = _from;
    }
    _currentOffsets[_from] = _dragOffset;
    _targetOffsets[_from] = _initialBounds[_to].center;
    int from = _from;
    _from = null;
    await _rearrangeAnimationController.forward(from: 0);
    widget.onReorder(from, _to);
    _overlay.remove();
    setState(() {
      _currentOffsets = {};
      _to = null;
      _currentOffsets = {};
      _initialBounds = {};
      _targetOffsets = {};
    });
  }

  Widget _draggableChild(int index) {
    return AnimatedBuilder(
      animation: _rearrangeAnimationController,
      builder: (ctx, child) => Transform.translate(
        offset: _from == null
            ? (_initialBounds[index].topLeft + _calcTransitionOffset(index))
            : (_dragOffset + _initialBounds[index].topLeft),
        child: widget.itemBuilder(
          context,
          null,
          (c) => c,
          index,
        ),
      ),
    );
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
