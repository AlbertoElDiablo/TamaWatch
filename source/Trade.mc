import Toybox.Lang;

// Trading team members with a friend, over the same link as link battles (online or nearby).
// A team member is [dex, nick, shiny, level, ivAtk, ivDef, ivSpe, ivHp, trAtk, trDef, trSpe,
// [moves], bond, exp]; on the wire it is "dex,nick,shiny,level,ivA,ivD,ivS,ivH,trA,trD,trS,m1.m2.m3.m4,exp".
// The newcomer takes the traded one's place in the team, keeps its level, IVs, training and
// moves, and starts with no bond. Your partner can't be traded.
module Trade {
    function toWire(m) {
        var mv = m[11];
        var exp = m.size() > 13 ? m[13] : Lvl.expFor(m[3]);
        return Wire.join([m[0], Wire.clean(m[1]), m[2] ? 1 : 0, m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10],
                          Wire.join([mv[0], mv[1], mv[2], mv[3]], "."), exp], ",");
    }

    function fromWire(s) {
        var p = Wire.split(s, ",");
        if (p.size() < 13) { return null; }
        var n = new [13];
        for (var i = 0; i < 13; i++) {
            if (i == 1 || i == 11) { n[i] = 0; continue; }
            var v = p[i].toNumber();
            if (v == null) { return null; }
            n[i] = v;
        }
        if (n[0] < 1 || n[0] > Dex.COUNT || n[3] < 1 || n[3] > 100) { return null; }
        var mp = Wire.split(p[11], ".");
        var mv = new [4];
        for (var i = 0; i < 4; i++) {
            var x = i < mp.size() ? mp[i].toNumber() : null;
            mv[i] = x == null ? 0 : x;
        }
        return [n[0], p[1], n[2] == 1, n[3], n[4], n[5], n[6], n[7], n[8], n[9], n[10], mv, 0, n[12]];
    }

    function label(m) { return SpriteIndex.name(m[0]).toUpper() + "  " + Tr.t("Lv") + m[3]; }

    // The swap: the newcomer in the traded one's place, registered in the Pokedex.
    function swap(model, idx, newcomer) {
        if (idx < 0 || idx >= model.party.size()) { return false; }
        model.party[idx] = newcomer;
        var n = newcomer[0];
        model.dexReg[(n - 1) / 24] |= 1 << ((n - 1) % 24);
        if (newcomer[2]) { model.dexShiny[(n - 1) / 24] |= 1 << ((n - 1) % 24); }
        model.save();
        return true;
    }
}
