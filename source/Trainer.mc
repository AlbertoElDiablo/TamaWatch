import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// You, the trainer: the first-run guide (name, character, trainings a week), the summary of what
// your activity earned while the app was closed, your profile, your team and each member's
// summary page.

const GREEN = 0x00AA00;        // the home screen's bar green (FOOD, ENE, HYG, steps, EXP)
const APPLE_RED = 0xFF0000;    // the main red of the apple icon
const TEAM_MATES = 5;          // the team: your partner and 5 more (PetModel.PARTY_MAX)
const KID_W = 48;
const KID_H = 72;

// One of the two characters (0 or 1) from the kids strip, top-left at x, y (72 tall): its lower
// 48 rows from cell g, its top 24 from cell 36 + g (make_trainer_art.py packs the strip 48 tall).
function drawKid(dc, kids, g, x, y) {
    dc.setClip(x, y + 24, KID_W, 48);
    dc.drawBitmap(x - g * KID_W, y + 24, kids);
    dc.setClip(x, y, KID_W, 24);
    dc.drawBitmap(x - (36 + g) * KID_W, y - 24, kids);
    dc.clearClip();
}

// A bar in the home screen's style: grey track, solid fill leaving a 1 px rim, black outline.
function drawFillBar(dc, x, y, w, h, num, den, color) {
    dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
    dc.fillRectangle(x, y, w, h);
    var fw = den > 0 ? ((w - 2) * num.toFloat() / den).toNumber() : 0;
    if (fw > w - 2) { fw = w - 2; }
    if (fw > 0) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 1, y + 1, fw, h - 2);
    }
    dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
    dc.drawRectangle(x, y, w, h);
}

// ---------------------------------------------------------------------------------------------
// The first-run guide. 0 welcome, 1 your name, 2 your character, 3 trainings a week, 4 done.
class SetupView extends WatchUi.View {
    const WHEEL = ["OK", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
                   "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "-", " ", "DEL"];
    const MAX_LEN = 10;

    var model;
    var stage = 0;
    var intro = 0;
    var petView = null;     // the home screen underneath, so BACK can lead out of the app          // stage 0 has four pages: welcome, training, battles, the guide
    var name = "";
    var at = 1;
    var gender = 0;
    var perWeek = 3;
    var kids = null;

    function initialize(m) {
        View.initialize();
        model = m;
        if (m.trName != null) { name = m.trName; gender = m.trGender; perWeek = m.trainingsPerWeek(); }
    }

    function onShow() { kids = WatchUi.loadResource(Rez.Drawables.kids); }
    function onHide() { kids = null; }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var w = dc.getWidth();
        var cx = w / 2;
        var titles = [Tr.t("WELCOME!"), Tr.t("YOUR NAME"), Tr.t("CHARACTER"), Tr.t("TRAININGS"), Tr.t("ALL SET!")];
        var introTitles = [Tr.t("WELCOME!"), Tr.t("TRAINING"), Tr.t("BATTLES"), Tr.t("GUIDE")];
        drawDisc(dc, stage == 0 ? introTitles[intro] : titles[stage]);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        var f = UiFont.tiny();
        if (stage == 0) {
            var y = paragraph(dc, Tr.t(INTRO[intro]), 62, f);
            if (intro == 1) {
                // what each kind of activity trains, in the stats' colours
                var rows = [[Tr.t("Running"), Tr.t("SPEED")], [Tr.t("Cycling, swimming"), Tr.t("DEFENSE")], [Tr.t("Strength, gym"), Tr.t("ATTACK")]];
                for (var i = 0; i < rows.size(); i++) {
                    var ry = y + i * 18;
                    dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(cx - 4, capY(f, ry + 9), f, rows[i][0], Graphics.TEXT_JUSTIFY_RIGHT);
                    dc.setColor(STAT_COL[i], Graphics.COLOR_TRANSPARENT);
                    dc.drawText(cx + 4, capY(f, ry + 9), f, rows[i][1], Graphics.TEXT_JUSTIFY_LEFT);
                }
            }
            // page dots, then the button underneath
            for (var i = 0; i < 4; i++) {
                dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
                if (i == intro) { dc.fillCircle(cx - 15 + i * 10, 186, 3); } else { dc.drawCircle(cx - 15 + i * 10, 186, 3); }
            }
            drawOk(dc, cx, 196, intro < 3 ? Tr.t("NEXT") : Tr.t("START"));
        } else if (stage == 1) {
            dc.drawText(cx, 62, UiFont.mid(), (name.length() > 0 ? name : "") + "_", Graphics.TEXT_JUSTIFY_CENTER);
            // the letter wheel: each letter centred on its row, the chosen one in its box
            for (var k = -2; k <= 2; k++) {
                var i = (at + k + WHEEL.size()) % WHEEL.size();
                var cy = 150 + k * 24;
                if (k == 0) {
                    dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(3);
                    dc.drawRoundedRectangle(cx - 34, cy - 14, 68, 28, 8);
                    dc.setPenWidth(1);
                }
                var label = Tr.t(WHEEL[i].equals(" ") ? "space" : WHEEL[i]);
                var lf = k == 0 ? UiFont.small() : f;
                dc.setColor(k == 0 ? 0x000055 : TEXT_GREY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, capY(lf, cy), lf, label, Graphics.TEXT_JUSTIFY_CENTER);
            }
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, capY(f, 214), f, Tr.t("START: add a letter"), Graphics.TEXT_JUSTIFY_CENTER);
        } else if (stage == 2) {
            for (var g = 0; g < 2; g++) {
                var bx = cx - 82 + g * 88;
                dc.setColor(g == gender ? 0xFFFF55 : 0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(bx, 64, 76, 100, 10);
                dc.setColor(g == gender ? 0xFF0000 : 0x000000, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(g == gender ? 3 : 1);
                dc.drawRoundedRectangle(bx, 64, 76, 100, 10);
                dc.setPenWidth(1);
                if (kids != null) { drawKid(dc, kids, g, bx + 14, 78); }
            }
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 174, f, Tr.t("UP / DOWN to choose"), Graphics.TEXT_JUSTIFY_CENTER);
            drawOk(dc, cx, 200, "OK");
        } else if (stage == 3) {
            dc.drawText(cx, 58, f, Tr.t("Workouts you record"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, 78, f, Tr.t("in a usual week"), Graphics.TEXT_JUSTIFY_CENTER);
            centerText(dc, cx - 50, 104, 100, 44, Graphics.FONT_NUMBER_MEDIUM, perWeek.toString());
            for (var i = 0; i < 2; i++) {
                var x = i == 0 ? 52 : 196;
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(x, 110, 32, 32, 6);
                dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(x, 110, 32, 32, 6);
                centerText(dc, x, 110, 32, 32, UiFont.mid(), i == 0 ? "-" : "+");
            }
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 154, f, Tr.t("Change it later in Settings"), Graphics.TEXT_JUSTIFY_CENTER);
            drawOk(dc, cx, 186, "OK");
        } else {
            if (kids != null) { drawKid(dc, kids, gender, cx - KID_W / 2, 58); }
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 124, UiFont.small(), Tr.t("Hi, ") + name + "!", Graphics.TEXT_JUSTIFY_CENTER);
            // wrapped to the screen: some languages need three lines
            var endY = paragraph(dc, Tr.t("Joy stays full while you") + " " + Tr.t("keep up ") + perWeek +
                      (perWeek == 1 ? Tr.t(" training") : Tr.t(" trainings")) + Tr.t(" a week"), 156, f);
            drawOk(dc, cx, endY + 6 > 206 ? endY + 6 : 206, model.starterPick ? Tr.t("PICK PARTNER") : Tr.t("START"));
        }
    }

    const INTRO = [
        Tr.t("Your adventure starts here! TamaWatch keeps you active, with your partner always by your side. Walk, run and train: it grows with you."),
        Tr.t("Every activity you record makes your partner stronger:"),
        Tr.t("Battle wild creatures, earn the badges of 8 gyms and challenge your friends, online or nearby. Ready?"),
        Tr.t("New here? Read the GUIDE: it explains HP, food, eggs, battles and more. Hold UP, or pick the book, and choose GUIDE.")];
    const STAT_COL = [0x0055AA, 0x00AA00, 0xFF0000];

    // Text wrapped to the round screen's width at each line, centred; returns the y below it.
    function paragraph(dc, text, y, f) {
        var words = Wire.split(text, " ");
        var lh = 18;
        var line = "";
        for (var i = 0; i < words.size(); i++) {
            var maxW = Fit.span(y, lh, 210)[1] - 12;
            var t = line.length() == 0 ? words[i] : line + " " + words[i];
            if (line.length() > 0 && dc.getTextWidthInPixels(t, f) > maxW) {
                dc.drawText(dc.getWidth() / 2, capY(f, y + lh / 2), f, line, Graphics.TEXT_JUSTIFY_CENTER);
                y += lh;
                line = words[i];
            } else {
                line = t;
            }
        }
        if (line.length() > 0) {
            dc.drawText(dc.getWidth() / 2, capY(f, y + lh / 2), f, line, Graphics.TEXT_JUSTIFY_CENTER);
            y += lh;
        }
        return y;
    }

    function drawOk(dc, cx, y, label) {
        var bf = Fit.font(dc, label, 150, [UiFont.mid(), UiFont.small(), UiFont.tiny()]);   // fits whatever the language
        var bw = dc.getTextWidthInPixels(label, bf) + 30;
        dc.setColor(0x55FF55, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - bw / 2, y, bw, 30, 8);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(cx - bw / 2, y, bw, 30, 8);
        centerText(dc, cx - bw / 2, y, bw, 30, bf, label);
    }
}

class SetupDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { return step(1); }
    function onPreviousPage() { return step(-1); }

    function step(d) {
        if (v.stage == 1) { v.at = (v.at + d + v.WHEEL.size()) % v.WHEEL.size(); }
        else if (v.stage == 2) { v.gender = 1 - v.gender; }
        else if (v.stage == 3) {
            v.perWeek -= d;                 // UP adds a training, DOWN takes one away
            if (v.perWeek < 1) { v.perWeek = 1; }
            if (v.perWeek > 14) { v.perWeek = 14; }
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        if (v.stage == 1) {
            var c = v.WHEEL[v.at];
            if (c.equals("OK")) {
                if (v.name.length() == 0) { return true; }
                v.stage = 2;
            } else if (c.equals("DEL")) {
                if (v.name.length() > 0) { v.name = v.name.substring(0, v.name.length() - 1); }
            } else if (v.name.length() < v.MAX_LEN) {
                v.name = v.name + c;
                if (v.name.length() == v.MAX_LEN) { v.at = 0; }   // full: the wheel goes to OK
            }
        } else if (v.stage == 4) {
            v.model.setTrainer(v.name, v.gender, v.perWeek);
            WatchUi.popView(WatchUi.SLIDE_LEFT);
            return true;
        } else if (v.stage == 0 && v.intro < 3) {
            v.intro++;                      // the next page of the welcome
        } else {
            v.stage++;
            if (v.stage == 1 && v.name.length() > 0) { v.at = 0; }
        }
        WatchUi.requestUpdate();
        return true;
    }

    // BACK steps back a page (and deletes a letter on the name page); the guide can't be skipped.
    function onBack() {
        if (v.stage == 1 && v.name.length() > 0) {
            v.name = v.name.substring(0, v.name.length() - 1);
        } else if (v.stage > 0) {
            v.stage--;
        } else if (v.intro > 0) {
            v.intro--;
        } else {
            // the first page: back to choosing the language, which is forgotten until picked again
            Tr.clear();
            var lp = languagePanel(v.model, v.petView);
            WatchUi.switchToView(lp[0], lp[1], WatchUi.SLIDE_RIGHT);
            return true;
        }
        WatchUi.requestUpdate();
        return true;
    }
}

// ---------------------------------------------------------------------------------------------
// When you come back: what your activity earned while the app was closed.
class ReportView extends WatchUi.View {
    var rows = [];

    function initialize(m) {
        View.initialize();
        if (m.repMin > 0) { rows.add([Tr.t("Active minutes"), m.repMin.toString()]); }
        if (m.repWork > 0) { rows.add([m.repWork == 1 ? Tr.t("Workout") : Tr.t("Workouts"), m.repWork.toString()]); }
        // no activity logged: the steps you walked instead
        if (m.repMin == 0 && m.repWork == 0 && m.repSteps > 0) { rows.add([Tr.t("Steps"), m.repSteps.toString()]); }
        if (m.repExp > 0) { rows.add([Tr.t("EXP"), "+" + m.repExp]); }
        if (m.repLv > 0) { rows.add([Tr.t("Level"), Tr.t("Lv.") + m.level() + "!"]); }
        if (m.repBag[0] > 0) { rows.add([Tr.t("Apples"), "+" + m.repBag[0]]); }
        if (m.repBag[1] > 0) { rows.add([Tr.t("Blue berries"), "+" + m.repBag[1]]); }
        if (m.repBag[2] > 0) { rows.add([Tr.t("Oranges"), "+" + m.repBag[2]]); }
        if (m.repBag[3] > 0) { rows.add([Tr.t("Candy"), "+" + m.repBag[3]]); }
        if (m.repJoy > 0) { rows.add([Tr.t("Joy"), "+" + m.repJoy]); }
        if (Incubator.repFound > 0) { rows.add([Tr.t("Eggs found"), "+" + Incubator.repFound]); }
        for (var i = 0; i < Incubator.repHatched.size(); i++) { rows.add([Tr.t("Hatched"), Incubator.repHatched[i]]); }
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        drawDisc(dc, Tr.t("WELCOME!"));
        var f = UiFont.tiny();
        var n = rows.size() > 6 ? 6 : rows.size();
        var rh = 22;
        var y0 = 140 - (n * rh) / 2 - 4;
        if (y0 < 64) { y0 = 64; }
        for (var i = 0; i < n; i++) {
            var y = y0 + i * rh;
            var sp = [Fit.COL_X, Fit.COL_W];
            dc.setColor(i % 2 == 0 ? 0xFFFFAA : 0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(sp[0], y, sp[1], rh);
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sp[0] + 10, capY(f, y + rh / 2), f, rows[i][0], Graphics.TEXT_JUSTIFY_LEFT);   // centred on its row with any font
            dc.setColor(rows[i][1].find("+") == 0 || rows[i][0].equals(Tr.t("Level")) ? GREEN : 0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sp[0] + sp[1] - 10, capY(f, y + rh / 2), f, rows[i][1], Graphics.TEXT_JUSTIFY_RIGHT);
        }
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y0 + n * rh + 10, UiFont.tiny(), Tr.t("START to continue"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class CloseDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onSelect() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

// ---------------------------------------------------------------------------------------------
// Your profile: name, character, team, when you joined, active minutes and medals.
class TrainerView extends WatchUi.View {
    var model;
    var kids = null;
    var thumbs = null;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onShow() {
        kids = WatchUi.loadResource(Rez.Drawables.kids);
        thumbs = true;                  // loaded one by one (Thumbs)
    }
    function onHide() { kids = null; thumbs = null; Thumbs.clear(); }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        drawDisc(dc, model.trName != null ? model.trName.toUpper() : Tr.t("TRAINER"));
        if (kids != null) { drawKid(dc, kids, model.trGender, 58, 64); }
        var f = UiFont.tiny();
        var d = Gregorian.info(new Time.Moment(model.trJoined), Time.FORMAT_SHORT);
        var lines = [[Tr.t("JOINED"), d.day + "/" + d.month + "/" + (d.year % 100).format("%02d")],
                     [Tr.t("ACTIVE"), model.activeTotal + Tr.t(" min")],
                     [Tr.t("MEDALS"), model.totalMedals.toString()],
                     [Tr.t("BADGES"), model.badgeCount(false) + "/8"]];
        for (var i = 0; i < lines.size(); i++) {
            var y = 62 + i * 19;
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(116, y, f, lines[i][0], Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(244, y, f, lines[i][1], Graphics.TEXT_JUSTIFY_RIGHT);
        }
        // the team: your partner, then the party
        var team = [model.isEgg() ? null : model.selfMember()];
        for (var i = 0; i < model.party.size() && team.size() < 6; i++) { team.add(model.party[i]); }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 144, f, Tr.t("TEAM"), Graphics.TEXT_JUSTIFY_CENTER);
        for (var i = 0; i < 6; i++) {
            var x = cx - 61 + (i % 3) * 42;          // three 40 px boxes, 2 apart, centred
            var y = 166 + (i / 3) * 42;
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x - 1, y - 1, 40, 40, 6);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x - 1, y - 1, 40, 40, 6);
            var m = i < team.size() ? team[i] : null;
            if (m == null || thumbs == null) { continue; }
            var n = m[0];
            var dy = ThumbCentres.DY[n - 1];         // the creature in the middle, not on the floor
            dc.setClip(x, y, 38, 38);
            Thumbs.draw(dc, n, x, y + dy, false);
            dc.clearClip();
        }
    }
}

// On your profile, START opens the team; BACK goes back.
class TrainerDelegate extends WatchUi.BehaviorDelegate {
    var v;
    function initialize(view) { BehaviorDelegate.initialize(); v = view; }
    function onSelect() {
        var tm = new TeamView(v.model);
        WatchUi.pushView(tm, new TeamDelegate2(tm), WatchUi.SLIDE_LEFT);
        return true;
    }
    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

// ---------------------------------------------------------------------------------------------
// The team: your partner and the party, one card each. START opens a member's summary.
class TeamView extends WatchUi.View {
    var model;
    var sel = 0;
    var boxMode = false;    // the pet box: the creatures you keep beyond the team of 6
    var thumbs = null;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onShow() { thumbs = true; }              // loaded one by one (Thumbs)
    function onHide() { thumbs = null; Thumbs.clear(); }

    function members() {
        if (boxMode) { return model.box; }
        var t = [];
        if (!model.isEgg()) { t.add(model.selfMember()); }
        for (var i = 0; i < model.party.size(); i++) { t.add(model.party[i]); }
        return t;
    }

    // Like the classic party list: one blue card per member on white, its icon on the left, name and level, and an HP bar with the numbers. The highlighted
    // card has an orange border. 4 cards a page.
    const PER = 3;
    const CARD_H = 52;

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var t = members();
        dc.setColor(0xFFFFFF, 0xFFFFFF);          // plain white, like the other menu screens
        dc.clear();
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 14, UiFont.small(), Tr.t(boxMode ? "POKÉBOX" : "TEAM"), Graphics.TEXT_JUSTIFY_CENTER);
        if (t.size() == 0) {
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, capY(UiFont.small(), 120), UiFont.small(), boxMode ? Tr.t("The Pokébox is empty") : Tr.t("No one yet"), Graphics.TEXT_JUSTIFY_CENTER);
            if (boxMode) {
                dc.drawText(cx, capY(Graphics.FONT_XTINY, 150), Graphics.FONT_XTINY, Tr.t("Send team members here"), Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx, capY(Graphics.FONT_XTINY, 170), Graphics.FONT_XTINY, Tr.t("from TEAM"), Graphics.TEXT_JUSTIFY_CENTER);
            }
            return;
        }
        if (sel >= t.size()) { sel = t.size() - 1; }
        var first = (sel / PER) * PER;
        for (var k = 0; k < PER; k++) {
            var i = first + k;
            if (i >= t.size()) { break; }
            drawCard(dc, t[i], 52 + k * (CARD_H + 5), i == sel);
        }
        if (t.size() > PER) {   // page dots
            var pages = (t.size() + PER - 1) / PER;
            for (var p = 0; p < pages; p++) {
                dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
                var dx = cx - (pages - 1) * 5 + p * 10;
                if (p == sel / PER) { dc.fillCircle(dx, 240, 3); } else { dc.drawCircle(dx, 240, 3); }
            }
        }
    }

    function drawCard(dc, m, y, on) {
        var x = Fit.COL_X;              // the menu's column
        var cw = Fit.COL_W;
        var st = model.memberStats(m);
        // card: blue with a lighter lower band, white rim, orange when highlighted
        dc.setColor(0x0055AA, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, cw, CARD_H, 8);
        dc.setColor(0x5555FF, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 40, y + 18, cw - 46, 1);
        dc.setColor(on ? 0xFF5500 : 0x000055, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(on ? 3 : 1);
        dc.drawRoundedRectangle(x, y, cw, CARD_H, 8);
        dc.setPenWidth(1);
        // the icon, straight on the card
        var bx = x + 20;
        var by = y + CARD_H / 2;
        if (thumbs != null) {
            var n = m[0];
            dc.setClip(bx - 19, by - 19, 38, 38);
            Thumbs.draw(dc, n, bx - 19, by - 19 + ThumbCentres.DY[n - 1], false);
            dc.clearClip();
        }
        // three lines: the name; the level and HP numbers; the HP bar
        var tx = x + 44;
        var r = x + cw - 8;
        var f = Graphics.FONT_XTINY;
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx, capY(f, y + 11), f, Fit.trim(dc, model.memberName(m).toUpper(), r - tx, f), Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(tx, capY(f, y + 26), f, Tr.t("Lv") + m[3], Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(r, capY(f, y + 26), f, st[0] + "/" + st[0], Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(tx, y + 35, 22, 12, 4);
        dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx + 11, capY(f, y + 41), f, Tr.t("HP"), Graphics.TEXT_JUSTIFY_CENTER);
        drawFillBar(dc, tx + 24, y + 36, r - tx - 24, 10, 1, 1, GREEN);
    }
}

class TeamDelegate2 extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { var n = v.members().size(); if (n > 0) { v.sel = (v.sel + 1) % n; } WatchUi.requestUpdate(); return true; }
    function onPreviousPage() { var n = v.members().size(); if (n > 0) { v.sel = (v.sel - 1 + n) % n; } WatchUi.requestUpdate(); return true; }

    // Your partner (first card) opens its summary. Another member asks: its summary, or make it
    // your partner (the one on the home screen, which gets the full EXP).
    function onSelect() {
        var t = v.members();
        if (v.sel >= t.size()) { return true; }
        if (v.boxMode) {
            // a creature in the box: its summary, into the team (or swap with a member when the
            // team is full), or let it go
            var full = v.model.party.size() >= TEAM_MATES;
            var rows = [[Tr.t("SUMMARY"), :sum, 0, -1],
                        full ? [Tr.t("SWAP WITH TEAM"), :swap, 0, -1] : [Tr.t("TO TEAM"), :toTeam, 0, -1],
                        [Tr.t("RELEASE"), :release, 1, -1]];
            var pv = new PanelView(v.model.memberName(t[v.sel]).toUpper(), rows, full ? Tr.t("The team is full (6)") : null);
            pv.tr = true;
            WatchUi.pushView(pv, new PanelDelegate(pv, new BoxMemberAction(v, v.sel)), WatchUi.SLIDE_UP);
            return true;
        }
        var isPet = v.sel == 0 && !v.model.isEgg();
        if (isPet || v.model.isEgg() || v.model.ceremony != v.model.CER_NONE) {
            var sv = new SummaryView(v.model, t[v.sel], isPet);
            WatchUi.pushView(sv, new SummaryDelegate(sv), WatchUi.SLIDE_LEFT);
            return true;
        }
        var rows = [[Tr.t("SUMMARY"), :sum, 0, -1], [Tr.t("MAKE PARTNER"), :partner, 0, -1],
                    [Tr.t("TO POKÉBOX"), :toBox, 0, -1], [Tr.t("RELEASE"), :release, 1, -1]];
        var pv = new PanelView(v.model.memberName(t[v.sel]).toUpper(), rows, Tr.t("The partner gets full EXP, the team 25%"));
        pv.tr = true;
        WatchUi.pushView(pv, new PanelDelegate(pv, new TeamMemberAction(v, v.sel - 1)), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

// ---------------------------------------------------------------------------------------------
// A member's summary, after the classic skills page: level and name, the sprite, the six stats,
// EXP and the next level, and your bond. Page 2 (DOWN): its moves and training.
class SummaryView extends WatchUi.View {
    var model;
    var m;
    var isPet;
    var page = 0;
    var meta = null;
    var art = null;

    function initialize(model_, member, pet) {
        View.initialize();
        model = model_;
        m = member;
        isPet = pet;
    }

    function onShow() {
        meta = WatchUi.loadResource(SpriteIndex.data(m[0]));
        art = SpriteIndex.art(meta, m[0], m[2]);
    }
    function onHide() { meta = null; art = null; }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var w = dc.getWidth();
        var cx = w / 2;
        dc.setColor(0xFFFFFF, 0xFFFFFF);
        dc.clear();
        var f = UiFont.tiny();
        var accent = Dex.row(m[0])[12];
        // header pill: level and name
        var title = Tr.t("Lv") + m[3] + "  " + (m[2] ? "*" : "") + model.memberName(m).toUpper();
        dc.setColor(0xAAAAFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - 92, 16, 184, 26, 9);
        dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(cx - 92, 16, 184, 26, 9);
        centerText(dc, cx - 74, 16, 148, 26, UiFont.small(), title);   // ~140 px of the pill is on screen up here
        if (page == 0) {
            // the sprite in its frame on the left, the stats on the right
            dc.setColor(0xAAAAFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(36, 52, 90, 96, 8);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(40, 56, 82, 88, 6);
            if (meta != null) {
                // centred in the frame: equal space left and right of the sprite itself
                var a = meta["idle"];
                var sx = 81 - (meta["ic"] != null ? meta["ic"] : a["w"] / 2);
                var sy = 136 - meta["foot"] + a["y"];
                dc.setClip(sx, sy, a["w"], a["h"]);
                dc.drawBitmap(sx, sy - a["r"] - art[1], art[0]);
                dc.clearClip();
            }
            var st = model.memberStats(m);
            // its nature: the name in the frame, the stat it raises in orange, the one it lowers in blue
            var nat = Battle.natureOf(m[4], m[5], m[6], m[7]);
            var natAt = [1, 2, 5, 3, 4];
            var upI = nat / 5 == nat % 5 ? -1 : natAt[nat / 5];
            var downI = nat / 5 == nat % 5 ? -1 : natAt[nat % 5];
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(81, capY(Graphics.FONT_XTINY, 64), Graphics.FONT_XTINY, Fit.trim(dc, Tr.t(Battle.natureNames()[nat]).toUpper(), 78, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_CENTER);
            var labels = [Tr.t("HP"), Tr.t("ATTACK"), Tr.t("DEFENSE"), Tr.t("SP.ATK"), Tr.t("SP.DEF"), Tr.t("SPEED")];
            if (dc.getTextWidthInPixels(labels[2], Graphics.FONT_XTINY) > 86) { labels[2] = Tr.t("DEF."); }   // VERTEIDIGUNG
            for (var i = 0; i < 6; i++) {
                var y = 50 + i * 17;
                dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(128, y + 1, 88, 15, 6);          // wide enough for VELOCIDADE
                dc.setColor(i == upI ? 0xFFAA00 : (i == downI ? 0x55AAFF : 0xFFFFFF), Graphics.COLOR_TRANSPARENT);
                dc.drawText(172, capY(Graphics.FONT_XTINY, y + 8), Graphics.FONT_XTINY, Fit.trim(dc, labels[i], 86, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_CENTER);
                dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
                dc.drawText(244, capY(Graphics.FONT_XTINY, y + 8), Graphics.FONT_XTINY, st[i].toString(), Graphics.TEXT_JUSTIFY_RIGHT);
            }
            // EXP: points, to the next level, and the bar
            var l = m[3];
            var e = isPet ? model.exp : Lvl.expFor(l);
            var next = l >= model.MAX_LEVEL ? 0 : Lvl.expFor(l + 1) - e;
            var into = l >= model.MAX_LEVEL ? 1 : e - Lvl.expFor(l);
            var span = l >= model.MAX_LEVEL ? 1 : Lvl.expFor(l + 1) - Lvl.expFor(l);
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(44, 154, f, Tr.t("EXP. POINTS"), Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(236, 154, f, e.toString(), Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(48, 174, f, Tr.t("NEXT LV."), Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(232, 174, f, next.toString(), Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
            var el = Tr.t("EXP");
            dc.drawText(56, 196, f, el, Graphics.TEXT_JUSTIFY_LEFT);
            var ex0 = 56 + dc.getTextWidthInPixels(el, f) + 8;
            drawFillBar(dc, ex0, 200, 224 - ex0, 10, into, span, GREEN);
            // bond
            var b = m.size() > 12 ? m[12] : 0;
            dc.setColor(APPLE_RED, Graphics.COLOR_TRANSPARENT);
            var bl = Tr.t("BOND");                                      // the bar starts after its label
            dc.drawText(62, 216, f, bl, Graphics.TEXT_JUSTIFY_LEFT);
            var bx0 = 62 + dc.getTextWidthInPixels(bl, f) + 8;
            drawFillBar(dc, bx0, 220, 214 - bx0, 10, b, 100, APPLE_RED);
        } else if (page == 2) {
            // your partner's care record, like the stats page: a grey label pill and its value
            var md = model;
            var age = md.ageMinutes;
            var fav = md.berryKnown ? Tr.t(["Apple", "Blue berry", "Orange"][md.dex % 3]) : "?";
            var rows = [["AGE", age / 1440 + "d " + (age % 1440) / 60 + "h"],
                        ["BOND", md.bond.toString()],
                        ["WEIGHT", md.weight.toString()],
                        ["ACTIVE WEEKS", md.streak + " (" + md.bestStreak + ")"],
                        ["THIS WEEK", md.weekPct() + "%"],
                        ["SLIP-UPS", md.careMistakes.toString()],
                        ["FAV. FRUIT", fav]];
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 50, f, Tr.t("CARE"), Graphics.TEXT_JUSTIFY_CENTER);
            for (var i = 0; i < rows.size(); i++) {
                var y = 76 + i * 22;
                dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(Fit.COL_X, y, 108, 17, 6);
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.drawText(Fit.COL_X + 54, capY(Graphics.FONT_XTINY, y + 9), Graphics.FONT_XTINY,
                            Fit.trim(dc, Tr.t(rows[i][0]), 102, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_CENTER);
                dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
                dc.drawText(Fit.COL_X + Fit.COL_W, capY(Graphics.FONT_XTINY, y + 9), Graphics.FONT_XTINY,
                            Fit.trim(dc, rows[i][1], Fit.COL_W - 114, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_RIGHT);
            }
        } else if (page == 3) {
            // its medals, like the moves page: boxes, yellow when earned
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 50, f, Tr.t("MEDALS"), Graphics.TEXT_JUSTIFY_CENTER);
            var bw = (Fit.COL_W - 6) / 2;
            for (var i = 0; i < 8; i++) {
                var got = model.hasMedal(1 << i);
                var x = Fit.COL_X + (i % 2) * (bw + 6);
                var y = 74 + (i / 2) * 32;
                dc.setColor(got ? 0xFFFFAA : 0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(x, y, bw, 28, 8);
                dc.setColor(got ? 0x000000 : 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(x, y, bw, 28, 8);
                dc.setColor(got ? 0x000055 : TEXT_GREY, Graphics.COLOR_TRANSPARENT);
                centerText(dc, x, y, bw, 28, Graphics.FONT_XTINY, Tr.t(model.MEDAL_NAMES[i]));
            }
        } else {
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 50, f, Tr.t("MOVES"), Graphics.TEXT_JUSTIFY_CENTER);
            var mv = m[11];
            for (var i = 0; i < 4; i++) {
                var y = 72 + i * 30;
                var sp = [Fit.COL_X, Fit.COL_W];
                dc.setColor(mv[i] != 0 ? 0xFFFFAA : 0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(sp[0], y, sp[1], 26, 8);
                dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(sp[0], y, sp[1], 26, 8);
                centerText(dc, sp[0], y, sp[1], 26, UiFont.small(), mv[i] != 0 ? Moves.name(mv[i]) : "-");
            }
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 196, f, Tr.t("TRAINED  ATK ") + m[8] + Tr.t("  DEF ") + m[9] + Tr.t("  SPD ") + m[10], Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 216, f, Tr.t("IV  ") + m[4] + " / " + m[5] + " / " + m[6] + " / " + m[7], Graphics.TEXT_JUSTIFY_CENTER);
        }
        // page dots
        var np = pages();
        for (var i = 0; i < np; i++) {
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            var dx = cx - (np - 1) * 5 + i * 10;
            if (i == page) { dc.fillCircle(dx, 246, 3); } else { dc.drawCircle(dx, 246, 3); }
        }
    }

    // your partner has its care record and medals too; the others, stats and moves
    function pages() { return isPet ? 4 : 2; }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { v.page = (v.page + 1) % v.pages(); WatchUi.requestUpdate(); return true; }
    function onPreviousPage() { v.page = (v.page + v.pages() - 1) % v.pages(); WatchUi.requestUpdate(); return true; }
    function onSelect() { return onNextPage(); }
    function onBack() { WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
}

class TeamMemberAction {
    var tv;
    var idx;            // index in the party

    function initialize(teamView, partyIdx) {
        tv = teamView;
        idx = partyIdx;
    }

    function selectId(id) {
        var m = tv.model;
        if (id == :sum) {
            var sv = new SummaryView(m, m.party[idx], false);
            WatchUi.switchToView(sv, new SummaryDelegate(sv), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == :partner) {
            makePartner(m, idx);
            tv.sel = 0;
        } else if (id == :toBox) {
            m.toBox(idx);
        } else if (id == :release) {
            confirmRelease(m, true, idx);
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// Releasing is for good, so it asks first.
function confirmRelease(m, inParty, idx) {
    var rows = [[Tr.t("RELEASE FOR GOOD"), :yes, 1, -1], [Tr.t("KEEP"), :close, 2, -1]];
    var pv = new PanelView(Tr.t("RELEASE?"), rows, Tr.t("It will not come back"));
    WatchUi.switchToView(pv, new PanelDelegate(pv, new ReleaseAction(m, inParty, idx)), WatchUi.SLIDE_LEFT);
}

class BoxMemberAction {
    var tv;
    var idx;            // index in the box

    function initialize(view, boxIdx) {
        tv = view;
        idx = boxIdx;
    }

    function selectId(id) {
        var m = tv.model;
        if (id == :sum) {
            var sv = new SummaryView(m, m.box[idx], false);
            WatchUi.switchToView(sv, new SummaryDelegate(sv), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == :toTeam) {
            m.toParty(idx);
        } else if (id == :swap) {
            // which team member goes into the box in its place
            var rows = [];
            for (var i = 0; i < m.party.size(); i++) {
                rows.add([m.memberName(m.party[i]).toUpper() + Tr.t(" Lv") + m.party[i][3], i, 0, -1]);
            }
            var pv = new PanelView(Tr.t("SWAP WITH"), rows, null);
            WatchUi.switchToView(pv, new PanelDelegate(pv, new SwapAction(m, idx)), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :release) {
            confirmRelease(m, false, idx);
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// A box creature and a team member change places.
class SwapAction {
    var model;
    var boxIdx;

    function initialize(m, b) {
        model = m;
        boxIdx = b;
    }

    function selectId(partyIdx) {
        var b = model.box[boxIdx];
        model.box[boxIdx] = model.party[partyIdx];
        model.party[partyIdx] = b;
        model.say(model.memberName(b) + Tr.t(" joined the team!"), 3000);
        model.save();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// A party member becomes the partner on the home screen, and the partner joins the party in
// its place. Everything that is the creature changes hands, its care (food, joy, energy,
// hygiene, HP) too: the one leaving keeps its own and recovers in the team (Care.mc).
function makePartner(m, idx) {
    if (idx < 0 || idx >= m.party.size() || m.isEgg() || m.ceremony != m.CER_NONE) { return; }
    var p = m.party[idx];
    var mine = m.selfMember();
    // the old partner takes its care with it (and recovers in the team); the new one brings its own
    Care.store(mine, m.food, m.joy, m.energy, m.hygiene, Hp.now(m));
    var cv = Care.now(p);
    m.food = cv[0]; m.joy = cv[1]; m.hygiene = cv[3];
    if (m.bbNow < 0) { m.energy = cv[2]; }      // with Body Battery, energy is yours
    m.hpv = [cv[4], Time.now().value()];
    m.dex = p[0]; m.nick = p[1]; m.shiny = p[2];
    m.ivAtk = p[4]; m.ivDef = p[5]; m.ivSpe = p[6]; m.ivHp = p[7];
    m.trAtk = p[8]; m.trDef = p[9]; m.trSpe = p[10];
    m.moves = [p[11][0], p[11][1], p[11][2], p[11][3]];
    if (m.moves.indexOf(0) == 0) { m.moves = Battle.bestMoves(p[0], p[3]); }
    m.bond = p.size() > 12 ? p[12] : 0;
    m.exp = p.size() > 13 ? p[13] : Lvl.expFor(p[3]);
    m.party[idx] = mine;
    m.learnQueue = [];
    m.lastLearnLevel = m.level();
    m.evoDeclinedLv = 0;
    m.berryKnown = false;
    m.pendingAnim = 3;
    m.say(m.name() + Tr.t(" is your partner!"), 3000);
    m.save();
}

// ---------------------------------------------------------------------------------------------
// The pet box, laid out like the Pokedex: 4 x 4 thumbnails a page. Your team comes first, each on
// a light-blue tile with a red dot (the partner's dot is gold), then the creatures in the box.
// UP/DOWN turn the pages; START picks on the page (UP/DOWN move, the name shows below); START
// again opens what you can do with it; BACK steps back.
class PetBoxView extends WatchUi.View {
    var model;
    var at = 0;
    var sel = 0;            // (for the team actions, which reset it)
    var picking = false;
    var thumbs = null;
    const PER = 16;
    const CELL = 46;
    const GX = 48;          // centred, as the Pokedex
    const GY = 56;
    const THUMB = 38;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    var eggBmp = null;

    function onShow() { thumbs = true; }              // loaded one by one (Thumbs)
    function onHide() { thumbs = null; eggBmp = null; Thumbs.clear(); }

    // [member, kind, index]: kind 0 the partner, 1 a team member (party index), 2 in the box
    function entries() {
        var e = [];
        if (!model.isEgg()) { e.add([model.selfMember(), 0, -1]); }
        for (var i = 0; i < model.party.size(); i++) { e.add([model.party[i], 1, i]); }
        for (var i = 0; i < model.box.size(); i++) { e.add([model.box[i], 2, i]); }
        var eggs = Incubator.waiting();                     // bonus eggs still to hatch: last
        for (var i = 0; i < eggs.size(); i++) { e.add([eggs[i], 3, i]); }
        return e;
    }

    function page() { return at / PER; }
    function pages(n) { var p = (n + PER - 1) / PER; return p < 1 ? 1 : p; }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        dc.setColor(0xFFFFFF, 0xFFFFFF);
        dc.clear();
        var e = entries();
        if (at >= e.size()) { at = e.size() > 0 ? e.size() - 1 : 0; }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 26, UiFont.mid(), Tr.t("POKÉBOX"), Graphics.TEXT_JUSTIFY_CENTER);
        if (e.size() == 0) {
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, capY(UiFont.small(), 130), UiFont.small(), Tr.t("No one yet"), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        for (var k = 0; k < PER; k++) {
            var i = page() * PER + k;
            if (i >= e.size()) { break; }
            var x = GX + (k % 4) * CELL;
            var y = GY + (k / 4) * CELL;
            var kind = e[i][1];
            if (kind < 2) {                                   // your team: tile and dot
                dc.setColor(0xAAFFFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(x + 2, y + 2, CELL - 4, CELL - 4, 8);
            }
            var n = e[i][0][0];
            if (kind == 3) {                                  // an egg (the home screen's): a surprise inside
                if (eggBmp == null) { eggBmp = WatchUi.loadResource(Rez.Drawables.egg_small); }
                dc.drawBitmap(x + (CELL - 32) / 2, y + (CELL - 32) / 2, eggBmp);
            } else if (thumbs != null) {
                var ox = x + (CELL - THUMB) / 2;
                var oy = y + (CELL - THUMB) / 2;
                dc.setClip(ox, oy, THUMB, THUMB);
                Thumbs.draw(dc, n, ox, oy + ThumbCentres.DY[n - 1], false);
                dc.clearClip();
            }
            if (kind < 2) {
                dc.setColor(kind == 0 ? 0xFFAA00 : 0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x + CELL - 9, y + 9, 4);
                dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x + CELL - 9, y + 9, 4);
            }
            if (picking && i == at) {
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawRoundedRectangle(x + 1, y + 1, CELL - 2, CELL - 2, 8);
                dc.setPenWidth(1);
            }
        }
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        var f = Graphics.FONT_XTINY;
        if (picking && e[at][1] == 3) {
            dc.drawText(cx, capY(f, 250), f, Fit.trim(dc, Tr.f("{0} steps left", [e[at][0][2]]), 166, f), Graphics.TEXT_JUSTIFY_CENTER);
        } else if (picking) {
            var m = e[at][0];
            dc.drawText(cx, capY(f, 250), f, Fit.trim(dc, model.memberName(m).toUpper() + Tr.t(" Lv") + m[3], 150, f), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(cx, capY(f, 250), f, "< " + (page() + 1) + "/" + pages(e.size()) + Tr.t(" >  START"), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class PetBoxDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { return move(1); }
    function onPreviousPage() { return move(-1); }

    function move(d) {
        var n = v.entries().size();
        if (n == 0) { return true; }
        if (!v.picking) {
            var pg = v.pages(n);
            v.at = ((v.page() + d + pg) % pg) * v.PER;
        } else {
            var first = v.page() * v.PER;
            var count = n - first < v.PER ? n - first : v.PER;
            v.at = first + (v.at - first + d + count) % count;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        var e = v.entries();
        if (e.size() == 0) { return true; }
        if (!v.picking) { v.picking = true; WatchUi.requestUpdate(); return true; }
        var en = e[v.at];
        var m = v.model;
        if (en[1] == 3) {                                   // an egg: how far it has to go
            var pv = new PanelView(Tr.t("EGG"), [[Tr.t("CLOSE"), :close, 2, -1]],
                                   Tr.f("{0} steps left", [en[0][2]]));
            WatchUi.pushView(pv, new PanelDelegate(pv, null), WatchUi.SLIDE_UP);
            return true;
        }
        var name = m.memberName(en[0]).toUpper();
        if (en[1] == 0) {                                   // your partner: summary, release
            var rows = [["SUMMARY", :sum, 0, -1], ["RELEASE", :release, m.canRetireNow() ? 1 : 2, -1]];
            var pv = new PanelView(name, rows, Tr.t("Your partner"));
            pv.tr = true;
            pv.title = en[0][1].length() > 0 ? en[0][1].toUpper() : SpriteIndex.name(en[0][0]).toUpper();
            WatchUi.pushView(pv, new PanelDelegate(pv, new PartnerAction(m)), WatchUi.SLIDE_UP);
        } else if (en[1] == 1) {                            // a team member
            var rows = [[Tr.t("SUMMARY"), :sum, 0, -1], [Tr.t("MAKE PARTNER"), :partner, 0, -1],
                        [Tr.t("TO POKÉBOX"), :toBox, 0, -1], [Tr.t("RELEASE"), :release, 1, -1]];
            var pv = new PanelView(name, rows, Tr.t("In your team"));
            pv.tr = true;
            WatchUi.pushView(pv, new PanelDelegate(pv, new TeamMemberAction(v, en[2])), WatchUi.SLIDE_UP);
        } else {                                            // in the box
            var full = m.party.size() >= TEAM_MATES;
            var rows = [[Tr.t("SUMMARY"), :sum, 0, -1],
                        full ? [Tr.t("SWAP WITH TEAM"), :swap, 0, -1] : [Tr.t("TO TEAM"), :toTeam, 0, -1],
                        [Tr.t("RELEASE"), :release, 1, -1]];
            var pv = new PanelView(name, rows, full ? Tr.t("The team is full (6)") : null);
            pv.tr = true;
            WatchUi.pushView(pv, new PanelDelegate(pv, new BoxMemberAction(v, en[2])), WatchUi.SLIDE_UP);
        }
        return true;
    }

    function onBack() {
        if (v.picking) { v.picking = false; WatchUi.requestUpdate(); return true; }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

// ---------------------------------------------------------------------------------------------
// The very first screen: the language, before anything else. The six by their own names in
// alphabetical order, the watch's own language picked to start with (and the title in it).
const LANG_TITLE = ["IDIOMA", "LANGUAGE", "IDIOMA", "LANGUE", "LINGUA", "IDIOMA", "SPRACHE"];

function languagePanel(model, petView) {
    var def = Tr.deviceDefault();
    var rows = [];
    for (var k = 0; k < Tr.ORDER.size(); k++) { rows.add([Tr.NAMES[Tr.ORDER[k]], Tr.ORDER[k], 0, -1]); }
    var pv = new PanelView(LANG_TITLE[def], rows, null);
    pv.sel = Tr.pos(def);
    return [pv, new LangDelegate(pv, new LangAction(model, petView), petView)];
}

// BACK on the language leaves the app (the language screen comes back next time).
class LangDelegate extends PanelDelegate {
    var petView;
    function initialize(view, t, pv) { PanelDelegate.initialize(view, t); petView = pv; }
    function onBack() {
        if (petView != null) { petView.leaving = true; }    // the home screen closes the app
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// The language is saved, then the welcome guide takes the screen's place.
class LangAction {
    var model;
    var petView;
    function initialize(m, pv) { model = m; petView = pv; }
    function selectId(id) {
        Tr.set(id as Number);
        var sv = new SetupView(model);
        sv.petView = petView;
        WatchUi.switchToView(sv, new SetupDelegate(sv), WatchUi.SLIDE_LEFT);
    }
}

// Your partner, from the pet box: its summary, or retiring / releasing it (as the menu once did).
class PartnerAction {
    var model;
    function initialize(m) { model = m; }
    function selectId(id) {
        if (id == :sum) {
            var sv = new SummaryView(model, model.selfMember(), true);
            WatchUi.switchToView(sv, new SummaryDelegate(sv), WatchUi.SLIDE_LEFT);
            return;
        }
        var rows;
        var title;
        var sub = null;
        if (!model.canRetireNow()) { return; }               // greyed out (asleep, an egg...)
        title = Tr.t("RELEASE?");
        rows = [[Tr.t("RELEASE"), :doRelease, 1, -1], [Tr.t("CANCEL"), :none, 0, -1]];
        sub = Tr.t("It will not come back");
        var pv = new PanelView(title, rows, sub);
        WatchUi.switchToView(pv, new PanelDelegate(pv, new ConfirmAction(model, null)), WatchUi.SLIDE_LEFT);
    }
}
