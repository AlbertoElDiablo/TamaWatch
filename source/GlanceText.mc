import Toybox.Application.Storage;
import Toybox.Lang;

// The few texts the widget glance and the background reminders show, in every language. They run
// with too little memory to load the app's translations, so these are built in. Rows follow
// Tr.CODES: ca, en, es, fr, it, pt, de.
(:glance, :background)
module GT {
    const OPEN = 0;
    const STARTER = 1;
    const WALK = 2;         // {0} = steps
    const READY = 3;
    const SLEEPING = 4;
    const HUNGRY = 5;
    const POOP = 6;
    const BATH = 7;
    const MOVE = 8;
    const TRAIN = 9;
    const SLEEP = 10;
    const ALL_GOOD = 11;
    const PLAY = 12;
    const EGG = 13;
    const N_HUNGRY = 14;    // after the pet's name
    const N_BATH = 15;
    const N_TRAIN = 16;
    const N_EGG = 17;
    const N_HATCH = 18;
    const BTN_OPEN = 19;    // the notification's button
    const N_MOVE = 20;      // after the pet's name: the work-hours nudge to walk

    // One language's texts, made only when asked for: all seven at once don't fit in the glance's
    // 32 KB. Rows follow Tr.CODES (ca, en, es, fr, it, pt, de).
    function row(l) {
        if (l == 0) {
            return ["Obre per començar", "Tria el teu inicial", "Camina {0} passos per eclosionar", "A punt d'eclosionar!", "Dormint",
             "Té gana", "Neteja la caca", "Necessita un bany", "Vol moure's", "Vol entrenar", "Necessita dormir",
             "Tot bé!", "START per jugar", "OU", " té gana!", " necessita un bany!", " vol entrenar amb tu!", "Has trobat un ou! Obre TamaWatch", "El teu ou està eclosionant! Obre TamaWatch", "Obre", " vol moure's! Un passeig de 3-4 min? (~400 passos)"];
        }
        if (l == 1) {
            return ["Open to start", "Choose your starter", "Walk {0} steps to hatch", "Ready to hatch!", "Sleeping",
             "Hungry", "Clean up poop", "Needs a bath", "Wants to move", "Wants to train", "Needs sleep",
             "All good!", "START to play", "EGG", " is hungry!", " needs a bath!", " wants to train with you!", "You found an egg! Open TamaWatch", "Your egg is hatching! Open TamaWatch", "Open", " wants to move! A 3-4 min walk? (~400 steps)"];
        }
        if (l == 2) {
            return ["Abre para empezar", "Elige tu inicial", "Camina {0} pasos para eclosionar", "¡Listo para eclosionar!", "Durmiendo",
             "Tiene hambre", "Limpia la caca", "Necesita un baño", "Quiere moverse", "Quiere entrenar", "Necesita dormir",
             "¡Todo bien!", "START para jugar", "HUEVO", " tiene hambre!", " necesita un baño!", " quiere entrenar contigo!", "¡Has encontrado un huevo! Abre TamaWatch", "¡Tu huevo está eclosionando! Abre TamaWatch", "Abrir", " quiere moverse! ¿Un paseo de 3-4 min? (~400 pasos)"];
        }
        if (l == 3) {
            return ["Ouvre pour commencer", "Choisis ton starter", "Marche {0} pas pour l'éclosion", "Prêt à éclore !", "Il dort",
             "A faim", "Nettoie les crottes", "Besoin d'un bain", "Veut bouger", "Veut s'entraîner", "Besoin de dormir",
             "Tout va bien !", "START pour jouer", "ŒUF", " a faim !", " a besoin d'un bain !", " veut s'entraîner avec toi !", "Tu as trouvé un œuf ! Ouvre TamaWatch", "Ton œuf éclot ! Ouvre TamaWatch", "Ouvrir", " veut bouger ! Une marche de 3-4 min ? (~400 pas)"];
        }
        if (l == 4) {
            return ["Apri per iniziare", "Scegli il tuo iniziale", "Cammina {0} passi per la schiusa", "Pronto a schiudersi!", "Dorme",
             "Ha fame", "Pulisci la cacca", "Ha bisogno di un bagno", "Vuole muoversi", "Vuole allenarsi", "Ha bisogno di dormire",
             "Tutto bene!", "START per giocare", "UOVO", " ha fame!", " ha bisogno di un bagno!", " vuole allenarsi con te!", "Hai trovato un uovo! Apri TamaWatch", "Il tuo uovo si sta schiudendo! Apri TamaWatch", "Apri", " vuole muoversi! Una camminata di 3-4 min? (~400 passi)"];
        }
        if (l == 5) {
            return ["Abre para começar", "Escolhe o teu inicial", "Caminha {0} passos para chocar", "Pronto para chocar!", "A dormir",
             "Tem fome", "Limpa o cocó", "Precisa de banho", "Quer mexer-se", "Quer treinar", "Precisa de dormir",
             "Tudo bem!", "START para jogar", "OVO", " tem fome!", " precisa de banho!", " quer treinar contigo!", "Encontraste um ovo! Abre o TamaWatch", "O teu ovo está a chocar! Abre o TamaWatch", "Abrir", " quer mexer-se! Uma caminhada de 3-4 min? (~400 passos)"];
        }
        if (l == 6) {
            return ["Öffnen zum Starten", "Wähle dein Starter", "Lauf {0} Schritte bis zum Schlüpfen", "Bereit zum Schlüpfen!", "Schläft",
             "Hat Hunger", "Mach den Kot weg", "Braucht ein Bad", "Will sich bewegen", "Will trainieren", "Braucht Schlaf",
             "Alles gut!", "START zum Spielen", "EI", " hat Hunger!", " braucht ein Bad!", " will mit dir trainieren!", "Du hast ein Ei gefunden! Öffne TamaWatch", "Dein Ei schlüpft! Öffne TamaWatch", "Öffnen", " will sich bewegen! 3-4 Min. gehen? (~400 Schritte)"];
        }
        return row(1);
    }

    var cur = null;
    var curLang = -1;


    function g(k) {
        var l = Storage.getValue("lang");
        if (l == null) { l = 1; }
        if (cur == null || l != curLang) { cur = row(l); curLang = l; }
        return cur[k];
    }

    function walk(n) {
        var s = g(WALK);
        var i = s.find("{0}");
        return i == null ? s : s.substring(0, i) + n + s.substring(i + 3, s.length());
    }
}
