import XCTest
@testable import Ilay

final class JsonTests: XCTestCase {
    func testAccessorsNeverAssumeAShape() {
        let j = json(#"{"a":{"b":[1,"x",true,null,2.5]},"s":"","f":false,"n":null}"#)
        XCTAssertEqual(j["a"]["b"][0].int(), 1)
        XCTAssertEqual(j["a"]["b"][1].str(), "x")
        XCTAssertEqual(j["a"]["b"][2].bool(), true)
        XCTAssertEqual(j["a"]["b"][4].double(), 2.5)
        XCTAssertEqual(j["a"]["b"][4].long(), 2)
        XCTAssertNil(j["a"]["b"][9])
        XCTAssertNil(j["s"]["deep"]["er"])
        XCTAssertNil(j["f"].str())
        XCTAssertNil(j["n"].str())
        XCTAssertNil(j["a"]["b"][1].int(), "a string isn't a number")
        XCTAssertNil(json(#""true""#).bool(), "a string isn't a boolean")
        XCTAssertFalse(j["missing"].isTrue())
    }

    func testKeepsKeyOrderAndWholeNumbers() {
        let text = #"{"z":1,"a":2.5,"m":[true,null],"k":{"y":"é\n\"q\"","b":1700000000000}}"#
        XCTAssertEqual(json(text).encoded(), text.replacingOccurrences(of: "é", with: "é"))
        XCTAssertEqual(json(text).obj()?.keys, ["z", "a", "m", "k"])
    }

    func testEscapes() {
        XCTAssertEqual(json(#""\u00e9\ud83d\ude00\t\/""#).str(), "é😀\t/")
        XCTAssertEqual(JsonElement.string("a\"b\\c\n\u{1}").encoded(), #""a\"b\\c\n\u0001""#)
    }

    func testBigNumbersAndExponents() {
        XCTAssertEqual(json("1793307492.7951").double(), 1793307492.7951)
        XCTAssertEqual(json("1e3").double(), 1000)
        XCTAssertEqual(json("-5").int(), -5)
        XCTAssertEqual(json("1e30").long(), Int.max)
    }

    func testRejectsBadJson() {
        for bad in ["", "{", "[1,", "{\"a\"}", "tru", "1 2", "{\"a\":1,}"] {
            XCTAssertNil(parseJsonOrNull(bad), bad)
        }
    }

    func testPrettyParsesBackToTheSame() {
        let j = json(#"{"a":[1,{"b":"c"}],"d":{},"e":[]}"#)
        XCTAssertEqual(json(j.pretty()), j)
        XCTAssertTrue(j.pretty().contains("\n  \"a\": ["))
    }

    func testOrderedMapReinsertGoesLast() {
        var m = OrderedMap<Int>()
        m["a"] = 1
        m["b"] = 2
        m["a"] = 3
        XCTAssertEqual(m.keys, ["a", "b"], "a value update keeps its place")
        m.removeValue(forKey: "a")
        m["a"] = 4
        XCTAssertEqual(m.keys, ["b", "a"])
        m.removeFirst()
        XCTAssertEqual(m.keys, ["a"])
        XCTAssertEqual(m.count, 1)
    }

    func testFormAndQueryEncoding() {
        let body = String(decoding: formEncoded([("a b", "c+d&e=é"), ("skip", nil), ("x", "1")]), as: UTF8.self)
        XCTAssertEqual(body, "a+b=c%2Bd%26e%3D%C3%A9&x=1")
    }
}
