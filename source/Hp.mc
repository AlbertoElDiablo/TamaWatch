import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;

// The pet's HP, kept between battles (PetModel.hpv: [%, when], saved under "hp"). Battles take
// it and the next battle starts from what is left. It refills by itself from empty in 15 minutes
// (HP_FULL_SEC); food, a training game and a recorded activity give some back at once.
module Hp {

    function now(m) {
        var dt = Time.now().value() - m.hpv[1];
        if (dt >= HP_FULL_SEC || dt < 0) { return 100; }      // (and no overflow on a long gap)
        var v = m.hpv[0] + dt * 100 / HP_FULL_SEC;
        return v > 100 ? 100 : (v < 0 ? 0 : v);
    }

    function set(m, v) {
        m.hpv = [v < 0 ? 0 : (v > 100 ? 100 : v), Time.now().value()];
        Storage.setValue("hp", m.hpv);
    }

    function heal(m, v) {
        if (m.isEgg()) { return; }
        var before = now(m);
        if (before < 100) { set(m, before + v); }
    }

    // After a battle (or running from one): the pet keeps the HP it ended with. A battle that
    // took 40 % or more of it also costs food, a quarter of what it lost.
    // Returns the food it cost (0: none).
    function afterBattle(m, endPct, startPct) {
        set(m, endPct);
        var lost = startPct - endPct;
        if (lost >= 40) {
            var before = m.food;
            m.food = m.clamp100(m.food - lost / 4);
            m.save();
            return before - m.food;
        }
        return 0;
    }

    // After a training game: some HP back and, now and then (1 in 3), one piece of fruit found
    // on the way: 0 apple, 1 blue berry, 2 orange; -1 nothing this time.
    function afterGame(m) {
        heal(m, HP_GAME);
        if (m.isEgg() || m.rnd(3) != 0) { return -1; }
        var r = m.rnd(10);
        var item = r < 6 ? m.FOOD_APPLE : (r < 8 ? m.FOOD_BLUE : m.FOOD_ORANGE);
        if (m.bag[item] < 99) { m.bag[item] += 1; }
        m.save();
        return item;
    }
}
