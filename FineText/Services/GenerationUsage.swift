import Foundation

/// Prices returned by a provider's model catalogue, in USD per token.
struct ModelPricing: Codable, Hashable, Sendable {
  var input: Double
  var output: Double
  var cachedInput: Double?
}

struct GenerationUsage: Sendable {
  var inputTokens: Int?
  var outputTokens: Int?
  var cachedTokens: Int = 0
  var costUSD: Double?

  static func parse(_ json: [String: Any], isVercelGateway: Bool = false) -> GenerationUsage? {
    let usage = json["usage"] as? [String: Any] ?? [:]
    func number(_ value: Any?) -> Double? {
      let result = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
      return result.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    let metadata = (json["provider_metadata"] ?? json["providerMetadata"]) as? [String: Any]
    let gateway = metadata?["gateway"] as? [String: Any]
    let gatewayCost = number(gateway?["cost"])
    var usageCost = number(usage["cost"]) ?? number(usage["total_cost_usd"])
    // Gateway billing metadata is authoritative. A bare zero in compatibility usage
    // is insufficient to price a paid model; use token pricing when available.
    if isVercelGateway, usageCost == 0, gatewayCost == nil { usageCost = nil }
    guard !usage.isEmpty || gatewayCost != nil else { return nil }
    let details = (usage["prompt_tokens_details"] ?? usage["input_tokens_details"]) as? [String: Any]
    return GenerationUsage(inputTokens: usage["prompt_tokens"] as? Int ?? usage["input_tokens"] as? Int,
                           outputTokens: usage["completion_tokens"] as? Int ?? usage["output_tokens"] as? Int,
                           cachedTokens: details?["cached_tokens"] as? Int ?? 0,
                           costUSD: gatewayCost ?? usageCost)
  }

  func estimate(_ pricing: ModelPricing?) -> Double? {
    guard let pricing, let inputTokens, let outputTokens, inputTokens >= 0, outputTokens >= 0,
          pricing.input.isFinite, pricing.output.isFinite, pricing.input >= 0, pricing.output >= 0,
          pricing.cachedInput.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
    let cached = min(inputTokens, max(0, cachedTokens))
    let value = Double(inputTokens - cached) * pricing.input + Double(cached) * (pricing.cachedInput ?? pricing.input)
      + Double(outputTokens) * pricing.output
    return value.isFinite && value >= 0 ? value : nil
  }
}
