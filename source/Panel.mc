import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// TamaPoke's overlay panels (drawMenu / renderTrain), scaled 466 -> 280: the scene dimmed with
// stripes, a white rounded panel, and rounded rows: cream with an ink border, RETIRE in red with
// white text, CLOSE and disabled rows in grey. A row may carry a progress bar (training).
// UP/DOWN move the highlight (the panel scrolls), START picks, BACK closes.
class PanelView extends WatchUi.View {

    const ST_NORMAL = 0;
    const ST_RED = 1;
    const ST_GREY = 2;

    var title;
    var tr = false;         // title and labels are English keys, translated as drawn (live language)
    var rows;          // [label, id, style, barPct or -1]
    var hint;
    var sel = 0;
    var top = 0;
    const VISIBLE = 5;
    const ROW_H = 34;
    const GAP = 5;

    function initialize(t, r, h) {
        View.initialize();
        title = t;
        rows = r;
        hint = h;
    }

    function lab(s) { return tr && s != null ? Tr.t(s) : s; }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var title = lab(self.title);
        var hint = lab(self.hint);
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(0xFFFFFF, 0xFFFFFF);                         // the panel's white fills the screen
        dc.clear();
        var hasBars = rows.size() > 0 && rows[0][3] >= 0;
        var rowH = hasBars ? 40 : ROW_H;
        var n = rows.size() < VISIBLE ? rows.size() : VISIBLE;
        if (hasBars) { n = rows.size(); }
        var hintLines = [];
        if (hint != null) {
            // as many lines of 190 px as it takes (up to 3): nothing is cut off
            var words = Wire.split(hint, " ");
            var cur = "";
            for (var k = 0; k < words.size(); k++) {
                var t = cur.length() == 0 ? words[k] : cur + " " + words[k];
                if (cur.length() > 0 && dc.getTextWidthInPixels(t, UiFont.tiny()) > 190) {
                    hintLines.add(cur);
                    cur = words[k];
                } else {
                    cur = t;
                }
            }
            if (cur.length() > 0) { hintLines.add(cur); }
            if (hintLines.size() > 3) { hintLines = hintLines.slice(0, 3); }
        }
        var titleH = 0;
        if (title != null) {
            var tf0 = Fit.font(dc, title, 176, [UiFont.big(), UiFont.mid(), UiFont.small(), UiFont.tiny()]);
            titleH = dc.getFontHeight(tf0) + 4;
        }
        var hintH = 16 * hintLines.size();
        var ph = titleH + n * (rowH + GAP) + hintH;
        var py = (h - ph) / 2;
        // one size for every row: the largest in which the longest label fits (TamaPoke's uiFitAll)
        var rowFont = UiFont.mid();
        for (var i = 0; i < rows.size(); i++) {
            if (dc.getTextWidthInPixels(lab(rows[i][0]), rowFont) > 150) { rowFont = UiFont.small(); }
        }
        for (var i = 0; i < rows.size(); i++) {
            if (dc.getTextWidthInPixels(lab(rows[i][0]), rowFont) > 150) { rowFont = UiFont.tiny(); }
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        if (title != null) {
            var tf = Fit.font(dc, title, 176, [UiFont.big(), UiFont.mid(), UiFont.small(), UiFont.tiny()]);
            dc.drawText(cx, py, tf, Fit.trim(dc, title, 176, tf), Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (sel < top) { top = sel; }
        if (sel >= top + n) { top = sel - n + 1; }
        // the app's one column of boxes (narrower still if a tall panel needs it)
        var rw = Fit.COL_W;
        for (var k = 0; k < n; k++) {
            var spk = Fit.span(py + titleH + k * (rowH + GAP), rowH, Fit.COL_W);
            if (spk[1] < rw) { rw = spk[1]; }
        }
        var rx = cx - rw / 2;
        for (var k = 0; k < n; k++) {
            var i = top + k;
            if (i >= rows.size()) { break; }
            var r = rows[i];
            var y = py + titleH + k * (rowH + GAP);
            var on = i == sel;
            // the highlighted row is filled solid with a pointer, so you always know where you are
            var fill = on ? 0xFF0000 : (r[2] == ST_RED ? 0xFF0000 : (r[2] == ST_GREY ? 0xAAAAAA : 0xFFFFFF));
            dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(rx, y, rw, rowH, 9);
            dc.setColor(on ? 0x000000 : (r[2] == ST_RED ? 0xAA5500 : 0x000000), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(on ? 3 : 1);
            dc.drawRoundedRectangle(rx, y, rw, rowH, 9);
            dc.setPenWidth(1);
            var txt = on || r[2] == ST_RED ? 0xFFFFFF : 0x000000;
            if (on) {
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                var my = y + rowH / 2;
                dc.fillPolygon([[rx + 8, my - 6], [rx + 8, my + 6], [rx + 15, my]]);
            }
            if (r[3] >= 0) {
                dc.setColor(txt, Graphics.COLOR_TRANSPARENT);
                dc.drawText(rx + 20, y + 1, UiFont.tiny(), lab(r[0]), Graphics.TEXT_JUSTIFY_LEFT);
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(rx + 20, y + 24, rw - 34, 9, 3);
                var fw = (rw - 38) * r[3] / 100;
                if (fw > 0) {
                    dc.setColor(r[3] >= 100 ? 0x55FF55 : 0xFFAA00, Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(rx + 22, y + 26, fw, 5, 2);
                }
            } else {
                dc.setColor(txt, Graphics.COLOR_TRANSPARENT);
                centerText(dc, rx + 12, y, rw - 24, rowH, rowFont, lab(r[0]));   // clear of the pointer (rx+8..15)
            }
        }
        // more rows above / below
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        if (top > 0) { dc.fillPolygon([[cx - 7, py + titleH - 4], [cx + 7, py + titleH - 4], [cx, py + titleH - 11]]); }
        if (top + n < rows.size()) {
            var by = py + titleH + n * (rowH + GAP);
            dc.fillPolygon([[cx - 7, by], [cx + 7, by], [cx, by + 7]]);
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        for (var k = 0; k < hintLines.size(); k++) {
            dc.drawText(cx, py + ph - hintH + k * 16 + 4, UiFont.tiny(), Fit.trim(dc, hintLines[k], 190, UiFont.tiny()), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

// Picks call target.selectId(id); a row whose id is :close just closes the panel.
class PanelDelegate extends WatchUi.BehaviorDelegate {
    var v;
    var target;

    function initialize(view, t) {
        BehaviorDelegate.initialize();
        v = view;
        target = t;
    }

    function onNextPage() { v.sel = (v.sel + 1) % v.rows.size(); WatchUi.requestUpdate(); return true; }
    function onPreviousPage() { v.sel = (v.sel - 1 + v.rows.size()) % v.rows.size(); WatchUi.requestUpdate(); return true; }

    function onSelect() {
        var r = v.rows[v.sel];
        if (r[1] == :close) { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
        if (r[2] == v.ST_GREY) { return true; }          // a disabled row does nothing
        target.selectId(r[1]);
        return true;
    }

    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}
