import 'api_client.dart';

class QdWallet {
  final double balance;
  final List<QdLedgerEntry> ledger;

  const QdWallet({required this.balance, required this.ledger});

  factory QdWallet.fromJson(Map<String, dynamic> j) => QdWallet(
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
        ledger: (j['ledger'] as List? ?? [])
            .map((e) => QdLedgerEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class QdLedgerEntry {
  final double amount;
  final double balanceAfter;
  final String kind;
  final String refType;
  final String refId;
  final String createdAt;

  const QdLedgerEntry({
    required this.amount,
    required this.balanceAfter,
    required this.kind,
    this.refType = '',
    this.refId = '',
    this.createdAt = '',
  });

  factory QdLedgerEntry.fromJson(Map<String, dynamic> j) => QdLedgerEntry(
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        balanceAfter: (j['balanceAfter'] as num?)?.toDouble() ?? 0,
        kind: (j['kind'] ?? '').toString(),
        refType: (j['refType'] ?? '').toString(),
        refId: (j['refId'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

class WalletApi {
  final ApiClient _c;
  WalletApi([String? token]) : _c = ApiClient(token: token);

  Future<QdWallet> getQdWallet({int limit = 20}) async {
    final resp = await _c.get('/app/wallet/qd', query: {'limit': '$limit'});
    if (resp.statusCode != 200) throw Exception(resp.body);
    return QdWallet.fromJson(ApiClient.decode(resp));
  }

  Future<double> getQdBalance() async {
    final w = await getQdWallet(limit: 1);
    return w.balance;
  }

  Future<({double balance, String withdrawId, String message})> withdrawQd({
    required double amount,
    required String account,
  }) async {
    final resp = await _c.post('/app/wallet/qd/withdraw', body: {
      'amount': amount,
      'account': account,
    });
    if (resp.statusCode != 200) throw Exception(resp.body);
    final j = ApiClient.decode(resp);
    return (
      balance: (j['balance'] as num?)?.toDouble() ?? 0,
      withdrawId: (j['withdrawId'] ?? '').toString(),
      message: (j['message'] ?? '提现申请已提交').toString(),
    );
  }
}
