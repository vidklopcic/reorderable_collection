import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:gm5_utils/gm5_utils.dart';

typedef ReordeableCollectionGestureDetectorBuilder = Widget Function(Widget child);
typedef ReordeableCollectionItemBuilder<T> = Widget Function(
  BuildContext context,
  Key? key,
  ReordeableCollectionGestureDetectorBuilder dragDetector,
  int index,
);
typedef ReordeableCollectionItemBuilderWrapper<T> = Widget Function(BuildContext context, int index);
typedef ReordeableCollectionBuilder<T> = Widget Function(
  BuildContext context,
  Key key,
  ReordeableCollectionItemBuilderWrapper<T>? itemBuilder,
  ScrollController scrollController,
  bool disableScrolling,
  int itemCount,
);
typedef ReorderableCollectionOnReorder = void Function(int from, int to);
typedef DropPlaceholderBuilder = Widget Function(BuildContext context, int? from, int? to);
typedef ShadowItemBuilder = Widget Function(BuildContext context, int? index);
typedef DragPreviewBuilder = Widget Function(BuildContext context, int? index, Offset? cursorOffset);

enum ReordeableCollectionReorderType { swap, reorder }

class ReordeableCollection<T> extends StatefulWidget {
  /// forwarded to collection builder
  final int itemCount;

  /// builds primary collection and "shadow" widget to calculate future offsets
  final ReordeableCollectionBuilder<T> collectionBuilder;

  /// forwarded to collectionBuilder and used to build the preview
  final ReordeableCollectionItemBuilder<T> itemBuilder;
  final ReordeableCollectionReorderType reorderType;

  /// Reorder and drop animation duration. This is also the debounce duration.
  final Duration duration;

  /// reorder and drop animation curve
  final Curve curve;

  /// limit drag to a single axis
  final Axis limitToAxis;

  /// used to calculate scroll offset for the shadow widget
  final Axis scrollDirection;

  /// Any underlying data should be reordered here.
  /// Keys are reordered internally. Therefore StatefulWidgets will retain their state by default.
  final ReorderableCollectionOnReorder onReorder;

  /// overrides default preview from the itemBuilder
  final DragPreviewBuilder? dragPreviewBuilder;

  /// widget marking the potential drop target
  final DropPlaceholderBuilder? dropPlaceholderBuilder;

  /// Builds widgets directly behind the visible collection items.
  /// Can be used to add effects (eg. outline using OverflowBox or background if item is transparent)
  final ShadowItemBuilder? shadowItemBuilder;

  const ReordeableCollection({
    super.key,
    required this.collectionBuilder,
    required this.itemBuilder,
    required this.onReorder,
    required this.itemCount,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeInOutExpo,
    this.reorderType = ReordeableCollectionReorderType.reorder,
    this.limitToAxis = Axis.vertical,
    this.scrollDirection = Axis.vertical,
    this.dragPreviewBuilder,
    this.dropPlaceholderBuilder,
    this.shadowItemBuilder,
  });

  @override
  ReordeableCollectionState createState() => ReordeableCollectionState<T>();
}

class ReordeableCollectionState<T> extends State<ReordeableCollection<T>> with SingleTickerProviderStateMixin {
  ReordeableCollectionItemBuilderWrapper<T>? builderWrapper;

  Map<int, Rect> _initialBounds = {};
  Map<int, Offset> _targetOffsets = {};
  Map<int, Offset> _currentOffsets = {};
  _ElementKeys currentKeys = _ElementKeys();
  Offset? _cursorOffset;
  int? _from;
  int? _to;
  Offset _dragOffset = Offset.zero;
  GlobalKey _collectionKey = GlobalKey();
  GlobalKey _shadowCollectionKey = GlobalKey();

  OverlayEntry? _overlay;

  ScrollController _scrollController = ScrollController();
  ScrollController _shadowScrollController = ScrollController();
  bool _disableScrolling = false;
  double? _startScrollOffset = 0;
  late Rect _collectionBounds;

  late AnimationController _rearrangeAnimationController;
  late Animation<double> _rearrangeAnimation;

  int? _shadowIndexOffset;
  List<Widget>? _shadowChildren;

  List<Rect?> _shadowBounds = [];

  bool get isDragging => _from != null;

  late Widget _cachedCollection;

  @override
  Widget build(BuildContext context) {
    // use cached collection if dragging to improve performance
    if (!isDragging) {
      buildCollection();
    }
    return Stack(
      children: [
        Positioned.fill(child: _shadowWidget()),
        _cachedCollection,
      ],
    );
  }

  Offset _calcTransitionOffset(int? index) {
    Offset? oTo = _targetOffsets[index];
    Offset? oFrom = _initialBounds[index]?.center;
    Offset oCurr = _currentOffsets[index] ?? Offset.zero;
    if (oTo == null || oFrom == null) {
      oTo = Offset.zero;
      oFrom = Offset.zero;
    }
    Offset oTarg = oTo - oFrom;
    return Tween(begin: oCurr, end: oTarg).animate(_rearrangeAnimation).value;
  }

  @override
  void didUpdateWidget(covariant ReordeableCollection<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    buildCollection();
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
      if (_startScrollOffset == null) return;
      _shadowScrollController.jumpTo(_scrollController.offset - _startScrollOffset!);
    });

    buildCollection();
  }

  int? toFutureIndex(int? index) {
    if (_from == null || _to == null) return index;
    if (index == _from) return _to;
    if (widget.reorderType == ReordeableCollectionReorderType.swap) {
      if (index == _from)
        index = _to;
      else if (index == _to) index = _from;
    } else {
      if (index! > _from! && index <= _to!) {
        index -= 1;
      } else if (index < _from! && index >= _to!) {
        index += 1;
      }
    }
    return index;
  }

  int? fromFutureIndex(int? index) {
    if (_from == null || _to == null) return index;
    if (widget.reorderType == ReordeableCollectionReorderType.swap) {
      if (index == _from)
        index = _to;
      else if (index == _to) index = _from;
    } else {
      if (index == _to) {
        index = _from;
      } else if (index! >= _from! && index < _to!) {
        index += 1;
      } else if (index <= _from! && index > _to!) {
        index -= 1;
      }
    }
    return index;
  }

  int? getTargetOffset(int? index) {
    if (_from == null || _to == null) return index;
    if (widget.reorderType == ReordeableCollectionReorderType.swap) {
      if (index == _from)
        index = _to;
      else if (index == _to) index = _from;
    } else {
      if (index! > _from! && index <= _to!) {
        index -= 1;
      } else if (index < _from! && index >= _to!) {
        index += 1;
      }
    }
    return index;
  }

  ReordeableCollectionGestureDetectorBuilder _gestureDetector(GlobalKey? key, int index) {
    return (Widget child) => GestureDetector(
          onTapDown: (_) => setState(() {
            _disableScrolling = true;
            buildCollection();
          }),
          onPanStart: (details) {
            _cursorOffset = details.localPosition;
            _from = index;
            _updateBounds();
            _overlay = OverlayEntry(
              builder: (ctx) => Material(type: MaterialType.transparency, child: _draggableChild(index)),
            );
            Overlay.of(context)!.insert(_overlay!);

            _startShadowWidget();

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
            gm5Utils.eventUtils.debounce(widget.duration.inMilliseconds, _updateHitObject, arguments: [key]);
          },
          onPanEnd: (details) {
            _endDrag();
            _startScrollOffset = null;
          },
          child: child,
        );
  }

  Rect _renderBoxToBounds(RenderBox box) {
    Offset topLeft = box.localToGlobal(Offset.zero);
    Offset bottomRight = topLeft + box.size.bottomRight(Offset.zero);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _updateHitObject(GlobalKey draggingKey) {
    if (_from == null) return;
    Offset renderCenter = _dragOffset + _initialBounds[_from]!.center;
    for (int? index in _initialBounds.keys) {
      if (_initialBounds[index]!.contains(renderCenter)) {
        _setToIndex(index);
        return;
      }
    }
  }

  void _setToIndex(int? to) {
    if (to == _to) return;
    setState(() {
      _to = to;
    });

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _updatePositions();
    });
  }

  void _updatePositions() {
    for (int? index in _initialBounds.keys) {
      _currentOffsets[index!] = _calcTransitionOffset(index);
    }

    for (int? index in _initialBounds.keys) {
      _updateShadowBounds();
      _targetOffsets[index!] = _shadowBounds[index - _shadowIndexOffset!]!.center;
    }

    _rearrangeAnimationController.forward(from: 0);
  }

  void _updateBounds() {
    RenderObject? renderObject = _collectionKey.currentContext?.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      throw Exception('Collection key is not attached. Did you forget to use the ReordeableCollectionBuilder key?');
    }
    _collectionBounds = _renderBoxToBounds(renderObject as RenderBox);

    for (GlobalKey? key in currentKeys.keys) {
      RenderObject? renderObject = key!.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) continue;
      _initialBounds[currentKeys.indexForKey(key)!] = _renderBoxToBounds(renderObject as RenderBox);
    }
  }

  void _updateShadowBounds() {
    _shadowBounds = List.filled(_shadowChildren!.length, null);
    for (int i = 0; i < _shadowChildren!.length; i++) {
      final key = _shadowChildren![i].key as GlobalKey;
      RenderObject? renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) continue;
      _shadowBounds[i] = _renderBoxToBounds(renderObject as RenderBox);
    }
  }

  void _endDrag() async {
    for (int? index in _initialBounds.keys) {
      _currentOffsets[index!] = _calcTransitionOffset(index);
    }
    if (_to == null) {
      _to = _from;
    }
    _currentOffsets[_from!] = _dragOffset;
    int shadowIndex = _from! - _shadowIndexOffset!;
    if (shadowIndex <= _shadowBounds.length)
      _targetOffsets[_from!] = _shadowBounds[shadowIndex]!.center;
    else
      _targetOffsets[_from!] = _initialBounds[_from]!.center;
    int? from = _from;
    _from = null;
    _overlay!.remove();
    await _rearrangeAnimationController.forward(from: 0);
    if (from != _to) {
      widget.onReorder(from!, _to!);
      if (widget.reorderType == ReordeableCollectionReorderType.swap) {
        currentKeys.swap(from, _to);
      } else {
        currentKeys.move(from, _to);
      }
    }
    setState(() {
      _currentOffsets = {};
      _to = null;
      _currentOffsets = {};
      _initialBounds = {};
      _targetOffsets = {};
      _disableScrolling = false;
      buildCollection();
    });
  }

  Widget _draggableChild(int index) {
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _initialBounds[index]!.width,
        height: _initialBounds[index]!.height,
        child: AnimatedBuilder(
          animation: _rearrangeAnimationController,
          builder: (ctx, child) => Transform.translate(
            offset: _from == null
                ? (_initialBounds[index]!.topLeft + _calcTransitionOffset(index))
                : (_dragOffset + _initialBounds[index]!.topLeft),
            child: widget.dragPreviewBuilder != null
                ? widget.dragPreviewBuilder!(context, _from, _cursorOffset)
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

  Widget _shadowWidget() {
    if (_from == null || _shadowChildren == null) return Offstage();
    return widget.collectionBuilder(
      context,
      _shadowCollectionKey,
      (c, i) {
        int fi = fromFutureIndex(i + _shadowIndexOffset!)! - _shadowIndexOffset!;
        // print('$i -> $fi');
        return _shadowChildren![fi];
      },
      _shadowScrollController,
      true,
      _shadowChildren!.length,
    );
  }

  void _startShadowWidget() {
    if (_shadowScrollController.hasClients) {
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
    }

    _shadowIndexOffset = _initialBounds.keys.reduce(math.min);

    _shadowChildren = [];
    for (int? index in _initialBounds.keys.toList()..sort()) {
      _shadowChildren!.add(
        SizedBox(
          key: GlobalKey(),
          width: _initialBounds[index]!.width,
          height: _initialBounds[index]!.height,
          child: index == _from
              ? widget.dropPlaceholderBuilder != null
                  ? widget.dropPlaceholderBuilder!(context, _from, _to)
                  : widget.shadowItemBuilder != null
                      ? widget.shadowItemBuilder!(context, index)
                      : null
              : null,
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _updatePositions();
    });
  }

  void buildCollection() {
    _cachedCollection = widget.collectionBuilder(
      context,
      _collectionKey,
      builderWrapper,
      _scrollController,
      _disableScrolling,
      widget.itemCount,
    );
  }
}

class _ElementKeys {
  Map<int?, GlobalKey?> _indexes = {};
  Map<GlobalKey?, int?> _keys = {};

  GlobalKey? keyForIndex(int index) {
    return _indexes.putIfAbsent(
      index,
      () {
        GlobalKey key = GlobalKey();
        _keys[key] = index;
        return key;
      },
    );
  }

  int? indexForKey(GlobalKey? key) => _keys[key];

  List<GlobalKey?> get keys => _keys.keys.toList();

  void swap(int? from, int? to) {
    if (from == to) return;
    final _fk = _indexes[from];
    final _tk = _indexes[to];
    _indexes[from] = _tk;
    _indexes[to] = _fk;
    _keys[_tk] = from;
    _keys[_fk] = to;
  }

  void move(int? from, int? to) {
    if (from == to) return;
    GlobalKey? replacedKey = _indexes[to];
    _indexes[to] = _indexes[from];
    _keys[_indexes[to]] = to;

    int diff = to! - from!;
    for (int i = to - diff.sign; (i - to).abs() <= diff.abs(); i -= diff.sign) {
      GlobalKey? currentKey = replacedKey;
      replacedKey = _indexes[i];
      _indexes[i] = currentKey;
      _keys[currentKey] = i;
    }
  }
}
