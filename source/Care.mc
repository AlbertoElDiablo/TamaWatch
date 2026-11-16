import Toybox.Lang;
import Toybox.Time;

// Care for the creatures that are not your partner (team and Pokébox). Only the partner's FOOD,
// JOY, ENE and HYG drain. When a creature stops being partner it keeps the values it had, and
// from then on they climb back, evenly, to full in 24 hours; its HP refills like the partner's
// (empty to full in 15 minutes). Stored in the member's own list at [14]:
//   [food, joy, energy, hygiene, since, hp %, hp since]   (none: everything full)
module Care {
    const FULL_SEC = 86400;

    function rise(v, since) {
        var dt = Time.now().value() - since;
        if (dt >= FULL_SEC || dt < 0) { return 100; }
        return v + (100 - v) * dt / FULL_SEC;
    }

    function hpOf(c) {
        var dt = Time.now().value() - c[6];
        if (dt >= HP_FULL_SEC || dt < 0) { return 100; }
        var v = c[5] + dt * 100 / HP_FULL_SEC;
        return v > 100 ? 100 : v;
    }

    // [food, joy, energy, hygiene, hp %] right now
    function now(mem) {
        if (mem.size() < 15 || mem[14] == null) { return [100, 100, 100, 100, 100]; }
        var c = mem[14];
        return [rise(c[0], c[4]), rise(c[1], c[4]), rise(c[2], c[4]), rise(c[3], c[4]), hpOf(c)];
    }

    // the partner leaves the home screen: what it had goes with it
    function store(mem, food, joy, energy, hygiene, hp) {
        var t = Time.now().value();
        while (mem.size() < 14) { mem.add(0); }
        var c = [food, joy, energy, hygiene, t, hp, t];
        if (mem.size() < 15) { mem.add(c); } else { mem[14] = c; }
    }

    // after a battle: its HP from there (the other stats keep climbing as they were)
    function setHp(mem, pct) {
        var t = Time.now().value();
        if (mem.size() < 15 || mem[14] == null) {
            store(mem, 100, 100, 100, 100, pct);
            return;
        }
        var c = mem[14];
        mem[14] = [c[0], c[1], c[2], c[3], c[4], pct < 0 ? 0 : (pct > 100 ? 100 : pct), t];
    }

    // its extra chance to miss in battle, from its own care (as careMissPct for the partner)
    function miss(mem) {
        var v = now(mem);
        var m = 0;
        var s = [v[0], v[3], v[1]];
        for (var i = 0; i < 3; i++) { if (s[i] < 50) { m += (50 - s[i]) * 3 / 10; } }
        return m > 40 ? 40 : m;
    }
}
