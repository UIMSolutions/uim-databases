sap.ui.define([
	"sap/ui/core/UIComponent",
	"sap/ui/model/json/JSONModel",
	"sap/ui/model/odata/v4/ODataModel"
], function (UIComponent, JSONModel, ODataModel) {
	"use strict";

	const TOKEN_KEY = "hdb.token";

	return UIComponent.extend("hdb.client.Component", {
		metadata: {
			manifest: "json",
			interfaces: ["sap.ui.core.IAsyncContentCreation"]
		},

		init: function () {
			UIComponent.prototype.init.apply(this, arguments);
			this.setModel(new JSONModel({
				authenticated: false, busy: true, user: "", role: "", canWrite: false,
				layout: "OneColumn", sets: [], loginError: ""
			}), "app");
			this.getRouter().initialize();
			this._restoreSession();
		},

		/** Ein Token aus dieser Browser-Sitzung kann abgelaufen sein: /auth/me entscheidet. */
		_restoreSession: function () {
			let token = null;
			try {
				token = window.sessionStorage.getItem(TOKEN_KEY);
			} catch (e) { /* gesperrter Speicher: dann eben neu anmelden */ }
			if (!token) {
				this.getModel("app").setProperty("/busy", false);
				return;
			}
			this._startSession(token).catch(function () {
				this.endSession();
			}.bind(this));
		},

		login: function (user, password) {
			return fetch("/api/v1/auth/login", {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify({ user: user, password: password })
			}).then(function (response) {
				return response.json().then(function (body) {
					if (!response.ok) {
						throw new Error(body.statusMessage || response.statusText);
					}
					return this._startSession(body.token);
				}.bind(this));
			}.bind(this));
		},

		/**
		 * groupId $direct: der Server kennt kein $batch, jede Anfrage geht einzeln.
		 * Das ODataModel entsteht erst hier, weil schon $metadata das Token braucht.
		 */
		_startSession: function (token) {
			const app = this.getModel("app");
			return fetch("/api/v1/auth/me", { headers: { Authorization: "Bearer " + token } }).then(function (response) {
				if (!response.ok) {
					throw new Error(response.statusText);
				}
				return response.json();
			}).then(function (me) {
				this._token = token;
				try {
					window.sessionStorage.setItem(TOKEN_KEY, token);
				} catch (e) { /* die Sitzung gilt dann nur bis zum Neuladen */ }
				this.setModel(new ODataModel({
					serviceUrl: "/odata/v4/",
					groupId: "$direct",
					updateGroupId: "$direct",
					operationMode: "Server",
					httpHeaders: { Authorization: "Bearer " + token }
				}));
				app.setData(Object.assign(app.getData(), {
					authenticated: true, busy: false, user: me.name, role: me.role,
					canWrite: me.role !== "viewer", loginError: ""
				}));
				return this.loadEntitySets();
			}.bind(this));
		},

		/** Entity Sets und ihre Spalten kommen aus $metadata: neue Tabellen brauchen keine Änderung am Client. */
		loadEntitySets: function () {
			const meta = this.getModel().getMetaModel();
			return meta.requestObject("/").then(function (container) {
				const sets = Object.keys(container).filter(function (name) {
					return container[name].$kind === "EntitySet";
				}).sort().map(function (name) {
					return { name: name };
				});
				this.getModel("app").setProperty("/sets", sets);
			}.bind(this));
		},

		/** Spalten einer Tabelle; __rowid ist nur eine Position und wird nicht angezeigt. */
		describeEntitySet: function (set) {
			const meta = this.getModel().getMetaModel();
			return meta.requestObject("/" + set + "/").then(function (type) {
				if (!type) {
					throw new Error("Unknown table: " + set);
				}
				const key = type.$Key[0];
				const columns = Object.keys(type).filter(function (name) {
					return type[name].$kind === "Property" && name !== "__rowid";
				}).map(function (name) {
					return { name: name, type: type[name].$Type, key: name === key };
				});
				return { columns: columns, addressable: key !== "__rowid" };
			});
		},

		endSession: function (message) {
			const token = this._token;
			if (token) {
				fetch("/api/v1/auth/logout", { method: "POST", headers: { Authorization: "Bearer " + token } }).catch(function () {});
			}
			this._token = null;
			try {
				window.sessionStorage.removeItem(TOKEN_KEY);
			} catch (e) { /* nichts zu löschen */ }
			const old = this.getModel();
			this.setModel(null);
			if (old) {
				old.destroy();
			}
			const app = this.getModel("app");
			app.setData(Object.assign(app.getData(), {
				authenticated: false, busy: false, user: "", role: "", canWrite: false,
				layout: "OneColumn", sets: [], loginError: message || ""
			}));
			this.getRouter().navTo("home");
		},

		/** Fehler aus Anfragen: eine abgelaufene Sitzung führt zurück zur Anmeldung. */
		handleError: function (error, fallback) {
			if (error && error.status === 401) {
				this.endSession(this.getModel("i18n").getResourceBundle().getText("sessionExpired"));
				return true;
			}
			return false;
		}
	});
});
