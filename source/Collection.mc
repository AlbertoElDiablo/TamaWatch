import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Draws a creature's first idle frame (normal or shiny) standing on footY.
function drawIdle(dc, meta, art, cx, footY) {
    var a = meta["idle"];
    var x = cx + a["x"];
    var y = footY - meta["foot"] + a["y"];
    dc.setClip(x, y, a["w"], a["h"]);
    dc.drawBitmap(x, y - a["r"] - art[1], art[0]);
    dc.clearClip();
}

// A party or box member's sheet: sprite, level, IVs, training and moves.
class MemberView extends WatchUi.View {
    var model;
    var m;
    var meta = null;
    var art = null;

    function initialize(model_, member) {
        View.initialize();
        model = model_;
        m = member;
    }

    function onShow() {
        meta = WatchUi.loadResource(SpriteIndex.data(m[0]));
        art = SpriteIndex.art(meta, m[0], m[2]);
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        dc.setColor(0xFFFFFF, 0xFFFFFF);
        dc.clear();
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 22, UiFont.mid(), (m[2] ? "*" : "") + model.memberName(m) + Tr.t(" Lv") + m[3], Graphics.TEXT_JUSTIFY_CENTER);
        if (meta != null) { drawIdle(dc, meta, art, cx, 112); }
        var lines = [Tr.t("IV  ATK ") + m[4] + Tr.t("  DEF ") + m[5] + Tr.t("  SPD ") + m[6] + Tr.t("  VIT ") + m[7],
                     Tr.t("Training  ATK ") + m[8] + Tr.t("  DEF ") + m[9] + Tr.t("  SPD ") + m[10]];
        var mv = m[11];
        var names = "";
        for (var i = 0; i < 4; i++) {
            if (mv[i] != 0) { names += (names.length() > 0 ? ", " : "") + Moves.name(mv[i]); }
        }
        lines.add(names.length() > 0 ? names : Tr.t("No moves"));
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, 126 + i * 22, UiFont.tiny(), lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

// TamaPoke's Pokedex (renderGallery), scaled 466 -> 280: the region and its tally as the title,
// a 4x4 grid of thumbnails (silhouettes for species not raised, a gold "*" for shinies) and the
// page number. UP/DOWN move the highlight and turn pages, START opens the detail, BACK closes.
class GalleryView extends WatchUi.View {
    var model;
    var at = 0;            // highlighted dex index (0-based)
    var detail = false;
    var picking = false;   // false: UP/DOWN turn pages; START picks within the page
    var thumbs = null;
    var sils = null;
    var detailMeta = null; // [meta, art] of the creature shown in the detail
    var timer = null;
    var frame = 0;
    const PER = 16;
    const CELL = 46;
    const GX = 48;          // 4 cells of 46 centred on the screen
    const GY = 56;
    const THUMB = 38;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onShow() {
        Sfx.screenOk = true;
        thumbs = true;                  // loaded one by one (Thumbs)
        sils = true;
        timer = new Timer.Timer();
        timer.start(method(:tick), 150, true);
    }

    function onHide() {
        Sfx.screenOk = false;
        if (timer != null) { timer.stop(); timer = null; }   // the timer points back at this view: drop it, or neither is ever freed
        thumbs = null;
        sils = null;
        Thumbs.clear();
        detailMeta = null;
    }

    function tick() as Void {
        frame++;
        if (detail) { WatchUi.requestUpdate(); }
    }

    function page() { return at / PER; }
    function pages() { return (Dex.COUNT + PER - 1) / PER; }

    // Thumbnail n (1-151) from the colour or silhouette atlas, its cell at (x, y).
    function drawThumb(dc, n, x, y, sil) {
        var ox = x + (CELL - THUMB) / 2;
        var oy = y + (CELL - THUMB) / 2;
        dc.setClip(ox, oy, THUMB, THUMB);
        Thumbs.draw(dc, n, ox, oy, sil);
        dc.clearClip();
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());   // the background fills the screen
        if (detail) { drawDetail(dc, cx); return; }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 26, UiFont.mid(), Tr.t("KANTO ") + model.registeredCount() + "/151", Graphics.TEXT_JUSTIFY_CENTER);
        for (var k = 0; k < PER; k++) {
            var n = page() * PER + k + 1;
            if (n > Dex.COUNT) { break; }
            var x = GX + (k % 4) * CELL;
            var y = GY + (k / 4) * CELL;
            drawThumb(dc, n, x, y, model.isRegistered(n) != 1);
            if (((model.dexShiny[(n - 1) / 24] >> ((n - 1) % 24)) & 1) == 1) {
                dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x + 37, y + 2, UiFont.tiny(), "*", Graphics.TEXT_JUSTIFY_LEFT);
            }
            if (picking && n - 1 == at) {      // the watch's cursor (TamaPoke is tapped)
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawRoundedRectangle(x + 1, y + 1, CELL - 2, CELL - 2, 8);
                dc.setPenWidth(1);
            }
        }
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 242, UiFont.tiny(), picking ? (page() + 1) + "/" + pages() : "< " + (page() + 1) + "/" + pages() + Tr.t(" >  START"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // TamaPoke's detail: "N.001 NAME" in the species' colour (??? if not raised), and the
    // creature animated in colour, or its still silhouette.
    function drawDetail(dc, cx) {
        var n = at + 1;
        var reg = model.isRegistered(n) == 1;
        var shiny = ((model.dexShiny[(n - 1) / 24] >> ((n - 1) % 24)) & 1) == 1;
        var num = n < 10 ? "00" + n : (n < 100 ? "0" + n : "" + n);
        var head = "N." + num + " " + (shiny ? "*" : "") + (reg ? SpriteIndex.name(n).toUpper() : "???");
        dc.setColor(reg ? Dex.row(n)[12] : 0x000000, Graphics.COLOR_TRANSPARENT);
        var font = UiFont.big();
        if (dc.getTextWidthInPixels(head, font) > 156) { font = UiFont.mid(); }   // long names step down
        font = Fit.font(dc, head, 176, [font, UiFont.small(), UiFont.tiny()]);
        dc.drawText(cx, 34, font, Fit.trim(dc, head, 176, font), Graphics.TEXT_JUSTIFY_CENTER);
        if (reg) {
            if (detailMeta == null) {
                var m = WatchUi.loadResource(SpriteIndex.data(n));
                detailMeta = [m, SpriteIndex.art(m, n, false)];
            }
            var m = detailMeta[0];
            var a = m["idle"];
            var fi = (frame / 2) % a["d"].size();
            var x = cx + a["x"];
            var y = 180 - m["foot"] + a["y"];
            dc.setClip(x, y, a["w"], a["h"]);
            dc.drawBitmap(x - (fi % a["c"]) * a["w"], y - a["r"] - (fi / a["c"]) * a["h"] - detailMeta[1][1], detailMeta[1][0]);
            dc.clearClip();
        } else {
            drawThumb(dc, n, cx - CELL / 2, 110, true);
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 236, UiFont.tiny(), Tr.t("BACK: grid"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class GalleryDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { return move(1); }
    function onPreviousPage() { return move(-1); }

    // Landing on the Pokedex, UP/DOWN turn the pages. START picks on the page: then UP/DOWN move
    // between its creatures and START opens one. BACK steps back: detail, picking, then out.
    function move(d) {
        if (v.detail) { return true; }
        if (!v.picking) {
            var p = (v.page() + d + v.pages()) % v.pages();
            v.at = p * v.PER;
            Sfx.vibe(Sfx.TICK);
        } else {
            var first = v.page() * v.PER;
            var count = Dex.COUNT - first < v.PER ? Dex.COUNT - first : v.PER;
            v.at = first + (v.at - first + d + count) % count;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        if (!v.picking) {
            v.picking = true;
        } else if (!v.detail) {
            v.detail = true;
            v.detailMeta = null;
            if (v.model.isRegistered(v.at + 1) == 1) { Sfx.vibe(Sfx.TICK); }
        } else {
            v.detail = false;
            v.detailMeta = null;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        if (v.detail) { v.detail = false; v.detailMeta = null; WatchUi.requestUpdate(); return true; }
        if (v.picking) { v.picking = false; WatchUi.requestUpdate(); return true; }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
