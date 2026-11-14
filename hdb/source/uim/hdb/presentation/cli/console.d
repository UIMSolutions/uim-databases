/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.cli.console;

import uim.hdb.presentation.cli.interfaces;

import std.stdio : File;
import std.string : chomp;

@safe:

/// Eingabe aus einer Datei oder der Standardeingabe. Prompts erscheinen nur, wenn ein Terminal angeschlossen ist.
final class ConsoleInput : ICliInput {
    private File file;
    private bool tty;

    this(File file) {
        this.file = file;
        tty = isTerminal(file);
    }

    /// Die Standardeingabe.
    this() {
        this(standardInput);
    }

    string readLine(string prompt) {
        if (tty) {
            standardOutput.write(prompt);
            standardOutput.flush();
        }
        auto line = file.readln();
        if (line is null)
            return null;
        return line.chomp;
    }

    bool interactive() const {
        return tty;
    }
}

/// Ergebnisse auf stdout, Fehler und Hinweise auf stderr: so bleibt die Ausgabe von --csv und --json sauber.
final class ConsoleOutput : ICliOutput {
    void write(string text) {
        standardOutput.write(text);
        standardOutput.flush();
    }

    void error(string text) {
        standardOutput.flush();
        standardError.write(text);
    }
}

/// Fragt am Terminal nach einem Passwort, ohne Echo. null am Ende der Eingabe oder ohne Terminal: ist die
/// Standardeingabe umgeleitet, gehört sie dem Skript, dessen erste Zeile sonst als Passwort verloren ginge.
string readSecret(string prompt) @trusted {
    auto input = standardInput;
    immutable tty = isTerminal(input);
    if (!tty)
        return null;
    standardError.write(prompt);
    version (Posix) {
        import core.sys.posix.termios : ECHO, tcgetattr, tcsetattr, TCSANOW, termios;

        termios saved;
        immutable hide = tty && tcgetattr(input.fileno, &saved) == 0;
        if (hide) {
            auto silent = saved;
            silent.c_lflag &= ~ECHO;
            tcsetattr(input.fileno, TCSANOW, &silent);
        }
        scope (exit)
            if (hide) {
                tcsetattr(input.fileno, TCSANOW, &saved);
                standardError.write("\n");
            }
    }
    auto line = input.readln();
    return line is null ? null : line.chomp;
}

// @trusted: Phobos hält die Standardströme in __gshared-Variablen; dieses Programm liest und schreibt sie nur
// aus einem Thread.
private File standardInput() @trusted {
    import std.stdio : stdin;

    return stdin;
}

private File standardOutput() @trusted {
    import std.stdio : stdout;

    return stdout;
}

private File standardError() @trusted {
    import std.stdio : stderr;

    return stderr;
}

/// @trusted: isatty liest nur den Dateideskriptor.
private bool isTerminal(File file) @trusted {
    version (Posix) {
        import core.sys.posix.unistd : isatty;

        return file.isOpen && isatty(file.fileno) == 1;
    } else version (Windows) {
        import core.sys.windows.windows : GetConsoleMode;

        uint mode;
        return file.isOpen && GetConsoleMode(file.windowsHandle, &mode) != 0;
    } else
        return false;
}
