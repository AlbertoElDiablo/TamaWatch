import Toybox.Application.Storage;
import Toybox.Lang;

// Every step counts toward EXP and food, and what's left over carries on: if an apple takes
// 3,000 steps and you walk 2,000 now and 1,000 tomorrow, the apple comes with that last 1,000.
// Nothing resets at midnight or on a new week. Kept apart from PetModel (which is at Connect
// IQ's member limit), saved under "stepbank".
module StepBank {
    const STEPS_PER_EXP = 50;          // 10,000 steps = 200 EXP (an intensity minute is 10)
    const STEPS_PER_APPLE = 3000;

    var expSteps = null;               // steps toward the next EXP point
    var fruitSteps = 0;                // steps toward the next apple

    function load() {
        if (expSteps != null) { return; }
        var s = Storage.getValue("stepbank") as Array?;
        if (s == null || s.size() < 2) { expSteps = 0; fruitSteps = 0; return; }
        expSteps = s[0];
        fruitSteps = s[1];
    }

    function save() { Storage.setValue("stepbank", [expSteps, fruitSteps]); }

    // New steps (from PetModel.claimSteps). While the pet is still an egg the EXP waits in the
    // bank and is paid once it hatches.
    function onSteps(m, delta) {
        load();
        if (delta > 0) {
            expSteps += delta;
            fruitSteps += delta;
        }
        var changed = delta > 0;
        if (fruitSteps >= STEPS_PER_APPLE) {
            m.giveFruit(0, fruitSteps / STEPS_PER_APPLE);
            fruitSteps = fruitSteps % STEPS_PER_APPLE;
        }
        if (!m.isEgg() && expSteps >= STEPS_PER_EXP) {
            m.gainExp(expSteps / STEPS_PER_EXP);
            expSteps = expSteps % STEPS_PER_EXP;
        }
        if (changed) { save(); }
    }

    // How far along the next apple is, for the screens: [steps so far, steps needed].
    function appleProgress() { load(); return [fruitSteps, STEPS_PER_APPLE]; }
}
