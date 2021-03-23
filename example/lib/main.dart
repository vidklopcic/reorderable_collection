import 'dart:math';

import 'package:flutter/material.dart';
import 'package:reordeable_collection/reordeable_collection.dart';
import 'package:gm5_utils/extended_functionality/collections.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Random _random = Random();
  String _platformVersion = 'Unknown';
  List<String> _sortableItems = List.generate(20, (index) => '$index');

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('General reordeable example'),
        ),
        body: ReordeableCollection(
          limitToAxis: null,
          itemCount: _sortableItems.length,
          reorderType: ReordeableCollectionReorderType.swap,
          itemBuilder: (context, key, dragDetector, index) => dragDetector(
            StatefulSample(
              key: key,
              value: _sortableItems[index],
            ),
          ),
          dropPlaceholderBuilder: (context, from, to) => Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  spreadRadius: -10,
                  blurRadius: 15,
                ),
              ],
            ),
          ),
          collectionBuilder: (context, key, itemBuilder, scrollController, disableScroll, itemCount) => Wrap(
            key: key,
            children: _sortableItems
                .mapIndexed(
                  (index, item) => itemBuilder(context, index),
                )
                .toList(),
          ),
          onReorder: (a, b) {},
        ),
      ),
    );
  }
}

class StatefulSample extends StatefulWidget {
  final String value;

  const StatefulSample({Key key, this.value}) : super(key: key);

  @override
  _StatefulSampleState createState() => _StatefulSampleState();
}

class _StatefulSampleState extends State<StatefulSample> {
  String _value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() {}),
      child: Container(
        width: 50,
        height: 50,
        margin: const EdgeInsets.all(8),
        alignment: Alignment.center,
        color: Colors.black12,
        child: Text(_value),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }
}
