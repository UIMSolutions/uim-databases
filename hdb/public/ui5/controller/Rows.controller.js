sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/m/ColumnListItem",
	"sap/m/Column",
	"sap/m/Text",
	"sap/m/Label",
	"sap/m/Input",
	"sap/m/Dialog",
	"sap/m/Button",
	"sap/m/MessageToast",
	"sap/m/ViewSettingsDialog",
	"sap/m/ViewSettingsItem",
	"sap/ui/core/Messaging",
	"sap/ui/layout/form/SimpleForm",
	"sap/ui/model/Filter",
	"sap/ui/model/FilterOperator",
	"sap/ui/model/Sorter",
	"sap/ui/model/odata/type/Int64",
	"hdb/client/controller/values"
], function (Controller, ColumnListItem, Column, Text, Label, Input, Dialog, Button, MessageToast, ViewSettingsDialog,
	ViewSettingsItem, Messaging, SimpleForm, Filter, FilterOperator, Sorter, Int64, values) {
	"use strict";

	return Controller.extend("hdb.client.controller.Rows", {
		onInit: function () {
			const component = this.getOwnerComponent();
			const select = function (event) {
				this._show(event.getParameter("arguments").set);
			}.bind(this);
			component.getRouter().getRoute("table").attachPatternMatched(select);
			component.getRouter().getRoute("row").attachPatternMatched(select);
			component.getRouter().getRoute("home").attachPatternMatched(this._reset, this);
			const bus = sap.ui.getCore().getEventBus();
			bus.subscribe("hdb", "rowsChanged", this._refresh, this);
			bus.subscribe("hdb", "sessionEnded", this._reset, this);
		},

		onExit: function () {
			const bus = sap.ui.getCore().getEventBus();
			bus.unsubscribe("hdb", "rowsChanged", this._refresh, this);
			bus.unsubscribe("hdb", "sessionEnded", this._reset, this);
		},

		/** Das nächste Öffnen bindet neu, auch dieselbe Tabelle: nach einer Abmeldung gibt es ein neues Modell. */
		_reset: function () {
			this._set = null;
			this.byId("table").unbindItems();
		},

		_text: function (key, args) {
			return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(key, args);
		},

		_show: function (set) {
			if (set === this._set) {
				return;
			}
			const component = this.getOwnerComponent();
			this._set = set;
			this.byId("search").setValue("");
			this.byId("error").setVisible(false);
			component.describeEntitySet(set).then(function (info) {
				this._info = info;
				this.byId("hint").setVisible(!info.addressable);
				this._sorter = null;
				this._bind();
			}.bind(this)).catch(this._fail.bind(this));
		},

		_bind: function () {
			const table = this.byId("table");
			const info = this._info;
			table.unbindItems();
			table.removeAllColumns();
			info.columns.forEach(function (column) {
				table.addColumn(new Column({
					header: new Label({ text: column.name, design: column.key ? "Bold" : "Standard" }),
					hAlign: values.isNumber(column) ? "End" : "Begin"
				}));
			});
			table.bindItems({
				path: "/" + this._set,
				parameters: { $count: true },
				sorter: this._sorter ? [this._sorter] : [],
				templateShareable: false,
				template: new ColumnListItem({
					type: info.addressable ? "Navigation" : "Inactive",
					cells: info.columns.map(function (column) {
						// Kennungen sind keine Mengen: keine Tausendertrennzeichen im Schlüssel
						let text = "{" + column.name + "}";
						if (column.key && column.type === "Edm.Int64") {
							text = { path: column.name, type: new Int64({ groupingEnabled: false }) };
						} else if (values.needsFormatter(column)) {
							text = { path: column.name, targetType: "any", formatter: values.text };
						}
						return new Text({ text: text, wrapping: false });
					})
				}),
				events: { dataReceived: this._onDataReceived.bind(this) }
			});
		},

		_onDataReceived: function (event) {
			const error = event.getParameter("error");
			if (error) {
				this._fail(error);
			}
		},

		_fail: function (error) {
			if (this.getOwnerComponent().handleError(error)) {
				return;
			}
			const strip = this.byId("error");
			strip.setText(error.message);
			strip.setVisible(true);
		},

		_refresh: function () {
			const binding = this.byId("table").getBinding("items");
			if (binding) {
				binding.refresh();
			}
		},

		onUpdateFinished: function (event) {
			const total = event.getParameter("total");
			this.byId("title").setText(this._set + (total === undefined ? "" : " (" + total + ")"));
		},

		onRowPress: function (event) {
			if (!this._info.addressable) {
				return;
			}
			const path = event.getParameter("listItem").getBindingContext().getPath();
			const key = path.slice(path.indexOf("(") + 1, -1);
			this.getOwnerComponent().getRouter().navTo("row", { set: this._set, key: key });
		},

		onClose: function () {
			this.getOwnerComponent().getRouter().navTo("home");
		},

		onRefresh: function () {
			this._refresh();
		},

		/** Volltextsuche: Text enthält die Eingabe, Zahlen sind gleich ihr. */
		onSearch: function (event) {
			const query = (event.getParameter("query") || "").trim();
			const filters = [];
			if (query) {
				this._info.columns.forEach(function (column) {
					if (column.type === "Edm.String") {
						filters.push(new Filter(column.name, FilterOperator.Contains, query));
					} else if (column.type === "Edm.Boolean" && (query === "true" || query === "false")) {
						filters.push(new Filter(column.name, FilterOperator.EQ, query === "true"));
					} else if (values.isNumber(column) && this._searchable(column, query)) {
						filters.push(new Filter(column.name, FilterOperator.EQ, query));
					}
				}, this);
			}
			if (query && filters.length === 0) {
				filters.push(new Filter(this._info.columns[0].name, FilterOperator.EQ, null));
			}
			this.byId("table").getBinding("items").filter(filters.length ? new Filter({ filters: filters, and: false }) : []);
		},

		/** Eine Suche darf nie am Typ scheitern, sonst fällt sie für alle Spalten aus. */
		_searchable: function (column, query) {
			try {
				return values.parse(column, query) !== null;
			} catch (e) {
				return false;
			}
		},

		onSort: function () {
			if (this._sortDialog) {
				this._sortDialog.destroy();
			}
			this._sortDialog = new ViewSettingsDialog({
				sortItems: this._info.columns.map(function (column) {
					return new ViewSettingsItem({ text: column.name, key: column.name, selected: !!this._sorter && this._sorter.sPath === column.name });
				}, this),
				sortDescending: !!this._sorter && this._sorter.bDescending,
				confirm: function (event) {
					const item = event.getParameter("sortItem");
					this._sorter = item ? new Sorter(item.getKey(), event.getParameter("sortDescending")) : null;
					this.byId("table").getBinding("items").sort(this._sorter ? [this._sorter] : []);
				}.bind(this)
			});
			this.getView().addDependent(this._sortDialog);
			this._sortDialog.open();
		},

		onAdd: function () {
			const inputs = {};
			const content = [];
			this._info.columns.forEach(function (column) {
				inputs[column.name] = new Input({
					type: values.isNumber(column) ? "Number" : "Text",
					required: column.key,
					placeholder: column.key ? this._text("required") : ""
				});
				content.push(new Label({ text: column.name, required: column.key }), inputs[column.name]);
			}, this);
			const dialog = new Dialog({
				title: this._text("newRow"),
				contentWidth: "28rem",
				content: [
					new Text({ text: this._text("emptyIsNull") }).addStyleClass("sapUiSmallMargin"),
					new SimpleForm({ editable: true, layout: "ColumnLayout", content: content })
				],
				beginButton: new Button({ text: this._text("save"), type: "Emphasized", press: function () {
					this._create(dialog, inputs);
				}.bind(this) }),
				endButton: new Button({ text: this._text("cancel"), press: function () {
					dialog.close();
				} }),
				afterClose: function () {
					dialog.destroy();
				}
			});
			this.getView().addDependent(dialog);
			dialog.open();
		},

		_create: function (dialog, inputs) {
			const data = {};
			let invalid = false;
			this._info.columns.forEach(function (column) {
				const input = inputs[column.name];
				input.setValueState("None");
				try {
					const value = values.parseNew(column, input.getValue());
					if (value !== null) {
						data[column.name] = value;
					} else if (column.key) {
						input.setValueState("Error");
						input.setValueStateText(this._text("required"));
						invalid = true;
					}
				} catch (e) {
					input.setValueState("Error");
					input.setValueStateText(this._text(e.message, [column.name]));
					invalid = true;
				}
			}, this);
			if (invalid) {
				return;
			}
			// Eigene Liste: ein abgelehnter Eintrag bleibt so nicht als Geisterzeile in der Tabelle stehen
			const list = this.getOwnerComponent().getModel().bindList("/" + this._set);
			dialog.setBusy(true);
			Messaging.removeAllMessages();
			list.attachCreateCompleted(function (event) {
				dialog.setBusy(false);
				const context = event.getParameter("context");
				if (event.getParameter("success")) {
					dialog.close();
					MessageToast.show(this._text("rowCreated"));
					this._refresh();
					return;
				}
				const message = Messaging.getMessageModel().getData().slice(-1)[0];
				context.delete().catch(function () {});
				this._dialogError(dialog, message ? message.getMessage() : "");
			}, this);
			list.create(data, true);
		},

		_dialogError: function (dialog, text) {
			dialog.removeContent(this._dialogStrip);
			const strip = this.byId("error").clone();
			strip.setText(text);
			strip.setVisible(true);
			strip.addStyleClass("sapUiSmallMargin");
			this._dialogStrip = strip;
			dialog.insertContent(strip, 0);
		}
	});
});
