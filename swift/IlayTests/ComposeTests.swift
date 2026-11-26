import XCTest
@testable import Ilay

/// Port of Kotlin's LengthLimitTest.
final class ComposeTests: XCTestCase {
    func testCountsCodePointsAsRedditDoes() {
        XCTAssertEqual(redditLength("hello"), 5)
        XCTAssertEqual(redditLength("😀"), 1)
        // A skin tone is its own code point, as Reddit counts it (one grapheme to Swift).
        XCTAssertEqual(redditLength("👍🏽"), 2)
        XCTAssertEqual(redditLength(""), 0)
    }

    func testCounterShowsOnlyNearTheLimit() {
        XCTAssertNil(lengthCounter(String(repeating: "a", count: 269), limit: TextLimit.title))
        XCTAssertEqual(lengthCounter(String(repeating: "a", count: 270), limit: TextLimit.title), "270 / 300")
        XCTAssertEqual(lengthCounter(String(repeating: "a", count: 301), limit: TextLimit.title), "301 / 300")
        XCTAssertNil(lengthCounter(String(repeating: "a", count: 8999), limit: TextLimit.comment))
        XCTAssertEqual(lengthCounter(String(repeating: "a", count: 9000), limit: TextLimit.comment), "9000 / 10000")
        XCTAssertEqual(lengthCounter(String(repeating: "a", count: 40001), limit: TextLimit.postBody), "40001 / 40000")
    }

    func testPosterFallsBackToABlackFrameNotTheVideo() async {
        // Not a video: the poster must still be a JPEG, never these bytes.
        let notVideo = Data("not a video".utf8)
        let poster = await posterFrame(notVideo)
        XCTAssertNotEqual(poster, notVideo)
        XCTAssertEqual(Array(poster.prefix(2)), [0xFF, 0xD8]) // JPEG
    }

    // #296: a filepath lease makes Reddit report the image failed (a title-only post).
    func testAnImageLeasesWithoutAFilepath() {
        XCTAssertEqual(MediaUpload.leaseParams("image.png", mimeType: "image/png").map(\.0), ["mimetype"])
        XCTAssertEqual(MediaUpload.leaseParams("clip.mp4", mimeType: "video/mp4").map(\.0), ["filepath", "mimetype"])
    }

    func testTheUploadFormatComesFromTheBytes() {
        XCTAssertEqual(MediaUpload.imageMimeType(Data([0xFF, 0xD8, 0xFF, 0xE0]), fallback: "image/png"), "image/jpeg")
        XCTAssertEqual(MediaUpload.imageMimeType(Data([0x89]) + Data("PNG".utf8), fallback: "image/jpeg"), "image/png")
        XCTAssertEqual(MediaUpload.imageMimeType(Data("GIF89a".utf8), fallback: "image/jpeg"), "image/gif")
        XCTAssertEqual(MediaUpload.imageMimeType(Data("RIFF\0\0\0\0WEBPVP8 ".utf8), fallback: "image/jpeg"), "image/webp")
        XCTAssertEqual(MediaUpload.imageMimeType(Data([1, 2]), fallback: "image/jpeg"), "image/jpeg")
        XCTAssertEqual(MediaUpload.fileName("image.jpg", mimeType: "image/png"), "image.png")
        XCTAssertEqual(MediaUpload.fileName("photo", mimeType: "image/webp"), "photo.webp")
        XCTAssertEqual(MediaUpload.fileName("clip.mp4", mimeType: "video/mp4"), "clip.mp4")
    }

    func testReadsTheUploadFormWrappedOrBareAndS3sAnswer() throws {
        let wrapped = try AppJson.parse(#"{"args":{"action":"//a.example","fields":[]},"asset":{"asset_id":"x"}}"#)
        let bare = try AppJson.parse(#"{"action":"//b.example","fields":[]}"#)
        XCTAssertEqual(MediaUpload.uploadForm(wrapped)["action"].str(), "//a.example")
        XCTAssertEqual(MediaUpload.uploadForm(bare)["action"].str(), "//b.example")
        let xml = "<PostResponse><Location>https://u.example/abc?x=1&amp;y=2</Location><Key>abc</Key></PostResponse>"
        XCTAssertEqual(MediaUpload.xmlTag(xml, "Location"), "https://u.example/abc?x=1&y=2")
        XCTAssertEqual(MediaUpload.xmlTag(xml, "Key"), "abc")
        XCTAssertNil(MediaUpload.xmlTag("<Error/>", "Location"))
    }
}
