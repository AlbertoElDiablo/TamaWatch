import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The home screen, after TamaPoke's: scene, name + mood, the creature (SpriteCollab sheet),
// poops, hearts, messages, decision prompts, and the dock. Page 1 is the stat card.
class PetView extends WatchUi.View {

    const IDLE = 0;
    const SLEEP = 1;
    const HURT = 4;
    const HURT_EVERY_MS = 8000;
    const BASELINE = 168;

    var model;
    var delegate = null;
    var page = 0;
    var cardPage = 0;       // stat card: 0 profile, 1 battle, 2 medals
    var frame = 0;
    var timer = null;

    // first game: TamaPoke's starter screen (UP/DOWN pick a row, START chooses)
    var starterSel = 0;
    var starterArt = null;   // [meta, sheet] per starter, only while the screen is up
    const STARTER_ACCENT = [0x00AA00, 0xFF0000, 0x00AAAA];   // TamaPoke's type accents

    // sprite state: only the current creature's sheet is kept in memory
    var dex = -1;
    var meta = null;
    var anim = -1;
    var bmp = null;
    var sheetY = 0;          // where this creature's sheet starts (shiny ones share an atlas)
    var headX = 140;         // top-centre of the creature, for hearts and Zs
    var headY = 110;
    var oldArt = null;       // [meta, bmp, y] of the form it is evolving from
    var shownShiny = false;
    var fi = 0;
    var oneShot = -1;
    var loopsLeft = 0;
    var lastHurt = 0;

    // background
    var bgBiome = -1;
    var bgSlot = -1;
    var bg = null;

    // dock
    const BTN_FOOD = 0;
    const BTN_BATH = 1;
    const BTN_PLAY = 2;
    const BTN_BOOK = 3;     // the menu (same as holding UP)
    var sel = BTN_FOOD;
    var icons = null;

    // food picker: apple, blue berry, orange (TamaPoke's green berry), candy
    var picking = false;
    var pick = 0;
    const FOOD_NAMES = ["Apple", "Blue berry", "Orange", "Candy"];

    function initialize(m) {
        View.initialize();
        model = m;
    }

    // A restarted game: the new model, and nothing kept from the old creature.
    function swapModel(nm) {
        model = nm;
        var d = delegate != null ? delegate.get() : null;    // a weak link: the delegate points here too
        if (d != null) { d.model = nm; }
        dex = -1; meta = null; bmp = null; anim = -1; oldArt = null; starterArt = null;
        bg = null; bgBiome = -1; bgSlot = -1;
        page = 0; cardPage = 0; picking = false; sel = BTN_FOOD;
        setupOpen = false; reportChecked = false;
    }

    function onShow() {
        wake();
        promptWas = null;                   // its prompt shows again straight away
        Sfx.screenOk = true;                // vibration is allowed on the main screen
        model.screenOff = true;     // replay the closed time as "screen off", then wake
        model.update();             // the first slice now, so the first frame knows if it is catching up
        timer = Ticker.take(0);                   // (a reused timer: see Ticker)
        schedule(model.trName == null ? 50 : 200);   // a new game: the welcome guide at once
    }

    function onHide() {
        Sfx.screenOk = false;
        if (timer != null) { Ticker.release(0, timer); timer = null; }   // the timer points back at this view: drop it, or neither is ever freed
        model.clearReport();          // gains seen while open were shown as they came
        reportChecked = false;
        setupOpen = false;
        model.screenOff = true;
        model.save();
    }

    function schedule(ms) {
        if (timer != null && Ticker.who[0] == timer) { Ticker.t[0].stop(); Ticker.t[0].start(method(:tick), ms, false); }
    }

    var reportChecked = false;
    var opened = false;         // the app's opening check done (the report shows only then)
    var setupOpen = false;
    var lastUpdate = -100000;
    var lastInput = 0;
    const IDLE_MS = 30000;

    function wake() { lastInput = System.getTimer(); }

    // nothing on screen that is moving: no message, hearts, bath, eating or evolving
    function toastQuiet() {
        return model.toastText() == null && !model.showHeart() && !model.bathing() && !model.eating() &&
               !model.evolving() && oneShot < 0;
    }
    var leaving = false;    // BACK on the language screen: close the app
    var catchShown = false; // "Catching up..." already on screen

    function tick() {
        frame += 1;
        if (leaving) {
            leaving = false;
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return;
        }
        // Battery: the game's minute-by-minute update and the watch's activity data are read every
        // 2 s (not every animation frame), except while replaying the closed time
        var now = System.getTimer();
        if (model.catchingUp || now - lastUpdate >= 2000) {
            lastUpdate = now;
            model.update();
        }
        if (!model.catchingUp && model.ceremony == model.CER_NONE) {
            if (model.trName == null) {
                if (!setupOpen) {
                    setupOpen = true;
                    if (!Tr.chosen()) {                 // the very first thing: the language
                        var lp = languagePanel(model, self);
                        WatchUi.pushView(lp[0], lp[1], WatchUi.SLIDE_LEFT);
                    } else {
                        var sv = new SetupView(model);
                        sv.petView = self;
                        WatchUi.pushView(sv, new SetupDelegate(sv), WatchUi.SLIDE_LEFT);
                    }
                    return;
                }
            } else if (!reportChecked) {
                reportChecked = true;
                // the welcome-back report only when the app opens; back from a battle, a game or
                // a menu, what came meanwhile (steps walked during a battle...) is not news
                var first = !opened;
                opened = true;
                if (first && model.hasReport()) {
                    var rv = new ReportView(model);
                    model.clearReport();
                    WatchUi.pushView(rv, new CloseDelegate(), WatchUi.SLIDE_IMMEDIATE);
                    return;
                }
                if (!first) { model.clearReport(); }
            }
        }
        var wait = 400;
        if (model.catchingUp) {
            wait = 60;              // keep replaying the closed time quickly
        } else if (meta != null && anim >= 0 && !model.isEgg()) {
            var d = meta[SpriteIndex.ANIMS[anim]]["d"];
            fi += 1;
            if (fi >= d.size()) {
                fi = 0;
                if (oneShot >= 0) {
                    loopsLeft -= 1;
                    if (loopsLeft <= 0) { oneShot = -1; }
                }
            }
            wait = d[fi] < 150 ? 150 : d[fi];      // at most ~7 frames a second
        }
        // Battery: left alone for 30 s, the creature stops animating and the screen redraws
        // just once every 5 s (for the clock and the bars); any button wakes it again
        if (!model.catchingUp && now - lastInput > IDLE_MS && !picking && toastQuiet()) {
            fi = 0;
            wait = 5000;
        }
        // replaying the closed time: "Catching up..." is drawn once, the time goes to the replay
        if (!model.catchingUp || !catchShown) { WatchUi.requestUpdate(); }
        catchShown = model.catchingUp;
        schedule(wait);
    }

    // ---------- sprite handling ----------

    function wantedAnim() {
        if (model.pendingAnim >= 0) {
            oneShot = model.pendingAnim;
            loopsLeft = 2;
            model.pendingAnim = -1;
        }
        if (model.sleeping) {
            oneShot = -1;
            return SLEEP;
        }
        if (oneShot < 0 && model.lowestStat() < 25) {
            var now = System.getTimer();
            if (now - lastHurt > HURT_EVERY_MS) {
                lastHurt = now;
                oneShot = HURT;
                loopsLeft = 1;
            }
        }
        return (oneShot >= 0) ? oneShot : IDLE;
    }

    // Drop the pictures home keeps (its scene, the creature's sheet, the dock icons, the badges)
    // while a screen that doesn't show them is on top (Route Crossing): they come back on their
    // own the next time home draws (syncSprite, syncBackground and the lazy loads see them gone).
    function shed() {
        dex = -1; bmp = null; meta = null; anim = -1; oldArt = null;
        bg = null; bgBiome = -1; bgSlot = -1;
        icons = null; badgeStrip = null; eggBmp = null;
    }

    function syncSprite() {
        if (model.dex != dex || model.shiny != shownShiny) {
            dex = model.dex;
            shownShiny = model.shiny;
            bmp = null;
            meta = null;
            anim = -1;
            if (dex > 0) {
                meta = WatchUi.loadResource(SpriteIndex.data(dex));
                var art = SpriteIndex.art(meta, dex, model.shiny);
                bmp = art[0];
                sheetY = art[1];
            }
        }
        if (meta == null) { return; }
        var want = wantedAnim();
        if (want != anim) {
            anim = want;
            fi = 0;
        }
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (model.trName == null) {
            // a new game: the welcome guide opens over this in a moment, so show nothing of the
            // game (no starter pick) until it has been through
            dc.setColor(0xFFFFFF, 0xFFFFFF);
            dc.clear();
            return;
        }
        syncSprite();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (model.catchingUp) {
            drawCatchingUp(dc, w, h);
        } else if (!opened && model.ceremony == model.CER_NONE) {
            // opening: a blank screen until the welcome report (if there is one) comes over it
            // without a slide, never the home screen and partner before it
        } else if (model.starterPick) {
            drawStarterSelect(dc, w, h);
        } else if (page == 0) {
            drawHome(dc, w, h);
        } else {
            drawCard(dc, w, h);
        }
    }

    function syncBackground() {
        var biome = Scenes.biomeFor(model.dex);
        var slot = Scenes.timeSlot(System.getClockTime().hour);
        if (biome != bgBiome || slot != bgSlot) {
            bg = null;
            bgBiome = biome;
            bgSlot = slot;
            bg = WatchUi.loadResource(Scenes.background(biome, slot));
        }
    }

    // Light text with a dark outline, readable over any scene.
    function outlined(dc, x, y, font, text, color) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - 1, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x + 1, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x, y - 1, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x, y + 1, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---------- screens ----------

    // After TamaPoke's renderStarterSelect(), scaled 466 -> 280: cream disc, title, and one
    // rounded row per starter tinted with its type colour, sprite on the left, name beside it.
    function drawStarterSelect(dc, w, h) {
        if (starterArt == null) {
            starterArt = [];
            for (var i = 0; i < 3; i++) {
                var n = Dex.STARTERS[i];
                starterArt.add([WatchUi.loadResource(SpriteIndex.data(n)), WatchUi.loadResource(SpriteIndex.sheet(n))]);
            }
        }
        var cx = w / 2;
        dc.setColor(UI_BG_DAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, w, h);   // the background fills the screen
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 40, Graphics.FONT_XTINY, Tr.t("Choose your starter"), Graphics.TEXT_JUSTIFY_CENTER);
        var longest = "";
        for (var i = 0; i < 3; i++) {
            var n = SpriteIndex.name(Dex.STARTERS[i]).toUpper();
            if (dc.getTextWidthInPixels(n, Graphics.FONT_XTINY) > dc.getTextWidthInPixels(longest, Graphics.FONT_XTINY)) { longest = n; }
        }
        var nameFont = biggestFont(dc, longest, 145, 40);
        for (var i = 0; i < 3; i++) {
            var ry = 66 + i * 47;
            var acc = STARTER_ACCENT[i];
            dc.setColor(mixWhite(acc), Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(42, ry, 196, 42, 8);
            dc.setColor(acc, Graphics.COLOR_TRANSPARENT);
            if (i == starterSel) {
                dc.setPenWidth(3);
                dc.drawRoundedRectangle(40, ry - 2, 200, 46, 10);
                dc.setPenWidth(1);
            } else {
                dc.drawRoundedRectangle(42, ry, 196, 42, 8);
            }
            // one shared size for the three names: the biggest where the longest still fits;
            // the sprite and its name are centred together in the row
            var nm = SpriteIndex.name(Dex.STARTERS[i]).toUpper();
            var gw = 40 + 4 + dc.getTextWidthInPixels(nm, nameFont);
            var gx = cx - gw / 2;
            drawThumb(dc, i, gx + 20, ry + 40, i == starterSel);
            dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(gx + 44, ry + (42 - dc.getFontHeight(nameFont)) / 2, nameFont, nm, Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.drawText(cx, 212, Graphics.FONT_XTINY, Tr.t("START to choose"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // The largest system font in which text fits maxW x maxH.
    function biggestFont(dc, text, maxW, maxH) {
        var fonts = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        for (var f = 0; f < fonts.size(); f++) {
            if (dc.getTextWidthInPixels(text, fonts[f]) <= maxW && dc.getFontHeight(fonts[f]) <= maxH) { return fonts[f]; }
        }
        return Graphics.FONT_XTINY;
    }

    // A starter's first idle frame standing on y (it may poke above its row, as in TamaPoke);
    // the highlighted one bobs.
    function drawThumb(dc, i, cx, footY, bob) {
        var m = starterArt[i][0];
        var a = m["idle"];
        var x = cx + a["x"];
        var y = footY - m["foot"] + a["y"] - ((bob && frame % 2 == 0) ? 2 : 0);
        dc.setClip(x, y, a["w"], a["h"]);
        dc.drawBitmap(x, y - a["r"], starterArt[i][1]);
        dc.clearClip();
    }

    // Half way from a colour to white (TamaPoke goes 3/4, which reads as plain white on the
    // watch's transflective screen).
    function mixWhite(c) {
        var r = (c >> 16) & 0xFF;
        var g = (c >> 8) & 0xFF;
        var b = c & 0xFF;
        r = r + (255 - r) / 2;
        g = g + (255 - g) / 2;
        b = b + (255 - b) / 2;
        return (r << 16) | (g << 8) | b;
    }

    function drawCatchingUp(dc, w, h) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 20, Graphics.FONT_SMALL, Tr.t("Catching up..."), Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawHome(dc, w, h) {
        var cx = w / 2;
        syncBackground();
        if (bg != null) { dc.drawBitmap(0, 0, bg); }
        if (isNight()) { drawTwinkles(dc); }
        drawStepPlate(dc);
        if (!model.isEgg()) { drawExpPlate(dc); }

        drawHeader(dc, cx);

        if (model.ceremony != model.CER_NONE) {
            drawCeremony(dc, cx);
        } else if (model.isEgg()) {
            drawEgg(dc, cx, 128);
        } else {
            drawPoops(dc);
            drawCreature(dc, cx, BASELINE);
        }
        if (model.showHeart() && !model.isEgg()) { drawHeartFloat(dc); }
        if (model.sleeping && !model.isEgg()) { drawSnore(dc); }
        if (model.bathing()) { drawBubbles(dc, cx); }

        var msg = promptShown();            // (called first: its clock waits while a message shows)
        if (model.toastText() != null) { msg = model.toastText(); }
        if (msg != null) { drawBanner(dc, cx, msg); }

        drawDock(dc, w, h);
        if (picking) { drawPicker(dc, w, h); }
    }

    // The pet's HP under its name (as wide as the name and level): a dark plate, "HP" in pixel letters and the bar
    // (green, yellow under half, red under a fifth), as in a battle. Battles take it, time,
    // food, a recorded activity and the training games give it back.
    var hpY = 46;                      // set by drawHeader: under the name
    const HP_LETTERS = [[0, 0, 2, 7], [4, 0, 2, 7], [2, 3, 2, 1],                   // H
                        [8, 0, 2, 7], [10, 0, 3, 1], [10, 3, 3, 1], [12, 1, 2, 2]];  // P
    function drawHpBar(dc, cx, w) {
        var pct = Hp.now(model);
        var x = cx - w / 2;
        var y = hpY;
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, 10, 4);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);   // its edge, readable on any scene
        dc.drawRoundedRectangle(x, y, w, 10, 4);
        dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < HP_LETTERS.size(); i++) {
            var r = HP_LETTERS[i];
            dc.fillRectangle(x + 5 + r[0], y + 2 + r[1] * 6 / 7, r[2], r[3] == 7 ? 6 : r[3]);
        }
        var bx = x + 22;
        var bw = w - 26;
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, y + 3, bw, 4);
        var fw = bw * pct / 100;
        if (fw < 1 && pct > 0) { fw = 1; }
        if (fw > 0) {
            dc.setColor(pct > 50 ? 0x00FF00 : (pct > 20 ? 0xFFFF00 : 0xFF0000), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, y + 3, fw, 4);
        }
    }

    // TamaPoke's header: the time, a battery and the menu glyph; the name and level in large
    // capitals in the species' colour; the status line under it.
    function drawHeader(dc, cx) {
        var ct = System.getClockTime();
        // as your watch shows the time: 24-hour (13:05) or 12-hour (1:05 PM)
        var clock;
        if (System.getDeviceSettings().is24Hour) {
            clock = ct.hour.format("%02d") + ":" + ct.min.format("%02d");
        } else {
            var hr = ct.hour % 12 == 0 ? 12 : ct.hour % 12;
            clock = hr + ":" + ct.min.format("%02d") + (ct.hour < 12 ? Tr.t(" AM") : Tr.t(" PM"));
        }
        outlined(dc, cx, 6, Graphics.FONT_XTINY, clock, Graphics.COLOR_WHITE);
        var title = model.isEgg() ? Tr.t("EGG") : (model.shiny ? "*" : "") + model.name().toUpper() + Tr.t(" Lv.") + model.level();
        var col = model.isEgg() ? Graphics.COLOR_WHITE : Dex.row(model.dex)[12];
        // the round screen is narrow this high up: big type only for short names, with a margin
        // either side; long ones step down a size (and further only if they must)
        var font = Fit.font(dc, title, 130, [Graphics.FONT_SMALL, Graphics.FONT_TINY]);
        if (dc.getTextWidthInPixels(title, font) > 150) { font = Graphics.FONT_XTINY; }
        var fy = 24 + (dc.getFontHeight(Graphics.FONT_SMALL) - dc.getFontHeight(font)) / 2;
        var shown = Fit.trim(dc, title, 150, font);
        outlined(dc, cx, fy, font, shown, col);
        // the pet's HP bar right under its name and level, as wide as them (an egg has none),
        // 2 px below the letters (their ascent: capitals and digits have no descent); the status
        // line follows it
        var sy = 46;
        if (!model.isEgg() && model.ceremony == model.CER_NONE) {
            var tw = dc.getTextWidthInPixels(shown, font);
            hpY = fy + dc.getFontAscent(font) + 4;
            drawHpBar(dc, cx, tw < 70 ? 70 : tw);
            sy = hpY + 10;
        }
        outlined(dc, cx, sy, Graphics.FONT_XTINY, statusLine(), Graphics.COLOR_WHITE);
    }

    function statusLine() {
        if (model.isEgg()) {
            if (model.starterPick) { return Tr.t("Choose your starter"); }
            if (model.eggNeed > 0) {
                var left = model.eggNeed - model.eggSteps;
                return Tr.t("Walk ") + (left > 0 ? left : 0) + Tr.t(" steps to hatch");
            }
            var cracks = [Tr.t("Tap the egg..."), Tr.t("It moved!"), Tr.t("Almost there!")];
            return cracks[model.eggTaps < 3 ? model.eggTaps : 2];
        }
        return model.mood();
    }

    // A decision waiting for you: opened from the menu (hold UP).
    // A prompt shows for 4 s when it comes up, and again every 12 s while it applies (and each
    // time the home screen comes back); its clock only starts once no other message is showing,
    // so one can't hide it. What it offers stays in the menu (hold UP).
    var promptWas = null;
    var promptAt = 0;
    function promptShown() {
        var p = promptText();
        if (p == null) { promptWas = null; return null; }
        var now = System.getTimer();
        if (promptWas == null || !promptWas.equals(p)) { promptWas = p; promptAt = now; }
        if (model.toastText() != null) { promptAt = now; return null; }
        return (now - promptAt) % 12000 < 4000 ? p : null;
    }

    // What the prompt on screen right now offers (a menu entry's id), or null when none shows.
    function promptOnScreen() {
        if (model.toastText() != null || promptShown() == null) { return null; }
        if (model.wantEvolveButton()) { return :evolve; }
        if (model.wantFarewellButton()) { return :farewell; }
        if (model.canRunawayNow()) { return :runaway; }
        if (model.learnOffer() != 0) { return :learn; }
        if (model.waiting != null) { return :room; }
        if (model.canAct() && Extra.rivalReady(model)) { return :rival; }
        return null;
    }

    function promptText() {
        if (model.wantEvolveButton()) { return Tr.t("Ready to evolve! Hold UP"); }
        if (model.wantFarewellButton()) { return Tr.t("Time to say goodbye. Hold UP"); }
        if (model.canRunawayNow()) { return Tr.t("It wants to leave... Hold UP"); }
        if (model.learnOffer() != 0) { return Tr.t("New move! Hold UP"); }
        if (model.waiting != null) { return Tr.t("Party full: make room. Hold UP"); }
        if (model.canAct() && Extra.rivalReady(model)) { return Tr.f("{0} wants to battle! Hold UP", [RIVAL_NAME]); }
        return null;
    }

    // A message in a white pill; too wide for the round screen, it wraps onto two lines.
    const BANNER_Y = 84;                // under the status line (which the HP bar moved down)
    function drawBanner(dc, cx, text) {
        var maxW = 200;
        var lines = [text];
        if (dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) > maxW) {
            var words = Wire.split(text, " ");
            var a = "";
            var i = 0;
            while (i < words.size() && dc.getTextWidthInPixels(a + (a.length() > 0 ? " " : "") + words[i], Graphics.FONT_XTINY) <= maxW) {
                a = a + (a.length() > 0 ? " " : "") + words[i];
                i++;
            }
            var b = "";
            for (var k = i; k < words.size(); k++) { b = b + (b.length() > 0 ? " " : "") + words[k]; }
            lines = [a, Fit.trim(dc, b, maxW, Graphics.FONT_XTINY)];
        }
        var tw = 0;
        for (var k = 0; k < lines.size(); k++) {
            var lw = dc.getTextWidthInPixels(lines[k], Graphics.FONT_XTINY);
            if (lw > tw) { tw = lw; }
        }
        tw += 16;
        var bh = 6 + 15 * lines.size();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - tw / 2, BANNER_Y, tw, bh, 8);
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(cx - tw / 2, BANNER_Y, tw, bh, 8);
        for (var k = 0; k < lines.size(); k++) {
            dc.drawText(cx, BANNER_Y + k * 15, Graphics.FONT_XTINY, lines[k], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ---------- stat card (MENU > Stats; UP/DOWN pages, BACK closes) ----------

    function drawCard(dc, w, h) {
        var cx = w / 2;
        var titles = [Tr.t("PROFILE"), Tr.t("BATTLE"), Tr.t("MEDALS"), Tr.t("PROGRESS"), Tr.t("TRAINER")];
        dc.setColor(UI_BG_DAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, w, h);   // the background fills the screen
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 24, Graphics.FONT_XTINY, titles[cardPage] + "  " + (cardPage + 1) + "/5", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 42, Graphics.FONT_SMALL, model.name() + (model.shiny ? " *" : ""), Graphics.TEXT_JUSTIFY_CENTER);
        var lines = [];
        if (cardPage == 4) { drawBadgeCase(dc, cx); return; }
        if (model.isEgg()) {
            var tiers = ["", Tr.t("Common egg"), Tr.t("Rare egg"), Tr.t("Legendary egg")];
            lines = [tiers[model.eggRarity()], Tr.t("Pokedex ") + model.registeredCount() + "/" + Dex.COUNT,
                     model.eggNeed > 0 ? Tr.t("Steps ") + model.eggSteps + "/" + model.eggNeed : Tr.t("Tap to hatch"),
                     Tr.t("Active weeks ") + model.streak + Tr.t(" (best ") + model.bestStreak + ")"];
        } else if (cardPage == 0) {
            var age = model.ageMinutes;
            lines = [Tr.t("Lv ") + model.level() + Tr.t("   age ") + age / 1440 + "d " + (age % 1440) / 60 + "h",
                     Tr.t("Bond ") + model.bond + Tr.t("   weight ") + model.weight,
                     Tr.t("Active weeks ") + model.streak + Tr.t(" (best ") + model.bestStreak + ")",
                     Tr.t("EXP ") + model.exp + Tr.t("   week ") + model.weekPct() + "%",
                     Tr.t("Slip-ups ") + model.careMistakes,
                     Tr.t("Fav. fruit: ") + (model.berryKnown ? Tr.t(FOOD_NAMES[model.dex % 3]) : "?"),
                     Tr.t("Pokedex ") + model.registeredCount() + "/" + Dex.COUNT];
        } else if (cardPage == 1) {
            lines = [Tr.t("ATK ") + model.atkStat() + Tr.t("  (IV ") + model.ivAtk + Tr.t(", tr ") + model.trAtk + ")",
                     Tr.t("DEF ") + model.defStat() + Tr.t("  (IV ") + model.ivDef + Tr.t(", tr ") + model.trDef + ")",
                     Tr.t("SPD ") + model.speStat() + Tr.t("  (IV ") + model.ivSpe + Tr.t(", tr ") + model.trSpe + ")",
                     Tr.t("VIT ") + model.vitStat() + Tr.t("  (IV ") + model.ivHp + ")",
                     Tr.t("Training cap ATK ") + model.trMaxFor(model.ivAtk) + Tr.t(" DEF ") + model.trMaxFor(model.ivDef)];
        } else if (cardPage == 2) {
            for (var i = 0; i < 8; i++) {
                lines.add((model.hasMedal(1 << i) ? "[x] " : "[ ] ") + Tr.t(model.MEDAL_NAMES[i]));
            }
        } else {
            lines = [Tr.t("Pokedex ") + model.registeredCount() + "/" + Dex.COUNT,
                     Tr.t("Badges ") + model.badgeCount(false) + Tr.t("/8   hard ") + model.badgeCount(true) + "/8",
                     Tr.t("Best active streak ") + model.bestStreak + Tr.t(" wk"),
                     Tr.t("Medals earned ") + model.totalMedals,
                     Tr.t("Party ") + model.party.size() + Tr.t("/6   Pokébox ") + model.box.size()];
        }
        var y = 74;
        var step = lines.size() > 6 ? 19 : 24;
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, y + i * step, Graphics.FONT_XTINY, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // The badge case: earned ones shine (a gold ring for hard), the rest are outlines.
    var badgeStrip = null;

    // TamaPoke's player card: the badge case (yellow rings round the earned ones, a double ring on
    // hard), then STREAK, POKEDEX and PARTY.
    function drawBadgeCase(dc, cx) {
        if (badgeStrip == null) { badgeStrip = WatchUi.loadResource(Rez.Drawables.badges); }
        for (var i = 0; i < 8; i++) {
            var bx = cx - 78 + (i % 4) * 52;
            var by = 98 + (i / 4) * 54;
            var easy = model.hasBadge(i, false);
            var hard = model.hasBadge(i, true);
            if (easy || hard) {
                dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(hard ? 4 : 2);
                dc.drawCircle(bx, by, 24);
                dc.setPenWidth(1);
                dc.setClip(bx - 24, by - 24, 48, 48);
                dc.drawBitmap(bx - 24 - 48 * i, by - 24, badgeStrip);
                dc.clearClip();
            } else {
                dc.setColor(UI_TRACK, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(bx, by, 16);
            }
        }
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        var lines = [Tr.t("ACTIVE WEEKS ") + model.streak + Tr.t("  best ") + model.bestStreak,
                     Tr.t("POKEDEX ") + model.registeredCount() + "/" + Dex.COUNT,
                     Tr.t("PARTY ") + model.party.size() + "/6"];
        for (var k = 0; k < lines.size(); k++) {
            dc.drawText(cx, 172 + k * 18, Graphics.FONT_XTINY, lines[k], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ---------- drawing pieces ----------

    // TamaPoke's egg (SPR_EGG at 3x) with its cracks: CRACK1 after the first tap, CRACK2 after
    // the second, drawn as ink pixels on the map's 32x32 grid.
    const CRACK1 = [[15, 8], [16, 9], [15, 10]];
    const CRACK2 = [[11, 13], [12, 14], [11, 15], [20, 12], [19, 13], [20, 14]];
    var eggBmp = null;

    function drawEgg(dc, cx, cy) {
        if (eggBmp == null) { eggBmp = WatchUi.loadResource(Rez.Drawables.egg); }
        var s = 3;
        var x = cx - 16 * s;
        var y = cy - 16 * s;
        dc.setClip(x, y, 96, 96);               // (the small egg sits beside it in the picture)
        dc.drawBitmap(x, y, eggBmp);
        dc.clearClip();
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        if (model.eggTaps >= 1) {
            for (var i = 0; i < CRACK1.size(); i++) { dc.fillRectangle(x + CRACK1[i][0] * s, y + CRACK1[i][1] * s, s, s); }
        }
        if (model.eggTaps >= 2) {
            for (var i = 0; i < CRACK2.size(); i++) { dc.fillRectangle(x + CRACK2[i][0] * s, y + CRACK2[i][1] * s, s, s); }
        }
    }

    // Draws the current sprite frame standing on the baseline; flickers while evolving.
    function drawCreature(dc, cx, baseline) {
        if (meta == null || bmp == null) { return; }
        var a = meta[SpriteIndex.ANIMS[anim]];
        var w = a["w"];
        var x = cx + a["x"];
        var y = baseline - meta["foot"] + a["y"];
        var iw = meta["idle"]["w"];
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(cx, baseline, iw / 3, 4);

        headX = cx;
        headY = y + 6;
        if (model.evolving() && showOldForm()) {
            drawOldForm(dc, cx, baseline);
        } else {
            var h = a["h"];
            var cols = a["c"];
            dc.setClip(x, y, w, h);
            dc.drawBitmap(x - (fi % cols) * w, y - a["r"] - (fi / cols) * h - sheetY, bmp);
            dc.clearClip();
        }
        if (model.eating()) {
            drawFoodIcon(dc, x + w - 4, baseline - 26, model.eatItem);
        }
    }

    // TamaPoke's evolution: the two forms flicker, faster and faster, and the new one stays.
    function showOldForm() {
        if (model.prevDex == 0) { return false; }
        if (oldArt == null) {
            var m = WatchUi.loadResource(SpriteIndex.data(model.prevDex));
            var a = SpriteIndex.art(m, model.prevDex, model.shiny);
            oldArt = [m, a[0], a[1]];
        }
        var left = model.evolveUntil - System.getTimer();
        if (left < 600) { return false; }                       // the end: the new form
        var t = 1.0 - left / 5200.0;
        var period = (420 - 360 * t).toNumber();                 // flicker speeds up
        return ((System.getTimer() / period) % 2) == 0;
    }

    function drawOldForm(dc, cx, baseline) {
        var m = oldArt[0];
        var a = m["idle"];
        var x = cx + a["x"];
        var y = baseline - m["foot"] + a["y"];
        dc.setClip(x, y, a["w"], a["h"]);
        dc.drawBitmap(x, y - a["r"] - oldArt[2], oldArt[1]);
        dc.clearClip();
    }

    // TamaPoke's drawHeartFloat: one heart rises from the head, swaying and swelling.
    function drawHeartFloat(dc) {
        var left = model.heartUntil - System.getTimer();
        if (left <= 0) { oldArt = null; return; }
        var p = 1.0 - left / 1500.0;
        if (p < 0) { p = 0.0; }
        var x = headX + 6 + (Math.sin(p * 6) * 4).toNumber();
        var y = headY - (p * 40).toNumber();
        drawHeartSized(dc, x, y, 3 + (p * 2).toNumber());
    }

    function drawHeartSized(dc, x, y, r) {
        dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - r, y, r + 1);
        dc.fillCircle(x + r, y, r + 1);
        dc.fillPolygon([[x - 2 * r - 1, y + r / 3], [x + 2 * r + 1, y + r / 3], [x, y + 3 * r + 1]]);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - r - r / 3, y - r / 3, 1);
    }

    // TamaPoke's drawSnore: three Zs drift up and away from the head, growing.
    function drawSnore(dc) {
        var now = System.getTimer();
        var fonts = [Graphics.FONT_XTINY, Graphics.FONT_TINY, Graphics.FONT_SMALL];
        for (var i = 0; i < 3; i++) {
            var p = ((now + i * 900) % 2700) / 2700.0;
            if (p > 0.92) { continue; }
            var x = headX + (p * 34).toNumber() + (Math.sin(p * 9.0 + i) * 3).toNumber();
            var y = headY - 14 - (p * 47).toNumber();
            outlined(dc, x, y, fonts[p < 0.34 ? 0 : (p < 0.67 ? 1 : 2)], "Z", Graphics.COLOR_WHITE);
        }
    }

    // Night sky: a few stars twinkle, each on its own beat.
    const STARS = [[46, 72], [92, 40], [188, 36], [236, 78], [70, 102], [214, 108], [150, 22]];

    function drawTwinkles(dc) {
        var now = System.getTimer();
        for (var i = 0; i < STARS.size(); i++) {
            var phase = (now / (500 + i * 130) + i) % 4;
            if (phase == 0) {
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(STARS[i][0] - 3, STARS[i][1], STARS[i][0] + 4, STARS[i][1]);
                dc.drawLine(STARS[i][0], STARS[i][1] - 3, STARS[i][0], STARS[i][1] + 4);
            } else if (phase == 1) {
                dc.setColor(0x5555FF, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(STARS[i][0], STARS[i][1], 1);
            }
        }
    }

    // TamaPoke's step plate: a band on the left rim, the progress arc toward 10,000 (gold at the
    // goal), two footprints and today's count.
    function drawStepPlate(dc) {
        var info = ActivityMonitor.getInfo();
        var steps = (info != null && info.steps != null) ? info.steps : 0;
        var goal = model.stepGoal();                         // your own step goal
        var capped = steps > goal ? goal : steps;
        drawPlate(dc, false, capped.toFloat() / goal);
        var ink = isNight() ? UI_INK_NIGHT : UI_INK;
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(24 + TEXT_IN, 112, 4, 2);       // the footprints
        dc.fillEllipse(30 + TEXT_IN, 105, 4, 2);
        var txt = steps > 99999 ? "99k+" : steps.toString();
        dc.drawText(30 + TEXT_IN, 74, Graphics.FONT_XTINY, txt, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // The EXP plate: the steps plate's exact mirror on the right. The arc fills bottom to top with
    // how far it is into this level; the number is that in percent.
    function drawExpPlate(dc) {
        var pr = model.expProgress();
        drawPlate(dc, true, pr[1] > 0 ? pr[0].toFloat() / pr[1] : 1.0);
        dc.setColor(isNight() ? UI_INK_NIGHT : UI_INK, Graphics.COLOR_TRANSPARENT);
        var pct = pr[1] > 0 ? pr[0] * 100 / pr[1] : 100;
        dc.drawText(250 - TEXT_IN - EXP_SHIFT, 74, Graphics.FONT_XTINY, pct + "%", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(250 - TEXT_IN - EXP_SHIFT, 98, Graphics.FONT_XTINY, Tr.t("EXP"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // A side plate: a band of the ring around the screen (radius 104-140, from 140 to 172 degrees
    // on the left; mirrored on the right), its grey track and the green fill rising from the
    // bottom. Drawn as polygons worked out here, not with drawArc: the watch draws a thick arc's
    // two ends differently, so the right plate (whose inner end is where its arc finishes) came out
    // narrower and further from the pet than the left. Polygons come out the same everywhere.
    const PLATE_IN = 4;     // both plates sit this far in from the screen's edge (was 9: the
                            // side bars now run 5 px closer to the edge)
    const TEXT_IN = 7;      // the numbers and labels: 2 px out with the plate, clear of its edge
    // The EXP plate is the steps plate's exact mirror: same size, same distance from the centre.
    // (It was moved 17 px left to make up for the photos' parallax; the user wants the mirror.)
    const EXP_SHIFT = 0;
    function drawPlate(dc, right, frac) {
        if (frac > 1.0) { frac = 1.0; }
        // the plate runs out past the screen's edge (the screen clips it), so it reaches the border
        // on both sides whatever the shift; the track, fill and text stay where they were
        dc.setColor(isNight() ? 0x000055 : 0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        ring(dc, right, 104, 180, 140, 172);
        dc.setColor(UI_TRACK, Graphics.COLOR_TRANSPARENT);
        ring(dc, right, 134, 139, 143, 169);
        var a = 169 - 26 * frac;
        if (a < 168.5) {
            dc.setColor(barGreen(), Graphics.COLOR_TRANSPARENT);   // the FOOD bar's green
            ring(dc, right, 134, 139, a, 169);
        }
    }

    // The band between radii r0 and r1 from angle a0 to a1 (degrees, counter-clockwise from 3
    // o'clock, left-side geometry about (140 + PLATE_IN, 140)); mirrored left-right when right.
    function ring(dc, right, r0, r1, a0, a1) {
        var ox = 140 + PLATE_IN;
        var n = ((a1 - a0) / 2).toNumber() + 1;
        if (n < 2) { n = 2; }
        var pts = [];
        for (var k = 0; k <= n; k++) {
            var t = Math.toRadians(a0 + (a1 - a0) * k / n);
            pts.add(pt(ox + r1 * Math.cos(t), 140 - r1 * Math.sin(t), right));
        }
        for (var k = n; k >= 0; k--) {
            var t = Math.toRadians(a0 + (a1 - a0) * k / n);
            pts.add(pt(ox + r0 * Math.cos(t), 140 - r0 * Math.sin(t), right));
        }
        dc.fillPolygon(pts);
    }

    function pt(x, y, right) {
        return [(right ? 280 - x - EXP_SHIFT : x).toNumber(), y.toNumber()];
    }

    // Up to three poops on the ground, lower left (kept clear of the creature).
    function drawPoops(dc) {
        for (var i = 0; i < model.poops; i++) {
            var px = 58 + i * 20;
            var py = BASELINE - 2 + (i % 2) * 4;
            dc.setColor(0xAA5500, Graphics.COLOR_TRANSPARENT);
            dc.fillEllipse(px, py, 8, 4);
            dc.fillEllipse(px, py - 4, 6, 3);
            dc.fillEllipse(px, py - 7, 3, 2);
            dc.setColor(0xAAAA00, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(px - 2, py - 5, 1);
        }
    }

    // The bath: bubbles rise around the creature.
    function drawBubbles(dc, cx) {
        for (var k = 0; k < 7; k++) {
            var x = cx - 36 + (k * 37) % 72;
            var y = BASELINE - ((frame * 6 + k * 23) % 90);
            dc.setColor(0x55FFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 3 + k % 3);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - 1, y - 1, 1);
        }
    }

    function drawHeart(dc, x, y) {
        dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 4, y, 5);
        dc.fillCircle(x + 4, y, 5);
        dc.fillPolygon([[x - 9, y + 1], [x + 9, y + 1], [x, y + 11]]);
    }

    // The goodbye: hearts rise for a farewell or release; a runaway just walks off.
    function drawCeremony(dc, cx) {
        var t = 1.0 - (model.ceremonyUntil - System.getTimer()) / 10000.0;
        if (t < 0) { t = 0.0; }
        var text = Tr.t("Goodbye, ") + model.name() + "!";
        if (model.ceremony == model.CER_RUNAWAY) {
            text = model.name() + Tr.t(" ran away...");
            drawCreature(dc, cx + (t * 160).toNumber(), BASELINE);
        } else {
            drawCreature(dc, cx, BASELINE);
            for (var k = 0; k < 3; k++) {
                var p = ((t * 3 + k / 3.0) * 100).toNumber() % 100;
                drawHeart(dc, cx - 30 + k * 30, BASELINE - 40 - p);
            }
        }
        drawBanner(dc, cx, text);
    }

    // Icons live in one strip (0 apple, 1 moon (unused), 2 drop, 3 football; food: 4 blue, 5 orange,
    // 6 candy; 7 open book). The dock: apple, drop, dumbbell, book.
    const DOCK_ICON = [0, 2, 3, 7];
    const FOOD_ICON = [0, 4, 5, 6];

    function drawIcon(dc, idx, x, y) {
        // (the icons are rows 48-79 of the badges' picture: tools/merge_dock_icons.py)
        if (badgeStrip == null) { badgeStrip = WatchUi.loadResource(Rez.Drawables.badges); }
        dc.setClip(x, y, 32, 32);
        dc.drawBitmap(x - 32 * idx, y - 48, badgeStrip);
        dc.clearClip();
    }

    function drawFoodIcon(dc, x, y, item) {
        drawIcon(dc, FOOD_ICON[item], x, y);
    }

    // ---------- food picker ----------

    function drawPicker(dc, w, h) {
        var cx = w / 2;
        dc.setColor(UI_BG_DAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(30, 88, w - 60, 96, 12);
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(30, 88, w - 60, 96, 12);
        for (var i = 0; i < 4; i++) {
            var bx = cx - 94 + i * 48;            // each fruit's 40 px box, centred as a row
            if (i == pick) {
                dc.setColor(ACCENT[0], Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                dc.drawRoundedRectangle(bx, 94, 40, 40, 8);
                dc.setPenWidth(1);
            }
            drawIcon(dc, FOOD_ICON[i], bx + 4, 98);   // the 32 px icon in the middle of its box
            // how many are in the bag: under the box, not in it
            var n = model.bag[i];
            dc.setColor(n > 0 ? UI_INK : 0xFF0000, Graphics.COLOR_TRANSPARENT);
            dc.drawText(bx + 20, capY(Graphics.FONT_XTINY, 145), Graphics.FONT_XTINY, n.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, capY(Graphics.FONT_XTINY, 167), Graphics.FONT_XTINY, Tr.t(FOOD_NAMES[pick]), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---------- dock (after TamaPoke's drawBars / drawButtons, scaled 466 -> 280) ----------

    const UI_BG_DAY = 0xFFFFFF;
    const UI_BG_NIGHT = 0x000000;
    const UI_INK = 0x000055;
    const UI_INK_NIGHT = 0xFFFFFF;
    const UI_TRACK = 0xAAAAAA;
    const UI_BAR_OK = 0x55FF55;
    const UI_BAR_WARN = 0xFFAA00;
    const UI_BAR_BAD = 0xFF0000;

    const DOCK_TOP = 176;
    const BTN_HALF = 18;
    // on a curve along the bottom edge, mirrored about the centre line like the name and the pet
    // (x = centre + BTN_DX); every corner (with its shadow) stays 4+ px inside the circle
    const BTN_DX = [-58, -19, 19, 58];
    var BTN_CX = [82, 121, 159, 198];
    const BTN_CY = [229, 240, 240, 229];
    const TINT = [0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF];
    const ACCENT = [0xFF0000, 0x00AAFF, 0x00AAAA, 0xFF5500];

    function isNight() {
        return Scenes.timeSlot(System.getClockTime().hour) == 3;
    }

    // The bars' green (FOOD, EXP, steps): brighter on the dark night panel.
    function barGreen() { return isNight() ? 0x00FF00 : 0x00AA00; }

    function ink() {
        return isNight() ? UI_INK_NIGHT : UI_INK;
    }

    // Asleep, only the book (menu) works. It sleeps when you do and recharges to your Body Battery.
    function buttonDisabled(i) {
        return model.sleeping && i != BTN_BOOK;
    }

    function moveSelection(step) {
        for (var k = 0; k < 4; k++) {
            sel = (sel + step + 4) % 4;
            if (!buttonDisabled(sel)) { return; }
        }
    }

    function drawDock(dc, w, h) {
        var night = isNight();
        dc.setColor(night ? UI_BG_NIGHT : UI_BG_DAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, DOCK_TOP, w, h - DOCK_TOP);

        if (model.isEgg()) {
            dc.setColor(ink(), Graphics.COLOR_TRANSPARENT);
            // TamaPoke's egg panel: the rarity when it is rare, the Pokedex tally, and the region pill
            // all of it well inside the round bottom: rarity, the Pokedex tally, the region pill
            var tiers = ["", "", Tr.t("RARE EGG!"), Tr.t("LEGENDARY EGG!")];
            var t = model.starterPick ? "" : tiers[model.eggRarity()];
            if (t.length() > 0) {
                dc.setColor(model.eggRarity() == 3 ? UI_BAR_WARN : 0x00AAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, capY(Graphics.FONT_XTINY, DOCK_TOP + 10), Graphics.FONT_XTINY, t, Graphics.TEXT_JUSTIFY_CENTER);
            }
            dc.setColor(ink(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, capY(Graphics.FONT_SMALL, DOCK_TOP + 28), Graphics.FONT_SMALL, Tr.t("POKEDEX ") + model.registeredCount() + "/" + Dex.COUNT, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            var pill = Region.t("KANTO EGG");                  // as wide as its words, in any language
            var pw = dc.getTextWidthInPixels(pill, Graphics.FONT_XTINY) + 24;
            if (pw > 170) { pw = 170; }
            dc.fillRoundedRectangle(w / 2 - pw / 2, DOCK_TOP + 44, pw, 22, 7);
            dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(w / 2 - pw / 2, DOCK_TOP + 44, pw, 22, 7);
            centerText(dc, w / 2 - pw / 2, DOCK_TOP + 44, pw, 22, Graphics.FONT_XTINY, pill);
            return;
        }

        // two columns of bars, each 98 px (label + bar), 10 px apart, centred on the screen
        var cx = w / 2;
        for (var i = 0; i < 4; i++) { BTN_CX[i] = cx + BTN_DX[i]; }
        var lx = cx - 103;
        var rx = cx + 5;
        drawBar(dc, lx, 179, Tr.t("FOOD"), model.food);
        drawBar(dc, rx, 179, Tr.t("JOY"), model.joy);
        drawBar(dc, lx, 194, Tr.t("ENE"), model.energy);
        drawBar(dc, rx, 194, Tr.t("HYG"), model.hygiene);

        if (buttonDisabled(sel)) { sel = BTN_BOOK; }
        for (var i = 0; i < 4; i++) {
            drawButton(dc, i, night);
        }
    }

    // Bars that read on the transflective screen: a dark track at night (light by day), a solid
    // fill that only leaves a 1 px rim, and an ink outline.
    function drawBar(dc, x, y, label, value) {
        var night = isNight();
        dc.setColor(ink(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y - 4, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        var bx = x + 42;
        var bw = 56;
        var bh = 11;
        var fill = barGreen();
        if (value < 25) { fill = 0xFF0000; }
        else if (value < 50) { fill = night ? 0xFFFF00 : 0xFFAA00; }
        dc.setColor(night ? 0x555555 : 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, y, bw, bh);
        var fw = ((bw - 2) * value / 100.0).toNumber();
        if (fw > 0) {
            dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx + 1, y + 1, fw, bh - 2);
        }
        dc.setColor(night ? 0xFFFFFF : 0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(bx, y, bw, bh);
    }

    function drawButton(dc, i, night) {
        var off = buttonDisabled(i);
        var lift = (i == sel) ? 3 : 0;
        var bs = 2 * BTN_HALF;
        var bx = BTN_CX[i] - BTN_HALF;
        var by = BTN_CY[i] - BTN_HALF - lift;
        if (!model.sleeping) {
            dc.setColor(night ? 0x000000 : 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx + 1, by + 3 + lift, bs, bs, 8);
            dc.setColor(TINT[i], Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, by, bs, bs, 8);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx + 3, by + 2, bs - 6, bs / 2 - 3, 6);
            dc.setColor(ACCENT[i], Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(bx + 1, by + 1, bs - 2, bs - 2, 7);
        }
        if (i == sel) {
            dc.setColor(ACCENT[i], Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawRoundedRectangle(bx - 2, by - 2, bs + 4, bs + 4, 10);
            dc.setPenWidth(1);
        }
        dc.setColor(ink(), Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(bx, by, bs, bs, 8);
        if (!off) {
            drawIcon(dc, DOCK_ICON[i], BTN_CX[i] - 16, BTN_CY[i] - 16 - lift);
        }
    }
}
