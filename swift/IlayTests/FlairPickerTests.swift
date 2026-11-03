import XCTest
@testable import Ilay

/// Port of Kotlin's FlairPickerTest.
final class FlairPickerTests: XCTestCase {
    private func template(_ json: String) -> Flair { Flair.fromJson(parseJsonOrNull(json)!) }

    func testV2TemplateKeepsColoursEditableAndEmoji() {
        let f = template("""
            {"id":"abc","text":":star: Discussion","text_editable":true,"background_color":"#FF4500","text_color":"light",
             "type":"richtext","richtext":[{"e":"emoji","a":":star:","u":"https://emoji.redditmedia.com/s.png"},{"e":"text","t":" Discussion"}]}
            """)
        XCTAssertEqual(f.id, "abc")
        XCTAssertEqual(f.text, ":star: Discussion")
        XCTAssertTrue(f.editable)
        XCTAssertEqual(f.backgroundColor, 0xFF4500)
        XCTAssertTrue(f.lightText)
        XCTAssertEqual(f.label?.parts, [FlairPart(emojiUrl: "https://emoji.redditmedia.com/s.png"), FlairPart(text: " Discussion")])
    }

    func testPlainTemplateWithoutColour() {
        let f = template(#"{"id":"x","text":"Meta","text_editable":false,"background_color":"","text_color":"dark","richtext":[]}"#)
        XCTAssertFalse(f.editable)
        XCTAssertNil(f.backgroundColor)
        XCTAssertFalse(f.lightText)
        XCTAssertEqual(f.label?.text, "Meta")
    }

    func testTransparentBackgroundReadsAsNone() {
        XCTAssertNil(template(#"{"id":"x","text":"A","background_color":"transparent"}"#).backgroundColor)
    }

    private let flairs = [
        Flair(id: "1", text: "Question"),
        Flair(id: "2", text: ":star: Discussion", label: UserFlair(parts: [FlairPart(emojiUrl: "u"), FlairPart(text: " Discussion")])),
        Flair(id: "3", text: "Bug report"),
    ]

    func testBlankSearchShowsEveryFlair() {
        XCTAssertEqual(filterFlairs(flairs, "  "), flairs)
    }

    func testSearchMatchesWordsInAnyCaseNotEmojiCodes() {
        XCTAssertEqual(filterFlairs(flairs, "disc").map(\.id), ["2"])
        XCTAssertEqual(filterFlairs(flairs, " BUG ").map(\.id), ["3"])
        XCTAssertEqual(filterFlairs(flairs, "star").map(\.id), [])
    }

    private func form(_ flair: Flair?) -> [String] {
        RedditRepository.postFlairForm("t3_p1", flair).map { "\($0.0)=\($0.1 ?? "")" }
    }

    func testSelectflairFormForAPostFlair() {
        XCTAssertEqual(form(Flair(id: "1", text: "Question")), ["api_type=json", "link=t3_p1", "flair_template_id=1"])
    }

    func testSelectflairFormSendsYourTextOnlyForAnEditableFlair() {
        XCTAssertEqual(form(Flair(id: "2", text: "My words", editable: true)), ["api_type=json", "link=t3_p1", "flair_template_id=2", "text=My words"])
    }

    func testSelectflairFormWithoutATemplateRemovesTheFlair() {
        XCTAssertEqual(form(nil), ["api_type=json", "link=t3_p1"])
    }
}
