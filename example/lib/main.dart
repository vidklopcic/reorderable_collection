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
  List<String> _sortableItems = List.generate(100, (index) => '$index');

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
        body: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: 'Grid'),
                  Tab(text: 'Two columns'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ReordeableCollection(
                      limitToAxis: null,
                      itemCount: _sortableItems.length,
                      reorderType: ReordeableCollectionReorderType.reorder,
                      itemBuilder: (context, key, dragDetector, index, dragging) => dragDetector(
                        StatefulSample(key: key, value: _sortableItems[index]),
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
                      collectionBuilder: (context, key, itemBuilder, scrollController, disableScroll, itemCount) {
                        print('here');
                        return SingleChildScrollView(
                          physics: disableScroll ? NeverScrollableScrollPhysics() : null,
                          child: Wrap(
                            key: key,
                            children: _sortableItems.mapIndexed((index, item) => itemBuilder(context, index)).toList(),
                          ),
                        );
                      },
                      onReorder: (a, b) {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatefulSample extends StatefulWidget {
  final String value;

  const StatefulSample({Key? key, required this.value}) : super(key: key);

  @override
  _StatefulSampleState createState() => _StatefulSampleState();
}

class _StatefulSampleState extends State<StatefulSample> {
  String? _value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() {}),
      child: Container(
        width: 100,
        height: 100,
        margin: const EdgeInsets.all(8),
        alignment: Alignment.center,
        color: Colors.black12,
        child: Text(_value ?? ''),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }
}
