/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/search_condition.dart';
import 'package:proxypin/ui/component/search_history.dart';
import 'package:proxypin/ui/component/utils.dart';

import '../../component/model/search_model.dart';

class MobileSearch extends StatefulWidget {
  final Function(SearchModel searchModel)? onSearch;
  final bool showSearch;

  const MobileSearch({super.key, this.onSearch, this.showSearch = false});

  @override
  State<StatefulWidget> createState() {
    return MobileSearchState();
  }
}

class MobileSearchState extends State<MobileSearch> {
  SearchModel searchModel = SearchModel();
  bool _searched = false;
  final TextEditingController _keywordController = TextEditingController();
  bool _changing = false;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.showSearch) {
        showSearch();
      }
    });
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final list = await SearchHistory.load();
    if (mounted && list != _history) {
      setState(() => _history = list);
    }
  }

  @override
  dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.only(left: 0),
        child: TextFormField(
            controller: _keywordController,
            textAlignVertical: TextAlignVertical.center,
            cursorHeight: 20,
            keyboardType: TextInputType.url,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            onChanged: (val) {
              searchModel.keyword = val;
              if (!_changing) {
                _changing = true;
                Future.delayed(const Duration(milliseconds: 500), () {
                  _changing = false;
                  if (!_searched) {
                    searchModel.searchOptions = {Option.url, Option.method, Option.requestHeader, Option.requestBody, Option.responseBody};
                  }
                  widget.onSearch?.call(searchModel);
                });
              }
            },
            decoration: InputDecoration(
                border: InputBorder.none,
                prefixIcon: InkWell(
                    onTap: showSearch,
                    child: Icon(Icons.search, color: _searched ? Colors.green : Theme.of(context).colorScheme.primary)),
                hintText: 'Search')));
  }

  void showSearch() {
    showModalBottomSheet(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        isScrollControlled: true,
        context: context,
        builder: (context) {
          if (!_searched) {
            searchModel.searchOptions = {Option.url};
          }
          return Padding(
              padding: MediaQuery.of(context).viewInsets,
              child: Container(
                  constraints: const BoxConstraints(minHeight: 450, maxHeight: 480),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // 搜索历史（上游 #217）
                    if (_history.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 15, right: 15, top: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.history, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            const Text('搜索历史', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => showConfirmDialog(context,
                                  title: '删除',
                                  content: '清空搜索历史？',
                                  onConfirm: () async {
                                    await SearchHistory.clear();
                                    if (mounted) setState(() => _history = []);
                                  }),
                              child: const Icon(Icons.delete_outline, size: 14, color: Colors.grey),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final k in _history)
                                ActionChip(
                                  label: Text(k, style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _keywordController.text = k;
                                    searchModel.keyword = k;
                                    if (!_searched) {
                                      searchModel.searchOptions = {Option.url, Option.method, Option.requestHeader, Option.requestBody, Option.responseBody};
                                    }
                                    widget.onSearch?.call(searchModel);
                                  },
                                ),
                            ],
                          ),
                        ]),
                      ),
                    Flexible(
                      child: SearchConditions(
                        padding: const EdgeInsets.only(left: 15, right: 15, top: 10),
                        searchModel: searchModel,
                        onSearch: (val) {
                          setState(() {
                            searchModel = val;
                            _searched = searchModel.isNotEmpty;
                            _keywordController.text = searchModel.keyword ?? '';
                            widget.onSearch?.call(searchModel);
                          });
                          // 记录明确的搜索动作（上游 #217）
                          final kw = (searchModel.keyword ?? '').trim();
                          if (kw.isNotEmpty) {
                            SearchHistory.record(kw).then((_) => _loadHistory());
                          }
                        },
                      ),
                    ),
                  ])));
        });
  }
}
