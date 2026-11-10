import type { Locale } from "./locales";
export const tutorialSlugs = ["hugging-face", "openai-compatible", "flowcy", "humanizer", "refine-text"] as const;
export type TutorialSlug = typeof tutorialSlugs[number];
export type Tutorial = { slug: TutorialSlug; title: string; description: string; time: string; image: string; alt: string; caption: string; steps: { title: string; body: string }[]; note: string; link?: { label: string; href: string } };
const en: Tutorial[] = [
  { slug: "hugging-face", title: "Run a model on your Mac", description: "Find an MLX model on Hugging Face, download it, and write locally.", time: "5 min + download", image: "hugging-face", alt: "FineText’s Hugging Face browser with MLX Community models and search, source and sort controls", caption: "Hugging Face browser · FineText for macOS", steps: [
    { title: "Open the model browser", body: "Click the FineText menu bar icon, then the settings gear. Open Local Models → Browse Hugging Face… (or the + button)." },
    { title: "Choose and download a model", body: "Search for a model such as Qwen, open its detail page, review the download size, then choose Download. The browser lists MLX text-generation models. Start with a smaller 4-bit model that fits your Mac’s memory. Wait for the download to finish; the progress overlay also lets you cancel." },
    { title: "Use it in a rewrite", body: "Return to Rewrite → Add Platform, choose a platform, then On This Mac → your downloaded model. Paste a draft and choose Rewrite All. Downloaded text models run on your Mac; cloud models still send requests to their provider." },
  ], note: "You need an internet connection for the download. A Hugging Face repository must be compatible with FineText’s MLX runtime; arbitrary model formats are not supported.", link: { label: "Browse MLX Community on Hugging Face", href: "https://huggingface.co/mlx-community" } },
  { slug: "openai-compatible", title: "Connect your own endpoint", description: "Add an OpenAI-compatible cloud provider or a local model server.", time: "3 min", image: "provider", alt: "FineText’s Add Provider sheet showing Name, Base URL, API Key, Test Connection and Add", caption: "Add Provider sheet · example URL, no credentials", steps: [
    { title: "Add a provider", body: "Open Settings → Providers and click +. In the dedicated editor, select a preset or enter a name for your custom provider." },
    { title: "Enter the API base URL", body: "Use the provider’s API base URL, for example https://api.openai.com/v1. Do not paste the full /chat/completions URL. Enter the credential required by your provider; a local server that does not require authentication can leave API Key empty. FineText stores saved keys in macOS Keychain." },
    { title: "Test, save, and select", body: "Choose Test Connection to check model discovery through GET /models. If it fails, check the URL, server availability and authentication. Click Add, then choose the provider and a text model from the model submenu under Add Platform. Use Refresh All in Providers when the server’s model list changes." },
  ], note: "Model discovery is a connection check. The endpoint must also support compatible text generation for rewrites. Your provider’s usage and billing rules apply." },
  { slug: "flowcy", title: "Use your Flowcy subscription", description: "Sign in with your rxlab account and choose a Flowcy text model.", time: "3 min", image: "flowcy", alt: "Illustrated Flowcy setup path: Settings, General, Sign in with Flowcy, Refresh Models, then the Flowcy model submenu", caption: "Illustrated walkthrough · based on the current Flowcy interface", steps: [
    { title: "Check your Flowcy account", body: "Open Flowcy and make sure the rxlab account you intend to use has the plan and usage allowance you need. Subscription management happens in Flowcy; FineText does not sell or change your plan." },
    { title: "Sign in from General settings", body: "In FineText, open Settings → General → Flowcy → Sign in with Flowcy. Complete the native sign-in sheet with the same rxlab account. Once signed in, Manage Flowcy Account shows your account and available models; use Refresh Models if the list is empty or has changed." },
    { title: "Pick a Flowcy model", body: "Return to Rewrite → Add Platform, choose a platform, then Flowcy → an available text model. Run the rewrite. Requests use your Flowcy plan; if a usage limit is reached, check your allowance in Flowcy before retrying." },
  ], note: "Flowcy supports rewriting and translation, not image generation. If sign-in is unavailable or the app reports that Flowcy is not configured, use a build with Flowcy sign-in enabled. A subscription alone cannot enable sign-in in an unconfigured build.", link: { label: "Open Flowcy", href: "https://www.flowcy.dev" } },
  { slug: "humanizer", title: "Configure the Humanizer", description: "Choose a humanization engine, download its model, and control the rounds.", time: "4 min + download", image: "humanizer", alt: "FineText Humanizer settings showing fixed rounds, translation round trip, pivot language, AI detector and TranslateGemma model", caption: "Humanizer settings · labels may vary by app version", steps: [
    { title: "Choose a mode and engine", body: "Open Settings → Humanizer. Set Checking mode to fixed/manual rounds or automatic rounds. Fixed rounds runs the number of round trips you choose. Automatic rounds uses a target AI score. Off skips humanization. For the engine, choose Translation round trip or Selected rewrite model." },
    { title: "Prepare the model", body: "For Translation round trip, choose a pivot language and a translation model (TranslateGemma or NLLB), then Download if it is not ready. Wait until its status is Ready. For Selected rewrite model, humanization uses the text model chosen on the rewrite, so configure that provider or download that local model first." },
    { title: "Set up scoring when needed", body: "Open AI detector to select and download a detector. Automatic rounds needs a ready detector; fixed rounds can work without scoring. Set your target score or round count, then return to your draft and run a rewrite. Automatic mode keeps the best result and stops after three rounds without improvement." },
  ], note: "AI scores estimate patterns, not authorship or writing quality. The detectors are intended for English prose of at least 50 words. Read the result for meaning and accuracy; a lower score is not a guarantee." },
  { slug: "refine-text", title: "Fine-tune your text", description: "Take a rough draft from the menu bar to a version ready to share.", time: "2 min", image: "refine-text", alt: "Illustrated rewrite workflow with an original draft, platform and tone choices, a polished example and Copy", caption: "Illustrated example · output varies with your model and settings", steps: [
    { title: "Start with your draft", body: "Click FineText in the Mac menu bar. Paste or type your text in Original post, then choose Rewrite. Try: “we’ve been working on something new. excited to finally share it with everyone next week!”" },
    { title: "Choose a destination and model", body: "Open Add Platform, choose a destination such as LinkedIn, then select a configured provider, Flowcy, or On This Mac model. Add more destinations for multiple versions. Open a rewrite card to adjust Tone, Target language and Model. Use Custom Platforms… to save your own platform instructions." },
    { title: "Rewrite, review, and copy", body: "Choose Rewrite All, or Rewrite in a single detail view. Review the result and compare Before / After when available. Adjust the tone or model and Regenerate to try again. You can edit the output directly before choosing Copy. Humanization follows your Humanizer settings, and sessions are saved in History." },
  ], note: "Here, “fine-tune” means refining your writing. FineText does not train or modify model weights. Always check factual details and whether the result still sounds like you." },
];
const cn: Tutorial[] = [
  { ...en[0], title: "在 Mac 上运行本地模型", description: "从 Hugging Face 下载 MLX 模型，在本机处理文字。", time: "5 分钟＋下载", alt: "FineText 的 Hugging Face 模型浏览器，包含搜索、来源和排序控件", caption: "Hugging Face 浏览器 · macOS 版 FineText（英文界面）", steps: [
    { title: "打开模型浏览器", body: "点击菜单栏 FineText 图标，再点击设置齿轮。打开“本地模型 → 浏览 Hugging Face…”，也可以点击 +。" },
    { title: "选择并下载模型", body: "搜索 Qwen 等模型，进入详情页，查看下载大小后点击“下载”。浏览器仅列出 MLX 文本生成模型。建议先选适合 Mac 内存的小型 4-bit 模型。等待下载完成，也可在进度浮层中取消。" },
    { title: "用于改写", body: "返回“改写 → 添加平台”，选择平台，再选择“在此 Mac 上”中的已下载模型。粘贴草稿，点击“全部改写”。本地文本模型在 Mac 上运行；云端模型仍会向服务商发送请求。" },
  ], note: "首次下载需要联网。模型仓库必须兼容 FineText 使用的 MLX 运行环境，并非所有模型格式都能使用。", link: { label: "浏览 Hugging Face MLX Community", href: en[0].link!.href } },
  { ...en[1], title: "连接兼容 OpenAI 的端点", description: "添加云端服务商或本地模型服务器。", time: "3 分钟", alt: "FineText 添加服务商窗口，显示名称、Base URL、API Key、测试连接和添加", caption: "添加服务商 · 示例地址，不含凭据（英文界面）", steps: [
    { title: "添加服务商", body: "打开“设置 → 服务商”，点击 +。在独立编辑窗口中选择预设，或填写自定义服务商名称。" },
    { title: "填写 API 基础地址", body: "输入服务商提供的 API Base URL，例如 https://api.openai.com/v1，不要填入完整的 /chat/completions 地址。按服务商要求填写凭据；无需认证的本地服务器可留空 API Key。保存的密钥存放在 macOS 钥匙串中。" },
    { title: "测试、保存并选择模型", body: "点击“测试连接”，通过 GET /models 检查模型列表。如失败，请检查地址、服务是否运行及认证信息。点击“添加”，再在“添加平台”的模型子菜单中选择该服务商和文本模型。服务端模型变化后，可在服务商页面点击“全部刷新”。" },
  ], note: "获取模型列表仅验证连接；端点还需支持兼容的文本生成接口才能改写。用量与计费遵循服务商规则。" },
  { ...en[2], title: "使用 Flowcy 订阅", description: "登录 rxlab 账号，选择 Flowcy 文本模型。", time: "3 分钟", alt: "Flowcy 设置流程示意：通用设置、登录 Flowcy、刷新模型、选择模型", caption: "界面流程示意 · 根据当前 Flowcy 界面绘制", steps: [
    { title: "确认 Flowcy 账号与额度", body: "打开 Flowcy，确认准备使用的 rxlab 账号具备所需套餐与用量额度。订阅在 Flowcy 中管理，FineText 不销售或修改套餐。" },
    { title: "从通用设置登录", body: "在 FineText 中打开“设置 → 通用 → Flowcy → 登录 Flowcy”，在原生登录窗口中使用同一个 rxlab 账号。登录后，“管理 Flowcy 账号”会显示账号和可用模型。模型为空或发生变化时，点击“刷新模型”。" },
    { title: "选择 Flowcy 模型", body: "返回“改写 → 添加平台”，选择平台，再选择“Flowcy”中的可用文本模型，然后改写。请求使用 Flowcy 套餐额度。达到用量限制时，请先到 Flowcy 检查剩余额度。" },
  ], note: "Flowcy 支持改写与翻译，不支持图片生成。如果登录不可用，或应用提示尚未配置 Flowcy，请使用已启用 Flowcy 登录的应用版本。订阅本身无法启用未配置版本的登录。", link: { label: "打开 Flowcy", href: en[2].link!.href } },
  { ...en[3], title: "配置人性化模型", description: "选择人性化引擎，下载模型，并设置处理轮数。", time: "4 分钟＋下载", alt: "FineText 人性化设置，包含轮数、往返翻译、枢轴语言、AI 检测器与翻译模型", caption: "人性化设置 · 不同版本的标签可能略有差异（英文界面）", steps: [
    { title: "选择模式与引擎", body: "打开“设置 → 人性化”。检查模式可选择固定／手动轮数、自动轮数或关闭。固定模式按设置的轮数运行，自动模式使用目标 AI 分数。引擎可选择“往返翻译”或“所选改写模型”。" },
    { title: "准备模型", body: "使用往返翻译时，选择枢轴语言和翻译模型（TranslateGemma 或 NLLB），尚未就绪时点击“下载”，等待状态变为“就绪”。使用“所选改写模型”时，人性化会使用该条改写选择的文本模型，请先配置对应服务商或下载本地模型。" },
    { title: "按需启用评分", body: "打开“AI 检测器”，选择并下载检测模型。自动模式需要检测器就绪，固定轮数可不评分。设置目标分数或轮数后，返回草稿进行改写。自动模式会保留最佳结果，连续三轮未改善时停止。" },
  ], note: "AI 分数仅估计文本模式，不能判断作者身份或写作质量。检测器适用于至少 50 个词的英文正文。请自行检查语义与事实，低分并不构成保证。" },
  { ...en[4], title: "打磨你的文字", description: "从菜单栏粘贴草稿，调整表达，再复制分享。", time: "2 分钟", alt: "改写流程示意，包含原文、平台与语气、改写示例和复制操作", caption: "改写示例示意 · 实际输出取决于模型与设置", steps: [
    { title: "输入草稿", body: "点击 Mac 菜单栏中的 FineText，在“原文”中粘贴或输入内容，然后选择“改写”。可以试试：“最近一直在做一个新东西，好期待下周终于能分享给大家！”" },
    { title: "选择平台与模型", body: "打开“添加平台”，选择 LinkedIn 等目标，再选择已配置的服务商、Flowcy 或“在此 Mac 上”的模型。可添加多个平台生成不同版本。打开改写卡片，可调整语气、目标语言与模型；通过“自定义平台…”保存自己的平台指令。" },
    { title: "改写、检查并复制", body: "点击“全部改写”，或在单条详情页点击“改写”。阅读结果，提供“前／后”对比时可切换查看。调整语气或模型后点击“重新生成”。也可以直接编辑输出，然后复制。人性化遵循设置中的配置，会话会自动保存在历史记录中。" },
  ], note: "这里的“微调”指打磨文字，FineText 不会训练或修改模型权重。请核对事实，并确认结果仍符合你的表达习惯。" },
];
// Both traditional locales use traditional script, while retaining exact English UI labels in screenshots.
const tw: Tutorial[] = [
  { ...en[0], title: "在 Mac 上執行本機模型", description: "從 Hugging Face 下載 MLX 模型，在本機處理文字。", time: "5 分鐘＋下載", alt: "FineText 的 Hugging Face 模型瀏覽器，包含搜尋、來源與排序控制項", caption: "Hugging Face 瀏覽器 · macOS 版 FineText（英文介面）", steps: [
    { title: "開啟模型瀏覽器", body: "點選選單列 FineText 圖示，再點選設定齒輪。開啟「本機模型 → 瀏覽 Hugging Face…」，也可以點選 +。" },
    { title: "選擇並下載模型", body: "搜尋 Qwen 等模型，進入詳細資訊頁，查看下載大小後點選「下載」。瀏覽器僅列出 MLX 文字生成模型。建議先選適合 Mac 記憶體的小型 4-bit 模型。等待下載完成，也可在進度浮層中取消。" },
    { title: "用於改寫", body: "返回「改寫 → 新增平台」，選擇平台，再選擇「在此 Mac 上」中的已下載模型。貼上草稿，點選「全部改寫」。本機文字模型在 Mac 上執行；雲端模型仍會向服務商傳送請求。" },
  ], note: "首次下載需要連網。模型儲存庫必須相容於 FineText 使用的 MLX 執行環境，並非所有模型格式都能使用。", link: { label: "瀏覽 Hugging Face MLX Community", href: en[0].link!.href } },
  { ...en[1], title: "連接相容 OpenAI 的端點", description: "新增雲端服務商或本機模型伺服器。", time: "3 分鐘", alt: "FineText 新增服務商視窗，顯示名稱、Base URL、API Key、測試連線與新增", caption: "新增服務商 · 範例位址，不含憑證（英文介面）", steps: [
    { title: "新增服務商", body: "開啟「設定 → 服務商」，點選 +。在獨立編輯視窗中選擇預設，或填寫自訂服務商名稱。" },
    { title: "填寫 API 基礎位址", body: "輸入服務商提供的 API Base URL，例如 https://api.openai.com/v1，不要填入完整的 /chat/completions 位址。依服務商要求填寫憑證；無需驗證的本機伺服器可留空 API Key。儲存的金鑰存放於 macOS 鑰匙圈。" },
    { title: "測試、儲存並選擇模型", body: "點選「測試連線」，透過 GET /models 檢查模型清單。如失敗，請檢查位址、服務是否執行及驗證資訊。點選「新增」，再於「新增平台」的模型子選單選擇該服務商與文字模型。伺服器模型變更後，可於服務商頁面點選「全部重新整理」。" },
  ], note: "取得模型清單僅驗證連線；端點還需支援相容的文字生成介面才能改寫。用量與計費遵循服務商規則。" },
  { ...en[2], title: "使用 Flowcy 訂閱", description: "登入 rxlab 帳號，選擇 Flowcy 文字模型。", time: "3 分鐘", alt: "Flowcy 設定流程示意：一般設定、登入 Flowcy、重新整理模型、選擇模型", caption: "介面流程示意 · 依據目前 Flowcy 介面繪製", steps: [
    { title: "確認 Flowcy 帳號與額度", body: "開啟 Flowcy，確認準備使用的 rxlab 帳號具備所需方案與用量額度。訂閱於 Flowcy 管理，FineText 不銷售或變更方案。" },
    { title: "從一般設定登入", body: "於 FineText 開啟「設定 → 一般 → Flowcy → 登入 Flowcy」，在原生登入視窗中使用同一個 rxlab 帳號。登入後，「管理 Flowcy 帳號」會顯示帳號與可用模型。模型清單為空或有所變更時，點選「重新整理模型」。" },
    { title: "選擇 Flowcy 模型", body: "返回「改寫 → 新增平台」，選擇平台，再選擇「Flowcy」中的可用文字模型，然後改寫。請求使用 Flowcy 方案額度。達到用量限制時，請先至 Flowcy 檢查剩餘額度。" },
  ], note: "Flowcy 支援改寫與翻譯，不支援圖片生成。如果登入無法使用，或 App 提示尚未設定 Flowcy，請使用已啟用 Flowcy 登入的版本。訂閱本身無法啟用未設定版本的登入。", link: { label: "開啟 Flowcy", href: en[2].link!.href } },
  { ...en[3], title: "設定人性化模型", description: "選擇人性化引擎，下載模型，並設定處理輪數。", time: "4 分鐘＋下載", alt: "FineText 人性化設定，包含輪數、往返翻譯、中介語言、AI 偵測器與翻譯模型", caption: "人性化設定 · 不同版本的標籤可能略有差異（英文介面）", steps: [
    { title: "選擇模式與引擎", body: "開啟「設定 → 人性化」。檢查模式可選擇固定／手動輪數、自動輪數或關閉。固定模式依設定輪數執行，自動模式使用目標 AI 分數。引擎可選擇「往返翻譯」或「所選改寫模型」。" },
    { title: "準備模型", body: "使用往返翻譯時，選擇中介語言與翻譯模型（TranslateGemma 或 NLLB），尚未就緒時點選「下載」，等待狀態變為「就緒」。使用「所選改寫模型」時，人性化會使用該筆改寫選擇的文字模型，請先設定對應服務商或下載本機模型。" },
    { title: "依需要啟用評分", body: "開啟「AI 偵測器」，選擇並下載偵測模型。自動模式需要偵測器就緒，固定輪數可不評分。設定目標分數或輪數後，返回草稿進行改寫。自動模式會保留最佳結果，連續三輪未改善時停止。" },
  ], note: "AI 分數僅估計文字模式，不能判斷作者身分或寫作品質。偵測器適用於至少 50 個詞的英文正文。請自行檢查語意與事實，低分並不構成保證。" },
  { ...en[4], title: "打磨你的文字", description: "從選單列貼上草稿，調整表達，再複製分享。", time: "2 分鐘", alt: "改寫流程示意，包含原文、平台與語氣、改寫範例與複製操作", caption: "改寫範例示意 · 實際輸出取決於模型與設定", steps: [
    { title: "輸入草稿", body: "點選 Mac 選單列的 FineText，在「原文」貼上或輸入內容，然後選擇「改寫」。可以試試：「最近一直在做一個新東西，好期待下週終於能分享給大家！」" },
    { title: "選擇平台與模型", body: "開啟「新增平台」，選擇 LinkedIn 等目標，再選擇已設定的服務商、Flowcy 或「在此 Mac 上」的模型。可新增多個平台產生不同版本。開啟改寫卡片，可調整語氣、目標語言與模型；透過「自訂平台…」儲存自己的平台指令。" },
    { title: "改寫、檢查並複製", body: "點選「全部改寫」，或在單筆詳細頁點選「改寫」。閱讀結果，提供「前／後」對照時可切換查看。調整語氣或模型後點選「重新生成」。也可直接編輯輸出，然後複製。人性化遵循設定中的配置，對話會自動儲存於歷史記錄。" },
  ], note: "這裡的「微調」指打磨文字，FineText 不會訓練或修改模型權重。請核對事實，並確認結果仍符合你的表達習慣。" },
];
export function tutorialsFor(locale: Locale): Tutorial[] { return locale === "en" ? en : locale === "zh-CN" ? cn : tw; }
export function tutorialUI(locale: Locale) {
  if (locale === "en") return { title: "A good start. A better draft.", label: "TUTORIALS", nav: "Tutorials", intro: "Set up a model your way. Then turn your first draft into something worth sharing.", home: "Home", all: "All tutorials", open: "Read guide", enlarge: "Enlarge screenshot", close: "Close", next: "Next guide", note: "Good to know", steps: "Step by step", section: "Make yourself at home.", sectionBody: "A few small steps from a fresh install to your first polished draft." };
  if (locale === "zh-CN") return { title: "从轻松上手，到出色表达。", label: "使用教程", nav: "教程", intro: "按你的方式配置模型，再将第一份草稿打磨成值得分享的文字。", home: "首页", all: "全部教程", open: "阅读教程", enlarge: "放大截图", close: "关闭", next: "下一篇教程", note: "使用提示", steps: "操作步骤", section: "让 FineText 成为你的写作伙伴。", sectionBody: "从安装到第一份出色的草稿，只需几步。" };
  return { title: "從輕鬆上手，到出色表達。", label: "使用教學", nav: "教學", intro: "依你的方式設定模型，再將第一份草稿打磨成值得分享的文字。", home: "首頁", all: "全部教學", open: "閱讀教學", enlarge: "放大截圖", close: "關閉", next: "下一篇教學", note: "使用提示", steps: "操作步驟", section: "讓 FineText 成為你的寫作夥伴。", sectionBody: "從安裝到第一份出色的草稿，只需幾步。" };
}
