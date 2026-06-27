import Foundation

enum MedicineTags {
    /// Preset tag IDs shown in the add/edit form and returned by AI recognition.
    static let all: [String] = [
        "antibiotic",
        "cold",
        "fever",
        "cough",
        "pain",
        "anti_inflammatory",
        "stomach",
        "digestion",
        "external",
        "skin",
        "eye",
        "allergy",
        "vitamin",
        "supplement",
        "cardiovascular",
        "diabetes",
        "sleep",
        "pediatric",
        "gynecology",
        "liver",
        "bone",
        "firstaid"
    ]

    static let tagDescriptionsForPrompt: String = """
    antibiotic=抗生素, cold=感冒药, fever=退烧药, cough=止咳药, pain=止痛药, \
    anti_inflammatory=消炎药, stomach=肠胃药, digestion=消化助剂, external=外用药, \
    skin=皮肤用药, eye=眼科用药, allergy=抗过敏, vitamin=维生素, supplement=保健品, \
    cardiovascular=心血管, diabetes=糖尿病, sleep=助眠, pediatric=儿童用药, \
    gynecology=妇科, liver=护肝, bone=骨骼关节, firstaid=急救
    """

    static func normalize(_ raw: [String]?) -> [String] {
        guard let raw else { return [] }
        let allowed = Set(all)
        var seen = Set<String>()
        var result: [String] = []
        for item in raw {
            let key = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard allowed.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(key)
        }
        return result
    }
}
