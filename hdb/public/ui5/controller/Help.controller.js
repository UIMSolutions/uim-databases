sap.ui.define(["sap/ui/core/mvc/Controller"], function (Controller) {
	"use strict";

	return Controller.extend("hdb.client.controller.Help", {
		onClose: function () {
			this.getOwnerComponent().getRouter().navTo("home");
		}
	});
});
