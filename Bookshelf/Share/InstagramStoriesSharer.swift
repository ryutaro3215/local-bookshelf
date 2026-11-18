import Foundation
import UIKit
import os

/// Instagram ストーリーズへ画像を渡す（Meta の「ストーリーズへのシェア」。F8-7）。
/// アプリ自身は通信しない。画像をペーストボードに置き、Instagram アプリを開くだけ（S1 と矛盾しない）。
/// Meta の App ID が必要。Info.plist のキー `MetaAppID` に入れる（オーナーが Meta の開発者登録をして用意する）
@MainActor
enum InstagramStoriesSharer {
    /// Info.plist の App ID のキー
    static let appIDKey = "MetaAppID"
    /// ペーストボードの種類（Meta の仕様）
    static let backgroundImageType = "com.instagram.sharedSticker.backgroundImage"
    static let appIDType = "com.instagram.sharedSticker.appID"
    /// ペーストボードに置いた画像を消すまでの時間
    static let expiration: TimeInterval = 5 * 60

    enum Outcome: Equatable {
        /// Instagram を開いた
        case opened
        /// App ID が設定されていない（共有シートで渡す）
        case missingAppID
        /// Instagram が入っていない・開けなかった（共有シートで渡す）
        case unavailable
    }

    private static let logger = Logger(subsystem: "com.ryutaro3215.bookshelf", category: "Share")

    /// Info.plist の App ID（数字だけのときだけ使う）
    static var appID: String? {
        validated(Bundle.main.object(forInfoDictionaryKey: appIDKey) as? String)
    }

    static func validated(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
            value.allSatisfy(\.isASCII), value.allSatisfy(\.isNumber)
        else { return nil }
        return value
    }

    /// ストーリーズを開く URL（instagram-stories://share?source_application=<App ID>）
    static func storiesURL(appID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "instagram-stories"
        components.host = "share"
        components.queryItems = [URLQueryItem(name: "source_application", value: appID)]
        return components.url
    }

    /// 9:16 の画像を背景にしてストーリーズの作成画面を開く
    static func share(imageData: Data, appID: String? = Self.appID) async -> Outcome {
        guard let appID = validated(appID) else {
            logger.notice("Meta の App ID が無いので、ストーリーズは共有シートで渡す")
            return .missingAppID
        }
        guard let url = storiesURL(appID: appID) else { return .unavailable }
        UIPasteboard.general.setItems(
            [[backgroundImageType: imageData, appIDType: appID]],
            options: [.expirationDate: Date().addingTimeInterval(expiration)])
        let opened = await UIApplication.shared.open(url)
        if !opened {
            // Instagram が無い: 置いた画像をペーストボードに残さない
            UIPasteboard.general.items = []
            logger.notice("Instagram を開けなかった")
            return .unavailable
        }
        return .opened
    }
}
