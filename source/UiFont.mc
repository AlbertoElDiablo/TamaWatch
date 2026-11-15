import Toybox.Graphics;
import Toybox.Lang;

// The menu fonts, in one place. The watch's own fonts are used: they are drawn for this display
// and stay crisp in its 64 colours (a bitmap copy of TamaPoke's Fredoka came out thin and grainy).
module UiFont {
    function tiny() { return Graphics.FONT_XTINY; }    // hints, small labels
    function small() { return Graphics.FONT_TINY; }    // values, card text
    function mid() { return Graphics.FONT_SMALL; }     // row labels
    function big() { return Graphics.FONT_SMALL; }     // titles (taller fonts crowd the round top)
}

// Grey for text (hints, subtitles, BACK): the light grey of tracks and borders (AAAAAA) all but
// disappears on the watch's screen in daylight.
const TEXT_GREY = 0x555555;
