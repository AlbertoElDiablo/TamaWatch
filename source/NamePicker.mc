import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Renaming without a keyboard: UP/DOWN turn a letter wheel, START adds the letter,
// BACK deletes the last one (or leaves when empty). "OK" on the wheel saves, "CLR" restores
// the species name.
class NamePickerView extends WatchUi.View {

    const WHEEL = ["OK", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
                   "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "-", " ", "CLR"];
    const MAX_LEN = 10;

    var model;
    var name = "";
    var at = 1;

    function initialize(m) {
        View.initialize();
        model = m;
        name = m.nick;
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var w = dc.getWidth();
        var cx = w / 2;
        dc.setColor(0xFFFFFF, 0xFFFFFF);
        dc.clear();
        dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_XTINY, Tr.t("NAME"), Graphics.TEXT_JUSTIFY_CENTER);
        var shown = name.length() > 0 ? name : SpriteIndex.name(model.dex);
        dc.drawText(cx, 60, Graphics.FONT_MEDIUM, shown + "_", Graphics.TEXT_JUSTIFY_CENTER);
        for (var k = -2; k <= 2; k++) {
            var i = (at + k + WHEEL.size()) % WHEEL.size();
            var cy = 160 + k * 25;            // clear of the name above
            if (k == 0) {
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                dc.drawRoundedRectangle(cx - 34, cy - 14, 68, 28, 8);
                dc.setPenWidth(1);
            }
            var label = Tr.t(WHEEL[i].equals(" ") ? "space" : WHEEL[i]);
            var lf = k == 0 ? Graphics.FONT_SMALL : Graphics.FONT_XTINY;
            dc.setColor(k == 0 ? 0x000055 : TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, capY(lf, cy), lf, label, Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, Fit.trim(dc, Tr.t("START add  BACK delete"), 188, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class NamePickerDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { v.at = (v.at + 1) % v.WHEEL.size(); WatchUi.requestUpdate(); return true; }
    function onPreviousPage() { v.at = (v.at - 1 + v.WHEEL.size()) % v.WHEEL.size(); WatchUi.requestUpdate(); return true; }

    function onSelect() {
        var c = v.WHEEL[v.at];
        if (c.equals("OK")) {
            v.model.rename(v.name);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        if (c.equals("CLR")) { v.name = ""; }
        else if (v.name.length() < v.MAX_LEN) { v.name = v.name + c; }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        if (v.name.length() == 0) { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
        v.name = v.name.substring(0, v.name.length() - 1);
        WatchUi.requestUpdate();
        return true;
    }
}
