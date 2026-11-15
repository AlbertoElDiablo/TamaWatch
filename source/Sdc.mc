import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Every screen is laid out for the fenix 6X: a 280 x 280 round display. On any other watch the
// views draw through this stand-in for the Dc, which scales those 280-pixel coordinates to the
// real screen (by its shorter side) and centres them: boxes, lines, clips and pictures grow or
// shrink with it, text sits where it was meant to (its capitals centred on the same spot), and
// text is drawn in the fenix 6X's own fonts at that scale (tools/make_scaled.py), so widths and
// heights come back in 280-pixel units and the code that fits text to a box works unchanged. On
// the fenix 6X itself the views get the real Dc and its system fonts: nothing changes.
//
// Pictures are resized ahead of time for screens that include watches without drawScaledBitmap
// (before Connect IQ 4); elsewhere they are scaled as they are drawn.
module Scr {
    const DESIGN = 280;
    // the fenix 6X's font heights (XTINY, TINY, SMALL, MEDIUM, LARGE, NUMBER_MEDIUM), and how far
    // below the drawing y the middle of its capitals sits (see capY)
    const H280 = [19, 31, 34, 40, 43, 79];
    const MID = [11, 17, 18, 22, 22, 39];

    var k = null;          // the scale: real pixels per 280-pixel unit
    var ox = 0;            // where the 280 square starts on the real screen
    var oy = 0;
    var nativeUi = false;    // the fenix 6X: its own Dc and fonts, untouched
    var prescaled = false; // the pictures were resized for this screen (tools/make_scaled.py)
    var scaled = false;    // the watch can scale bitmaps as it draws them
    var thumbNative = false;   // the thumbnail atlas is the 280-pixel one (too big enlarged)
    var sysFonts = false;  // the watch's own fonts: on the fenix-style (MIP) screens they're this same
                           // Roboto Condensed Bold, hand-tuned for the screen and easier to read than ours
    var fonts = [null, null, null, null, null, null];

    function setup(w, h) {
        if (k != null) { return; }
        var s = w < h ? w : h;
        k = s.toFloat() / DESIGN;
        ox = (w - s) / 2;
        oy = (h - s) / 2;
        nativeUi = WatchUi.loadResource(Rez.Strings.NativeUi).equals("1") && w == DESIGN && h == DESIGN;
        prescaled = WatchUi.loadResource(Rez.Strings.ScaleInfo).equals("1");
        scaled = (Graphics.Dc has :drawScaledBitmap);
        thumbNative = WatchUi.loadResource(Rez.Strings.ThumbNative).equals("1");
        sysFonts = WatchUi.loadResource(Rez.Strings.SysFonts).equals("1");
    }

    // The real Dc on the fenix 6X, else the scaling stand-in.
    function wrap(dc) {
        setup(dc.getWidth(), dc.getHeight());
        if (nativeUi) { return dc; }
        return new Sdc(dc);
    }

    function fontIx(f) {
        if (f == Graphics.FONT_XTINY) { return 0; }
        if (f == Graphics.FONT_TINY) { return 1; }
        if (f == Graphics.FONT_SMALL) { return 2; }
        if (f == Graphics.FONT_MEDIUM) { return 3; }
        if (f == Graphics.FONT_LARGE) { return 4; }
        if (f == Graphics.FONT_NUMBER_MEDIUM) { return 5; }
        return -1;
    }

    // The fenix 6X's font, drawn at this screen's scale (loaded the first time it's used).
    function font(f) {
        var i = fontIx(f);
        if (i < 0 || sysFonts) { return f; }
        if (fonts[i] == null) {
            var ids = [Rez.Fonts.f0, Rez.Fonts.f1, Rez.Fonts.f2, Rez.Fonts.f3, Rez.Fonts.f4, Rez.Fonts.f5];
            fonts[i] = WatchUi.loadResource(ids[i]);
        }
        return fonts[i];
    }
}

class Sdc {
    var dc;
    var k;
    var ox;
    var oy;
    var clip = null;      // the clip in 280-pixel units, for drawing one cell of a picture strip

    function initialize(d) {
        dc = d;
        k = Scr.k;
        ox = Scr.ox;
        oy = Scr.oy;
    }

    function X(x) { return (ox + x * k + 0.5).toNumber(); }
    function Y(y) { return (oy + y * k + 0.5).toNumber(); }
    function L(n) { var v = (n * k + 0.5).toNumber(); return v < 1 && n > 0 ? 1 : v; }

    function getWidth() { return Scr.DESIGN; }
    function getHeight() { return Scr.DESIGN; }

    function setColor(f, b) { dc.setColor(f, b); }
    function clear() { dc.clear(); }
    function setPenWidth(w) { dc.setPenWidth(L(w)); }

    // the fonts are the fenix 6X's at this scale, so a text is where, and as wide as, it was there
    function getTextWidthInPixels(t, f) { return (dc.getTextWidthInPixels(t, Scr.font(f)) / k + 0.5).toNumber(); }
    function getFontHeight(f) {
        var i = Scr.fontIx(f);
        return i >= 0 && !Scr.sysFonts ? Scr.H280[i] : (Graphics.getFontHeight(f) / k).toNumber();
    }
    // Our fonts are the fenix 6X's at this scale: drawn at the scaled y. The watch's own fonts have
    // their own proportions: their capitals are centred where the fenix 6X's would be.
    function drawText(x, y, f, t, j) {
        var i = Scr.fontIx(f);
        if (!Scr.sysFonts || i < 0) { dc.drawText(X(x), Y(y), Scr.font(f), t, j); return; }
        var hd = Graphics.getFontHeight(f);
        dc.drawText(X(x), Y(y + Scr.MID[i]) - hd * Scr.MID[i] / Scr.H280[i], f, t, j);
    }

    function fillRectangle(x, y, w, h) { dc.fillRectangle(X(x), Y(y), X(x + w) - X(x), Y(y + h) - Y(y)); }
    function drawRectangle(x, y, w, h) { dc.drawRectangle(X(x), Y(y), X(x + w) - X(x), Y(y + h) - Y(y)); }
    function fillRoundedRectangle(x, y, w, h, r) { dc.fillRoundedRectangle(X(x), Y(y), X(x + w) - X(x), Y(y + h) - Y(y), L(r)); }
    function drawRoundedRectangle(x, y, w, h, r) { dc.drawRoundedRectangle(X(x), Y(y), X(x + w) - X(x), Y(y + h) - Y(y), L(r)); }
    function fillCircle(x, y, r) { dc.fillCircle(X(x), Y(y), L(r)); }
    function drawCircle(x, y, r) { dc.drawCircle(X(x), Y(y), L(r)); }
    function fillEllipse(x, y, a, b) { dc.fillEllipse(X(x), Y(y), L(a), L(b)); }
    function drawLine(x1, y1, x2, y2) { dc.drawLine(X(x1), Y(y1), X(x2), Y(y2)); }

    function fillPolygon(pts) {
        var p = new [pts.size()];
        for (var i = 0; i < pts.size(); i++) { p[i] = [X(pts[i][0]), Y(pts[i][1])]; }
        dc.fillPolygon(p);
    }

    function setClip(x, y, w, h) {
        clip = [x, y, w, h];
        dc.setClip(X(x), Y(y), X(x + w) - X(x), Y(y + h) - Y(y));
    }
    function clearClip() { clip = null; dc.clearClip(); }

    function R(v) { return Math.floor(v * k + 0.5).toNumber(); }

    // pictures already resized for this screen are drawn as they are; else scaled as drawn
    // A clipped picture is one cell of a strip (icons, badges, animation frames): the picture is
    // placed from the clip's corner and the clip fitted to where that cell landed in the scaled
    // strip, so the rounding never shows a pixel of the next cell.
    function drawBitmap(x, y, b) {
        var bx = X(x);
        var by = Y(y);
        if (clip != null) {
            var dx = clip[0] - x;
            var dy = clip[1] - y;
            var cx = X(clip[0]);
            var cy = Y(clip[1]);
            bx = cx - R(dx);
            by = cy - R(dy);
            dc.setClip(cx, cy, R(dx + clip[2]) - R(dx), R(dy + clip[3]) - R(dy));
        }
        if (Scr.prescaled || k == 1.0 || !Scr.scaled) {
            dc.drawBitmap(bx, by, b);
        } else {
            dc.drawScaledBitmap(bx, by, L(b.getWidth()), L(b.getHeight()), b);
        }
    }
}
