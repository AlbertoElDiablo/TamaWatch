import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// TamaPoke's three training games, with taps turned into the watch's buttons:
//   BAG   (STRENGTH, 10 s)  START as the swinging bag crosses the line
//   SPRINT (SPEED)          a best-of-5 sprint start against a rival: START the moment the light
//                           turns green (before it: a false start, the heat lost); the quicker
//                           reaction gets off the line first and wins the heat
//   ROUTE (DEFENSE)         START hops forward, UP / DOWN step left / right: cross grass (trees
//                           and boulders block), paths (wild creatures dash by), rivers (ride the
//                           logs, hop the lily pads) and railways; a point a lane, faster and
//                           busier the further it gets, until it's hit or falls in
// BACK quits and keeps what was earned. The pieces are simple shapes; the creature is its sprite.
class MiniGameView extends WatchUi.View {

    const BAG = 0;
    const SPRINT = 1;
    const BRACE = 2;
    const NAMES = ["TRAINING BAG", "SPRINT START", "ROUTE CROSSING"];
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

    // sprint start: the heat's state and when it began; the light's yellow (random) length; when it
    // turned green; the rival's and your reaction (ms; -1 not yet); a false start; heats won and
    // lost; your best clean reaction; what the heat came to (shown under the track)
    const S_READY = 0;
    const S_RED = 1;
    const S_YELLOW = 2;
    const S_GO = 3;
    const S_RESULT = 4;
    const RUN_MS = 1100;          // a runner's dash from the line to the finish
    var st = 0;
    var stAt = 0;
    var yellowMs = 0;
    var greenAt = 0;
    var aiMs = 0;
    var myMs = -1;
    var foul = false;
    var slow = false;
    var heat = 0;
    var wins = 0;
    var losses = 0;
    var bestMs = -1;
    var heatWon = false;
    var sprint = null;            // the track, the light and the rail (tools/make_sprint_art.py)

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
    var gym = null;       // TRAINING BAG's room (tools/make_gym_room.py)
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
        stAt = t0;
        nextOrbAt = t0 + 800;
        if (mode == BRACE || mode == SPRINT) {
            if (petView != null) { petView.shed(); }   // home's pictures aren't needed here: room for these
            kids = WatchUi.loadResource(Rez.Drawables.kids);
        }
        if (mode == BRACE) { RouteArt.make(); }         // the ground's first strip (one a frame: see drawCross)
        if (mode == SPRINT) { sprint = WatchUi.loadResource(Rez.Drawables.sprint); }
        if (mode == BAG) { gym = WatchUi.loadResource(Rez.Drawables.gym); }   // loaded once, here: never mid-game
        timer = Ticker.take(0);                   // (a reused timer: see Ticker)
        Ticker.t[0].start(method(:tick), 50, true);
    }

    function onHide() {
        if (timer != null) { Ticker.release(0, timer); timer = null; }   // the timer points back at this view: drop it, or neither is ever freed
        Thumbs.clear();
        RouteArt.clear();
        kids = null;
        gym = null;
        sprint = null;
    }

    function rnd(n) { return Math.rand().abs() % n; }
    function elapsed() { return System.getTimer() - t0; }

    function tick() as Void {
        var now = System.getTimer();
        var dt = now - last;
        last = now;
        if (!done) {
            if (mode == BAG) { bagStep(dt); }
            else if (mode == SPRINT) { sprintStep(now); }
            else { crossStep(dt); }
            if (mode == BAG && elapsed() >= LENGTH_MS[mode]) { finish(); }   // the others end themselves
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
        else if (mode == SPRINT) {
            if (wins >= 3) { score += 10; }                 // the match won
            gain = model.trainSpeed(score);
        }
        else { gain = model.playResult(score); }
        found = Hp.afterGame(model);
        if (mode != SPRINT) {
            // Route Crossing keeps its furthest run, the training bag its highest score
            var key = mode == BRACE ? "rcBest" : "bagBest";
            var b = Application.Storage.getValue(key);
            best = b instanceof Number ? b : 0;
            if (score > best) {
                newBest = best > 0;
                best = score;
                Application.Storage.setValue(key, score);
            }
        }
    }
    var best = -1;              // Route Crossing's or the training bag's record (-1: SPRINT START)
    var newBest = false;        // ... just beaten
    var found = -1;             // the fruit found during the game (-1: none)

    // the stat this game trains is already as high as its IV allows
    function statFull() {
        if (mode == BAG) { return model.trAtk >= model.trMaxFor(model.ivAtk); }
        if (mode == SPRINT) { return model.trSpe >= model.trMaxFor(model.ivSpe); }
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

    // ---------- sprint start ----------
    // Each heat: HEAT n (0.9 s), red (0.7 s), yellow (0.5-1.8 s, so green can't be counted on), green:
    // START now. The rival reacts in 230-400 ms, a little quicker each heat (182-352 by the fifth);
    // the runners leave the line at green plus their reaction and take RUN_MS to the finish, so the
    // quicker reaction wins (yours on a tie). No press within a second: TOO SLOW (the heat lost).
    // START before green, or within 100 ms of it (a guess, as in athletics): a false start, the heat
    // lost. First to 3 heats.
    // Points: a heat won 10, plus 6 under 200 ms, 4 under 250, 2 under 300; a false start -5; the
    // match won +10 (at the end); never below 0.

    function sprintStep(now) {
        if (st == S_READY && now - stAt >= 900) { st = S_RED; stAt = now; }
        else if (st == S_RED && now - stAt >= 700) { st = S_YELLOW; stAt = now; yellowMs = 500 + rnd(1300); }
        else if (st == S_YELLOW && now - stAt >= yellowMs) {
            st = S_GO; stAt = now; greenAt = now;
            aiMs = 230 + rnd(171) - heat * 12;
        } else if (st == S_GO) {
            if (myMs < 0 && !foul && now - greenAt >= 1000) { myMs = 1000; slow = true; }   // too slow
            var mine = foul ? 0 : myMs;
            if (mine >= 0 && now >= greenAt + (aiMs > mine ? aiMs : mine) + RUN_MS) { heatOver(now); }
        } else if (st == S_RESULT && now - stAt >= 1500) {
            if (wins >= 3 || losses >= 3) { finish(); return; }
            heat++;
            st = S_READY; stAt = now;
            myMs = -1; foul = false; slow = false;
        }
    }

    function sprintPress() {
        var now = System.getTimer();
        if (st == S_RED || st == S_YELLOW) {
            foul = true;                       // the rival goes on its own
            st = S_GO; stAt = now; greenAt = now; aiMs = 250;
        } else if (st == S_GO && !foul && myMs < 0) {
            myMs = now - greenAt;
            if (myMs < 100) {                  // quicker than anyone can react: it was guessed (as in athletics)
                foul = true; myMs = -1;
            }
        }
    }

    function heatOver(now) {
        st = S_RESULT; stAt = now;
        heatWon = !foul && !slow && myMs <= aiMs;
        if (heatWon) {
            wins++;
            score += 10 + (myMs < 200 ? 6 : (myMs < 250 ? 4 : (myMs < 300 ? 2 : 0)));
        } else {
            losses++;
            if (foul) { score = score > 5 ? score - 5 : 0; }
        }
        if (!foul && !slow && (bestMs < 0 || myMs < bestMs)) { bestMs = myMs; }
    }

    // a reaction as seconds: 0.231 s
    function secs(ms) {
        return (ms / 1000) + "." + (ms % 1000).format("%03d") + " s";
    }

    // ---------- route crossing ----------

    const COLS = 6;
    const CW = 36;                        // a column's width
    const FIELD_W = 216;                  // COLS * CW
    const PERIOD = 528;                   // items wrap round every this many px (its 22 tiles, scaled)
    const RH = 30;                        // a lane's height on screen
    const TOP = 5;                        // the field's top on screen (9 lanes fill the round screen)
    const LANES = 9;
    const STAND = 6;                      // the screen lane it stands on (0 top .. 8)
    const WILD = 10;                      // wild creatures in kids.png (make_trainer_art.py WILD)

    // Lanes are made in order, a few ahead. Kinds (after expo-crossy-road's rows, MIT, by Evan
    // Bacon): 0 grass (trees block), 1 path (wild creatures dash across), 2 river with drifting
    // logs, 3 river with still lily pads, 4 railway (a light flashes, then a train sweeps by).
    // A way through: the middle column's grass is never blocked, and pads and open grass line up.
    var made = -1;
    var lastHop = 0;

    function laneAt(k) {
        while (made < k) { makeLane(made + 1); }
        var l = lanes.get(k);
        return l != null ? l : [0, 1, 0, []];                   // (behind the start: plain grass)
    }

    // One row, the way expo-crossy-road's CrossyGame.newRow makes it: the first rows grass (the
    // start's open, the next ones dotted), then grass, a road or a river, each as likely; a road is
    // a railway one time in four; a river on an even row holds lily pads, on an odd one drifting
    // logs. Its sizes are scaled from its 9-tile field to our 6 columns (its 22-tile wrap: PERIOD).
    function makeLane(k) {
        made = k;
        var prev = lanes.get(k - 1);
        // and harder the further it goes (h 0 at the start .. 100 a hundred rows on): less grass,
        // busier grass, faster roads and rivers, shorter logs further apart, fewer pads, more trains
        var h = k > 100 ? 100 : k;
        var kind = 0;
        if (k >= 5) {
            var r = rnd(100);
            var grass = 34 - h / 7;                              // a third, down to a fifth
            if (r >= grass) {
                if (r < grass + (100 - grass) / 2) { kind = rnd(100) < 25 + h / 10 ? 4 : 1; }
                else { kind = k % 2 == 0 ? 3 : 2; }
            }
        }
        var items = [];
        var dir = rnd(2) == 0 ? -1 : 1;
        var speed = 0;
        if (kind == 0) {
            // Grass.treeGen: walking the columns, each (but the middle one) gets a rock or tree four
            // times in ten, until 1-3 stand; a lily pad just behind keeps its column open
            // ... never walling off a pocket: a tree stands only at an edge or next to another one
            // towards it, so every open square of the row reaches the middle column sideways (a
            // trainer can't get stuck between trees with the row ahead blocked)
            if (k >= 2) {
                var count = 1 + rnd(3) + h / 50;
                var n = 0;
                var blocked = [false, false, false, false, false, false];
                var order = [0, 5, 1, 4, 3];
                for (var j = 0; j < order.size() && n < count; j++) {
                    var c = order[j];
                    if (prev != null && prev[0] == 3 && bush(prev, c)) { continue; }
                    if (c == 1 && !blocked[0]) { continue; }
                    if ((c == 4 && !blocked[5]) || (c == 3 && !blocked[4])) { continue; }
                    if (rnd(10) >= 4) {
                        blocked[c] = true;
                        items.add([c * CW, CW, rnd(10) < 4 ? rnd(4) : 4 + rnd(8)]);   // 40 % rocks
                        n++;
                    }
                }
            }
        } else if (kind == 3) {
            // Water.generateStatic: 2-3 pads, 2-3 columns apart from one of the first two; one of
            // them on an open column of the grass just behind
            var cols = [] as Array<Number>;
            var pc = rnd(2);
            var pads = 2 + (rnd(100) < 60 - h / 2 ? 1 : 0);
            for (var i = 0; i < pads && pc < COLS; i++) { cols.add(pc); pc += 2 + rnd(2); }
            if (prev != null && prev[0] == 0) {
                var ok = false;
                for (var i = 0; i < cols.size(); i++) { if (!bush(prev, cols[i])) { ok = true; } }
                if (!ok) {
                    var open = [] as Array<Number>;
                    for (var oc = 0; oc < COLS; oc++) { if (!bush(prev, oc)) { open.add(oc); } }
                    cols[0] = open[rnd(open.size())];
                }
            }
            for (var i = 0; i < cols.size(); i++) { items.add([cols[i] * CW, CW, 0]); }
        } else if (kind == 4) {
            // RailRoad: a train of 1-3 carriages, very fast, round every few seconds
            speed = 960;
            items.add([-999.0, (1 + rnd(3)) * CW, 0]);
        } else if (kind == 2) {
            // Water.generateDynamic: 2-3 logs at one speed (1.2-4.2 tiles a second), each 5-8
            // tiles behind the last (here 3.3-5.3 columns), of the log models' lengths
            speed = (43 + rnd(108)) * (100 + h * 7 / 10) / 100;
            var x = rnd(PERIOD);
            var first = x;
            var n = 2 + rnd(2);
            for (var i = 0; i < n; i++) {
                var w = 52 + rnd(45) - h / 4;
                if (i > 0 && x + w > first + PERIOD - 24) { break; }     // room to wrap round
                items.add([(x % PERIOD).toFloat(), w, 0]);
                x += 120 + rnd(73) + h / 3;
            }
        } else {
            // Road.generate: 1-2 cars (wild creatures here) at one speed (1.2-4.8 tiles a second),
            // each 5-8 tiles behind the last
            speed = (43 + rnd(130)) * (100 + h * 7 / 10) / 100;
            var x = rnd(PERIOD);
            var cars = 1 + rnd(2) + (rnd(100) < h / 2 ? 1 : 0);
            for (var i = 0; i < cars; i++) {
                items.add([(x % PERIOD).toFloat(), 40, rnd(WILD)]);     // which wild creature (see things)
                x += 120 + rnd(73);
            }
        }
        // [kind, direction, speed, items, railway: when the next train comes (ms)]
        lanes.put(k, [kind, dir, speed, items, System.getTimer() + 2500 + rnd(4000)]);
        lanes.remove(k - 12);
    }

    // a rock, tree or bush in the grass (or a lily pad in the river) at column c?
    function bush(l, c) {
        if (l[0] != 0 && l[0] != 3) { return false; }    // (a pad in the river counts too)
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
                    var was = t[0];
                    t[0] += l[1] * l[2] * sec;
                    // so fast it could jump past you between two frames: anything it swept over
                    var lo = was < t[0] ? was : t[0];
                    var hi = (was > t[0] ? was : t[0]) + t[1];
                    if (k == row && px > lo + 6 && px < hi - 6) { crash(Tr.t("OUCH")); return; }
                    if (t[0] > FIELD_W + 40 || t[0] < -t[1] - 40) { t[0] = -999.0; l[4] = now + 3500 + rnd(2000) - (row > 100 ? 100 : row) * 15; }
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

    // BACK: one lane back (up to 3 behind the furthest: the lanes further back are gone), facing
    // the way it walks; a bush in the way: it stays
    function stepBack() {
        if (done || crashed || row <= 0 || row <= score - 3) { return; }
        var prev = laneAt(row - 1);
        var col = (px / CW).toNumber();
        if (col > COLS - 1) { col = COLS - 1; }
        if (col < 0) { col = 0; }
        face = 0;
        steps += 1;
        if (prev[0] == 0 && bush(prev, col)) { return; }
        row -= 1;
        lastHop = System.getTimer();
        if (prev[0] != 2) { px = (col * CW + CW / 2).toFloat(); }   // off the logs: back on the grid
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
        if (!done && mode == SPRINT) { drawSprint(dc, cx); return; }       // ... and the track
        if (!done && gym != null) {
            dc.drawBitmap(0, 0, gym);                                    // the gym
            // a plain white sign behind the title and score (the light panel's stripes showed through)
            var tw = dc.getTextWidthInPixels(Tr.t(NAMES[mode]), Graphics.FONT_XTINY);
            var sw = tw > 100 ? tw + 16 : 116;
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cx - sw / 2 - 2, 15, sw + 4, 44, 7);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cx - sw / 2, 17, sw, 40, 6);
        }
        // in the gym, PERFECT! / GOOD / MISS take the title's place on the sign for a moment
        var inSign = !done && gym != null && System.getTimer() < flashUntil;
        dc.setColor(inSign ? (flash.equals(Tr.t("MISS")) ? 0xFF0000 : 0x00AA00) : INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 18, Graphics.FONT_XTINY, inSign ? flash : Tr.t(NAMES[mode]), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        if (done) { drawResult(dc, cx); return; }
        var left = (LENGTH_MS[mode] - elapsed()) / 1000;
        dc.drawText(cx, 36, Graphics.FONT_XTINY, score + Tr.t(" pts   ") + (left < 0 ? 0 : left) + "s", Graphics.TEXT_JUSTIFY_CENTER);
        if (mode == BAG) { drawBag(dc, cx); }
        else { drawCross(dc, cx); }
        if (System.getTimer() < flashUntil && !inSign) {
            dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 56, Graphics.FONT_SMALL, flash, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawResult(dc, cx) {
        var stat = [Tr.t("STRENGTH"), Tr.t("SPEED"), Tr.t("DEFENSE")];
        var ly = 120;
        if (mode == SPRINT) {
            // the match (3 - 1, won or lost), the points, your best reaction
            dc.setColor(wins >= 3 ? 0x00AA00 : 0xFF0000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 44, Graphics.FONT_TINY, wins >= 3 ? Tr.t("YOU WIN!") : (losses >= 3 ? Tr.t("YOU LOSE") : ""), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, 66, Graphics.FONT_MEDIUM, wins + " - " + losses, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 104, Graphics.FONT_TINY, score + Tr.t(" points"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            if (bestMs >= 0) {
                dc.drawText(cx, 130, Graphics.FONT_XTINY, Tr.f("Best reaction {0}", [secs(bestMs)]), Graphics.TEXT_JUSTIFY_CENTER);
            }
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            ly = 150;
        } else {
            dc.drawText(cx, 80, Graphics.FONT_MEDIUM, score + Tr.t(" points"), Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (best >= 0) {
            // this run against the record
            dc.setColor(newBest ? 0x00AA00 : TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 120, Graphics.FONT_XTINY, newBest ? Tr.t("NEW BEST!") : Tr.f("BEST {0}", [best]), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            ly = 144;
        }
        // what it trained, or why nothing: that stat is already full, or too few points;
        // a size smaller (and trimmed) when the language needs more room
        var line = gain > 0 ? stat[mode] + " +" + Extra.fmt(gain) : (statFull() ? stat[mode] + ": " + Tr.t("Fully trained")
                   : (Extra.gamesLeft() == 0 ? Tr.t("Enough training for today") : Tr.t("No training gained")));
        var lf = Fit.font(dc, line, 200, [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]);
        dc.drawText(cx, ly, lf, Fit.trim(dc, line, 210, lf), Graphics.TEXT_JUSTIFY_CENTER);
        if (found >= 0) {
            var fruit = [Tr.t("Found an apple!"), Tr.t("Found a blue berry!"), Tr.t("Found an orange!")];
            dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, ly + 32, Graphics.FONT_XTINY, fruit[found], Graphics.TEXT_JUSTIFY_CENTER);
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

    // The punching bag on its chain from the ceiling's bracket (pivot 140, 70), swinging; the green
    // line it must cross; the partner on the mat (the room: make_gym_room.py, from the user's picture).
    function drawBag(dc, cx) {
        var ang = 0.6 * Math.sin(phase);
        var px = cx;
        var py = 70;
        var bx = px + (90 * Math.sin(ang)).toNumber();
        var by = py + (90 * Math.cos(ang)).toNumber();
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);   // the line to hit
        dc.fillRectangle(cx - 2, 148, 5, 30);
        dc.setColor(0x55FF00, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 1, 149, 3, 28);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);   // the bracket on the ceiling
        dc.fillRectangle(122, 61, 36, 8);
        dc.fillRectangle(134, 67, 12, 8);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(124, 63, 32, 4);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(124, 63, 32, 1);
        dc.fillRectangle(136, 68, 8, 5);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);   // the chain
        dc.setPenWidth(4);
        dc.drawLine(px, py, bx, by - 8);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(px, py, bx, by - 8);
        dc.setPenWidth(1);
        // the bag: dark outline, red body lit from the left, two white bands, a grey cap
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx - 14, by - 7, 28, 40, 8);
        dc.setColor(0xAA0000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx - 12, by - 5, 24, 36, 7);
        dc.setColor(0xFF5555, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx - 8, by, 4, 26);
        dc.setColor(0x550000, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx + 6, by, 3, 26);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx - 12, by + 4, 24, 3);
        dc.fillRectangle(bx - 12, by + 21, 24, 3);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx - 9, by - 12, 18, 7);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx - 7, by - 10, 14, 3);
        drawPet(dc, cx, 254);                               // on the mat
        if (streak >= 3) {
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 52, 196, Graphics.FONT_XTINY, "x" + streak, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // The track, the light over it (lit lamp: red, then yellow, then green; all dark before), your
    // runner in the top lane, the rail, the rival in the bottom lane; on a white sign below, what's
    // happening and the heats so far.
    function drawSprint(dc, cx) {
        var now = System.getTimer();
        if (sprint != null) {
            dc.setClip(0, 0, 280, 280);
            dc.drawBitmap(0, 0, sprint);
            // the light
            var lx = cx - SprintArt.LW / 2;
            var ly = 6;
            dc.setClip(lx, ly, SprintArt.LW, SprintArt.LH);
            dc.drawBitmap(lx - SprintArt.DARK_X, ly - SprintArt.LIGHT_Y, sprint);
            var on = st == S_RED || foul ? 0 : (st == S_YELLOW ? 1 : (st == S_GO || st == S_RESULT ? 2 : -1));
            if (foul && (now / 200) % 2 == 1) { on = -1; }             // a false start: the red flashes
            if (on >= 0) {
                var r = SprintArt.LAMPS[on];
                dc.setClip(lx, ly + r[0], SprintArt.LW, r[1] - r[0]);
                dc.drawBitmap(lx - SprintArt.LIT_X, ly - SprintArt.LIGHT_Y, sprint);
            }
            dc.clearClip();
        }
        var g = model.trGender == 1 ? 1 : 0;
        runner(dc, g, foul ? -1 : myMs, SprintArt.LANE1[1] - 12, now);
        if (sprint != null) {                  // the rail between the lanes
            var ry = (SprintArt.LANE1[1] + SprintArt.LANE2[0]) / 2 - SprintArt.RAIL_H / 2;
            dc.setClip(SprintArt.START_X, ry, SprintArt.RAIL_W, SprintArt.RAIL_H);
            dc.drawBitmap(SprintArt.START_X, ry - SprintArt.RAIL_Y, sprint);
            dc.clearClip();
        }
        runner(dc, 1 - g, st >= S_GO ? aiMs : -1, SprintArt.LANE2[1] - 4, now);
        // the sign: what's happening, then the heats
        var line = Tr.f("HEAT {0}", [heat + 1]);
        var col = INK;
        if (st == S_RED || st == S_YELLOW) { line = Tr.t("WAIT..."); }
        else if (st == S_GO) {
            if (foul) { line = Tr.t("FALSE START!"); col = 0xFF0000; }
            else if (myMs >= 0 && !slow) { line = secs(myMs); }
            else if (!slow) { line = Tr.t("GO!"); col = 0x00AA00; }
        }
        if (st == S_RESULT) {
            if (foul) { line = Tr.t("FALSE START!"); col = 0xFF0000; }
            else if (slow) { line = Tr.t("TOO SLOW"); col = 0xFF0000; }
            else { line = (heatWon ? Tr.t("WIN") : Tr.t("LOSE")) + "  " + secs(myMs); col = heatWon ? 0x00AA00 : 0xFF0000; }
        }
        var sw = dc.getTextWidthInPixels(line, Graphics.FONT_TINY);
        sw = sw < 110 ? 126 : sw + 16;
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - sw / 2 - 2, 196, sw + 4, 50, 7);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - sw / 2, 198, sw, 46, 6);
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 198, Graphics.FONT_TINY, line, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, Tr.t("YOU") + "  " + wins + " - " + losses + "  " + Tr.t("RIVAL"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // A runner (character g) in its lane, feet on footY: on the line until green plus its reaction
    // (react; -1: not off yet), then dashing to the finish (running frames), standing there after.
    function runner(dc, g, react, footY, now) {
        if (kids == null) { return; }
        var x0 = SprintArt.START_X + 4;
        var x1 = SprintArt.FINISH_X + 6;
        var x = x0;
        var frame = 0;
        if (react >= 0 && st >= S_GO) {
            var t = now - (greenAt + react);
            if (st == S_RESULT) { t = RUN_MS; }
            if (t > 0) {
                x = x0 + (x1 - x0) * (t < RUN_MS ? t : RUN_MS) / RUN_MS;
                if (t < RUN_MS) { frame = (t / 90) % 2; }
            }
        }
        var cell = 2 + g * 8 + 3 * 2 + frame;                  // facing right (make_trainer_art.py)
        var top = footY - 50;
        dc.setClip(x - 20, top, 40, 50);
        dc.drawBitmap(x - 20 - (cell * 48 + 4), top + 2, kids);
        dc.clearClip();
    }

    // The route (RouteArt.mc): ground strips painted once, the things on it drawn with shading,
    // your partner and the wild creatures as their thumbnails with a shadow under them.
    function drawCross(dc, cx) {
        if (!RouteArt.make()) {
            // the ground is still being painted (a strip a frame, a quarter of a second): grass
            dc.setColor(0x55AA55, 0x55AA55);
            dc.clear();
            return;
        }
        var x0 = cx - FIELD_W / 2;
        var now = System.getTimer();
        for (var s = LANES; s >= -1; s--) {              // (and one more past each edge)
            var k = row + (STAND - s);
            drawLane(dc, laneAt(k), k, x0, TOP + s * RH, now);
        }
        // the rocks, trees and bushes over the ground, further ones first (a tall tree stands in
        // front of the lane behind it); yours with them, in its row
        things(dc, x0, -1, STAND);
        // you, the trainer you chose, facing the way you last moved (flickering after a fall)
        if (kids != null && (!crashed || (now / 100) % 2 == 0)) {
            var py = TOP + STAND * RH;
            var ppx = x0 + px.toNumber();
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.fillEllipse(ppx, py + RH - 4, 10, 3);
            var cell = 2 + (model.trGender == 1 ? 8 : 0) + face * 2 + steps % 2;
            var top = py + RH - 3 - 50;                  // (up to 40 x 50 at 2x, on its cell's floor)
            dc.setClip(ppx - 20, top, 40, 50);
            dc.drawBitmap(ppx - 20 - (cell * 48 + 4), top + 2, kids);      // (kids.png: 48-row cells)
            dc.clearClip();
        }
        things(dc, x0, STAND + 1, LANES);
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

    // A log w long: its two ends (kids.png cells 33 and 35) and its middle (34) repeated between.
    function log(dc, x, y, w) {
        var base = y + 5 + 18 - 72;
        var a = w / 2 < 48 ? w / 2 : 48;
        dc.setClip(x, base, a, 72);
        dc.drawBitmap(x - 33 * 48, base + 24, kids);
        for (var m = x + a; m < x + w - a; m += 48) {
            var e = x + w - a - m < 48 ? x + w - a - m : 48;
            dc.setClip(m, base, e, 72);
            dc.drawBitmap(m - 34 * 48, base + 24, kids);
        }
        dc.setClip(x + w - a, base, a, 72);
        dc.drawBitmap(x + w - 48 - 35 * 48, base + 24, kids);
        dc.clearClip();
    }

    // The train: its engine at the front (kids.png cell 30 facing left, 31 right), a carriage
    // (cell 32) per 36 pixels behind it, each standing on the rails.
    function train(dc, x, y, w, dir) {
        if (kids == null) { return; }
        var base = y + RH - 6 - 72;                   // its wheels on the near rail
        var cars = w / 36;
        for (var i = 0; i < cars; i++) {
            var cx = x + i * 36;
            var cell = 32;
            var cw = 36;
            if (dir < 0 && i == 0) { cell = 30; cw = 42; cx -= 6; }
            else if (dir > 0 && i == cars - 1) { cell = 31; cw = 42; }
            dc.setClip(cx, base, cw, 72);
            dc.drawBitmap(cx - cell * 48, base + 24, kids);
        }
        dc.clearClip();
    }

    // The grass lanes' rocks, trees and bushes (kids.png cells 18-29, at 2x) in rows s0..s1.
    // ... and the paths' wild creatures, standing over the lane behind them: WILD of the region's
    // species baked into kids.png (make_trainer_art.py: cell 38 + 2i facing left, 39 + 2i right),
    // so nothing is loaded or made while the game runs (building their pictures mid-run, in
    // palette bitmaps cleared to transparent, crashed the fenix 6).
    function things(dc, x0, s0, s1) {
        if (kids == null) { return; }
        for (var s = s0; s <= s1; s++) {
            var k = row + (STAND - s);
            var l = laneAt(k);
            if (l[0] == 1) {
                var y = TOP + s * RH + RH - 1 - 48;
                for (var i = 0; i < l[3].size(); i++) {
                    var it = l[3][i];
                    var cell = 38 + 2 * it[2] + (l[1] > 0 ? 1 : 0);
                    for (var w = -1; w <= 1; w++) {
                        var ix = x0 + it[0].toNumber() + w * PERIOD;
                        if (ix > x0 + FIELD_W + 40 || ix + it[1] < x0 - 40) { continue; }
                        dc.setClip(ix - 4, y, 48, 48);
                        dc.drawBitmap(ix - 4 - cell * 48, y, kids);
                    }
                }
                continue;
            }
            if (l[0] != 0) { continue; }
            var base = TOP + s * RH + RH - 2 - 72;
            for (var i = 0; i < l[3].size(); i++) {
                var tx = x0 + l[3][i][0] + CW / 2;
                dc.setClip(tx - 24, base, 48, 72);
                dc.drawBitmap(tx - 24 - (18 + l[3][i][2]) * 48, base + 24, kids);
            }
        }
        dc.clearClip();
    }

    function drawLane(dc, l, k, x0, y, now) {
        var sx = x0 - (RouteArt.SW - FIELD_W) / 2;
        if (l[0] == 0) {
            dc.drawBitmap(sx, y, k % 2 == 0 ? RouteArt.grassA : RouteArt.grassB);
        } else if (l[0] == 1) {
            dc.drawBitmap(sx, y, RouteArt.path);
            for (var i = 0; i < l[3].size(); i++) {
                var it = l[3][i];
                for (var w = -1; w <= 1; w++) {
                    var ix = x0 + it[0].toNumber() + w * PERIOD;
                    if (ix > x0 + FIELD_W + 40 || ix + it[1] < x0 - 40) { continue; }
                    dc.setColor(0xAA5500, Graphics.COLOR_TRANSPARENT);
                    dc.fillEllipse(ix + 20, y + RH - 4, 14, 3);     // its shadow (itself: things)
                }
            }
        } else if (l[0] == 2 || l[0] == 3) {
            // the water flows with its logs (the same way, the same speed); its ripples repeat every 24
            var flow = (((now.toLong() * l[2].toNumber() * l[1] / 1000) % 24).toNumber() + 24) % 24;   // (a Long: no overflow)
            dc.drawBitmap(sx - 24 + flow, y, RouteArt.water);
            for (var i = 0; i < l[3].size(); i++) {
                var it = l[3][i];
                if (l[0] == 3) { RouteArt.lily(dc, x0 + it[0] + CW / 2, y, (it[0] / CW + k) % 3 == 0); continue; }
                for (var w = -1; w <= 1; w++) {
                    var ix = x0 + it[0].toNumber() + w * PERIOD;
                    if (ix > x0 + FIELD_W + 40 || ix + it[1] < x0 - 40) { continue; }
                    log(dc, ix, y, it[1]);
                }
            }
        } else {
            dc.drawBitmap(sx, y, RouteArt.rail);
            var t = l[3][0];
            RouteArt.signal(dc, x0 - 14, y, t[0] < -900 && now >= l[4] - 1500 && (now / 200) % 2 == 0);
            if (t[0] > -900) { train(dc, x0 + t[0].toNumber(), y, t[1], l[1]); }
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
        else if (v.mode == v.SPRINT) { v.sprintPress(); }
        else if (v.mode == v.BRACE) { v.hop(); }
        return true;
    }

    function onPreviousPage() {          // UP
        if (v.mode == v.BRACE) { v.sidestep(-1); }
        return true;
    }

    function onNextPage() {              // DOWN
        if (v.mode == v.BRACE) { v.sidestep(1); }
        return true;
    }

    function onBack() {                  // Route Crossing: a lane back (on the first: quit); else quit and keep what was earned
        if (!v.done && v.mode == v.BRACE && v.row > 0) { v.stepBack(); return true; }
        if (!v.done) { v.finish(); return true; }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
