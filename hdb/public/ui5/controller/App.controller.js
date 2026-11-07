sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/m/ActionSheet",
	"sap/m/Button"
], function (Controller, ActionSheet, Button) {
	"use strict";

	return Controller.extend("hdb.client.controller.App", {
		onInit: function () {
			const component = this.getOwnerComponent();
			this.getView().addStyleClass(component.getContentDensityClass ? component.getContentDensityClass() : "sapUiSizeCompact");
			Promise.all(["login", "tables", "rows", "row", "backups", "statistics", "help"].map(function (id) {
				return this.byId(id).loaded();
			}, this)).then(component.viewsLoaded);
			const router = component.getRouter();
			const app = component.getModel("app");
			router.getRoute("home").attachPatternMatched(function () {
				app.setProperty("/layout", "OneColumn");
			});
			router.attachRouteMatched(function (event) {
				const route = event.getParameter("name");
				app.setProperty("/navKey", route === "table" || route === "row" ? "home" : route);
			});
			const showMid = function (id, layout) {
				this.byId("fcl").toMidColumnPage(this.byId(id).getId());
				app.setProperty("/layout", layout);
			}.bind(this);
			router.getRoute("table").attachPatternMatched(showMid.bind(null, "rows", "TwoColumnsMidExpanded"));
			router.getRoute("row").attachPatternMatched(showMid.bind(null, "rows", "ThreeColumnsMidExpanded"));
			router.getRoute("backups").attachPatternMatched(showMid.bind(null, "backups", "MidColumnFullScreen"));
			router.getRoute("statistics").attachPatternMatched(showMid.bind(null, "statistics", "MidColumnFullScreen"));
			router.getRoute("help").attachPatternMatched(showMid.bind(null, "help", "MidColumnFullScreen"));
		},

		initials: function (name) {
			return (name || "?").slice(0, 2).toUpperCase();
		},

		onToggleSideNav: function () {
			this.byId("toolPage").toggleSideContentMode();
		},

		/** Die Schlüssel der Navigationseinträge sind Routennamen. */
		onSideNavSelect: function (event) {
			this.getOwnerComponent().getRouter().navTo(event.getParameter("item").getKey());
		},

		onProfile: function (event) {
			const component = this.getOwnerComponent();
			const bundle = component.getModel("i18n").getResourceBundle();
			const app = component.getModel("app");
			const avatar = event.getParameter("avatar");
			const current = component.getLanguages().find(function (language) {
				return language.key === component.getLanguage();
			});
			this._openSheet(app.getProperty("/user") + " (" + app.getProperty("/role") + ")", avatar, [
				new Button({ text: bundle.getText("backups"), icon: "sap-icon://product", visible: app.getProperty("/isAdmin"), press: function () {
					component.getRouter().navTo("backups");
				} }),
				new Button({ text: bundle.getText("adminConsole"), icon: "sap-icon://action-settings", press: function () {
					window.location.href = "/admin";
				} }),
				new Button({ text: bundle.getText("languageCurrent", [current.name]), icon: "sap-icon://world", press: function () {
					// Ein zweites Blatt öffnet sich erst, wenn das erste zu ist
					this._menu.attachEventOnce("afterClose", this._openLanguages.bind(this, avatar));
				}.bind(this) }),
				new Button({ text: bundle.getText("signOut"), icon: "sap-icon://log", press: function () {
					component.endSession();
				} })
			]);
		},

		_openLanguages: function (avatar) {
			const component = this.getOwnerComponent();
			const current = component.getLanguage();
			this._openSheet(component.getModel("i18n").getResourceBundle().getText("language"), avatar, component.getLanguages().map(function (language) {
				return new Button({
					text: language.name,
					icon: language.key === current ? "sap-icon://accept" : "",
					press: function () {
						if (language.key !== current) {
							component.setLanguage(language.key);
						}
					}
				});
			}));
		},

		_openSheet: function (title, opener, buttons) {
			if (this._menu) {
				this._menu.destroy();
			}
			this._menu = new ActionSheet({ title: title, placement: "Bottom", buttons: buttons });
			this.getView().addDependent(this._menu);
			this._menu.openBy(opener);
		}
	});
});
