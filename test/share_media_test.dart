import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/media/save_media.dart';

/// "Share as media" / save find a Reddit video's sound in its DASH playlist
/// (Kotlin's ShareMediaTest).
void main() {
  String mpd(String audio) => '''
<MPD><Period>
  <AdaptationSet contentType="video" id="1">
    <Representation bandwidth="169464" codecs="avc1.4d401e" id="5" mimeType="video/mp4">
      <BaseURL>CMAF_220.mp4</BaseURL>
    </Representation>
    <Representation bandwidth="1200000" id="6" mimeType="video/mp4"><BaseURL>CMAF_720.mp4</BaseURL></Representation>
  </AdaptationSet>
  $audio
</Period></MPD>''';

  test('a video without sound has no audio track', () {
    expect(audioTrack(mpd('')), isNull);
  });

  test('picks the best audio (CMAF naming)', () {
    const audio = '''
<AdaptationSet contentType="audio" id="2">
  <Representation audioSamplingRate="48000" bandwidth="65000" codecs="mp4a.40.2" id="7" mimeType="audio/mp4">
    <AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="2" />
    <BaseURL>CMAF_AUDIO_64.mp4</BaseURL>
  </Representation>
  <Representation audioSamplingRate="48000" bandwidth="131000" codecs="mp4a.40.2" id="8" mimeType="audio/mp4">
    <BaseURL>CMAF_AUDIO_128.mp4</BaseURL>
  </Representation>
</AdaptationSet>''';
    expect(audioTrack(mpd(audio)), 'CMAF_AUDIO_128.mp4');
  });

  test('older playlists mark audio by mimeType only (DASH naming)', () {
    const audio = '<AdaptationSet id="2" mimeType="audio/mp4">'
        '<Representation bandwidth="128000" id="9">'
        '<BaseURL>DASH_audio.mp4</BaseURL></Representation></AdaptationSet>';
    expect(audioTrack(mpd(audio)), 'DASH_audio.mp4');
  });

  test('the real no-sound playlist from v.redd.it', () {
    const real = '<MPD><Period duration="PT8.066667S" id="0">'
        '<AdaptationSet contentType="video" id="1" maxFrameRate="15360/512">'
        '<Representation bandwidth="169464" codecs="avc1.4d401e" '
        'frameRate="15360/512" height="220" id="5" mimeType="video/mp4" '
        'width="220"><BaseURL>CMAF_220.mp4</BaseURL>'
        '<SegmentBase indexRange="871-938" timescale="15360">'
        '<Initialization range="0-870" /></SegmentBase></Representation>'
        '</AdaptationSet></Period></MPD>';
    expect(audioTrack(real), isNull);
  });
}
