import Toybox.Lang;
import Toybox.Timer;

// The app's timers, made once and reused. On the fenix 6 a stopped Timer is never given back
// (Garmin bug CIQQA-986: Timer.stop doesn't free the timer), so a screen that made a new one each
// time it appeared ran out after a few visits ("Too Many Timers": the crash on a quick second
// Route Crossing run). Slot 0 is the screen on top (home, games, battles, the collection, the
// link screen), 1 the phone link, 2 the ANT link. A screen takes its slot when it appears (the
// token it gets back says it's still the owner) and lets it go when it hides, unless another
// screen has taken it in between.
module Ticker {
    var t = [null, null, null];
    var who = [0, 0, 0];
    var next = 0;

    function take(slot) {
        if (t[slot] == null) { t[slot] = new Timer.Timer(); } else { t[slot].stop(); }
        next++;
        who[slot] = next;
        return next;
    }

    function release(slot, tok) {
        if (t[slot] != null && who[slot] == tok) { t[slot].stop(); who[slot] = 0; }
    }
}
