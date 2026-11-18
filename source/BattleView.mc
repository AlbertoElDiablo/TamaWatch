import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The battle screen, after TamaPoke's renderBattle() scaled 466 -> 280: the foe's biome backdrop,
// the foe's box top-left with its sprite top-right, yours bottom-right with your sprite
// bottom-left, and the cream panel with FIGHT / SWITCH / RUN, the move grid or the narration.
class BattleView extends WatchUi.View {

    const FAINT_MS = 700;
    const LUNGE_MS = 260;
    const HIT_MS = 420;
    const MENU_MAIN = 0;
    const MENU_MOVES = 1;
    const MENU_RUN = 3;
    const MENU_SWITCH = 2;
    const MENU_BAG = 4;

    var model;
    var petView;
    var you;
    var foe;
    var hpShown = [0, 0];
    var menu = 0;
    var sel = 0;
    var msgs = [];          // narration still to show (3 lines a page)
    // A turn plays as steps, one action at a time: [msgs, lungeWho, hitWho, hpYou, hpFoe, faintYou, faintFoe]
    var steps = [];
    var stepAt = -1;
    var hpTarget = [0, 0];  // what the HP bars ease toward (the current step's values)
    var gone = [false, false];  // has fainted on screen
    var over = false;
    var won = false;
    var timer = null;
    var frame = 0;
    var lungeUntil = [0, 0];
    var hitUntil = [0, 0];
    var faintUntil = [0, 0];
    var art = [null, null];  // [meta, sheet] for you and the foe
    var back = null;

    // trainer battles (-1 = wild)
    var trainer = -1;
    var hard = false;
    var team = null;        // [[dex, level], ...]
    var foeAt = 0;
    var win = false;        // showing the win screen
    var newBadge = false;
    var trainGain = 0;
    var badgeBmp = null;
    var squad = [];         // your pet first, then the party
    var squadAt = 0;
    var pendingYouSwap = false;
    const BADGE_NAMES = ["Cairn", "Tide", "Spark", "Sprout", "Spore", "Mind", "Ember", "Quake"];

    // A wild foe (trainerIdx -1, foeDex/foeLvl) or a trainer from trainers.json.
    var squadMask = 0xFFFF;  // bit 0 = your pet, bit i+1 = party member i

    // link battles (trainer == -2): the host resolves, the guest plays the result back
    var lobby = null;
    var linkHost = false;
    var peerName = "";
    var foeSquad = [];
    var turn = 0;
    var myAct = null;        // [kind "M"/"S", index]
    var peerAct = null;
    var waitingPeer = false;
    var pendingFoeIdx = -1;
    var pendingYouIdx = -1;
    var petIn = true;

    function initialize(m, pv, foeDex, foeLvl, trainerIdx, isHard, mask) {
        View.initialize();
        initWith(m, pv, foeDex, foeLvl, trainerIdx, isHard, mask);
    }

    function initWith(m, pv, foeDex, foeLvl, trainerIdx, isHard, mask) {
        squadMask = mask;
        model = m;
        repSnap = [m.repExp, m.repLv, [m.repBag[0], m.repBag[1], m.repBag[2], m.repBag[3]]];
        petView = pv;
        trainer = trainerIdx;
        hard = isHard;
        if (trainer == -2) { return; }       // a link battle: setupLink() fills in the rest
        if (trainer >= 0) {
            var t = trainerRow();
            team = trainer == RIVAL ? t[4] : trainerTeam(model, trainer, hard, t[4]);   // a due rematch: stronger
            var top = 0;
            for (var i = 0; i < team.size(); i++) { if (team[i][1] > top) { top = team[i][1]; } }
            buildSquad(top);
            foe = Battle.fromSpecies(team[0][0], team[0][1], hard ? 31 : 16);
            msgs = [t[0] + Tr.t(" wants to battle!"), t[0] + Tr.t(" sends out ") + foe.name + "!", Tr.t("Go, ") + you.name + "!"];
        } else {
            buildSquad(0);
            foe = Battle.fromSpecies(foeDex, foeLvl, 20);
            msgs = [Tr.t("A wild ") + foe.name + Tr.t(" appeared!"), Tr.t("Go, ") + you.name + "!"];
        }
        hpShown = [you.hp, foe.maxHp];
        hpTarget = [you.hp, foe.maxHp];
    }

    // The pet's own combatant (null when it sits this one out) and its HP when the battle began:
    // what it ends with is written back to it (PetModel.afterBattle).
    var petC = null;
    var petStartPct = 100;
    var hpSaved = false;
    // for the result screen: what the battle paid, and the "while you were away" counters as they
    // were before it (a battle's EXP and candy are not news from your activity)
    var expGained = 0;
    var levelUp = false;
    var foodLost = 0;
    var repSnap = null;
    var ranAway = false;        // the friend left: no result screen, back to the lobby
    var squadParty = [];        // per squad member: its index in the party (-1: your partner)

    function notePet(c) {
        petC = c;
        petStartPct = c.hp * 100 / (c.maxHp > 0 ? c.maxHp : 1);
    }

    function savePetHp() {
        if (hpSaved) { return; }
        hpSaved = true;
        if (repSnap != null) {
            model.repExp = repSnap[0];
            model.repLv = repSnap[1];
            model.repBag = repSnap[2];
        }
        // the team members who fought keep their HP too
        for (var k = 0; k < squad.size() && k < squadParty.size(); k++) {
            var pi = squadParty[k];
            if (pi >= 0 && pi < model.party.size()) {
                var c = squad[k];
                var p = c.hp * 100 / (c.maxHp > 0 ? c.maxHp : 1);
                if (p == 0 && c.hp > 0) { p = 1; }
                Care.setHp(model.party[pi], p);
            }
        }
        if (petC == null || model.isEgg()) { return; }
        var pct = petC.hp * 100 / (petC.maxHp > 0 ? petC.maxHp : 1);
        if (pct == 0 && petC.hp > 0) { pct = 1; }
        foodLost = Hp.afterBattle(model, pct, petStartPct);
    }

    // The battle is over (won or lost) and its lines are read: the result screen takes its place.
    function showResult() {
        if (trainer == RIVAL) { Extra.rivalDone(model, won); }       // back in a few days
        awardExp(won);
        savePetHp();
        var mine = [];
        for (var i = 0; i < squad.size(); i++) { mine.add(squad[i].fainted()); }
        var theirs = [];
        if (lobby != null) {
            for (var i = 0; i < foeSquad.size(); i++) { theirs.add(foeSquad[i].fainted()); }
        } else if (trainer >= 0) {
            for (var i = 0; i < team.size(); i++) { theirs.add(i < foeAt || (i == foeAt && foe.fainted())); }
        } else {
            theirs.add(foe.fainted());
        }
        var rv = new BattleResultView(self, mine, theirs);
        WatchUi.switchToView(rv, new BattleResultDelegate(rv), WatchUi.SLIDE_UP);
    }

    function buildSquad(cap) {
        squad = [];
        petIn = (squadMask & 1) != 0;
        squadParty = [];
        if (petIn) { squad.add(Battle.fromPet(model, cap)); squadParty.add(-1); }
        for (var i = 0; i < model.party.size() && squad.size() < 6; i++) {
            if ((squadMask & (1 << (i + 1))) != 0) { squad.add(Battle.fromMember(model.party[i], cap)); squadParty.add(i); }
        }
        if (squad.size() == 0) { squad.add(Battle.fromPet(model, cap)); petIn = true; }
        if (petIn) { notePet(squad[0]); }
        squadAt = 0;
        you = squad[0];
    }

    function nextAlive() {
        for (var i = 0; i < squad.size(); i++) {
            if (i != squadAt && !squad[i].fainted()) { return i; }
        }
        return -1;
    }

    function bringIn(i, voluntary) {
        squadAt = i;
        you = squad[i];
        hpShown[0] = you.hp;
        art[0] = null;
        art[0] = loadArt(you);
        faintUntil[0] = 0;
        gone[0] = false;
        hpTarget[0] = you.hp;
        msgs = [Tr.t("Go, ") + you.name + "!"];
        if (voluntary) {                  // switching costs the turn: the foe acts, after the swap
            steps = [[msgs, -1, -1, you.hp, foe.hp, false, false]];
            actStep(foe, you, Battle.aiChoose(foe, you, hard));
            finishTurn();
        }
    }

    // ---------- link battles ----------

    function setupLink(lobbyView, mine, theirs, name, isHost) {
        lobby = lobbyView;
        linkHost = isHost;
        peerName = name;
        squad = mine;
        squadParty = [];                    // LinkView.mySquad(): the pet, then the party in order
        for (var i = 0; i < squad.size(); i++) { squadParty.add(i - 1); }
        squadAt = 0;
        you = squad[0];
        foeSquad = theirs;
        foeAt = 0;
        foe = foeSquad[0];
        notePet(squad[0]);                  // LinkView.mySquad(): your pet first
        hpShown = [you.hp, foe.hp];
        hpTarget = [you.hp, foe.hp];
        msgs = [peerName + Tr.t(" wants to battle!"), peerName + Tr.t(" sends out ") + foe.name + "!", Tr.t("Go, ") + you.name + "!"];
        if (isHost && lobby.earlyAct != null) { onLinkMsg("ACT", lobby.earlyAct); lobby.earlyAct = null; }
    }

    function nextAliveFoe() {
        for (var i = 0; i < foeSquad.size(); i++) {
            if (i != foeAt && !foeSquad[i].fainted()) { return i; }
        }
        return -1;
    }

    function switchMine(i) {
        squadAt = i;
        you = squad[i];
        art[0] = null;
        art[0] = loadArt(you);
        hpShown[0] = you.hp;
        hpTarget[0] = you.hp;
        gone[0] = false;
        faintUntil[0] = 0;
    }

    function switchFoe(i) {
        foeAt = i;
        foe = foeSquad[i];
        art[1] = null;
        art[1] = loadArt(foe);
        hpShown[1] = foe.hp;
        hpTarget[1] = foe.hp;
        gone[1] = false;
        faintUntil[1] = 0;
    }

    // Your choice for this turn: the guest sends it, the host waits for the guest's.
    function linkAct(kind, n) {
        menu = MENU_MAIN;
        sel = 0;
        if (linkHost) {
            myAct = [kind, n];
            if (peerAct == null) { waitingPeer = true; msgs = [Tr.t("Waiting for ") + peerName + "..."]; }
            else { resolveLink(); }
        } else {
            lobby.client.send("ACT", turn + "|" + kind + "|" + n);
            waitingPeer = true;
            msgs = [Tr.t("Waiting for ") + peerName + "..."];
        }
    }

    function onLinkMsg(type, parts) {
        if (type.equals("ACT") && linkHost && parts.size() >= 7 && parts[4].toNumber() == turn) {
            peerAct = [parts[5], parts[6].toNumber()];
            if (myAct != null) { resolveLink(); }
        } else if (type.equals("RES") && !linkHost && parts.size() >= 16) {
            applyRes(parts);
        }
        WatchUi.requestUpdate();
    }

    function peerLeft() {
        ranAway = true;
        waitingPeer = false;
        over = true;
        won = false;
        steps = [];
        stepAt = -1;
        msgs = [peerName + Tr.t(" left the battle.")];
        savePetHp();
    }

    // The host's turn: switches first, then both moves in speed order, then chip damage; the
    // result is played here and sent to the guest.
    function resolveLink() {
        waitingPeer = false;
        steps = [];
        msgs = [];
        var swH = -1;
        var swG = -1;
        if (myAct[0].equals("S")) {
            swH = myAct[1];
            switchMine(swH);
            steps.add([[Tr.t("Go, ") + you.name + "!"], -1, -1, you.hp, foe.hp, false, false]);
        }
        if (peerAct[0].equals("S")) {
            swG = peerAct[1];
            switchFoe(swG);
            steps.add([[peerName + Tr.t(" sends out ") + foe.name + "!"], -1, -1, you.hp, foe.hp, false, false]);
        }
        var localSwitchSteps = steps.size();
        var mh = myAct[0].equals("M") ? you.moves[myAct[1]] : 0;
        var mg = peerAct[0].equals("M") ? foe.moves[peerAct[1]] : 0;
        if (mh != 0 && mg != 0) {
            var hostFirst = Battle.movesFirst(you, mh, foe, mg);
            var a = hostFirst ? you : foe;
            var b = hostFirst ? foe : you;
            actStep(a, b, hostFirst ? mh : mg);
            if (!b.fainted()) { actStep(b, a, hostFirst ? mg : mh); }
        } else if (mh != 0) {
            actStep(you, foe, mh);
        } else if (mg != 0) {
            actStep(foe, you, mg);
        }
        if (!you.fainted() && !foe.fainted()) {
            chipStep(you);
            chipStep(foe);
        }
        finishTurn();
        lobby.client.send("RES", encodeRes(swH, swG, localSwitchSteps));
        turn++;
        myAct = null;
        peerAct = null;
    }

    // turn|swH|swG|nextH|nextG|over|winner|hpsH|hpsG|ailH|ailG|steps
    // steps: "line^line~lunge~hit~hpH~hpG~faintH~faintG" joined by "#" (host's view: side 0 = host).
    function encodeRes(swH, swG, skip) {
        var hpsH = [];
        var ailH = [];
        for (var i = 0; i < squad.size(); i++) { hpsH.add(squad[i].hp); ailH.add(squad[i].ailment); }
        var hpsG = [];
        var ailG = [];
        for (var i = 0; i < foeSquad.size(); i++) { hpsG.add(foeSquad[i].hp); ailG.add(foeSquad[i].ailment); }
        var st = [];
        for (var i = skip; i < steps.size(); i++) {
            var lines = [];
            var ls = steps[i][0];
            for (var k = 0; k < ls.size(); k++) {
                if (!ls[k].equals("You won!") && !ls[k].equals("You lost...")) { lines.add(ls[k]); }
            }
            st.add(Wire.join(lines, "^") + "~" + steps[i][1] + "~" + steps[i][2] + "~" + steps[i][3] + "~" + steps[i][4] +
                   "~" + (steps[i][5] ? 1 : 0) + "~" + (steps[i][6] ? 1 : 0));
        }
        return Wire.join([turn, swH, swG, pendingYouIdx, pendingFoeIdx, over ? 1 : 0, over ? (won ? "H" : "G") : "-",
                          Wire.join(hpsH, ","), Wire.join(hpsG, ","), Wire.join(ailH, ","), Wire.join(ailG, ","),
                          Wire.join(st, "#")], "|");
    }

    // The guest plays the host's turn from its own side: sides and HP are mirrored, and its own
    // switch lines and result are written here.
    function applyRes(p) {
        if (p[4].toNumber() != turn) { return; }
        waitingPeer = false;
        var swH = p[5].toNumber();
        var swG = p[6].toNumber();
        steps = [];
        if (swG >= 0) { switchMine(swG); steps.add([[Tr.t("Go, ") + you.name + "!"], -1, -1, you.hp, foe.hp, false, false]); }
        if (swH >= 0) { switchFoe(swH); steps.add([[peerName + Tr.t(" sends out ") + foe.name + "!"], -1, -1, you.hp, foe.hp, false, false]); }
        var raw = p[15];
        if (raw.length() > 0) {
            var list = Wire.split(raw, "#");
            for (var i = 0; i < list.size(); i++) {
                var f = Wire.split(list[i], "~");
                if (f.size() < 7) { continue; }
                var lunge = f[1].toNumber();
                var hit = f[2].toNumber();
                steps.add([f[0].length() > 0 ? Wire.split(f[0], "^") : [],
                           lunge >= 0 ? 1 - lunge : -1, hit >= 0 ? 1 - hit : -1,
                           f[4].toNumber(), f[3].toNumber(), f[6].equals("1"), f[5].equals("1")]);
            }
        }
        var hpsH = Wire.split(p[11], ",");
        var hpsG = Wire.split(p[12], ",");
        var ailH = Wire.split(p[13], ",");
        var ailG = Wire.split(p[14], ",");
        for (var i = 0; i < squad.size() && i < hpsG.size(); i++) { squad[i].hp = hpsG[i].toNumber(); squad[i].ailment = ailG[i].toNumber(); }
        for (var i = 0; i < foeSquad.size() && i < hpsH.size(); i++) { foeSquad[i].hp = hpsH[i].toNumber(); foeSquad[i].ailment = ailH[i].toNumber(); }
        over = p[9].equals("1");
        won = p[10].equals("G");
        pendingYouIdx = p[8].toNumber();
        pendingFoeIdx = p[7].toNumber();
        if (steps.size() == 0) { steps.add([[], -1, -1, you.hp, foe.hp, false, false]); }
        if (over) {
            var last = steps[steps.size() - 1];
            last[0] = last[0].addAll([won ? Tr.t("You won!") : Tr.t("You lost...")]);
        }
        turn++;
        menu = MENU_MAIN;
        sel = 0;
        stepAt = 0;
        playStep(0);
    }

    // trainer RIVAL (Gyms.mc) is the rival (rivalRow, its team built for this battle); 0-12 are
    // trainers.json's
    var rivalRow = null;
    function trainerRow() {
        if (trainer == RIVAL) {
            if (rivalRow == null) { rivalRow = [RIVAL_NAME, "", 0, -1, rivalTeam(model)]; }
            return rivalRow;
        }
        return WatchUi.loadResource(Rez.JsonData.trainers)[trainer];
    }

    function onShow() {
        // free the home screen's sheet and scene while the battle holds its own
        petView.bmp = null;
        petView.meta = null;
        petView.dex = -1;
        petView.bg = null;
        petView.bgBiome = -1;
        if (art[0] == null) {
            art = [loadArt(you), loadArt(foe)];
            var h = System.getClockTime().hour;
            backNight = h < 6 || h >= 20;
            back = WatchUi.loadResource(battleBack(Scenes.biomeFor(foe.dex)));
        }
        timer = new Timer.Timer();
        timer.start(method(:tick), 100, true);
    }

    function onHide() {
        if (timer != null) { timer.stop(); timer = null; }   // the timer points back at this view: drop it, or neither is ever freed
    }

    function tick() as Void {
        frame++;
        var busy = false;
        for (var i = 0; i < 2; i++) {        // HP bars ease toward the current step's value
            var real = hpTarget[i];
            var diff = real - hpShown[i];
            if (diff != 0) {
                busy = true;
                var step = diff / 5;
                if (step == 0) { step = diff > 0 ? 1 : -1; }
                hpShown[i] += step;
            }
        }
        // Battery: full speed while something moves (HP, lunges, hits, faints), else ~3 a second
        var now = System.getTimer();
        for (var i = 0; i < 2; i++) {
            if (now < lungeUntil[i] || now < hitUntil[i] || now < faintUntil[i]) { busy = true; }
        }
        if (busy || frame % 3 == 0) { WatchUi.requestUpdate(); }
    }

    // [meta, sheet or shiny atlas, y offset in it]
    function loadArt(c) {
        if (c.foreign) { return null; }           // another region's creature: drawStandIn
        var m = WatchUi.loadResource(SpriteIndex.data(c.dex));
        var a = SpriteIndex.art(m, c.dex, c.shiny);
        return [m, a[0], a[1]];
    }

    var backNight = false;

    // One bitmap per biome: day on top, night below (150 px each).
    function battleBack(biome) {
        var ids = [Rez.Drawables.battle_0, Rez.Drawables.battle_1, Rez.Drawables.battle_2, Rez.Drawables.battle_3,
                   Rez.Drawables.battle_4, Rez.Drawables.battle_5, Rez.Drawables.battle_6];
        return ids[biome];
    }

    // ---------- turns ----------

    // ---------- the bag: fruit in battle (it costs the turn, as an item does in FireRed) ----------
    // apple: 20% of HP back; blue berry: no more poison or burn; orange: awake, no paralysis,
    // ice or confusion. Fruit that would do nothing is kept, with a word why.
    function useItem(i) {
        if (i < 0 || i > 2 || model.bag[i] <= 0) { return; }
        var names = [Tr.t("Apple"), Tr.t("Blue berry"), Tr.t("Orange")];
        var did = false;
        if (i == 0 && you.hp < you.maxHp) {
            Battle.heal(you, you.maxHp / 5 > 0 ? you.maxHp / 5 : 1);
            did = true;
        } else if (i == 1 && (you.ailment == Moves.AIL_POISON || you.ailment == Moves.AIL_BURN)) {
            you.ailment = Moves.AIL_NONE;
            did = true;
        } else if (i == 2 && (you.ailment == Moves.AIL_SLEEP || you.ailment == Moves.AIL_PARA ||
                              you.ailment == Moves.AIL_FREEZE || you.confuseTurns > 0)) {
            if (you.ailment != Moves.AIL_POISON && you.ailment != Moves.AIL_BURN) { you.ailment = Moves.AIL_NONE; }
            you.confuseTurns = 0;
            did = true;
        }
        menu = MENU_MAIN;
        sel = 0;
        if (!did) { msgs = [Tr.t("It won't have any effect.")]; return; }
        model.bag[i] -= 1;
        model.save();
        steps = [[[Tr.f("{0} ate the {1}!", [you.name, names[i]]), i == 0 ? Tr.t("Its HP went up!") : Tr.t("It feels better!")],
                  -1, -1, you.hp, foe.hp, false, false]];
        actStep(foe, you, Battle.aiChoose(foe, you, hard));       // the foe still gets its turn
        if (!you.fainted() && !foe.fainted()) {
            chipStep(you);
            chipStep(foe);
        }
        finishTurn();
    }

    function useMove(slot) {
        var mv = you.moves[slot];
        if (mv == 0) { return; }
        if (lobby != null) { linkAct("M", slot); return; }
        var foeMove = Battle.aiChoose(foe, you, hard);
        var youFirst = Battle.movesFirst(you, mv, foe, foeMove);
        var a = youFirst ? you : foe;
        var b = youFirst ? foe : you;
        var ma = youFirst ? mv : foeMove;
        var mb = youFirst ? foeMove : mv;
        steps = [];
        actStep(a, b, ma);
        if (!b.fainted()) { actStep(b, a, mb); }
        if (!you.fainted() && !foe.fainted()) {
            chipStep(you);
            chipStep(foe);
        }
        finishTurn();
    }

    function sideOf(c) { return c == you ? 0 : 1; }

    // One action becomes one step: its lines, who lunges, who is hit, and the HP after it.
    function actStep(a, b, mv) {
        var before = [you.hp, foe.hp];
        msgs = [];
        var lg = Battle.act(a, b, mv);
        narrate(a, b, lg);
        var lunge = lg.damage > 0 && !lg.hurtSelf ? sideOf(a) : -1;
        var hit = you.hp < before[0] ? 0 : (foe.hp < before[1] ? 1 : -1);
        addStep(lunge, hit);
    }

    function chipStep(c) {
        var before = c.hp;
        msgs = [];
        var lg = Battle.endTurn(c);
        if (lg.damage == 0) { return; }
        narrate(c, c, lg);
        addStep(-1, c.hp < before ? sideOf(c) : -1);
    }

    function addStep(lunge, hit) {
        if (msgs.size() == 0) { return; }
        steps.add([msgs, lunge, hit, you.hp, foe.hp, false, false]);
    }

    // Faints and the outcome join the last step; then play from the first one.
    function finishTurn() {
        if (lobby == null) { turn++; }
        msgs = [];
        afterFaints();
        if (steps.size() == 0) { steps.add([[], -1, -1, you.hp, foe.hp, false, false]); }
        var last = steps[steps.size() - 1];
        last[0] = last[0].addAll(msgs);
        last[5] = you.fainted();
        last[6] = foe.fainted();
        menu = MENU_MAIN;
        sel = 0;
        stepAt = 0;
        playStep(0);
    }

    function playStep(i) {
        var st = steps[i];
        var now = System.getTimer();
        msgs = st[0];
        if (st[1] >= 0) { lungeUntil[st[1]] = now + LUNGE_MS; }
        if (st[2] >= 0) { hitUntil[st[2]] = now + LUNGE_MS + HIT_MS; }
        hpTarget = [st[3], st[4]];
        if (st[5]) { faintUntil[0] = now + FAINT_MS; gone[0] = true; }
        if (st[6]) { faintUntil[1] = now + FAINT_MS; gone[1] = true; }
        // battle EXP duel by duel (as it plays, on both watches of a link battle): a foe that
        // faints pays its whole worth to the one of yours on the field; one of yours that faints
        // gets a tenth of the worth of the foe that beat it
        if (st[6] && koSeen.indexOf(foe) < 0) { koSeen.add(foe); credit(squadAt, foeValue(foe)); }
        if (st[5] && downSeen.indexOf(you) < 0) { downSeen.add(you); credit(squadAt, foeValue(foe) / 10); }
    }

    var koSeen = [];
    var downSeen = [];
    var koExp = [];             // EXP earned so far, per squad member
    function credit(k, n) {
        while (koExp.size() < squad.size()) { koExp.add(0); }
        if (k >= 0 && k < koExp.size()) { koExp[k] += n < 1 ? 1 : n; }
    }

    // What beating c is worth (FireRed): its species' base yield x its level / 7, x1.5 from a
    // trainer or a friend, x3 from a hard gym.
    function foeValue(c) {
        var v = yieldOf(c) * c.level / 7;
        if (lobby != null) { v = v * 3 / 2; }
        else if (trainer >= 0) { v = hard ? v * 3 : v * 3 / 2; }
        return v < 1 ? 1 : v;
    }

    // Who fainted, who comes in next, and whether it is over.
    function afterFaints() {
        if (foe.fainted()) { msgs.add(foe.name + Tr.t(" fainted!")); }
        if (you.fainted()) { msgs.add(you.name + Tr.t(" fainted!")); }
        var foeLeft = foe.fainted() && (lobby != null ? nextAliveFoe() >= 0 : (trainer >= 0 && foeAt + 1 < team.size()));
        var youLeft = you.fainted() && nextAlive() >= 0;
        if (foe.fainted() && !foeLeft) {
            over = true;
            won = true;
            if (trainer >= 0) { finishTrainerWin(); } else { msgs.add(Tr.t("You won!")); }
            savePetHp();
        } else if (you.fainted() && !youLeft) {
            over = true;
            won = false;
            msgs.add(Tr.t("You lost..."));
            savePetHp();
        } else if (lobby != null) {
            pendingFoeIdx = foeLeft ? nextAliveFoe() : -1;   // each side's next one comes in
            pendingYouIdx = youLeft ? nextAlive() : -1;
        } else {
            pendingSwap = foeLeft;
            pendingYouSwap = youLeft;
        }
    }

    const AIL_HIT = ["", " is paralysed!", " was burned!", " was poisoned!", " fell asleep!", " was frozen solid!", " became confused!"];
    const STAT_NAMES = ["ATTACK", "DEFENSE", "SP. ATK", "SP. DEF", "SPEED"];

    // Turns a TurnLog into lines; nothing is recomputed.
    function narrate(actor, target, lg) {
        if (lg.skipped) {
            if (actor.fainted()) { return; }
            if (actor.ailment == Moves.AIL_SLEEP) { msgs.add(actor.name + Tr.t(" is fast asleep.")); }
            else if (actor.ailment == Moves.AIL_FREEZE) { msgs.add(actor.name + Tr.t(" is frozen solid!")); }
            else if (actor.ailment == Moves.AIL_PARA) { msgs.add(actor.name + Tr.t(" can't move!")); }
            else { msgs.add(actor.name + Tr.t(" must recharge!")); }
            return;
        }
        if (actor == target && lg.inflicted != 0) {    // end-of-turn chip
            msgs.add(actor.name + Tr.t(" is hurt by its ") + (lg.inflicted == Moves.AIL_BURN ? Tr.t("burn!") : Tr.t("poison!")));
            return;
        }
        if (lg.hurtSelf) { msgs.add(actor.name + Tr.t(" hurt itself in confusion!")); return; }
        if (lg.charged) { msgs.add(actor.name + Tr.t(" is charging up!")); return; }
        msgs.add(actor.name + Tr.t(" used ") + Moves.name(lg.move) + "!");
        if (lg.missed) {
            // poor care: say which need made it miss
            var why = ["But it missed!", "Missed because it's hungry!", "Missed because it wants a bath!", "Missed because it wants to train!"];
            msgs.add(Tr.t(why[lg.missWhy >= 0 && lg.missWhy <= 3 ? lg.missWhy : 0]));
            return;
        }
        if (lg.immune) { msgs.add(Tr.t("It had no effect...")); return; }
        if (lg.healed) { msgs.add(actor.name + Tr.t(" regained health!")); return; }
        if (lg.stageMask != 0) {
            for (var i = 0; i < 5; i++) {
                if ((lg.stageMask & Battle.STAGE_BITS[i]) != 0) {
                    var who = Moves.get(lg.move)[9] == Moves.TG_SELF ? actor : target;
                    var how = lg.stageDelta > 1 ? Tr.t(" rose sharply!") : (lg.stageDelta > 0 ? Tr.t(" rose!") : (lg.stageDelta < -1 ? Tr.t(" fell harshly!") : Tr.t(" fell!")));
                    msgs.add(Tr.f("{0}'s {1}{2}", [who.name, Tr.t(STAT_NAMES[i]), how]));
                }
            }
            return;
        }
        if (lg.hits > 1) { msgs.add(Tr.t("Hit ") + lg.hits + Tr.t(" times!")); }
        if (lg.crit) { msgs.add(Tr.t("A critical hit!")); }
        if (lg.effPct > 100) { msgs.add(Tr.t("It's super effective!")); }
        else if (lg.effPct < 100 && lg.effPct > 0) { msgs.add(Tr.t("It's not very effective...")); }
        if (lg.inflicted != 0) { msgs.add(target.name + Tr.t(AIL_HIT[lg.inflicted])); }
    }

    var pendingSwap = false;

    // The trainer's next creature steps in.
    function swapFoe() {
        pendingSwap = false;
        foeAt++;
        foe = Battle.fromSpecies(team[foeAt][0], team[foeAt][1], hard ? 31 : 16);
        hpShown[1] = foe.maxHp;
        hpTarget[1] = foe.maxHp;
        gone[1] = false;
        art[1] = null;
        art[1] = loadArt(foe);
        faintUntil[1] = 0;
        msgs = [trainerRow()[0] + Tr.t(" sends out ") + foe.name + "!"];
    }

    // EXP for the pet when it took part: wild foes, gym leaders (their whole team), link battles.
    // At the end (BattleView.showResult): each creature gets what it earned duel by duel (koExp).
    // Your partner's goes through the wild-battle daily limit and not to the team; a team member's
    // straight to it. The bench gets nothing from a battle.
    var memberExp = [];         // [[name, EXP], ...] of the team members who earned some
    function awardExp(didWin) {
        if (model.isEgg()) { return; }
        var kind = lobby != null ? 2 : (trainer >= 0 ? 1 : 0);
        var before = model.level();
        for (var k = 0; k < koExp.size() && k < squadParty.size(); k++) {
            var n = koExp[k];
            if (n <= 0) { continue; }
            var pi = squadParty[k];
            if (pi < 0) {
                n = model.battleGain(kind, n, didWin);
                if (squad[k] == lead()) { expGained = n; }
            } else if (pi < model.party.size()) {
                var m = model.party[pi];
                while (m.size() < 14) { m.add(m.size() == 12 ? 0 : Lvl.expFor(m[3])); }
                var e = m[13] + n;
                if (e > Lvl.expFor(Lvl.MAX)) { e = Lvl.expFor(Lvl.MAX); }
                m[13] = e;
                m[3] = Lvl.levelFor(e);
                memberExp.add([model.memberName(m).toUpper(), n]);
                if (squad[k] == lead()) { expGained = n; }
            }
        }
        levelUp = model.level() > before;
        model.save();
    }

    // who the result screen shows on the left: your partner when it fought, else the last one out
    function lead() { return petC != null ? petC : you; }

    // A gym badge the first time, and training into a stat with room (TamaPoke's gym-win reward).
    // A species' base EXP yield (dex.json column 13; another region's creature: 100).
    function baseYield(dex) {
        if (dex < 1 || dex > Dex.COUNT) { return 100; }
        var r = Dex.row(dex);
        return r.size() > 13 ? r[13] : 64;
    }
    function yieldOf(c) { return c.foreign ? 100 : baseYield(c.dex); }

    function finishTrainerWin() {
        var t = trainerRow();
        var badge = t[3];
        newBadge = badge >= 0 && !model.hasBadge(badge, hard);
        if (trainer != RIVAL && !model.hasBadge(trainer, hard)) { model.winBadge(trainer, hard); }   // unlocks the next trainer
        if (trainer != RIVAL) { Extra.beaten(trainer); }             // a rematch is due in 2 days
        var amt = hard ? 2 + model.rnd(2) : 1 + model.rnd(2);          // slow and steady
        trainGain = petIn ? model.rewardTraining(amt) : 0;   // only the live pet, and only if it fought
        model.save();
        msgs.add(Tr.t("You beat ") + t[0] + "!");
        model.giveFruit(model.FOOD_CANDY, 1);
        msgs.add(Tr.t("You got a candy!"));
        if (badge >= 0) { badgeBmp = WatchUi.loadResource(Rez.Drawables.badges); }
    }



    // START on the narration: next page, the trainer's next creature, the win screen, or leave.
    function advance() {
        if (msgs.size() > 3) { msgs = msgs.slice(3, null); return false; }
        if (stepAt >= 0 && stepAt + 1 < steps.size()) {
            stepAt++;
            playStep(stepAt);
            return false;
        }
        steps = [];
        stepAt = -1;
        msgs = [];
        if (pendingSwap) { swapFoe(); return false; }
        if (pendingYouSwap) { pendingYouSwap = false; bringIn(nextAlive(), false); return false; }
        if (pendingFoeIdx >= 0) {
            var fi = pendingFoeIdx;
            pendingFoeIdx = -1;
            switchFoe(fi);
            msgs = [peerName + Tr.t(" sends out ") + foe.name + "!"];
            return false;
        }
        if (pendingYouIdx >= 0) {
            var yi = pendingYouIdx;
            pendingYouIdx = -1;
            switchMine(yi);
            msgs = [Tr.t("Go, ") + you.name + "!"];
            return false;
        }
        return over;
    }

    // ---------- drawing ----------

    const UI_BG_DAY = 0xFFFFFF;
    const UI_INK = 0x000055;
    const UI_TRACK = 0xAAAAAA;
    const UI_BAR_OK = 0x55FF55;
    const UI_BAR_WARN = 0xFFAA00;
    const UI_BAR_BAD = 0xFF0000;
    const CELL_W = 94;
    const CELL_H = 26;
    const GRID_X = 44;      // the 2x2 grid's bottom corners stay inside the circle
    const GRID_Y = 158;

    function cellX(i) { return GRID_X + (i % 2) * (CELL_W + 4); }
    function cellY(i) { return GRID_Y + (i / 2) * (CELL_H + 4); }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (win) { drawWin(dc, w, h); return; }
        if (back != null) {
            dc.setClip(0, 4, w, 150);
            dc.drawBitmap(0, 4 - (backNight ? 150 : 0), back);
            dc.clearClip();
        }
        dc.setColor(UI_BG_DAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 152, w, h - 152);
        side(dc, 65, 41, 216, 96, foe, 1);       // boxes placed so every corner is on screen
        side(dc, 137, 106, 66, 144, you, 0);
        if (msgs.size() > 0) {
            panelBox(dc);
            // a line too wide for the box goes on over two (or more): nothing is cut, the rest
            // shows on the next page (3 lines a page)
            msgs = wrapLines(dc, msgs, 2 * CELL_W + 4 - 14);
            dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < 3 && i < msgs.size(); i++) {
                dc.drawText(w / 2, capY(Graphics.FONT_XTINY, GRID_Y + 10 + i * 17), Graphics.FONT_XTINY, msgs[i], Graphics.TEXT_JUSTIFY_CENTER);
            }
            dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            if (!waitingPeer) { dc.drawText(w / 2, capY(Graphics.FONT_XTINY, GRID_Y + 61), Graphics.FONT_XTINY, Tr.t("- START -"), Graphics.TEXT_JUSTIFY_CENTER); }
        } else if (menu == MENU_SWITCH) {
            for (var i = 0; i < 4; i++) {
                var mi = i + (i >= squadAt ? 1 : 0);
                if (mi < squad.size()) {
                    var c = squad[mi];
                    cell(dc, i, fit(dc, c.name, CELL_W - 30) + " " + c.hp, sel == i, c.fainted() ? UI_TRACK : UI_BG_DAY, c.fainted());
                } else {
                    cell(dc, i, "", false, UI_TRACK, true);
                }
            }
        } else if (menu == MENU_MAIN) {
            cell(dc, 0, Tr.t("FIGHT"), sel == 0, UI_BG_DAY, false);
            cell(dc, 1, Tr.t("BAG"), sel == 1, UI_BG_DAY, lobby != null);       // not in link battles
            cell(dc, 2, Tr.t("POKEMON"), sel == 2, UI_TRACK, squad.size() < 2);
            cell(dc, 3, Tr.t("RUN"), sel == 3, UI_TRACK, false);
        } else if (menu == MENU_BAG) {
            var names = [Tr.t("Apple"), Tr.t("Blue berry"), Tr.t("Orange")];
            for (var i = 0; i < 3; i++) {
                cell(dc, i, fit(dc, names[i], CELL_W - 26) + " x" + model.bag[i], sel == i, UI_BG_DAY, model.bag[i] == 0);
            }
            cell(dc, 3, Tr.t("BACK"), sel == 3, UI_TRACK, false);
        } else if (menu == MENU_RUN) {
            wideCell(dc, Tr.t("RUN?"), false, UI_BG_DAY);
            cell(dc, 2, Tr.t("YES"), sel == 0, UI_BAR_BAD, false);
            cell(dc, 3, Tr.t("NO"), sel == 1, UI_BAR_OK, false);
        } else {
            for (var i = 0; i < 4; i++) { moveCell(dc, i); }
            // TamaPoke's back pill under the grid
            dc.setColor(UI_TRACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(w / 2 - 44, GRID_Y + 62, 88, 18, 6);
            dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(w / 2 - 44, GRID_Y + 62, 88, 18, 6);
            dc.drawText(w / 2, GRID_Y + 62, Graphics.FONT_XTINY, Tr.t("BACK"), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // After TamaPoke's renderWin(): who you beat, the badge (a gold ring on hard), the count,
    // and the training it earned.
    function drawWin(dc, w, h) {
        var cx = w / 2;
        var t = trainerRow();
        dc.setColor(UI_BG_DAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, w, h);   // the background fills the screen
        dc.setColor(UI_BAR_WARN, Graphics.COLOR_TRANSPARENT);
        var wt = Tr.t("You win!");
        var wf = Fit.font(dc, wt, 170, [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY]);
        dc.drawText(cx, 26, wf, wt, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 64, Graphics.FONT_XTINY, Fit.trim(dc, t[0] + Tr.t(" defeated!"), 190, Graphics.FONT_XTINY), Graphics.TEXT_JUSTIFY_CENTER);
        var badge = t[3];
        var by = 122;
        if (badge >= 0) {
            dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);   // TamaPoke's ring around the badge
            dc.setPenWidth(hard ? 5 : 3);
            dc.drawCircle(cx, by, 33);
            dc.setPenWidth(1);
            if (badgeBmp != null) {             // badge i is at x = 48 * i in the strip
                dc.setClip(cx - 24, by - 24, 48, 48);
                dc.drawBitmap(cx - 24 - 48 * badge, by - 24, badgeBmp);
                dc.clearClip();
            }
            if (newBadge) {
                dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, by + 38, Graphics.FONT_XTINY, Tr.t("NEW BADGE!"), Graphics.TEXT_JUSTIFY_CENTER);
            }
            dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, by + 54, Graphics.FONT_XTINY, Tr.t("BADGES ") + model.badgeCount(hard) + "/8", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(cx, by - 8, Graphics.FONT_SMALL, t[0], Graphics.TEXT_JUSTIFY_CENTER);
        }
        var statNames = [Tr.t("STRENGTH"), Tr.t("DEFENSE"), Tr.t("SPEED")];
        dc.setColor(trainGain > 0 ? 0x00AA00 : TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 196, Graphics.FONT_XTINY, trainGain > 0 ? statNames[model.lastTrained] + " +" + Extra.fmt(trainGain) : Tr.t("Fully trained"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 220, Graphics.FONT_XTINY, Tr.t("START: back"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Lines wider than maxW split at spaces into lines that fit (unchanged when all fit).
    function wrapLines(dc, lines, maxW) {
        var f = Graphics.FONT_XTINY;
        var ok = true;
        for (var i = 0; i < lines.size(); i++) {
            if (dc.getTextWidthInPixels(lines[i], f) > maxW) { ok = false; break; }
        }
        if (ok) { return lines; }
        var out = [];
        for (var i = 0; i < lines.size(); i++) {
            var words = Wire.split(lines[i], " ");
            var cur = "";
            for (var k = 0; k < words.size(); k++) {
                var t = cur.length() == 0 ? words[k] : cur + " " + words[k];
                if (cur.length() > 0 && dc.getTextWidthInPixels(t, f) > maxW) {
                    out.add(cur);
                    cur = words[k];
                } else {
                    cur = t;
                }
            }
            if (cur.length() > 0) { out.add(cur); }
            // a message that would run over onto the next page starts on that page instead
            if (i + 1 < lines.size()) {
                var need = dc.getTextWidthInPixels(lines[i + 1], f) > maxW ? 2 : 1;
                var room = 3 - out.size() % 3;
                if (room < 3 && need > room) { for (var k = 0; k < room; k++) { out.add(""); } }
            }
        }
        return out;
    }

    function panelBox(dc) {
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(GRID_X, GRID_Y - 2, 2 * CELL_W + 4, 2 * CELL_H + 22, 8);
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(GRID_X, GRID_Y - 2, 2 * CELL_W + 4, 2 * CELL_H + 22, 8);
    }

    function ring(dc, x, y, cw, ch, on) {
        dc.setColor(on ? 0xFF0000 : UI_INK, Graphics.COLOR_TRANSPARENT);
        if (on) {
            dc.setPenWidth(3);
            dc.drawRoundedRectangle(x - 1, y - 1, cw + 2, ch + 2, 7);
            dc.setPenWidth(1);
        } else {
            dc.drawRoundedRectangle(x, y, cw, ch, 6);
        }
    }

    function wideCell(dc, text, on, fill) {
        var cw = 2 * CELL_W + 4;
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(GRID_X, GRID_Y, cw, CELL_H, 6);
        ring(dc, GRID_X, GRID_Y, cw, CELL_H, on);
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(GRID_X + cw / 2, capY(Graphics.FONT_XTINY, GRID_Y + CELL_H / 2), Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function cell(dc, i, text, on, fill, dim) {
        var x = cellX(i);
        var y = cellY(i);
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, CELL_W, CELL_H, 6);
        ring(dc, x, y, CELL_W, CELL_H, on);
        dc.setColor(dim ? 0x555555 : UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + CELL_W / 2, capY(Graphics.FONT_XTINY, y + CELL_H / 2), Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Move name and a type chip; "+" when it gets the same-type bonus.
    function moveCell(dc, i) {
        var x = cellX(i);
        var y = cellY(i);
        var mv = you.moves[i];
        dc.setColor(mv != 0 ? UI_BG_DAY : UI_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, CELL_W, CELL_H, 6);
        ring(dc, x, y, CELL_W, CELL_H, i == sel);
        if (mv == 0) { return; }
        // just the move's name, centred in its button
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + CELL_W / 2, capY(Graphics.FONT_XTINY, y + CELL_H / 2), Graphics.FONT_XTINY,
                    fit(dc, Moves.name(mv), CELL_W - 8), Graphics.TEXT_JUSTIFY_CENTER);
    }

    function fit(dc, text, maxW) {
        while (text.length() > 3 && dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) > maxW) {
            text = text.substring(0, text.length() - 1);
        }
        return text;
    }

    // One side: the info box (name, level, HP bar, status) and the creature with its
    // lunge / hit-shake / faint-sink offsets.
    function side(dc, tx, ty, sx, footY, c, who) {
        var now = System.getTimer();
        dc.setColor(UI_BG_DAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(tx - 5, ty - 5, 128, 38, 6);       // 128 wide: inside the round screen
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(tx - 5, ty - 5, 128, 38, 6);
        // the whole name on top (the status, if any, at its right); the level on the HP line
        var ail = c.ailment != Moves.AIL_NONE ? Tr.t(Moves.AIL_NAMES[c.ailment]) : "";
        var ailW = ail.length() > 0 ? dc.getTextWidthInPixels(ail, Graphics.FONT_XTINY) + 4 : 0;
        dc.drawText(tx, ty - 4, Graphics.FONT_XTINY, fit(dc, c.name, 118 - ailW), Graphics.TEXT_JUSTIFY_LEFT);
        var lv = Tr.t("Lv") + c.level;
        var lvW = dc.getTextWidthInPixels(lv, Graphics.FONT_XTINY);
        dc.drawText(tx + 118, ty + 13, Graphics.FONT_XTINY, lv, Graphics.TEXT_JUSTIFY_RIGHT);
        var bw = 118 - 22 - lvW - 4;
        var shown = hpShown[who];
        var fw = c.maxHp > 0 ? (bw - 2) * shown / c.maxHp : 0;
        var col = shown * 2 > c.maxHp ? UI_BAR_OK : (shown * 4 > c.maxHp ? UI_BAR_WARN : UI_BAR_BAD);
        dc.setColor(UI_BAR_WARN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx, ty + 13, Graphics.FONT_XTINY, Tr.t("HP"), Graphics.TEXT_JUSTIFY_LEFT);
        // a solid bar with an outline, readable on the transflective screen
        dc.setColor(UI_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(tx + 22, ty + 16, bw, 10);
        if (fw > 0) {
            dc.setColor(col == UI_BAR_OK ? 0x00AA00 : col, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(tx + 23, ty + 17, fw, 8);
        }
        dc.setColor(UI_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(tx + 22, ty + 16, bw, 10);
        if (ail.length() > 0) {
            dc.setColor(UI_BAR_BAD, Graphics.COLOR_TRANSPARENT);
            dc.drawText(tx + 118, ty - 4, Graphics.FONT_XTINY, ail, Graphics.TEXT_JUSTIFY_RIGHT);
        }

        var ox = 0;
        var oy = 0;
        if (now < faintUntil[who]) {
            oy += (FAINT_MS - (faintUntil[who] - now)) * 40 / FAINT_MS;
        } else if (gone[who]) {
            return;
        }
        if (now < lungeUntil[who]) {
            var left = lungeUntil[who] - now;
            var amt = (left > LUNGE_MS / 2 ? LUNGE_MS - left : left) * 13 / (LUNGE_MS / 2);
            ox = who == 0 ? amt : -amt;
            oy = who == 0 ? -amt / 2 : amt / 2;
        }
        if (now < hitUntil[who]) { ox += ((hitUntil[who] - now) / 50) % 2 == 1 ? 3 : -3; }
        drawSprite(dc, who, sx + ox, footY + oy, now < hitUntil[who] ? 4 : 0);
    }

    // A friend's creature from another region, which this build has no picture of: an orb in its
    // type's colour (the second type as a band) with its national number, bobbing gently.
    function drawStandIn(dc, who, cx, footY) {
        var c = who == 0 ? you : foe;
        var r = 22;
        var cy = footY - r - 2 - ((frame / 4) % 2);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(cx, footY, r, 3);
        dc.setColor(Moves.typeColor(c.t1), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        if (c.t2 >= 0) {
            dc.setColor(Moves.typeColor(c.t2), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx - r + 3, cy + 4, 2 * r - 6, 7);
        }
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 8, cy - 9, 4);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, r);
        dc.setPenWidth(1);
        dc.drawText(cx, cy - 12, Graphics.FONT_XTINY, "?", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // A frame of the creature's sheet (idle, or hurt while hit) standing on footY.
    function drawSprite(dc, who, cx, footY, animIdx) {
        if (art[who] == null) { drawStandIn(dc, who, cx, footY); return; }
        var m = art[who][0];
        var a = m[SpriteIndex.ANIMS[animIdx]];
        var n = a["d"].size();
        var fi = (frame / 3) % n;
        var w = a["w"];
        var hh = a["h"];
        var x = cx + a["x"];
        var y = footY - m["foot"] + a["y"];
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(cx, footY, m["idle"]["w"] / 3, 3);
        dc.setClip(x, y, w, hh);
        dc.drawBitmap(x - (fi % a["c"]) * w, y - a["r"] - (fi / a["c"]) * hh - art[who][2], art[who][1]);
        dc.clearClip();
    }
}

// UP/DOWN move the highlight, START picks / advances, BACK steps back (and offers RUN).
class BattleDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function cells() {
        if (v.menu == v.MENU_RUN) { return 2; }
        return 4;
    }

    function onNextPage() { return step(1); }
    function onPreviousPage() { return step(-1); }

    function step(d) {
        if (v.msgs.size() > 0) { return true; }
        var n = cells();
        for (var k = 0; k < n; k++) {
            v.sel = (v.sel + d + n) % n;
            if (v.menu != v.MENU_MOVES || v.you.moves[v.sel] != 0) { break; }
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        if (v.waitingPeer) { return true; }
        if (v.msgs.size() > 0) {
            if (v.advance()) {
                // over: the result, straight from the battle (a run away goes back as before)
                if (v.over && !v.ranAway) { v.showResult(); } else { leave(); }
            }
        } else if (v.menu == v.MENU_MAIN) {
            if (v.sel == 0) { v.menu = v.MENU_MOVES; v.sel = 0; }
            else if (v.sel == 1) { if (v.lobby == null) { v.menu = v.MENU_BAG; v.sel = 0; } }
            else if (v.sel == 3) { v.menu = v.MENU_RUN; v.sel = 1; }
            else if (v.squad.size() > 1) { v.menu = v.MENU_SWITCH; v.sel = 0; }
        } else if (v.menu == v.MENU_BAG) {
            if (v.sel == 3) { v.menu = v.MENU_MAIN; v.sel = 1; } else { v.useItem(v.sel); }
        } else if (v.menu == v.MENU_SWITCH) {
            var mi = v.sel + (v.sel >= v.squadAt ? 1 : 0);
            if (mi < v.squad.size() && !v.squad[mi].fainted()) {
                v.menu = v.MENU_MAIN;
                v.sel = 0;
                if (v.lobby != null) { v.linkAct("S", mi); } else { v.bringIn(mi, true); }
            }
        } else if (v.menu == v.MENU_RUN) {
            if (v.sel == 0) { leave(); return true; }
            v.menu = v.MENU_MAIN;
            v.sel = 0;
        } else {
            v.useMove(v.sel);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        if (v.msgs.size() > 0) { return true; }
        if (v.menu == v.MENU_MAIN) { v.menu = v.MENU_RUN; v.sel = 1; }
        else { v.menu = v.MENU_MAIN; v.sel = 0; }
        WatchUi.requestUpdate();
        return true;
    }

    function leave() {
        v.savePetHp();                       // running away keeps the HP it has now
        if (v.lobby != null) { v.lobby.battleDone(v.won); }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
