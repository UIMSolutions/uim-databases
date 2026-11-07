sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/m/Button",
	"sap/m/Dialog",
	"sap/m/Input",
	"sap/m/Label",
	"sap/m/MessageBox",
	"sap/m/MessageToast",
	"sap/m/StepInput",
	"sap/m/Switch",
	"sap/m/Text",
	"sap/ui/layout/form/SimpleForm",
	"sap/ui/model/json/JSONModel",
	"hdb/client/controller/values"
], function (Controller, Button, Dialog, Input, Label, MessageBox, MessageToast, StepInput, Switch, Text, SimpleForm, JSONModel, values) {
	"use strict";

	/** Sicherungen laufen über die REST-API: sie sind Dateien und Vorgänge, keine OData-Entitäten. */
	return Controller.extend("hdb.client.controller.Backups", {
		onInit: function () {
			this.getView().setModel(new JSONModel({ items: [], busy: false }), "view");
			this.getOwnerComponent().getRouter().getRoute("backups").attachPatternMatched(this._load, this);
		},

		_text: function (key, args) {
			return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(key, args);
		},

		_api: function (url, options) {
			return this.getOwnerComponent().authFetch(url, options);
		},

		_load: function () {
			const view = this.getView().getModel("view");
			view.setProperty("/busy", true);
			this.byId("error").setVisible(false);
			return Promise.all([this._api("/api/v1/backups"), this._api("/api/v1/backups/schedule")]).then(function (responses) {
				return Promise.all(responses.map(function (response) {
					return response.json();
				}));
			}).then(function (results) {
				view.setProperty("/items", results[0]);
				this._showSchedule(results[1]);
				view.setProperty("/busy", false);
			}.bind(this)).catch(this._fail.bind(this));
		},

		_showSchedule: function (schedule) {
			const view = this.getView().getModel("view");
			view.setProperty("/schedule", schedule);
			view.setProperty("/scheduleError", schedule.lastError ? this._text("scheduleFailed", [schedule.lastError]) : "");
			let text = this._text("scheduleOff");
			if (schedule.enabled) {
				text = this._text("scheduleOn", [schedule.intervalHours, schedule.keepScheduled]);
				if (schedule.nextRun) {
					text += " " + this._text("scheduleNext", [schedule.nextRun]);
				}
			}
			view.setProperty("/scheduleText", text);
		},

		formatKind: function (kind) {
			return this._text("kind_" + kind);
		},

		onSchedule: function () {
			const schedule = this.getView().getModel("view").getProperty("/schedule");
			const enabled = new Switch({ state: schedule.enabled });
			const field = function (value, max) {
				return new StepInput({ value: value, min: 1, max: max, width: "10rem" });
			};
			const interval = field(schedule.intervalHours, 8760);
			const keepScheduled = field(schedule.keepScheduled, 1000);
			const keepSafety = field(schedule.keepSafety, 1000);
			const dialog = new Dialog({
				title: this._text("schedule"),
				contentWidth: "30rem",
				content: [
					new SimpleForm({ editable: true, layout: "ColumnLayout", content: [
						new Label({ text: this._text("scheduleEnabled") }), enabled,
						new Label({ text: this._text("scheduleInterval") }), interval,
						new Label({ text: this._text("scheduleKeep") }), keepScheduled,
						new Label({ text: this._text("scheduleKeepSafety") }), keepSafety
					] }),
					new Text({ text: this._text("scheduleHint") }).addStyleClass("sapUiSmallMargin")
				],
				beginButton: new Button({ text: this._text("save"), type: "Emphasized", press: function () {
					dialog.setBusy(true);
					this._api("/api/v1/backups/schedule", {
						method: "PUT",
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify({
							enabled: enabled.getState(), intervalHours: interval.getValue(),
							keepScheduled: keepScheduled.getValue(), keepSafety: keepSafety.getValue()
						})
					}).then(function () {
						dialog.close();
						MessageToast.show(this._text("scheduleSaved"));
						return this._load();
					}.bind(this)).catch(function (error) {
						dialog.close();
						this._fail(error);
					}.bind(this));
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

		_fail: function (error) {
			this.getView().getModel("view").setProperty("/busy", false);
			if (this.getOwnerComponent().handleError(error)) {
				return;
			}
			const strip = this.byId("error");
			strip.setText(error.message);
			strip.setVisible(true);
		},

		_backupOf: function (event) {
			return event.getSource().getBindingContext("view").getObject();
		},

		formatSize: values.size,

		onRefresh: function () {
			this._load();
		},

		onClose: function () {
			this.getOwnerComponent().getRouter().navTo("home");
		},

		onCreate: function () {
			const label = new Input({ placeholder: this._text("backupLabel"), maxLength: 40 });
			const dialog = new Dialog({
				title: this._text("createBackup"),
				contentWidth: "24rem",
				content: [label.addStyleClass("sapUiSmallMargin")],
				beginButton: new Button({ text: this._text("createBackup"), type: "Emphasized", press: function () {
					dialog.setBusy(true);
					this._api("/api/v1/backups", {
						method: "POST",
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify({ label: label.getValue() })
					}).then(function () {
						dialog.close();
						MessageToast.show(this._text("backupCreatedToast"));
						return this._load();
					}.bind(this)).catch(function (error) {
						dialog.close();
						this._fail(error);
					}.bind(this));
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

		onUpload: function () {
			const input = document.createElement("input");
			input.type = "file";
			input.accept = ".hdbbak";
			input.addEventListener("change", function () {
				if (!input.files.length) {
					return;
				}
				this.getView().getModel("view").setProperty("/busy", true);
				this._api("/api/v1/backups/import", {
					method: "POST",
					headers: { "Content-Type": "application/octet-stream" },
					body: input.files[0]
				}).then(function () {
					MessageToast.show(this._text("backupUploaded"));
					return this._load();
				}.bind(this)).catch(this._fail.bind(this));
			}.bind(this));
			input.click();
		},

		/** Ein Link kann das Token nicht mitsenden: die Datei kommt per fetch und wird lokal angeboten. */
		onDownload: function (event) {
			const name = this._backupOf(event).name;
			this._api("/api/v1/backups/" + encodeURIComponent(name) + "/content").then(function (response) {
				return response.blob();
			}).then(function (blob) {
				const url = URL.createObjectURL(blob);
				const link = document.createElement("a");
				link.href = url;
				link.download = name;
				document.body.appendChild(link);
				link.click();
				link.remove();
				URL.revokeObjectURL(url);
			}).catch(this._fail.bind(this));
		},

		onRestore: function (event) {
			const name = this._backupOf(event).name;
			MessageBox.warning(this._text("restoreConfirm"), {
				actions: [this._text("restore"), MessageBox.Action.CANCEL],
				emphasizedAction: MessageBox.Action.CANCEL,
				onClose: function (action) {
					if (action !== this._text("restore")) {
						return;
					}
					this.getView().getModel("view").setProperty("/busy", true);
					this._api("/api/v1/backups/" + encodeURIComponent(name) + "/restore", { method: "POST" }).then(function (response) {
						return response.json();
					}).then(function (result) {
						// Tabellen können andere sein als zuvor: $metadata und alle Listen müssen neu geladen werden
						MessageBox.success(this._text("restoreDone", [result.safetyBackup.name]), {
							onClose: function () {
								window.location.reload();
							}
						});
					}.bind(this)).catch(this._fail.bind(this));
				}.bind(this)
			});
		},

		onDelete: function (event) {
			const name = this._backupOf(event).name;
			MessageBox.confirm(this._text("backupDeleteConfirm"), {
				emphasizedAction: MessageBox.Action.CANCEL,
				onClose: function (action) {
					if (action !== MessageBox.Action.OK) {
						return;
					}
					this._api("/api/v1/backups/" + encodeURIComponent(name), { method: "DELETE" }).then(function () {
						MessageToast.show(this._text("backupDeleted"));
						return this._load();
					}.bind(this)).catch(this._fail.bind(this));
				}.bind(this)
			});
		}
	});
});
