import 'package:flutter/widgets.dart';

/// Pixel width to decode full-width feed images at: the screen's width.
///
/// Without it every image decodes at its source size — a direct i.redd.it
/// link can be 4000px wide for a card a tenth of that — which drops frames
/// while scrolling and evicts the rest of the image cache, so scrolling back
/// decodes everything again. Images narrower than this are never upscaled.
int feedDecodeWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
        .round();
