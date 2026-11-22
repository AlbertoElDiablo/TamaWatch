import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Text that must fit: the largest of the given fonts in which it fits maxW, else trimmed.
module Fit {
    function font(dc, text, maxW, fonts) {
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxW) { return fonts[i]; }
        }
        return fonts[fonts.size() - 1];
    }

    function trim(dc, text, maxW, f) {
        if (dc.getTextWidthInPixels(text, f) <= maxW) { return text; }
        while (text.length() > 1 && dc.getTextWidthInPixels(text + ".", f) > maxW) {
            text = text.substring(0, text.length() - 1);
        }
        return text + ".";
    }

    // The fenix 6X screen is a full 280 x 280 circle (1.4"), centre (140, 140). A box from y to y+h
    // stays visible, with SAFE pixels to spare for the bezel seen at an angle, when its half-width
    // is at most the circle's half-width at whichever of its edges is further from the centre.
    // Returns [x, w] for a centred box of at most maxW.
    // Every column of boxes in the app (menus, team, party, moves, gyms, lists) uses this one:
    // the menu's 5-row column, 182 px wide, centred on the screen (x 49-231). It is the widest a
    // row can be at the menu's top and bottom rows, so every row in that band fits the circle.
    const COL_W = 182;
    const COL_X = 49;

    const SAFE = 6;
    function span(y, h, maxW) {
        var d1 = (y - 140).abs();
        var d2 = (y + h - 140).abs();
        var d = d1 > d2 ? d1 : d2;
        var r = 140 - SAFE;
        var half = d >= r ? 0 : Math.sqrt(r * r - d * d).toNumber();
        var w = 2 * half < maxW ? 2 * half : maxW;
        return [140 - w / 2, w];
    }
}

// The y to draw text at so its capital letters are centred on cy. The watch's fonts carry padding
// above the letters (measured on the fenix 6X: the capitals of XTINY sit 5-16 px below the
// drawing y, TINY 9-26, SMALL 8-28, MEDIUM 10-33, LARGE 10-35), so centring on the font height
// leaves text 1-2 px low and, in a short box, sitting on its bottom edge.
function capY(font, cy) {
    var mid;
    if (font == Graphics.FONT_XTINY) { mid = 11; }
    else if (font == Graphics.FONT_TINY) { mid = 17; }
    else if (font == Graphics.FONT_SMALL) { mid = 18; }
    else if (font == Graphics.FONT_MEDIUM) { mid = 22; }
    else if (font == Graphics.FONT_LARGE) { mid = 22; }
    else { mid = 39; }                     // NUMBER_MEDIUM, half its height on the fenix 6X
    return cy - mid;
}

// Text centred horizontally and vertically (on its capitals) in a box, trimmed so it never spills.
function centerText(dc, x, y, w, h, font, text) {
    // step the font down before ever cutting the text
    if (dc.getTextWidthInPixels(text, font) > w - 8) { font = Fit.font(dc, text, w - 8, [UiFont.small(), UiFont.tiny()]); }
    // still too wide: two lines, split at the space nearest the middle, when the box is tall enough
    if (dc.getTextWidthInPixels(text, font) > w - 8 && h >= 30 && text.find(" ") != null) {
        var f = Graphics.FONT_XTINY;
        var best = -1;
        var bestW = 9999;
        for (var i = 1; i < text.length() - 1; i++) {
            if (text.substring(i, i + 1).equals(" ")) {
                var a = dc.getTextWidthInPixels(text.substring(0, i), f);
                var b = dc.getTextWidthInPixels(text.substring(i + 1, text.length()), f);
                var m = a > b ? a : b;
                if (m < bestW) { bestW = m; best = i; }
            }
        }
        if (best > 0) {
            var cy = y + h / 2;
            dc.drawText(x + w / 2, capY(f, cy - 8), f, Fit.trim(dc, text.substring(0, best), w - 8, f), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(x + w / 2, capY(f, cy + 8), f, Fit.trim(dc, text.substring(best + 1, text.length()), w - 8, f), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
    }
    var t = Fit.trim(dc, text, w - 8, font);
    dc.drawText(x + w / 2, capY(font, y + h / 2), font, t, Graphics.TEXT_JUSTIFY_CENTER);
}

// The cream disc every TamaPoke screen sits on, with its title.
function drawDisc(dc, title) {
    var cx = dc.getWidth() / 2;
    dc.setColor(0x000000, 0x000000);
    dc.clear();
    dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
    dc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());   // the background fills the screen
    dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
    // a size smaller, then the smallest, before a long (translated) title is ever cut
    var f = Fit.font(dc, title, 176, [UiFont.big(), UiFont.mid(), UiFont.small(), UiFont.tiny()]);
    dc.drawText(cx, 30, f, Fit.trim(dc, title, 176, f), Graphics.TEXT_JUSTIFY_CENTER);   // clear of the round top
}

// TamaPoke's party / box: cards of two columns (thumbnail, name, level) and a page number.
// Page 0 is the party (6), the following pages the box (6 each).
// UP/DOWN move the highlight across pages, START opens the member's actions, BACK closes.
class PartyView extends WatchUi.View {
    var model;
    var sel = 0;          // 0..5 party, 6.. box
    var thumbs = null;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onShow() { thumbs = true; }              // loaded one by one (Thumbs)
    function onHide() { thumbs = null; Thumbs.clear(); }

    // index space: 0..5 the party slots, 6.. the box
    function total() { return 6 + model.box.size(); }
    function page() { return sel < 6 ? sel / 3 : 2 + (sel - 6) / 4; }
    function pages() { return 2 + (model.box.size() + 3) / 4; }

    function memberAt(i) {
        if (i < 6) { return i < model.party.size() ? model.party[i] : null; }
        var b = i - 6;
        return b < model.box.size() ? model.box[b] : null;
    }

    // Party pages hold 3 slots, box pages 4: one full-width card each (thumbnail, name, level).
    function onUpdate(dc) {
        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        var p = page();
        var inBox = sel >= 6;
        drawDisc(dc, inBox ? Tr.t("POKÉBOX ") + model.box.size() + "/" + model.BOX_MAX : Tr.t("PARTY ") + model.party.size() + "/6");
        var first = inBox ? 6 + (p - 2) * 4 : p * 3;
        var count = inBox ? 4 : 3;
        for (var k = 0; k < count; k++) {
            var i = first + k;
            if (!inBox && i >= 6) { break; }
            if (inBox && i - 6 >= model.box.size()) { break; }
            var m = memberAt(i);
            var y = 66 + k * 42;
            dc.setColor(m == null ? 0xFFFF55 : 0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(Fit.COL_X, y, Fit.COL_W, 40, 7);
            dc.setColor(sel == i ? 0xFF0000 : 0x000000, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(sel == i ? 3 : 1);
            dc.drawRoundedRectangle(Fit.COL_X, y, Fit.COL_W, 40, 7);
            dc.setPenWidth(1);
            if (m == null) {
                dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, capY(UiFont.tiny(), y + 20), UiFont.tiny(), Tr.t("empty"), Graphics.TEXT_JUSTIFY_CENTER);
                continue;
            }
            var n = m[0];
            dc.setClip(Fit.COL_X + 2, y + 1, 38, 38);
            Thumbs.draw(dc, n, Fit.COL_X + 2, y + 1, false);
            dc.clearClip();
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Fit.COL_X + 44, capY(UiFont.tiny(), y + 11), UiFont.tiny(), Fit.trim(dc, model.memberName(m).toUpper(), Fit.COL_W - 52, UiFont.tiny()), Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(m[2] ? 0xFFAA00 : 0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Fit.COL_X + 44, capY(UiFont.tiny(), y + 29), UiFont.tiny(), Tr.t("Lv.") + m[3] + (m[2] ? Tr.t("  shiny *") : ""), Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 224, UiFont.tiny(), (p + 1) + "/" + pages() + Tr.t("   BACK"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class PartyDelegate2 extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { v.sel = (v.sel + 1) % v.total(); WatchUi.requestUpdate(); return true; }
    function onPreviousPage() { v.sel = (v.sel - 1 + v.total()) % v.total(); WatchUi.requestUpdate(); return true; }

    // A member's sheet of actions, in TamaPoke's panel style.
    function onSelect() {
        var m = v.memberAt(v.sel);
        if (m == null) { return true; }
        var inParty = v.sel < 6;
        var rows = [[Tr.t("INFO"), :info, 0, -1]];
        if (inParty) { rows.add([Tr.t("TO POKÉBOX"), :toBox, 0, -1]); }
        else { rows.add([Tr.t("TO PARTY"), :toParty, v.model.party.size() < 6 ? 0 : 2, -1]); }
        rows.add([Tr.t("RELEASE"), :release, 1, -1]);
        rows.add([Tr.t("CLOSE"), :close, 2, -1]);
        var pv = new PanelView(v.model.memberName(m).toUpper(), rows, null);
        WatchUi.pushView(pv, new PanelDelegate(pv, new MemberActions(v.model, inParty, inParty ? v.sel : v.sel - 6)), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

class MemberActions {
    var model;
    var inParty;
    var idx;

    function initialize(m, p, i) {
        model = m;
        inParty = p;
        idx = i;
    }

    function selectId(id) {
        if (id == :info) {
            var mv = new MemberView(model, inParty ? model.party[idx] : model.box[idx]);
            WatchUi.switchToView(mv, new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == :toBox) { model.toBox(idx); }
        else if (id == :toParty) { model.toParty(idx); }
        else if (id == :release) {
            var rows = [[Tr.t("RELEASE FOR GOOD"), :yes, 1, -1], [Tr.t("KEEP"), :close, 2, -1]];
            var pv = new PanelView(Tr.t("RELEASE?"), rows, Tr.t("It will not come back"));
            WatchUi.switchToView(pv, new PanelDelegate(pv, new ReleaseAction(model, inParty, idx)), WatchUi.SLIDE_LEFT);
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ReleaseAction {
    var model;
    var inParty;
    var idx;

    function initialize(m, p, i) {
        model = m;
        inParty = p;
        idx = i;
    }

    function selectId(id) {
        if (id == :yes) { model.releaseMember(inParty, idx); }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// TamaPoke's MOVES screen: four rows, each with the name, a type chip, STAB, and PWR or STATUS.
// START on a row lists what it can learn into that slot.
class MovesView extends WatchUi.View {
    var model;
    var sel = 0;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        drawDisc(dc, Tr.t("MOVES"));
        for (var i = 0; i < 4; i++) {
            var y = 66 + i * 38;
            var mv = model.moves[i];
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(Fit.COL_X, y, Fit.COL_W, 36, 7);
            dc.setColor(sel == i ? 0xFF0000 : 0x000000, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(sel == i ? 3 : 1);
            dc.drawRoundedRectangle(Fit.COL_X, y, Fit.COL_W, 36, 7);
            dc.setPenWidth(1);
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            if (mv == 0) {
                dc.drawText(cx, capY(UiFont.tiny(), y + 18), UiFont.tiny(), Tr.t("(empty)"), Graphics.TEXT_JUSTIFY_CENTER);
                continue;
            }
            dc.drawText(Fit.COL_X + 8, capY(UiFont.tiny(), y + 10), UiFont.tiny(), Fit.trim(dc, Moves.name(mv), Fit.COL_W - 16, UiFont.tiny()), Graphics.TEXT_JUSTIFY_LEFT);
            var t = Moves.type(mv);
            var tn = Moves.typeName(t);
            var cw = dc.getTextWidthInPixels(tn, UiFont.tiny()) + 8;
            dc.setColor(Moves.typeColor(t), Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(Fit.COL_X + 8, y + 19, cw, 15, 4);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            centerText(dc, Fit.COL_X + 8, y + 19, cw, 15, UiFont.tiny(), tn);
            var status = Moves.cat(mv) == Moves.MC_STATUS;
            if (!status && Moves.hasStab(model.dex, t)) {
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.drawText(Fit.COL_X + 12 + cw, capY(UiFont.tiny(), y + 26), UiFont.tiny(), Tr.t("STAB"), Graphics.TEXT_JUSTIFY_LEFT);
            }
            dc.setColor(status ? 0x000000 : 0xFF0000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Fit.COL_X + Fit.COL_W - 8, capY(UiFont.tiny(), y + 26), UiFont.tiny(), status ? Tr.t("STATUS") : Tr.t("PWR ") + Moves.power(mv), Graphics.TEXT_JUSTIFY_RIGHT);
        }
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 222, UiFont.tiny(), Tr.t("START: change   BACK"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class MovesDelegate2 extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { v.sel = (v.sel + 1) % 4; WatchUi.requestUpdate(); return true; }
    function onPreviousPage() { v.sel = (v.sel + 3) % 4; WatchUi.requestUpdate(); return true; }

    function onSelect() {
        var can = v.model.pendingLearnables();
        var rows = [];
        for (var i = 0; i < can.size(); i++) { rows.add([Moves.name(can[i]), can[i], 0, -1]); }
        rows.add([Tr.t("CLOSE"), :close, 2, -1]);
        var pv = new PanelView(can.size() > 0 ? Tr.t("LEARN") : Tr.t("NOTHING NEW"), rows, null);
        WatchUi.pushView(pv, new PanelDelegate(pv, new LearnInto(v.model, v.sel)), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

class LearnInto {
    var model;
    var slot;

    function initialize(m, s) {
        model = m;
        slot = s;
    }

    function selectId(id) {
        model.acceptLearn(slot, id);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// TamaPoke's settings pages (title, a big value, - / + buttons, the page dots and a green OK):
// here VIBRATION and CARE ALERTS, each ON or OFF, and your TRAININGS a week (1-14). UP = -, DOWN = +, START = OK, BACK = cancel;
// MENU (hold UP) goes to the next page.
class SettingsView extends WatchUi.View {
    var model;
    var page = 0;
    var values = [true, true, 3, 1];
    var single = false;     // opened from the SETTINGS list: just this one, OK goes back to it
    const TITLES = ["VIBRATION", "CARE ALERTS", "TRAININGS/WEEK", "LANGUAGE"];
    const PAGES = 4;

    function initialize(m) {
        View.initialize();
        model = m;
        values = [Sfx.enabled(), m.alertsOn(), m.trainingsPerWeek(), Tr.lang()];
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        drawDisc(dc, Tr.t(TITLES[page]));
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        var val = page == 2 ? values[2].toString() : (page == 3 ? Tr.NAMES[values[3]] : (values[page] ? Tr.t("ON") : Tr.t("OFF")));
        centerText(dc, cx - 54, 84, 108, 32, page == 3 ? UiFont.mid() : Graphics.FONT_LARGE, val);   // between the - and + buttons
        if (page == 2) {
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 122, UiFont.tiny(), Tr.t("now about ") + model.trainingsPerWeek() + Tr.t(" from your workouts"), Graphics.TEXT_JUSTIFY_CENTER);
        }
        for (var i = 0; i < 2; i++) {          // - and + buttons
            var x = i == 0 ? 52 : 196;
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, 84, 32, 32, 6);
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, 84, 32, 32, 6);
            centerText(dc, x, 84, 32, 32, UiFont.mid(), i == 0 ? "-" : "+");
        }
        for (var i = 0; !single && i < PAGES; i++) {      // page dots
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            if (i == page) { dc.fillCircle(cx - 18 + i * 12, 152, 3); } else { dc.drawCircle(cx - 18 + i * 12, 152, 3); }
        }
        dc.setColor(0x55FF55, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - 48, 168, 96, 30, 8);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        centerText(dc, cx - 48, 168, 96, 30, UiFont.mid(), "OK");
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 206, UiFont.tiny(), single ? Tr.t("BACK: cancel") : Tr.t("MENU: next   BACK: cancel"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class SettingsDelegate2 extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onPreviousPage() {      // UP: one more training (on the trainings page)
        if (v.page == 2) { if (v.values[2] < 14) { v.values[2] += 1; } }
        else if (v.page == 3) { v.values[3] = Tr.ORDER[(Tr.pos(v.values[3]) + Tr.ORDER.size() - 1) % Tr.ORDER.size()]; }   // the languages round
        else { v.values[v.page] = false; }
        WatchUi.requestUpdate();
        return true;
    }
    function onNextPage() {          // DOWN: one fewer
        if (v.page == 2) { if (v.values[2] > 1) { v.values[2] -= 1; } }
        else if (v.page == 3) { v.values[3] = Tr.ORDER[(Tr.pos(v.values[3]) + 1) % Tr.ORDER.size()]; }
        else { v.values[v.page] = true; }
        WatchUi.requestUpdate();
        return true;
    }
    function onMenu() {
        if (v.single) { return true; }
        v.page = (v.page + 1) % v.PAGES;
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        Storage.setValue("vibe", v.values[0]);
        v.model.setAlerts(v.values[1]);
        if (v.values[2] != v.model.trainingsPerWeek()) { v.model.setTrainingsPerWeek(v.values[2]); }
        if (v.values[3] != Tr.lang()) { Tr.set(v.values[3]); }      // everything is in it from now
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

// SETTINGS: a list like the main menu, one box per setting; START opens it to change, OK saves
// and comes back here. The labels follow the language as soon as it changes.
function settingsPanel(model) {
    var rows = [["VIBRATION", 0, 0, -1], ["CARE ALERTS", 1, 0, -1], ["TRAININGS/WEEK", 2, 0, -1], ["LANGUAGE", 3, 0, -1]];
    var pv = new PanelView("SETTINGS", rows, null);
    pv.tr = true;
    return [pv, new PanelDelegate(pv, new SettingsAction(model))];
}

class SettingsAction {
    var model;
    function initialize(m) { model = m; }
    function selectId(id) {
        var sv = new SettingsView(model);
        sv.page = id as Number;
        sv.single = true;
        WatchUi.pushView(sv, new SettingsDelegate2(sv), WatchUi.SLIDE_LEFT);
    }
}

// ---------------------------------------------------------------------------------------------
// GUIDE: a list of topics (like SETTINGS); each opens its own page of text, wrapped to the round
// screen, that UP/DOWN scroll. Titles and texts are English keys, translated as drawn.
// (a function, not a constant: global constants are built in every process, the 32 KB glance
// too, and these texts alone don't fit there)
function guideTopics() {
    return [
    ["BASICS", "Your partner lives on your watch. Feed it with the apple and bathe it with the drop. Its energy is your Body Battery, and it sleeps when you do. Its joy comes from your workouts. Being active earns it EXP, fruit and eggs."],
    ["HP", "The bar under your partner is its HP. Battles take it and it keeps what is left: your next battle starts from there. A battle that costs 40% or more of it also costs some food. HP refills by itself, from empty to full in 15 minutes. Each fruit gives some back at once, and so does every training game; a recorded activity gives back half of it."],
    ["GOOD CARE", "Look after your partner before a fight: when food, hygiene or joy is under half, its attacks miss more often (up to 4 in 10 when all three are empty). A training game sometimes finds a piece of fruit, at most one per game. Care alerts wait while you record an activity, so nothing buzzes mid-run."],
    ["TRAINING", "Each workout you record (5 min or more) fills joy and trains a stat: running SPEED, cycling and swimming DEFENSE, strength and gym ATTACK; walks, hikes and the rest train a random one. Joy slowly drops over a week, so keep up your trainings per week. The football has three mini-games."],
    ["EXP & LEVELS", "Every 50 steps give 1 EXP. Each activity you record gives EXP by its length and sport, per minute: running or swimming 20, strength or gym 27, cycling 15, hiking 12, walking 8, anything else 15 (so 45 minutes of weights pay like an hour's run). Intensity minutes outside your recorded activities give 10 EXP each. Battles give EXP too: wild fights a few times a day, gyms and link battles more. Your partner gets all of it and the rest of the team 25%. New levels teach moves and let it evolve."],
    ["FOOD & FRUIT", "Fruit is earned: an apple for every 5,000 steps (they add up over time, so 4,000 now and 1,000 later earn it), for every 45 active minutes and for reaching your step goal; a berry or an orange for each workout of 30 minutes or more and for reaching your step goal; candy for your weekly goal and each gym win. Every species has a favourite fruit."],
    ["EGGS", "Every 15,000 steps earns an egg, at most 5 in any 7 days. Steps carry over until you reach 15,000, but while you already have 5 eggs from the last 7 days they don't count. Open the app to collect it, then walk 1,000 to 3,000 steps to hatch it. Each step counts once: while an egg waits, your steps hatch it, and only the steps after that count toward the next egg. The steps of your runs and walks count too, even on days you don't open the app. It joins your team, or the Pokébox if the team is full."],
    ["BATTLES & GYMS", "Fight wild creatures from the menu and beat the 8 gyms in order to earn badges. Hard gyms are tougher and stay closed while your Body Battery is 20% or less. Link battles let you fight a friend online through your phone, or nearby watch to watch."],
    ["TEAM & POKÉBOX", "Your team holds 6: your partner plus 5. The rest wait in the Pokébox. There you can make any team member your partner, swap creatures between the team and the Pokébox, see their stats or release them. Only your partner gets hungry, tired, bored or dirty: the others' food, joy, energy and hygiene climb back to full within 24 hours, and their HP within 15 minutes. Each one keeps its own when it becomes your partner."],
    ["BATTLE EXTRAS", "Every creature has a nature that raises one stat by 10% and lowers another (its summary shows which, in orange and blue). In battle, the BAG lets it eat fruit: an apple brings back HP, a blue berry cures poison and burns, an orange wakes it up and cures paralysis, ice and confusion; eating takes the turn. Each of yours that beats a foe earns that foe's EXP. Beaten gym leaders come back stronger two days later for a rematch, and your rival XAVI turns up every few days."],
    ["GROWING STRONGER", "Each stat is its species' base, plus its level, plus a bonus from its IV, plus its trained points: each trained point adds 1 to that stat (ATTACK's to SP.ATK too, DEFENSE's to SP.DEF too). Only your partner trains. Stats grow slowly and steadily, like your own fitness: every workout brings the next point of a stat closer (a 30-minute one about a quarter of a point at first, a longer one more), a good training game a quarter of that (4 games a day count) and each gym win some too; each point takes a little longer than the last, with no fixed ceiling. Great care until it evolves (few care mistakes, a strong bond) adds 3 to each stat. Route Crossing trains DEFENSE: hop as far as you can over grass, paths, rivers and railways; it only ends when you are hit or fall in. The TRAINING panel's bars show how close each next point is: a full bar is +1. Your partner's summary shows the points the same way: SPD 2.72 is 2 points and 72% of the next."],
    ["REGIONS", "This TamaWatch holds the {0} region. Every region is its own version of the app, with its own game: pick another on the TamaWatch website. Link battles work with friends of any region; trades need the same one."],
    ["SETTINGS", "Vibration turns the buzz on or off. Care alerts send reminders when your partner needs you, and news about eggs. Trainings/week is your weekly workout target; it adjusts to what you really do. Language changes the whole app."],
    ["BUTTONS", "UP and DOWN move, START picks and BACK goes back. Hold UP, or pick the book, for the menu. In the Pokedex and the Pokébox, UP and DOWN turn pages until START picks on the page."]];
}

function guidePanel() {
    var rows = [];
    var topics = guideTopics();
    for (var i = 0; i < topics.size(); i++) { rows.add([topics[i][0], i, 0, -1]); }
    var pv = new PanelView("GUIDE", rows, null);
    pv.tr = true;
    return [pv, new PanelDelegate(pv, new GuideAction())];
}

class GuideAction {
    function initialize() {}
    function selectId(id) {
        var gv = new GuideView(id as Number);
        WatchUi.pushView(gv, new GuideDelegate(gv), WatchUi.SLIDE_LEFT);
    }
}

class GuideView extends WatchUi.View {
    var topic;
    var top = 0;            // first line shown
    var count = 0;          // lines in all
    const LH = 18;
    const Y0 = 64;
    const SHOW = 9;

    function initialize(t) {
        View.initialize();
        topic = t;
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        var gt = guideTopics()[topic];
        drawDisc(dc, Tr.t(gt[0]));
        var f = Graphics.FONT_XTINY;
        // the text in lines as wide as the circle allows where each will be drawn
        var words = Wire.split(Tr.f(gt[1], [Region.NAME]), " ");
        gt = null;
        var lines = [];
        var line = "";
        for (var i = 0; i < words.size(); i++) {
            var row = lines.size() - top;
            if (row < 0) { row = 0; }
            if (row >= SHOW) { row = SHOW - 1; }
            var maxW = Fit.span(Y0 + row * LH, LH, 210)[1] - 14;
            var t = line.length() == 0 ? words[i] : line + " " + words[i];
            if (line.length() > 0 && dc.getTextWidthInPixels(t, f) > maxW) {
                lines.add(line);
                line = words[i];
            } else {
                line = t;
            }
        }
        if (line.length() > 0) { lines.add(line); }
        count = lines.size();
        dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
        for (var k = 0; k < SHOW && top + k < count; k++) {
            dc.drawText(cx, capY(f, Y0 + k * LH + LH / 2), f, lines[top + k], Graphics.TEXT_JUSTIFY_CENTER);
        }
        // more above / below
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        if (top > 0) { dc.fillPolygon([[cx - 7, Y0 - 3], [cx + 7, Y0 - 3], [cx, Y0 - 10]]); }
        if (top + SHOW < count) {
            var by = Y0 + SHOW * LH + 3;
            dc.fillPolygon([[cx - 7, by], [cx + 7, by], [cx, by + 7]]);
        }
    }
}

// UP/DOWN scroll three lines; START or BACK goes back to the topics.
class GuideDelegate extends WatchUi.BehaviorDelegate {
    var v;
    function initialize(view) { BehaviorDelegate.initialize(); v = view; }
    function onNextPage() {
        if (v.top + v.SHOW < v.count) { v.top += 3; WatchUi.requestUpdate(); }
        return true;
    }
    function onPreviousPage() {
        v.top = v.top > 3 ? v.top - 3 : 0;
        WatchUi.requestUpdate();
        return true;
    }
    function onSelect() { WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
    function onBack() { WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
}
