import Toybox.Lang;
import Toybox.WatchUi;

// The Pokedex thumbnails: one atlas of 16 x 10 cells of 38 px (tools/make_thumbs.py), colour and
// silhouette, each loaded the first time a screen draws from it and let go when it closes.
module Thumbs {
    const C = 38;
    var atlas = null;
    var sils = null;

    // Thumbnail n with its top-left corner at (x, y), clipped to its own 38 x 38 square.
    function draw(dc, n, x, y, sil) {
        var b;
        if (sil) {
            if (sils == null) { sils = WatchUi.loadResource(Rez.Drawables.thumbs_sil); }
            b = sils;
        } else {
            if (atlas == null) { atlas = WatchUi.loadResource(Rez.Drawables.thumbs); }
            b = atlas;
        }
        if (Scr.thumbNative && dc instanceof Sdc) {
            // the 280-pixel atlas on an enlarged screen: centred in the enlarged cell
            var pad = ((C * Scr.k - C) / 2).toNumber();
            var px = dc.X(x) + pad;
            var py = dc.Y(y) + pad;
            dc.dc.setClip(px, py, C, C);    // just this thumbnail (the caller clears the clip)
            dc.dc.drawBitmap(px - ((n - 1) % 16) * C, py - ((n - 1) / 16) * C, b);
        } else {
            // just this thumbnail: shifted to sit centred in its box, the box would otherwise show
            // the edge of its neighbour in the atlas (the caller clears the clip)
            dc.setClip(x, y, C, C);
            dc.drawBitmap(x - ((n - 1) % 16) * C, y - ((n - 1) / 16) * C, b);
        }
    }

    function clear() { atlas = null; sils = null; }
}
