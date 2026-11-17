import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;
import Toybox.WatchUi;

// The creature and its rules, ported from TamaPoke's pet.cpp (MIT).
// 1 tick = 1 real minute. The watch app is closed most of the time, so on every
// update the minutes since the last one are replayed with the same rules
// (in chunks, to stay inside Connect IQ's per-call time limit).
// EXP and levels: level L needs L^3 EXP (Lv 1 needs none).
module Lvl {
    const MAX = 100;
    function expFor(l) { return l <= 1 ? 0 : l * l * l; }
    function levelFor(e) {
        var l = 1;
        while (l < MAX && expFor(l + 1) <= e) { l++; }
        return l;
    }
}

// HP (PetModel.hpNow): empty to full by itself in 15 minutes; what food, a training game and a
// recorded activity give back at once (a favourite fruit 10 more, candy half).
const HP_FULL_SEC = 900;
const HP_FRUIT = 20;
const HP_GAME = 25;
const HP_WORKOUT = 50;

var workoutsRead = 0;            // when PetModel.claimWorkouts last read the history (UTC epoch)
// Intensity minutes a recorded activity already paid for (as its own EXP): taken off the next
// intensity minutes read, so the same effort isn't paid twice. Saved in "bag".
var amCredit = 0;
var giftDay = 0;                 // the day the daily fruit was last given (saved in "bag")

// The watch says you are asleep right now: its sleep mode (your sleep window, or a sleep it
// detected). Used besides the profile's bedtime and wake time.
function sleepModeNow() {
    var i = ActivityMonitor.getInfo();
    return i != null && (i has :isSleepMode) && i.isSleepMode == true;
}

// EXP a minute of a recorded activity, by sport: about 10 for each intensity minute it is worth,
// weighted so the same effort pays the same. Strength raises the heart rate less (fewer intensity
// minutes) but is as hard: 45 minutes of weights ~ 60 of running ~ 80 of cycling ~ 1,200 EXP.
// And how many of the watch's intensity minutes a minute of it usually makes (x2: vigorous
// minutes count double), which amCredit holds back.
function workoutExp(sport) {
    if (sport == Activity.SPORT_RUNNING || sport == Activity.SPORT_SWIMMING) { return 20; }
    if (sport == Activity.SPORT_TRAINING || sport == Activity.SPORT_FITNESS_EQUIPMENT) { return 27; }
    if (sport == Activity.SPORT_CYCLING) { return 15; }
    if (sport == Activity.SPORT_HIKING) { return 12; }
    if (sport == Activity.SPORT_WALKING) { return 8; }
    return 15;
}
function workoutIm2(sport) {           // intensity minutes x2 per minute
    if (sport == Activity.SPORT_RUNNING) { return 4; }
    if (sport == Activity.SPORT_CYCLING || sport == Activity.SPORT_SWIMMING) { return 3; }
    if (sport == Activity.SPORT_HIKING) { return 2; }
    return 1;
}

// Recorded activities' start times come in the watch's own clock, counted from 31 Dec 1989
// (Garmin's epoch) on many watches rather than from 1970: read as 1970 time they look 20 years
// old and were never paid. Anything before 2014 in 1970 time is that clock: move it over.
function actStart(st) {
    return st < 1388534400 ? st + 631065600 : st;
}

// Hungry, dirty or unhappy, it fights badly: every attack has this extra chance (%) to miss.
// Each of FOOD, HYG and JOY under 50 adds up to 15 (at 0); together at most 40.
// Food drops by 1 this often (minutes awake); asleep it doesn't drop at all.
const FOOD_EVERY_MIN = 7;

// Why a pet that missed did: its lowest of FOOD, HYG and JOY under 50 (0: none is).
// 1 hungry, 2 wants a bath, 3 wants to train.
function careMissWhy(food, hygiene, joy) {
    var why = 0;
    var low = 50;
    if (food < low) { low = food; why = 1; }
    if (hygiene < low) { low = hygiene; why = 2; }
    if (joy < low) { why = 3; }
    return why;
}

function careMissPct(p) {
    var m = 0;
    var v = [p.food, p.hygiene, p.joy];
    for (var i = 0; i < 3; i++) { if (v[i] < 50) { m += (50 - v[i]) * 3 / 10; } }
    return m > 40 ? 40 : m;
}

class PetModel {

    // ---- tuning, as TamaPoke ----
    const MAX_LEVEL = 100;
    const DRAIN_EVERY = 2;
    const RUNAWAY_TICKS = 180;
    const FAREWELL_AGE_MIN = 4320;          // 3 days in final form
    const EVO_PENALTY_LEVELS = 24;
    const DEF_TRAIN_TICKS = 60;
    const MAX_CATCHUP_MIN = 20160;          // 2 weeks
    const CHUNK = 40;                       // minutes replayed per update call at most
    const CHUNK_MS = 40;                    // ...and no longer than this (the watchdog ends long calls)
    const HEART_MS = 1500;
    const EAT_ANIM_MS = 2500;
    const EVOLVE_ANIM_MS = 5200;
    const CEREMONY_MS = 10000;

    // sleep: who decided it
    const SLEEP_NONE = 0;
    const SLEEP_AUTO = 1;
    const SLEEP_PLAYER = 2;
    // endings
    const CER_NONE = 0;
    const CER_FAREWELL = 1;
    const CER_RUNAWAY = 2;
    const CER_RELEASE = 3;
    // food
    const FOOD_APPLE = 0;
    const FOOD_BLUE = 1;
    const FOOD_ORANGE = 2;     // was the green berry; the same favourites love it
    const FOOD_CANDY = 3;
    // medals (bitmask)
    const MED_LV10 = 1;
    const MED_LV25 = 2;
    const MED_LV50 = 4;
    const MED_BERRY = 8;
    const MED_STREAK7 = 16;
    const MED_BOND = 32;
    const MED_FINAL = 64;
    const MED_FIT = 128;
    const MEDAL_NAMES = ["Lv 10", "Lv 25", "Lv 50", "Fav. fruit", "Active week", "Max bond", "Final form", "Fit"];
    // ---- the wearer's exercise ----
    // EXP: level L needs L^3 points (Lv 16 = 4,096, Lv 36 = 46,656, Lv 100 = 1,000,000)
    const EXP_PER_ACTIVE_MIN = 10;          // each of your intensity minutes
    const HATCH_LEVEL = 5;
    const WILD_FULL_PER_DAY = 5;            // wild wins a day at full EXP, then a tenth
    const JOY_EVERY_MIN = 101;              // joy -1 this often: full to empty in a week untrained
    const EGG_STEPS = [0, 1000, 2000, 3000]; // steps to hatch: -, common, rare, legendary

    // ---- saved state ----
    var food = 80;          // TamaPoke's "fullness"
    var joy = 80;
    var energy = 80;
    var hygiene = 100;
    var poops = 0;
    var weight = 0;
    var ivAtk = 16;
    var ivDef = 16;
    var ivSpe = 16;
    var ivHp = 16;
    var trAtk = 0;
    var trDef = 0;
    var trSpe = 0;
    var berryKnown = false;
    var shiny = false;
    var ageMinutes = 0;
    var dex = 0;            // 0 = egg
    var careMistakes = 0;
    var sleeping = false;
    var sleepAuto = 0;
    var ceremony = 0;
    var lastEnd = 0;
    var dexReg = [0, 0, 0, 0, 0, 0, 0];       // 24 species per number
    var dexShiny = [0, 0, 0, 0, 0, 0, 0];
    var streak = 0;
    var bestStreak = 0;
    var lastCareDay = 0;
    var lastMilestone = 0;
    var bond = 0;
    var bondToday = 0;
    var medals = 0;
    var totalMedals = 0;
    var nick = "";
    var eggTarget = 1;
    var eggShiny = false;
    var eggTaps = 0;
    var mistakeCooldown = 0;
    var evoDeclinedLv = 0;
    var farDeclinedAge = 0;
    var starterPick = false;
    var evoPen = 0;
    var retirePending = false;
    var neglectTicks = 0;
    var drainPhase = 0;
    var goodTicks = 0;
    var lastSeen = 0;       // UTC epoch of the last minute applied
    var stepClaim = 0;      // bits: 2,500 / 5,000 / 10,000 paid today
    var stepDay = 0;
    var moves = [0, 0, 0, 0];   // move ids, 0 = empty
    var lastLearnLevel = 0;
    var learnQueue = [];        // level-up moves waiting for a free slot or your decision
    var badges = 0;             // bit n = gym n beaten on easy (the player's, kept across pets)
    var badgesHard = 0;         // ... and on hard
    var party = [];             // up to 6 past companions (frozen), then the box
    var box = [];
    var waiting = null;         // a newcomer with nowhere to go: party and box both full
    var lastTrained = 0;        // which stat the last training reward went to (0 STR, 1 DEF, 2 SPD)
    // saved apart under "fit" (so older saves still load)
    var actSeen = 0;            // start time of the newest recorded activity already paid
    var xpDay = 0;
    var xpToday = 0;            // bonus levels paid today
    var bonusLv = 0;            // levels this creature earned from your workouts
    var eggSteps = 0;           // steps walked with the current egg
    var eggNeed = 0;            // steps it needs (0: hatches by itself, the starter)
    var stepRead = 0;           // today's step count when last read
    var stepReadDay = 0;
    var weekPaid = 0;           // the last week whose intensity-minutes goal was met
    var moveAt = 0;
    var restless = false;       // your move bar is filling up
    var thumbKey = -2;          // which glance thumbnail is in storage
    var exp = 0;                // the creature's EXP (its level comes from it)
    var wildDay = 0;
    var wildWins = 0;           // wild wins today (EXP shrinks after a few)

    // ---- the trainer (you), saved under "trainer" ----
    var trName = null;          // null until the first-run guide is done
    var trGender = 0;           // which character: 0 or 1
    var trJoined = 0;           // when you started (UTC epoch)
    var tpw10 = 30;             // your trainings a week x10: what you said, then averaged with what you do
    var weekCnt = 0;            // recorded trainings this week
    var weekKey = 0;            // which week weekCnt counts
    var activeTotal = 0;        // intensity minutes since you started
    var lastAM = -1;            // the week's intensity-minute total when last read (-1: not yet)

    // ---- what happened while you were away (shown when you come back; not saved) ----
    var repMin = 0;
    var repExp = 0;
    var repLv = 0;
    var repJoy = 0;
    var repWork = 0;
    var repSteps = 0;
    var repBag = [0, 0, 0, 0];

    // ---- HP: what battles leave it with, saved under "hp" ----
    // Lost in battle and kept afterwards: the next battle starts from it. It refills by itself
    // from empty in 15 minutes; food, a recorded activity and the training games speed it up.
    // (tuning: HP_FULL_SEC, HP_FRUIT, HP_GAME, HP_WORKOUT at the top of this file)
    var hpv = [100, 0];         // HP (0-100 %) at the moment hpv[1] (UTC epoch); see Hp.mc

    // ---- the fruit bag: apples, blue berries, oranges, candy. Earned by being active ----
    var bag = [6, 1, 1, 1];
    var amFruit = 0;            // intensity minutes toward the next apple
    const MIN_PER_APPLE = 20;

    // ---- on-screen moments (not saved) ----
    var screenOff = true;   // true while replaying minutes the app was closed
    var heartUntil = 0;
    var eatUntil = 0;
    var eatItem = 0;
    var evolveUntil = 0;
    var prevDex = 0;
    var ceremonyUntil = 0;
    var toast = null;       // short message over the scene
    var toastUntil = 0;
    var pendingAnim = -1;   // one-shot sprite animation for the view
    var catchingUp = false;

    function initialize() {
        Math.srand(Time.now().value());
        load();
    }

    // ---------- helpers ----------

    function rnd(n) { return Math.rand().abs() % n; }
    function ms() { return System.getTimer(); }
    function min(a, b) { return a < b ? a : b; }

    function clamp100(v) {
        if (v < 0) { return 0; }
        if (v > 100) { return 100; }
        return v;
    }

    // Falls by d but never below the floor fl (and never raises a value already under it).
    function dropTo(v, d, fl) {
        if (v <= fl) { return v; }
        return (v - fl > d) ? v - d : fl;
    }

    function localOffset() { return System.getClockTime().timeZoneOffset; }
    function today() { return lastSeen == 0 ? 0 : (lastSeen + localOffset()) / 86400; }
    function hourAt(epoch) { return ((epoch + localOffset()) / 3600) % 24; }

    function isEgg() { return dex == 0; }
    function lowestStat() {
        var m = food;           // joy follows your training now: not counted as neglect
        // energy held down by your own Body Battery is not the pet's neglect
        if (energy < m && (bbNow < 0 || energy < bbNow)) { m = energy; }
        if (hygiene < m) { m = hygiene; }
        return m;
    }
    function inTotalNeglect() { return food == 0 && joy == 0 && energy == 0 && hygiene == 0; }

    function level() {
        return Lvl.levelFor(exp);
    }

    function name() {
        if (isEgg()) { return Tr.t("Egg"); }
        return nick.length() > 0 ? nick : SpriteIndex.name(dex);
    }

    function isRegistered(n) { return (dexReg[(n - 1) / 24] >> ((n - 1) % 24)) & 1; }
    function registeredCount() {
        var c = 0;
        for (var n = 1; n <= Dex.COUNT; n++) { c += isRegistered(n); }
        return c;
    }
    function registerSpecies(n) {
        dexReg[(n - 1) / 24] |= 1 << ((n - 1) % 24);
        if (shiny) { dexShiny[(n - 1) / 24] |= 1 << ((n - 1) % 24); }
    }

    // Better eggs for an active life: weeks in a row meeting your intensity-minutes goal, this
    // week's progress toward it, and the bond.
    function careBonus() {
        var s = streak > 10 ? 10 : streak;
        return s + weekPct() / 25 + bond / 25;
    }

    function hasMedal(m) { return (medals & m) != 0; }
    function showHeart() { return ms() < heartUntil; }
    function eating() { return ms() < eatUntil; }
    function evolving() { return ms() < evolveUntil; }

    function say(text, forMs) {
        toast = text;
        toastUntil = ms() + forMs;
    }
    function toastText() { return ms() < toastUntil ? toast : null; }

    // ---------- stats (stat = base + level + IV*level/100 + training) ----------

    // [EXP into this level, EXP this level needs] for the EXP bar
    function expProgress() {
        var l = level();
        if (l >= MAX_LEVEL) { return [1, 1]; }
        return [exp - Lvl.expFor(l), Lvl.expFor(l + 1) - Lvl.expFor(l)];
    }

    // EXP from your activity and from battles. A new level can teach a move or allow evolving.
    function gainExp(n) {
        if (isEgg() || n <= 0) { return 0; }
        var before = level();
        exp += n;
        if (exp > Lvl.expFor(MAX_LEVEL)) { exp = Lvl.expFor(MAX_LEVEL); }
        var up = level() - before;
        repExp += n;
        // the rest of the team (the party) gets a quarter of it
        var share = n / 4;
        for (var i = 0; share > 0 && i < party.size(); i++) {
            var m = party[i];
            if (m.size() < 13) { m.add(0); }                            // bond, for older saves
            if (m.size() < 14) { m.add(Lvl.expFor(m[3])); }             // its EXP from its level
            var e = m[13] + share;
            if (e > Lvl.expFor(MAX_LEVEL)) { e = Lvl.expFor(MAX_LEVEL); }
            m[13] = e;
            m[3] = Lvl.levelFor(e);
        }
        if (up > 0) {
            repLv += up;
            checkLearnGates();
            checkMedals();
            heartUntil = ms() + HEART_MS;
            pendingAnim = 3;
            say(name() + Tr.t(" grew to Lv.") + level() + "!", 3500);
            if (!catchingUp) { Sfx.vibe(Sfx.MEDAL); }
        }
        return n;
    }

    // A battle's EXP for the pet (only if it fought): wild foes pay full a few times a day, gym
    // leaders double on hard, link battles the most. A loss still teaches a quarter.
    // pts: what the creatures beaten are worth (BattleView: base yield x level / 7 each, FireRed's
    // rule). A trainer's or a friend's pay 1.5 times that (a hard gym twice that again); wild wins
    // pay in full a few times a day, then a tenth; a lost battle pays a tenth of a win.
    function battleExp(kind, pts, won, hardGym) {
        var n = 0;
        if (kind == 0) {
            var d = today();
            if (d != wildDay) { wildDay = d; wildWins = 0; }
            if (won) { wildWins++; }
            n = pts;
            if (wildWins > WILD_FULL_PER_DAY) { n = n / 10; }
        } else if (kind == 1) {
            n = hardGym ? pts * 3 : pts * 3 / 2;     // x1.5, a hard gym x3
        } else {
            n = pts * 3 / 2;                         // a friend's team: a trainer's
        }
        if (!won) { n = n / 10; }           // a lost battle: a tenth of what winning it pays
        if (n < 1) { n = 1; }
        gainExp(n);
        save();
        return n;
    }

    function calcStat(base, iv, tr) { return base + level() + iv * level() / 100 + tr; }
    function atkStat() { return isEgg() ? 0 : calcStat(Dex.row(dex)[4], ivAtk, trAtk); }
    function defStat() { return isEgg() ? 0 : calcStat(Dex.row(dex)[5], ivDef, trDef); }
    function speStat() { return isEgg() ? 0 : calcStat(Dex.row(dex)[6], ivSpe, trSpe); }
    function vitStat() { return isEgg() ? 0 : calcStat(Dex.row(dex)[3], ivHp, 10); }
    function spaStat() { return isEgg() ? 0 : calcStat(Dex.row(dex)[7], ivAtk, trAtk); }   // special uses ATK's IV/training
    function spdStat() { return isEgg() ? 0 : calcStat(Dex.row(dex)[8], ivDef, trDef); }
    function trMaxFor(iv) { return 70 + (30 * iv) / 31; }

    // ---------- time ----------

    // ---------- the wearer: Body Battery and sleep window ----------
    // The pet's energy is your Body Battery, minute by minute (the ENE bar shows it), and it sleeps
    // in your sleep window from the watch's user profile. Without Body Battery data it drains awake
    // and recharges asleep as before.
    var bbTimes = [];      // sample times, newest first
    var bbVals = [];
    var bbLoaded = 0;
    var bbNow = -1;        // your Body Battery at the minute being replayed, -1 if unknown
    var userSleep = 22 * 3600;
    var userWake = 6 * 3600;

    // Returns true when it read the history this call (the caller then leaves the replay for the
    // next call: both together are too much work for one).
    function loadWearer() {
        var now = Time.now().value();
        if (bbLoaded != 0 && now - bbLoaded < 120) { return false; }
        bbLoaded = now;
        bbTimes = [];
        bbVals = [];
        bbCursor = 0;
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            // only as far back as the minutes still to replay (plus an hour)
            var span = lastSeen > 0 ? now - lastSeen + 3600 : 3600;
            if (span > MAX_CATCHUP_MIN * 60) { span = MAX_CATCHUP_MIN * 60; }
            if (span < 3600) { span = 3600; }
            var it = SensorHistory.getBodyBatteryHistory({:period => new Time.Duration(span),
                                                          :order => SensorHistory.ORDER_NEWEST_FIRST});
            if (it != null) {
                var s = it.next();
                while (s != null && bbTimes.size() < 400) {
                    if (s.data != null && s.when != null) {
                        bbTimes.add(s.when.value());
                        bbVals.add(s.data.toNumber());
                    }
                    s = it.next();
                }
            }
        }
        if (Toybox has :UserProfile) {
            var p = UserProfile.getProfile();
            if (p != null && (p has :sleepTime) && p.sleepTime != null && p.wakeTime != null) {
                userSleep = p.sleepTime.value();
                userWake = p.wakeTime.value();
            }
        }
        return true;
    }

    // Body Battery at time t: the latest sample at or before t (the oldest one if t is older).
    // The replayed minutes only move forward, so the search resumes where the last one stopped
    // (scanning the whole history every minute trips the watchdog on a long catch-up).
    var bbCursor = 0;
    function bbAt(t) {
        var n = bbTimes.size();
        if (n == 0) { return -1; }
        if (bbCursor >= n || (bbCursor < n - 1 && bbTimes[bbCursor] > t)) { bbCursor = n - 1; }   // went back: restart
        while (bbCursor > 0 && bbTimes[bbCursor - 1] <= t) { bbCursor--; }
        return bbVals[bbCursor];
    }

    function userAsleepAt(t) {
        var s = ((t + localOffset()) % 86400 + 86400) % 86400;
        if (userSleep == userWake) { return false; }
        if (userSleep < userWake) { return s >= userSleep && s < userWake; }
        return s >= userSleep || s < userWake;
    }

    // Replays the minutes since lastSeen, a little per call (the view's timer keeps calling, and
    // each call is its own watchdog budget). Progress is saved as it goes, so an app that is shut
    // mid-replay picks up where it stopped instead of starting the same long replay again.
    var chunksSinceSave = 0;
    function update() {
        if (loadWearer() && catchingUp) { return; }
        if (ceremony != CER_NONE && ms() > ceremonyUntil) {
            newEgg();
            return;
        }
        var now = Time.now().value();
        if (lastSeen == 0) { lastSeen = now; }
        var mins = (now - lastSeen) / 60;
        if (mins > MAX_CATCHUP_MIN) {
            lastSeen = now - MAX_CATCHUP_MIN * 60;
            mins = MAX_CATCHUP_MIN;
        }
        catchingUp = mins > CHUNK;
        var n = mins > CHUNK ? CHUNK : mins;
        var t0 = ms();
        var done = 0;
        while (done < n) {
            lastSeen += 60;
            tick();
            done++;
            if (ms() - t0 > CHUNK_MS) { break; }
        }
        if (done < mins) {
            catchingUp = true;       // more to replay: the next call goes on
            chunksSinceSave++;
            if (chunksSinceSave >= 15) { chunksSinceSave = 0; save(); }
            return;
        }
        catchingUp = false;
        chunksSinceSave = 0;
        if (screenOff) {
            setScreenOff(false);     // caught up: you are looking at it now
        }
        if (bbVals.size() > 0) { bbNow = bbVals[0]; energy = bbNow; }   // your Body Battery right now
        claimSteps();
        // the day's gift: 2 pieces of fruit the first time you look in a day (missed days don't add up)
        var d = today();
        if (!isEgg() && d > 0 && d != $.giftDay) {
            $.giftDay = d;
            for (var k = 0; k < 2; k++) {
                var item = rnd(3);
                if (bag[item] < 99) { bag[item] += 1; }
            }
            say(Tr.t("Daily gift: 2 fruit!"), 5000);
            save();
        }
        if (done > 0) { save(); }
    }

    function tick() {
        if (ceremony != CER_NONE || starterPick) { return; }
        ageMinutes++;
        if (isEgg()) {
            if (eggNeed == 0 && ageMinutes >= 3) { hatch(); }   // step eggs hatch by walking
            return;
        }
        if (ageMinutes % JOY_EVERY_MIN == 0 && joy > 0) { joy--; }   // a week untrained: empty
        applyAutoSleep();
        bbNow = bbAt(lastSeen);
        var cap = bbNow < 0 ? 100 : bbNow;
        if (sleeping) {
            energy = energy + 6 > cap ? cap : energy + 6;   // recharges (without Body Battery data)
            if (bbNow >= 0) { energy = bbNow; }
            if (weight > 0 && ageMinutes % 3 == 0) { weight--; }
            // asleep with you, it doesn't get hungry (TamaPoke's slow night drain is gone)
            if (ageMinutes % (6 * DRAIN_EVERY) == 0) { hygiene = dropTo(hygiene, 1, 45); }
            defTick(true);
            checkMedals();
            return;
        }
        drainPhase = (drainPhase + 1) % DRAIN_EVERY;
        var drainNow = drainPhase == 0;
        // food: a full bar lasts about 12 waking hours (TamaPoke's pace emptied it in 3.5, faster
        // than a watch you glance at can keep up with)
        if (ageMinutes % FOOD_EVERY_MIN == 0) { food = clamp100(food - 1); }
        if (drainNow) {
            energy = clamp100(energy - 1);
            if (food > 40 && poops < 3 && rnd(200) < 15) { poops++; }   // half TamaPoke's rate
            if (ageMinutes % (2 * DRAIN_EVERY) == 0) { hygiene = clamp100(hygiene - 1 - 4 * poops); }
            if (weight > 50) { energy = clamp100(energy - 1); }
        }
        if (energy > cap) { energy = cap; }                 // never livelier than you
        if (bbNow >= 0) { energy = bbNow; }                 // with Body Battery, its energy IS yours
        if (weight > 0 && ageMinutes % 3 == 0) { weight--; }
        defTick(false);
        if (mistakeCooldown > 0) { mistakeCooldown--; }
        if (lowestStat() <= 10 && mistakeCooldown == 0) {
            careMistakes++;
            mistakeCooldown = 60;
            if (bond > 1) { bond--; }
        }
        checkMedals();
        if (inTotalNeglect()) {
            if (neglectTicks < RUNAWAY_TICKS) { neglectTicks++; }
        } else {
            neglectTicks = 0;
        }
    }

    // Calm forges defence: an hour of wellbeing (or rest) = +1 DEF training.
    function defTick(resting) {
        if (!resting && lowestStat() < 40) { return; }
        goodTicks++;
        if (goodTicks < DEF_TRAIN_TICKS) { return; }
        goodTicks = 0;
        if (trDef < trMaxFor(ivDef)) { trDef++; }
    }

    // Night is your own sleep window (bedtime to wake time in the watch's user profile). With the
    // app closed then it goes to bed with you, and it wakes when you do or when you open the app.
    // (There is no sleep button any more: an old save's put-to-bed counts as asleep with you.)
    // Also the watch's own sleep mode for the minute being lived now (not a replayed one).
    function isNightHour() { return userAsleepAt(lastSeen) || (!catchingUp && $.sleepModeNow()); }

    function applyAutoSleep() {
        if (isEgg() || ceremony != CER_NONE) { return; }
        var night = isNightHour();
        if (screenOff && night && !sleeping && sleepAuto != SLEEP_PLAYER) {
            sleeping = true;
            sleepAuto = SLEEP_AUTO;
        }
        if (!night && sleeping && sleepAuto == SLEEP_AUTO) {   // you are up: so is it
            sleeping = false;
            sleepAuto = SLEEP_NONE;
        }
        if (!night && sleepAuto == SLEEP_PLAYER) { sleepAuto = SLEEP_NONE; }
    }

    function setScreenOff(off) {
        screenOff = off;
        if (!off && sleeping && sleepAuto == SLEEP_AUTO) {
            sleeping = false;
            sleepAuto = SLEEP_NONE;
        }
        applyAutoSleep();
    }

    // ---------- eggs ----------

    function newEgg() {
        ceremony = CER_NONE;
        neglectTicks = 0;
        weight = 0;
        dex = 0;
        prevDex = 0;
        eggTarget = pickEggSpecies();
        starterPick = registeredCount() == 0;
        var shinyBase = (lastEnd == CER_FAREWELL ? 24 : 48) - careBonus();
        if (shinyBase < 8) { shinyBase = 8; }
        eggShiny = rnd(shinyBase) == 0;
        evoPen = retirePending ? EVO_PENALTY_LEVELS : 0;
        retirePending = false;
        eggTaps = 0;
        food = 80; joy = 100; energy = 80; hygiene = 100;
        poops = 0;
        ageMinutes = 0;
        careMistakes = 0;
        mistakeCooldown = 0;
        sleeping = false;
        sleepAuto = SLEEP_NONE;
        eggSteps = 0;
        eggNeed = starterPick ? 0 : EGG_STEPS[eggRarity()];
        var info = ActivityMonitor.getInfo();
        stepRead = (info != null && info.steps != null) ? info.steps : 0;   // only steps from now on
        stepReadDay = today();
        save();
    }

    // Is any form of this line still missing from the Pokedex?
    function lineHasUnregistered(base) {
        var cur = base;
        for (var guard = 0; cur >= 1 && cur <= Dex.COUNT && guard < 6; guard++) {
            if (isRegistered(cur) == 0) { return true; }
            if (cur == Dex.EEVEE) {
                for (var i = 0; i < Dex.EEVEE_EVOS.size(); i++) {
                    if (isRegistered(Dex.EEVEE_EVOS[i]) == 0) { return true; }
                }
                return false;
            }
            cur = Dex.evolvesTo(cur);
        }
        return false;
    }

    // Rarity tier first (a goodbye blesses it, a runaway curses it; care helps), then a
    // species of that tier, preferring lines you have not finished.
    function pickEggSpecies() {
        if (registeredCount() == 0) { return Dex.STARTERS[rnd(3)]; }
        var tier = Dex.R_COMMON;
        if (lastEnd != CER_RUNAWAY) {
            var blessed = lastEnd == CER_FAREWELL;
            var rare = (blessed ? 45 : 27) + careBonus();
            var leg = registeredCount() >= 25 ? (blessed ? 10 : 3) + careBonus() / 3 : 0;
            var r = rnd(100);
            if (r < leg) { tier = Dex.R_LEGEND; }
            else if (r < leg + rare) { tier = Dex.R_RARE; }
        }
        for (var pass = 0; pass < 2; pass++) {
            for (var t = tier; t >= Dex.R_COMMON; t--) {
                var cand = [];
                for (var n = 1; n <= Dex.COUNT; n++) {
                    if (Dex.rarity(n) != t) { continue; }
                    if (pass == 0 && !lineHasUnregistered(n)) { continue; }
                    cand.add(n);
                }
                if (cand.size() > 0) { return cand[rnd(cand.size())]; }
            }
        }
        return Dex.STARTERS[rnd(3)];
    }

    function eggRarity() { return Dex.rarity(eggTarget); }

    function chooseStarter(n) {
        eggTarget = n;
        starterPick = false;
        save();
    }

    function eggTap() {
        if (!isEgg() || starterPick) { return; }
        if (eggNeed > 0) {
            var left = eggNeed - eggSteps;
            say((left > 0 ? left : 0) + Tr.t(" steps to go!"), 2500);
            return;
        }
        eggTaps++;
        if (eggTaps >= 3) { hatch(); } else { save(); }
    }

    function rollIV(bonus) {
        var v = 8 + rnd(24) + bonus / 2;
        return v > 31 ? 31 : v;
    }

    function rollIVs() {
        var b = careBonus();
        ivAtk = rollIV(b); ivDef = rollIV(b); ivSpe = rollIV(b); ivHp = rollIV(b);
        if (Dex.rarity(dex) == Dex.R_LEGEND) {     // legendaries: 3 of 4 perfect
            var skip = rnd(4);
            if (skip != 0) { ivAtk = 31; }
            if (skip != 1) { ivDef = 31; }
            if (skip != 2) { ivSpe = 31; }
            if (skip != 3) { ivHp = 31; }
        }
        if (shiny) {                               // shinies: every IV at least 20
            if (ivAtk < 20) { ivAtk = 20; }
            if (ivDef < 20) { ivDef = 20; }
            if (ivSpe < 20) { ivSpe = 20; }
            if (ivHp < 20) { ivHp = 20; }
        }
    }

    function hatch() {
        Hp.set(self, 100);
        dex = eggTarget;
        shiny = eggShiny;
        rollIVs();
        trAtk = 0; trDef = 0; trSpe = 0;
        goodTicks = 0;
        berryKnown = false;
        bond = 0;
        bondToday = 0;
        medals = 0;
        nick = "";
        registerSpecies(dex);
        moves = [0, 0, 0, 0];
        learnQueue = [];
        lastLearnLevel = 0;
        bonusLv = 0;
        exp = Lvl.expFor(HATCH_LEVEL);
        joy = 100;
        checkLearnGates();
        checkMedals();
        pendingAnim = 3;   // hop
        Sfx.vibe(Sfx.HATCH);
        say(SpriteIndex.name(dex) + Tr.t(" hatched!"), 3000);
        save();
    }

    // ---------- evolution ----------

    function canEvolveNow() {
        if (isEgg() || sleeping || ceremony != CER_NONE) { return false; }
        if (Dex.evolvesTo(dex) == 0) { return false; }
        return level() >= Dex.evolveLevel(dex) + careMistakes + evoPen && lowestStat() >= 40;
    }

    function wantEvolveButton() { return canEvolveNow() && level() > evoDeclinedLv; }
    function declineEvolve() { evoDeclinedLv = level(); save(); }

    function evolve() {
        if (!canEvolveNow()) { return; }
        prevDex = dex;
        var next = Dex.evolvesTo(dex);
        if (dex == Dex.EEVEE) {    // toward a branch you are still missing
            var fresh = [];
            for (var i = 0; i < Dex.EEVEE_EVOS.size(); i++) {
                if (isRegistered(Dex.EEVEE_EVOS[i]) == 0) { fresh.add(Dex.EEVEE_EVOS[i]); }
            }
            next = fresh.size() > 0 ? fresh[rnd(fresh.size())] : Dex.EEVEE_EVOS[rnd(3)];
        }
        dex = next;
        registerSpecies(dex);
        lastLearnLevel = level() - 1;   // the new form may gate a move at this very level
        checkLearnGates();
        evolveUntil = ms() + EVOLVE_ANIM_MS;
        Sfx.vibe(Sfx.EVOLVE);
        say(SpriteIndex.name(prevDex) + Tr.t(" evolved into ") + SpriteIndex.name(dex) + "!", 4000);
        checkMedals();
        save();
    }

    // ---------- endings ----------

    function canFarewellNow() {
        return !isEgg() && !sleeping && ceremony == CER_NONE &&
               Dex.evolvesTo(dex) == 0 && ageMinutes >= FAREWELL_AGE_MIN;
    }
    function wantFarewellButton() { return canFarewellNow() && ageMinutes >= farDeclinedAge; }
    function declineFarewell() { farDeclinedAge = ageMinutes + 1440; save(); }

    function canRunawayNow() {
        return !isEgg() && !sleeping && ceremony == CER_NONE &&
               neglectTicks >= RUNAWAY_TICKS && inTotalNeglect();
    }

    function canRetireNow() { return !isEgg() && !sleeping && ceremony == CER_NONE && !starterPick; }

    // A goodbye hands the creature to the party (the box when it is full).
    // [dex, nick, shiny, level, ivAtk, ivDef, ivSpe, ivHp, trAtk, trDef, trSpe, moves]
    function snapshotForParty() {
        var m = [dex, nick, shiny, level(), ivAtk, ivDef, ivSpe, ivHp, trAtk, trDef, trSpe,
                 [moves[0], moves[1], moves[2], moves[3]], bond, exp];
        // party first, then the box; only when both are full is it your choice (TamaPoke)
        if (party.size() < PARTY_MAX) {
            party.add(m);
            say(memberName(m) + Tr.t(" joined your party!"), 3500);
        } else if (box.size() < BOX_MAX) {
            box.add(m);
            say(memberName(m) + Tr.t(" went to the Pokébox"), 3500);
        } else {
            waiting = m;
        }
    }

    // Party and box full: the newcomer replaces a party member, or is let go.
    function placeWaiting(slot) {
        if (waiting == null) { return; }
        if (slot >= 0 && slot < party.size()) {
            party[slot] = waiting;
            say(memberName(waiting) + Tr.t(" joined your party!"), 3500);
        }
        waiting = null;
        save();
    }

    function startCeremony(kind) {
        if (isEgg() || ceremony != CER_NONE) { return; }
        if (kind == CER_FAREWELL && !retirePending) { snapshotForParty(); }   // a release or a run-away: gone
        lastEnd = kind;
        ceremony = kind;
        ceremonyUntil = ms() + CEREMONY_MS;
        if (kind != CER_RUNAWAY) { heartUntil = ceremonyUntil; }
        save();
    }

    function startFarewell() { startCeremony(CER_FAREWELL); }
    function startRunaway() { startCeremony(CER_RUNAWAY); }
    // Releasing your partner: it is gone for good (it does not join the team). If it had earned
    // its goodbye (final form, 3 days in it), the next egg is blessed as after a goodbye; if not,
    // the next egg is plain, with no other cost.
    function release() {
        if (!canRetireNow()) { return; }
        var earned = canFarewellNow();
        startCeremony(CER_RELEASE);
        if (earned) {
            lastEnd = CER_FAREWELL;
            save();
        }
    }

    // ---------- care ----------

    function canAct() { return !isEgg() && !sleeping && ceremony == CER_NONE; }

    // Each species has a hidden favourite of the three fruits.
    function lovesBerry(color) { return !isEgg() && dex % 3 == color; }

    function feedFruit(color) {
        if (!canAct()) { return; }
        if (bag[color] <= 0) { say(Tr.t("None left: get active!"), 2500); return; }
        bag[color]--;
        if (lovesBerry(color)) {
            food = clamp100(food + 49);        // 40 % more than TamaPoke's 35
            joy = clamp100(joy + 2);
            heartUntil = ms() + HEART_MS;
            if (!berryKnown) { say(Tr.t("It loves this one!"), 2500); }
            berryKnown = true;
            addBond(2);
            Hp.heal(self, HP_FRUIT + 10);
        } else {
            food = clamp100(food + 35);        // (25)
            Hp.heal(self, HP_FRUIT);
        }
        startEating(color);
    }

    function feedCandy() {
        if (!canAct()) { return; }
        if (bag[FOOD_CANDY] <= 0) { say(Tr.t("No candy: weekly goal!"), 2500); return; }
        bag[FOOD_CANDY]--;
        food = clamp100(food + 14);            // (10)
        joy = clamp100(joy + 2);
        weight = clamp100(weight + 12);
        Hp.heal(self, HP_FRUIT / 2);
        startEating(FOOD_CANDY);
    }

    function startEating(item) {
        eatItem = item;
        eatUntil = ms() + EAT_ANIM_MS;
        pendingAnim = 2;   // eat
        registerCare();
        save();
    }

    function play() {
        if (!canAct()) { return; }
        joy = clamp100(joy + 3);
        if (bbNow < 0) { energy = clamp100(energy - 10); }   // with Body Battery, energy is only yours
        food = clamp100(food - 5);
        heartUntil = ms() + HEART_MS;
        pendingAnim = 3;   // hop
        addBond(2);
        registerCare();
        save();
    }

    var bathUntil = 0;

    function rename(n) {
        nick = n;
        save();
    }

    function bathing() { return ms() < bathUntil; }

    function clean() {
        if (ceremony != CER_NONE || isEgg()) { return; }
        bathUntil = ms() + 2500;
        poops = 0;
        hygiene = 100;
        addBond(1);
        registerCare();
        save();
    }

    function caress() {
        if (!canAct()) { return; }
        joy = clamp100(joy + 1);
        heartUntil = ms() + HEART_MS;
        addBond(1);
        registerCare();
        save();
    }

    // ---------- bond, streak, medals ----------

    // The first care of each day: the player's streak and the creature's bond.
    function registerCare() {
        if (isEgg() || ceremony != CER_NONE) { return; }
        var d = today();
        if (d == 0 || d == lastCareDay) { return; }
        lastCareDay = d;
        bondToday = 0;
        bond = clamp100(bond + 4);
        checkMedals();
    }

    function addBond(amt) {
        if (bondToday >= 20) { return; }
        bond = clamp100(bond + amt);
        bondToday += amt;
    }

    function checkMedals() {
        if (isEgg()) { return; }
        var before = medals;
        if (level() >= 10) { medals |= MED_LV10; }
        if (level() >= 25) { medals |= MED_LV25; }
        if (level() >= 50) { medals |= MED_LV50; }
        if (berryKnown) { medals |= MED_BERRY; }
        if (streak >= 1) { medals |= MED_STREAK7; }        // a week's intensity goal met
        if (bond >= 100) { medals |= MED_BOND; }
        if (Dex.evolvesTo(dex) == 0) { medals |= MED_FINAL; }
        if (weight == 0 && level() >= 5 && careMistakes == 0) { medals |= MED_FIT; }
        var gained = medals & ~before;
        for (var i = 0; i < 8; i++) {
            if ((gained >> i) & 1) {
                totalMedals++;
                if (!catchingUp) { Sfx.vibe(Sfx.MEDAL); }
                say(Tr.t("Medal: ") + Tr.t(MEDAL_NAMES[i]), 4000);
            }
        }
    }

    // ---------- steps ----------

    // Walking pays the pet, three milestones a day, each once.
    function stepGoal() {
        var info = ActivityMonitor.getInfo();
        var g = (info != null && (info has :stepGoal) && info.stepGoal != null) ? info.stepGoal : 0;
        return g > 0 ? g : 10000;
    }

    // A new day since the steps were last read: the rest of that day (a run after the app was last
    // opened) and any whole days the app wasn't opened, from the watch's daily history, so those
    // steps still count toward eggs, hatching, EXP and apples.
    function missedSteps(lastDay, readThen, today) {
        if (lastDay <= 0 || !(ActivityMonitor has :getHistory)) { return 0; }
        var hist = ActivityMonitor.getHistory();
        if (hist == null) { return 0; }
        var n = 0;
        for (var i = 0; i < hist.size(); i++) {
            var h = hist[i];
            if (h == null || h.startOfDay == null || h.steps == null) { continue; }
            var day = (h.startOfDay.value() + localOffset()) / 86400;
            if (day == lastDay) { n += h.steps > readThen ? h.steps - readThen : 0; }
            else if (day > lastDay && day < today) { n += h.steps; }
        }
        return n;
    }

    // Your step goal in thirds (TamaPoke paid at 2,500 / 5,000 / 10,000), steps hatch eggs, the
    // floors goal trains DEF; then workouts, the weekly intensity goal and the move bar.
    function claimSteps() {
        var info = ActivityMonitor.getInfo();
        if (info == null) { return; }
        var steps = info.steps != null ? info.steps : 0;
        var d = today();
        var missed = 0;
        if (d != stepReadDay) {
            missed = missedSteps(stepReadDay, stepRead, d);
            stepReadDay = d;
            stepRead = 0;
        }
        var delta = steps - stepRead;
        if (delta < 0) { delta = steps; }
        delta += missed;
        stepRead = steps;
        if (delta > 0) { repSteps += delta; }
        Incubator.onSteps(self, delta);                 // bonus eggs: one per 15,000 steps
        StepBank.onSteps(self, delta);                  // EXP and apples, the remainder carried over
        if (isEgg() && !starterPick && eggNeed > 0 && ceremony == CER_NONE) {
            eggSteps += delta;
            var stage = eggSteps * 3 / eggNeed;
            eggTaps = stage > 2 ? 2 : stage;              // the shell cracks as you walk
            if (eggSteps >= eggNeed) { hatch(); }
            return;
        }
        if (isEgg() || ceremony != CER_NONE) { return; }
        if (d != stepDay) { stepDay = d; stepClaim = 0; }
        var g = stepGoal();
        if (steps >= g / 3 && (stepClaim & 1) == 0) {
            stepClaim |= 1;
            giveFruit(0, 1);
            joy = clamp100(joy + 2);
            repJoy += 2;
            stepToast(g / 3);
        }
        if (steps >= 2 * g / 3 && (stepClaim & 2) == 0) {
            stepClaim |= 2;
            giveFruit(0, 1);
            joy = clamp100(joy + 3);
            repJoy += 3;
            if (bbNow < 0) { energy = clamp100(energy + 10); }   // with Body Battery, energy is only yours
            addBond(3);
            stepToast(2 * g / 3);
        }
        if (steps >= g && (stepClaim & 4) == 0) {
            stepClaim |= 4;
            rewardTraining(3);
            giveFruit(0, 1);
            giveFruit(1 + rnd(2), 1);
            joy = clamp100(joy + 5);
            repJoy += 5;
            addBond(5);
            stepToast(g);
        }
        if ((info has :floorsClimbed) && (info has :floorsClimbedGoal) && info.floorsClimbed != null && info.floorsClimbedGoal != null &&
            info.floorsClimbedGoal > 0 && info.floorsClimbed >= info.floorsClimbedGoal && (stepClaim & 8) == 0) {
            stepClaim |= 8;
            trDef = min(trDef + 2, trMaxFor(ivDef));
            heartUntil = ms() + HEART_MS;
            if (!catchingUp) { Sfx.vibe(Sfx.STEPS); }
            say(Tr.t("FLOORS GOAL! DEF +2"), 3500);
            save();
        }
        claimWorkouts();                // first: what it pays, the intensity minutes don't again
        claimActive(info);
        claimWeek(info);
        checkMoveBar(info);
    }

    // ---------- workouts, the active week, the move bar ----------

    // Your intensity minutes are the creature's EXP (10 a minute), less those a recorded activity
    // already paid for (amCredit; claimWorkouts runs first). Read as the week's total, so a drop
    // means a new week started (and the last week's credit no longer applies).
    function claimActive(info) {
        if (isEgg() || !(info has :activeMinutesWeek) || info.activeMinutesWeek == null) { return; }
        var total = info.activeMinutesWeek.total;
        if (total == null) { return; }
        if (lastAM < 0) { lastAM = total; return; }       // counting starts now
        var delta = total >= lastAM ? total - lastAM : total;
        if (total < lastAM) { $.amCredit = 0; }
        lastAM = total;
        if (delta <= 0) { return; }
        activeTotal += delta;
        var c = $.amCredit < delta ? $.amCredit : delta;
        $.amCredit -= c;
        delta -= c;
        if (delta <= 0) { saveTrainer(); save(); return; }
        repMin += delta;
        amFruit += delta;
        if (amFruit >= MIN_PER_APPLE) { giveFruit(0, amFruit / MIN_PER_APPLE); amFruit = amFruit % MIN_PER_APPLE; }
        gainExp(delta * EXP_PER_ACTIVE_MIN);
        saveTrainer();
        save();
    }

    // Trainings a week: what you said at the start, then each finished week moves it a quarter of
    // the way toward what you actually did.
    function rollWeek() {
        var wk = thisWeek();
        if (weekKey == 0) { weekKey = wk; return; }
        var n = 0;
        while (weekKey < wk && n < 4) {
            tpw10 = (tpw10 * 3 + weekCnt * 10) / 4;
            if (tpw10 < 10) { tpw10 = 10; }
            weekCnt = 0;
            weekKey++;
            n++;
        }
        weekKey = wk;
    }

    // Joy one training gives back: your weekly number of them fills it from empty.
    function joyPerTraining() {
        var j = 1000 / (tpw10 < 10 ? 10 : tpw10);
        return j < 8 ? 8 : j;
    }

    // Each recorded activity pays once: EXP by its length and sport (workoutExp), joy (your weekly
    // target's worth), fruit, bond, HP, and training by sport: running SPD, strength ATK,
    // cycling/swimming DEF, anything else into a stat with room.

    function claimWorkouts() {
        if (!(Toybox has :UserProfile) || !(UserProfile has :getUserActivityHistory)) { return; }
        var nowS = Time.now().value();
        if ($.workoutsRead != 0 && nowS - $.workoutsRead < 60) { return; }   // once a minute is plenty
        $.workoutsRead = nowS;
        rollWeek();
        var it = UserProfile.getUserActivityHistory();
        if (it == null) { return; }
        var newest = actSeen;
        var got = [];
        var a = it.next();
        // the whole history (the watch keeps a few dozen; their order is not documented)
        for (var guard = 0; a != null && guard < 200; guard++) {
            if (a.startTime != null && a.duration != null) {
                var st = actStart(a.startTime.value());
                // paid once: newer than the last one paid, and not one still being recorded
                if (st > actSeen && st <= nowS) {
                    got.add([a.type, a.duration.value() / 60, a.distance]);
                    if (st > newest) { newest = st; }
                }
            }
            a = it.next();
        }
        actSeen = newest;
        if (got.size() == 0 || isEgg()) { return; }
        var msg = null;
        for (var i = 0; i < got.size(); i++) {
            var m = got[i][1];
            if (m < 5) { continue; }                       // a few minutes is not a workout
            weekCnt++;
            repWork++;
            giveFruit(1 + rnd(2), 1 + m / 45);        // a berry or an orange, one more each 45 min
            var jg = joyPerTraining();
            var before = joy;
            joy = clamp100(joy + jg);
            repJoy += joy - before;
            var pts = m / 5 > 12 ? 12 : m / 5;
            var sp = got[i][0];
            var label = Tr.t("WORKOUT");
            var gain = "";
            if (sp == Activity.SPORT_RUNNING) {
                label = Tr.t("RUN");
                var b = trSpe; trSpe = min(trSpe + pts, trMaxFor(ivSpe)); gain = Tr.t("SPD +") + (trSpe - b);
            } else if (sp == Activity.SPORT_CYCLING || sp == Activity.SPORT_SWIMMING) {
                label = sp == Activity.SPORT_CYCLING ? Tr.t("RIDE") : Tr.t("SWIM");
                var b = trDef; trDef = min(trDef + pts, trMaxFor(ivDef)); gain = Tr.t("DEF +") + (trDef - b);
            } else if (sp == Activity.SPORT_TRAINING || sp == Activity.SPORT_FITNESS_EQUIPMENT) {
                label = Tr.t("GYM");
                var b = trAtk; trAtk = min(trAtk + pts, trMaxFor(ivAtk)); gain = Tr.t("ATK +") + (trAtk - b);
            } else {
                if (sp == Activity.SPORT_WALKING) { label = Tr.t("WALK"); }
                else if (sp == Activity.SPORT_HIKING) { label = Tr.t("HIKE"); }
                var g2 = rewardTraining(pts / 2 > 0 ? pts / 2 : 1);
                gain = ([Tr.t("ATK"), Tr.t("DEF"), Tr.t("SPD")])[lastTrained] + " +" + g2;
            }
            addBond(3 + m / 20);
            Hp.heal(self, HP_WORKOUT);
            // its EXP, by length and sport; its intensity minutes won't be paid again
            var xp = gainExp(m * workoutExp(sp));
            $.amCredit += m * workoutIm2(sp) / 2;
            if ($.amCredit > 2000) { $.amCredit = 2000; }
            msg = label + " " + m + "m: +" + xp + " EXP, " + gain;
        }
        saveTrainer();
        if (msg == null) { return; }
        checkMedals();
        heartUntil = ms() + HEART_MS;
        pendingAnim = 3;
        if (!catchingUp) { Sfx.vibe(Sfx.MEDAL); }
        say(msg, 6000);
        save();
    }

    function hasReport() {
        return repMin > 0 || repExp > 0 || repWork > 0 || repJoy > 0 || repSteps > 0 ||
               repBag[0] + repBag[1] + repBag[2] + repBag[3] > 0 || Incubator.hasReport();
    }
    function clearReport() {
        repMin = 0; repExp = 0; repLv = 0; repJoy = 0; repWork = 0; repSteps = 0;
        repBag = [0, 0, 0, 0];
        Incubator.clearReport();
    }

    // Fruit into the bag (0 apple, 1 blue berry, 2 orange, 3 candy). A species' favourite is
    // dex % 3 of the first three, so the ones that loved the green berry now love the orange.
    function giveFruit(item, n) {
        bag[item] += n;
        if (bag[item] > 99) { bag[item] = 99; }
        repBag[item] += n;
    }


    // ---------- the trainer ----------

    function setTrainer(n, g, perWeek) {
        trName = n;
        trGender = g;
        if (trJoined == 0) { trJoined = Time.now().value(); }
        tpw10 = perWeek * 10;
        weekKey = thisWeek();
        joy = 100;                  // a new trainer starts with a happy partner
        saveTrainer();
        save();
    }

    function setTrainingsPerWeek(n) { tpw10 = n * 10; saveTrainer(); }
    function trainingsPerWeek() { return (tpw10 + 5) / 10; }

    function saveTrainer() {
        if (trName == null || wiped) { return; }
        Storage.setValue("trainer", [trName, trGender, trJoined, tpw10, weekCnt, weekKey, activeTotal, lastAM]);
    }

    function loadBag() {
        var b = Storage.getValue("bag") as Array?;
        if (b == null || b.size() < 5) { return; }     // first time: the starting bag
        bag = [b[0], b[1], b[2], b[3]];
        amFruit = b[4];
        $.amCredit = b.size() > 5 ? b[5] : 0;
        $.giftDay = b.size() > 6 ? b[6] : 0;
    }

    function loadTrainer() {
        var t = Storage.getValue("trainer") as Array?;
        if (t == null || t.size() < 8) { return; }
        trName = t[0]; trGender = t[1]; trJoined = t[2]; tpw10 = t[3]; weekCnt = t[4]; weekKey = t[5];
        activeTotal = t[6]; lastAM = t[7];
    }

    // Stats of a team member (the pet, or a party member [dex, nick, shiny, level, ivAtk, ivDef,
    // ivSpe, ivHp, trAtk, trDef, trSpe, moves, bond?]): [HP, ATK, DEF, SP.ATK, SP.DEF, SPEED].
    function memberStats(m) {
        var r = Dex.row(m[0]);
        var l = m[3];
        return [Battle.stat(r[3], m[7], l, 10), Battle.stat(r[4], m[4], l, m[8]), Battle.stat(r[5], m[5], l, m[9]),
                Battle.stat(r[7], m[4], l, m[8]), Battle.stat(r[8], m[5], l, m[9]), Battle.stat(r[6], m[6], l, m[10])];
    }

    // The pet in the party-member shape (bond last), for the team screens.
    function selfMember() {
        return [dex, nick, shiny, level(), ivAtk, ivDef, ivSpe, ivHp, trAtk, trDef, trSpe,
                [moves[0], moves[1], moves[2], moves[3]], bond, exp];
    }

    // Weeks in a row meeting your intensity-minutes goal are the streak now.
    var weekPctNow = 0;
    function weekPct() { return weekPctNow; }
    function thisWeek() { return (today() + 3) / 7; }   // weeks start on Monday

    function claimWeek(info) {
        var wk = thisWeek();
        if (wk == 0) { return; }
        if ((info has :activeMinutesWeek) && (info has :activeMinutesWeekGoal) && info.activeMinutesWeek != null &&
            info.activeMinutesWeekGoal != null && info.activeMinutesWeekGoal > 0) {
            var total = info.activeMinutesWeek.total;
            if (total == null) { total = 0; }
            weekPctNow = total * 100 / info.activeMinutesWeekGoal;
            if (weekPctNow > 100) { weekPctNow = 100; }
            if (total >= info.activeMinutesWeekGoal && weekPaid != wk) {
                streak = weekPaid == wk - 1 ? streak + 1 : 1;
                weekPaid = wk;
                if (streak > bestStreak) { bestStreak = streak; }
                joy = clamp100(joy + 15);
                addBond(5);
                heartUntil = ms() + HEART_MS;
                if (!catchingUp) { Sfx.vibe(Sfx.MEDAL); }
                giveFruit(3, 2);
                say(Tr.t("Weekly goal! ") + streak + (streak == 1 ? Tr.t(" week") : Tr.t(" weeks")) + Tr.t(" in a row"), 5000);
                checkMedals();
                save();
            }
        }
        if (weekPaid < wk - 1 && streak > 0) { streak = 0; save(); }   // a week went by unmet
    }


    // A filling move bar makes it restless (joy drips away); a walk that clears it is thanked.
    function checkMoveBar(info) {
        if (!(info has :moveBarLevel) || info.moveBarLevel == null || sleeping || catchingUp) { return; }
        var now = Time.now().value();
        if (info.moveBarLevel >= 3) {
            if (!restless) {
                restless = true;
                moveAt = now;
                say(Tr.t("Let's go for a walk!"), 4000);
            } else if (now - moveAt >= 600) {
                moveAt = now;
                joy = clamp100(joy - 3);
            }
        } else if (restless && info.moveBarLevel == 0) {
            restless = false;
            joy = clamp100(joy + 10);
            addBond(2);
            heartUntil = ms() + HEART_MS;
            say(Tr.t("Thanks for the walk!"), 3500);
            save();
        }
    }

    function stepToast(n) {
        heartUntil = ms() + HEART_MS;
        Sfx.vibe(Sfx.STEPS);
        say(n + Tr.t(" STEPS!"), 3500);
        save();
    }

    // Training into a random stat that still has room under its IV ceiling.
    function rewardTraining(amount) {
        var room = [];
        if (trAtk < trMaxFor(ivAtk)) { room.add(0); }
        if (trDef < trMaxFor(ivDef)) { room.add(1); }
        if (trSpe < trMaxFor(ivSpe)) { room.add(2); }
        if (room.size() == 0) { return 0; }
        var which = room[rnd(room.size())];
        lastTrained = which;
        if (which == 0) { trAtk = min(trAtk + amount, trMaxFor(ivAtk)); }
        else if (which == 1) { trDef = min(trDef + amount, trMaxFor(ivDef)); }
        else { trSpe = min(trSpe + amount, trMaxFor(ivSpe)); }
        return amount;
    }

    // ---------- moves (TamaPoke's checkLearnGates / acceptLearn / pendingLearnables) ----------

    function moveCount() {
        var n = 0;
        for (var i = 0; i < 4; i++) { if (moves[i] != 0) { n++; } }
        return n;
    }

    function knowsMove(mv) {
        return mv != 0 && moves.indexOf(mv) >= 0;
    }

    // Each level gained: a level-up move unlocked at it fills a free slot, or waits as an offer.
    function checkLearnGates() {
        if (isEgg() || ceremony != CER_NONE) { return; }
        var lvl = level();
        if (lvl <= lastLearnLevel) { return; }
        var L = Moves.learnset(dex);
        for (var i = 0; i + 1 < L.size(); i += 2) {
            var mv = L[i];
            var at = L[i + 1];
            if (at == 0 || at <= lastLearnLevel || at > lvl) { continue; }   // 0 = TM: no gate
            if (mv <= 0 || mv >= Moves.count() || knowsMove(mv)) { continue; }
            var free = moves.indexOf(0);
            if (free >= 0) { moves[free] = mv; continue; }
            if (learnQueue.size() < 8 && learnQueue.indexOf(mv) < 0) { learnQueue.add(mv); }
        }
        lastLearnLevel = lvl;
    }

    function learnOffer() { return learnQueue.size() > 0 ? learnQueue[0] : 0; }

    function acceptLearn(slot, mv) {
        if (slot < 0 || slot > 3) { return; }
        moves[slot] = mv;
        var q = learnQueue.indexOf(mv);
        if (q >= 0) { learnQueue.remove(mv); }
        save();
    }

    function declineLearn() {
        if (learnQueue.size() > 0) { learnQueue = learnQueue.slice(1, null); }
        save();
    }

    // Moves it could learn now: level-up ones reached and, from level 40, every TM.
    function pendingLearnables() {
        var out = [];
        if (isEgg()) { return out; }
        var lvl = level();
        var L = Moves.learnset(dex);
        for (var i = 0; i + 1 < L.size(); i += 2) {
            var mv = L[i];
            var at = L[i + 1];
            if (at == 0 && lvl < Moves.TM_LEVEL) { continue; }
            if (at > lvl) { continue; }
            if (mv <= 0 || mv >= Moves.count() || knowsMove(mv) || out.indexOf(mv) >= 0) { continue; }
            out.add(mv);
        }
        return out;
    }

    // ---------- training games (TamaPoke's trainStrength / trainSpeed / playResult) ----------

    // Training bag: 3 points = 1 STRENGTH, at most +18 a session, under the IV ceiling.
    function trainStrength(hits) {
        if (!canAct()) { return 0; }
        var gain = min(hits / 3, 18);
        var before = trAtk;
        trAtk = min(trAtk + gain, trMaxFor(ivAtk));
        gain = trAtk - before;
        if (bbNow < 0) { energy = dropTo(energy, 12, 5); }   // with Body Battery, energy is only yours
        food = dropTo(food, 5, 5);
        weight = weight - hits / 3 > 0 ? weight - hits / 3 : 0;
        joy = clamp100(joy + 2);
        if (hits >= 20) { heartUntil = ms() + HEART_MS; }
        addBond(2 + gain / 6);
        registerCare();
        save();
        return gain;
    }

    // Dodge run: 2 points = 1 SPEED, at most +18 a session.
    function trainSpeed(hits) {
        if (!canAct()) { return 0; }
        var gain = min(hits / 2, 18);
        var before = trSpe;
        trSpe = min(trSpe + gain, trMaxFor(ivSpe));
        gain = trSpe - before;
        if (bbNow < 0) { energy = dropTo(energy, 10, 5); }   // with Body Battery, energy is only yours
        food = dropTo(food, 4, 5);
        weight = weight - hits / 2 > 0 ? weight - hits / 2 : 0;
        joy = clamp100(joy + 2);
        addBond(2 + gain / 6);
        registerCare();
        save();
        return gain;
    }

    // Brace and block: 5 points = 3 DEFENSE (at most +18) and joy: 5, plus 2 a point (max +35).
    function playResult(score) {
        if (!canAct()) { return 0; }
        var gain = min(score * 3 / 5, 18);
        var before = trDef;
        trDef = min(trDef + gain, trMaxFor(ivDef));
        gain = trDef - before;
        joy = clamp100(joy + 2 + (score > 15 ? 3 : 0));
        if (bbNow < 0) { energy = dropTo(energy, 10 + score / 2, 5); }   // with Body Battery, energy is only yours
        food = dropTo(food, 5, 5);
        weight = weight - score * 2 > 0 ? weight - score * 2 : 0;
        if (score >= 5) { heartUntil = ms() + HEART_MS; }
        addBond(2 + gain / 6);
        registerCare();
        save();
        return gain;
    }

    // ---------- party ----------

    function memberName(m) { return m[1].length() > 0 ? m[1] : SpriteIndex.name(m[0]); }

    // Swap a party member and a box member, or move one between them.
    function toParty(boxIdx) {
        if (boxIdx < 0 || boxIdx >= box.size() || party.size() >= PARTY_MAX) { return; }
        party.add(box[boxIdx]);
        box = removeAt(box, boxIdx);
        save();
    }

    function toBox(partyIdx) {
        if (partyIdx < 0 || partyIdx >= party.size()) { return; }
        box.add(party[partyIdx]);
        party = removeAt(party, partyIdx);
        save();
    }

    // Letting one go for good: it does not fall into the box.
    function releaseMember(inParty, idx) {
        if (inParty) { party = removeAt(party, idx); } else { box = removeAt(box, idx); }
        save();
    }

    function removeAt(arr, idx) {
        var out = [];
        for (var i = 0; i < arr.size(); i++) { if (i != idx) { out.add(arr[i]); } }
        return out;
    }

    // ---------- settings ----------

    function alertsOn() {
        var v = Storage.getValue("alerts");
        return v == null ? true : v;
    }

    function setAlerts(on) {
        Storage.setValue("alerts", on);
        save();
    }

    // ---------- badges ----------

    function hasBadge(i, hard) { return (((hard ? badgesHard : badges) >> i) & 1) == 1; }

    function winBadge(i, hard) {
        if (hard) { badgesHard |= 1 << i; } else { badges |= 1 << i; }
        save();
    }

    // TamaPoke's gymUnlocked(): the first is open, each later one once the one before is beaten.
    function trainerUnlocked(i, hard) {
        return i == 0 || hasBadge(i - 1, hard);
    }

    // bits 0-7 are the gym badges; 8-12 record the Elite 4 and champion wins
    function badgeCount(hard) {
        var v = (hard ? badgesHard : badges) & 0xFF;
        var n = 0;
        while (v != 0) { n += v & 1; v = v >> 1; }
        return n;
    }

    // ---------- mood ----------

    // TamaPoke's statusMsg(), in its order.
    function mood() {
        if (evolving()) { return Tr.t("Evolving!"); }
        if (bathing()) { return Tr.t("Splish splash!"); }
        if (sleeping) { return ""; }                 // the Zs above its head say it
        if (eating()) { return Tr.t("Yum yum!"); }
        if (showHeart()) { return Tr.t("It likes it!"); }
        if (food < 25) { return Tr.t("It's hungry!"); }
        if (hygiene < 25) { return Tr.t("Needs a bath!"); }
        if (energy < 25) { return Tr.t("Worn out..."); }
        if (joy < 25) { return Tr.t("Wants to train!"); }
        if (restless) { return Tr.t("Let's go for a walk!"); }
        if (weight > 60) { return Tr.t("A bit chubby..."); }
        if (shiny && ageMinutes < 15) { return Tr.t("It's SHINY!!"); }
        return Tr.t("It's happy");
    }

    // ---------- persistence ----------

    const SAVE_SIZE = 56;
    const PARTY_MAX = 5;       // with the partner, a team of 6; the rest wait in the pet box
    const BOX_MAX = 120;

    // Everything erased; nothing is saved again before the app closes.
    var wiped = false;
    function restartGame() {
        wiped = true;
        Storage.clearValues();
        Incubator.queue = null;          // reloaded (empty) by the new game
        StepBank.expSteps = null;
    }

    function save() {
        if (wiped) { return; }
        Storage.setValue("tp", [
            food, joy, energy, hygiene, poops, weight, ivAtk, ivDef, ivSpe, ivHp,
            trAtk, trDef, trSpe, berryKnown, shiny, ageMinutes, dex, careMistakes,
            sleeping, sleepAuto, ceremony, lastEnd, dexReg, dexShiny, streak, bestStreak,
            lastCareDay, lastMilestone, bond, bondToday, medals, totalMedals, nick,
            eggTarget, eggShiny, eggTaps, mistakeCooldown, evoDeclinedLv, farDeclinedAge,
            starterPick, evoPen, retirePending, neglectTicks, drainPhase, goodTicks,
            lastSeen, stepClaim, stepDay, moves, lastLearnLevel, learnQueue, badges, badgesHard, party, box, waiting]);
        // the widget glance draws the pet from these runs (it can't load sprite sheets)
        var tk = isEgg() ? -1 : dex * 2 + (shiny ? 1 : 0);
        if (tk != thumbKey) {
            thumbKey = tk;
            var runs = null;
            if (tk >= 0) {
                var meta = WatchUi.loadResource(SpriteIndex.data(dex)) as Dictionary;
                runs = meta[shiny ? "gs" : "g"];
            }
            Storage.setValue("gthumb", runs);
        }
        Storage.setValue("bag", [bag[0], bag[1], bag[2], bag[3], amFruit, $.amCredit, $.giftDay]);
        Storage.setValue("fit", [actSeen, xpDay, xpToday, bonusLv, eggSteps, eggNeed, stepRead, stepReadDay,
                                 weekPaid, restless, exp, wildDay, wildWins]);
        // a small summary for the background check and the widget glance
        Storage.setValue("pet", {"name" => name(), "food" => food, "joy" => joy, "hygiene" => hygiene,
                                 "energy" => energy, "bb" => bbNow >= 0, "poops" => poops, "lv" => isEgg() ? 0 : level(),
                                 "alerts" => alertsOn(), "steps" => eggSteps, "need" => eggNeed,
                                 "starter" => starterPick, "restless" => restless,
                                 "egg" => isEgg(), "asleep" => sleeping, "last" => lastSeen,
                                 "sl" => userSleep, "wk" => userWake});
    }

    function loadFit() {
        var f = Storage.getValue("fit") as Array?;
        if (f != null && f.size() == 10) {
            // before EXP: the level it had (age + workout levels) becomes its EXP, so it keeps it
            var old = 1 + ageMinutes / 60 + f[3];
            f = f.addAll([Lvl.expFor(old > MAX_LEVEL ? MAX_LEVEL : old), 0, 0]);
        }
        if (f == null || f.size() != 13) {
            // first run with exercise: workouts from today on count, the streak becomes weeks
            var t = Time.today().value();
            actSeen = t;
            var info = ActivityMonitor.getInfo();
            stepRead = (info != null && info.steps != null) ? info.steps : 0;
            stepReadDay = -1;   // set on the first read below
            streak = 0;
            bestStreak = 0;
            lastMilestone = 0;
            return;
        }
        actSeen = f[0]; xpDay = f[1]; xpToday = f[2]; bonusLv = f[3]; eggSteps = f[4]; eggNeed = f[5];
        stepRead = f[6]; stepReadDay = f[7]; weekPaid = f[8]; restless = f[9];
        exp = f[10]; wildDay = f[11]; wildWins = f[12];
    }

    function load() {
        loadTrainer();
        loadBag();
        var a = Storage.getValue("tp") as Array?;
        if (a != null && a.size() == 48) {   // Phase 1 save: no moves yet
            a = a.addAll([[0, 0, 0, 0], 0, []]);
        }
        if (a != null && a.size() == 51) {   // before badges
            a = a.addAll([0, 0]);
        }
        if (a != null && a.size() == 53) {   // before the party
            a = a.addAll([[], []]);
        }
        if (a != null && a.size() == 55) {   // before the waiting newcomer
            a.add(null);
        }
        if (a == null || a.size() != SAVE_SIZE) {
            // a new game (or a save from before the TamaPoke rules): start with the starter pick
            lastSeen = Time.now().value();
            loadFit();
            newEgg();
            return;
        }
        food = a[0]; joy = a[1]; energy = a[2]; hygiene = a[3]; poops = a[4]; weight = a[5];
        ivAtk = a[6]; ivDef = a[7]; ivSpe = a[8]; ivHp = a[9];
        trAtk = a[10]; trDef = a[11]; trSpe = a[12]; berryKnown = a[13]; shiny = a[14];
        ageMinutes = a[15]; dex = a[16]; careMistakes = a[17]; sleeping = a[18]; sleepAuto = a[19] == SLEEP_PLAYER ? SLEEP_AUTO : a[19];
        ceremony = a[20]; lastEnd = a[21]; dexReg = a[22]; dexShiny = a[23]; streak = a[24];
        bestStreak = a[25]; lastCareDay = a[26]; lastMilestone = a[27]; bond = a[28]; bondToday = a[29];
        medals = a[30]; totalMedals = a[31]; nick = a[32]; eggTarget = a[33]; eggShiny = a[34];
        eggTaps = a[35]; mistakeCooldown = a[36]; evoDeclinedLv = a[37]; farDeclinedAge = a[38];
        starterPick = a[39]; evoPen = a[40]; retirePending = a[41]; neglectTicks = a[42];
        drainPhase = a[43]; goodTicks = a[44]; lastSeen = a[45]; stepClaim = a[46]; stepDay = a[47];
        moves = a[48]; lastLearnLevel = a[49]; learnQueue = a[50];
        badges = a[51]; badgesHard = a[52];
        party = a[53]; box = a[54]; waiting = a[55];
        while (party.size() > PARTY_MAX) {          // older saves carried 6 besides the partner
            box.add(party[party.size() - 1]);
            party = party.slice(0, party.size() - 1);
        }
        var hs = Storage.getValue("hp") as Array?;
        if (hs != null && hs.size() == 2) { hpv = hs; }
        var fresh = Storage.getValue("fit") == null;
        loadFit();
        if (fresh) { stepReadDay = today(); }
        if (!isEgg() && moveCount() == 0) { lastLearnLevel = 0; checkLearnGates(); }
        if (ceremony != CER_NONE) { newEgg(); }   // the app closed mid-goodbye: finish it
    }
}
