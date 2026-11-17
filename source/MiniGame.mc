import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// TamaPoke's three training games, with taps turned into the watch's buttons:
//   BAG   (STRENGTH, 10 s)  START as the swinging bag crosses the line
//   DODGE (SPEED, 15 s)     UP / DOWN move the creature between three lanes
//   ROUTE (DEFENSE)         START hops forward, UP / DOWN step left / right: cross grass (trees
//                           and boulders block), paths (wild creatures dash by), rivers (ride the
//                           logs, hop the lily pads) and railways; a point a lane, faster and
//                           busier the further it gets, until it's hit or falls in
// BACK quits and keeps what was earned. The pieces are simple shapes; the creature is its sprite.
class MiniGameView extends WatchUi.View {

    const BAG = 0;
    const DODGE = 1;
    const BRACE = 2;
    const NAMES = ["TRAINING BAG", "DODGE RUN", "ROUTE CROSSING"];
    const LENGTH_MS = [10000, 15000, 30000];

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

    // route crossing: the lanes, by number from the start (0, 1 grass); each [kind, direction,
    // speed px/s, [[x, width], ...]]; kind 0 grass (items: bushes, by column), 1 path (items
    // roll), 2 river (items: logs to ride)
    var lanes = {};
    var row = 0;          // the lane it stands on
    var px = 90.0;        // where it stands across the field (0..FIELD_W)
    var crashed = false;
    var face = 1;         // which way the trainer faces: 0 front, 1 back (up the route), 2 left, 3 right
    var steps = 0;        // moves made: the walking frame alternates with each
    var kids = null;      // the trainers' picture (its walking views: make_trainer_art.py)
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
        if (mode == BRACE) { kids = WatchUi.loadResource(Rez.Drawables.kids); }
        timer = new Timer.Timer();
        timer.start(method(:tick), 50, true);
    }

    function onHide() {
        if (timer != null) { timer.stop(); timer = null; }   // the timer points back at this view: drop it, or neither is ever freed
        Thumbs.clear();
        RouteArt.clear();
        kids = null;
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
            else { crossStep(dt); }
            if (mode != BRACE && elapsed() >= LENGTH_MS[mode]) { finish(); }   // the route ends only on a fall
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

    // the stat this game trains is already as high as its IV allows
    function statFull() {
        if (mode == BAG) { return model.trAtk >= model.trMaxFor(model.ivAtk); }
        if (mode == DODGE) { return model.trSpe >= model.trMaxFor(model.ivSpe); }
        return model.trDef >= model.trMaxFor(model.ivDef);
    }

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

    // ---------- route crossing ----------

    const COLS = 6;
    const CW = 36;                        // a column's width
    const FIELD_W = 216;                  // COLS * CW
    const PERIOD = 288;                   // items wrap round every this many px
    const RH = 30;                        // a lane's height on screen
    const TOP = 5;                        // the field's top on screen (9 lanes fill the round screen)
    const LANES = 9;
    const STAND = 6;                      // the screen lane it stands on (0 top .. 8)

    // Lanes are made in order, a few ahead. Kinds (after expo-crossy-road's rows, MIT, by Evan
    // Bacon): 0 grass (trees block), 1 path (wild creatures dash across), 2 river with drifting
    // logs, 3 river with still lily pads, 4 railway (a light flashes, then a train sweeps by).
    // A clear way through always exists: pathCol wanders a column at a time, and no tree stands
    // on it (nor on the last one's) and a lily pad always floats on it.
    var made = -1;
    var pathCol = 2;
    var lastHop = 0;

    function laneAt(k) {
        while (made < k) { makeLane(made + 1); }
        var l = lanes.get(k);
        return l != null ? l : [0, 1, 0, []];
    }

    function makeLane(k) {
        made = k;
        var prevCol = pathCol;
        pathCol += rnd(3) - 1;
        if (pathCol < 0) { pathCol = 0; }
        if (pathCol > COLS - 1) { pathCol = COLS - 1; }
        var kind = 0;
        if (k > 1) {
            var a = lanes.get(k - 1);
            var b = lanes.get(k - 2);
            var wet = a != null && a[0] >= 2 && a[0] <= 3 && b != null && b[0] >= 2 && b[0] <= 3;
            var r = rnd(100);
            var g = 30 - k / 4 < 16 ? 16 : 30 - k / 4;            // less grass to rest on, further on
            kind = r < g ? 0 : (r < 62 ? 1 : (r < 75 ? 2 : (r < 84 ? 3 : 4)));
            if ((kind == 2 || kind == 3) && (wet || k < 4)) { kind = 1; }
            if (kind == 4 && k < 6) { kind = 0; }
            if (kind == 3 && a != null && a[0] == 2) { kind = 0; }      // no jump from a log to a pad
        }
        var items = [];
        var dir = rnd(2) == 0 ? -1 : 1;
        // the further, the faster and the busier
        var speed = 24 + (k * 6 / 5 > 90 ? 90 : k * 6 / 5) + rnd(16 + k / 5);
        var trees = 20 + (k / 3 > 20 ? 20 : k / 3);
        if (kind == 0) {
            if (k > 1) {
                for (var c = 0; c < COLS; c++) {
                    if (c != pathCol && c != prevCol && rnd(100) < trees) { items.add([c * CW, CW, rnd(3) == 0 ? 1 : 0]); }
                }
            }
            speed = 0;
        } else if (kind == 3) {
            pathCol = prevCol;                                   // the pad right ahead of the way
            items.add([pathCol * CW, CW, 0]);
            for (var c = 0; c < COLS; c++) {
                if (c != pathCol && rnd(100) < (35 - k / 2 < 8 ? 8 : 35 - k / 2)) { items.add([c * CW, CW, 0]); }
            }
            speed = 0;
        } else if (kind == 4) {
            speed = 320;
            items.add([-999.0, 3 * CW, 0]);                      // the train, waiting off the field
        } else {
            var n = kind == 1 ? 1 + rnd(2) + (k > 15 ? 1 : 0) + (k > 35 ? 1 : 0) : (k > 30 ? 2 : 3);
            for (var i = 0; i < n; i++) {
                // a path's are wild creatures dashing across (30 wide); a river's, logs (shorter, further on)
                var w = kind == 1 ? 30 : (100 - k < 52 ? 52 : 100 - k) + rnd(24);
                var who = 1;
                for (var t = 0; t < 10; t++) {
                    who = 1 + rnd(Dex.COUNT);
                    if (Dex.rarity(who) != Dex.R_LEGEND) { break; }
                }
                items.add([(i * PERIOD / n + rnd(30)).toFloat(), w, who]);
            }
        }
        // [kind, direction, speed, items, railway: when the next train comes (ms)]
        lanes.put(k, [kind, dir, speed, items, System.getTimer() + 2500 + rnd(4000)]);
        lanes.remove(k - 12);
    }

    // a tree (or boulder) in the grass at column c?
    function bush(l, c) {
        if (l[0] != 0) { return false; }
        for (var i = 0; i < l[3].size(); i++) { if (l[3][i][0] == c * CW) { return true; } }
        return false;
    }

    // is x (across the field) on one of the lane's moving items (wrapping round)?
    function onItem(l, x, pad) {
        for (var i = 0; i < l[3].size(); i++) {
            var it = l[3][i];
            for (var w = -1; w <= 1; w++) {
                var a = it[0] + w * PERIOD;
                if (x >= a - pad && x <= a + it[1] + pad) { return true; }
            }
        }
        return false;
    }

    function crossStep(dt) {
        if (crashed) { return; }
        var now = System.getTimer();
        if (lastHop == 0) { lastHop = now; }
        var sec = dt / 1000.0;
        for (var k = row - 2; k <= row + STAND; k++) {
            if (k < 0) { continue; }
            var l = laneAt(k);
            if (l[0] == 1 || l[0] == 2) {
                for (var i = 0; i < l[3].size(); i++) {
                    var x = l[3][i][0] + l[1] * l[2] * sec;
                    if (x >= PERIOD) { x -= PERIOD; }
                    if (x < 0) { x += PERIOD; }
                    l[3][i][0] = x;
                }
            } else if (l[0] == 4) {
                // the train: due at l[4], it enters from its side, sweeps across, then waits again
                var t = l[3][0];
                if (now >= l[4] && t[0] < -900) { t[0] = (l[1] > 0 ? -t[1] - 20 : FIELD_W + 20).toFloat(); }
                if (t[0] > -900) {
                    t[0] += l[1] * l[2] * sec;
                    if (t[0] > FIELD_W + 40 || t[0] < -t[1] - 40) { t[0] = -999.0; l[4] = now + 2500 + rnd(5000 - row * 60 < 1500 ? 1500 : 5000 - row * 60); }
                }
            }
        }
        var here = laneAt(row);
        if (here[0] == 2) {
            // on a log it drifts with it; off one, or carried off the field, it falls in
            if (onItem(here, px, -4)) { px += here[1] * here[2] * sec; }
            if (!onItem(here, px, -4) || px < 0 || px > FIELD_W) { crash(Tr.t("SPLASH!")); }
        } else if (here[0] == 3) {
            if (!bush(here, (px / CW).toNumber())) { crash(Tr.t("SPLASH!")); }   // not on a pad
        } else if ((here[0] == 1 && onItem(here, px, -10)) || (here[0] == 4 && here[3][0][0] > -900 && onItem(here, px, -6))) {
            crash(Tr.t("OUCH"));
        }
    }

    function crash(word) {
        crashed = true;
        face = 0;                         // it turns round
        say(word);
        finish();
    }

    // START: one lane forward (a bush in the way: it stays); UP / DOWN: a column left / right
    function hop() {
        if (done || crashed) { return; }
        var next = laneAt(row + 1);
        var col = (px / CW).toNumber();
        if (col > COLS - 1) { col = COLS - 1; }
        if (col < 0) { col = 0; }
        if (next[0] == 0 && bush(next, col)) { return; }
        row += 1;
        face = 1;
        steps += 1;
        lastHop = System.getTimer();
        if (next[0] != 2) { px = (col * CW + CW / 2).toFloat(); }   // off the logs: back on the grid
        if (row > score) { score = row; }
    }

    function sidestep(d) {
        if (done || crashed) { return; }
        var l = laneAt(row);
        face = d < 0 ? 2 : 3;
        steps += 1;
        var nx = px + d * CW;
        if (nx < CW / 2 - 1 || nx > FIELD_W - CW / 2 + 1) { return; }
        if (l[0] == 0 && bush(l, (nx / CW).toNumber())) { return; }
        px = nx;
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
        if (!done && mode == BRACE) { drawCross(dc, cx); return; }         // the route fills the screen
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 18, Graphics.FONT_XTINY, Tr.t(NAMES[mode]), Graphics.TEXT_JUSTIFY_CENTER);
        if (done) { drawResult(dc, cx); return; }
        var left = (LENGTH_MS[mode] - elapsed()) / 1000;
        dc.drawText(cx, 36, Graphics.FONT_XTINY, score + Tr.t(" pts   ") + (left < 0 ? 0 : left) + "s", Graphics.TEXT_JUSTIFY_CENTER);
        if (mode == BAG) { drawBag(dc, cx); }
        else if (mode == DODGE) { drawDodge(dc, cx); }
        else { drawCross(dc, cx); }
        if (System.getTimer() < flashUntil) {
            dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 56, Graphics.FONT_SMALL, flash, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawResult(dc, cx) {
        var stat = [Tr.t("STRENGTH"), Tr.t("SPEED"), Tr.t("DEFENSE")];
        dc.drawText(cx, 80, Graphics.FONT_MEDIUM, score + Tr.t(" points"), Graphics.TEXT_JUSTIFY_CENTER);
        // what it trained, or why nothing: that stat is already full, or too few points;
        // a size smaller (and trimmed) when the language needs more room
        var line = gain > 0 ? stat[mode] + " +" + gain : (statFull() ? stat[mode] + ": " + Tr.t("Fully trained")
                   : (Extra.gamesLeft() == 0 ? Tr.t("Enough training for today") : Tr.t("No training gained")));
        var lf = Fit.font(dc, line, 200, [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);
        dc.drawText(cx, 120, lf, Fit.trim(dc, line, 210, lf), Graphics.TEXT_JUSTIFY_CENTER);
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

    // The route (RouteArt.mc): ground strips painted once, the things on it drawn with shading,
    // your partner and the wild creatures as their thumbnails with a shadow under them.
    function drawCross(dc, cx) {
        RouteArt.make();
        var x0 = cx - FIELD_W / 2;
        var now = System.getTimer();
        for (var s = LANES - 1; s >= 0; s--) {
            var k = row + (STAND - s);
            if (k < 0) { continue; }
            drawLane(dc, laneAt(k), k, x0, TOP + s * RH, now);
        }
        // you, the trainer you chose, facing the way you last moved (flickering after a fall)
        if (kids != null && (!crashed || (now / 100) % 2 == 0)) {
            var py = TOP + STAND * RH;
            var ppx = x0 + px.toNumber();
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.fillEllipse(ppx, py + RH - 4, 10, 3);
            var cell = 2 + (model.trGender == 1 ? 8 : 0) + face * 2 + steps % 2;
            var top = py + RH - 3 - 50;                  // (up to 40 x 50 at 2x, on its cell's floor)
            dc.setClip(ppx - 20, top, 40, 50);
            dc.drawBitmap(ppx - 20 - (cell * 48 + 4), top - 22, kids);
            dc.clearClip();
        }
        // the distance, in a box at the top; how to play until the first hop
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - 28, 16, 56, 30, 8);
        dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(cx - 28, 16, 56, 30, 8);
        dc.setPenWidth(1);
        centerText(dc, cx - 28, 16, 56, 30, Graphics.FONT_SMALL, score.toString());
        if (row == 0) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cx - 105, 52, 210, 22, 6);
            dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
            centerText(dc, cx - 105, 52, 210, 22, Graphics.FONT_XTINY, Tr.t("START hop, UP/DOWN move"));
        }
    }

    function drawLane(dc, l, k, x0, y, now) {
        var sx = x0 - (RouteArt.SW - FIELD_W) / 2;
        if (l[0] == 0) {
            dc.drawBitmap(sx, y, k % 2 == 0 ? RouteArt.grassA : RouteArt.grassB);
            for (var i = 0; i < l[3].size(); i++) {
                var tx = x0 + l[3][i][0] + CW / 2;
                if (l[3][i][2] == 1) { RouteArt.boulder(dc, tx, y); } else { RouteArt.tree(dc, tx, y); }
            }
        } else if (l[0] == 1) {
            dc.drawBitmap(sx, y, RouteArt.path);
            for (var i = 0; i < l[3].size(); i++) {
                var it = l[3][i];
                for (var w = -1; w <= 1; w++) {
                    var ix = x0 + it[0].toNumber() + w * PERIOD;
                    if (ix > x0 + FIELD_W + 40 || ix + it[1] < x0 - 40) { continue; }
                    dc.setColor(0xAA5500, Graphics.COLOR_TRANSPARENT);
                    dc.fillEllipse(ix + 15, y + RH - 4, 11, 3);
                    dc.setClip(ix - 4, y - 6, 38, RH + 6);
                    Thumbs.draw(dc, it[2], ix - 4, y + RH / 2 - 23, false);
                    dc.clearClip();
                }
            }
        } else if (l[0] == 2 || l[0] == 3) {
            // the water scrolls slowly (its ripples repeat every 24)
            dc.drawBitmap(sx - ((now / 120) % 24) * l[1] - 24, y, RouteArt.water);
            for (var i = 0; i < l[3].size(); i++) {
                var it = l[3][i];
                if (l[0] == 3) { RouteArt.lily(dc, x0 + it[0] + CW / 2, y, (it[0] / CW + k) % 3 == 0); continue; }
                for (var w = -1; w <= 1; w++) {
                    var ix = x0 + it[0].toNumber() + w * PERIOD;
                    if (ix > x0 + FIELD_W + 40 || ix + it[1] < x0 - 40) { continue; }
                    RouteArt.log(dc, ix, y, it[1]);
                }
            }
        } else {
            dc.drawBitmap(sx, y, RouteArt.rail);
            var t = l[3][0];
            RouteArt.signal(dc, x0 - 14, y, t[0] < -900 && now >= l[4] - 1500 && (now / 200) % 2 == 0);
            if (t[0] > -900) { RouteArt.train(dc, x0 + t[0].toNumber(), y, t[1], l[1]); }
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
        else if (v.mode == v.BRACE) { v.hop(); }
        return true;
    }

    function onPreviousPage() {          // UP
        if (v.mode == v.DODGE) { v.dodgeMove(-1); }
        else if (v.mode == v.BRACE) { v.sidestep(-1); }
        return true;
    }

    function onNextPage() {              // DOWN
        if (v.mode == v.DODGE) { v.dodgeMove(1); }
        else if (v.mode == v.BRACE) { v.sidestep(1); }
        return true;
    }

    function onBack() {                  // quit and keep what was earned
        if (!v.done) { v.finish(); return true; }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
