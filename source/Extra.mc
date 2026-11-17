import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

// Newer game state, kept apart from PetModel (at Connect IQ's member limit), saved under "ext":
//   [0] when each trainer (0-12) was last beaten (UTC): a rematch is due 2 days later
//   [1] when the rival next shows up (UTC, 0: not set yet)   [2] rival battles won
//   [3] the day [4] counts on   [4] stat points training games gave today   [5] unused
module Extra {
    const REMATCH_SEC = 172800;         // 2 days
    var d = null;

    function load() {
        if (d != null) { return; }
        var s = Storage.getValue("ext") as Array?;
        if (s != null && s.size() >= 6) {
            d = s;
            if (!(d[3] instanceof Number)) { d[3] = 0; d[4] = 0; }       // (an early save's sickness flag)
            return;
        }
        d = [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0, 0, 0, 0, 0];
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

    // Training games train slowly, slower than workouts: a game good enough to train (g > 0)
    // gives 1 point one time in three, at most GAME_DAY points a day from all of them.
    const GAME_DAY = 2;
    function gameGain(g) {
        load();
        var day = Time.now().value() / 86400;
        if (d[3] != day) { d[3] = day; d[4] = 0; }
        if (d[4] >= GAME_DAY || g <= 0 || Math.rand().abs() % 3 != 0) { return 0; }
        d[4] += 1;
        save();
        return 1;
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
