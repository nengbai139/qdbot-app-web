import 'dart:convert';
import 'api_client.dart';

class PayOrder {
  final String orderId;
  final String userCode;
  final String productType;
  final double amount;
  final int level;
  final String levelName;
  final String status;
  final String? payChannel;
  final DateTime? expiresAt;
  final DateTime? paidAt;

  const PayOrder({
    this.orderId = '',
    this.userCode = '',
    this.productType = '',
    this.amount = 0,
    this.level = 0,
    this.levelName = '',
    this.status = '',
    this.payChannel,
    this.expiresAt,
    this.paidAt,
  });

  bool get isAiSubscription => productType == 'ai_pro_monthly';

  factory PayOrder.fromJson(Map<String, dynamic> j) {
    DateTime? parse(String? k) {
      final v = j[k];
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }
    return PayOrder(
      orderId: (j['orderId'] ?? '').toString(),
      userCode: (j['userCode'] ?? j['planId'] ?? '').toString(),
      productType: (j['productType'] ?? '').toString(),
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      level: (j['level'] as num?)?.toInt() ?? 0,
      levelName: (j['levelName'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      payChannel: j['payChannel']?.toString(),
      expiresAt: parse('expiresAt'),
      paidAt: parse('paidAt'),
    );
  }

  bool get isPaid => status == 'paid' || status == 'consumed';
}

class PayApi {
  final ApiClient _c;
  PayApi([String? token]) : _c = ApiClient(token: token);

  /// 创建靓号订单（注册前无需 token）
  Future<PayOrder> createAiSubscriptionOrder({
    required String userId,
    String planId = 'ai_pro_monthly',
    String? email,
  }) async {
    final resp = await _c.post('/app/pay/orders', body: {
      'productType': 'ai_pro_monthly',
      'planId': planId,
      'userId': userId,
      if (email != null && email.isNotEmpty) 'email': email,
    });
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    return PayOrder.fromJson(ApiClient.decode(resp));
  }

  Future<PayOrder> createQdRechargeOrder({
    required String userId,
    required double coins,
  }) async {
    final resp = await _c.post('/app/pay/orders', body: {
      'productType': 'qd_recharge',
      'userId': userId,
      'amount': coins,
      'planId': '${coins.toInt()}',
    });
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    return PayOrder.fromJson(ApiClient.decode(resp));
  }

  /// @deprecated 礼物请用 QD 币，见 WalletApi + sendLiveGift
  Future<PayOrder> createLiveGiftOrder({
    required String userId,
    required String giftOrderId,
    required double amount,
    String? levelName,
  }) async {
    final resp = await _c.post('/app/pay/orders', body: {
      'productType': 'live_gift',
      'planId': giftOrderId,
      'userId': userId,
      'amount': amount,
      if (levelName != null) 'levelName': levelName,
    });
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    return PayOrder.fromJson(ApiClient.decode(resp));
  }

  Future<PayOrder> createPremiumOrder({
    required String userCode,
    required String email,
    String? birthday,
    String? userId,
  }) async {
    final resp = await _c.post('/app/pay/orders', body: {
      'userCode': userCode,
      'email': email,
      if (birthday != null && birthday.isNotEmpty) 'birthday': birthday,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
    });
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    return PayOrder.fromJson(ApiClient.decode(resp));
  }

  Future<PayOrder> getOrder(String orderId) async {
    final resp = await _c.get('/app/pay/orders/$orderId');
    if (resp.statusCode != 200) throw Exception(resp.body);
    return PayOrder.fromJson(ApiClient.decode(resp));
  }

  /// ponytail: Web MVP 模拟支付；生产走 checkout(channel)
  Future<PayOrder> mockPay(String orderId) async {
    final resp = await _c.post('/app/pay/orders/$orderId/mock-pay');
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    final data = ApiClient.decode(resp);
    final order = data['order'];
    if (order is Map) return PayOrder.fromJson(Map<String, dynamic>.from(order));
    return getOrder(orderId);
  }

  /// 发起支付：mock / alipay / wechat
  Future<Map<String, dynamic>> checkout(String orderId, String channel) async {
    final resp = await _c.post('/app/pay/orders/$orderId/checkout', body: {'channel': channel});
    if (resp.statusCode != 200 && resp.statusCode != 501) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    return ApiClient.decode(resp);
  }

  Future<PayOrder> alipayConfirm(String orderId) async {
    final resp = await _c.post('/app/pay/orders/$orderId/alipay-confirm');
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    final data = ApiClient.decode(resp);
    final order = data['order'];
    if (order is Map) return PayOrder.fromJson(Map<String, dynamic>.from(order));
    return getOrder(orderId);
  }

  Future<PayOrder> wechatConfirm(String orderId) async {
    final resp = await _c.post('/app/pay/orders/$orderId/wechat-confirm');
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    final data = ApiClient.decode(resp);
    final order = data['order'];
    if (order is Map) return PayOrder.fromJson(Map<String, dynamic>.from(order));
    return getOrder(orderId);
  }

  Future<List<PayOrder>> listOrders() async {
    final resp = await _c.get('/app/pay/orders');
    if (resp.statusCode != 200) throw Exception(resp.body);
    final list = jsonDecode(resp.body)['orders'] as List<dynamic>? ?? [];
    return list.map((e) => PayOrder.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<String> applyUserCode({required String userCode, required String premiumOrderId}) async {
    final resp = await _c.put('/app/user/code', body: {
      'userCode': userCode,
      'premiumOrderId': premiumOrderId,
    });
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
    return ApiClient.decode(resp)['userCode'] as String? ?? userCode;
  }
}

final publicPayApi = PayApi();
