import Toybox.Lang;
import Toybox.Math;

// A creature inside a battle (TamaPoke's Combatant). Nothing here is written back to the
// pet, which is what keeps ailments battle-only.
class Combatant {
    var dex = 0;
    var level = 1;
    var maxHp = 1;
    var hp = 1;
    var base = [1, 1, 1, 1, 1];      // ATK, DEF, SPA, SPD, SPE before stages
    var stage = [0, 0, 0, 0, 0];     // -6..+6
    var moves = [0, 0, 0, 0];
    var ailment = 0;
    var ailTurns = 0;
    var confuseTurns = 0;
    var recharge = false;
    var charging = 0;
    var name = "";
    var shiny = false;
    var careMiss = 0;                // extra % to miss an attack: a hungry, dirty or unhappy pet
    var missWhy = 0;                 // ... and why (careMissWhy: 1 hungry, 2 bath, 3 train)
    var t1 = 0;                      // its types (from the species table, or the wire)
    var t2 = -1;
    var foreign = false;             // a friend's creature from another region: no sprite here
    var nat = 0;                     // national number
    var region = "";

    function initialize() {}
    function fainted() { return hp == 0; }
}

// What one action did, so the screen can narrate it without recomputing anything.
class TurnLog {
    var move = 0;
    var damage = 0;
    var effPct = 100;
    var hits = 0;
    var inflicted = 0;
    var stageDelta = 0;
    var stageMask = 0;
    var missed = false;
    var missWhy = 0;                 // a miss from poor care: why (0: an ordinary miss)
    var crit = false;
    var immune = false;
    var skipped = false;
    var hurtSelf = false;
    var charged = false;
    var healed = false;
    var targetFainted = false;

    function initialize() {}
}

// Turn resolution, ported from TamaPoke's battle.cpp (MIT): integer maths, same rules.
module Battle {

    const SI_ATK = 0;
    const SI_DEF = 1;
    const SI_SPA = 2;
    const SI_SPD = 3;
    const SI_SPE = 4;
    const STAGE_BITS = [1, 2, 4, 8, 16];

    function rnd(n) { return Math.rand().abs() % n; }

    function fill(c, dex, lvl, hp, a, d, sa, sd, sp) {
        c.dex = dex;
        c.level = lvl;
        c.maxHp = hp > 0 ? hp : 1;
        c.hp = c.maxHp;
        c.base = [a, d, sa, sd, sp];
        c.name = SpriteIndex.name(dex).toUpper();
        var r = Dex.row(dex);
        c.t1 = r[10];
        c.t2 = r[11];
        c.nat = Region.national(dex);
        c.region = Region.ID;
    }

    function hasType(c, t) { return c.t1 == t || c.t2 == t; }

    // cap > 0 fights at most at that level (no battle uses one: yours keep their own level).
    function fromPet(p, cap) {
        var c = new Combatant();
        var lvl = p.level();
        if (cap > 0 && lvl > cap) { lvl = cap; }
        var r = Dex.row(p.dex);
        fill(c, p.dex, lvl,
             stat(r[3], p.ivHp, lvl, 10), stat(r[4], p.ivAtk, lvl, p.trAtk), stat(r[5], p.ivDef, lvl, p.trDef),
             stat(r[7], p.ivAtk, lvl, p.trAtk), stat(r[8], p.ivDef, lvl, p.trDef), stat(r[6], p.ivSpe, lvl, p.trSpe));
        applyNature(c, natureOf(p.ivAtk, p.ivDef, p.ivSpe, p.ivHp));
        c.moves = [p.moves[0], p.moves[1], p.moves[2], p.moves[3]];
        c.shiny = p.shiny;
        if (p.nick.length() > 0) { c.name = p.nick.toUpper(); }
        // it fights with the HP it has now, never less than 1
        c.hp = c.maxHp * Hp.now(p) / 100;
        if (c.hp < 1) { c.hp = 1; }
        c.careMiss = careMissPct(p);
        c.missWhy = careMissWhy(p.food, p.hygiene, p.joy);
        return c;
    }

    // A party member, frozen at the level it reached (capped like the pet).
    function fromMember(m, cap) {
        var lvl = m[3];
        if (cap > 0 && lvl > cap) { lvl = cap; }
        var r = Dex.row(m[0]);
        var c = new Combatant();
        fill(c, m[0], lvl,
             stat(r[3], m[7], lvl, 10), stat(r[4], m[4], lvl, m[8]), stat(r[5], m[5], lvl, m[9]),
             stat(r[7], m[4], lvl, m[8]), stat(r[8], m[5], lvl, m[9]), stat(r[6], m[6], lvl, m[10]));
        applyNature(c, natureOf(m[4], m[5], m[6], m[7]));
        c.moves = [m[11][0], m[11][1], m[11][2], m[11][3]];
        if (c.moves.indexOf(0) == 0) { c.moves = bestMoves(m[0], lvl); }
        if (m[1].length() > 0) { c.name = m[1].toUpper(); }
        c.shiny = m[2];
        // its own HP and care (Care.mc), as the partner's are its own
        var cv = Care.now(m);
        c.hp = c.maxHp * cv[4] / 100;
        if (c.hp < 1) { c.hp = 1; }
        c.careMiss = Care.miss(m);
        c.missWhy = careMissWhy(cv[0], cv[3], cv[1]);
        return c;
    }

    // A creature of a species at a level with flat IVs and no training, knowing the best of
    // what it could have learned by then (TamaPoke's foe: dbgHatchAs + relearnFromLevel).
    function fromSpecies(dex, lvl, iv) {
        var r = Dex.row(dex);
        var c = new Combatant();
        fill(c, dex, lvl,
             stat(r[3], iv, lvl, 10), stat(r[4], iv, lvl, 0), stat(r[5], iv, lvl, 0),
             stat(r[7], iv, lvl, 0), stat(r[8], iv, lvl, 0), stat(r[6], iv, lvl, 0));
        applyNature(c, rnd(25));            // a wild or a trainer's creature: any nature
        c.moves = bestMoves(dex, lvl);
        return c;
    }

    // A creature on the wire: dex,level,maxHp,atk,def,spa,spd,spe,m1,m2,m3,m4,shiny,name,hp,careMiss,
    // national number,type1,type2,region. dex is the number inside the sender's region. An older
    // watch sends only the first 14 (Kanto, full HP, types from the table).
    function toWire(c) {
        return Wire.join([c.dex, c.level, c.maxHp, c.base[0], c.base[1], c.base[2], c.base[3], c.base[4],
                          c.moves[0], c.moves[1], c.moves[2], c.moves[3], c.shiny ? 1 : 0, Wire.clean(c.name),
                          c.hp, c.careMiss, c.nat, c.t1, c.t2, c.region, c.missWhy], ",");
    }

    function fromWire(s) {
        var f = Wire.split(s, ",");
        if (f.size() < 14) { return null; }
        var c = new Combatant();
        var dex = f[0].toNumber();
        var reg = f.size() >= 20 ? f[19] : "kanto";
        if (!reg.equals(Region.ID)) {
            // another region's creature: fights with its own numbers and types, drawn as a stand-in
            var nt = f.size() >= 17 ? f[16].toNumber() : dex;
            var a = f.size() >= 19 ? f[17].toNumber() : 0;
            var b = f.size() >= 19 ? f[18].toNumber() : -1;
            if (nt == null || a == null || b == null || a < 0 || a > 17 || b < -1 || b > 17) { return null; }
            var lv = f[1].toNumber();
            var mh = f[2].toNumber();
            if (lv == null || mh == null || mh < 1) { return null; }
            c.foreign = true;
            c.dex = 0;
            c.nat = nt;
            c.region = reg;
            c.t1 = a;
            c.t2 = b;
            c.level = lv;
            c.maxHp = mh;
            c.hp = mh;
            c.base = [f[3].toNumber(), f[4].toNumber(), f[5].toNumber(), f[6].toNumber(), f[7].toNumber()];
            for (var i = 0; i < 5; i++) { if (c.base[i] == null || c.base[i] < 1) { c.base[i] = 1; } }
            c.name = "#" + nt;
        } else {
            if (dex == null || dex < 1 || dex > Dex.COUNT) { return null; }
            fill(c, dex, f[1].toNumber(), f[2].toNumber(), f[3].toNumber(), f[4].toNumber(), f[5].toNumber(),
                 f[6].toNumber(), f[7].toNumber());
        }
        c.moves = [f[8].toNumber(), f[9].toNumber(), f[10].toNumber(), f[11].toNumber()];
        for (var i = 0; i < 4; i++) {
            if (c.moves[i] == null || c.moves[i] < 0 || c.moves[i] >= Moves.count()) { c.moves[i] = 0; }
        }
        c.shiny = f[12].equals("1");
        if (f[13].length() > 0) { c.name = f[13].toUpper(); }
        if (f.size() >= 16) {
            var h = f[14].toNumber();
            var cm = f[15].toNumber();
            if (h != null && h >= 1 && h <= c.maxHp) { c.hp = h; }
            if (cm != null && cm >= 0 && cm <= 40) { c.careMiss = cm; }
            if (f.size() >= 21) {
                var w = f[20].toNumber();
                if (w != null && w >= 0 && w <= 3) { c.missWhy = w; }
            }
        }
        return c;
    }

    // A whole squad: members separated by ";".
    function squadToWire(squad) {
        var parts = [];
        for (var i = 0; i < squad.size(); i++) { parts.add(toWire(squad[i])); }
        return Wire.join(parts, ";");
    }

    function squadFromWire(s) {
        var out = [];
        var parts = Wire.split(s, ";");
        for (var i = 0; i < parts.size() && out.size() < 6; i++) {
            var c = fromWire(parts[i]);
            if (c != null) { out.add(c); }
        }
        return out;
    }

    function stat(base, iv, lvl, tr) { return base + lvl + iv * lvl / 100 + tr; }

    // ---------- natures (FireRed's 25, in its order) ----------
    // Nature n raises stat n / 5 by 10% and lowers stat n % 5 by 10%, stats in the order ATK, DEF,
    // SPE, SP.ATK, SP.DEF (n / 5 == n % 5: neutral). A creature's comes from its IVs, so it never
    // changes and survives evolution.
    function natureOf(ivA, ivD, ivS, ivH) { return (ivA * 3 + ivD * 7 + ivS * 11 + ivH * 13) % 25; }

    function natureNames() {
        return ["Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold", "Docile", "Relaxed", "Impish", "Lax",
                "Timid", "Hasty", "Serious", "Jolly", "Naive", "Modest", "Mild", "Quiet", "Bashful", "Rash",
                "Calm", "Gentle", "Sassy", "Careful", "Quirky"];
    }

    // c.base is [ATK, DEF, SP.ATK, SP.DEF, SPE]
    function applyNature(c, n) {
        var at = [0, 1, 4, 2, 3];
        var up = at[n / 5];
        var down = at[n % 5];
        if (up == down) { return; }
        c.base[up] = c.base[up] * 11 / 10;
        c.base[down] = c.base[down] * 9 / 10;
        if (c.base[down] < 1) { c.base[down] = 1; }
    }

    // TamaPoke's relearnFromLevel(): fill four slots with the strongest moves reached
    // (level-up first, TMs only from level 40), STAB preferred, and make sure at least
    // one attack matches the creature's type when it has one.
    function bestMoves(dex, lvl) {
        var out = [0, 0, 0, 0];
        var score = [0, 0, 0, 0];
        var r = Dex.row(dex);
        var L = Moves.learnset(dex);
        for (var pass = 0; pass < 2; pass++) {
            var tmPass = pass == 1;
            for (var i = 0; i + 1 < L.size(); i += 2) {
                var mv = L[i];
                var at = L[i + 1];
                if (at > lvl || tmPass != (at == 0)) { continue; }
                if (mv <= 0 || mv >= Moves.count() || out.indexOf(mv) >= 0) { continue; }
                if (tmPass && lvl < Moves.TM_LEVEL) { continue; }
                var m = Moves.get(mv);
                var sc = m[2] == Moves.MC_STATUS ? 10 : m[3] + 20;
                if (m[2] != Moves.MC_STATUS && (m[1] == r[10] || m[1] == r[11])) { sc += 40; }
                if (m[5] == Moves.EF_RECHARGE) { sc -= 35; }
                if (m[5] == Moves.EF_RECOIL) { sc -= 20; }
                sc += at;
                if (sc < 1) { sc = 1; }
                var slot = -1;
                for (var s = 0; s < 4; s++) { if (sc > score[s]) { slot = s; break; } }
                if (slot < 0) { continue; }
                for (var s = 3; s > slot; s--) { score[s] = score[s - 1]; out[s] = out[s - 1]; }
                score[slot] = sc;
                out[slot] = mv;
            }
            if (out.indexOf(0) < 0) { break; }
        }
        for (var i = 0; i < 4; i++) {
            if (out[i] == 0) { continue; }
            var m = Moves.get(out[i]);
            if (m[2] != Moves.MC_STATUS && (m[1] == r[10] || m[1] == r[11])) { return out; }
        }
        var best = 0;
        var bestSc = 0;
        for (var i = 0; i + 1 < L.size(); i += 2) {
            var mv = L[i];
            var at = L[i + 1];
            if (at > lvl || mv <= 0 || mv >= Moves.count()) { continue; }
            var m = Moves.get(mv);
            if (m[2] == Moves.MC_STATUS || (m[1] != r[10] && m[1] != r[11])) { continue; }
            if (at == 0 && lvl < Moves.TM_LEVEL) { continue; }
            var sc = m[3];
            if (m[5] == Moves.EF_RECHARGE) { sc -= 35; }
            if (m[5] == Moves.EF_RECOIL) { sc -= 20; }
            if (sc > bestSc) { bestSc = sc; best = mv; }
        }
        if (best != 0) { out[3] = best; }
        return out;
    }

    function stagedStat(base, st) {
        if (st > 6) { st = 6; }
        if (st < -6) { st = -6; }
        var num = 2 + (st > 0 ? st : 0);
        var den = 2 + (st < 0 ? -st : 0);
        var v = base * num / den;
        return v < 1 ? 1 : v;
    }

    function effStat(c, idx) {
        var v = stagedStat(c.base[idx], c.stage[idx]);
        if (idx == SI_ATK && c.ailment == Moves.AIL_BURN) { v = v / 2 > 0 ? v / 2 : 1; }
        if (idx == SI_SPE && c.ailment == Moves.AIL_PARA) { v = v / 2 > 0 ? v / 2 : 1; }
        return v;
    }

    function damage(atk, def, mv, crit, roll) {
        if (mv <= 0 || mv >= Moves.count()) { return 0; }
        var m = Moves.get(mv);
        if (m[2] == Moves.MC_STATUS) { return 0; }
        if (m[5] == Moves.EF_FIXED_LVL) { return atk.level > 0 ? atk.level : 1; }
        if (m[5] == Moves.EF_FIXED) { return m[6] > 0 ? m[6] : 1; }
        var phys = m[2] == Moves.MC_PHYS;
        var A = phys ? effStat(atk, SI_ATK) : effStat(atk, SI_SPA);
        var D = phys ? effStat(def, SI_DEF) : effStat(def, SI_SPD);
        if (crit) {                         // a critical hit ignores stages
            A = phys ? atk.base[SI_ATK] : atk.base[SI_SPA];
            D = phys ? def.base[SI_DEF] : def.base[SI_SPD];
        }
        if (D == 0) { D = 1; }
        var dmg = (2 * atk.level / 5 + 2) * m[3] * A / D / 50 + 2;
        if (crit) { dmg *= 2; }
        if (hasType(atk, m[1])) { dmg = dmg * 3 / 2; }
        var eff = Moves.effVs(m[1], def.t1, def.t2);
        if (eff == 0) { return 0; }
        dmg = dmg * eff / 100;
        dmg = dmg * roll / 255;
        return dmg < 1 ? 1 : dmg;
    }

    function priority(mv) {
        if (mv <= 0 || mv >= Moves.count()) { return 0; }
        var m = Moves.get(mv);
        return m[5] == Moves.EF_PRIORITY ? m[6] : 0;
    }

    // Priority first, then the staged speed (paralysis halves it); a tie is a coin flip.
    function movesFirst(a, ma, b, mb) {
        var pa = priority(ma);
        var pb = priority(mb);
        if (pa != pb) { return pa > pb; }
        var sa = effStat(a, SI_SPE);
        var sb = effStat(b, SI_SPE);
        if (sa != sb) { return sa > sb; }
        return rnd(2) == 0;
    }

    function applyStages(c, mask, delta) {
        for (var i = 0; i < 5; i++) {
            if ((mask & STAGE_BITS[i]) == 0) { continue; }
            var v = c.stage[i] + delta;
            c.stage[i] = v > 6 ? 6 : (v < -6 ? -6 : v);
        }
    }

    function hurt(c, amount) { c.hp = amount >= c.hp ? 0 : c.hp - amount; }
    function heal(c, amount) { c.hp = c.hp + amount > c.maxHp ? c.maxHp : c.hp + amount; }

    // One creature's action: ailments that stop it, accuracy, damage, effects.
    function act(atk, def, mv) {
        var log = new TurnLog();
        log.move = mv;
        if (atk.fainted() || def.fainted()) { log.skipped = true; return log; }
        if (atk.recharge) { atk.recharge = false; log.skipped = true; return log; }
        if (atk.ailment == Moves.AIL_FREEZE) {
            if (rnd(100) < 20) { atk.ailment = Moves.AIL_NONE; }
            else { log.skipped = true; return log; }
        }
        if (atk.ailment == Moves.AIL_SLEEP) {
            if (atk.ailTurns > 0) { atk.ailTurns--; }
            if (atk.ailTurns == 0) { atk.ailment = Moves.AIL_NONE; }
            else { log.skipped = true; return log; }
        }
        if (atk.ailment == Moves.AIL_PARA && rnd(100) < 25) { log.skipped = true; return log; }
        if (atk.confuseTurns > 0) {
            atk.confuseTurns--;
            if (rnd(100) < 33) {
                var d0 = atk.base[SI_DEF] > 0 ? atk.base[SI_DEF] : 1;
                var selfHit = (2 * atk.level / 5 + 2) * 40 * atk.base[SI_ATK] / d0 / 50 + 2;
                hurt(atk, selfHit);
                log.hurtSelf = true;
                log.damage = selfHit;
                return log;
            }
        }
        if (atk.charging != 0) {
            mv = atk.charging;
            atk.charging = 0;
        } else if (mv > 0 && mv < Moves.count() && Moves.get(mv)[5] == Moves.EF_CHARGE) {
            atk.charging = mv;
            log.charged = true;
            return log;
        }
        if (mv <= 0 || mv >= Moves.count()) { log.skipped = true; return log; }
        var m = Moves.get(mv);
        log.move = mv;
        // a pet that is hungry, dirty or unhappy misses more of its attacks (any attack)
        if (atk.careMiss > 0 && m[2] != Moves.MC_STATUS && rnd(100) < atk.careMiss) {
            log.missed = true;
            log.missWhy = atk.missWhy;
            return log;
        }
        if (m[4] > 0 && m[5] != Moves.EF_NEVER_MISS && rnd(100) >= m[4]) {
            log.missed = true;
            return log;
        }
        if (m[2] == Moves.MC_STATUS) {
            if (m[5] == Moves.EF_HEAL) {
                heal(atk, atk.maxHp * (m[6] > 0 ? m[6] : 50) / 100);
                log.healed = true;
            } else if (m[5] == Moves.EF_STAGE) {
                applyStages(m[9] == Moves.TG_SELF ? atk : def, m[7], m[8]);
                log.stageMask = m[7];
                log.stageDelta = m[8];
            }
            return log;
        }
        var hits = m[5] == Moves.EF_MULTI ? 2 + rnd(4) : 1;
        var total = 0;
        log.effPct = Moves.effVs(m[1], def.t1, def.t2);
        if (log.effPct == 0) { log.immune = true; return log; }
        for (var h = 0; h < hits; h++) {
            var crit = rnd(16) == 0;
            var d = damage(atk, def, mv, crit, 217 + rnd(39));
            total += d;
            if (crit) { log.crit = true; }
            hurt(def, d);
            if (def.fainted()) { hits = h + 1; break; }
        }
        log.hits = hits;
        log.damage = total;
        if (m[5] == Moves.EF_RECOIL && m[6] > 0) { hurt(atk, total / m[6] > 0 ? total / m[6] : 1); }
        if (m[5] == Moves.EF_DRAIN && m[6] > 0) { heal(atk, total * m[6] / 100); }
        if (m[5] == Moves.EF_RECHARGE) { atk.recharge = true; }
        if (m[10] != Moves.AIL_NONE && m[11] > 0 && !def.fainted() && rnd(100) < m[11]) {
            if (m[10] == Moves.AIL_CONFUSE) {
                if (def.confuseTurns == 0) {
                    def.confuseTurns = 2 + rnd(3);
                    log.inflicted = Moves.AIL_CONFUSE;
                }
            } else if (def.ailment == Moves.AIL_NONE) {
                var immune = (m[10] == Moves.AIL_BURN && hasType(def, 1)) ||
                             (m[10] == Moves.AIL_FREEZE && hasType(def, 5)) ||
                             (m[10] == Moves.AIL_POISON && hasType(def, 7)) ||
                             (m[10] == Moves.AIL_PARA && hasType(def, 3));
                if (!immune) {
                    def.ailment = m[10];
                    if (m[10] == Moves.AIL_SLEEP) { def.ailTurns = 2 + rnd(3); }
                    log.inflicted = m[10];
                }
            }
        }
        log.targetFainted = def.fainted();
        return log;
    }

    // Burn and poison chip damage after both have acted.
    function endTurn(c) {
        var log = new TurnLog();
        if (c.fainted()) { return log; }
        if (c.ailment == Moves.AIL_BURN || c.ailment == Moves.AIL_POISON) {
            var chip = c.maxHp / 16;
            if (chip < 1) { chip = 1; }
            hurt(c, chip);
            log.damage = chip;
            log.inflicted = c.ailment;
            log.targetFainted = c.fainted();
        }
        return log;
    }

    // Easy picks at random; hard reads the type chart, accuracy, kills and boosts.
    function aiChoose(user, foe, smart) {
        var legal = [];
        for (var i = 0; i < 4; i++) {
            if (user.moves[i] > 0 && user.moves[i] < Moves.count()) { legal.add(user.moves[i]); }
        }
        if (legal.size() == 0) { return 0; }
        if (!smart) { return legal[rnd(legal.size())]; }
        var bestScore = -100000;
        var best = legal[0];
        for (var i = 0; i < legal.size(); i++) {
            var mv = legal[i];
            var m = Moves.get(mv);
            var sc;
            if (m[2] == Moves.MC_STATUS) {
                if (m[5] == Moves.EF_HEAL) {
                    sc = ((user.maxHp - user.hp) * 100 / (user.maxHp > 0 ? user.maxHp : 1)) - 30;
                } else if (m[5] == Moves.EF_STAGE) {
                    var t = m[9] == Moves.TG_SELF ? user : foe;
                    var stacked = 0;
                    var hit = 0;
                    for (var k = 0; k < 5; k++) {
                        if ((m[7] & STAGE_BITS[k]) != 0) { stacked += t.stage[k] * (m[8] > 0 ? 1 : -1); hit++; }
                    }
                    if (hit == 0) { hit = 1; }
                    sc = 26 - stacked * 12 / hit;
                    if (user.hp * 3 < user.maxHp) { sc -= 40; }
                } else {
                    sc = 5;
                }
            } else {
                var dmg = damage(user, foe, mv, false, 236);
                sc = dmg;
                if (dmg >= foe.hp) { sc += 1000; }
                var acc = m[4] > 0 ? m[4] : 100;
                sc = sc * acc / 100;
                if (m[5] == Moves.EF_RECHARGE) { sc -= dmg / 4; }
                if (m[5] == Moves.EF_RECOIL) { sc -= dmg / 6; }
                if (m[5] == Moves.EF_CHARGE) { sc -= dmg / 3; }
                if (m[10] != Moves.AIL_NONE && foe.ailment == Moves.AIL_NONE) { sc += m[11] / 4; }
            }
            if (sc > bestScore) { bestScore = sc; best = mv; }
        }
        return best;
    }
}
