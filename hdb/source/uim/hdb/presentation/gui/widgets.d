/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Bausteine der Oberfläche. GtkD ist nicht @safe, deshalb bleiben die GTK-Module @system; alles, was sich prüfen
/// lässt, steht im @safe-Modul api.
module uim.hdb.presentation.gui.widgets;

import uim.hdb.presentation.gui.api : ApiError, Grid;
import gobject.c.types : GType;
import gtk.Box;
import gtk.Button;
import gtk.CellRendererText;
import gtk.CheckButton;
import gtk.ComboBoxText;
import gtk.Dialog;
import gtk.Entry;
import gtk.Grid : GtkGrid = Grid;
import gtk.Label;
import gtk.ListStore;
import gtk.MessageDialog;
import gtk.ScrolledWindow;
import gtk.TreeIter;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.Widget;
import gtk.Window;
import gtk.c.types : ButtonsType, DialogFlags, MessageType, Orientation, PolicyType, ResponseType, WindowPosition;

/// Tabelle mit beliebig vielen Textspalten, für Ergebnisse, deren Spalten erst zur Laufzeit feststehen.
final class DataGrid {
    ScrolledWindow widget;
    private TreeView view;
    private ListStore store;
    private string[] columns;

    this() {
        view = new TreeView();
        view.setEnableSearch(true);
        view.setGridLines(GtkTreeViewGridLines.HORIZONTAL);
        widget = new ScrolledWindow();
        widget.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        widget.add(view);
    }

    /// Ersetzt Spalten und Zeilen. Unterstriche in Spaltennamen würden sonst als Tastenkürzel gelesen.
    void show(Grid grid) {
        if (auto existing = view.getColumns()) // null bei keiner Spalte
            foreach (c; existing.toArray!TreeViewColumn)
                view.removeColumn(c);
        columns = grid.columns.dup;
        if (columns.length == 0) { // GTK kennt kein Modell ohne Spalten
            store = null;
            view.setModel(null);
            return;
        }
        auto types = new GType[columns.length];
        types[] = GType.STRING;
        store = new ListStore(types);
        foreach (i, name; columns) {
            auto renderer = new CellRendererText();
            auto column = new TreeViewColumn(name.replaceUnderscores, renderer, "text", cast(int) i);
            column.setResizable(true);
            column.setSortColumnId(cast(int) i);
            view.appendColumn(column);
        }
        foreach (row; grid.rows) {
            auto iter = store.createIter();
            foreach (i, text; row)
                store.setValue(iter, cast(int) i, text.length > 200 ? text[0 .. 200] ~ " …" : text);
        }
        view.setModel(store);
    }

    void clear() {
        show(Grid.init);
    }

    /// Werte der gewählten Zeile; leer, wenn keine gewählt ist.
    string[] selected() {
        auto iter = view.getSelectedIter();
        if (iter is null || store is null)
            return null;
        string[] result;
        foreach (i; 0 .. columns.length)
            result ~= store.getValueString(iter, cast(int) i);
        return result;
    }

    /// Wert einer Spalte der gewählten Zeile; leer ohne Auswahl.
    string selected(string column) {
        auto row = selected();
        foreach (i, c; columns)
            if (c == column && i < row.length)
                return row[i];
        return "";
    }

    TreeView treeView() {
        return view;
    }
}

private string replaceUnderscores(string s) {
    import std.array : replace;

    return s.replace("_", "__");
}

private import gtk.c.types : GtkTreeViewGridLines;
private import glib.ListG;

/// Kinder eines Containers. GtkD gibt für eine leere Liste null zurück statt einer leeren ListG.
Widget[] childrenOf(Container container) {
    auto list = container.getChildren();
    return list is null ? null : list.toArray!Widget;
}

private import gtk.Container;

/// Meldung mit einem OK-Knopf. Der Text geht als Argument an "%s": Prozentzeichen aus Serverfehlern bleiben Text.
void showMessage(Window parent, string text, bool error = true) {
    auto d = new MessageDialog(parent, DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
        error ? MessageType.ERROR : MessageType.INFO, ButtonsType.CLOSE, "%s", text);
    d.setPosition(WindowPosition.CENTER_ON_PARENT);
    d.run();
    d.destroy();
}

/// Ja/Nein-Frage; true bei Ja.
bool confirm(Window parent, string text) {
    auto d = new MessageDialog(parent, DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT, MessageType.QUESTION,
        ButtonsType.YES_NO, "%s", text);
    d.setPosition(WindowPosition.CENTER_ON_PARENT);
    scope (exit)
        d.destroy();
    return d.run() == ResponseType.YES;
}

/// Führt eine Aktion aus und zeigt Fehler an. Eine abgelaufene Sitzung (401) meldet `onSignedOut`.
bool guarded(Window parent, void delegate() action, void delegate() onSignedOut = null) {
    try {
        action();
        return true;
    } catch (ApiError e) {
        if (e.status == 401 && onSignedOut !is null) {
            onSignedOut();
            return false;
        }
        showMessage(parent, e.msg);
    } catch (Exception e)
        showMessage(parent, e.msg);
    return false;
}

/// Dialog mit beschrifteten Feldern. Die Felder werden in der Reihenfolge des Hinzufügens angelegt.
final class FormDialog {
    private Dialog dialog;
    private GtkGrid grid;
    private int rowCount;
    private Entry[string] entries;
    private ComboBoxText[string] combos;
    private CheckButton[string] checks;

    this(Window parent, string title, string okLabel) {
        dialog = new Dialog(title, parent, DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
            ["Cancel", okLabel], [ResponseType.CANCEL, ResponseType.OK]);
        dialog.setDefaultResponse(ResponseType.OK);
        dialog.setPosition(WindowPosition.CENTER_ON_PARENT);
        grid = new GtkGrid();
        grid.setRowSpacing(8);
        grid.setColumnSpacing(12);
        grid.setMarginTop(12);
        grid.setMarginBottom(12);
        grid.setMarginStart(12);
        grid.setMarginEnd(12);
        dialog.getContentArea().packStart(grid, true, true, 0);
    }

    FormDialog text(string key, string label, string value = "", bool secret = false) {
        auto e = new Entry();
        e.setText(value.length ? value : ""); // ein null-String würde als NULL an GTK gehen
        e.setVisibility(!secret);
        e.setActivatesDefault(true);
        e.setWidthChars(32);
        entries[key] = e;
        return add(label, e);
    }

    FormDialog choice(string key, string label, string[] options, string selected = "") {
        auto c = new ComboBoxText(false);
        foreach (i, o; options) {
            c.appendText(o);
            if (o == selected)
                c.setActive(cast(int) i);
        }
        if (c.getActive() < 0 && options.length)
            c.setActive(0);
        combos[key] = c;
        return add(label, c);
    }

    FormDialog flag(string key, string label, bool value) {
        auto c = new CheckButton(label);
        c.setActive(value);
        checks[key] = c;
        grid.attach(c, 1, rowCount++, 1, 1);
        return this;
    }

    FormDialog note(string text) {
        auto l = new Label(text);
        l.setLineWrap(true);
        l.setXalign(0);
        l.setMaxWidthChars(50);
        grid.attach(l, 0, rowCount++, 2, 1);
        return this;
    }

    private FormDialog add(string label, Widget field) {
        auto l = new Label(label);
        l.setXalign(1);
        grid.attach(l, 0, rowCount, 1, 1);
        field.setHexpand(true);
        grid.attach(field, 1, rowCount++, 1, 1);
        return this;
    }

    /// Zeigt den Dialog; true bei OK.
    bool run() {
        dialog.showAll();
        return dialog.run() == ResponseType.OK;
    }

    string opIndex(string key) {
        if (auto e = key in entries)
            return e.getText();
        if (auto c = key in combos)
            return c.getActiveText();
        return "";
    }

    bool checked(string key) {
        auto c = key in checks;
        return c !is null && c.getActive();
    }

    void close() {
        dialog.destroy();
    }
}

/// Senkrechte Box mit Abstand, als Grundlage einer Seite.
Box pageBox() {
    auto box = new Box(Orientation.VERTICAL, 8);
    box.setMarginTop(12);
    box.setMarginBottom(12);
    box.setMarginStart(12);
    box.setMarginEnd(12);
    return box;
}

/// Waagerechte Leiste für Knöpfe und Eingaben.
Box toolbar() {
    return new Box(Orientation.HORIZONTAL, 6);
}

Button button(string label, void delegate() action) {
    auto b = new Button(label);
    b.addOnClicked((Button _) { action(); });
    return b;
}

Label heading(string text) {
    auto l = new Label("");
    l.setMarkup("<b>" ~ escapeMarkup(text) ~ "</b>");
    l.setXalign(0);
    return l;
}

string escapeMarkup(string s) {
    import std.array : replace;

    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
}
