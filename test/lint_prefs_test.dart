import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/code_lint_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LintPrefs.resetForTest();
  });

  tearDown(LintPrefs.resetForTest);

  test('没有任何设置时所有语言都没有关闭项', () {
    expect(LintPrefs.disabledFor('dart'), isEmpty);
    expect(LintPrefs.hasOverride('dart'), isFalse);
  });

  test('没单独设置过的语言继承默认集合', () async {
    await LintPrefs.applyToAll({'missing-semicolon'});
    expect(LintPrefs.disabledFor('dart'), {'missing-semicolon'});
    expect(LintPrefs.disabledFor('python'), {'missing-semicolon'});
    expect(LintPrefs.hasOverride('dart'), isFalse);
  });

  test('单独设置某语言后有自己的集合（C# 关分号不影响 Python）', () async {
    await LintPrefs.applyToAll({'missing-semicolon'});
    await LintPrefs.setFor('csharp', {'missing-semicolon'});
    expect(LintPrefs.disabledFor('python'), {'missing-semicolon'});
    expect(LintPrefs.hasOverride('csharp'), isTrue);

    // 把默认改成「什么都不关」，c# 的独立设置必须保留
    await LintPrefs.applyToAll(<String>{});
    expect(LintPrefs.disabledFor('python'), isEmpty);
    expect(LintPrefs.disabledFor('csharp'), {'missing-semicolon'});
  });

  test('applyToAll 会清掉所有语言的独立设置', () async {
    await LintPrefs.setFor('dart', {'unclosed-bracket'});
    await LintPrefs.setFor('python', {'missing-semicolon'});
    expect(LintPrefs.overrides(), ['dart', 'python']);

    await LintPrefs.applyToAll({'full-width-punctuation'});
    expect(LintPrefs.overrides(), isEmpty);
    expect(LintPrefs.disabledFor('dart'), {'full-width-punctuation'});
  });

  test('把某语言设成空集合等于取消独立设置（回去继承默认）', () async {
    await LintPrefs.applyToAll({'missing-semicolon'});
    await LintPrefs.setFor('dart', {'unclosed-bracket'});
    expect(LintPrefs.disabledFor('dart'), {'unclosed-bracket'});

    await LintPrefs.setFor('dart', <String>{});
    expect(LintPrefs.hasOverride('dart'), isFalse);
    expect(LintPrefs.disabledFor('dart'), {'missing-semicolon'});
  });

  test('语言标识统一小写，空串落到默认集合', () {
    expect(LintPrefs.normalize('Dart'), 'dart');
    expect(LintPrefs.normalize('  CSharp '), 'csharp');
    expect(LintPrefs.normalize(''), LintPrefs.globalKey);
    expect(LintPrefs.normalize('   '), LintPrefs.globalKey);
  });

  test('clearOverrides 只留默认集合', () async {
    await LintPrefs.applyToAll({'a-rule'});
    await LintPrefs.setFor('dart', {'b-rule'});
    await LintPrefs.clearOverrides();
    expect(LintPrefs.overrides(), isEmpty);
    expect(LintPrefs.disabledFor('dart'), {'a-rule'});
  });
}
