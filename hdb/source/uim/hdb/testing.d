/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Hilfen nur für Unittests.
module uim.hdb.testing;

version (unittest):

import vibe.core.core : exitEventLoop, runEventLoop, runTask;

/// Führt `test` in einem vibe-Task aus (TaskLocal, HTTP-Client und Server brauchen einen) und beendet danach die
/// Ereignisschleife. Ein Fehler, auch ein fehlgeschlagenes assert, kommt als Rückgabewert zurück, damit der Test
/// erst aufräumen und ihn dann werfen kann; sonst bliebe die Schleife hängen.
/// @trusted: Throwable abzufangen ist in @safe-Code verboten. Hier wird es nur weitergereicht, nie verschluckt.
Throwable runInEventLoop(void delegate() @safe test) @trusted {
    Throwable failure;
    runTask(() nothrow {
        try
            test();
        catch (Throwable t)
            failure = t;
        try
            exitEventLoop();
        catch (Exception) {
        }
    });
    runEventLoop();
    return failure;
}
