import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Route Crossing's ground, painted once when the game opens into bitmaps (one strip a kind of
// lane), so the detail costs nothing per frame: GBA-era route grass with tufts and flowers, a
// sandy path with edges and pebbles, rippling water (it scrolls), and a railway. Our own art.
module RouteArt {
    const SW = 320;                 // a strip's width in 280-pixel units (the field and both edges)
    const SH = 30;                  // a lane's height
    var f = 1.0;                    // real pixels per unit in the strips
    var grassA = null;
    var grassB = null;
    var path = null;
    var water = null;
    var rail = null;
    var seed = 7;

    function rnd(n) { seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF; return (seed >> 8) % n; }
    function R(v) { return (v * f + 0.5).toNumber(); }

    function newBmp(pal) {
        var o = {:width => R(SW), :height => R(SH), :palette => pal};
        if (Graphics has :createBufferedBitmap) { return Graphics.createBufferedBitmap(o).get(); }
        return new Graphics.BufferedBitmap(o);
    }

    function rect(dc, c, x, y, w, h) {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(R(x), R(y), R(x + w) - R(x) > 0 ? R(x + w) - R(x) : 1, R(y + h) - R(y) > 0 ? R(y + h) - R(y) : 1);
    }

    function make() {
        if (grassA != null) { return; }
        // the strips are drawn as they are where the watch's pictures were resized for it (or it
        // can't scale them), and scaled by Sdc where it can
        f = (Scr.prescaled || !Scr.scaled) ? Scr.k : 1.0;
        seed = 7;
        grassA = newBmp([0x55AA55, 0x00AA00, 0x005500, 0xFFFFFF, 0xFFFF00, 0xFF5555, 0x55FF55]);
        paintGrass(grassA.getDc(), 0x55AA55, 0x00AA00);
        grassB = newBmp([0x55AA55, 0x00AA00, 0x005500, 0xFFFFFF, 0xFFFF00, 0xFF5555, 0x55FF55]);
        paintGrass(grassB.getDc(), 0x00AA00, 0x55AA55);
        path = newBmp([0xFFAA55, 0xAA5500, 0xFFFFAA, 0x550000, 0xFFFF55]);
        paintPath(path.getDc());
        water = newBmp([0x0055FF, 0x0000AA, 0x55AAFF, 0xFFFFFF, 0x00AAFF]);
        paintWater(water.getDc());
        rail = newBmp([0xAAAAAA, 0x555555, 0x550000, 0xAA5500, 0xFFFFFF, 0x000000]);
        paintRail(rail.getDc());
    }

    function clear() { grassA = null; grassB = null; path = null; water = null; rail = null; }

    // grass: its colour, a darker seam at the top, tufts of tall grass and a few flowers
    function paintGrass(dc, base, tuft) {
        rect(dc, base, 0, 0, SW, SH);
        rect(dc, tuft, 0, 0, SW, 1);
        for (var x = 0; x < SW; x += 10) {
            var y = 5 + rnd(18);
            var tx = x + rnd(6);
            rect(dc, 0x005500, tx, y + 2, 1, 3);
            rect(dc, 0x005500, tx + 2, y, 1, 5);
            rect(dc, 0x005500, tx + 4, y + 2, 1, 3);
            rect(dc, 0x55FF55, tx + 2, y, 1, 1);
            if (rnd(9) == 0) {
                var fx = x + rnd(8);
                var fy = 4 + rnd(20);
                var petal = rnd(3) == 0 ? 0xFF5555 : 0xFFFFFF;
                rect(dc, petal, fx, fy + 1, 3, 1);
                rect(dc, petal, fx + 1, fy, 1, 3);
                rect(dc, 0xFFFF00, fx + 1, fy + 1, 1, 1);
            }
        }
    }

    // a sandy path: darker edges, two faint ruts, pebbles with a light and a dark side
    function paintPath(dc) {
        rect(dc, 0xFFAA55, 0, 0, SW, SH);
        rect(dc, 0xAA5500, 0, 0, SW, 2);
        rect(dc, 0xAA5500, 0, SH - 2, SW, 2);
        for (var x = 0; x < SW; x += 6) {
            if (rnd(3) != 0) { rect(dc, 0xFFFF55, x, 9, 3, 1); }
            if (rnd(3) != 0) { rect(dc, 0xFFFF55, x + 2, 20, 3, 1); }
        }
        for (var x = 0; x < SW; x += 14) {
            var px = x + rnd(10);
            var py = 4 + rnd(21);
            rect(dc, 0xAA5500, px, py, 3, 2);
            rect(dc, 0xFFFFAA, px, py, 2, 1);
        }
    }

    // water: a dark bank shadow at the top, rows of ripples (repeating every 24, so it can scroll)
    // and a few sparkles
    function paintWater(dc) {
        rect(dc, 0x0055FF, 0, 0, SW, SH);
        rect(dc, 0x0000AA, 0, 0, SW, 2);
        for (var x = 0; x < SW; x += 24) {
            rect(dc, 0x55AAFF, x + 2, 7, 7, 1);
            rect(dc, 0x00AAFF, x + 3, 8, 5, 1);
            rect(dc, 0x55AAFF, x + 14, 16, 7, 1);
            rect(dc, 0x00AAFF, x + 15, 17, 5, 1);
            rect(dc, 0x55AAFF, x + 6, 24, 6, 1);
            rect(dc, 0xFFFFFF, x + 19, 11, 1, 1);
        }
    }

    // a railway: speckled gravel, wooden sleepers, two steel rails with a shine
    function paintRail(dc) {
        rect(dc, 0xAAAAAA, 0, 0, SW, SH);
        for (var x = 0; x < SW; x += 4) { rect(dc, 0x555555, x + rnd(3), 2 + rnd(26), 1, 1); }
        for (var x = 0; x < SW; x += 12) {
            rect(dc, 0x550000, x, 4, 7, SH - 8);
            rect(dc, 0xAA5500, x + 1, 5, 5, 2);
        }
        rect(dc, 0x555555, 0, 9, SW, 3);
        rect(dc, 0xFFFFFF, 0, 9, SW, 1);
        rect(dc, 0x555555, 0, SH - 12, SW, 3);
        rect(dc, 0xFFFFFF, 0, SH - 12, SW, 1);
        rect(dc, 0x000000, 0, 12, SW, 1);
        rect(dc, 0x000000, 0, SH - 9, SW, 1);
    }

    // ---------- things on the lanes (drawn each frame, through Sdc) ----------

    function tree(dc, x, y) {
        dc.setColor(0x005500, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(x + 2, y + 26, 12, 3);                     // its shadow
        dc.setColor(0x550000, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - 3, y + 17, 7, 10);
        dc.setColor(0xAA5500, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - 2, y + 18, 2, 8);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 10, 14);
        dc.setColor(0x005500, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 10, 13);
        dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 1, y + 8, 10);
        dc.setColor(0x55FF55, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 4, y + 5, 4);
        dc.setColor(0x005500, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + 5, y + 13, 3);
    }

    function boulder(dc, x, y) {
        dc.setColor(0x005500, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(x + 2, y + 24, 12, 3);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 15, 12);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 15, 11);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 2, y + 13, 8);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 5, y + 9, 2);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x + 2, y + 10, x + 5, y + 17);
    }

    function lily(dc, x, y, flower) {
        dc.setColor(0x005500, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 15, 13);
        dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 15, 11);
        dc.setColor(0x55FF55, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x - 6, y + 15, x + 4, y + 15);
        dc.drawLine(x - 3, y + 9, x + 2, y + 21);
        dc.setColor(0x0055FF, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, y + 15], [x + 14, y + 9], [x + 14, y + 17]]);    // the notch
        if (flower) {
            dc.setColor(0xFF55AA, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - 4, y + 11, 3);
            dc.fillCircle(x - 1, y + 13, 3);
            dc.fillCircle(x - 6, y + 14, 3);
            dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - 4, y + 13, 1);
        }
    }

    function log(dc, x, y, w) {
        dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x + 2, y + 23, w - 2, 4, 2);           // its shadow in the water
        dc.setColor(0x550000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y + 5, w, 20, 7);
        dc.setColor(0xAA5500, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x + 1, y + 6, w - 2, 17, 6);
        dc.setColor(0xFFAA55, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 6, y + 8, w - 16, 2);
        dc.setColor(0x550000, Graphics.COLOR_TRANSPARENT);
        for (var g = x + 12; g < x + w - 14; g += 13) {
            dc.drawLine(g, y + 13, g + 6, y + 13);
            dc.drawLine(g + 4, y + 18, g + 10, y + 18);
        }
        // the cut end
        dc.setColor(0xFFAA55, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(x + w - 5, y + 15, 4, 8);
        dc.setColor(0xAA5500, Graphics.COLOR_TRANSPARENT);
        dc.drawEllipse(x + w - 5, y + 15, 2, 5);
    }

    // a train of n carriages heading dir (+1 right), its engine in front
    function train(dc, x, y, w, dir) {
        var cars = w / 36;
        for (var i = 0; i < cars; i++) {
            var cx = x + i * 36;
            var front = (dir > 0 && i == cars - 1) || (dir < 0 && i == 0);
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cx + 1, y + 2, 34, 25, 4);
            dc.setColor(front ? 0xFF0000 : 0xAA0000, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cx + 2, y + 3, 32, 22, 3);
            dc.setColor(0x550000, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx + 2, y + 3, 32, 4);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx + 2, y + 18, 32, 2);
            if (front) {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(dir > 0 ? cx + 20 : cx + 5, y + 8, 10, 8);
                dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(dir > 0 ? cx + 32 : cx + 4, y + 21, 2);
            } else {
                dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx + 6, y + 8, 9, 7);
                dc.fillRectangle(cx + 21, y + 8, 9, 7);
            }
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx + 9, y + 26, 3);
            dc.fillCircle(cx + 27, y + 26, 3);
        }
    }

    // the railway's signal: a post and a lamp, flashing red before a train
    function signal(dc, x, y, on) {
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - 1, y + 4, 3, 22);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 6, 6);
        dc.setColor(on ? 0xFF0000 : 0x550000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 6, 4);
        if (on) {
            dc.setColor(0xFFAAAA, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - 1, y + 5, 1);
        }
    }
}
