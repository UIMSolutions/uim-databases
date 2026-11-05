sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/m/Input",
	"sap/m/Label",
	"sap/m/MessageBox",
	"sap/m/MessageToast",
	"sap/m/Text",
	"sap/ui/model/json/JSONModel",
	"hdb/client/controller/values"
], function (Controller, Input, Label, MessageBox, MessageToast, Text, JSONModel, values) {
	"use strict";

	return Controller.extend("hdb.client.controller.Row", {
		onInit: function () {
			this.getView().setModel(new JSONModel({ title: "", editing: false }), "view");
			const router = this.getOwnerComponent().getRouter();
			router.getRoute("row").attachPatternMatched(function (event) {
				const args = event.getParameter("arguments");
				this._load(args.set, args.key);
			}, this);
		},

		_text: function (key, args) {
			return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(key, args);
		},

		_load: function (set, key) {
			const component = this.getOwnerComponent();
			if (!component.getModel()) { // Neuladen: die Anmeldung läuft noch
				window.setTimeout(this._load.bind(this, set, key), 200);
				return;
			}
			this._set = set;
			this._key = key;
			const view = this.getView().getModel("view");
			view.setData({ title: set + " (" + key + ")", editing: false });
			this.byId("error").setVisible(false);
			component.describeEntitySet(set).then(function (info) {
				this._info = info;
				if (this._binding) {
					this._binding.destroy();
				}
				// Der Schlüssel ist in der Route schon ein fertiges OData-Literal
				this._binding = component.getModel().bindContext("/" + set + "(" + key + ")");
				return this._binding.getBoundContext().requestObject();
			}.bind(this)).then(function (entity) {
				this._entity = entity;
				this._render();
			}.bind(this)).catch(this._fail.bind(this));
		},

		_fail: function (error) {
			if (this.getOwnerComponent().handleError(error)) {
				return;
			}
			const strip = this.byId("error");
			strip.setText(error.message);
			strip.setVisible(true);
		},

		_render: function () {
			const form = this.byId("form");
			const editing = this.getView().getModel("view").getProperty("/editing");
			form.destroyContent();
			this._inputs = {};
			this._info.columns.forEach(function (column) {
				const value = values.text(this._entity[column.name]);
				form.addContent(new Label({ text: column.name, design: column.key ? "Bold" : "Standard" }));
				if (editing && !column.key) {
					this._inputs[column.name] = new Input({ value: value, type: column.type === "Edm.String" ? "Text" : "Number" });
					form.addContent(this._inputs[column.name]);
				} else {
					form.addContent(new Text({ text: value }));
				}
			}, this);
		},

		onEdit: function () {
			this.getView().getModel("view").setProperty("/editing", true);
			this._render();
		},

		onCancel: function () {
			this.getView().getModel("view").setProperty("/editing", false);
			this._render();
		},

		/** Sendet nur geänderte Felder; ohne $batch ist das je Feld ein PATCH. */
		onSave: function () {
			const changes = {};
			let invalid = false;
			this._info.columns.forEach(function (column) {
				const input = this._inputs[column.name];
				if (!input) {
					return;
				}
				input.setValueState("None");
				try {
					const value = values.parse(column, input.getValue());
					const current = this._entity[column.name];
					if (values.text(value) !== values.text(current)) {
						changes[column.name] = value;
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
			const context = this._binding.getBoundContext();
			this.getView().setBusy(true);
			Promise.all(Object.keys(changes).map(function (name) {
				return context.setProperty(name, changes[name]);
			})).then(function () {
				return context.requestObject();
			}).then(function (entity) {
				this._entity = entity;
				this.getView().setBusy(false);
				this.getView().getModel("view").setProperty("/editing", false);
				this._render();
				MessageToast.show(this._text("rowSaved"));
				sap.ui.getCore().getEventBus().publish("hdb", "rowsChanged");
			}.bind(this)).catch(function (error) {
				this.getView().setBusy(false);
				this._fail(error);
			}.bind(this));
		},

		onDelete: function () {
			MessageBox.confirm(this._text("deleteConfirm"), {
				emphasizedAction: MessageBox.Action.CANCEL,
				onClose: function (action) {
					if (action !== MessageBox.Action.OK) {
						return;
					}
					this._binding.getBoundContext().delete().then(function () {
						MessageToast.show(this._text("rowDeleted"));
						sap.ui.getCore().getEventBus().publish("hdb", "rowsChanged");
						this.onClose();
					}.bind(this)).catch(this._fail.bind(this));
				}.bind(this)
			});
		},

		onClose: function () {
			this.getOwnerComponent().getRouter().navTo("table", { set: this._set });
		}
	});
});
