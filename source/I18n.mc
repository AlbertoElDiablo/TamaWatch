import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The app's languages. Every text is written in English in the code and looked up here: Tr.t(s)
// gives it in the chosen language (the English itself when there is no translation), Tr.f(s, args)
// does the same for a sentence with {0}, {1}... in it. Pokemon names are never translated.
// The translations live in resources/jsondata/lang_xx.json (made by tools/make_lang.py); only the
// chosen one is loaded.
module Tr {
    // German came later, so it is last here (the index is what's saved); lists show ORDER,
    // alphabetical by their own names
    const CODES = ["ca", "en", "es", "fr", "it", "pt", "de"];
    const NAMES = ["Català", "English", "Español", "Français", "Italiano", "Português", "Deutsch"];
    const ORDER = [0, 6, 1, 2, 3, 4, 5];
    const EN = 1;

    // Where language i is in ORDER.
    function pos(i) {
        for (var k = 0; k < ORDER.size(); k++) { if (ORDER[k] == i) { return k; } }
        return 0;
    }

    var cur = -1;
    var dict = null;

    // The chosen language (an index into CODES); English until one is chosen.
    function lang() {
        if (cur < 0) {
            var l = Storage.getValue("lang");
            cur = l == null ? EN : l;
            dict = null;
            var ids = [Rez.JsonData.lang_ca, null, Rez.JsonData.lang_es, Rez.JsonData.lang_fr, Rez.JsonData.lang_it, Rez.JsonData.lang_pt, Rez.JsonData.lang_de];
            if (ids[cur] != null) { dict = WatchUi.loadResource(ids[cur]); }
        }
        return cur;
    }

    function chosen() { return Storage.getValue("lang") != null; }

    // No language chosen any more: English (and the device's) until one is picked.
    function clear() {
        Storage.deleteValue("lang");
        cur = -1;
        lang();
    }

    function set(i) {
        Storage.setValue("lang", i);
        cur = -1;
        lang();
    }

    // The watch's own language, if it is one of ours (the watch has no Catalan), else English.
    function deviceDefault() {
        var l = System.getDeviceSettings().systemLanguage;
        if (l == System.LANGUAGE_SPA) { return 2; }
        if (l == System.LANGUAGE_FRE) { return 3; }
        if (l == System.LANGUAGE_ITA) { return 4; }
        if (l == System.LANGUAGE_POR) { return 5; }
        if (l == System.LANGUAGE_DEU) { return 6; }
        return EN;
    }

    function t(s) {
        lang();
        if (dict == null || s == null) { return s; }
        var v = dict[s];
        return v != null ? v : s;
    }

    // t(s) with {0}, {1}, ... replaced by args (in the translation's own word order)
    function f(s, args) {
        var out = t(s);
        for (var i = 0; i < args.size(); i++) {
            var key = "{" + i + "}";
            var at = out.find(key);
            while (at != null) {
                out = out.substring(0, at) + args[i] + out.substring(at + key.length(), out.length());
                at = out.find(key);
            }
        }
        return out;
    }
}
