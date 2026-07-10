import Foundation

/// Make A Deck Skill（slide 演示）
struct MakeADeckSkill: Skill {
    let name = "make-a-deck"
    var displayName: String { "skill.makeADeck".l }
    var skillDescription: String { "skill.makeADeck".l }

    var systemPromptFragment: String {
        PromptLocalizer.text(named: "skill_make_a_deck")
    }

    func matches(_ userInput: String) -> Bool {
        let keywords = [
            "slide", "deck", "ppt", "演示", "幻灯片", "pitch", "路演",
            "presentation", "keynote", "présentation", "présenter"
        ]
        return defaultMatches(keywords, in: userInput)
    }
}
