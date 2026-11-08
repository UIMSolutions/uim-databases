sap.ui.define(["sap/ui/core/mvc/Controller"], function (Controller) {
	"use strict";

	return Controller.extend("hdb.client.controller.Login", {
		onLogin: function () {
			const component = this.getOwnerComponent();
			const app = component.getModel("app");
			const bundle = component.getModel("i18n").getResourceBundle();
			const password = this.byId("password");
			app.setProperty("/busy", true);
			app.setProperty("/loginError", "");
			component.login(this.byId("user").getValue(), password.getValue(), app.getProperty("/tenant")).then(function () {
				password.setValue("");
			}).catch(function (error) {
				app.setProperty("/busy", false);
				app.setProperty("/loginError", error.message || bundle.getText("loginFailed"));
				password.setValue("");
			});
		}
	});
});
