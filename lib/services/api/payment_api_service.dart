import 'api_service.dart';
import '../../database/local_database.dart';
import '../../config/app_config.dart';

/// Сервис платежей через Stripe.
class PaymentApiService {
  static final PaymentApiService _i = PaymentApiService._();
  factory PaymentApiService() => _i;
  PaymentApiService._();

  bool get isEnabled => AppConfig.featurePayments;

  // ── Продукты ──────────────────────────────────────

  static const Map<String, Product> products = {
    'premium_monthly': Product(
      id:          'premium_monthly',
      name:        'Premium Pro',
      description: 'Полный доступ, AI анализ, без ограничений',
      price:       9.99,
      currency:    'USD',
      interval:    'month',
    ),
    'ai_monthly': Product(
      id:          'ai_monthly',
      name:        'AI Анализ',
      description: '50 AI анализов в месяц',
      price:       4.99,
      currency:    'USD',
      interval:    'month',
    ),
    'server_monthly': Product(
      id:          'server_monthly',
      name:        'Серверная обработка',
      description: 'До 500 фото в месяц на сервере',
      price:       3.99,
      currency:    'USD',
      interval:    'month',
    ),
    'api_monthly': Product(
      id:          'api_monthly',
      name:        'API Доступ',
      description: '10,000 запросов в месяц',
      price:       19.99,
      currency:    'USD',
      interval:    'month',
    ),
    'pack_100': Product(
      id:          'pack_100',
      name:        'Пакет 100 сравнений',
      description: '100 дополнительных сравнений',
      price:       2.99,
      currency:    'USD',
      interval:    'once',
    ),
  };

  // ── Покупка ───────────────────────────────────────

  Future<PaymentResult> purchase(String productId, String userId) async {
    if (!isEnabled) {
      return PaymentResult.error('Платежи не подключены');
    }

    final product = products[productId];
    if (product == null) {
      return PaymentResult.error('Продукт не найден');
    }

    try {
      // 1. Создаём PaymentIntent на сервере
      final intent = await ApiService().post('/payments/create-intent', {
        'product_id': productId,
        'user_id':    userId,
      });

      final clientSecret = intent['client_secret'] as String?;
      if (clientSecret == null) {
        return PaymentResult.error('Ошибка создания платежа');
      }

      // 2. TODO: открыть Stripe Payment Sheet
      // await Stripe.instance.initPaymentSheet(
      //   paymentSheetParameters: SetupPaymentSheetParameters(
      //     paymentIntentClientSecret: clientSecret,
      //     merchantDisplayName: 'Photo Compare',
      //   ),
      // );
      // await Stripe.instance.presentPaymentSheet();

      // 3. Подтверждаем на сервере
      final confirm = await ApiService().post('/payments/confirm', {
        'payment_intent_id': intent['payment_intent_id'],
        'user_id':           userId,
      });

      // 4. Сохраняем локально
      final purchase = {
        'id':               confirm['purchase_id'] ?? '${userId}_$productId',
        'user_id':          userId,
        'product_id':       productId,
        'product_name':     product.name,
        'price':            product.price,
        'currency':         product.currency,
        'status':           'active',
        'stripe_payment_id': confirm['payment_intent_id'],
        'expires_at':       _expiresAt(product.interval),
        'created_at':       DateTime.now().toIso8601String(),
      };
      await LocalDatabase().savePurchase(purchase);

      return PaymentResult.success(purchase);

    } on ApiException catch (e) {
      return PaymentResult.error('Ошибка платежа: ${e.statusCode}');
    } catch (e) {
      return PaymentResult.error('Ошибка: $e');
    }
  }

  // ── Восстановление покупок ────────────────────────

  Future<List<Map<String, dynamic>>> restorePurchases(String userId) async {
    if (!isEnabled) return [];
    try {
      final res = await ApiService().get('/payments/purchases',
          params: {'user_id': userId});
      final items = res['items'] as List? ?? [];
      for (final item in items) {
        await LocalDatabase().savePurchase(item as Map<String, dynamic>);
      }
      return await LocalDatabase().getPurchases(userId);
    } catch (_) {
      return await LocalDatabase().getPurchases(userId);
    }
  }

  // ── Проверка подписки ─────────────────────────────

  Future<bool> hasActivePremium(String userId) async {
    return LocalDatabase().hasActivePremium(userId);
  }

  // ── Утилиты ───────────────────────────────────────

  String? _expiresAt(String interval) {
    switch (interval) {
      case 'month': return DateTime.now().add(const Duration(days: 31)).toIso8601String();
      case 'year':  return DateTime.now().add(const Duration(days: 365)).toIso8601String();
      default: return null; // разовая покупка не истекает
    }
  }
}

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String currency;
  final String interval; // 'month', 'year', 'once'

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.interval,
  });
}

class PaymentResult {
  final bool                      success;
  final Map<String, dynamic>?     purchase;
  final String?                   error;

  const PaymentResult._({required this.success, this.purchase, this.error});

  factory PaymentResult.success(Map<String, dynamic> purchase) =>
      PaymentResult._(success: true, purchase: purchase);

  factory PaymentResult.error(String message) =>
      PaymentResult._(success: false, error: message);
}
