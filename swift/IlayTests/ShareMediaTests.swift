import XCTest
@testable import Ilay

/// "Share as media" finds a Reddit video's sound in its DASH playlist.
final class ShareMediaTests: XCTestCase {
    private func mpd(_ audio: String) -> String {
        """
        <MPD><Period>
          <AdaptationSet contentType="video" id="1">
            <Representation bandwidth="169464" codecs="avc1.4d401e" id="5" mimeType="video/mp4">
              <BaseURL>CMAF_220.mp4</BaseURL>
            </Representation>
            <Representation bandwidth="1200000" id="6" mimeType="video/mp4"><BaseURL>CMAF_720.mp4</BaseURL></Representation>
          </AdaptationSet>
          \(audio)
        </Period></MPD>
        """
    }

    func testAVideoWithoutSoundHasNoAudioTrack() {
        XCTAssertNil(audioTrack(mpd("")))
    }

    func testPicksTheBestAudioCmafNaming() {
        let audio = """
        <AdaptationSet contentType="audio" id="2">
          <Representation audioSamplingRate="48000" bandwidth="65000" codecs="mp4a.40.2" id="7" mimeType="audio/mp4">
            <AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="2" />
            <BaseURL>CMAF_AUDIO_64.mp4</BaseURL>
          </Representation>
          <Representation audioSamplingRate="48000" bandwidth="131000" codecs="mp4a.40.2" id="8" mimeType="audio/mp4">
            <BaseURL>CMAF_AUDIO_128.mp4</BaseURL>
          </Representation>
        </AdaptationSet>
        """
        XCTAssertEqual(audioTrack(mpd(audio)), "CMAF_AUDIO_128.mp4")
    }

    func testOlderPlaylistsMarkAudioByMimeTypeOnlyDashNaming() {
        let audio = #"<AdaptationSet id="2" mimeType="audio/mp4"><Representation bandwidth="128000" id="9"><BaseURL>DASH_audio.mp4</BaseURL></Representation></AdaptationSet>"#
        XCTAssertEqual(audioTrack(mpd(audio)), "DASH_audio.mp4")
    }

    func testTheRealNoSoundPlaylistFromVReddIt() {
        let real = #"<MPD><Period duration="PT8.066667S" id="0"><AdaptationSet contentType="video" id="1" maxFrameRate="15360/512"><Representation bandwidth="169464" codecs="avc1.4d401e" frameRate="15360/512" height="220" id="5" mimeType="video/mp4" width="220"><BaseURL>CMAF_220.mp4</BaseURL><SegmentBase indexRange="871-938" timescale="15360"><Initialization range="0-870" /></SegmentBase></Representation></AdaptationSet></Period></MPD>"#
        XCTAssertNil(audioTrack(real))
    }
}

/// Not a Kotlin test: which card gets the one inline player.
final class InlineVideoPoolTests: XCTestCase {
    func testNothingPastTheThresholdPlaysNothing() {
        XCTAssertNil(InlineVideoPool.choose([0, 0.3, 0.6], current: nil))
    }

    func testTheMostVisibleCardWinsTheFirstOnATie() {
        XCTAssertEqual(InlineVideoPool.choose([0.65, 0.9, 0.9], current: nil), 1)
    }

    func testThePlayingCardKeepsThePlayerWhileAboutAsVisible() {
        XCTAssertEqual(InlineVideoPool.choose([0.85, 0.9], current: 0), 0)
        XCTAssertEqual(InlineVideoPool.choose([0.8, 0.9], current: 0), 1)
    }

    func testAPlayingCardBelowTheThresholdLosesThePlayer() {
        XCTAssertEqual(InlineVideoPool.choose([0.6, 0.65], current: 0), 1)
        XCTAssertNil(InlineVideoPool.choose([0.5], current: 0))
    }
}
