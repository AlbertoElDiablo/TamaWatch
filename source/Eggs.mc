import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;

// Bonus eggs from walking: every 15,000 steps earns an egg, at most 2 in any 7 days. Steps
// carry over for as long as it takes to reach 15,000; but while 2 eggs were already earned in
// the last 7 days, steps don't count (nothing piles up past the limit). An egg
// then hatches by walking its own steps (1,000 common, 2,000 rare, 3,000 legendary) and the
// newcomer joins the team, or the Pokébox when the team is full; your partner stays. Each step
// counts once: toward hatching the waiting egg, or toward the next egg.
// Kept apart from PetModel (which is at Connect IQ's member limit), saved under "eggs".
module Incubator {
    const STEPS_PER_EGG = 15000;
    const MAX_PER_WEEK = 2;
    const WEEK = 604800;                    // seconds
    const HATCH_STEPS = [0, 1000, 2000, 3000];

    var queue = null;       // [[species, shiny, steps left], ...] waiting to hatch
    var bank = 0;           // steps toward the next egg
    var times = [];         // when the recent eggs were earned (UTC), for the weekly limit
    var total = 0;          // eggs earned ever (the background notifies once per egg by it)
    var repFound = 0;       // for the welcome-back screen
    var repHatched = [];    // names hatched

    function load() {
        if (queue != null) { return; }
        var s = Storage.getValue("eggs") as Array?;
        if (s == null || s.size() < 3) { queue = []; bank = 0; times = []; total = 0; return; }
        queue = s[0]; bank = s[1]; times = s[2];
        total = s.size() > 3 ? s[3] : times.size();
    }

    function save() { Storage.setValue("eggs", [queue, bank, times, total]); }

    // Eggs earned in the last 7 days.
    function recent() {
        var now = Time.now().value();
        var keep = [];
        for (var i = 0; i < times.size(); i++) { if (now - times[i] < WEEK) { keep.add(times[i]); } }
        times = keep;
        return keep.size();
    }

    // New steps walked (called from PetModel.claimSteps; a run's steps included, and those of days
    // the app wasn't opened): each step counts once, either toward hatching the waiting egg or,
    // when there is none (or once it has hatched), toward finding the next. So an egg is never
    // found and hatched by the same steps: a new egg only hatches with the steps after it.
    function onSteps(m, delta) {
        load();
        if (delta <= 0) { return; }
        var rest = delta;
        if (queue.size() > 0) {
            var e = queue[0];
            var use = rest < e[2] ? rest : e[2];
            e[2] -= use;
            rest -= use;
            if (e[2] <= 0) { hatch(m, e); queue = queue.slice(1, null); }
        }
        if (recent() < MAX_PER_WEEK) { bank += rest; }        // at the limit, steps don't pile up
        while (bank >= STEPS_PER_EGG) {
            if (recent() >= MAX_PER_WEEK) { bank = 0; break; }
            bank -= STEPS_PER_EGG;
            total++;
            var n = m.pickEggSpecies();
            var shinyOdds = 48 - m.careBonus();
            if (shinyOdds < 8) { shinyOdds = 8; }
            // made when you open the app, so you see it first; only steps after that hatch it
            queue.add([n, m.rnd(shinyOdds) == 0, HATCH_STEPS[Dex.rarity(n)], total]);
            times.add(Time.now().value());
            if (recent() >= MAX_PER_WEEK) { bank = 0; }       // the week's second egg: nothing left over
            repFound++;
            m.say(Tr.t("You found an egg! Walk to hatch it"), 4000);
            Sfx.vibe(Sfx.HATCH);
        }
        save();
    }

    // The newcomer: level 5, fresh IVs, its best moves for its level, into the team or the box.
    function hatch(m, e) {
        var n = e[0];
        var shiny = e[1];
        var b = m.careBonus();
        var iv = [m.rollIV(b), m.rollIV(b), m.rollIV(b), m.rollIV(b)];
        if (shiny) { for (var i = 0; i < 4; i++) { if (iv[i] < 20) { iv[i] = 20; } } }
        var mv = Battle.bestMoves(n, 5);
        var member = [n, "", shiny, 5, iv[0], iv[1], iv[2], iv[3], 0, 0, 0, mv, 0, Lvl.expFor(5)];
        m.dexReg[(n - 1) / 24] |= 1 << ((n - 1) % 24);
        if (shiny) { m.dexShiny[(n - 1) / 24] |= 1 << ((n - 1) % 24); }
        var name = SpriteIndex.name(n);
        if (m.party.size() < TEAM_MATES) {
            m.party.add(member);
            m.say(Tr.f("{0} hatched and joined your team!", [name]), 4000);
        } else {
            m.box.add(member);
            m.say(Tr.f("{0} hatched and went to the Pokébox!", [name]), 4000);
        }
        repHatched.add(name);
        Sfx.vibe(Sfx.HATCH);
        m.save();
    }

    function hasReport() { return repFound > 0 || repHatched.size() > 0; }
    function clearReport() { repFound = 0; repHatched = []; }
    function waiting() { load(); return queue; }
}
