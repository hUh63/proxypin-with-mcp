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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/ui/component/search_condition.dart';
import 'package:proxypin/ui/component/search_history.dart';

import '../../component/model/search_model.dart';

/// @author wanghongen
/// 2023/10/8
class Search extends StatefulWidget {
  final Function(SearchModel searchModel)? onSearch;

  const Search({super.key, this.onSearch});

  @override
  State<StatefulWidget> createState() {
    return SearchState();
  }
}

class SearchState extends State<Search> {
  SearchModel searchModel = SearchModel();
  bool searched = false;
  TextEditingController keywordController = TextEditingController();
  bool changing = false;

  /// 搜索历史。桌面端此前完全没有接 SearchHistory（只有移动端接了），
  /// 于是同一个应用在两端行为不一致：手机有历史、桌面没有。
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    keywordController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await SearchHistory.load();
    if (mounted && list != _history) {
      setState(() => _history = list);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).hoverColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          )
        ],
      ),
      child: TextField(
        cursorHeight: 22,
        controller: keywordController,
        onChanged: (val) async {
          searchModel.keyword = val;

          if (!changing) {
            changing = true;
            Future.delayed(const Duration(milliseconds: 500), () {
              changing = false;
              if (!searched) {
                searchModel.searchOptions = {Option.url, Option.method, Option.requestHeader, Option.requestBody, Option.responseBody};
              }
              widget.onSearch?.call(searchModel);
            });
          }
        },
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.all(0),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade400, width: 0.5), borderRadius: BorderRadius.circular(15)),
          border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade400, width: 0.5), borderRadius: BorderRadius.circular(15)),
          prefixIcon: InkWell(
              child: Icon(Icons.search, color: searched ? Colors.green : Theme.of(context).colorScheme.primary),
              onTapDown: (details) {
                searchDialog(details);
              }),
          hintText: 'Search',
          suffixIcon: ContentTypeSelect(onSelected: (contentType) {
            searchModel.responseContentTypes = contentType == null ? {} : {contentType};
            widget.onSearch?.call(searchModel);
          }),
        ),
      ),
    );
  }

  void searchDialog([TapDownDetails? details]) {
    if (!searched) {
      searchModel.searchOptions = {Option.url};
    }
    bool isCN = AppLocalizations.of(context)!.localeName == 'zh';
    var height = MediaQuery.of(context).size.height;
    height = !isCN ? height - 501 : height - 468;
    if (Platform.isMacOS) {
      height -= 30;
    }
    final loc = AppLocalizations.of(context)!;
    showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(65, height, 65, height),
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 330),
        items: [
          PopupMenuItem(
              padding: const EdgeInsets.only(left: 15, right: 15, top: 10, bottom: 5),
              enabled: false,
              child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                  child: SizedBox(
                      child: SearchConditions(
                          searchModel: searchModel,
                          onSearch: (val) {
                            setState(() {
                              searchModel = val;
                              searched = searchModel.isNotEmpty;
                              keywordController.text = searchModel.keyword ?? '';
                              widget.onSearch?.call(searchModel);
                            });
                            // 主动搜索时记录历史（与移动端行为保持一致）
                            final kw = (searchModel.keyword ?? '').trim();
                            if (kw.isNotEmpty) {
                              SearchHistory.record(kw).then((_) => _loadHistory());
                            }
                          })))),
          // 搜索历史：点某条直接按该关键词搜索；末尾提供「清空搜索历史」
          if (_history.isNotEmpty) ...[
            const PopupMenuDivider(),
            for (final h in _history)
              PopupMenuItem<String>(
                  value: h,
                  height: 34,
                  padding: const EdgeInsets.only(left: 15, right: 15),
                  child: Row(children: [
                    const Icon(Icons.history, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(h,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13))),
                  ])),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
                value: '__clear__',
                height: 34,
                padding: const EdgeInsets.only(left: 15, right: 15),
                child: Row(children: [
                  const Icon(Icons.delete_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(loc.clearSearchHistory, style: const TextStyle(fontSize: 13)),
                ])),
          ]
        ]).then((value) {
      if (!mounted || value == null) return;
      if (value == '__clear__') {
        SearchHistory.clear().then((_) => _loadHistory());
        return;
      }
      // 选了一条历史关键词：填回输入框并立即搜索
      setState(() {
        searchModel.keyword = value;
        keywordController.text = value;
        searched = searchModel.isNotEmpty;
        widget.onSearch?.call(searchModel);
      });
    });
  }
}

class ContentTypeSelect extends StatefulWidget {
  final Function(ContentType? contentType) onSelected;

  const ContentTypeSelect({super.key, required this.onSelected});

  @override
  State<StatefulWidget> createState() {
    return ContentTypeState();
  }
}

class ContentTypeState extends State<ContentTypeSelect> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String? value;
  List<String>? types;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    value ??= localizations.all;
    types ??= ["JSON", "IMAGE", "HTML", "XML", "JS", "CSS", "TEXT",  localizations.all];

    return PopupMenuButton(
      initialValue: value,
      offset: Offset(-10, (types!.length - types!.indexOf(value!)) * -30.0 - 10),
      tooltip: localizations.responseType,
      constraints: const BoxConstraints(maxWidth: 75),
      child: Wrap(runAlignment: WrapAlignment.center, children: [
        Text(value!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const Icon(Icons.arrow_drop_up, size: 20)
      ]),
      onSelected: (String value) {
        if (this.value == value) {
          return;
        }
        setState(() {
          this.value = value;
        });
        widget.onSelected(value == localizations.all ? null : ContentType.valueOf(value));
      },
      itemBuilder: (BuildContext context) {
        return types!.map(item).toList();
      },
    );
  }

  PopupMenuItem<String> item(String value) {
    return PopupMenuItem(
      height: 30,
      value: value,
      child: Text(value, style: const TextStyle(fontSize: 12)),
    );
  }
}
