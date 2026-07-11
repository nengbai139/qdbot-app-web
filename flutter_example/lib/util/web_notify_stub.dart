typedef WebNotifyTap = void Function(String kind, Map<String, String> data);
typedef ImNotifyLookup = Map<String, String>? Function(Map<String, dynamic> msg);

ImNotifyLookup? _imLookup;

void setupImNotifyLookup(ImNotifyLookup? lookup) => _imLookup = lookup;

void setupWebNotifyHandler(WebNotifyTap? handler) {}

Future<bool> requestWebNotifyPermission() async => false;

void maybeNotifyImMessage(Map<String, dynamic> msg) {}

void maybeNotifyCircleMessage(Map<String, dynamic> msg) {}

void maybeNotifyAiMessage(Map<String, dynamic> msg) {}

void maybeNotifySubscriptionExpiry({required int daysLeft, String planName = 'AI Pro'}) {}

bool webDocumentHidden() => false;

void maybeNotifyCallSignal(Map<String, dynamic> msg) {}
