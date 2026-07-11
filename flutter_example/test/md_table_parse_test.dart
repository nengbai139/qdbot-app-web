import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:qdbot_app_example/ui/chat_helpers.dart';

int countTables(List<md.Node> nodes) {
  var c = 0;
  void walk(md.Node node) {
    if (node is md.Element) {
      if (node.tag == 'table') c++;
      for (final ch in node.children ?? []) {
        walk(ch);
      }
    }
  }
  for (final n in nodes) {
    walk(n);
  }
  return c;
}

List<md.Node> parseMd(String input) =>
    md.Document(extensionSet: md.ExtensionSet.gitHubWeb).parse(input);

void main() {
  test('indented template rows break GFM unless stripped', () {
    const indented = '''#### 领涨板块 TOP5
      | 排名 | 板块名称 | 涨跌幅 | 领涨股 |
      |-----|---------|--------|--------|
      | 1 | 银行 | 2.50% | 招商银行 |


      | 2 | 地产 | 1.20% | 万科A |
''';
    expect(countTables(parseMd(indented)), 0);
    expect(countTables(parseMd(normalizeMarkdownContent(indented))), 1);
  });

  test('range template blank lines inside table', () {
    const sectorSample = '''#### 领涨板块 TOP5
| 排名 | 板块名称 | 涨跌幅 | 领涨股 |
|-----|---------|--------|--------|
| 1 | 银行 | 2.50% | 招商银行 |


| 2 | 地产 | 1.20% | 万科A |


| 3 | 保险 | 0.80% | 中国平安 |
''';
    final fixed = normalizeMarkdownContent(sectorSample);
    expect(countTables(parseMd(sectorSample)), 1);
    expect(countTables(parseMd(fixed)), 1);
    expect(fixed.contains('| 2 | 地产 |\n\n\n| 3 |'), isFalse);
  });

  test('full market sample parses all tables', () {
    const fullMarket = '''## 今日股市
⏰ 2026-07-01 15:04:05

| 指数 | 点位 | 涨跌幅 | 成交额 |
|-----|------|--------|--------|
| 上证指数 | 3200 | +0.5% | 4000亿 |
| **全市场** | **偏强** | **↑3000 ↓2000** | — |

#### 领涨板块 TOP5
| 排名 | 板块名称 | 涨跌幅 | 领涨股 |
|-----|---------|--------|--------|
| 1 | 银行 | 2.50% | 招商银行 |

| 2 | 地产 | 1.20% | 万科A |

#### 概念题材榜 TOP5
| 排名 | 概念名称 | 涨跌幅 | 主力净流入 |
|-----|---------|--------|-----------|
| 1 | AI | 3.1% | 12亿 |
''';
    final fixed = normalizeMarkdownContent(fullMarket);
    expect(countTables(parseMd(fixed)), greaterThanOrEqualTo(3));
  });
}
