import Foundation

// MARK: - 打工人语录
class WorkerQuotes {
    static let shared = WorkerQuotes()
    private var quotes: [String] = []

    private var quotesFilePath: String {
        let dir = SettingsManager.shared.appSupportDir
        return dir + "/quotes.txt"
    }

    private static let builtinQuotes = """
    # DesktopPet 语录文件
    # 一行一条语录，空行和 # 开头的行会被忽略
    # 你可以自由编辑、添加、删除语录，保存后下次说话时生效
    #
    # ── 经典打工人 ──
    别催了在写了在写了💦
    这需求做完我就辞职
    今天也是想躺平的一天
    摸鱼5分钟 工作2小时
    工资是不可能涨的
    已经不知道在写什么了
    好想下班啊啊啊
    干完这票就收手
    需求又改了？？？
    我不是在加班 是在卖命
    CPU在燃烧 我也在燃烧
    电脑不关机 打工不停歇
    这bug又不是我写的
    上班如上坟 干活如渡劫
    代码能跑就行 别问为什么
    老板看到赶紧关掉
    月初发工资 月底吃泡面
    偷偷打开Boss直聘
    只是假装很忙的样子
    不是我不努力 是IDE太慢
    下班倒计时中...
    再改需求我真跑路了
    打工人打工魂😭
    对不起 我是废物
    看看工资 又有动力了吗 没有
    先摸为敬🐟
    我命由天不由我
    这是我最后一份工了
    精神状态: 摇摇欲坠
    上班=被迫营业
    头发比代码掉得快
    外面的世界不属于我
    有一种累叫心累
    已读不回是对需求最大的尊重
    写字楼里的牛马
    谢谢 有被工作到
    认真工作.jpg(假的)
    等等 我先发个疯
    不是 哥们 又有需求？
    i人勿扰 正在假装社死
    #
    # ── 牛马发疯篇 ──
    牛马累了会自己冲咖啡
    淡淡的疯感和平静的癫
    别想拧我 我扎手
    虽然啥也没干 但真的辛苦我了
    按时到工位已经很厉害了
    我在公司很想家
    不想开会不想开会不想开会
    甩锅是技术 更是艺术
    清醒程度取决于咖啡浓度
    有些工作就像污渍 拖一拖就没了
    都市隶人 在线卖命
    打工而已 不必上头
    有情绪不发泄 憋着干嘛
    成熟一点 焦虑不值钱
    #
    # ── 摸鱼哲学篇 ──
    努力不一定被看到 摸鱼一定会
    咖啡苦可以加奶 工作苦不能加薪
    我放不下工作 工作也放不下我
    老板掏心掏肺 就是不肯掏钱
    只要我够努力 老板就能过上他想要的生活
    干不完的活 睡不够的觉
    喂不胖的钱包 买不起的貂
    人可以不吃饭 但不能不打工
    不缺王子 我缺觉
    有些事情熬一熬就过去了吧
    #
    # ── 班味儿篇 ──
    一身班味 无处可藏
    每天好饿好累好想睡
    七八个闹钟都起不来
    迟到扣钱 所以不敢迟到
    上班第一件事: 看还有几天放假
    每次加班像在给世界写遗书
    压力是别人给的 花是自己开的
    在工位静静地撒野
    又菜又爱卷 容易被手撕
    骑共享单车的手不能擦眼泪
    #
    # ── 精神状态篇 ──
    今天的精神状态像个emoji
    脑子已经下班了 身体还在工位
    我的热情已经被KPI浇灭了
    心态崩了但还在假笑
    灵魂出窍 肉体打卡
    表面在开会 灵魂已飘走
    工作使我面目全非
    眼神呆滞 双手不停
    我不想努力了 有没有富婆
    身体在加班 心已在三亚
    一到周一就犯困 一到周五就清醒
    #
    # ── 嘴替篇 ──
    这点工资还想让我怎样
    下班了 这周的苦就吃到这里
    累不累的先干着吧
    钱没到位 什么都不对
    不是不想干 是真的干不动了
    你说得都对 但我想下班
    在搞钱和发疯之间反复横跳
    还能怎样呢 先活着吧
    一天班上的 我啥也不是了
    薪尽自然凉
    打工打的就是一个寂寞
    上班恐惧 下班心虚
    就这?就这??就这???
    正在渡劫 请勿打扰
    """

    init() {
        ensureFileExists()
        loadQuotes()
    }

    private func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: quotesFilePath) else { return }
        // 首次启动，写入内置语录
        try? WorkerQuotes.builtinQuotes.write(toFile: quotesFilePath, atomically: true, encoding: .utf8)
    }

    private func loadQuotes() {
        guard let content = try? String(contentsOfFile: quotesFilePath, encoding: .utf8) else {
            quotes = ["打工ing..."]
            return
        }
        quotes = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        if quotes.isEmpty {
            quotes = ["打工ing..."]
        }
    }

    func reload() {
        loadQuotes()
    }

    static func random() -> String {
        shared.quotes.randomElement() ?? "打工ing..."
    }
}
