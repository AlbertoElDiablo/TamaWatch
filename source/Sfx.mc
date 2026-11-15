import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Lang;

// Feedback by vibration only (no tones), and only on the main screen and in the Pokedex:
// those views set screenOk while they are showing. Settings > Vibration turns it off.
module Sfx {

    const HATCH = 0;
    const EVOLVE = 1;
    const MEDAL = 2;
    const STEPS = 6;
    const TICK = 7;        // Pokedex: a page turns / a raised entry opens

    var screenOk = false;

    function enabled() {
        var v = Storage.getValue("vibe");
        return v == null ? true : v;
    }

    function vibe(cue) {
        if (!screenOk || !enabled() || !(Attention has :vibrate)) { return; }
        var ms = cue == TICK ? 30 : (cue == MEDAL || cue == STEPS ? 120 : 250);
        Attention.vibrate([new Attention.VibeProfile(cue == TICK ? 40 : 70, ms)]);
    }
}
