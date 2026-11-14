/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.cli.interfaces;

@safe:

/// Zeilenweise Eingabe der Shell (Terminal, Datei, Test).
interface ICliInput {
    /// Liest die nächste Zeile ohne Zeilenende; null am Ende der Eingabe.
    /// `prompt` zeigt nur eine interaktive Eingabe an.
    string readLine(string prompt);
    /// true, wenn ein Mensch tippt: dann gibt es Prompts und eine Begrüßung.
    bool interactive() const;
}

/// Ausgabe der Shell. Ergebnisse gehen nach `write`, Fehler und Hinweise nach `error`.
interface ICliOutput {
    void write(string text);
    void error(string text);
}
