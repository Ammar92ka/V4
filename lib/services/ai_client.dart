import 'ai_provider.dart';
import 'settings_service.dart';

/// يرسل الطلب للمزود المختار، ويجرب نماذج بديلة تلقائيا عند الضغط أو توقف النموذج.
class AiClient {
  final AiProvider provider;
  final String apiKey;
  final List<String> models;

  /// تفعيل البحث على الويب للتحقق من الوقائع (إن دعمه المزود). يزيد الاستهلاك.
  final bool search;

  AiClient({
    required this.provider,
    required this.apiKey,
    required this.models,
    this.search = false,
  }) : assert(models.isNotEmpty);

  factory AiClient.fromSettings(AiSettings s) {
    final provider = aiProviderById(s.provider);
    final models = <String>[s.effectiveModel];
    for (final m in [provider.defaultModel, ...provider.fallbackModels]) {
      if (!models.contains(m)) models.add(m);
    }
    return AiClient(
      provider: provider,
      apiKey: s.apiKey,
      models: models,
      search: s.useSearch && provider.supportsSearch,
    );
  }

  /// يطلب جولة بصيغة JSON.
  Future<String> generateJson(String prompt) => _run(prompt, json: true, search: search);

  /// طلب نصي قصير (لاختبار الاتصال من الإعدادات) بنفس منطق النماذج البديلة.
  Future<String> generateText(String prompt) => _run(prompt, json: false, search: false);

  Future<String> _run(String prompt, {required bool json, required bool search}) async {
    AiException? last;
    var useSearch = search;
    for (final model in models) {
      try {
        return await _once(prompt, model, json, useSearch);
      } on AiException catch (e) {
        // رفض الطلب مع البحث غالبا بسبب عدم دعم النموذج للبحث: نعيد بدونه فورا
        if (useSearch && e.status == 400) {
          useSearch = false;
          try {
            return await _once(prompt, model, json, false);
          } on AiException catch (e2) {
            last = e2;
            if (!e2.retryable && !e2.modelProblem) rethrow;
            continue;
          }
        }
        last = e;
        // الأخطاء غير المؤقتة (مفتاح خاطئ مثلا) لا تفيد معها النماذج البديلة
        if (!e.retryable && !e.modelProblem) rethrow;
      }
    }
    throw last ?? const AiException('تعذر الاتصال بالذكاء الاصطناعي.');
  }

  Future<String> _once(String prompt, String model, bool json, bool useSearch) =>
      provider.generate(
        prompt: prompt,
        apiKey: apiKey,
        model: model,
        json: json,
        search: useSearch,
      );
}
