import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// TamaPoke's three training games, with taps turned into the watch's buttons:
//   BAG   (STRENGTH, 10 s)  START as the swinging bag crosses the line
//   DODGE (SPEED, 15 s)     UP / DOWN move the creature between three lanes
//   BRACE (DEFENSE, 20 s)   UP = left, START = top, DOWN = right raises a shield on that side
// BACK quits and keeps what was earned. The pieces are simple shapes; the creature is its sprite.
class MiniGameView extends WatchUi.View {

    const BAG = 0;
    const DODGE = 1;
    const BRACE = 2;
    const NAMES = ["TRAINING BAG", "DODGE RUN", "BRACE & BLOCK"];
    const LENGTH_MS = [10000, 15000, 20000];

    var model;
    var petView;
    var mode;
    var timer = null;
    var t0 = 0;
    var last = 0;
    var score = 0;
    var streak = 0;
    var done = false;
    var gain = 0;
    var flash = "";       // PERFECT / GOOD / MISS ...
    var flashUntil = 0;

    // bag
    var phase = 0.0;      // radians of swing
    var pass = 0;         // half-swing index
    var passScored = false;
    var lockUntil = 0;

    // dodge
    var lane = 1;
    var rows = [];        // [y, mask, resolved]
    var nextRowAt = 0;
    var stunUntil = 0;

    // brace
    var hearts = 4;
    var orbs = [];        // [side, launchedAt, flightMs, resolved]
    var nextOrbAt = 0;
    var shieldSide = -1;
    var shieldAt = 0;
    var lastRaise = -1000;

    function initialize(m, pv, gameMode) {
        View.initialize();
        model = m;
        petView = pv;
        mode = gameMode;
    }

    function onShow() {
        t0 = System.getTimer();
        last = t0;
        nextRowAt = t0 + 600;
        nextOrbAt = t0 + 800;
        timer = new Timer.Timer();
        timer.start(method(:tick), 50, true);
    }

    function onHide() {
        if (timer != null) { timer.stop(); timer = null; }   // the timer points back at this view: drop it, or neither is ever freed
    }

    function rnd(n) { return Math.rand().abs() % n; }
    function elapsed() { return System.getTimer() - t0; }

    function tick() as Void {
        var now = System.getTimer();
        var dt = now - last;
        last = now;
        if (!done) {
            if (mode == BAG) { bagStep(dt); }
            else if (mode == DODGE) { dodgeStep(now); }
            else { braceStep(now); }
            if (elapsed() >= LENGTH_MS[mode] || (mode == BRACE && hearts <= 0)) { finish(); }
        }
        WatchUi.requestUpdate();
    }

    function say(text) {
        flash = text;
        flashUntil = System.getTimer() + 600;
    }

    // The session pays out once, through the pet's own training rules.
    function finish() {
        if (done) { return; }
        done = true;
        if (mode == BAG) { gain = model.trainStrength(score); }
        else if (mode == DODGE) { gain = model.trainSpeed(score); }
        else { gain = model.playResult(score); }
        found = Hp.afterGame(model);
    }
    var found = -1;             // the fruit found during the game (-1: none)

    // ---------- bag: the period speeds up from 1.5 s to 1.0 s ----------

    function period() { return 1500 - 500 * elapsed() / LENGTH_MS[BAG]; }

    function bagStep(dt) {
        phase += Math.PI * 2 * dt / period();
        var p = (phase / Math.PI).toNumber();
        if (p != pass) {
            if (!passScored) { streak = 0; }   // a pass with no press breaks the streak
            pass = p;
            passScored = false;
        }
    }

    function bagPress() {
        var now = System.getTimer();
        if (now < lockUntil || passScored) { return; }
        // distance to the nearest crossing (phase at a multiple of pi), in ms
        var frac = phase / Math.PI - (phase / Math.PI).toNumber();
        var off = frac < 0.5 ? frac : 1.0 - frac;
        var ms = (off * period() / 2).toNumber();
        if (ms <= 50) { award(5, Tr.t("PERFECT!")); }
        else if (ms <= 120) { award(3, Tr.t("GOOD")); }
        else {
            streak = 0;
            lockUntil = now + 320;
            say(Tr.t("MISS"));
            return;
        }
        passScored = true;
    }

    function award(pts, text) {
        streak++;
        var bonus = streak / 3;
        if (bonus > 3) { bonus = 3; }
        score += pts + bonus;
        say(text);
    }

    // ---------- dodge: rows fall faster and closer together ----------

    function dodgeStep(now) {
        var k = elapsed() * 1.0 / LENGTH_MS[DODGE];
        var speed = 0.096 + 0.084 * k;                  // px/ms (TamaPoke's 0.16 -> 0.30 at 466 px)
        for (var i = 0; i < rows.size(); i++) {
            var r = rows[i];
            r[0] = r[0] + speed * 50;
            if (!r[2] && r[0] >= 196) {                  // reaches the creature
                r[2] = true;
                if (((r[1] >> lane) & 1) == 1 && now >= stunUntil) {
                    stunUntil = now + 400;
                    streak = 0;
                    say(Tr.t("CRASH!"));
                } else if (now >= stunUntil) {
                    streak++;
                    var bonus = streak / 3;
                    if (bonus > 2) { bonus = 2; }
                    score += 3 + bonus;
                }
            }
        }
        while (rows.size() > 0 && rows[0][0] > 260) { rows = rows.slice(1, null); }
        if (now >= nextRowAt) {
            var mask;
            if (rnd(100) < 70) { mask = 1 << rnd(3); }
            else { var open = rnd(3); mask = 7 & ~(1 << open); }   // two blocked, one open
            rows.add([40.0, mask, false]);
            nextRowAt = now + (1300 - 350 * k).toNumber();
        }
    }

    function dodgeMove(d) {
        if (System.getTimer() < stunUntil) { return; }
        lane = lane + d;
        if (lane < 0) { lane = 0; }
        if (lane > 2) { lane = 2; }
    }

    // ---------- brace: orbs telegraph from the left, top or right ----------

    function braceStep(now) {
        var k = elapsed() * 1.0 / LENGTH_MS[BRACE];
        var flight = (1250 - 250 * k).toNumber();
        for (var i = 0; i < orbs.size(); i++) {
            var o = orbs[i];
            if (o[3]) { continue; }
            var impact = o[1] + o[2];
            if (now >= impact) {
                o[3] = true;
                var up = shieldSide == o[0] && now - shieldAt <= 320;
                if (up) {
                    var parry = impact - shieldAt <= 90;
                    streak++;
                    var bonus = streak / 4;
                    if (bonus > 2) { bonus = 2; }
                    score += (parry ? 3 : 2) + bonus;
                    say(parry ? Tr.t("PARRY!") : Tr.t("BLOCK"));
                } else {
                    hearts--;
                    streak = 0;
                    say(Tr.t("OUCH"));
                }
            }
        }
        while (orbs.size() > 0 && orbs[0][3]) { orbs = orbs.slice(1, null); }
        if (now >= nextOrbAt) {
            var side = rnd(3);
            orbs.add([side, now, flight, false]);
            if (k >= 0.5 && rnd(4) == 0) {               // from halfway, some come in pairs
                var other = (side + 1 + rnd(2)) % 3;
                orbs.add([other, now + 380, flight, false]);
            }
            nextOrbAt = now + flight + 350;
        }
    }

    function raise(side) {
        var now = System.getTimer();
        if (now - lastRaise < 240) { return; }
        lastRaise = now;
        shieldSide = side;
        shieldAt = now;
    }

    // ---------- drawing ----------

    const BG = 0xFFFFFF;
    const INK = 0x000055;

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(BG, BG);
        dc.clear();
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 18, Graphics.FONT_XTINY, Tr.t(NAMES[mode]), Graphics.TEXT_JUSTIFY_CENTER);
        if (done) { drawResult(dc, cx); return; }
        var left = (LENGTH_MS[mode] - elapsed()) / 1000;
        dc.drawText(cx, 36, Graphics.FONT_XTINY, score + Tr.t(" pts   ") + (left < 0 ? 0 : left) + "s", Graphics.TEXT_JUSTIFY_CENTER);
        if (mode == BAG) { drawBag(dc, cx); }
        else if (mode == DODGE) { drawDodge(dc, cx); }
        else { drawBrace(dc, cx); }
        if (System.getTimer() < flashUntil) {
            dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 56, Graphics.FONT_SMALL, flash, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawResult(dc, cx) {
        var stat = [Tr.t("STRENGTH"), Tr.t("SPEED"), Tr.t("DEFENSE")];
        dc.drawText(cx, 80, Graphics.FONT_MEDIUM, score + Tr.t(" points"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 120, Graphics.FONT_SMALL, gain > 0 ? stat[mode] + " +" + gain : Tr.t("No training gained"), Graphics.TEXT_JUSTIFY_CENTER);
        if (found >= 0) {
            var fruit = [Tr.t("Found an apple!"), Tr.t("Found a blue berry!"), Tr.t("Found an orange!")];
            dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 152, Graphics.FONT_XTINY, fruit[found], Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 200, Graphics.FONT_XTINY, Tr.t("START"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // The creature's idle frame (from the home screen's loaded sheet) standing on footY.
    function drawPet(dc, cx, footY) {
        var m = petView.meta;
        var bmp = petView.bmp;
        if (m == null || bmp == null) { return; }
        var a = m["idle"];
        var x = cx + a["x"];
        var y = footY - m["foot"] + a["y"];
        dc.setClip(x, y, a["w"], a["h"]);
        dc.drawBitmap(x, y - a["r"] - petView.sheetY, bmp);
        dc.clearClip();
    }

    function drawBag(dc, cx) {
        var ang = 0.6 * Math.sin(phase);
        var px = cx;
        var py = 70;
        var bx = px + (90 * Math.sin(ang)).toNumber();
        var by = py + (90 * Math.cos(ang)).toNumber();
        dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);   // the line to hit
        dc.fillRectangle(cx - 1, 150, 3, 26);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(px, py, bx, by);
        dc.setPenWidth(1);
        dc.setColor(0xAA0000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx - 12, by - 6, 24, 36, 8);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(bx - 12, by - 6, 24, 36, 8);
        drawPet(dc, cx - 60, 232);
        if (streak >= 3) { dc.drawText(cx + 70, 200, Graphics.FONT_XTINY, "x" + streak, Graphics.TEXT_JUSTIFY_CENTER); }
    }

    const LANE_X = [86, 140, 194];

    function drawDodge(dc, cx) {
        dc.setColor(0xFF5555, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(60, 60, 160, 180);
        for (var i = 0; i < rows.size(); i++) {
            var r = rows[i];
            for (var l = 0; l < 3; l++) {
                if (((r[1] >> l) & 1) == 1) {
                    dc.setColor(0xAA0000, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(LANE_X[l], r[0].toNumber(), 14);
                    dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
                    dc.drawCircle(LANE_X[l], r[0].toNumber(), 14);
                }
            }
        }
        var stunned = System.getTimer() < stunUntil;
        if (!stunned || (System.getTimer() / 80) % 2 == 0) { drawPet(dc, LANE_X[lane], 226); }
    }

    function drawBrace(dc, cx) {
        var cy = 150;
        var now = System.getTimer();
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 4; i++) {
            dc.setColor(i < hearts ? 0xFF0000 : 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 30 + i * 20, 62, 6);
        }
        var starts = [[30, cy], [cx, 60], [250, cy]];
        for (var i = 0; i < orbs.size(); i++) {
            var o = orbs[i];
            if (now < o[1]) { continue; }
            var t = (now - o[1]) * 1.0 / o[2];
            if (t > 1.0) { t = 1.0; }
            var sx = starts[o[0]][0];
            var sy = starts[o[0]][1];
            for (var d = 0; d < 6; d++) {          // the dotted path
                var u = d / 6.0;
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle((sx + (cx - sx) * u).toNumber(), (sy + (cy - sy) * u).toNumber(), 2);
            }
            dc.setColor(0x0000FF, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle((sx + (cx - sx) * t).toNumber(), (sy + (cy - sy) * t).toNumber(), 8);
        }
        drawPet(dc, cx, cy + 30);
        if (shieldSide >= 0 && now - shieldAt <= 320) {
            dc.setColor(0x00AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(5);
            if (shieldSide == 0) { dc.drawLine(cx - 40, cy - 30, cx - 40, cy + 30); }
            else if (shieldSide == 1) { dc.drawLine(cx - 30, cy - 50, cx + 30, cy - 50); }
            else { dc.drawLine(cx + 40, cy - 30, cx + 40, cy + 30); }
            dc.setPenWidth(1);
        }
    }
}

class MiniGameDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onSelect() {
        if (v.done) { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
        if (v.mode == v.BAG) { v.bagPress(); }
        else if (v.mode == v.BRACE) { v.raise(1); }
        return true;
    }

    function onPreviousPage() {          // UP
        if (v.mode == v.DODGE) { v.dodgeMove(-1); }
        else if (v.mode == v.BRACE) { v.raise(0); }
        return true;
    }

    function onNextPage() {              // DOWN
        if (v.mode == v.DODGE) { v.dodgeMove(1); }
        else if (v.mode == v.BRACE) { v.raise(2); }
        return true;
    }

    function onBack() {                  // quit and keep what was earned
        if (!v.done) { v.finish(); return true; }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
