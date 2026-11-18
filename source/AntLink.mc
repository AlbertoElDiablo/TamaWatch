import Toybox.Ant;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Timer;

// Link battles NEARBY, watch to watch over ANT (the radio Garmin uses for sensors): no phone and
// no internet. Same interface as LinkClient (start, stop, online, send; the target's onLink), so
// the lobby and the battle don't care which one carries the messages.
//
// The host opens an ANT master channel, the friend a slave channel searching for it. Both find
// each other by the room code, which becomes the channel's device number, so two pairs of
// players next to each other don't cross. Each message ("TW1|role|seq|type|payload", as online)
// goes as one ANT burst: its UTF-8 bytes in 8-byte packets, zero-padded. A burst is acknowledged
// by the radio, so a failed one is simply sent again a moment later.
class AntLink {
    const DEVICE_TYPE = 0x7A;          // TamaWatch's own (not an ANT+ profile)
    const TRANS_TYPE = 1;
    const FREQ = 66;                   // 2466 MHz, clear of ANT+ (57)
    const PERIOD = 8192;               // 4 Hz beacon
    const RETRY_MS = 700;

    var role;                          // "H" or "G"
    var target = null;
    var devNum = 1;
    var channel = null;
    var listener = null;
    var failed = false;                // no ANT channel could be opened on this watch
    var seq = 0;
    var peerSeq = 0;
    var outbox = [];
    var sending = false;
    var timer = null;
    var heard = false;                 // a message from the friend has arrived

    function initialize(code, isHost, handlerTarget) {
        role = isHost ? "H" : "G";
        target = handlerTarget;
        // the room code (4 letters) becomes a device number 1..65535
        var h = 7;
        var b = code.toUtf8Array();
        for (var i = 0; i < b.size(); i++) { h = (h * 31 + b[i]) & 0xFFFF; }
        devNum = h == 0 ? 1 : h;
    }

    function start() {
        try {
            listener = new AntBurstListener(self);
            var assign = new Ant.ChannelAssignment(role.equals("H") ? Ant.CHANNEL_TYPE_TX_NOT_RX : Ant.CHANNEL_TYPE_RX_NOT_TX,
                                                   Ant.NETWORK_PUBLIC);
            channel = new Ant.GenericChannel(method(:onMessage), assign);
            channel.setDeviceConfig(new Ant.DeviceConfig({
                :deviceNumber => devNum,
                :deviceType => DEVICE_TYPE,
                :transmissionType => TRANS_TYPE,
                :messagePeriod => PERIOD,
                :radioFrequency => FREQ,
                :searchTimeoutLowPriority => 12,      // 30 s, then the channel is reopened
                :searchThreshold => 0}));
            channel.setBurstListener(listener);
            failed = !channel.open();
            if (!failed && role.equals("H")) { beacon(); }
        } catch (e) {
            failed = true;
        }
        timer = Ticker.take(2);                   // (a reused timer: see Ticker)
        Ticker.t[2].start(method(:onTimer), RETRY_MS, true);
    }

    function stop() {
        if (timer != null) { Ticker.release(2, timer); timer = null; }
        if (channel != null) {
            try { channel.close(); channel.release(); } catch (e) { }
            channel = null;
        }
    }

    function online() { return !failed; }

    function send(type, payload) {
        seq++;
        outbox.add("TW1|" + role + "|" + seq + "|" + type + "|" + payload);
        flush();
    }

    // The host's beacon, so the friend's watch can find and lock on to it.
    function beacon() {
        var m = new Ant.Message();
        m.setPayload([0x54, 0x57, 1, devNum & 0xFF, (devNum >> 8) & 0xFF, 0, 0, 0]);
        channel.sendBroadcast(m);
    }

    function flush() {
        if (sending || outbox.size() == 0 || channel == null || failed) { return; }
        var bytes = (outbox[0] as String).toUtf8Array();
        var burst = new Ant.BurstPayload();
        var n = (bytes.size() + 7) / 8;
        if (n < 2) { n = 2; }
        for (var p = 0; p < n; p++) {
            var pkt = [0, 0, 0, 0, 0, 0, 0, 0];
            for (var j = 0; j < 8; j++) {
                var k = p * 8 + j;
                if (k < bytes.size()) { pkt[j] = bytes[k]; }
            }
            burst.add(pkt);
        }
        sending = true;
        try {
            channel.sendBurst(burst);
        } catch (e) {
            sending = false;           // tried again on the next timer tick
        }
    }

    function onSent(ok) {
        sending = false;
        if (ok && outbox.size() > 0) { outbox = outbox.slice(1, null); flush(); }
        // a failure is retried by the timer: the friend may not be in range yet
    }

    function onTimer() as Void { if (!sending) { flush(); } }

    function onReceived(payload) {
        var it = new Ant.BurstPayloadIterator(payload);
        var bytes = [];
        var pkt = it.next();
        while (pkt != null) {
            for (var j = 0; j < pkt.size(); j++) { if (pkt[j] != 0) { bytes.add(pkt[j]); } }
            pkt = it.next();
        }
        var line = null;
        try { line = StringUtil.utf8ArrayToString(bytes); } catch (e) { return; }
        if (line == null || line.length() < 8 || !line.substring(0, 4).equals("TW1|")) { return; }
        var parts = Wire.split(line, "|");
        if (parts.size() < 4 || parts[1].equals(role)) { return; }
        var n = parts[2].toNumber();
        if (n == null || n <= peerSeq) { return; }
        peerSeq = n;
        heard = true;
        if (target != null) { target.onLink(parts[3], parts); }
    }

    // Channel events: keep the host's beacon going, reopen a search that timed out.
    function onMessage(msg as Ant.Message) as Void {
        var p = msg.getPayload();
        if (msg.messageId == Ant.MSG_ID_CHANNEL_RESPONSE_EVENT && p[0] == Ant.MSG_ID_RF_EVENT) {
            var ev = p[1];
            if (ev == Ant.MSG_CODE_EVENT_TX && channel != null) {
                beacon();
            } else if (ev == Ant.MSG_CODE_EVENT_CHANNEL_CLOSED && channel != null) {
                try { channel.open(); } catch (e) { failed = true; }
            }
        }
    }
}

class AntBurstListener extends Ant.BurstListener {
    var link;

    function initialize(l) {
        BurstListener.initialize();
        link = l;
    }

    function onTransmitComplete() as Void { link.onSent(true); }
    function onTransmitFail(errorCode as Ant.BurstError) as Void { link.onSent(false); }
    function onReceiveFail(errorCode as Ant.BurstError) as Void { }
    function onReceiveComplete(burstPayload as Ant.BurstPayload) as Void { link.onReceived(burstPayload); }
}
