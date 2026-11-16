import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Notifications;
import Toybox.System;
import Toybox.Time;

// Runs every 5 minutes in the background. It only reads the saved summary, projects
// the awake drain forward (FOOD ~0.5/min, HYG ~0.25/min, JOY ~1 per 101 min) and asks the
// watch to prompt you when a need runs low; never while you are recording an activity.
(:background)
class PetService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // An alert. Watches with Connect IQ 5.1+ (the monkey-new.jungle build) show it as a notification
    // whose button is ours, in the chosen language; the others ask with the system's wake prompt,
    // whose Launch / Dismiss buttons the watch draws in its own language (an app can't change them).
    (:notif)
    function notify(msg) {
        Notifications.showNotification("TamaWatch", msg, {
            :actions => [{:label => GT.g(GT.BTN_OPEN), :data => 1}],
            :dismissPrevious => true});
    }

    (:nonotif)
    function notify(msg) { Background.requestApplicationWake(msg); }

    // An activity being recorded on the watch (running, paused, or stopped and not yet saved):
    // no alerts until it is over; the next check after it asks again.
    function recording() {
        if (!(Toybox has :Activity) || !(Activity has :getActivityInfo)) { return false; }
        var i = Activity.getActivityInfo();
        if (i == null || !(i has :timerState) || i.timerState == null) { return false; }
        return i.timerState != Activity.TIMER_STATE_OFF;
    }

    function onTemporalEvent() {
        if (recording()) { Background.exit(null); return; }
        var d = Storage.getValue("pet") as Dictionary?;
        if (eggReady(d) || eggHatching(d)) { Background.exit(null); return; }
        if (d != null && !d["egg"] && !d["asleep"] && d["alerts"] != false) {
            var mins = (Time.now().value() - d["last"]) / 60;
            var food = d["food"] - mins / 2;
            var joy = d["joy"] - mins / 101;
            var hygiene = d["hygiene"] - mins / 4;
            if (food < 20) {
                notify(d["name"] + GT.g(GT.N_HUNGRY));
            } else if (hygiene < 20) {
                notify(d["name"] + GT.g(GT.N_BATH));
            } else if (joy < 20) {
                notify(d["name"] + GT.g(GT.N_TRAIN));
            }
        }
        Background.exit(null);
    }

    // The first waiting egg (one you have seen in the app) has had all its steps walked: it hatches
    // when the game next opens; tell the wearer once, if care alerts are on.
    function eggHatching(d) {
        if (d == null || d["alerts"] == false || !(Toybox has :ActivityMonitor)) { return false; }
        var e = Storage.getValue("eggs") as Array?;
        var f = Storage.getValue("fit") as Array?;
        if (e == null || e.size() < 1 || e[0].size() == 0 || f == null || f.size() < 8) { return false; }
        var egg = e[0][0];
        var info = ActivityMonitor.getInfo();
        if (info == null || info.steps == null) { return false; }
        var now = Time.now().value();
        var today = (now + System.getClockTime().timeZoneOffset) / 86400;
        var walked = today == f[7] ? info.steps - f[6] : info.steps;
        if (egg[2] - walked > 0) { return false; }
        var id = egg.size() > 3 ? egg[3] : -1;
        if (Storage.getValue("hatchnote") == id) { return false; }
        Storage.setValue("hatchnote", id);
        notify(GT.g(GT.N_HATCH));
        return true;
    }

    // A bonus egg's steps walked (15,000 since the last, while under 2 eggs in 7 days): tell the
    // wearer once, if care alerts are on. The game adds the egg when it next opens.
    function eggReady(d) {
        if (d == null || d["alerts"] == false || !(Toybox has :ActivityMonitor)) { return false; }
        var e = Storage.getValue("eggs") as Array?;
        var f = Storage.getValue("fit") as Array?;
        if (f == null || f.size() < 8) { return false; }
        var bank = e != null && e.size() > 1 ? e[1] : 0;
        var times = e != null && e.size() > 2 ? e[2] : [];
        var total = e != null && e.size() > 3 ? e[3] : 0;
        var now = Time.now().value();
        var recent = 0;
        for (var i = 0; i < times.size(); i++) { if (now - times[i] < 604800) { recent++; } }
        if (recent >= 2) { return false; }
        var info = ActivityMonitor.getInfo();
        if (info == null || info.steps == null) { return false; }
        var today = (now + System.getClockTime().timeZoneOffset) / 86400;
        var walked = today == f[7] ? info.steps - f[6] : info.steps;     // since the game last read them
        if (walked < 0) { walked = 0; }
        if (bank + walked < 15000) { return false; }
        if (Storage.getValue("eggnote") == total + 1) { return false; }   // this egg was announced
        Storage.setValue("eggnote", total + 1);
        notify(GT.g(GT.N_EGG));
        return true;
    }
}
