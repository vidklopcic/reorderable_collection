import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
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
  String _platformVersion = 'Unknown';
  List<String> _sortableItems = List.generate(1000, (index) => 'Item $index');

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
          itemBuilder: (context, key, dragDetector, index) => dragDetector(ListTile(
            key: key,
            title: Text(
              _sortableItems[index],
            ),
          )),
          collectionBuilder: (context, key, itemBuilder, scrollController) => ListView.builder(
            key: key,
            controller: scrollController,
            itemCount: _sortableItems.length,
            itemBuilder: itemBuilder,
          ),
          onReorder: _sortableItems.move,
        ),
      ),
    );
  }
}
