import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Keys (the 6X Pro has no touchscreen):
//   UP/DOWN  move the dock highlight / the food picker / the stat card page
//   START    tap the egg, press the highlighted button, pick the food
//   MENU     (hold UP, or the book in the dock) decisions waiting + Pet it, Stats, Release
//   BACK     close the picker or card, else exit
class PetDelegate extends WatchUi.BehaviorDelegate {

    var model;
    var view;

    function initialize(m, v) {
        BehaviorDelegate.initialize();
        model = m;
        view = v;
        v.delegate = self.weak();   // so a restarted game can hand both the new model (weak: no cycle)
    }

    function onSelect() {
        view.wake();
        if (model.starterPick) {
            model.chooseStarter(Dex.STARTERS[view.starterSel]);
            view.starterArt = null;     // free the three sprites
            WatchUi.requestUpdate();
            return true;
        }
        if (view.page != 0) {
            view.page = 0;
        } else if (view.picking) {
            view.picking = false;
            if (view.pick == model.FOOD_CANDY) { model.feedCandy(); } else { model.feedFruit(view.pick); }
        } else if (model.ceremony != model.CER_NONE) {
            // nothing: the goodbye plays out
        } else if (model.isEgg()) {
            model.eggTap();
        } else if (!view.buttonDisabled(view.sel)) {
            press(view.sel);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function press(i) {
        if (i == view.BTN_FOOD) {
            if (model.canAct()) { view.picking = true; view.pick = 0; }
        } else if (i == view.BTN_BATH) {
            model.clean();
        } else if (i == view.BTN_BOOK) {
            onMenu();
        } else {
            // TamaPoke's dumbbell: the TRAINING panel, a row per stat with its progress to the cap
            if (!model.canAct()) { return; }
            var rows = [[Tr.t("STRENGTH"), 0, 0, pct(model.trAtk, model.trMaxFor(model.ivAtk))],
                        [Tr.t("SPEED"), 1, 0, pct(model.trSpe, model.trMaxFor(model.ivSpe))],
                        [Tr.t("DEFENSE"), 2, 0, pct(model.trDef, model.trMaxFor(model.ivDef))]];
            var pv = new PanelView(Tr.t("TRAINING"), rows, Tr.t("START: train"));
            WatchUi.pushView(pv, new PanelDelegate(pv, new TrainingDelegate(model, view)), WatchUi.SLIDE_UP);
        }
    }

    function pct(cur, cap) { return cap > 0 ? (cur * 100 / cap) : 0; }

    function onNextPage() { return move(1); }
    function onPreviousPage() { return move(-1); }

    function move(step) {
        view.wake();
        if (model.starterPick) {
            view.starterSel = (view.starterSel + step + 3) % 3;
        } else if (view.picking) {
            view.pick = (view.pick + step + 4) % 4;
        } else if (view.page != 0) {
            view.cardPage = (view.cardPage + step + 5) % 5;
        } else {
            view.moveSelection(step);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        view.wake();
        if (view.picking) { view.picking = false; WatchUi.requestUpdate(); return true; }
        if (view.page != 0) { view.page = 0; WatchUi.requestUpdate(); return true; }
        return false;   // exit the app
    }

    // TamaPoke's menu panel: its rows (STATS, POKEDEX, SETTINGS, RETIRE, CLOSE) in its style, with
    // TamaWatch's extra entries above them (on the watch they can't be reached by swiping).
    function onMenu() {
        view.wake();
        if (model.ceremony != model.CER_NONE) { return true; }
        var p = menuPanel();
        WatchUi.pushView(p[0], p[1], WatchUi.SLIDE_UP);
        return true;
    }

    // [view, delegate] of the menu panel (a function of its own so tests can open it directly).
    function menuPanel() {
        var rows = [];
        // you first, then your team
        rows.add([model.trName != null ? model.trName.toUpper() : Tr.t("TRAINER"), :trainer, 0, -1]);
        rows.add([Tr.t("TEAM"), :team, 0, -1]);
        rows.add([Tr.t("POKÉBOX"), :petbox, 0, -1]);
        if (model.wantEvolveButton()) { rows.add([Tr.t("EVOLVE!"), :evolve, 0, -1]); }
        if (model.wantFarewellButton()) { rows.add([Tr.t("SAY GOODBYE"), :farewell, 0, -1]); }
        if (model.canRunawayNow()) { rows.add([Tr.t("IT WANTS TO LEAVE"), :runaway, 0, -1]); }
        if (model.waiting != null) { rows.add([Tr.t("MAKE ROOM"), :room, 0, -1]); }
        if (model.learnOffer() != 0) { rows.add([Tr.t("NEW MOVE: ") + Moves.name(model.learnOffer()), :learn, 0, -1]); }
        if (model.canAct()) {
            rows.add([Tr.t("PET IT"), :pet, 0, -1]);
            rows.add([Tr.t("GYMS ") + model.badgeCount(false) + "/8", :gyms, 0, -1]);
            rows.add([Tr.t("WILD BATTLE"), :wild, 0, -1]);
            if (Extra.rivalReady(model)) { rows.add([Tr.t("RIVAL BATTLE"), :rival, 1, -1]); }
            rows.add([Tr.t("LINK BATTLE"), :link, 0, -1]);
            rows.add([Tr.t("TRADE"), :trade, 0, -1]);
        }
        if (!model.isEgg()) { rows.add([Tr.t("MOVES"), :moves, 0, -1]); }
        if (!model.isEgg()) { rows.add([Tr.t("RENAME"), :rename, 0, -1]); }
        rows.add([Tr.t("POKEDEX ") + model.registeredCount() + "/" + Dex.COUNT, :dex, 0, -1]);
        rows.add([Tr.t("SETTINGS"), :settings, 0, -1]);
        rows.add([Tr.t("GUIDE"), :guide, 0, -1]);
        rows.add([Tr.t("RESTART GAME"), :restart, 1, -1]);
        var pv = new PanelView(null, rows, null);
        return [pv, new PanelDelegate(pv, new MainMenuDelegate(model, view))];
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    var model;
    var view;

    function initialize(m, v) {
        Menu2InputDelegate.initialize();
        model = m;
        view = v;
    }

    function onSelect(item) { selectId(item.getId()); }

    // Screens you browse (trainer, team, gyms, party, Pokedex, ...) open on top of the menu, so BACK
    // walks back the way you came: the screen, then the menu, then home. Battles and decisions
    // replace the menu and return home when done.
    function selectId(id) {
        if (id == :trainer) {
            var tv = new TrainerView(model);
            WatchUi.pushView(tv, new TrainerDelegate(tv), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :petbox) {
            var bx = new PetBoxView(model);
            WatchUi.pushView(bx, new PetBoxDelegate(bx), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :team) {
            var tm = new TeamView(model);
            WatchUi.pushView(tm, new TeamDelegate2(tm), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :pet) {
            model.caress();
        } else if (id == :wild) {
            var foe = pickWild();
            // a third weaker (1-4 levels below), a third your level, a third stronger (1-4 above)
            var lv = model.level();
            var pick = model.rnd(3);
            if (pick == 0) { lv -= 1 + model.rnd(4); } else if (pick == 2) { lv += 1 + model.rnd(4); }
            if (lv < 2) { lv = 2; }
            if (lv > 100) { lv = 100; }
            var bv = new BattleView(model, view, foe, lv, -1, false, 0xFFFF);
            WatchUi.switchToView(bv, new BattleDelegate(bv), WatchUi.SLIDE_UP);
            return;
        } else if (id == :rival) {
            var rv = new BattleView(model, view, 0, 0, RIVAL, false, 0xFFFF);
            WatchUi.switchToView(rv, new BattleDelegate(rv), WatchUi.SLIDE_UP);
            return;
        } else if (id == :gyms) {
            var gv = new GymView(model, view);
            WatchUi.pushView(gv, new GymDelegate2(gv), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :link || id == :trade) {
            var lv = new LinkView(model, view);
            lv.trade = id == :trade;
            WatchUi.pushView(lv, new LinkDelegate(lv), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :learn) {
            slotMenu(model.learnOffer(), true);
            return;
        } else if (id == :moves) {
            var mv = new MovesView(model);
            WatchUi.pushView(mv, new MovesDelegate2(mv), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :party) {
            var pv = new PartyView(model);
            WatchUi.pushView(pv, new PartyDelegate2(pv), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :room) {
            var rows = [];
            for (var i = 0; i < model.party.size(); i++) {
                rows.add([Tr.t("REPLACE ") + model.memberName(model.party[i]).toUpper(), i, 0, -1]);
            }
            rows.add([Tr.t("LET IT GO"), -1, 1, -1]);
            var pv = new PanelView(Tr.t("MAKE ROOM"), rows, model.memberName(model.waiting) + Tr.t(" is waiting"));
            WatchUi.pushView(pv, new PanelDelegate(pv, new RoomAction(model)), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :rename) {
            var np = new NamePickerView(model);
            WatchUi.pushView(np, new NamePickerDelegate(np), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :guide) {
            var gp = guidePanel();
            WatchUi.pushView(gp[0], gp[1], WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :settings) {
            var sp = settingsPanel(model);
            WatchUi.pushView(sp[0], sp[1], WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :dex) {
            var g = new GalleryView(model);
            WatchUi.pushView(g, new GalleryDelegate(g), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :stats) {
            view.page = 1;
            view.cardPage = 0;
        } else if (id == :evolve) {
            confirm(Tr.t("EVOLVE?"), Tr.t("EVOLVE"), Tr.t("KEEP FORM"), :doEvolve, :keepForm, null);
            return;
        } else if (id == :farewell) {
            confirm(Tr.t("SAY GOODBYE?"), Tr.t("SAY GOODBYE"), Tr.t("STAY TOGETHER"), :doFarewell, :stay, null);
            return;
        } else if (id == :runaway) {
            confirm(Tr.t("LET IT GO?"), Tr.t("LET IT GO"), Tr.t("NOT YET"), :doRunaway, :none, null);
            return;
        } else if (id == :release) {
            confirm(Tr.t("RELEASE?"), Tr.t("RELEASE"), Tr.t("CANCEL"), :doRelease, :none, Tr.t("It will not come back"));
            return;
        } else if (id == :restart) {
            confirm(Tr.t("RESTART GAME?"), Tr.t("RESTART"), Tr.t("CANCEL"), :doRestart, :none, Tr.t("Erases your pet, party, Pokedex and trainer"));
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    // A random wild creature that is not a legendary.
    function pickWild() {
        while (true) {
            var n = 1 + model.rnd(Dex.COUNT);
            if (Dex.rarity(n) != Dex.R_LEGEND) { return n; }
        }
        return 16;
    }

    function slotMenu(mv, offer) {
        WatchUi.switchToView(buildSlotMenu(model, mv, offer), new SlotDelegate(model, mv, offer), WatchUi.SLIDE_LEFT);
    }

    // A two-choice decision in TamaPoke's panel style: the yes row in red, the no row in cream.
    function confirm(title, yes, no, yesId, noId, sub) {
        var rows = [[yes, yesId, 1, -1], [no, noId, 0, -1]];
        var pv = new PanelView(title, rows, sub);
        WatchUi.switchToView(pv, new PanelDelegate(pv, new ConfirmAction(model, view)), WatchUi.SLIDE_LEFT);
    }
}

class ConfirmDelegate extends WatchUi.Menu2InputDelegate {
    var model;

    function initialize(m) {
        Menu2InputDelegate.initialize();
        model = m;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :doEvolve) { model.evolve(); }
        else if (id == :keepForm) { model.declineEvolve(); }
        else if (id == :doFarewell) { model.startFarewell(); }
        else if (id == :stay) { model.declineFarewell(); }
        else if (id == :doRunaway) { model.startRunaway(); }
        else if (id == :doRelease) { model.release(); }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// Which known move a new one replaces (or a free slot), or keep the four.
function buildSlotMenu(model, mv, offer) {
    // drawn by FitTitle: the system title breaks a long word mid-way ("FUOCOPUGN-O")
    var menu = new WatchUi.Menu2({:title => new FitTitle(Tr.t("Learn ") + Moves.name(mv) + "?")});
    for (var i = 0; i < 4; i++) {
        var old = model.moves[i];
        var fl = Tr.t("Forget ") + Moves.name(old);
        if (old != 0 && fl.length() > 15) {     // too long for the round screen: the move, "Forget" under it
            menu.addItem(new WatchUi.MenuItem(Moves.name(old), Tr.t("Forget ").substring(0, Tr.t("Forget ").length() - 1), i, {}));
        } else {
            menu.addItem(new WatchUi.MenuItem(old == 0 ? Tr.t("Empty slot") : fl, null, i, {}));
        }
    }
    menu.addItem(new WatchUi.MenuItem(offer ? Tr.t("Don't learn it") : Tr.t("Cancel"), null, -1, {}));
    return menu;
}

class SlotDelegate extends WatchUi.Menu2InputDelegate {
    var model;
    var mv;
    var offer;

    function initialize(m, move, isOffer) {
        Menu2InputDelegate.initialize();
        model = m;
        mv = move;
        offer = isOffer;
    }

    function onSelect(item) {
        var slot = item.getId() as Number;
        if (slot >= 0) { model.acceptLearn(slot, mv); }
        else if (offer) { model.declineLearn(); }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// The moves list: known ones are information; "Learn X" asks which one to replace.
class MovesDelegate extends WatchUi.Menu2InputDelegate {
    var model;

    function initialize(m) {
        Menu2InputDelegate.initialize();
        model = m;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id instanceof Lang.Number) {
            WatchUi.switchToView(buildSlotMenu(model, id, false), new SlotDelegate(model, id, false), WatchUi.SLIDE_LEFT);
        }
    }
}

// Pick a gym, then easy or hard.
class GymDelegate extends WatchUi.Menu2InputDelegate {
    var model;
    var view;

    function initialize(m, v) {
        Menu2InputDelegate.initialize();
        model = m;
        view = v;
    }

    function onSelect(item) {
        var idx = item.getId() as Number;
        var menu = new WatchUi.Menu2({:title => Tr.t("Difficulty")});
        menu.addItem(new WatchUi.MenuItem(Tr.t("Easy"), Tr.t("Foes IV 16, random moves"), idx * 2, {}));
        menu.addItem(new WatchUi.MenuItem(Tr.t("Hard"), Tr.t("Foes IV 31, smart moves"), idx * 2 + 1, {}));
        WatchUi.switchToView(menu, new DifficultyDelegate(model, view), WatchUi.SLIDE_LEFT);
    }
}

class DifficultyDelegate extends WatchUi.Menu2InputDelegate {
    var model;
    var view;

    function initialize(m, v) {
        Menu2InputDelegate.initialize();
        model = m;
        view = v;
    }

    function onSelect(item) {
        var code = item.getId() as Number;
        if (model.party.size() == 0) {
            var bv = new BattleView(model, view, 0, 0, code / 2, code % 2 == 1, 0xFFFF);
            WatchUi.switchToView(bv, new BattleDelegate(bv), WatchUi.SLIDE_UP);
            return;
        }
        // choose the team (TamaPoke's squad pick): everyone ticked to start
        var menu = new WatchUi.Menu2({:title => Tr.t("Your team")});
        menu.addItem(new WatchUi.CheckboxMenuItem(model.name(), Tr.t("Lv ") + model.level(), 0, true, {}));
        for (var i = 0; i < model.party.size(); i++) {
            var m = model.party[i];
            menu.addItem(new WatchUi.CheckboxMenuItem(model.memberName(m), Tr.t("Lv ") + m[3], i + 1, true, {}));
        }
        menu.addItem(new WatchUi.MenuItem(Tr.t("Fight!"), null, -1, {}));
        WatchUi.switchToView(menu, new TeamDelegate(model, view, code), WatchUi.SLIDE_LEFT);
    }
}

class TrainingDelegate extends WatchUi.Menu2InputDelegate {
    var model;
    var view;

    function initialize(m, v) {
        Menu2InputDelegate.initialize();
        model = m;
        view = v;
    }

    function onSelect(item) { selectId(item.getId()); }

    function selectId(id) {
        var g = new MiniGameView(model, view, id as Number);
        WatchUi.switchToView(g, new MiniGameDelegate(g), WatchUi.SLIDE_UP);
    }
}

// Party first, then the box. id = index (party) or 100 + index (box).
function partyMenu(model) {
    var menu = new WatchUi.Menu2({:title => Tr.t("Party")});
    for (var i = 0; i < model.party.size(); i++) {
        var m = model.party[i];
        menu.addItem(new WatchUi.MenuItem(model.memberName(m), Tr.t("Lv ") + m[3] + (m[2] ? " *" : ""), i, {}));
    }
    for (var i = 0; i < model.box.size(); i++) {
        var m = model.box[i];
        menu.addItem(new WatchUi.MenuItem(Tr.t("[Pokébox] ") + model.memberName(m), Tr.t("Lv ") + m[3] + (m[2] ? " *" : ""), 100 + i, {}));
    }
    return menu;
}

class PartyDelegate extends WatchUi.Menu2InputDelegate {
    var model;

    function initialize(m) {
        Menu2InputDelegate.initialize();
        model = m;
    }

    function onSelect(item) {
        var id = item.getId() as Number;
        var inParty = id < 100;
        var idx = inParty ? id : id - 100;
        var m = inParty ? model.party[idx] : model.box[idx];
        var menu = new WatchUi.Menu2({:title => model.memberName(m)});
        menu.addItem(new WatchUi.MenuItem(Tr.t("Info"), Tr.t("Level, IVs, moves"), :info, {}));
        if (inParty) { menu.addItem(new WatchUi.MenuItem(Tr.t("Move to Pokébox"), null, :toBox, {})); }
        else if (model.party.size() < 6) { menu.addItem(new WatchUi.MenuItem(Tr.t("To party"), null, :toParty, {})); }
        menu.addItem(new WatchUi.MenuItem(Tr.t("Release"), Tr.t("Gone for good"), :release, {}));
        menu.addItem(new WatchUi.MenuItem(Tr.t("Back"), null, :back, {}));
        WatchUi.switchToView(menu, new MemberDelegate(model, inParty, idx), WatchUi.SLIDE_LEFT);
    }
}

class MemberDelegate extends WatchUi.Menu2InputDelegate {
    var model;
    var inParty;
    var idx;

    function initialize(m, p, i) {
        Menu2InputDelegate.initialize();
        model = m;
        inParty = p;
        idx = i;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :info) {
            var mv = new MemberView(model, inParty ? model.party[idx] : model.box[idx]);
            WatchUi.switchToView(mv, new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == :toBox) { model.toBox(idx); }
        else if (id == :toParty) { model.toParty(idx); }
        else if (id == :release) {
            var menu = new WatchUi.Menu2({:title => Tr.t("Release for good?")});
            menu.addItem(new WatchUi.MenuItem(Tr.t("Release"), Tr.t("It will not come back"), :yes, {}));
            menu.addItem(new WatchUi.MenuItem(Tr.t("Keep"), null, :no, {}));
            WatchUi.switchToView(menu, new ReleaseMemberDelegate(model, inParty, idx), WatchUi.SLIDE_LEFT);
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ReleaseMemberDelegate extends WatchUi.Menu2InputDelegate {
    var model;
    var inParty;
    var idx;

    function initialize(m, p, i) {
        Menu2InputDelegate.initialize();
        model = m;
        inParty = p;
        idx = i;
    }

    function onSelect(item) {
        if (item.getId() == :yes) { model.releaseMember(inParty, idx); }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class SettingsDelegate extends WatchUi.Menu2InputDelegate {
    var model;

    function initialize(m) {
        Menu2InputDelegate.initialize();
        model = m;
    }

    function onSelect(item) {
        var on = (item as WatchUi.ToggleMenuItem).isEnabled();
        var id = item.getId();
        if (id == :alerts) { model.setAlerts(on); }
        else if (id == :vibe) { Storage.setValue("vibe", on); }
    }
}

class TeamDelegate extends WatchUi.Menu2InputDelegate {
    var model;
    var view;
    var code;
    var mask = 0xFFFF;

    function initialize(m, v, c) {
        Menu2InputDelegate.initialize();
        model = m;
        view = v;
        code = c;
    }

    function onSelect(item) {
        var id = item.getId() as Number;
        if (id >= 0) {
            var on = (item as WatchUi.CheckboxMenuItem).isChecked();
            if (on) { mask |= 1 << id; } else { mask &= ~(1 << id); }
            return;
        }
        var bv = new BattleView(model, view, 0, 0, code / 2, code % 2 == 1, mask);
        WatchUi.switchToView(bv, new BattleDelegate(bv), WatchUi.SLIDE_UP);
    }
}

class RoomDelegate extends WatchUi.Menu2InputDelegate {
    var model;

    function initialize(m) {
        Menu2InputDelegate.initialize();
        model = m;
    }

    function onSelect(item) {
        model.placeWaiting(item.getId() as Number);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ConfirmAction {
    var model;
    var view;

    function initialize(m, v) { model = m; view = v; }

    function selectId(id) {
        if (id == :doEvolve) { model.evolve(); }
        else if (id == :keepForm) { model.declineEvolve(); }
        else if (id == :doFarewell) { model.startFarewell(); }
        else if (id == :stay) { model.declineFarewell(); }
        else if (id == :doRunaway) { model.startRunaway(); }
        else if (id == :doRelease) { model.release(); }
        else if (id == :doRestart) {
            // Everything erased, then a brand-new game in place: a fresh model (it finds no save, so
            // it starts at the egg and starter pick) handed to the app and the home screen, which
            // opens the welcome guide as soon as it shows. A widget can't close itself on the watch.
            model.restartGame();
            var nm = new PetModel();
            var app = Application.getApp() as TamaWatchApp;
            app.model = nm;
            view.swapModel(nm);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class RoomAction {
    var model;

    function initialize(m) { model = m; }

    function selectId(id) {
        model.placeWaiting(id as Number);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// A menu title that always fits: one line in the largest font that fits, else two lines split at
// a space, else a smaller font. Never breaks a word.
class FitTitle extends WatchUi.Drawable {
    var text;

    function initialize(t) {
        Drawable.initialize({});
        text = t;
    }

    function draw(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var sw = System.getDeviceSettings().screenWidth;
        var maxW = sw * (sw == 280 ? 150 : 120) / 280;   // what shows of the title area (narrower on other watches)
        var fonts = [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var lines = [text];
        var f = Graphics.FONT_XTINY;
        for (var k = 0; k < fonts.size(); k++) {
            f = fonts[k];
            var lh0 = Graphics.getFontHeight(f);
            if (dc.getTextWidthInPixels(text, f) <= maxW && lh0 <= h) { lines = [text]; break; }
            var cut = text.find(" ");
            var best = null;
            while (cut != null) {           // the split whose longer half is shortest
                var a = text.substring(0, cut);
                var b = text.substring(cut + 1, text.length());
                var wa = dc.getTextWidthInPixels(a, f);
                var wb = dc.getTextWidthInPixels(b, f);
                var m = wa > wb ? wa : wb;
                if (m <= maxW && 2 * lh0 <= h + (sw == 280 ? 8 : -8) && (best == null || m < best[2])) { best = [a, b, m]; }
                var rest = text.substring(cut + 1, text.length()).find(" ");
                cut = rest == null ? null : cut + 1 + rest;
            }
            if (best != null) { lines = [best[0], best[1]]; break; }
        }
        var lh = Graphics.getFontHeight(f);
        var y = h * 58 / 100 - lines.size() * lh / 2;
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(w / 2, y + i * lh, f, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
