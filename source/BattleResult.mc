import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// After a battle (won or lost), straight from it: VICTORY! or DEFEAT, who it was against, your
// creature and the rival each in a frame like the summary page's (with the HP they ended on), a
// VS between them, a row of dots for each team when more than one fought (crossed out: fainted),
// then what the battle meant: EXP and a new level, HP left and any food it cost, the turns, and
// for a gym its badge, training and candy. START goes back (to the home screen, or the lobby).
class BattleResultView extends WatchUi.View {
    var b;              // the BattleView it replaced (its creatures, art and results)
    var mine;           // [fainted?] per member of your side
    var theirs;         // ... and of theirs

    const INK = 0x000055;
    const FRAME = 0xAAAAFF;
    const FW = 90;
    const FH = 84;
    const FY = 70;

    var lead;             // who stands in the left frame: your partner when it fought (its EXP, level
    var leadArt;          // and HP are the lines below), else the last one of yours on the field

    function initialize(battle, myTeam, theirTeam) {
        View.initialize();
        b = battle;
        mine = myTeam;
        theirs = theirTeam;
        lead = b.petC != null ? b.petC : b.you;
    }

    function onShow() {
        if (lead == b.you) { leadArt = b.art[0]; return; }
        b.art[0] = null;                // the one on the field: its sheet is not needed any more
        var meta = WatchUi.loadResource(SpriteIndex.data(b.model.dex));
        var a = SpriteIndex.art(meta, b.model.dex, b.model.shiny);
        leadArt = [meta, a[0], a[1]];
    }

    function onUpdate(dc) {
        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var w = dc.getWidth();
        var cx = w / 2;
        dc.setColor(0xFFFFFF, 0xFFFFFF);
        dc.clear();

        // VICTORY! / DEFEAT and who it was against
        var title = b.won ? Tr.t("VICTORY!") : Tr.t("DEFEAT");
        var tf = Fit.font(dc, title, 170, [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY]);
        dc.setColor(b.won ? 0x00AA00 : 0xFF0000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, capY(tf, 36), tf, title, Graphics.TEXT_JUSTIFY_CENTER);
        var who = b.lobby != null ? b.peerName : (b.trainer >= 0 ? b.trainerRow()[0] : Tr.t("Wild"));
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, capY(Graphics.FONT_XTINY, 59), Graphics.FONT_XTINY, Fit.trim(dc, Tr.t("vs ") + who, 190, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_CENTER);

        // the two frames and VS
        var lx = cx - 12 - FW;
        var rx = cx + 12;
        frame(dc, lx, lead, leadArt);
        frame(dc, rx, b.foe, b.art[1]);
        dc.setColor(0xFF5500, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, capY(Graphics.FONT_SMALL, FY + FH / 2), Graphics.FONT_SMALL, Tr.t("VS"), Graphics.TEXT_JUSTIFY_CENTER);

        // names under them, then the team dots when a side had more than one
        var ny = FY + FH + 10;
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx + FW / 2, capY(Graphics.FONT_XTINY, ny), Graphics.FONT_XTINY, Fit.trim(dc, lead.name, FW + 20, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rx + FW / 2, capY(Graphics.FONT_XTINY, ny), Graphics.FONT_XTINY, Fit.trim(dc, b.foe.name, FW + 20, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_CENTER);
        var y = ny + 12;
        if (mine.size() > 1 || theirs.size() > 1) {
            dots(dc, lx + FW / 2, y + 4, mine);
            dots(dc, rx + FW / 2, y + 4, theirs);
            y += 12;
        }

        // what it meant, a line or two of pairs
        var items = [];
        if (b.expGained > 0) { items.add([Tr.t("EXP") + " +" + b.expGained, 0x00AA00]); }
        if (b.levelUp) { items.add([Tr.t("Lv.") + b.model.level() + "!", 0x00AA00]); }
        if (b.petC != null) {
            var pct = b.petC.hp * 100 / (b.petC.maxHp > 0 ? b.petC.maxHp : 1);
            items.add([Tr.t("HP") + " " + pct + "%", pct > 50 ? INK : (pct > 20 ? 0xFF5500 : 0xFF0000)]);
        }
        if (b.foodLost > 0) { items.add([Tr.t("FOOD") + " -" + b.foodLost, 0xFF0000]); }
        if (b.won && b.trainer >= 0) {
            if (b.newBadge) { items.add([Tr.t("NEW BADGE!") + " " + b.model.badgeCount(b.hard) + "/8", 0xFF5500]); }
            if (b.trainGain > 0) {
                var statNames = [Tr.t("STRENGTH"), Tr.t("DEFENSE"), Tr.t("SPEED")];
                items.add([statNames[b.model.lastTrained] + " +" + b.trainGain, 0x00AA00]);
            }
            items.add([Tr.t("Candy") + " +1", 0x00AA00]);
        }
        items.add([b.turn == 1 ? Tr.t("1 turn") : Tr.f("{0} turns", [b.turn]), TEXT_GREY]);
        var f = Graphics.FONT_XTINY;
        var i = 0;
        while (i < items.size() && y < 236) {
            // two to a line when they fit the circle at this height
            var room = Fit.span(y, 17, 220)[1] - 16;
            var one = items[i][0];
            var two = i + 1 < items.size() ? items[i + 1][0] : null;
            var gap = 14;
            if (two != null && dc.getTextWidthInPixels(one, f) + gap + dc.getTextWidthInPixels(two, f) <= room) {
                var w1 = dc.getTextWidthInPixels(one, f);
                var w2 = dc.getTextWidthInPixels(two, f);
                var x0 = cx - (w1 + gap + w2) / 2;
                dc.setColor(items[i][1], Graphics.COLOR_TRANSPARENT);
                dc.drawText(x0, capY(f, y + 8), f, one, Graphics.TEXT_JUSTIFY_LEFT);
                dc.setColor(items[i + 1][1], Graphics.COLOR_TRANSPARENT);
                dc.drawText(x0 + w1 + gap, capY(f, y + 8), f, two, Graphics.TEXT_JUSTIFY_LEFT);
                i += 2;
            } else {
                dc.setColor(items[i][1], Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, capY(f, y + 8), f, Fit.trim(dc, one, room, f), Graphics.TEXT_JUSTIFY_CENTER);
                i += 1;
            }
            y += 17;
        }
    }

    // A creature in its frame (as on the summary page) with the HP it ended on along the bottom;
    // one from another region (no art here) as an orb in its type's colours.
    function frame(dc, x, c, art) {
        dc.setColor(FRAME, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, FY, FW, FH, 8);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x + 4, FY + 4, FW - 8, FH - 8, 6);
        var foot = FY + FH - 16;
        if (art != null) {
            var meta = art[0];
            var a = meta["idle"];
            var sx = x + FW / 2 - (meta["ic"] != null ? meta["ic"] : a["w"] / 2);
            var sy = foot - meta["foot"] + a["y"];
            // inside the frame only (a big creature is cut at its edges)
            var cl = sx > x + 4 ? sx : x + 4;
            var ct = sy > FY + 4 ? sy : FY + 4;
            var cr = sx + a["w"] < x + FW - 4 ? sx + a["w"] : x + FW - 4;
            var cb = sy + a["h"] < FY + FH - 12 ? sy + a["h"] : FY + FH - 12;
            if (cr > cl && cb > ct) {
                dc.setClip(cl, ct, cr - cl, cb - ct);
                dc.drawBitmap(sx, sy - a["r"] - art[2], art[1]);
                dc.clearClip();
            }
        } else {
            var r = 22;
            var cy = foot - r;
            dc.setColor(Moves.typeColor(c.t1), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + FW / 2, cy, r);
            if (c.t2 >= 0) {
                dc.setColor(Moves.typeColor(c.t2), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x + FW / 2 - r + 3, cy + 4, 2 * r - 6, 7);
            }
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x + FW / 2, cy, r);
        }
        // HP along the bottom of the frame
        var bw = FW - 20;
        var bx = x + 10;
        var by = FY + FH - 10;
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, bw, 4);
        var pct = c.hp * 100 / (c.maxHp > 0 ? c.maxHp : 1);
        var fw = bw * pct / 100;
        if (fw < 1 && c.hp > 0) { fw = 1; }
        if (fw > 0) {
            dc.setColor(pct > 50 ? 0x00AA00 : (pct > 20 ? 0xFFAA00 : 0xFF0000), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, by, fw, 4);
        }
    }

    // One dot per team member, centred on x: filled while it still stands, a grey cross if fainted.
    function dots(dc, x, y, team) {
        var n = team.size();
        var x0 = x - (n - 1) * 6;
        for (var i = 0; i < n; i++) {
            var px = x0 + i * 12;
            if (team[i]) {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(px - 3, y - 3, px + 4, y + 4);
                dc.drawLine(px + 3, y - 3, px - 4, y + 4);
            } else {
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(px, y, 4);
                dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(px, y, 4);
            }
        }
    }
}

class BattleResultDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function close() {
        if (v.b.lobby != null) { v.b.lobby.battleDone(v.b.won); }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onSelect() { return close(); }
    function onBack() { return close(); }
}
