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
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/repeat_task_manager.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

///高级重放
/// @author wang
class MobileCustomRepeat extends StatefulWidget {
  final Function onRepeat;
  final SharedPreferences prefs;

  /// 任务标题（用于「发送队列」展示），如 `GET api.example.com/user`
  final String? taskTitle;

  /// 待发送请求清单（上游 #715），供「发送队列」查看准备发送的请求
  final List<String>? pendingItems;

  const MobileCustomRepeat(
      {super.key, required this.onRepeat, required this.prefs, this.taskTitle, this.pendingItems});

  @override
  State<StatefulWidget> createState() => _CustomRepeatState();
}

class _CustomRepeatState extends State<MobileCustomRepeat> {
  TextEditingController count = TextEditingController(text: '1');
  TextEditingController interval = TextEditingController(text: '0');
  TextEditingController minInterval = TextEditingController(text: '0');
  TextEditingController maxInterval = TextEditingController(text: '1000');
  TextEditingController delay = TextEditingController(text: '0');

  bool fixed = true;
  bool keepSetting = true;
  bool enableRetry = true; // 启用重试 (#892)
  int maxRetries = 3; // 最大重试次数 (#892)
  
  // 增强：指数退避基数 (#892)
  int retryBaseDelayMs = 100;

  // 时间单位：0=毫秒，1=秒，2=分钟 (#887)
  int timeUnit = 0;

  DateTime? time;

  // 重放统计 (#892)
  int successCount = 0;
  int failCount = 0;
  int retryCount = 0;
  
  // 增强：记录最后错误信息 (#892)
  String? lastError;

  // 当前重放任务（#715/#401：登记到发送队列，供随时查看状态）
  RepeatTask? _task;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();

    var customerRepeat = widget.prefs.getString('customerRepeat');
    keepSetting = customerRepeat != null;
    if (customerRepeat != null) {
      Map<String, dynamic> data = jsonDecode(customerRepeat);
      count.text = data['count'];
      interval.text = data['interval'];
      minInterval.text = data['minInterval'];
      maxInterval.text = data['maxInterval'];
      delay.text = data['delay'];
      fixed = data['fixed'] == true;
    }
  }

  @override
  void dispose() {
    count.dispose();
    interval.dispose();
    delay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    return Scaffold(
        appBar: AppBar(
          title: Text(localizations.customRepeat, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          actions: [
            TextButton(
              child: Text(localizations.done),
              onPressed: () {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                if (keepSetting) {
                  widget.prefs.setString(
                      'customerRepeat',
                      jsonEncode({
                        'count': count.text,
                        'interval': interval.text,
                        'minInterval': minInterval.text,
                        'maxInterval': maxInterval.text,
                        'delay': delay.text,
                        'fixed': fixed
                      }));
                } else {
                  widget.prefs.remove('customerRepeat');
                }

                int delayValue = int.parse(delay.text);
                DateTime? schedule;
                if (time != null) {
                  DateTime now = DateTime.now();
                  schedule = DateTime(now.year, now.month, now.day, time!.hour, time!.minute);
                  if (schedule.isBefore(now)) {
                    schedule = schedule.add(const Duration(days: 1));
                  }
                  delayValue += schedule.difference(now).inMilliseconds;
                }

                // 上游 #715/#401：把任务登记到「发送队列」，
                // 记录计划时间与待发送请求清单，关页后仍可查看进度与状态
                _task = RepeatTaskManager.instance.create(
                  title: widget.taskTitle ?? localizations.customRepeat,
                  total: int.parse(count.text),
                  scheduledAt: schedule,
                  pending: widget.pendingItems ?? const [],
                );

                Future.delayed(Duration(milliseconds: delayValue), () => submitTask(int.parse(count.text)));
                Navigator.of(context).pop();
              },
            )
          ],
        ),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(15),
            child: Form(
              key: formKey,
              child: Column(
                children: <Widget>[
                  field(localizations.repeatCount, textField(count)), //次数
                  const SizedBox(height: 6),
                  intervalWidget(), //间隔
                  const SizedBox(height: 6),
                  field(localizations.repeatDelay, textField(delay)), //延时
                  const SizedBox(height: 6),
                  field(
                      localizations.scheduleTime,
                      InkWell(
                          onTap: _pickScheduleDateTime,
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.only(left: 10, right: 10),
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withAlpha((0.5 * 255).round()),
                                    width: 1.0),
                                borderRadius: BorderRadius.circular(4)),
                            child: Row(
                              children: [
                                Text(time == null
                                    ? ''
                                    : "${time!.year}-${_two(time!.month)}-${_two(time!.day)} ${_two(time!.hour)}:${_two(time!.minute)}"),
                                const Expanded(child: SizedBox()),
                                if (time != null)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        time = null;
                                      });
                                    },
                                    child: const Icon(Icons.clear, size: 18),
                                  ),
                                if (time == null)
                                  Icon(Icons.access_time, size: 18, color: Theme.of(context).colorScheme.primary),
                              ],
                            ),
                          ))), //指定时间
                  const SizedBox(height: 6),
                  //记录选择
                  Row(children: [
                    Text(localizations.keepCustomSettings),
                    Expanded(
                        child: Checkbox(
                            value: keepSetting,
                            onChanged: (val) {
                              setState(() {
                                keepSetting = val == true;
                              });
                            })),
                  ])
                ],
              ),
            )));
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  // 定时重放 - 支持时间单位 (#887) + 重试机制 (#892)
  void submitTask(int counter) {
    // 用户已在「发送队列」取消该任务
    if (_task?.status == RepeatTaskStatus.canceled) {
      return;
    }
    if (counter <= 0) {
      if (_task != null) RepeatTaskManager.instance.markCompleted(_task!);
      _showRepeatResult();
      return;
    }
    // 首次执行：任务从「等待发送」转为「发送中」
    if (_task != null && _task!.status == RepeatTaskStatus.scheduled) {
      RepeatTaskManager.instance.markRunning(_task!);
    }
    _executeWithRetry(counter);
  }

  // 带重试机制的执行 (#892) - 增强：指数退避策略
  Future<void> _executeWithRetry(int counter, {int attempt = 1}) async {
    try {
      await widget.onRepeat.call();
      successCount++;
      lastError = null; // 清除错误记录
      if (_task != null) RepeatTaskManager.instance.record(_task!, ok: true);
      _scheduleNext(counter - 1);
    } catch (e) {
      failCount++;
      lastError = e.toString();
      if (_task != null) RepeatTaskManager.instance.record(_task!, ok: false, error: lastError);
      if (enableRetry && attempt < maxRetries) {
        retryCount++;
        if (_task != null) RepeatTaskManager.instance.recordRetry(_task!);
        // 增强：指数退避延迟 (100ms, 200ms, 400ms...) (#892)
        int delayMs = retryBaseDelayMs * attempt;
        Future.delayed(Duration(milliseconds: delayMs), () {
          _executeWithRetry(counter, attempt: attempt + 1);
        });
      } else {
        // 增强：记录失败原因 (#892)
        logger.e('重放失败 (尝试 $attempt/$maxRetries): $lastError');
        _scheduleNext(counter - 1);
      }
    }
  }

  // 调度下一次重放
  void _scheduleNext(int counter) {
    if (counter <= 0) return;
    int intervalValue = int.parse(interval.text);
    int multiplier = timeUnit == 0 ? 1 : (timeUnit == 1 ? 1000 : 60000);
    intervalValue = intervalValue * multiplier;
    if (!fixed) {
      int min = int.parse(minInterval.text) * multiplier;
      int max = int.parse(maxInterval.text) * multiplier;
      intervalValue = Random().nextInt(max - min) + min;
    }
    Future.delayed(Duration(milliseconds: intervalValue), () {
      submitTask(counter);
    });
  }

  // 显示重放结果统计 (#892) - 增强：显示最后错误信息
  void _showRepeatResult() {
    if (successCount > 0 || failCount > 0) {
      String message = '成功：$successCount\n失败：$failCount\n重试：$retryCount';
      if (lastError != null && failCount > 0) {
        // 增强：截断错误信息避免过长 (#892)
        String errorPreview = lastError!.length > 50 ? '${lastError!.substring(0, 50)}...' : lastError!;
        message += '\n错误：$errorPreview';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4), // 增强：延长显示时间以便查看错误
          backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
        ),
      );
      successCount = 0;
      failCount = 0;
      retryCount = 0;
      lastError = null;
    }
  }


  //间隔widget
  Widget intervalWidget() {
    return Row(
      children: [
        SizedBox(width: 83, child: Text(localizations.repeatInterval)),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 时间单位选择器 (#887)
          Row(children: [
            SizedBox(
                width: 70,
                child: DropdownButton<int>(
                  value: timeUnit,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('毫秒', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 1, child: Text('秒', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 2, child: Text('分钟', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => timeUnit = val);
                    }
                  },
                )),
            const Spacer(),
          ]),
          const SizedBox(height: 5),
          //Checkbox样式 固定和随机
          Row(children: [
            SizedBox(
                width: 112,
                height: 35,
                child: Transform.scale(
                    scale: 0.82,
                    child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("${localizations.fixed}:"),
                        value: fixed,
                        dense: true,
                        onChanged: (val) {
                          setState(() {
                            fixed = true;
                          });
                        }))),
            Expanded(child: textField(interval, style: const TextStyle(fontSize: 13))),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            SizedBox(
                width: 112,
                child: Transform.scale(
                    scale: 0.82,
                    child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("${localizations.random}:"),
                        value: !fixed,
                        dense: true,
                        onChanged: (val) {
                          setState(() {
                            fixed = false;
                          });
                        }))),
            Flexible(child: textField(minInterval, style: const TextStyle(fontSize: 13))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text("-")),
            Flexible(child: textField(maxInterval, style: const TextStyle(fontSize: 13))),
          ]),
        ])),
      ],
    );
  }


  Future<void> _pickScheduleDateTime() async {
    DateTime now = DateTime.now();
    DateTime temp = time ?? now;
    if (temp.isBefore(now)) {
      temp = now;
    }

    DateTime? selected = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (BuildContext context) {
        DateTime current = temp;
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.dateAndTime,
                    use24hFormat: true,
                    initialDateTime: temp,
                    minimumDate: now,
                    maximumDate: now.add(const Duration(days: 365)),
                    onDateTimeChanged: (DateTime value) {
                      current = value;
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(localizations.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, current),
                      child: Text(localizations.done),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        time = selected;
      });
    }
  }

  Widget field(String label, Widget child) {
    return Row(
      children: [
        SizedBox(width: 95, child: Text("$label :")),
        Expanded(child: child),
      ],
    );
  }

  FormField textField(TextEditingController? controller, {TextStyle? style}) {
    Color color = Theme.of(context).colorScheme.primary;

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: style,
      decoration: InputDecoration(
          errorStyle: const TextStyle(height: 2, fontSize: 0),
          contentPadding: const EdgeInsets.only(left: 10, right: 10, top: 5, bottom: 5),
          border: OutlineInputBorder(borderSide: BorderSide(width: 1, color: color.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(width: 1.5, color: color.withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(width: 2, color: color))),
      validator: (val) => val == null || val.isEmpty ? localizations.cannotBeEmpty : null,
    );
  }
}
