import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;

// Newer game state, kept apart from PetModel (at Connect IQ's member limit), saved under "ext":
//   [0] when each trainer (0-12) was last beaten (UTC): a rematch is due 2 days later
//   [1] when the rival next shows up (UTC, 0: not set yet)   [2] rival battles won
//   [3] the day [4] counts on   [4] training games that counted today   [5] unused
//   [6..8] effort toward the next ATK / DEF / SPD training point (see train)
module Extra {
    const REMATCH_SEC = 172800;         // 2 days
    var d = null;

    function load() {
        if (d != null) { return; }
        var s = Storage.getValue("ext") as Array?;
        if (s != null && s.size() >= 6) {
            d = s;
            if (!(d[3] instanceof Number)) { d[3] = 0; d[4] = 0; }       // (an early save's sickness flag)
            while (d.size() < 9) { d.add(0); }
            return;
        }
        d = [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0, 0, 0, 0, 0, 0, 0, 0];
    }

    function save() { load(); Storage.setValue("ext", d); }

    // ---------- gym rematches (FireRed's VS Seeker) ----------

    // a beaten trainer can be challenged again, stronger, 2 days after its last defeat (one beaten
    // before rematches existed: straight away)
    function rematchReady(i) {
        load();
        if (i < 0 || i >= d[0].size()) { return false; }
        return Time.now().value() - d[0][i] >= REMATCH_SEC;
    }

    function beaten(i) {
        load();
        if (i >= 0 && i < d[0].size()) { d[0][i] = Time.now().value(); save(); }
    }

    // ---------- training games: only the first 3 a day train a stat ----------

    // Training builds up slowly, like VO2 max: everything that trains (workouts, games, gym wins,
    // goals, good care) adds effort, in hundredths, toward the stat's next point, and each point
    // costs more than the last: 100 + 3 a point already earned (1 point at 0, 4 at 100, 7 at 200).
    // A 30-minute workout is 24; a good training game a quarter of that. No ceiling but MAX.
    const MAX = 255;
    const GAME_EFFORT = 6;
    const GAME_DAY = 4;                 // training games that count a day
    function cost(cur) { return 100 + 3 * cur; }

    // Effort into stat which (0 ATK, 1 DEF, 2 SPD) of m: the points it reached (m.tr* raised), and
    // shown = how much of a point that was (hundredths, for "+0.24").
    var shown = 0;
    function train(m, which, effort) {
        load();
        var cur = which == 0 ? m.trAtk : (which == 1 ? m.trDef : m.trSpe);
        if (cur >= MAX) { shown = 0; return 0; }
        shown = effort * 100 / cost(cur);
        if (shown < 1) { shown = 1; }
        var p = d[6 + which] + effort;
        var got = 0;
        while (cur < MAX && p >= cost(cur)) { p -= cost(cur); cur++; got++; }
        d[6 + which] = p;
        if (which == 0) { m.trAtk = cur; } else if (which == 1) { m.trDef = cur; } else { m.trSpe = cur; }
        save();
        return got;
    }

    // how far stat which (at cur points) is toward its next point, 0-99
    function progress(which, cur) {
        load();
        return d[6 + which] * 100 / cost(cur);
    }

    // hundredths as "0.24"
    function fmt(h) {
        return (h / 100) + "." + (h % 100 < 10 ? "0" : "") + (h % 100);
    }

    // A training game good enough to train (g > 0) gives GAME_EFFORT, the first GAME_DAY a day.
    function gameGain(g) {
        load();
        var day = Time.now().value() / 86400;
        if (d[3] != day) { d[3] = day; d[4] = 0; }
        if (d[4] >= GAME_DAY || g <= 0) { return 0; }
        d[4] += 1;
        save();
        return GAME_EFFORT;
    }

    function gamesLeft() {
        load();
        return d[3] == Time.now().value() / 86400 ? (d[4] >= GAME_DAY ? 0 : GAME_DAY - d[4]) : GAME_DAY;
    }

    // ---------- the rival ----------

    function rivalReady(m) {
        load();
        if (m.isEgg() || m.level() < 5) { return false; }
        var now = Time.now().value();
        if (d[1] == 0) { d[1] = now + 6 * 3600; save(); return false; }     // the first visit: later today
        return now >= d[1];
    }

    // after a rival battle, won or lost: back in 2 to 4 days
    function rivalDone(m, won) {
        load();
        d[1] = Time.now().value() + (2 + m.rnd(3)) * 86400;
        if (won) { d[2] += 1; }
        save();
    }
}
