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
			const router = component.getRouter();
			const app = component.getModel("app");
			router.getRoute("home").attachPatternMatched(function () {
				app.setProperty("/layout", "OneColumn");
			});
			router.getRoute("table").attachPatternMatched(function () {
				app.setProperty("/layout", "TwoColumnsMidExpanded");
			});
			router.getRoute("row").attachPatternMatched(function () {
				app.setProperty("/layout", "ThreeColumnsMidExpanded");
			});
		},

		initials: function (name) {
			return (name || "?").slice(0, 2).toUpperCase();
		},

		onHome: function () {
			this.getOwnerComponent().getRouter().navTo("home");
		},

		onProfile: function (event) {
			const component = this.getOwnerComponent();
			const bundle = component.getModel("i18n").getResourceBundle();
			const app = component.getModel("app");
			if (this._menu) {
				this._menu.destroy();
			}
			this._menu = new ActionSheet({
				title: app.getProperty("/user") + " (" + app.getProperty("/role") + ")",
				placement: "Bottom",
				buttons: [
					new Button({ text: bundle.getText("adminConsole"), icon: "sap-icon://action-settings", press: function () {
						window.location.href = "/admin";
					} }),
					new Button({ text: bundle.getText("signOut"), icon: "sap-icon://log", press: function () {
						component.endSession();
					} })
				]
			});
			this.getView().addDependent(this._menu);
			this._menu.openBy(event.getParameter("avatar"));
		}
	});
});
