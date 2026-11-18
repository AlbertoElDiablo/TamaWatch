import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;

// String helpers (Connect IQ has no split).
module Wire {
    function split(s, sep) {
        var out = [];
        var rest = s;
        while (true) {
            var i = rest.find(sep);
            if (i == null) { out.add(rest); return out; }
            out.add(rest.substring(0, i));
            rest = rest.substring(i + sep.length(), rest.length());
        }
        return out;
    }

    function join(arr, sep) {
        var s = "";
        for (var i = 0; i < arr.size(); i++) { s += (i > 0 ? sep : "") + arr[i]; }
        return s;
    }

    // Keep only characters that are safe inside our messages.
    function clean(s) {
        var ok = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -.!'?";
        var out = "";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            if (ok.find(chars[i].toString()) != null) { out += chars[i].toString(); }
        }
        return out;
    }
}

// Link battles over the internet, in place of TamaPoke's ESP-NOW radio: both watches post to and
// read from one ntfy.sh topic (through their phones). A message is
//   TW1|<role H or G>|<seq>|<type>|<payload...>
// Each side ignores its own messages and anything with a sequence number it has already seen.
// Sends are queued and retried, polls run every 5 s (ntfy.sh's free rate limit).
class LinkClient {
    const POLL_MS = 5000;
    const HOST_URL = "https://ntfy.sh/";

    var topic;
    var role;               // "H" or "G"
    var target = null;      // object with onLink(type, parts)
    var seq = 0;
    var peerSeq = 0;
    var outbox = [];
    var sending = false;
    var polling = false;
    var timer = null;
    var errors = 0;
    var lastError = 0;

    function initialize(code, isHost, handlerTarget) {
        topic = "tamawatch-v1-" + code + "-k7q2";       // every region meets in the same rooms
        role = isHost ? "H" : "G";
        target = handlerTarget;
    }

    function start() {
        timer = Ticker.take(1);                   // (a reused timer: see Ticker)
        Ticker.t[1].start(method(:poll), POLL_MS, true);
        poll();
    }

    function stop() {
        if (timer != null) { Ticker.release(1, timer); timer = null; }
    }

    function online() { return errors < 3; }

    function send(type, payload) {
        seq++;
        outbox.add("TW1|" + role + "|" + seq + "|" + type + "|" + payload);
        flush();
    }

    function flush() {
        if (sending || outbox.size() == 0) { return; }
        sending = true;
        Communications.makeWebRequest(HOST_URL, {"topic" => topic, "message" => outbox[0]},
            {:method => Communications.HTTP_REQUEST_METHOD_POST,
             :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON},
             :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON},
            method(:onSent));
    }

    function onSent(code as Number, data as Dictionary or String or Null) as Void {
        sending = false;
        if (code == 200) {
            outbox = outbox.slice(1, null);
            errors = 0;
        } else {
            errors++;
            lastError = code;
        }
        flush();      // the next one, or a retry
    }

    function poll() as Void {
        if (polling) { return; }
        polling = true;
        Communications.makeWebRequest(HOST_URL + topic + "/raw", {"poll" => "1", "since" => "all"},
            {:method => Communications.HTTP_REQUEST_METHOD_GET,
             :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN},
            method(:onPoll));
        if (outbox.size() > 0) { flush(); }
    }

    function onPoll(code as Number, data as Dictionary or String or Null) as Void {
        polling = false;
        if (code != 200 || !(data instanceof String)) {
            errors++;
            lastError = code;
            if (target != null) { target.onLink("NET", null); }
            return;
        }
        errors = 0;
        var lines = Wire.split(data as String, "\n");
        for (var i = 0; i < lines.size(); i++) {
            var line = lines[i];
            if (line.length() < 8 || !line.substring(0, 4).equals("TW1|")) { continue; }
            var parts = Wire.split(line, "|");
            if (parts.size() < 4 || parts[1].equals(role)) { continue; }
            var n = parts[2].toNumber();
            if (n == null || n <= peerSeq) { continue; }
            peerSeq = n;
            if (target != null) { target.onLink(parts[3], parts); }
        }
    }
}
