import Foundation

/// ジャンルの区分（requirements §10.6）。データとして持ち、一覧の見出しに使う。
struct GenreCategory: Sendable, Equatable {
    let id: String
    let name: String
    let nameEn: String
}

/// 初期ジャンル（requirements §10.6。表の順を初期の並び順とする）。
enum InitialGenres {
    static let literature = GenreCategory(id: "literature", name: "文芸", nameEn: "Literature")
    static let humanities = GenreCategory(id: "humanities", name: "人文", nameEn: "Humanities")
    static let society = GenreCategory(id: "society", name: "社会", nameEn: "Social Sciences")
    static let science = GenreCategory(id: "science", name: "自然科学", nameEn: "Science")
    static let technology = GenreCategory(id: "technology", name: "技術・医療", nameEn: "Technology & Medicine")
    static let arts = GenreCategory(id: "arts", name: "芸術・生活", nameEn: "Arts & Lifestyle")
    /// ユーザーが追加したジャンル用
    static let myGenres = GenreCategory(id: "my", name: "マイジャンル", nameEn: "My Genres")
    /// 買いたい本・未分類の区分（内部では「システム」。表示名は「その他」）
    static let system = GenreCategory(id: "system", name: "その他", nameEn: "Other")

    static let categories: [GenreCategory] = [
        literature, humanities, society, science, technology, arts, myGenres, system,
    ]

    /// (区分, 日本語名, 英語名)
    static let genres: [(category: GenreCategory, name: String, nameEn: String)] = [
        (literature, "小説", "Fiction"),
        (literature, "エッセイ", "Essays"),
        (literature, "詩歌", "Poetry"),
        (literature, "漫画", "Manga"),
        (literature, "絵本・児童書", "Children's Books"),
        (humanities, "哲学・思想", "Philosophy"),
        (humanities, "宗教", "Religion"),
        (humanities, "歴史", "History"),
        (humanities, "心理", "Psychology"),
        (humanities, "言語・語学", "Languages"),
        (society, "政治・法律", "Politics & Law"),
        (society, "経済・経営", "Economics & Management"),
        (society, "ビジネス・自己啓発", "Business & Self-Help"),
        (society, "社会", "Society"),
        (society, "教育", "Education"),
        (science, "数学", "Mathematics"),
        (science, "物理", "Physics"),
        (science, "化学", "Chemistry"),
        (science, "生物", "Biology"),
        (science, "地球・宇宙", "Earth & Space"),
        (technology, "コンピュータ・IT", "Computers & IT"),
        (technology, "工学・技術", "Engineering"),
        (technology, "医学・健康", "Medicine & Health"),
        (arts, "芸術・デザイン", "Art & Design"),
        (arts, "音楽", "Music"),
        (arts, "料理・暮らし", "Cooking & Home"),
        (arts, "旅行・地理", "Travel & Geography"),
        (arts, "趣味・スポーツ", "Hobbies & Sports"),
    ]

    /// システム棚（区分「システム」で、この順に末尾に置く）
    static let wishlist = (name: "買いたい本", nameEn: "Wishlist")
    static let unsorted = (name: "未分類", nameEn: "Unsorted")
}
