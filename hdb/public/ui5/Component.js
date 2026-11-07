sap.ui.define([
	"sap/base/i18n/Localization",
	"sap/ui/core/UIComponent",
	"sap/ui/model/json/JSONModel",
	"sap/ui/model/odata/v4/ODataModel"
], function (Localization, UIComponent, JSONModel, ODataModel) {
	"use strict";

	const TOKEN_KEY = "hdb.token";
	const LANGUAGE_KEY = "hdb.language";
	const LANGUAGES = [{ key: "en", name: "English" }, { key: "de", name: "Deutsch" }];

	return UIComponent.extend("hdb.client.Component", {
		metadata: {
			manifest: "json",
			interfaces: ["sap.ui.core.IAsyncContentCreation"]
		},

		init: function () {
			UIComponent.prototype.init.apply(this, arguments);
			this.setModel(new JSONModel({
				authenticated: false, busy: true, user: "", role: "", canWrite: false, isAdmin: false,
				layout: "OneColumn", navKey: "home", sets: [], loginError: ""
			}), "app");
			this._viewsReady = new Promise(function (resolve) {
				this.viewsLoaded = resolve;
			}.bind(this));
			this._restoreSession();
		},

		getLanguages: function () {
			return LANGUAGES;
		},

		/** Sprachen ohne Übersetzung fallen auf die Grundtexte zurück, und die sind Englisch. */
		getLanguage: function () {
			const current = Localization.getLanguage().split(/[-_]/)[0];
			return LANGUAGES.some(function (language) { return language.key === current; }) ? current : "en";
		},

		/**
		 * index.html liest die Wahl vor dem Start von UI5. Neu laden, weil im Code gebaute Texte und die Texte der
		 * UI5-Controls sonst in der alten Sprache blieben.
		 * Token und Hash überstehen das. Ohne Speicher ginge beides verloren: dann nur die Modelle umstellen.
		 */
		setLanguage: function (key) {
			try {
				window.localStorage.setItem(LANGUAGE_KEY, key);
			} catch (e) {
				Localization.setLanguage(key);
				return;
			}
			window.location.reload();
		},

		/**
		 * Der Router startet erst mit den Spalten-Views und einem Modell: sonst ginge das erste Routenereignis
		 * eines Deep Links verloren, oder ein Controller bekäme eine Route, bevor er Daten lesen kann.
		 */
		_startRouting: function () {
			return this._viewsReady.then(function () {
				this.getRouter().initialize();
			}.bind(this));
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
					canWrite: me.role !== "viewer", isAdmin: me.role === "admin", loginError: ""
				}));
				return this.loadEntitySets();
			}.bind(this)).then(this._startRouting.bind(this));
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
				authenticated: false, busy: false, user: "", role: "", canWrite: false, isAdmin: false,
				layout: "OneColumn", navKey: "home", sets: [], loginError: message || ""
			}));
			sap.ui.getCore().getEventBus().publish("hdb", "sessionEnded");
			this.getRouter().stop();
			this.getRouter().getHashChanger().setHash("");
		},

		/** Anfragen an die REST-API mit Token; Fehler tragen Status und Meldung des Servers. */
		authFetch: function (url, options) {
			const settings = Object.assign({}, options);
			settings.headers = Object.assign({ Authorization: "Bearer " + this._token }, settings.headers);
			return fetch(url, settings).then(function (response) {
				if (response.ok) {
					return response;
				}
				return response.json().catch(function () {
					return {};
				}).then(function (body) {
					const error = new Error(body.statusMessage || response.statusText);
					error.status = response.status;
					throw error;
				});
			});
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
