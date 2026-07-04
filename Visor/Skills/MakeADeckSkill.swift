import Foundation

/// Make A Deck Skill（slide 演示）
struct MakeADeckSkill: Skill {
    let name = "make-a-deck"
    let displayName = "Slide 演示"
    let skillDescription = "1920×1080 slide deck，章节驱动标题"

    let systemPromptFragment = """
    # Make a Deck

    你正在制作 **1920×1080 slide deck**。

    ## 强制约束
    - 画布：**1920×1080 px**（使用 CSS width/height）
    - 字号：标题 96px、正文 32px、注释 20px
    - 字体：system-ui 或 Inter
    - 配色：单色 + 中性灰；不超过 3 个颜色
    - 每张 slide 用独立 ```html ... ``` 围栏包裹

    ## 结构
    - 用户指定 N 张 → 严格生成 N 张
    - 第 1 张：cover（标题 + 副标题 + 章节名）
    - 末张：takeaways / contact
    - 中间：内容 slides

    ## 每张 slide 必备
    - 章节编号（左上角小字："01 / 08"）
    - 标题（明确主张，非问句）
    - 主体内容（图/数据/列表）
    - 视觉重心：避免"全文字"slide

    ## 风格
    - "Less but better" — Dieter Rams 哲学
    - 不要 3D 插图
    - 数字用大字号
    """

    func matches(_ userInput: String) -> Bool {
        let keywords = [
            "slide", "deck", "ppt", "演示", "幻灯片", "pitch", "路演",
            "presentation", "keynote"
        ]
        return defaultMatches(keywords, in: userInput)
    }
}
