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
  List<String> _sortableItems = List.generate(1000, (index) => '$index');

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
        body: ReordeableCollectionController(
          itemCount: _sortableItems.length,
          itemBuilder: (context, key, dragDetector, index) => dragDetector(
            Container(
              key: key,
              padding: EdgeInsets.symmetric(vertical: (50.0 * int.parse(_sortableItems[index])) % 100),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black45),
                ),
              ),
              child: ListTile(
                title: Text(
                  _sortableItems[index],
                ),
              ),
            ),
          ),
          collectionBuilder: (context, key, itemBuilder, scrollController, disableScroll, itemCount) =>
              ListView.builder(
            physics: disableScroll ? NeverScrollableScrollPhysics() : null,
            key: key,
            controller: scrollController,
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
          onReorder: _sortableItems.move,
        ),
      ),
    );
  }
}
