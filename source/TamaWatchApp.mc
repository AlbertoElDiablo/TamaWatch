import Toybox.Application;
import Toybox.Background;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// The app class is loaded by the background service and the widget glance too, so it carries
// both annotations. TamaWatch is a widget: its glance shows the pet's needs, selecting it opens
// the game.
(:background, :glance)
class TamaWatchApp extends Application.AppBase {

    var model = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
        if (model != null) {
            model.update();
            model.save();
        }
    }

    function getInitialView() {
        model = new PetModel();
        // Wake in the background to check if the pet needs care (and for bonus eggs).
        if (Background has :registerForTemporalEvent) {
            // every 15 minutes (was 5): the reminders and egg news still arrive in good time, and
            // the watch wakes the app a third as often
            Background.registerForTemporalEvent(new Time.Duration(15 * 60));
        }
        // glances on: the game opens straight from the glance. Off: the widget loop shows a card
        // first (UP/DOWN belong to the loop there) and START opens the game.
        var ds = System.getDeviceSettings();
        if ((ds has :isGlanceModeEnabled) && ds.isGlanceModeEnabled) {
            var view = new PetView(model);
            return [view, new PetDelegate(model, view)];
        }
        return [new WidgetCard(), new WidgetCardDelegate(model)];
    }

    (:glance)
    function getGlanceView() {
        return [new TamaGlance()];
    }

    function getServiceDelegate() {
        return [new PetService()];
    }
}
