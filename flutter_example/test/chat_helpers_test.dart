import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/ui/chat_helpers.dart';

void main() {
  test('sessionLastPreview image url', () {
    expect(
      sessionLastPreview({'lastMsg': 'https://cdn.example.com/a.jpg'}),
      '[图片]',
    );
  });

  test('sessionLastPreview content type', () {
    expect(
      sessionLastPreview({'lastMsg': 'x', 'lastMsgType': 'image'}),
      '[图片]',
    );
  });

  test('sessionMatchesQuery userCode and preview', () {
    expect(
      sessionMatchesQuery(
        {
          'peerName': 'Alice',
          'peerUserCode': 'U12345',
          'lastMsg': 'https://cdn.example.com/a.jpg',
        },
        'u12345',
      ),
      isTrue,
    );
    expect(
      sessionMatchesQuery(
        {'lastMsg': 'https://cdn.example.com/a.jpg', 'lastMsgType': 'image'},
        '图片',
      ),
      isTrue,
    );
    expect(sessionMatchesQuery({'peerName': 'Bob'}, 'alice'), isFalse);
  });

  test('userRecordMatchesQuery nickname', () {
    expect(
      userRecordMatchesQuery({'nickname': '白木轮', 'userId': 'u1'}, '白木'),
      isTrue,
    );
    expect(userRecordMatchesQuery({'nickname': '白木轮'}, 'alice'), isFalse);
  });

  test('sessionMatchesQuery group notice', () {
    expect(
      sessionMatchesQuery(
        {'groupName': '研发群', 'notice': '明天开会', 'lastMsg': ''},
        '开会',
        group: true,
      ),
      isTrue,
    );
  });

  test('hasMarkdown detects headings and tables', () {
    expect(hasMarkdown('## 结论\n- foo'), isTrue);
    expect(hasMarkdown('| a | b |\n|---|---|'), isTrue);
    expect(hasMarkdown('plain text only'), isFalse);
  });

  test('isAgentProgressContent distinguishes progress vs finance reply', () {
    expect(isAgentProgressContent('🔄 🔧 正在调用财经查询技能获取实时数据...'), isTrue);
    expect(isAgentProgressContent('正在处理中...'), isTrue);
    expect(isAgentProgressContent(''), isTrue);
    expect(isAgentProgressContent('45%'), isTrue);
    const finance = '''## 今日财经摘要
| 指数 | 涨跌 |
| --- | --- |
| 上证 | 1.20% |
| 银行板块 | 2.50% |
''';
    expect(isAgentProgressContent(finance), isFalse);
  });

  test('mergeAiMessagesWithPending keeps optimistic user when server has progress tail', () {
    final local = [
      {'role': 'user', 'content': 'old', 'id': 1},
      {'role': 'assistant', 'content': '🔄 progress', 'id': 2},
      {'role': 'user', 'content': '今日股市'},
    ];
    final server = [
      {'role': 'user', 'content': 'old', 'id': 1},
      {'role': 'assistant', 'content': '🔄 progress', 'id': 2},
      {'role': 'assistant', 'content': '🔄 正在调用财经查询技能', 'id': 3},
    ];
    final merged = mergeAiMessagesWithPending(local, server);
    expect(merged.last['content'], '今日股市');
    expect(aiServerCaughtUpWithLocal(local, server), isFalse);
  });

  test('mergeAiMessagesWithPending keeps optimistic user send', () {
    final local = [
      {'role': 'user', 'content': 'old', 'id': 1},
      {'role': 'assistant', 'content': 'hi', 'id': 2},
      {'role': 'user', 'content': 'new question'},
    ];
    final server = [
      {'role': 'user', 'content': 'old', 'id': 1},
      {'role': 'assistant', 'content': 'hi', 'id': 2},
    ];
    final merged = mergeAiMessagesWithPending(local, server);
    expect(merged.length, 3);
    expect(merged.last['content'], 'new question');
    expect(aiServerCaughtUpWithLocal(local, server), isFalse);
    expect(aiServerCaughtUpWithLocal(local, merged), isTrue);
  });

  test('normalizeMarkdownContent fixes finance template quirks', () {
    expect(
      normalizeMarkdownContent('```markdown\n## 结论\n```'),
      '## 结论',
    );
    expect(
      normalizeMarkdownContent('| ⏰ 2026-07-01 15:04:05 |'),
      '⏰ 2026-07-01 15:04:05',
    );
    expect(
      normalizeMarkdownContent('| **全市场** | **偏强** | **↑3000只 ↓2000只** | — |'),
      '- **全市场**：**偏强** · **↑3000只 ↓2000只**',
    );
    expect(
      normalizeMarkdownContent('结论\n| 指数 | 涨跌 |\n|---|---|\n| 上证 | 1% |'),
      '结论\n\n| 指数 | 涨跌 |\n| --- | --- |\n| 上证 | 1% |',
    );
    const sectorSample = '''#### 领涨板块 TOP5
| 排名 | 板块名称 | 涨跌幅 | 领涨股 |
|-----|---------|--------|--------|
| 1 | 银行 | 2.50% | 招商银行 |
| 2 | 地产 | 1.20% | 万科A |


| 3 | 保险 | 0.80% | 中国平安 |
''';
    final fixed = normalizeMarkdownContent(sectorSample);
    expect(fixed, contains('| 1 | 银行 | 2.50% | 招商银行 |'));
    expect(fixed, contains('| --- | --- | --- | --- |'));
    expect(fixed.contains('| 2 | 地产 |\n\n\n| 3 |'), isFalse);
    expect(RegExp(r'\| --- \| --- \| --- \| --- \|').allMatches(fixed).length, 1);
  });
}
