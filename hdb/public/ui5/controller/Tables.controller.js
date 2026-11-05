sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/ui/model/Filter",
	"sap/ui/model/FilterOperator"
], function (Controller, Filter, FilterOperator) {
	"use strict";

	return Controller.extend("hdb.client.controller.Tables", {
		onInit: function () {
			const router = this.getOwnerComponent().getRouter();
			router.getRoute("home").attachPatternMatched(function () {
				this.byId("list").removeSelections(true);
			}, this);
		},

		onFilter: function (event) {
			const query = event.getParameter("newValue");
			this.byId("list").getBinding("items").filter(query ? [new Filter("name", FilterOperator.Contains, query)] : []);
		},

		onSelect: function (event) {
			const item = event.getParameter("listItem");
			this.getOwnerComponent().getRouter().navTo("table", { set: item.getBindingContext("app").getProperty("name") });
		},

		/** $metadata ist im Modell gecacht: neue Tabellen erscheinen erst mit neu geladenen Metadaten. */
		onRefresh: function () {
			window.location.reload();
		}
	});
});
