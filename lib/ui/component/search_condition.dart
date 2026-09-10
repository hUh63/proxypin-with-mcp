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
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/lang.dart';

import 'model/search_model.dart';

/// @author wanghongen
/// 2023/8/6
class SearchConditions extends StatefulWidget {
  final SearchModel searchModel;
  final Function(SearchModel searchModel)? onSearch;
  final EdgeInsetsGeometry? padding;

  const SearchConditions({super.key, required this.searchModel, this.onSearch, this.padding});

  @override
  State<StatefulWidget> createState() {
    return SearchConditionsState();
  }
}

class SearchConditionsState extends State<SearchConditions> {
  final Map<String, ContentType?> requestContentMap = {
    'JSON': ContentType.json,
    'FORM-URL': ContentType.formUrl,
    'FORM-DATA': ContentType.formData,
  };

  final Map<String, ContentType?> responseContentMap = {
    'JSON': ContentType.json,
    'IMAGE': ContentType.image,
    'HTML': ContentType.html,
    'XML': ContentType.xml,
    'JS': ContentType.js,
    'CSS': ContentType.css,
    'TEXT': ContentType.text,
    'SSE': ContentType.sse,
  };

  late SearchModel searchModel;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    searchModel = widget.searchModel.clone();
  }

  @override
  Widget build(BuildContext context) {
    requestContentMap[localizations.all] = null;
    responseContentMap[localizations.all] = null;
    Color primaryColor = ColorScheme.of(context).primary;
    return Container(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // keyword
          TextFormField(
            initialValue: searchModel.keyword,
            onChanged: (val) => searchModel.keyword = val,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.all(10),
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              hintText: localizations.keyword,
              suffixIcon: Obx(() => ToggleButtons(
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
                    borderRadius: BorderRadius.circular(8),
                    renderBorder: false,
                    selectedColor: primaryColor,
                    isSelected: [searchModel.caseSensitive.value, searchModel.isRegExp.value],
                    onPressed: (index) {
                      switch (index) {
                        case 0:
                          searchModel.caseSensitive.value = !searchModel.caseSensitive.value;
                          break;
                        case 1:
                          searchModel.isRegExp.value = !searchModel.isRegExp.value;
                          break;
                      }
                    },
                    children: [
                      Tooltip(message: 'Case Sensitive', child: const Text('Aa')),
                      Tooltip(message: localizations.regExp, child: const Text('.*')),
                    ],
                  )),
            ),
          ),
          // 排序选项 (#843)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('排序:', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Row(
                children: [
                  // 排序字段
                  DropdownMenu<String>(
                    initialValue: searchModel.sortBy.name,
                    items: [
                      DropdownMenuEntry(value: 'time', label: '时间'),
                      DropdownMenuEntry(value: 'duration', label: '耗时'),
                      DropdownMenuEntry(value: 'statusCode', label: '状态码'),
                    ],
                    onSelected: (val) {
                      if (val != null) {
                        setState(() {
                          searchModel.sortBy = SortBy.values.firstWhere((e) => e.name == val);
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  // 排序方向
                  DropdownMenu<String>(
                    initialValue: searchModel.sortOrder.name,
                    items: [
                      DropdownMenuEntry(value: 'desc', label: '降序↓'),
                      DropdownMenuEntry(value: 'asc', label: '升序↑'),
                    ],
                    onSelected: (val) {
                      if (val != null) {
                        setState(() {
                          searchModel.sortOrder = SortOrder.values.firstWhere((e) => e.name == val);
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          // protocol quick selectors placed under the keyword input (very compact)
          protocolsWidget(),
          const SizedBox(height: 10),
          // keyword scope
          Text(localizations.keywordSearchScope),
          const SizedBox(height: 10),
          Wrap(
            children: [
              options('URL', Option.url),
              options(localizations.requestHeader, Option.requestHeader),
              options(localizations.requestBody, Option.requestBody),
              options(localizations.responseHeader, Option.responseHeader),
              options(localizations.responseBody, Option.responseBody),
            ],
          ),
          const SizedBox(height: 10),

          // request method
          row(
            Text('${localizations.requestMethod}:'),
            DropdownMenu<String>(
              initialValue: searchModel.requestMethod?.name ?? localizations.all,
              items: [DropdownMenuEntry(value: localizations.all, label: localizations.all), ...HttpMethod.methods().map((e) => DropdownMenuEntry(value: e.name, label: e.name))],
              onSelected: (String value) {
                searchModel.requestMethod = value == localizations.all ? null : HttpMethod.valueOf(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          // request type
          row(
            Text('${localizations.requestType}:'),
            DropdownMenu<String>(
              initialValue: Maps.getKey(requestContentMap, searchModel.requestContentType) ?? localizations.all,
              items: [DropdownMenuEntry(value: localizations.all, label: localizations.all), ...requestContentMap.keys.map((k) => DropdownMenuEntry(value: k, label: k))],
              onSelected: (String value) {
                searchModel.requestContentType = requestContentMap[value];
              },
            ),
          ),

          // response type
          row(
            Text('${localizations.responseType}:'),
            DropdownMenu<String>(
              initialValue: Maps.getKey(responseContentMap, searchModel.responseContentType) ?? localizations.all,
              items: [DropdownMenuEntry(value: localizations.all, label: localizations.all), ...responseContentMap.keys.map((k) => DropdownMenuEntry(value: k, label: k))],
              onSelected: (String value) {
                searchModel.responseContentType = responseContentMap[value];
              },
            ),
          ),
          const SizedBox(height: 10),

          // status code range
          row(
            Text('${localizations.statusCode}: '),
            Row(children: [
              SizedBox(
                  width: 55,
                  height: 32,
                  child: textField(
                      initialValue: searchModel.statusCodeFrom?.toString(),
                      onChanged: (val) => searchModel.statusCodeFrom = int.tryParse(val))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text(" - ")),
              SizedBox(
                  width: 55,
                  height: 32,
                  child: textField(
                      initialValue: searchModel.statusCodeTo?.toString(),
                      onChanged: (val) => searchModel.statusCodeTo = int.tryParse(val))),
            ]),
          ),
          const SizedBox(height: 10),

          // duration range (ms)
          row(
            Text('${localizations.duration} (ms): '),
            Row(children: [
              SizedBox(
                  width: 55,
                  height: 32,
                  child: textField(
                      initialValue: searchModel.durationFromMs?.toString(),
                      onChanged: (val) => searchModel.durationFromMs = int.tryParse(val))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text(" - ")),
              SizedBox(
                  width: 55,
                  height: 32,
                  child: textField(
                      initialValue: searchModel.durationToMs?.toString(),
                      onChanged: (val) => searchModel.durationToMs = int.tryParse(val))),
            ]),
          ),
          const SizedBox(height: 15),

          // action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(localizations.cancel, style: const TextStyle(fontSize: 14)),
              ),
              TextButton(
                onPressed: () {
                  widget.onSearch?.call(SearchModel());
                  Navigator.pop(context);
                },
                child: Text(localizations.clearSearch, style: const TextStyle(fontSize: 14)),
              ),
              TextButton(
                onPressed: () {
                  widget.onSearch?.call(searchModel);
                  Navigator.pop(context);
                },
                child: Text(localizations.confirm, style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget protocolsWidget() {
    Color primaryColor = ColorScheme.of(context).primary;
    return Wrap(
      spacing: 5,
      runSpacing: 2,
      children: <Widget>[
        FilterChip(
          label: const Text('HTTP'),
          selected: searchModel.protocols.contains(Protocol.http),
          showCheckmark: false,
          selectedColor: primaryColor.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.http) : searchModel.protocols.remove(Protocol.http);
          }),
        ),
        FilterChip(
          label: const Text('HTTPS'),
          selected: searchModel.protocols.contains(Protocol.https),
          showCheckmark: false,
          selectedColor: primaryColor.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.https) : searchModel.protocols.remove(Protocol.https);
          }),
        ),
        FilterChip(
          label: const Text('WS'),
          selected: searchModel.protocols.contains(Protocol.ws),
          showCheckmark: false,
          selectedColor: primaryColor.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.ws) : searchModel.protocols.remove(Protocol.ws);
          }),
        ),
        FilterChip(
          label: const Text('SSE'),
          selected: searchModel.protocols.contains(Protocol.sse),
          showCheckmark: false,
          selectedColor: primaryColor.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.sse) : searchModel.protocols.remove(Protocol.sse);
          }),
        ),
        FilterChip(
          label: const Text('HTTP/1'),
          selected: searchModel.protocols.contains(Protocol.http1),
          showCheckmark: false,
          selectedColor: primaryColor.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.http1) : searchModel.protocols.remove(Protocol.http1);
          }),
        ),
        FilterChip(
          label: const Text('H2'),
          selected: searchModel.protocols.contains(Protocol.h2),
          showCheckmark: false,
          selectedColor: primaryColor.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          labelStyle: const TextStyle(fontSize: 12),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          onSelected: (sel) => setState(() {
            sel ? searchModel.protocols.add(Protocol.h2) : searchModel.protocols.remove(Protocol.h2);
          }),
        ),
      ],
    );
  }

  Widget options(String title, Option option) {
    bool isCN = localizations.localeName == 'zh';
    return Container(
        constraints: BoxConstraints(maxWidth: isCN ? 100 : 132, minWidth: 100, maxHeight: 33),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          Checkbox(
              visualDensity: VisualDensity.compact,
              value: searchModel.searchOptions.contains(option),
              onChanged: (val) {
                setState(() {
                  val == true ? searchModel.searchOptions.add(option) : searchModel.searchOptions.remove(option);
                });
              })
        ]));
  }

  Widget row(Widget child, Widget child2) {
    return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [Expanded(flex: 4, child: child), Expanded(flex: 6, child: child2)]);
  }

  Widget textField({String? initialValue, final ValueChanged<String>? onChanged, TextStyle? style}) {
    Color color = Theme.of(context).colorScheme.primary;

    return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 32),
        child: TextFormField(
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
          initialValue: initialValue,
          onChanged: onChanged,
          style: style,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.only(left: 10, right: 10, top: 2, bottom: 2),
            border: OutlineInputBorder(borderSide: BorderSide(width: 1, color: color.withValues(alpha: 0.3))),
          ),
        ));
  }
}

class DropdownMenu<T> extends StatefulWidget {
  final T? initialValue;
  final Iterable<DropdownMenuEntry<T>> items;
  final Function(T value) onSelected;

  const DropdownMenu({super.key, this.initialValue, required this.items, required this.onSelected});

  @override
  State<DropdownMenu<T>> createState() {
    return DropdownMenuState<T>();
  }
}

class DropdownMenuState<T> extends State<DropdownMenu<T>> {
  T? selectValue;

  @override
  void initState() {
    super.initState();
    selectValue = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: '',
      initialValue: selectValue,
      // 菜单宽度下限：保证较长选项（如 FORM-URL / 本地化类型名）在菜单里完整显示
      constraints: const BoxConstraints(minWidth: 200),
      child: Wrap(runAlignment: WrapAlignment.center, children: [
        // 单行省略 + 长按提示：避免长选中值在 Wrap 里换行后被外层固定高度裁切
        Tooltip(
            message: selectValue?.toString() ?? '',
            child: Text(selectValue?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        const Icon(Icons.arrow_drop_down, size: 20)
      ]),
      onSelected: (T value) {
        setState(() {
          widget.onSelected.call(value);
          selectValue = value;
        });
      },
      itemBuilder: (BuildContext context) {
        return widget.items
            .map((entry) => PopupMenuItem<T>(
                height: 35,
                value: entry.value,
                child: Text(entry.label ?? entry.value.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(fontSize: 12))))
            .toList();
      },
    );
  }
}
