module uim.hdb.adapters.outbound.file_statement_log;

import uim.hdb;

@safe:

/// Outgoing adapter: line-by-line instruction log in a file.
final class FileStatementLog : IStatementLog {
    private string path;

    this(string path) {
        this.path = path;
        auto dir = dirName(path);
        if (dir.length && !exists(dir))
            mkdirRecurse(dir);
    }

    void append(string statement) {
        auto f = File(path, "a");
        scope (exit)
            f.close();
        f.writeln(escape(statement));
        f.flush();
    }

    void appendAll(string[] statements) {
        auto f = File(path, "a");
        scope (exit)
            f.close();
        foreach (s; statements)
            f.writeln(escape(s));
        f.flush();
    }

    string[] readAll() {
        string[] result;
        if (!exists(path))
            return result;
        // Zeilenende ist nur '\n': escape maskiert \r und \n in Anweisungen, ein Zeilenumbruch trennt also immer
        foreach (line; readText(path).splitter('\n'))
            if (line.length)
                result ~= unescape(line);
        return result;
    }

    void replaceAll(string[] statements) {
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

private string escape(string s) {
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r");
}

private string unescape(string s) {
    string r;
    for (size_t i = 0; i < s.length; ++i) {
        if (s[i] == '\\' && i + 1 < s.length) {
            ++i;
            if (s[i] == 'n')
                r ~= '\n';
            else if (s[i] == 'r')
                r ~= '\r';
            else
                r ~= s[i];
        } else
            r ~= s[i];
    }
    return r;
}
