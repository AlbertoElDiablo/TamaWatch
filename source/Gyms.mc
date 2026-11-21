import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// TamaPoke's gym screens, scaled 466 -> 280. GYMS in the menu opens stage 1 straight away (one
// region a build; LINK BATTLE has its own menu entry):
//   stage 0 "GYMS": the region row with its badge tally, and LINK BATTLE (no longer shown)
//   stage 1 "KANTO GYMS": the EASY / HARD pill and one row per trainer (name, town or LOCKED,
//   "Lv.12 x2" = top level x team size); a trainer opens once the one before is beaten.
class GymView extends WatchUi.View {
    var model;
    var petView;
    var stage = 1;
    var sel = 1;          // stage 0: 0 region, 1 link; stage 1: 0 pill, 1.. trainers
    var top = 0;
    var hard = false;
    var trainers = null;
    const BG = 0xFFFFFF;
    const INK = 0x000000;
    const TRACK = 0xAAAAAA;

    function initialize(m, pv) {
        View.initialize();
        model = m;
        petView = pv;
    }

    function onShow() { trainers = WatchUi.loadResource(Rez.JsonData.trainers); }
    function onHide() { trainers = null; }

    function rowBox(dc, x, y, w, h, on, fill) {
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 7);
        dc.setColor(on ? 0xFF0000 : INK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(on ? 3 : 1);
        dc.drawRoundedRectangle(x, y, w, h, 7);
        dc.setPenWidth(1);
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        dc.setColor(0x000000, 0x000000);
        dc.clear();
        dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());   // the background fills the screen
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        if (stage == 0) {
            dc.drawText(cx, 34, UiFont.mid(), Tr.t("GYMS"), Graphics.TEXT_JUSTIFY_CENTER);
            rowBox(dc, Fit.COL_X, 76, Fit.COL_W, 38, sel == 0, BG);
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Fit.COL_X + 10, capY(UiFont.small(), 95), UiFont.small(), Region.t("KANTO"), Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            var bc = Tr.t("BADGES ") + model.badgeCount(false) + "/8";       // just the count if the word won't fit
            var room = Fit.COL_W - 28 - dc.getTextWidthInPixels(Region.t("KANTO"), UiFont.small());
            if (dc.getTextWidthInPixels(bc, UiFont.tiny()) > room) { bc = model.badgeCount(false) + "/8"; }
            dc.drawText(Fit.COL_X + Fit.COL_W - 10, capY(UiFont.tiny(), 95), UiFont.tiny(), bc, Graphics.TEXT_JUSTIFY_RIGHT);
            rowBox(dc, Fit.COL_X, 126, Fit.COL_W, 38, sel == 1, BG);
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            centerText(dc, Fit.COL_X, 126, Fit.COL_W, 38, UiFont.mid(), Tr.t("LINK BATTLE"));
            dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 236, UiFont.tiny(), Tr.t("BACK"), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var gt = Region.t("KANTO GYMS");                     // a size smaller if the language needs it
        var gf = Fit.font(dc, gt, 176, [UiFont.mid(), UiFont.small(), UiFont.tiny()]);
        dc.drawText(cx, 24, gf, Fit.trim(dc, gt, 176, gf), Graphics.TEXT_JUSTIFY_CENTER);
        rowBox(dc, cx - 38, 58, 76, 22, sel == 0, TRACK);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        centerText(dc, cx - 38, 58, 76, 22, UiFont.tiny(), hard ? Tr.t("HARD") : Tr.t("EASY"));
        var visible = 3;                  // three rows tall enough for their two lines
        var ti = sel - 1;
        if (ti >= 0) {
            if (ti < top) { top = ti; }
            if (ti >= top + visible) { top = ti - visible + 1; }
        }
        for (var k = 0; k < visible; k++) {
            var i = top + k;
            if (i >= trainers.size()) { break; }
            var t = trainers[i];
            var tired = hard && lowBattery(model);       // hard gyms wait for your Body Battery
            var open = model.trainerUnlocked(i, hard) && !tired;
            var y = 88 + k * 46;
            rowBox(dc, Fit.COL_X, y, Fit.COL_W, 42, sel == i + 1, BG);
            dc.setColor(open ? INK : TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            var done = model.hasBadge(i, hard) ? " *" : "";
            dc.drawText(Fit.COL_X + 8, capY(UiFont.tiny(), y + 13), UiFont.tiny(), t[0] + done, Graphics.TEXT_JUSTIFY_LEFT);
            var team = trainerTeam(model, i, hard, t[4]);
            var re = team != t[4];                         // a rematch is due: stronger now
            dc.setColor(re && open ? 0xFF5500 : TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            var sub = open ? (re ? Tr.t("REMATCH!") : t[1].toUpper()) : (tired ? Tr.t("LOW BODY BATTERY") : Tr.t("LOCKED"));
            var lv = 0;
            for (var j = 0; j < team.size(); j++) { if (team[j][1] > lv) { lv = team[j][1]; } }
            var lvText = Tr.t("Lv.") + lv + " x" + team.size();
            // the second line shortened, never under the level on its right
            var room = Fit.COL_W - 16 - (tired ? 0 : dc.getTextWidthInPixels(lvText, UiFont.tiny()) + 10);
            dc.drawText(Fit.COL_X + 8, capY(UiFont.tiny(), y + 29), UiFont.tiny(), Fit.trim(dc, sub, room, UiFont.tiny()), Graphics.TEXT_JUSTIFY_LEFT);
            if (!tired) {                                   // closed for Body Battery: just the warning
                dc.setColor(open ? INK : TEXT_GREY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(Fit.COL_X + Fit.COL_W - 8, capY(UiFont.tiny(), y + 29), UiFont.tiny(), lvText, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, capY(UiFont.tiny(), 238), UiFont.tiny(), (ti >= 0 ? ti + 1 : 1) + "/" + trainers.size() + Tr.t("   BACK"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class GymDelegate2 extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function count() { return v.stage == 0 ? 2 : v.trainers.size() + 1; }
    function onNextPage() { v.sel = (v.sel + 1) % count(); WatchUi.requestUpdate(); return true; }
    function onPreviousPage() { v.sel = (v.sel - 1 + count()) % count(); WatchUi.requestUpdate(); return true; }

    function onSelect() {
        if (v.stage == 0) {
            if (v.sel == 0) { v.stage = 1; v.sel = 1; v.top = 0; }
            else {
                var lv = new LinkView(v.model, v.petView);
                WatchUi.switchToView(lv, new LinkDelegate(lv), WatchUi.SLIDE_LEFT);
                return true;
            }
        } else if (v.sel == 0) {
            v.hard = !v.hard;
        } else {
            var idx = v.sel - 1;
            if (v.hard && lowBattery(v.model)) {
                // greyed out: say why in a pop-up
                var pv = new PanelView(Tr.t("HARD"), [[Tr.t("OK"), :close, 0, -1]],
                                       Tr.f("Body Battery {0}%: hard gyms need over 20%", [v.model.bbNow]));
                WatchUi.pushView(pv, new PanelDelegate(pv, null), WatchUi.SLIDE_UP);
                return true;
            }
            if (!v.model.trainerUnlocked(idx, v.hard)) { return true; }   // locked: nothing
            if (v.model.party.size() == 0) {
                var bv = new BattleView(v.model, v.petView, 0, 0, idx, v.hard, 0xFFFF);
                WatchUi.switchToView(bv, new BattleDelegate(bv), WatchUi.SLIDE_UP);
            } else {
                var tr = v.trainers[idx];
                var pk = new PickView(v.model, v.petView, idx, v.hard, [tr[0], tr[1], tr[2], tr[3], trainerTeam(v.model, idx, v.hard, tr[4])]);
                WatchUi.switchToView(pk, new PickDelegate(pk), WatchUi.SLIDE_LEFT);
            }
            return true;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);       // back to the menu
        return true;
    }
}

// TamaPoke's team pick: the trainer and its team as the title, CHOSEN n/6, cards of your pet and
// party (thumbnail, name, level, types, a tick when chosen), and BACK / FIGHT.
class PickView extends WatchUi.View {
    var model;
    var petView;
    var trainer;
    var hard;
    var row;
    var mask = 0;
    var sel = 0;          // cards, then BACK, then FIGHT
    var thumbs = null;
    var cards = [];       // [dex, name, level, shiny]
    var top = 0;          // the first row shown (on BACK / FIGHT the page stays put)
    const ROWS = 3;

    function initialize(m, pv, idx, isHard, trainerRow) {
        View.initialize();
        model = m;
        petView = pv;
        trainer = idx;
        hard = isHard;
        row = trainerRow;
        cards.add([m.dex, m.name(), m.level(), m.shiny]);
        for (var i = 0; i < m.party.size() && cards.size() < 7; i++) {
            var p = m.party[i];
            cards.add([p[0], m.memberName(p), p[3], p[2]]);
        }
        for (var i = 0; i < cards.size() && i < 6; i++) { mask |= 1 << i; }
    }

    function onShow() { thumbs = true; }              // loaded one by one (Thumbs)
    function onHide() { thumbs = null; Thumbs.clear(); }

    function chosen() {
        var n = 0;
        for (var i = 0; i < cards.size(); i++) { if ((mask >> i) & 1) { n++; } }
        return n;
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        dc.setColor(0x000000, 0x000000);
        dc.clear();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());   // the background fills the screen
        var team = row[4];
        var lv = 0;
        for (var j = 0; j < team.size(); j++) { if (team[j][1] > lv) { lv = team[j][1]; } }
        // the trainer and its team, then how many you chose: each on its own line, centred
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        var tt = row[0] + Tr.t(" Lv.") + lv + " x" + team.size();
        var tf = Fit.font(dc, tt, 170, [UiFont.small(), UiFont.tiny()]);
        dc.drawText(cx, capY(tf, 32), tf, Fit.trim(dc, tt, 170, tf), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        var pages = (cards.size() + ROWS - 1) / ROWS;
        var first = sel < cards.size() ? (sel / ROWS) * ROWS : top;
        top = first;
        var sub = Tr.t("CHOSEN ") + chosen() + "/6" + (pages > 1 ? "   " + (first / ROWS + 1) + "/" + pages : "");
        dc.drawText(cx, capY(UiFont.tiny(), 52), UiFont.tiny(), sub, Graphics.TEXT_JUSTIFY_CENTER);
        // one row per creature: its picture, name and level on top, type below, a tick when chosen
        var x = Fit.COL_X;
        var rw = Fit.COL_W;
        for (var k = 0; k < ROWS; k++) {
            var i = first + k;
            if (i >= cards.size()) { break; }
            var c = cards[i];
            var y = 62 + k * 45;
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, rw, 41, 7);
            dc.setColor(sel == i ? 0xFF0000 : 0x000000, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(sel == i ? 3 : 1);
            dc.drawRoundedRectangle(x, y, rw, 41, 7);
            dc.setPenWidth(1);
            var n = c[0];
            dc.setClip(x + 3, y + 2, 38, 38);
            Thumbs.draw(dc, n, x + 3, y + 2, false);
            dc.clearClip();
            var on = ((mask >> i) & 1) != 0;
            var tx = x + 44;
            var right = x + rw - (on ? 26 : 8);          // the tick sits at the row's right end
            // the name on its own line; its level and type below
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(tx, capY(UiFont.tiny(), y + 13), UiFont.tiny(), Fit.trim(dc, c[1].toUpper(), right - tx, UiFont.tiny()), Graphics.TEXT_JUSTIFY_LEFT);
            var lvs = Tr.t("Lv.") + c[2] + (c[3] ? " *" : "");
            dc.drawText(tx, capY(UiFont.tiny(), y + 29), UiFont.tiny(), lvs, Graphics.TEXT_JUSTIFY_LEFT);
            var r = Dex.row(n);
            dc.setColor(Moves.typeColor(r[10]), Graphics.COLOR_TRANSPARENT);
            var lw = dc.getTextWidthInPixels(lvs + "  ", UiFont.tiny());
            dc.drawText(tx + lw, capY(UiFont.tiny(), y + 29), UiFont.tiny(), Fit.trim(dc, Moves.typeName(r[10]), right - tx - lw, UiFont.tiny()), Graphics.TEXT_JUSTIFY_LEFT);
            if (on) {
                dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x + rw - 14, y + 20, 7);
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawLine(x + rw - 18, y + 20, x + rw - 15, y + 23);
                dc.drawLine(x + rw - 15, y + 23, x + rw - 10, y + 17);
                dc.setPenWidth(1);
            }
        }
        var bSel = sel == cards.size();
        var fSel = sel == cards.size() + 1;
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(52, 200, 82, 26, 7);
        dc.setColor(0x55FF55, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(146, 200, 82, 26, 7);
        dc.setColor(bSel ? 0xFF0000 : 0x000000, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(bSel ? 3 : 1);
        dc.drawRoundedRectangle(52, 200, 82, 26, 7);
        dc.setColor(fSel ? 0xFF0000 : 0x000000, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(fSel ? 3 : 1);
        dc.drawRoundedRectangle(146, 200, 82, 26, 7);
        dc.setPenWidth(1);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(93, capY(UiFont.tiny(), 213), UiFont.tiny(), Tr.t("BACK"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(187, capY(UiFont.tiny(), 213), UiFont.tiny(), Tr.t("FIGHT"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class PickDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function count() { return v.cards.size() + 2; }
    function onNextPage() { v.sel = (v.sel + 1) % count(); WatchUi.requestUpdate(); return true; }
    function onPreviousPage() { v.sel = (v.sel - 1 + count()) % count(); WatchUi.requestUpdate(); return true; }

    function onSelect() {
        if (v.sel < v.cards.size()) {
            var bit = 1 << v.sel;
            if ((v.mask & bit) != 0) { v.mask &= ~bit; }
            else if (v.chosen() < 6) { v.mask |= bit; }
        } else if (v.sel == v.cards.size()) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        } else if (v.chosen() > 0) {
            var bv = new BattleView(v.model, v.petView, 0, 0, v.trainer, v.hard, v.mask);
            WatchUi.switchToView(bv, new BattleDelegate(bv), WatchUi.SLIDE_UP);
            return true;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

// Hard gyms need some energy in you: with your Body Battery at 20% or less they are closed
// (greyed out, and START says why). Unknown Body Battery never closes them.
function lowBattery(m) { return m.bbNow >= 0 && m.bbNow <= 20; }

// A trainer's team for this battle: its own, or for a due rematch (beaten, 2 days on: Extra) a
// stronger one, its ace 2 levels over your partner (and at least 3 over before), the rest as far
// below it as they were, each evolved as far as its level allows.
function trainerTeam(m, idx, hard, team) {
    if (idx < 0 || idx > 12 || !m.hasBadge(idx, hard) || !Extra.rematchReady(idx)) { return team; }
    return grownTeam(team, m.level() + 2);
}

function grownTeam(team, target) {
    var top = 0;
    for (var j = 0; j < team.size(); j++) { if (team[j][1] > top) { top = team[j][1]; } }
    if (target < top + 3) { target = top + 3; }
    var out = [];
    for (var j = 0; j < team.size(); j++) {
        var lv = team[j][1] + target - top;
        if (lv > 100) { lv = 100; }
        out.add([evolvedAt(team[j][0], lv), lv]);
    }
    return out;
}

// the species a creature would have become by level lv
function evolvedAt(dex, lv) {
    for (var g = 0; g < 4; g++) {
        var nx = Dex.evolvesTo(dex);
        var at = Dex.evolveLevel(dex);
        if (nx <= 0 || at <= 0 || lv < at) { break; }
        dex = nx;
    }
    return dex;
}

// The rival (FireRed's): leads with the starter strong against yours (grass, fire, water: the
// next one), and brings more as you level up and earn badges, all around your level; the others
// come from the region, always the same ones for you (seeded by when you started).
const RIVAL_NAME = "KAI";
const RIVAL = 99;                // its trainer number in BattleView
function rivalTeam(m) {
    var st = Dex.STARTERS;
    var mine = -1;
    for (var i = 0; i < 3 && mine < 0; i++) { if (m.isRegistered(st[i]) == 1) { mine = i; } }
    if (mine < 0) { mine = (m.trJoined / 7).toNumber() % 3; }
    var lv = m.level();
    var size = 1 + (m.badgeCount(false) + 1) / 2 + lv / 20;
    if (size > 6) { size = 6; }
    var out = [];
    var seed = (m.trJoined / 60).toNumber();
    for (var i = 1; i < size; i++) {
        var n = 1;
        for (var tries = 0; tries < 30; tries++) {
            n = 1 + ((seed + i * 37 + tries * 11) % Dex.COUNT).abs();
            if (Dex.rarity(n) != Dex.R_LEGEND && st.indexOf(n) < 0) { break; }
        }
        var l = lv - 1 - (i % 3);
        if (l < 2) { l = 2; }
        out.add([evolvedAt(n, l), l]);
    }
    out.add([evolvedAt(st[(mine + 1) % 3], lv + 1), lv + 1]);   // the ace last
    return out;
}
