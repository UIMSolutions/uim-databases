module uim.hdb.adapters.outbound.file_statement_log;

import uim.hdb.application.ports;
import std.file : exists, mkdirRecurse, rename;
import std.path : dirName;
import std.stdio : File;
import std.string : replace;

/// Ausgehender Adapter: zeilenweises Anweisungsprotokoll in einer Datei.
final class FileStatementLog : IStatementLog
{
    private string path;

    this(string path)
    {
        this.path = path;
        auto dir = dirName(path);
        if (dir.length && !exists(dir))
            mkdirRecurse(dir);
    }

    void append(string statement)
    {
        auto f = File(path, "a");
        scope (exit) f.close();
        f.writeln(escape(statement));
        f.flush();
    }

    void appendAll(string[] statements)
    {
        auto f = File(path, "a");
        scope (exit) f.close();
        foreach (s; statements)
            f.writeln(escape(s));
        f.flush();
    }

    string[] readAll()
    {
        string[] result;
        if (!exists(path))
            return result;
        foreach (line; File(path, "r").byLine)
            if (line.length)
                result ~= unescape(line.idup);
        return result;
    }

    void replaceAll(string[] statements)
    {
        auto tmp = path ~ ".tmp";
        {
            auto f = File(tmp, "w");
            foreach (s; statements)
                f.writeln(escape(s));
            f.flush();
        }
        rename(tmp, path); // atomar auf POSIX
    }
}

private string escape(string s)
{
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r");
}

private string unescape(string s)
{
    string r;
    for (size_t i = 0; i < s.length; ++i)
    {
        if (s[i] == '\\' && i + 1 < s.length)
        {
            ++i;
            if (s[i] == 'n')
                r ~= '\n';
            else if (s[i] == 'r')
                r ~= '\r';
            else
                r ~= s[i];
        }
        else
            r ~= s[i];
    }
    return r;
}
