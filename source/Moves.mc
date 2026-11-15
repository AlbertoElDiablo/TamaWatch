import Toybox.Lang;
import Toybox.WatchUi;

// Moves and types (generated from TamaPoke's moves.h / dex.h by tools/make_moves.py).
// Move row: [name, type, cat, power, acc, effect, param, statMask, stages, target, ailment, ailChance]
module Moves {

    // categories
    const MC_PHYS = 0;
    const MC_SPEC = 1;
    const MC_STATUS = 2;
    // effects
    const EF_NONE = 0;
    const EF_STAGE = 1;
    const EF_RECOIL = 2;
    const EF_DRAIN = 3;
    const EF_FIXED_LVL = 4;
    const EF_FIXED = 5;
    const EF_PRIORITY = 6;
    const EF_NEVER_MISS = 7;
    const EF_MULTI = 8;
    const EF_HEAL = 9;
    const EF_RECHARGE = 10;
    const EF_CHARGE = 11;
    // stat bits for EF_STAGE
    const ST_ATK = 1;
    const ST_DEF = 2;
    const ST_SPA = 4;
    const ST_SPD = 8;
    const ST_SPE = 16;
    const TG_SELF = 0;
    const TG_FOE = 1;
    // ailments
    const AIL_NONE = 0;
    const AIL_PARA = 1;
    const AIL_BURN = 2;
    const AIL_POISON = 3;
    const AIL_SLEEP = 4;
    const AIL_FREEZE = 5;
    const AIL_CONFUSE = 6;
    const AIL_NAMES = ["", "PAR", "BRN", "PSN", "SLP", "FRZ", "CNF"];

    const TM_LEVEL = 40;     // every TM unlocks at 40, nothing before

    var table = null;
    var types = null;

    function rows() {
        if (table == null) { table = WatchUi.loadResource(Rez.JsonData.moves); }
        return table;
    }

    function count() { return rows().size(); }
    function get(mv) { return rows()[mv]; }
    function name(mv) { return Tr.t(rows()[mv][0]); }
    function type(mv) { return rows()[mv][1]; }
    function cat(mv) { return rows()[mv][2]; }
    function power(mv) { return rows()[mv][3]; }

    function typeData() {
        if (types == null) { types = WatchUi.loadResource(Rez.JsonData.types); }
        return types;
    }

    function typeName(t) { return Tr.t(typeData()["names"][t]); }
    function typeColor(t) { return typeData()["colors"][t]; }

    // Percent: 100 neutral, 200 super effective, 50 resisted, 0 immune (400 / 25 doubled up).
    function effVsDex(atkType, dex) {
        var r = Dex.row(dex);
        var fx = typeData()["fx"][atkType];
        var e = fx[r[10]];
        return e * (r[11] >= 0 ? fx[r[11]] : 10);
    }

    // Same-type attack bonus: the move matches one of the user's types.
    function hasStab(dex, t) {
        var r = Dex.row(dex);
        return r[10] == t || r[11] == t;
    }

    // A species' learnset as [move, level, ...] (level 0 = TM).
    function learnset(dex) {
        return WatchUi.loadResource(SpriteIndex.data(dex))["L"];
    }
}
