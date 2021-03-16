import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:gm5_utils/gm5_utils.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

typedef ReordeableCollectionGestureDetectorBuilder = Widget Function(Widget child);
typedef ReordeableCollectionItemBuilder<T> = Widget Function(
  BuildContext context,
  Key key,
  ReordeableCollectionGestureDetectorBuilder dragDetector,
  int index,
);
typedef ReordeableCollectionItemBuilderWrapper<T> = Widget Function(BuildContext context, int index);
typedef ReordeableCollectionBuilder<T> = Widget Function(
  BuildContext context,
  Key key,
  ReordeableCollectionItemBuilderWrapper<T> itemBuilder,
  ScrollController scrollController,
  bool disableScrolling,
  int itemCount,
);
typedef ReorderableCollectionOnReorder = void Function(int from, int to);
typedef DropPlaceholderBuilder = Widget Function(BuildContext context, int from, int to);
typedef DragPreviewBuilder = Widget Function(BuildContext context, int index, Offset cursorOffset);

// todo support swap with offset positioning
enum ReordeableCollectionReorderType { swap, reorder }
enum ReordeableCollectionPositioningType {
  /// items are tigtly coupled together (ie. in ListView), so offset for the moving widget applies everywhere
  offset,

  /// align item's center points - useful for layouts where reordering doesn't affect center points
  center,

  /// build a duplicate collection in the target state and use its positions for ordering - some performance hit
  shadow,
}

class ReordeableCollectionController<T> extends StatefulWidget {
  final int itemCount;
  final ReordeableCollectionBuilder<T> collectionBuilder;
  final ReordeableCollectionItemBuilder<T> itemBuilder;
  final ReordeableCollectionReorderType reorderType;
  final ReordeableCollectionPositioningType positioningType;
  final Duration duration;
  final Curve curve;
  final Axis limitToAxis;
  final Axis scrollDirection;
  final ReorderableCollectionOnReorder onReorder;
  final DragPreviewBuilder dragPreviewBuilder;
  final DropPlaceholderBuilder dropPlaceholderBuilder;

  const ReordeableCollectionController({
    Key key,
    @required this.collectionBuilder,
    @required this.itemBuilder,
    @required this.onReorder,
    @required this.itemCount,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOutExpo,
    this.reorderType = ReordeableCollectionReorderType.reorder,
    this.limitToAxis = Axis.vertical,
    this.positioningType = ReordeableCollectionPositioningType.shadow,
    this.scrollDirection = Axis.vertical,
    this.dragPreviewBuilder,
    this.dropPlaceholderBuilder,
  })  : assert(positioningType != ReordeableCollectionPositioningType.offset || limitToAxis != null),
        super(key: key);

  @override
  ReordeableCollectionControllerState createState() => ReordeableCollectionControllerState<T>();
}

class ReordeableCollectionControllerState<T> extends State<ReordeableCollectionController<T>>
    with SingleTickerProviderStateMixin {
  ReordeableCollectionItemBuilderWrapper<T> builderWrapper;

  Map<int, Rect> _initialBounds = {};
  Map<int, Offset> _targetOffsets = {};
  Map<int, Offset> _currentOffsets = {};
  _ElementKeys currentKeys = _ElementKeys();
  Offset _cursorOffset;
  int _from;
  int _to;
  Offset _dragOffset = Offset.zero;
  GlobalKey _collectionKey = GlobalKey();
  GlobalKey _shadowCollectionKey = GlobalKey();

  OverlayEntry _overlay;

  ScrollController _scrollController = ScrollController();
  ScrollController _shadowScrollController = ScrollController();
  bool _disableScrolling = false;
  double _startScrollOffset;
  Rect _collectionBounds;

  AnimationController _rearrangeAnimationController;
  Animation<double> _rearrangeAnimation;

  int _shadowIndexOffset;
  List<Widget> _shadowChildren;

  List<Rect> _shadowBounds = [];

  @override
  Widget build(BuildContext context) {
    final collection = widget.collectionBuilder(
      context,
      _collectionKey,
      builderWrapper,
      _scrollController,
      _disableScrolling,
      widget.itemCount,
    );

    if (widget.positioningType == ReordeableCollectionPositioningType.shadow) {
      return Stack(
        children: [
          Positioned.fill(child: _shadowWidget()),
          collection,
        ],
      );
    } else {
      return collection;
    }
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
    builderWrapper = (context, index) => AnimatedBuilder(
          animation: _rearrangeAnimation,
          builder: (ctx, child) {
            if (_from == index)
              return Transform.translate(
                offset: Offset(MediaQuery.of(context).size.width * 2, 0),
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

    // couple shadow scroll with real layout
    _scrollController.addListener(() {
      if (widget.positioningType != ReordeableCollectionPositioningType.shadow || _startScrollOffset == null) return;
      _shadowScrollController.jumpTo(_scrollController.offset - _startScrollOffset);
    });
  }

  int toFutureIndex(int index) {
    if (_from == null || _to == null) return index;
    if (index == _from) return _to;
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

  int fromFutureIndex(int index) {
    if (_from == null || _to == null) return index;
    if (widget.reorderType == ReordeableCollectionReorderType.swap) {
      if (index == _from)
        index = _to;
      else if (index == _to) index = _from;
    } else {
      if (index == _to) {
        index = _from;
      } else if (index >= _from && index < _to) {
        index += 1;
      } else if (index <= _from && index > _to) {
        index -= 1;
      }
    }
    return index;
  }

  int getTargetOffset(int index) {
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
          onTapDown: (_) => setState(() => _disableScrolling = true),
          onPanStart: (details) {
            _cursorOffset = details.localPosition;
            _from = index;
            _updateBounds();
            _overlay = OverlayEntry(
              builder: (ctx) => Material(type: MaterialType.transparency, child: _draggableChild(index)),
            );
            Overlay.of(context).insert(_overlay);

            if (widget.positioningType == ReordeableCollectionPositioningType.shadow) {
              _startShadowWidget();
            }

            setState(() {
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
            _startScrollOffset = null;
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
    setState(() {
      _to = to;
    });

    if (widget.positioningType == ReordeableCollectionPositioningType.shadow) {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _updatePositions();
      });
    } else {
      _updateBounds();
    }
  }

  void _updatePositions() {
    for (int index in _initialBounds.keys) {
      _currentOffsets[index] = _calcTransitionOffset(index);
    }

    for (int index in _initialBounds.keys) {
      switch (widget.positioningType) {
        case ReordeableCollectionPositioningType.offset:
          _updateCenterPositions(index);
          _rearrangeAnimationController.forward(from: 0);
          break;
        case ReordeableCollectionPositioningType.center:
          _updateCenterPositions(index);
          _rearrangeAnimationController.forward(from: 0);
          break;
        case ReordeableCollectionPositioningType.shadow:
          _updateShadowPositions(index);
          break;
      }
    }
    _rearrangeAnimationController.forward(from: 0);
  }

  void _updateBounds() {
    RenderObject renderObject = _collectionKey.currentContext?.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      throw Exception('Collection key is not attached. Did you forget to use the ReordeableCollectionBuilder key?');
    }
    _collectionBounds = _renderBoxToBounds(renderObject);

    for (GlobalKey key in currentKeys.keys) {
      RenderObject renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) continue;
      _initialBounds[currentKeys.indexForKey(key)] = _renderBoxToBounds(renderObject);
    }
  }

  void _updateShadowBounds() {
    _shadowBounds = List.filled(_shadowChildren.length, null);
    for (int i = 0; i < _shadowChildren.length; i++) {
      final key = _shadowChildren[i].key as GlobalKey;
      RenderObject renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) continue;
      _shadowBounds[i] = _renderBoxToBounds(renderObject);
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
    if (widget.positioningType == ReordeableCollectionPositioningType.offset) {
      if (widget.limitToAxis == Axis.vertical) {
        if (_to < _from) {
          _targetOffsets[_from] = _initialBounds[_to].topCenter + Offset(0, _initialBounds[_from].height / 2);
        } else {
          _targetOffsets[_from] = _initialBounds[_to].bottomCenter - Offset(0, _initialBounds[_from].height / 2);
        }
      } else {
        if (_to < _from) {
          _targetOffsets[_from] = _initialBounds[_to].centerLeft + Offset(_initialBounds[_from].width / 2, 0);
        } else {
          _targetOffsets[_from] = _initialBounds[_to].centerRight - Offset(_initialBounds[_from].width / 2, 0);
        }
      }
    } else if (widget.positioningType == ReordeableCollectionPositioningType.shadow) {
      _targetOffsets[_from] = _shadowBounds[_from - _shadowIndexOffset].center;
    } else {
      _targetOffsets[_from] = _initialBounds[_to].center;
    }
    int from = _from;
    _from = null;
    _overlay.remove();
    await _rearrangeAnimationController.forward(from: 0);
    widget.onReorder(from, _to);
    setState(() {
      _currentOffsets = {};
      _to = null;
      _currentOffsets = {};
      _initialBounds = {};
      _targetOffsets = {};
      _disableScrolling = false;
    });
  }

  Widget _draggableChild(int index) {
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _initialBounds[index].width,
        height: _initialBounds[index].height,
        child: AnimatedBuilder(
          animation: _rearrangeAnimationController,
          builder: (ctx, child) => Transform.translate(
            offset: _from == null
                ? (_initialBounds[index].topLeft + _calcTransitionOffset(index))
                : (_dragOffset + _initialBounds[index].topLeft),
            child: widget.dragPreviewBuilder != null
                ? widget.dragPreviewBuilder(context, _from, _cursorOffset)
                : widget.itemBuilder(
                    context,
                    null,
                    (c) => c,
                    index,
                  ),
          ),
        ),
      ),
    );
  }

  void _updateCenterPositions(int index) {
    int futureIndex = toFutureIndex(index);
    _targetOffsets[index] = _initialBounds[futureIndex].center;
  }

  void _updateOffsetPositions(int index) {
    int tDistance = _to - _from;
    Offset offset;
    if (widget.limitToAxis == Axis.vertical) {
      offset = Offset(0, _initialBounds[_from].height);
    } else {
      offset = Offset(_initialBounds[_from].width, 0);
    }
    _targetOffsets[index] = _initialBounds[index].center;

    int distance = index - _from;
    if (distance.abs() <= tDistance.abs() && distance.sign == tDistance.sign) {
      _targetOffsets[index] -= offset * distance.sign.toDouble();
    }
  }

  void _updateShadowPositions(int index) {
    _updateShadowBounds();
    _targetOffsets[index] = _shadowBounds[index - _shadowIndexOffset].center;
  }

  Widget _shadowWidget() {
    if (_from == null || _shadowChildren == null) return Offstage();
    return widget.collectionBuilder(
      context,
      _shadowCollectionKey,
      (c, i) {
        int fi = fromFutureIndex(i + _shadowIndexOffset) - _shadowIndexOffset;
        // print('$i -> $fi');
        return _shadowChildren[fi];
      },
      _shadowScrollController,
      true,
      _shadowChildren.length,
    );
  }

  void _startShadowWidget() {
    _startScrollOffset = _scrollController.offset;
    double scrollOffset;
    if (widget.scrollDirection == Axis.vertical) {
      scrollOffset = _collectionBounds.top - _initialBounds.values.map((e) => e.top).reduce(math.min);
    } else {
      scrollOffset = _collectionBounds.left - _initialBounds.values.map((e) => e.left).reduce(math.min);
    }
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _shadowScrollController.jumpTo(scrollOffset);
    });

    _shadowIndexOffset = _initialBounds.keys.reduce(math.min);

    _shadowChildren = [];
    for (int index in _initialBounds.keys.toList()..sort()) {
      _shadowChildren.add(
        SizedBox(
          key: GlobalKey(),
          width: _initialBounds[index].width,
          height: _initialBounds[index].height,
          child: index == _from
              ? widget.dropPlaceholderBuilder != null
                  ? widget.dropPlaceholderBuilder(context, _from, _to)
                  : null
              : null,
        ),
      );
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
