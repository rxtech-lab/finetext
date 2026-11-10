import Foundation
import SwiftData

// Only the app's unrelated model-download defaults are stubbed in this standalone check.
enum HumanizationEngine: String { case translateGemma }
enum AIDetectorEngine: String { case disabled }
struct TranslationModel { var id = "test"; static let `default` = TranslationModel() }

@main struct HistoryCostsTests {
  @MainActor static func main() throws {
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("fixtures.store")
    let schema = Schema([RefinementSession.self, RewriteItem.self, TranslationItem.self, ImageItem.self, GenerationCharge.self])
    let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
    let context = container.mainContext
    let model = ModelRef(providerID: UUID(), modelID: "test")
    for index in 0..<45 {
      let session = RefinementSession()
      session.originalText = "Draft \(index)"
      session.updatedAt = Date(timeIntervalSince1970: Double(1000-index))
      context.insert(session)
      if index == 40 {
        session.summaryTitle = "Saved AI Title"
        let rewrite = RewriteItem(presetID: "x", tone: .natural, model: model)
        rewrite.output = "Café rewrite needle"
        session.rewrites.append(rewrite)
        let translation = TranslationItem(language: .japanese, model: model, sourceRewriteID: nil)
        translation.output = "translation needle"
        session.translations.append(translation)
        let image = ImageItem(model: model)
        image.instruction = "image needle"
        session.images.append(image)
      }
    }
    context.insert(RefinementSession())
    try context.save()
    let first = try HistoryStore.page(in: context, query: "", offset: 0)
    let second = try HistoryStore.page(in: context, query: "", offset: 20)
    let third = try HistoryStore.page(in: context, query: "", offset: 40)
    precondition(first.count == 20 && second.count == 20 && third.count == 5)
    precondition(Set((first+second+third).map(\.id)).count == 45)
    precondition(first.first?.originalText == "Draft 0")
    for term in ["draft 40", "SAVED AI TITLE", "cafe", "translation needle", "image needle"] {
      let results = try HistoryStore.page(in: context, query: term, offset: 0)
      precondition(results.count == 1, "Search failed: \(term)")
    }
    let absent = try HistoryStore.page(in: context, query: "absent", offset: 0)
    precondition(absent.isEmpty)

    // MCP requests get independent, immediately searchable history, including while
    // output is pending. Saving later rounds must update the same persisted item.
    let externalItem = RewriteItem(presetID: "email", tone: .natural, model: model)
    externalItem.refinementSource = "MCP email draft"
    externalItem.customPlatformName = "Email"
    let externalSession = try HistoryStore.createRewriteSession(in: context, text: "MCP email draft", item: externalItem)
    let humanizedItem = RewriteItem(presetID: "message", tone: .natural, model: model)
    let humanizedSession = try HistoryStore.createRewriteSession(in: context, text: "MCP humanize draft", item: humanizedItem)
    precondition(externalSession.id != humanizedSession.id && externalSession.id != first[0].id)
    precondition(externalItem.session?.id == externalSession.id)
    let pendingExternal = try HistoryStore.page(in: context, query: "MCP", offset: 0)
    precondition(pendingExternal.count == 2)
    externalItem.output = "Saved external output"
    externalItem.initialAIScore = 80
    externalItem.finalAIScore = 15
    externalItem.humanizationRounds = 2
    humanizedItem.output = "Saved humanized output"
    let externalCharge = GenerationCharge(sessionID: externalSession.id, itemID: externalItem.id, modelID: model.modelID, kind: "mcp")
    externalCharge.costUSD = 0.05
    context.insert(externalCharge)
    try context.save()
    let externalReload = ModelContext(container)
    let savedExternal = try HistoryStore.page(in: externalReload, query: "Saved external output", offset: 0)
    precondition(savedExternal.count == 1 && savedExternal[0].id == externalSession.id)
    let savedItem = savedExternal[0].rewrites[0]
    precondition(savedItem.id == externalItem.id && savedItem.refinementSource == "MCP email draft")
    precondition(savedItem.finalAIScore == 15 && savedItem.humanizationRounds == 2)
    precondition(savedItem.platformTitle == "Email")
    let savedCharges = try externalReload.fetch(FetchDescriptor<GenerationCharge>())
    precondition(CostSummary(charges: savedCharges.filter { $0.sessionID == savedExternal[0].id }).total == 0.05)
    context.delete(externalSession)
    context.delete(humanizedSession)
    context.delete(externalCharge)
    try context.save()

    let session = first[0]
    session.summaryTitle = "AI summary"
    session.summarySource = session.titleSource
    precondition(session.title == "AI summary")
    session.originalText = "Changed source"
    precondition(session.title == "Changed source")

    let usage = GenerationUsage.parse(["usage": ["prompt_tokens": 100, "completion_tokens": 20,
      "prompt_tokens_details": ["cached_tokens": 40], "cost": "0.0123"]])!
    precondition(usage.costUSD == 0.0123 && usage.cachedTokens == 40)
    let estimate = usage.estimate(ModelPricing(input: 0.000002, output: 0.00001, cachedInput: 0.000001))!
    precondition(abs(estimate - 0.00036) < 0.000000001)
    precondition(GenerationUsage.parse(["usage": ["cost": -1]])?.costUSD == nil)
    precondition(GenerationUsage.parse(["usage": ["cost": "NaN"]])?.costUSD == nil)
    precondition(GenerationUsage.parse(["usage": ["cost": 0]])?.costUSD == 0)
    precondition(GenerationUsage().estimate(ModelPricing(input: 1, output: 1)) == nil)
    let remote = OpenAIClient.classify(["id": "example", "pricing": ["prompt": "0.000002", "completion": "0.00001"]])!
    precondition(remote.pricing?.input == 0.000002)
    // Vercel uses input/output names, and compatibility usage can contain a zero
    // while billing lives in provider_metadata.gateway.cost.
    let gateway = OpenAIClient.classify(["id": "google/gemini-3.8-flash", "pricing": [
      "input": "0.00000075", "output": "0.00000375", "input_cache_read": "0.000000075"
    ]])!
    precondition(gateway.pricing?.input == 0.00000075 && gateway.pricing?.output == 0.00000375)
    let gatewayUsage = GenerationUsage.parse(["usage": ["prompt_tokens": 100, "completion_tokens": 20, "cost": 0]], isVercelGateway: true)!
    precondition(gatewayUsage.costUSD == nil)
    precondition(abs(gatewayUsage.estimate(gateway.pricing)! - 0.00015) < 0.000000001)
    let billing = GenerationUsage.parse([
      "usage": ["cost": 0], "provider_metadata": ["gateway": ["cost": "0.00015"]]
    ], isVercelGateway: true)!
    precondition(billing.costUSD == 0.00015)
    let free = GenerationUsage.parse(["provider_metadata": ["gateway": ["cost": "0"]]], isVercelGateway: true)!
    precondition(free.costUSD == 0)
    precondition(CostSummary.usd(0.00000004) != CostSummary.usd(0))
    precondition(CostSummary.usd(0.00015) != CostSummary.usd(0))
    let oldCache = Data("{\"id\":\"old\",\"generatesImages\":false,\"generatesText\":true}".utf8)
    let decoded = try JSONDecoder().decode(RemoteModel.self, from: oldCache)
    precondition(decoded.pricing == nil)

    let charge = GenerationCharge(sessionID: session.id, itemID: UUID(), modelID: "test", kind: "rewrite")
    charge.costUSD = 0.1
    let regeneration = GenerationCharge(sessionID: session.id, itemID: charge.itemID, modelID: "test", kind: "rewrite")
    regeneration.costUSD = 0.2
    regeneration.estimated = true
    let unknown = GenerationCharge(sessionID: session.id, itemID: UUID(), modelID: "codex-image", kind: "image")
    precondition(CostSummary(charges: [unknown]).totalLabel == LocalizableKey.costUnavailable.string)
    for item in [charge, regeneration, unknown] { context.insert(item) }
    try context.save()
    let totals = CostSummary(charges: [charge, regeneration, unknown])
    precondition(abs(totals.total - 0.3) < 0.00000001 && totals.unknownCount == 1 && totals.hasEstimate)
    precondition(totals.label.contains("≈") && totals.label.contains("?"))
    context.delete(session)
    try context.save()
    let reloaded = ModelContext(container)
    let surviving = try reloaded.fetch(FetchDescriptor<GenerationCharge>())
    precondition(surviving.count == 3 && abs(CostSummary(charges: surviving).total - 0.3) < 0.00000001)
    print("PASS: disk-backed paging, MCP session isolation/persistence/search/scores/costs, title invalidation, pricing/usage parsing, cumulative spend, deletion-safe ledger")
  }
}
