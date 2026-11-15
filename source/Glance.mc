import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// What the widget shows without opening the game: the pet, its name and level and what it needs,
// read from the summary PetModel.save() leaves in storage. The needs are projected forward with
// the awake drain (FOOD ~0.5/min, HYG ~0.25/min, JOY a week from full to empty).
(:glance)
module Needs {
    function summary() {
        return Storage.getValue("pet") as Dictionary?;
    }

    // [food, joy, energy, hygiene] now, estimated
    function stats(d) {
        var mins = (Time.now().value() - d["last"]) / 60;
        if (mins < 0) { mins = 0; }
        if (d["asleep"]) { mins = 0; }
        var poops = d["poops"] != null ? d["poops"] : 0;
        var e = d["energy"] != null ? d["energy"] : 50;
        var eDrain = d["bb"] == true ? 0 : mins / 4;       // with Body Battery it is yours, no drain
        return [clamp(d["food"] - mins / 2), clamp(d["joy"] - mins / 101), clamp(e - eDrain),
                clamp(d["hygiene"] - mins / 4 - poops * mins / 8)];
    }

    function clamp(v) { return v < 0 ? 0 : (v > 100 ? 100 : v); }

    function name(d) {
        if (d == null) { return "TAMAWATCH"; }
        return d["egg"] ? GT.g(GT.EGG) : d["name"].toUpper();
    }

    function level(d) {
        return (d != null && !d["egg"] && d["lv"] != null && d["lv"] > 0) ? "Lv." + d["lv"] : "";
    }

    function title(d) {
        if (d == null) { return "TAMAWATCH"; }
        if (d["egg"]) { return GT.g(GT.EGG); }
        return d["name"].toUpper() + (d["lv"] != null && d["lv"] > 0 ? " Lv." + d["lv"] : "");
    }

    // What it needs right now, in words, most urgent first (nothing when all is well).
    function needs(d) {
        var out = [];
        if (d == null) { out.add(GT.g(GT.OPEN)); return out; }
        if (d["egg"]) {
            if (d["starter"]) { out.add(GT.g(GT.STARTER)); return out; }
            var need = d["need"] != null ? d["need"] : 0;
            var left = need - (d["steps"] != null ? d["steps"] : 0);
            out.add(need > 0 && left > 0 ? GT.walk(left) : GT.g(GT.READY));
            return out;
        }
        if (d["asleep"]) { out.add(GT.g(GT.SLEEPING)); return out; }
        var s = stats(d);
        if (s[0] < 25) { out.add(GT.g(GT.HUNGRY)); }
        if (d["poops"] != null && d["poops"] > 0) { out.add(GT.g(GT.POOP)); }
        if (s[3] < 25) { out.add(GT.g(GT.BATH)); }
        if (d["restless"] == true) { out.add(GT.g(GT.MOVE)); }
        if (s[1] < 25) { out.add(GT.g(GT.TRAIN)); }
        if (s[2] < 25) { out.add(GT.g(GT.SLEEP)); }
        return out;
    }

    // The pet from its stored runs (colour << 18 | y << 12 | x << 6 | length), cropped to its own
    // outline and scaled to tall pixels high with its left edge at x; returns the width drawn.
    // An egg is drawn when there is no pet yet.
    function drawPet(dc, d, x, y, tall) {
        if (d != null && d["egg"]) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            var rx = tall * 3 / 8;
            dc.fillEllipse(x + rx, y + tall / 2, rx, tall / 2);
            dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + rx - rx / 3, y + tall / 3, tall / 10 + 1);
            dc.fillCircle(x + rx + rx / 3, y + tall * 2 / 3, tall / 8 + 1);
            return rx * 2;
        }
        var runs = Storage.getValue("gthumb") as Array?;
        if (runs == null || runs.size() == 0) { return 0; }
        var x0 = 63; var y0 = 63; var x1 = 0; var y1 = 0;
        for (var i = 0; i < runs.size(); i++) {
            var v = runs[i];
            var rx = (v >> 6) & 63;
            var ry = (v >> 12) & 63;
            if (rx < x0) { x0 = rx; }
            if (ry < y0) { y0 = ry; }
            if (rx + (v & 63) > x1) { x1 = rx + (v & 63); }
            if (ry + 1 > y1) { y1 = ry + 1; }
        }
        var sh = y1 - y0;                                   // scale = tall / sh
        for (var i = 0; i < runs.size(); i++) {
            var v = runs[i];
            var c = (v >> 18) & 63;
            var rx = ((v >> 6) & 63) - x0;
            var ry = ((v >> 12) & 63) - y0;
            var px0 = rx * tall / sh;
            var px1 = (rx + (v & 63)) * tall / sh;
            var py0 = ry * tall / sh;
            var py1 = (ry + 1) * tall / sh;
            if (px1 <= px0 || py1 <= py0) { continue; }
            dc.setColor(((c >> 4) & 3) * 0x550000 + ((c >> 2) & 3) * 0x5500 + (c & 3) * 0x55, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + px0, y + py0, px1 - px0, py1 - py0);
        }
        return (x1 - x0) * tall / sh;
    }

    // As many needs as fit on one line of maxW pixels, then "..." if some were left out.
    function oneLine(dc, items, font, maxW) {
        var out = items[0];
        for (var i = 1; i < items.size(); i++) {
            var t = out + ", " + items[i];
            var more = i + 1 < items.size() ? "..." : "";
            if (dc.getTextWidthInPixels(t + more, font) > maxW) { return out + "..."; }
            out = t;
        }
        return out;
    }

    // The needs as wrapped lines of at most maxW pixels (at most maxLines).
    function wrap(dc, items, font, maxW, maxLines) {
        var lines = [];
        var cur = "";
        for (var i = 0; i < items.size(); i++) {
            var t = cur.length() == 0 ? items[i] : cur + ", " + items[i];
            if (cur.length() > 0 && dc.getTextWidthInPixels(t, font) > maxW) {
                lines.add(cur);
                cur = items[i];
            } else {
                cur = t;
            }
        }
        if (cur.length() > 0) { lines.add(cur); }
        while (lines.size() > maxLines) { lines = lines.slice(0, maxLines); }
        return lines;
    }
}

// The glance in the widget list. Selecting it opens the game.
(:glance)
class TamaGlance extends WatchUi.GlanceView {
    function initialize() { GlanceView.initialize(); }

    // Like the watch's own glances: the Poke Ball icon is the watch's, on the left; here the
    // name with its level right after it, and just below, what it needs.
    const TIGHT = 6;    // the system fonts' top padding, taken out between the two

    function onUpdate(dc) {
        var d = Needs.summary();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var th = dc.getFontHeight(Graphics.FONT_TINY);
        var lh = dc.getFontHeight(Graphics.FONT_XTINY);
        var items = Needs.needs(d);
        var ok = items.size() == 0;
        // the actions always share one line, so they always sit at the same height
        var lines = ok ? [GT.g(GT.ALL_GOOD)] : [Needs.oneLine(dc, items, Graphics.FONT_XTINY, w)];
        var y = (h - (th - TIGHT) - lines.size() * lh) / 2;
        // the name (a size smaller, then fewer letters, if it must), the level right after it
        var name = Needs.name(d);
        var lv = Needs.level(d);
        var lvW = lv.length() > 0 ? dc.getTextWidthInPixels(lv, Graphics.FONT_XTINY) + 5 : 0;
        var tf = Graphics.FONT_TINY;
        if (dc.getTextWidthInPixels(name, tf) > w - lvW) { tf = Graphics.FONT_XTINY; }
        while (name.length() > 3 && dc.getTextWidthInPixels(name, tf) > w - lvW) {
            name = name.substring(0, name.length() - 1);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, y, tf, name, Graphics.TEXT_JUSTIFY_LEFT);
        if (lv.length() > 0) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            var nw = dc.getTextWidthInPixels(name, tf);
            dc.drawText(nw + 5, y + dc.getFontHeight(tf) - lh, Graphics.FONT_XTINY, lv, Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.setColor(ok ? 0x00FF00 : 0xFFAA00, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(0, y + th - TIGHT + i * lh, Graphics.FONT_XTINY, lines[i], Graphics.TEXT_JUSTIFY_LEFT);
        }
    }
}

// With glances turned off, the widget loop shows this card (UP/DOWN scroll the loop there);
// START opens the game.
class WidgetCard extends WatchUi.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc) {
        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var d = Needs.summary();
        var cx = dc.getWidth() / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var pw0 = 70;
        Needs.drawPet(dc, d, cx - 30, 34, pw0);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 112, Graphics.FONT_SMALL, Needs.title(d), Graphics.TEXT_JUSTIFY_CENTER);
        var items = Needs.needs(d);
        var ok = items.size() == 0;
        var lines = ok ? [GT.g(GT.ALL_GOOD)] : Needs.wrap(dc, items, Graphics.FONT_TINY, 200, 2);
        dc.setColor(ok ? 0x00FF00 : 0xFFAA00, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, 142 + i * 24, Graphics.FONT_TINY, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 198, Graphics.FONT_XTINY, GT.g(GT.PLAY), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class WidgetCardDelegate extends WatchUi.BehaviorDelegate {
    var model;
    function initialize(m) { BehaviorDelegate.initialize(); model = m; }

    function onSelect() {
        model = (Application.getApp() as TamaWatchApp).model;   // a restarted game has a new one
        var view = new PetView(model);
        WatchUi.pushView(view, new PetDelegate(model, view), WatchUi.SLIDE_LEFT);
        return true;
    }
}
