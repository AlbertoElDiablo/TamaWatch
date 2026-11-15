import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;
import Toybox.WatchUi;

// The link lobby, for battles and trades, after TamaPoke's renderLan() scaled 466 -> 280. First the
// way to connect: ONLINE (both post to one ntfy.sh topic through their phones' internet) or NEARBY
// (watch to watch over ANT radio, no phone; AntLink). Either way the host shows a 4-letter room
// code and the friend types it in. Then a battle (FIGHT), or a trade: each picks a team member to
// offer (OFFER), both see what they give and get, and the swap happens when both say TRADE.
class LinkView extends WatchUi.View {

    const S_OFF = 0;      // HOST / JOIN
    const S_ENTER = 1;    // typing the room code
    const S_WAIT = 2;     // hosting: waiting for a friend / joining: waiting for the host
    const S_READY = 3;    // both teams in hand: FIGHT
    const S_DONE = 4;     // after a battle: REMATCH
    const S_LOST = 5;     // the friend left, or no connection
    const S_MODE = 6;     // ONLINE / NEARBY
    const S_PICK = 7;     // trade: choosing the team member to offer
    const S_OFFER = 8;    // trade: offered, waiting for the friend's offer
    const S_CONFIRM = 9;  // trade: both offers in: TRADE (or BACK to choose again)
    const S_TRADED = 10;  // trade: done
    const MODE_ONLINE = 0;
    const MODE_NEARBY = 1;

    const LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ";   // no I / O, easy to read out loud

    var model;
    var petView;
    var state = 6;
    var mode = 0;
    var sel = 0;          // HOST / JOIN highlight
    var code = "";
    var entry = [0, 0, 0, 0];
    var entryAt = 0;
    var host = false;
    var client = null;
    var mine = "";        // my squad on the wire
    var theirs = "";      // the friend's squad
    var peerName = "";
    var peerCount = 0;
    var gotReady = false;
    var battle = null;
    var earlyAct = null;  // an ACT that arrived before this watch opened the fight
    var youWon = false;
    var lostMsg = "";
    var timer = null;
    var trade = false;    // a trade instead of a battle
    var pickIdx = 0;      // the team member shown while picking
    var myOffer = -1;     // the team index offered
    var theirOffer = null;
    var iAccepted = false;
    var theyAccepted = false;
    var traded = null;    // who arrived

    function initialize(m, pv) {
        View.initialize();
        model = m;
        petView = pv;
    }

    function onShow() {
        timer = new Timer.Timer();
        timer.start(method(:tick), 500, true);
    }

    function onHide() {
        if (timer != null) { timer.stop(); timer = null; }   // the timer points back at this view: drop it, or neither is ever freed
        Thumbs.clear();
    }

    function tick() as Void { WatchUi.requestUpdate(); }

    // Your pet first, then the party, at their own levels (TamaPoke's LAN squads are uncapped).
    function mySquad() {
        var sq = [Battle.fromPet(model, 0)];
        for (var i = 0; i < model.party.size() && sq.size() < 6; i++) {
            sq.add(Battle.fromMember(model.party[i], 0));
        }
        return sq;
    }

    function myName() { return Wire.clean(model.name()).toUpper(); }

    function startHost() {
        host = true;
        code = "";
        for (var i = 0; i < 4; i++) {
            var k = Math.rand().abs() % LETTERS.length();
            code += LETTERS.substring(k, k + 1);
        }
        begin();
        client.send("HELLO", myName() + "|" + mine);
    }

    function startJoin() {
        host = false;
        code = "";
        for (var i = 0; i < 4; i++) { code += LETTERS.substring(entry[i], entry[i] + 1); }
        begin();
        client.send("JOIN", myName() + "|" + mine);
    }

    function begin() {
        if (client != null) { client.stop(); }
        mine = Battle.squadToWire(mySquad());
        theirs = "";
        peerName = "";
        gotReady = false;
        earlyAct = null;
        client = mode == MODE_NEARBY ? new AntLink(code, host, self) : new LinkClient(code, host, self);
        client.start();
        state = S_WAIT;
        if (mode == MODE_NEARBY && !client.online()) {
            state = S_LOST;
            lostMsg = Tr.t("Nearby link not available");
        }
    }

    // Messages from the friend's watch.
    function onLink(type, parts) {
        if (type.equals("NET")) {
            if (!client.online() && state == S_WAIT) { state = S_LOST; lostMsg = Tr.t("No connection: check the phone"); }
            return;
        }
        if (type.equals("BYE")) {
            if (battle != null) { battle.peerLeft(); }
            state = S_LOST;
            lostMsg = peerName + Tr.t(" left");
            return;
        }
        if (battle != null && (type.equals("ACT") || type.equals("RES"))) {
            battle.onLinkMsg(type, parts);
            return;
        }
        if (type.equals("ACT") && host) { earlyAct = parts; return; }
        if (type.equals("JOIN") && host && parts.size() >= 6) {
            peerName = parts[4];
            theirs = parts[5];
            peerCount = Wire.split(theirs, ";").size();
            client.send("READY", myName());
            ready();
        } else if (type.equals("HELLO") && !host && parts.size() >= 6) {
            peerName = parts[4];
            theirs = parts[5];
            peerCount = Wire.split(theirs, ";").size();
            if (gotReady) { ready(); }
        } else if (type.equals("READY") && !host) {
            gotReady = true;
            if (theirs.length() > 0) { ready(); }
        } else if (type.equals("AGAIN") && state == S_DONE) {
            state = S_READY;
        } else if (type.equals("OFFER") && parts.size() >= 5) {
            theirOffer = Trade.fromWire(parts[4]);
            theyAccepted = false;
            if (state == S_OFFER && theirOffer != null) { state = S_CONFIRM; }
        } else if (type.equals("ACCEPT")) {
            theyAccepted = true;
            if (iAccepted) { doTrade(); }
        } else if (type.equals("DECLINE")) {
            resetOffers();
            if (state == S_OFFER || state == S_CONFIRM) { state = S_PICK; }
        }
    }

    // Both connected: a battle's FIGHT, or a trade's pick.
    function ready() {
        if (!trade) { state = S_READY; return; }
        resetOffers();
        pickIdx = 0;
        state = S_PICK;
    }

    function resetOffers() {
        myOffer = -1;
        theirOffer = null;
        iAccepted = false;
        theyAccepted = false;
    }

    function offer() {
        if (model.party.size() == 0) { return; }
        myOffer = pickIdx;
        iAccepted = false;
        client.send("OFFER", Trade.toWire(model.party[myOffer]));
        state = theirOffer != null ? S_CONFIRM : S_OFFER;
    }

    function accept() {
        if (iAccepted) { return; }
        iAccepted = true;
        client.send("ACCEPT", "1");
        if (theyAccepted) { doTrade(); }
    }

    function decline() {
        client.send("DECLINE", "1");
        resetOffers();
        state = S_PICK;
    }

    function doTrade() {
        if (myOffer < 0 || theirOffer == null) { return; }
        if (Trade.swap(model, myOffer, theirOffer)) {
            traded = theirOffer;
            Sfx.vibe(Sfx.HATCH);
        }
        resetOffers();
        state = S_TRADED;
    }

    function fight() {
        var bv = new BattleView(model, petView, 0, 0, -2, false, 0xFFFF);
        bv.setupLink(self, Battle.squadFromWire(mine), Battle.squadFromWire(theirs), peerName, host);
        battle = bv;
        WatchUi.pushView(bv, new BattleDelegate(bv), WatchUi.SLIDE_UP);
    }

    function battleDone(won) {
        battle = null;
        youWon = won;
        if (state != S_LOST) { state = S_DONE; }
    }

    function rematch() {
        client.send("AGAIN", "1");
        state = S_READY;
    }

    function leave() {
        if (client != null) {
            if (state != S_OFF) { client.send("BYE", "1"); }
            client.stop();
        }
    }

    // ---------- drawing ----------

    const BG = 0xFFFFFF;
    const INK = 0x000000;
    const TRACK = 0xAAAAAA;

    function button(dc, cx, y, w, text, on, fill, textCol) {
        w = Fit.COL_W;                  // the app's column of boxes
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - w / 2, y, w, 34, 8);
        dc.setColor(on ? 0xFF0000 : INK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(on ? 3 : 1);
        dc.drawRoundedRectangle(cx - w / 2, y, w, 34, 8);
        dc.setPenWidth(1);
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        centerText(dc, cx - w / 2, y, w, 34, UiFont.mid(), text);   // centred both ways
    }

    // A team member: its thumbnail in a box, name and level below.
    function memberCard(dc, cx, y, m, pick) {
        dc.setColor(0xAAFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - 24, y, 48, 48, 8);
        dc.setColor(pick ? 0xFF0000 : INK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pick ? 3 : 1);
        dc.drawRoundedRectangle(cx - 24, y, 48, 48, 8);
        dc.setPenWidth(1);
        dc.setClip(cx - 19, y + 5, 38, 38);
        Thumbs.draw(dc, m[0], cx - 19, y + 5 + ThumbCentres.DY[m[0] - 1], false);
        dc.clearClip();
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, capY(UiFont.small(), y + 64), UiFont.small(), Fit.trim(dc, (m[2] ? "*" : "") + Trade.label(m), 190, UiFont.small()), Graphics.TEXT_JUSTIFY_CENTER);
    }

    function onUpdate(dc) {

        dc = Scr.wrap(dc);              // any screen size: see Sdc.mc
        var cx = dc.getWidth() / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());   // the background fills the screen
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        var lt = trade ? Tr.t("TRADE") : Tr.t("LINK BATTLE");   // a size smaller if the language needs it
        var lf = Fit.font(dc, lt, 140, [UiFont.small(), UiFont.tiny()]);   // a taller font runs into the line below
        dc.drawText(cx, 26, lf, Fit.trim(dc, lt, 150, lf), Graphics.TEXT_JUSTIFY_CENTER);
        var msg = state == S_MODE ? Tr.t("How to connect?") : (mode == MODE_NEARBY ? Tr.t("NEARBY") : Tr.t("ONLINE")) + Tr.t(": pick one");
        var msgCol = TRACK;
        if (state == S_WAIT) {
            msg = mode == MODE_NEARBY ? (host ? Tr.t("Waiting nearby...") : Tr.t("Looking for the host..."))
                                      : (host ? Tr.t("Waiting for a friend...") : Tr.t("Waiting for the host..."));
        }
        else if (state == S_ENTER) { msg = Tr.t("Enter the room code"); }
        else if (state == S_READY) { msg = Tr.t("Ready!"); }
        else if (state == S_DONE) { msg = youWon ? Tr.t("You won!") : Tr.t("You lost..."); }
        else if (state == S_LOST) { msg = lostMsg; msgCol = 0xFF0000; }
        else if (state == S_PICK) { msg = Tr.t("Pick a pet to trade"); }
        else if (state == S_OFFER || (state == S_CONFIRM && iAccepted)) { msg = Tr.t("Waiting for ") + peerName + "..."; }
        else if (state == S_CONFIRM) { msg = peerName; }
        else if (state == S_TRADED) { msg = Tr.t("Traded!"); }
        dc.setColor(msgCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 52, UiFont.tiny(), msg, Graphics.TEXT_JUSTIFY_CENTER);

        if (state == S_MODE) {
            button(dc, cx, 78, 172, Tr.t("ONLINE"), sel == 0, BG, INK);
            dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 113, UiFont.tiny(), Tr.t("anywhere, through your phone"), Graphics.TEXT_JUSTIFY_CENTER);
            button(dc, cx, 140, 172, Tr.t("NEARBY"), sel == 1, BG, INK);
            dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 175, UiFont.tiny(), Tr.t("watch to watch, no phone"), Graphics.TEXT_JUSTIFY_CENTER);
        } else if (state == S_OFF || state == S_LOST) {
            button(dc, cx, 82, 172, Tr.t("HOST"), sel == 0, BG, INK);
            button(dc, cx, 124, 172, Tr.t("JOIN"), sel == 1, BG, INK);
        } else if (state == S_ENTER) {
            for (var i = 0; i < 4; i++) {
                var x = cx - 66 + i * 44;
                dc.setColor(i == entryAt ? 0xFF0000 : INK, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(i == entryAt ? 3 : 1);
                dc.drawRoundedRectangle(x - 18, 90, 36, 44, 6);
                dc.setPenWidth(1);
                dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, 94, UiFont.big(), LETTERS.substring(entry[i], entry[i] + 1), Graphics.TEXT_JUSTIFY_CENTER);
            }
            dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 150, UiFont.tiny(), Tr.t("UP/DOWN letter, START next"), Graphics.TEXT_JUSTIFY_CENTER);
        } else if (state == S_WAIT) {
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 84, UiFont.tiny(), Tr.t("Room code"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, 100, UiFont.big(), code, Graphics.TEXT_JUSTIFY_CENTER);
            if (client != null && !client.online()) {
                dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, 150, UiFont.tiny(), mode == MODE_NEARBY ? Tr.t("Nearby link not available") : Tr.t("No connection: check the phone"), Graphics.TEXT_JUSTIFY_CENTER);
            } else if (mode == MODE_NEARBY) {
                dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, 150, UiFont.tiny(), Tr.t("Keep the watches close"), Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else if (state == S_READY) {
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, capY(UiFont.mid(), 92), UiFont.mid(), peerName, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, capY(UiFont.small(), 120), UiFont.small(), Tr.t("vs ") + peerCount, Graphics.TEXT_JUSTIFY_CENTER);
            button(dc, cx, 146, 136, Tr.t("FIGHT"), true, 0x55FF55, INK);   // dark text: cream on pale green is unreadable in 64 colours
        } else if (state == S_DONE) {
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 92, UiFont.mid(), peerName, Graphics.TEXT_JUSTIFY_CENTER);
            button(dc, cx, 132, 136, Tr.t("REMATCH"), true, BG, INK);
        } else if (state == S_PICK) {
            if (model.party.size() == 0) {
                dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, capY(UiFont.tiny(), 110), UiFont.tiny(), Tr.t("Your team is empty"), Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                if (pickIdx >= model.party.size()) { pickIdx = 0; }
                var m = model.party[pickIdx];
                memberCard(dc, cx, 74, m, true);
                dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, capY(UiFont.tiny(), 158), UiFont.tiny(), "< " + (pickIdx + 1) + "/" + model.party.size() + " >", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(cx, capY(UiFont.tiny(), 178), UiFont.tiny(), Fit.trim(dc, Tr.t("START: offer"), 190, UiFont.tiny()), Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else if (state == S_OFFER || state == S_CONFIRM) {
            // what you give and, once it's in, what you get
            dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, capY(UiFont.tiny(), 84), UiFont.tiny(), Tr.t("You give"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            if (myOffer >= 0 && myOffer < model.party.size()) {
                dc.drawText(cx, capY(UiFont.small(), 102), UiFont.small(), Fit.trim(dc, Trade.label(model.party[myOffer]), 180, UiFont.small()), Graphics.TEXT_JUSTIFY_CENTER);
            }
            if (state == S_CONFIRM && theirOffer != null) {
                dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, capY(UiFont.tiny(), 128), UiFont.tiny(), Tr.t("You get"), Graphics.TEXT_JUSTIFY_CENTER);
                dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, capY(UiFont.small(), 146), UiFont.small(), Fit.trim(dc, (theirOffer[2] ? "*" : "") + Trade.label(theirOffer), 180, UiFont.small()), Graphics.TEXT_JUSTIFY_CENTER);
                if (!iAccepted) { button(dc, cx, 168, 136, Tr.t("TRADE"), true, 0x55FF55, INK); }
            }
        } else if (state == S_TRADED) {
            if (traded != null) { memberCard(dc, cx, 74, traded, false); }
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, capY(UiFont.tiny(), 160), UiFont.tiny(), Fit.trim(dc, Tr.t("Joined your team!"), 190, UiFont.tiny()), Graphics.TEXT_JUSTIFY_CENTER);
            button(dc, cx, 176, 136, Tr.t("TRADE AGAIN"), true, BG, INK);
        }
        dc.setColor(TEXT_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, capY(UiFont.tiny(), 226), UiFont.tiny(), Tr.t("BACK"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class LinkDelegate extends WatchUi.BehaviorDelegate {
    var v;

    function initialize(view) {
        BehaviorDelegate.initialize();
        v = view;
    }

    function onNextPage() { return step(1); }
    function onPreviousPage() { return step(-1); }

    function step(d) {
        if (v.state == v.S_OFF || v.state == v.S_LOST || v.state == v.S_MODE) { v.sel = 1 - v.sel; }
        else if (v.state == v.S_PICK && v.model.party.size() > 0) {
            v.pickIdx = (v.pickIdx + d + v.model.party.size()) % v.model.party.size();
        }
        else if (v.state == v.S_ENTER) {
            var n = v.LETTERS.length();
            v.entry[v.entryAt] = (v.entry[v.entryAt] + d + n) % n;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() {
        if (v.state == v.S_MODE) {
            v.mode = v.sel;
            v.state = v.S_OFF;
            v.sel = 0;
        } else if (v.state == v.S_OFF || v.state == v.S_LOST) {
            if (v.sel == 0) { v.startHost(); } else { v.state = v.S_ENTER; v.entryAt = 0; }
        } else if (v.state == v.S_ENTER) {
            if (v.entryAt < 3) { v.entryAt++; } else { v.startJoin(); }
        } else if (v.state == v.S_READY) {
            v.fight();
        } else if (v.state == v.S_DONE) {
            v.rematch();
        } else if (v.state == v.S_PICK) {
            v.offer();
        } else if (v.state == v.S_CONFIRM) {
            v.accept();
        } else if (v.state == v.S_TRADED) {
            v.ready();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        if (v.state == v.S_ENTER && v.entryAt > 0) { v.entryAt--; WatchUi.requestUpdate(); return true; }
        if ((v.state == v.S_OFFER || v.state == v.S_CONFIRM) && !v.iAccepted) { v.decline(); WatchUi.requestUpdate(); return true; }
        if (v.state == v.S_OFF || v.state == v.S_ENTER || (v.state == v.S_LOST && v.battle == null)) {
            // back to choosing ONLINE / NEARBY
            v.leave();
            v.client = null;
            v.state = v.S_MODE;
            v.sel = v.mode;
            WatchUi.requestUpdate();
            return true;
        }
        v.leave();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
